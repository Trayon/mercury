/*
INIT mercury_sys_init_engine
ENDINIT
*/
/*
** Copyright (C) 1993-2000 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

#include	"mercury_imp.h"

#include	<stdio.h>
#include 	<string.h>
#include	<setjmp.h>

#include	"mercury_engine.h"
#include	"mercury_memory_zones.h"	/* for create_zone() */
#include	"mercury_memory_handlers.h"	/* for default_handler() */

#include	"mercury_dummy.h"

#ifdef USE_GCC_NONLOCAL_GOTOS

#define LOCALS_SIZE	10024	/* amount of space to reserve for local vars */
#define MAGIC_MARKER	187	/* a random character */
#define MAGIC_MARKER_2	142	/* another random character */

#endif

static	void	call_engine_inner(MR_Code *entry_point) NO_RETURN;

#ifndef USE_GCC_NONLOCAL_GOTOS
  static MR_Code	*engine_done(void);
  static MR_Code	*engine_init_registers(void);
#endif

bool	MR_debugflag[MR_MAXFLAG];

#ifndef MR_THREAD_SAFE
  MercuryEngine	MR_engine_base;
#endif

/*---------------------------------------------------------------------------*/

/*
** init_engine() calls init_memory() which sets up all the necessary
** stuff for allocating memory-zones and other runtime areas (such as
** the zone structures and context structures).
*/
void 
init_engine(MercuryEngine *eng)
{
	/*
	** First, ensure that the truly global stuff has been initialized
	** (if it was already initialized, this does nothing).
	*/

	init_memory();

#ifndef USE_GCC_NONLOCAL_GOTOS
	{
		static bool made_engine_done_label = FALSE;
		if (!made_engine_done_label) {
			make_label("engine_done", LABEL(engine_done),
				engine_done);
			made_engine_done_label = TRUE;
		}
	}
#endif

	/*
	** Second, initialize the per-engine (i.e. normally per Posix thread)
	** stuff.
	*/

#ifndef	CONSERVATIVE_GC
	eng->heap_zone = create_zone("heap", 1, heap_size, next_offset(),
			heap_zone_size, default_handler);
	eng->e_hp = eng->heap_zone->min;

#ifdef	NATIVE_GC
	eng->heap_zone2 = create_zone("heap2", 1, heap_size, next_offset(),
			heap_zone_size, default_handler);

  #ifdef MR_DEBUG_AGC_PRINT_VARS
	eng->debug_heap_zone = create_zone("debug_heap", 1, debug_heap_size,
			next_offset(), debug_heap_zone_size, default_handler);
  #endif
#endif

	eng->solutions_heap_zone = create_zone("solutions_heap", 1,
			solutions_heap_size, next_offset(),
			solutions_heap_zone_size, default_handler);
	eng->e_sol_hp = eng->solutions_heap_zone->min;

	eng->global_heap_zone = create_zone("global_heap", 1,
			global_heap_size, next_offset(),
			global_heap_zone_size, default_handler);
	eng->e_global_hp = eng->global_heap_zone->min;
#endif

#ifdef MR_LOWLEVEL_DEBUG
	/*
	** Create the dumpstack, used for debugging stack traces.
	** Note that we can just make the dumpstack the same size as
	** the detstack and we never have to worry about the dumpstack
	** overflowing.
	*/
	dumpstack_zone = create_zone("dumpstack", 1, detstack_size,
		next_offset(), detstack_zone_size, default_handler);
#endif

#ifdef	MR_THREAD_SAFE
	eng->owner_thread = pthread_self();
	eng->c_depth = 0;
	eng->saved_owners = NULL;
#endif

	/*
	** Finally, allocate an initialize context (Mercury thread)
	** in the engine and initialize the per-context stuff.
	*/
	eng->this_context = create_context();
}

/*---------------------------------------------------------------------------*/

void finalize_engine(MercuryEngine *eng)
{
	/*
	** XXX there are lots of other resources in MercuryEngine that
	** might need to be finalized.  
	*/
	destroy_context(eng->this_context);
}

/*---------------------------------------------------------------------------*/

MercuryEngine *
create_engine(void)
{
	MercuryEngine *eng;

	/*
	** We need to use MR_GC_NEW_UNCOLLECTABLE() here,
	** rather than MR_GC_NEW(), since the engine pointer
	** will normally be stored in thread-local storage, which is
	** not traced by the conservative garbage collector.
	*/
	eng = MR_GC_NEW_UNCOLLECTABLE(MercuryEngine);
	init_engine(eng);
	return eng;
}

void
destroy_engine(MercuryEngine *eng)
{
	finalize_engine(eng);
	MR_GC_free(eng);
}

/*---------------------------------------------------------------------------*/

/*
** MR_Word *
** MR_call_engine(MR_Code *entry_point, bool catch_exceptions)
**
**	This routine calls a Mercury routine from C.
**
**	The called routine should be det/semidet/cc_multi/cc_nondet.
**
**	If the called routine returns normally (this includes the case of a
**	semidet/cc_nondet routine failing, i.e. returning with r1 = FALSE),
**	then MR_call_engine() will return NULL.
**
**	If the called routine exits by throwing an exception, then the
**	behaviour depends on the `catch_exceptions' flag.
**	if `catch_exceptions' is true, then MR_call_engine() will return the
**	Mercury exception object thrown.  If `catch_exceptions' is false,
**	then MR_call_engine() will not return; instead, the code for `throw'
**	will unwind the stacks (including the C stack) back to the nearest
**	enclosing exception handler.
**
**	The virtual machine registers must be set up correctly before the call
**	to MR_call_engine().  Specifically, the non-transient real registers
**	must have valid values, and the fake_reg copies of the transient
**	(register window) registers must have valid values; call_engine()
**	will call restore_transient_registers() and will then assume that
**	all the registers have been correctly set up.
**
**	call_engine() will call save_registers() before returning.
**	That will copy the real registers we use to the fake_reg array.
**
**	Beware, however, that if you are planning to return to C code
**	that did not #include "mercury_regs.h" (directly or via e.g. "mercury_imp.h"),
**	and you have fiddled with the Mercury registers or invoked
**	call_engine() or anything like that, then you will need to
**	save the real registers that C is using before modifying the
**	Mercury registers and then restore them afterwards.
**
**	The called routine may invoke C functions; currently this
**	is done by just invoking them directly, although that will
**	have to change if we start using the caller-save registers.
**
**	The called routine may invoke C functions which in turn
**	invoke call_engine() to invoke invoke Mercury routines (which
**	in turn invoke C functions which ... etc. ad infinitum.)
**
**	call_engine() calls setjmp() and then invokes call_engine_inner()
**	which does the real work.  call_engine_inner() exits by calling
**	longjmp() to return to call_engine().  There are two 
**	different implementations of call_engine_inner(), one for gcc,
**	and another portable version that works on standard ANSI C compilers.
*/

MR_Word *
MR_call_engine(MR_Code *entry_point, bool catch_exceptions)
{

	jmp_buf		curr_jmp_buf;
	jmp_buf		* volatile prev_jmp_buf;
#if defined(PROFILE_TIME)
	MR_Code		* volatile prev_proc;
#endif

	/*
	** Preserve the value of MR_ENGINE(e_jmp_buf) on the C stack.
	** This is so "C calls Mercury which calls C which calls Mercury" etc.
	** will work.
	*/

	restore_transient_registers();

	prev_jmp_buf = MR_ENGINE(e_jmp_buf);
	MR_ENGINE(e_jmp_buf) = &curr_jmp_buf;

	/*
	** Create an exception handler frame on the nondet stack
	** so that we can catch and return Mercury exceptions.
	*/
	if (catch_exceptions) {
		MR_create_exception_handler("call_engine",
			MR_C_LONGJMP_HANDLER, 0, ENTRY(do_fail));
	}

	/*
	** Mark this as the spot to return to.
	*/

#ifdef	MR_DEBUG_JMPBUFS
	printf("engine setjmp %p\n", curr_jmp_buf);
#endif

	if (setjmp(curr_jmp_buf)) {
		MR_Word	* this_frame;
		MR_Word	* exception;

#ifdef	MR_DEBUG_JMPBUFS
		printf("engine caught jmp %p %p\n",
			prev_jmp_buf, MR_ENGINE(e_jmp_buf));
#endif

		debugmsg0("...caught longjmp\n");
		/*
		** On return,
		** set MR_prof_current_proc to be the caller proc again
		** (if time profiling is enabled),
		** restore the registers (since longjmp may clobber them),
		** and restore the saved value of MR_ENGINE(e_jmp_buf).
		*/
		update_prof_current_proc(prev_proc);
		restore_registers();
		MR_ENGINE(e_jmp_buf) = prev_jmp_buf;
		if (catch_exceptions) {
			/*
			** Figure out whether or not we got an exception.
			** If we got an exception, then all of the necessary
			** cleanup such as stack unwinding has already been
			** done, so all we have to do here is to return the
			** exception.
			*/
			exception = MR_ENGINE(e_exception);
			if (exception != NULL) {
				return exception;
			}
			/*
			** If we added an exception hander, but we didn't
			** get an exception, then we need to remove the
			** exception handler frames from the nondet stack
			** and prune the trail ticket allocated by
			** MR_create_exception_handler().
			*/
			this_frame = MR_curfr;
			MR_maxfr = MR_prevfr_slot(this_frame);
			MR_curfr = MR_succfr_slot(this_frame);
#ifdef MR_USE_TRAIL
			MR_prune_ticket();
#endif
		}
		return NULL;
	}


  	MR_ENGINE(e_jmp_buf) = &curr_jmp_buf;
  
	/*
	** If call profiling is enabled, and this is a case of
	** Mercury calling C code which then calls Mercury,
	** then we record the Mercury caller / Mercury callee pair
	** in the table of call counts, if possible.
	*/
#ifdef PROFILE_CALLS
  #ifdef PROFILE_TIME
	if (MR_prof_current_proc != NULL) {
		PROFILE(entry_point, MR_prof_current_proc);
	}
  #else
	/*
	** XXX There's not much we can do in this case
	** to keep the call counts accurate, since
	** we don't know who the caller is.
	*/ 
  #endif
#endif /* PROFILE_CALLS */

	/*
	** If time profiling is enabled, then we need to
	** save MR_prof_current_proc so that we can restore it
	** when we return.  We must then set MR_prof_current_proc
	** to the procedure that we are about to call.
	**
	** We do this last thing before calling call_engine_inner(),
	** since we want to credit as much as possible of the time
	** in C code to the caller, not to the callee.
	** Note that setting and restoring MR_prof_current_proc
	** here in call_engine() means that time in call_engine_inner()
	** unfortunately gets credited to the callee.
	** That is not ideal, but we can't move this code into
	** call_engine_inner() since call_engine_inner() can't
	** have any local variables and this code needs the
	** `prev_proc' local variable.
	*/
#ifdef PROFILE_TIME
	prev_proc = MR_prof_current_proc;
	set_prof_current_proc(entry_point);
#endif

	call_engine_inner(entry_point);
}

#ifdef USE_GCC_NONLOCAL_GOTOS

/* The gcc-specific version */

static void 
call_engine_inner(MR_Code *entry_point)
{
	/*
	** Allocate some space for local variables in other
	** procedures. This is done because we may jump into the middle
	** of a C function, which may assume that space on the stack
	** has already beened allocated for its variables. Such space
	** would generally be used for expression temporary variables.
	** How did we arrive at the correct value of LOCALS_SIZE?
	** Good question. I think it's more voodoo than science.
	**
	** This used to be done by just calling
	** alloca(LOCALS_SIZE), but on the mips that just decrements the
	** stack pointer, whereas local variables are referenced
	** via the frame pointer, so it didn't work.
	** This technique should work and should be vaguely portable,
	** just so long as local variables and temporaries are allocated in
	** the same way in every function.
	**
	** WARNING!
	** Do not add local variables to call_engine_inner that you expect
	** to remain live across Mercury execution - Mercury execution will
	** scribble on the stack frame for this function.
	*/

	unsigned char locals[LOCALS_SIZE];
{

#ifdef MR_LOWLEVEL_DEBUG
{
	/* ensure that we only make the label once */
	static	bool	initialized = FALSE;

	if (!initialized)
	{
		make_label("engine_done", LABEL(engine_done), engine_done);
		initialized = TRUE;
	}
}
#endif

	/*
	** restore any registers that get clobbered by the C function
	** call mechanism
	*/

	restore_transient_registers();

	/*
	** We save the address of the locals in a global pointer to make
	** sure that gcc can't optimize them away.
	*/

	global_pointer = locals;

#ifdef MR_LOWLEVEL_DEBUG
	memset((void *)locals, MAGIC_MARKER, LOCALS_SIZE);
#endif
	debugmsg1("in `call_engine_inner', locals at %p\n", (void *)locals);

	/*
	** We need to ensure that there is at least one
	** real function call in call_engine_inner(), because
	** otherwise gcc thinks that it doesn't need to
	** restore the caller-save registers (such as
	** the return address!) because it thinks call_engine_inner() is
	** a leaf routine which doesn't call anything else,
	** and so it thinks that they won't have been clobbered.
	**
	** This probably isn't necessary now that we exit from this function
	** using longjmp(), but it doesn't do much harm, so I'm leaving it in.
	**
	** Also for gcc versions >= egcs1.1, we need to ensure that
	** there is at least one jump to an unknown label.
	*/
	goto *dummy_identify_function(&&dummy_label);
dummy_label:

	/*
	** Increment the number of times we've entered this
	** engine from C, and mark the current context as being
	** owned by this thread.
	*/
#ifdef	MR_THREAD_SAFE
	MR_ENGINE(c_depth)++;
{
	MercuryThreadList *new_element;

	new_element = MR_GC_NEW(MercuryThreadList);
	new_element->thread = MR_ENGINE(this_context)->owner_thread;
	new_element->next = MR_ENGINE(saved_owners);
	MR_ENGINE(saved_owners) = new_element;
}

	MR_ENGINE(this_context)->owner_thread = MR_ENGINE(owner_thread);

#endif

	/*
	** Now just call the entry point
	*/

	noprof_call(entry_point, LABEL(engine_done));

Define_label(engine_done);

	/*
	** Decrement the number of times we've entered this
	** engine from C and restore the owning thread in
	** the current context.
	*/
#ifdef	MR_THREAD_SAFE

	assert(MR_ENGINE(this_context)->owner_thread
		== MR_ENGINE(owner_thread));
	MR_ENGINE(c_depth)--;
{
	MercuryThreadList *tmp;
	MercuryThread val;

	tmp = MR_ENGINE(saved_owners);
	if (tmp != NULL)
	{
		val = tmp->thread;
		MR_ENGINE(saved_owners) = tmp->next;
		MR_GC_free(tmp);
	} else {
		val = 0;
	}
	MR_ENGINE(this_context)->owner_thread = val;
}
#endif

	debugmsg1("in label `engine_done', locals at %p\n", locals);

#ifdef MR_LOWLEVEL_DEBUG
	/*
	** Check how much of the space we reserved for local variables
	** was actually used.
	*/

	if (check_space) {
		int	low = 0, high = LOCALS_SIZE;
		int	used_low, used_high;

		while (low < high && locals[low] == MAGIC_MARKER) {
			low++;
		}
		while (low < high && locals[high - 1] == MAGIC_MARKER) {
			high--;
		}
		used_low = high;
		used_high = LOCALS_SIZE - low;
		printf("max locals used:  %3d bytes (probably)\n",
			min(high, LOCALS_SIZE - low));
		printf("(low mark = %d, high mark = %d)\n", low, high);
	}
#endif /* MR_LOWLEVEL_DEBUG */

	/*
	** Despite the above precautions with allocating a large chunk
	** of unused stack space, the return address may still have been
	** stored on the top of the stack, past our dummy locals,
	** where it may have been clobbered.
	** Hence the only safe way to exit is with longjmp().
	**
	** Since longjmp() may clobber the registers, we need to
	** save them first.
	*/
	MR_ENGINE(e_exception) = NULL;
	save_registers();

#ifdef	MR_DEBUG_JMPBUFS
	printf("engine longjmp %p\n", MR_ENGINE(e_jmp_buf));
#endif

	debugmsg0("longjmping out...\n");
	longjmp(*(MR_ENGINE(e_jmp_buf)), 1);
}} /* end call_engine_inner() */

/* with nonlocal gotos, we don't save the previous locations */
void 
dump_prev_locations(void) {}

#else /* not USE_GCC_NONLOCAL_GOTOS */

/*
** The portable version
**
** To keep the main dispatch loop tight, instead of returning a null
** pointer to indicate when we've finished executing, we just longjmp()
** out.  We need to save the registers before calling longjmp(),
** since doing a longjmp() might clobber them.
**
** With register windows, we need to restore the registers to
** their initialized values from their saved copies.
** This must be done in a function engine_init_registers() rather
** than directly from call_engine_inner() because otherwise their value
** would get mucked up because of the function call from call_engine_inner().
*/

static MR_Code *
engine_done(void)
{
	MR_ENGINE(e_exception) = NULL;
	save_registers();
	debugmsg0("longjmping out...\n");
	longjmp(*(MR_ENGINE(e_jmp_buf)), 1);
}

static MR_Code *
engine_init_registers(void)
{
	restore_transient_registers();
	MR_succip = (MR_Code *) engine_done;
	return NULL;
}

/*
** For debugging purposes, we keep a circular buffer of
** the last 40 locations that we jumped to.  This is
** very useful for determining the cause of a crash,
** since it runs a lot faster than -dg.
*/

#define NUM_PREV_FPS	40

typedef MR_Code	*Func(void);

static MR_Code 	*prev_fps[NUM_PREV_FPS];
static int	prev_fp_index = 0;

void 
dump_prev_locations(void)
{
	int i, pos;

#if !defined(MR_DEBUG_GOTOS)
	if (MR_tracedebug) 
#endif
	{
		printf("previous %d locations:\n", NUM_PREV_FPS);
		for (i = 0; i < NUM_PREV_FPS; i++) {
			pos = (i + prev_fp_index) % NUM_PREV_FPS;
			printlabel(prev_fps[pos]);
		}
	}
}

static void 
call_engine_inner(MR_Code *entry_point)
{
	reg	Func	*fp;

	/*
	** Start up the actual engine.
	** The loop is unrolled a bit for efficiency.
	*/

	fp = engine_init_registers;
	fp = (Func *) (*fp)();
	fp = (Func *) entry_point;

#if !defined(MR_DEBUG_GOTOS)
if (!MR_tracedebug) {
	for (;;)
	{
		fp = (Func *) (*fp)();
		fp = (Func *) (*fp)();
		fp = (Func *) (*fp)();
		fp = (Func *) (*fp)();
		fp = (Func *) (*fp)();
		fp = (Func *) (*fp)();
		fp = (Func *) (*fp)();
		fp = (Func *) (*fp)();
	}
} else
#endif
	for (;;)
	{
		prev_fps[prev_fp_index] = (MR_Code *) fp;

		if (++prev_fp_index >= NUM_PREV_FPS)
			prev_fp_index = 0;

		debuggoto(fp);
		debugsreg();
		fp = (Func *) (*fp)();
	}
} /* end call_engine_inner() */
#endif /* not USE_GCC_NONLOCAL_GOTOS */

/*---------------------------------------------------------------------------*/

void
terminate_engine(void)
{
	/*
	** we don't bother to deallocate memory...
	** that will happen automatically on process exit anyway.
	*/
}

/*---------------------------------------------------------------------------*/

Define_extern_entry(do_redo);
Define_extern_entry(do_fail);
Define_extern_entry(do_succeed);
Define_extern_entry(do_last_succeed);
Define_extern_entry(do_not_reached);
Define_extern_entry(exception_handler_do_fail);

BEGIN_MODULE(special_labels_module)
	init_entry_ai(do_redo);
	init_entry_ai(do_fail);
	init_entry_ai(do_succeed);
	init_entry_ai(do_last_succeed);
	init_entry_ai(do_not_reached);
	init_entry_ai(exception_handler_do_fail);
BEGIN_CODE

Define_entry(do_redo);
	MR_redo();

Define_entry(do_fail);
	MR_fail();

Define_entry(do_succeed);
	MR_succeed();

Define_entry(do_last_succeed);
	MR_succeed_discard();

Define_entry(do_not_reached);
	MR_fatal_error("reached not_reached\n");

Define_entry(exception_handler_do_fail);
	/*
	** `exception_handler_do_fail' is the same as `do_fail':
	** it just invokes fail().  The reason we don't just use
	** `do_fail' for this is that when unwinding the stack we
	** check for a redoip of `exception_handler_do_fail' and
	** handle it specially.
	*/
	MR_fail();

END_MODULE

void mercury_sys_init_engine(void); /* suppress gcc warning */
void mercury_sys_init_engine(void) {
	special_labels_module();
}

/*---------------------------------------------------------------------------*/
