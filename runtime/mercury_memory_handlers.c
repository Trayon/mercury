/*
** Copyright (C) 1998,2000 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** This module defines the signal handlers for memory zones.
** These handlers are invoked when memory is accessed outside of
** the memory zones, or at the protected region at the end of a
** memory zone (if available).
*/

/*---------------------------------------------------------------------------*/

#include "mercury_imp.h"

#ifdef HAVE_UNISTD_H
  #include <unistd.h>
#endif

#include <stdio.h>
#include <string.h>

/*
** XXX This code is duplicated in three files:
** mercury_memory.c, mercury_memory_handlers.c, and mercury_signal.c.
*/
#ifdef HAVE_SIGCONTEXT_STRUCT
  /*
  ** Some versions of Linux call it struct sigcontext_struct, some call it
  ** struct sigcontext.  The following #define eliminates the differences.
  */
  #define sigcontext_struct sigcontext /* must be before #include <signal.h> */
  struct sigcontext; /* this forward decl avoids a gcc warning in signal.h */

  /*
  ** On some systems (e.g. most versions of Linux) we need to #define
  ** __KERNEL__ to get sigcontext_struct from <signal.h>.
  ** This stuff must come before anything else that might include <signal.h>,
  ** otherwise the #define __KERNEL__ may not work.
  */
  #define __KERNEL__
  #include <signal.h>	/* must come third */
  #undef __KERNEL__

  /*
  ** Some versions of Linux define it in <signal.h>, others define it in
  ** <asm/sigcontext.h>.  We try both.
  */
  #ifdef HAVE_ASM_SIGCONTEXT
    #include <asm/sigcontext.h>
  #endif 
#else
  #include <signal.h>
#endif

#ifdef HAVE_SYS_SIGINFO
  #include <sys/siginfo.h>
#endif 

#ifdef	HAVE_MPROTECT
  #include <sys/mman.h>
#endif

#ifdef	HAVE_UCONTEXT
  #include <ucontext.h>
#endif

#ifdef	HAVE_SYS_UCONTEXT
  #include <sys/ucontext.h>
#endif

#include "mercury_imp.h"
#include "mercury_signal.h"
#include "mercury_trace_base.h"
#include "mercury_memory_zones.h"
#include "mercury_memory_handlers.h"
#include "mercury_faultaddr.h"

/*---------------------------------------------------------------------------*/

#ifdef HAVE_SIGINFO
  #if defined(HAVE_SIGCONTEXT_STRUCT)
    #if defined(HAVE_SIGCONTEXT_STRUCT_3ARG)
      static	void	complex_sighandler_3arg(int, int, 
		      struct sigcontext_struct);
    #else
      static	void	complex_sighandler(int, struct sigcontext_struct);
    #endif
  #elif defined(HAVE_SIGINFO_T)
    static	void	complex_bushandler(int, siginfo_t *, void *);
    static	void	complex_segvhandler(int, siginfo_t *, void *);
  #else
    #error "HAVE_SIGINFO defined but don't know how to get it"
  #endif
#else
  static	void	simple_sighandler(int);
#endif


#ifdef HAVE_SIGINFO
  #if defined(HAVE_SIGCONTEXT_STRUCT)
    #if defined(HAVE_SIGCONTEXT_STRUCT_3ARG)
      #define     bus_handler	complex_sighandler_3arg
      #define     segv_handler	complex_sighandler_3arg
    #else
      #define     bus_handler	complex_sighandler
      #define     segv_handler	complex_sighandler
    #endif
  #elif defined(HAVE_SIGINFO_T)
    #define     bus_handler	complex_bushandler
    #define     segv_handler	complex_segvhandler
  #else
    #error "HAVE_SIGINFO defined but don't know how to get it"
  #endif
#else
    #define     bus_handler	simple_sighandler
    #define     segv_handler	simple_sighandler
#endif


/*
** round_up(amount, align) returns `amount' rounded up to the nearest
** alignment boundary.  `align' must be a power of 2.
*/

static	void	print_dump_stack(void);
static	bool	try_munprotect(void *address, void *context);
static	char	*explain_context(void *context);
static	MR_Code	*get_pc_from_context(void *the_context);
static	MR_Word	*get_sp_from_context(void *the_context);
static	MR_Word	*get_curfr_from_context(void *the_context);

#define STDERR 2


static bool 
try_munprotect(void *addr, void *context)
{
#if !(defined(HAVE_SIGINFO) || defined(MR_WIN32_VIRTUAL_ALLOC))
	return FALSE;
#else
	MR_Word *    fault_addr;
	MemoryZone *zone;

	fault_addr = (MR_Word *) addr;

	zone = get_used_memory_zones();

	if (MR_memdebug) {
		fprintf(stderr, "caught fault at %p\n", (void *)addr);
	}

	while(zone != NULL) {
		if (MR_memdebug) {
			fprintf(stderr, "checking %s#%d: %p - %p\n",
				zone->name, zone->id, (void *) zone->redzone,
				(void *) zone->top);
		}

		if (zone->redzone <= fault_addr && fault_addr <= zone->top) {

			if (MR_memdebug) {
				fprintf(stderr, "address is in %s#%d redzone\n",
					zone->name, zone->id);
			}

			return zone->handler(fault_addr, zone, context);
		}
		zone = zone->next;
	}

	if (MR_memdebug) {
		fprintf(stderr, "address not in any redzone.\n");
	}

	return FALSE;
#endif /* HAVE_SIGINFO */
} 

bool 
null_handler(MR_Word *fault_addr, MemoryZone *zone, void *context)
{
	return FALSE;
}

/*
** fatal_abort() prints an error message, possibly a stack dump, and then exits.
** It is like fatal_error(), except that it is safe to call
** from a signal handler.
*/

static void 
fatal_abort(void *context, const char *main_msg, int dump)
{
	char	*context_msg;

	context_msg = explain_context(context);
	write(STDERR, main_msg, strlen(main_msg));
	write(STDERR, context_msg, strlen(context_msg));
	MR_trace_report_raw(STDERR);

	if (dump) {
		print_dump_stack();
	}

	_exit(1);
}

bool 
default_handler(MR_Word *fault_addr, MemoryZone *zone, void *context)
{
#ifndef MR_CHECK_OVERFLOW_VIA_MPROTECT
	return FALSE;
#else
    MR_Word *new_zone;
    size_t zone_size;

    new_zone = (MR_Word *) round_up((MR_Unsigned) fault_addr + sizeof(MR_Word), unit);

    if (new_zone <= zone->hardmax) {
	zone_size = (char *)new_zone - (char *)zone->redzone;

	if (MR_memdebug) {
	    fprintf(stderr, "trying to unprotect %s#%d from %p to %p (%x)\n",
	    zone->name, zone->id, (void *) zone->redzone, (void *) new_zone,
	    (int)zone_size);
	}
	if (MR_protect_pages((char *)zone->redzone, zone_size,
		PROT_READ|PROT_WRITE) < 0)
	{
	    char buf[2560];
	    sprintf(buf, "Mercury runtime: cannot unprotect %s#%d zone",
		zone->name, zone->id);
	    perror(buf);
	    exit(1);
	}

	zone->redzone = new_zone;

	if (MR_memdebug) {
	    fprintf(stderr, "successful: %s#%d redzone now %p to %p\n",
		zone->name, zone->id, (void *) zone->redzone,
		(void *) zone->top);
	}
  #ifdef NATIVE_GC
	MR_schedule_agc(get_pc_from_context(context),
		get_sp_from_context(context),
		get_curfr_from_context(context));
  #endif
	return TRUE;
    } else {
	char buf[2560];
	if (MR_memdebug) {
	    fprintf(stderr, "can't unprotect last page of %s#%d\n",
		zone->name, zone->id);
	    fflush(stdout);
	}
	sprintf(buf, "\nMercury runtime: memory zone %s#%d overflowed\n",
		zone->name, zone->id);
	fatal_abort(context, buf, TRUE);
    }

    return FALSE;
#endif
} 

void
setup_signals(void)
{
/*
** When using Microsoft Visual C structured exceptions don't set any
** signal handlers.
** See mercury_wrapper.c for the reason why.
*/
#ifndef MR_MSVC_STRUCTURED_EXCEPTIONS
  #ifdef SIGBUS
	MR_setup_signal(SIGBUS, (MR_Code *) bus_handler, TRUE,
		"Mercury runtime: cannot set SIGBUS handler");
  #endif
	MR_setup_signal(SIGSEGV, (MR_Code *) segv_handler, TRUE,
		"Mercury runtime: cannot set SIGSEGV handler");
#endif
}

static char *
explain_context(void *the_context)
{
	static	char	buf[100];

#if defined(HAVE_SIGCONTEXT_STRUCT)

  #ifdef PC_ACCESS
	struct sigcontext_struct *context = the_context;
	void *pc_at_signal = (void *) context->PC_ACCESS;

	sprintf(buf, "PC at signal: %ld (%lx)\n",
		(long)pc_at_signal, (long)pc_at_signal);
  #else
	buf[0] = '\0';
  #endif

#elif defined(HAVE_SIGINFO_T)

  #ifdef PC_ACCESS

	ucontext_t *context = the_context;

    #ifdef PC_ACCESS_GREG
	sprintf(buf, "PC at signal: %ld (%lx)\n",
		(long) context->uc_mcontext.gregs[PC_ACCESS],
		(long) context->uc_mcontext.gregs[PC_ACCESS]);
    #else
	sprintf(buf, "PC at signal: %ld (%lx)\n",
		(long) context->uc_mcontext.PC_ACCESS,
		(long) context->uc_mcontext.PC_ACCESS);
    #endif

  #else /* not PC_ACCESS */

	/* if PC_ACCESS is not set, we don't know the context */
	/* therefore we return an empty string to be printed  */
	buf[0] = '\0';

  #endif /* not PC_ACCESS */

#else /* not HAVE_SIGINFO_T && not HAVE_SIGCONTEXT_STRUCT */

	buf[0] = '\0';

#endif

	return buf;
}

#if defined(HAVE_SIGCONTEXT_STRUCT)
  #if defined(HAVE_SIGCONTEXT_STRUCT_3ARG)
    static void
    complex_sighandler_3arg(int sig, int code,
		    struct sigcontext_struct sigcontext)
  #else
    static void
    complex_sighandler(int sig, struct sigcontext_struct sigcontext)
  #endif
{
	void *address = (void *) MR_GET_FAULT_ADDR(sigcontext);
  #ifdef PC_ACCESS
	void *pc_at_signal = (void *) sigcontext.PC_ACCESS;
  #endif

	switch(sig) {
		case SIGSEGV:
			/*
			** If we're debugging, print the segv explanation
			** messages before we call try_munprotect.  But if
			** we're not debugging, only print them if
			** try_munprotect fails.
			*/
			if (MR_memdebug) {
				fflush(stdout);
				fprintf(stderr, "\n*** Mercury runtime: "
					"caught segmentation violation ***\n");
			}
			if (try_munprotect(address, &sigcontext)) {
				if (MR_memdebug) {
					fprintf(stderr, "returning from "
						"signal handler\n\n");
				}
				return;
			}
			if (!MR_memdebug) {
				fflush(stdout);
				fprintf(stderr, "\n*** Mercury runtime: "
					"caught segmentation violation ***\n");
			}
			break;

#ifdef SIGBUS
		case SIGBUS:
			fflush(stdout);
			fprintf(stderr, "\n*** Mercury runtime: "
					"caught bus error ***\n");
			break;
#endif

		default:
			fflush(stdout);
			fprintf(stderr, "\n*** Mercury runtime: "
					"caught unknown signal %d ***\n", sig);
			break;
	}

  #ifdef PC_ACCESS
	fprintf(stderr, "PC at signal: %ld (%lx)\n",
		(long) pc_at_signal, (long) pc_at_signal);
  #endif
	fprintf(stderr, "address involved: %p\n", address);

	MR_trace_report(stderr);
	print_dump_stack();
	dump_prev_locations();
	fprintf(stderr, "exiting from signal handler\n");
	exit(1);
} /* end complex_sighandler() */


#elif defined(HAVE_SIGINFO_T)

static void 
complex_bushandler(int sig, siginfo_t *info, void *context)
{
	fflush(stdout);

	if (sig != SIGBUS || !info || info->si_signo != SIGBUS) {
		fprintf(stderr, "\n*** Mercury runtime: ");
		fprintf(stderr, "caught strange bus error ***\n");
		exit(1);
	}

	fprintf(stderr, "\n*** Mercury runtime: ");
	fprintf(stderr, "caught bus error ***\n");

	if (info->si_code > 0) {
		fprintf(stderr, "cause: ");
		switch (info->si_code)
		{
		case BUS_ADRALN:
			fprintf(stderr, "invalid address alignment\n");
			break;

		case BUS_ADRERR:
			fprintf(stderr, "non-existent physical address\n");
			break;

		case BUS_OBJERR:
			fprintf(stderr, "object specific hardware error\n");
			break;

		default:
			fprintf(stderr, "unknown\n");
			break;

		} /* end switch */

		fprintf(stderr, "%s", explain_context(context));
		fprintf(stderr, "address involved: %p\n",
			(void *) info->si_addr);
	} /* end if */

	MR_trace_report(stderr);
	print_dump_stack();
	dump_prev_locations();
	fprintf(stderr, "exiting from signal handler\n");
	exit(1);
} /* end complex_bushandler() */

static void 
explain_segv(siginfo_t *info, void *context)
{
	fflush(stdout);

	fprintf(stderr, "\n*** Mercury runtime: ");
	fprintf(stderr, "caught segmentation violation ***\n");

	if (!info) {
		return;
	}

	if (info->si_code > 0) {
		fprintf(stderr, "cause: ");
		switch (info->si_code)
		{
		case SEGV_MAPERR:
			fprintf(stderr, "address not mapped to object\n");
			break;

		case SEGV_ACCERR:
			fprintf(stderr, "bad permissions for mapped object\n");
			break;

		default:
			fprintf(stderr, "unknown\n");
			break;
		}

		fprintf(stderr, "%s", explain_context(context));
		fprintf(stderr, "address involved: %p\n",
			(void *) info->si_addr);

	} /* end if */
} /* end explain_segv() */

static void 
complex_segvhandler(int sig, siginfo_t *info, void *context)
{
	if (sig != SIGSEGV || !info || info->si_signo != SIGSEGV) {
		fprintf(stderr, "\n*** Mercury runtime: ");
		fprintf(stderr, "caught strange segmentation violation ***\n");
		exit(1);
	}

	/*
	** If we're debugging, print the segv explanation messages
	** before we call try_munprotect.  But if we're not debugging,
	** only print them if try_munprotect fails.
	*/

	if (MR_memdebug) {
		explain_segv(info, context);
	}

	if (try_munprotect(info->si_addr, context)) {
		if (MR_memdebug) {
			fprintf(stderr, "returning from signal handler\n\n");
		}

		return;
	}

	if (!MR_memdebug) {
		explain_segv(info, context);
	}

	MR_trace_report(stderr);
	print_dump_stack();
	dump_prev_locations();
	fprintf(stderr, "exiting from signal handler\n");
	exit(1);
} /* end complex_segvhandler */

#else /* not HAVE_SIGINFO_T && not HAVE_SIGCONTEXT_STRUCT */

static void 
simple_sighandler(int sig)
{
	fflush(stdout);
	fprintf(stderr, "*** Mercury runtime: ");

	switch (sig)
	{
#ifdef SIGBUS
	case SIGBUS:
		fprintf(stderr, "caught bus error ***\n");
		break;
#endif

	case SIGSEGV:
		fprintf(stderr, "caught segmentation violation ***\n");
		break;

	default:
		fprintf(stderr, "caught unknown signal %d ***\n", sig);
		break;
	}

	print_dump_stack();
	dump_prev_locations();
	fprintf(stderr, "exiting from signal handler\n");
	exit(1);
}

#endif /* not HAVE_SIGINFO_T && not HAVE_SIGCONTEXT_STRUCT */

#ifdef MR_MSVC_STRUCTURED_EXCEPTIONS
static const char *MR_find_exception_name(DWORD exception_code);
static void MR_explain_exception_record(EXCEPTION_RECORD *rec);
static void MR_dump_exception_record(EXCEPTION_RECORD *rec);
static bool MR_exception_record_is_access_violation(EXCEPTION_RECORD *rec,
		void **address_ptr, int *access_mode_ptr);

/*
** Exception code and their string representation
*/
#define DEFINE_EXCEPTION_NAME(a)   {a,#a}

typedef struct
{
	DWORD		exception_code;
	const char	*exception_name;
} MR_ExceptionName;

static const
MR_ExceptionName MR_exception_names[] =
{
	DEFINE_EXCEPTION_NAME(EXCEPTION_ACCESS_VIOLATION),
	DEFINE_EXCEPTION_NAME(EXCEPTION_DATATYPE_MISALIGNMENT),
	DEFINE_EXCEPTION_NAME(EXCEPTION_BREAKPOINT),
	DEFINE_EXCEPTION_NAME(EXCEPTION_SINGLE_STEP),
	DEFINE_EXCEPTION_NAME(EXCEPTION_ARRAY_BOUNDS_EXCEEDED),
	DEFINE_EXCEPTION_NAME(EXCEPTION_FLT_DENORMAL_OPERAND),
	DEFINE_EXCEPTION_NAME(EXCEPTION_FLT_DIVIDE_BY_ZERO),
	DEFINE_EXCEPTION_NAME(EXCEPTION_FLT_INEXACT_RESULT),
	DEFINE_EXCEPTION_NAME(EXCEPTION_FLT_INVALID_OPERATION),
	DEFINE_EXCEPTION_NAME(EXCEPTION_FLT_OVERFLOW),
	DEFINE_EXCEPTION_NAME(EXCEPTION_FLT_STACK_CHECK),
	DEFINE_EXCEPTION_NAME(EXCEPTION_FLT_UNDERFLOW),
	DEFINE_EXCEPTION_NAME(EXCEPTION_INT_DIVIDE_BY_ZERO),
	DEFINE_EXCEPTION_NAME(EXCEPTION_INT_OVERFLOW),
	DEFINE_EXCEPTION_NAME(EXCEPTION_PRIV_INSTRUCTION),
	DEFINE_EXCEPTION_NAME(EXCEPTION_IN_PAGE_ERROR),
	DEFINE_EXCEPTION_NAME(EXCEPTION_ILLEGAL_INSTRUCTION),
	DEFINE_EXCEPTION_NAME(EXCEPTION_NONCONTINUABLE_EXCEPTION),
	DEFINE_EXCEPTION_NAME(EXCEPTION_STACK_OVERFLOW),
	DEFINE_EXCEPTION_NAME(EXCEPTION_INVALID_DISPOSITION),
	DEFINE_EXCEPTION_NAME(EXCEPTION_GUARD_PAGE),
	DEFINE_EXCEPTION_NAME(EXCEPTION_INVALID_HANDLE)
};


/*
** Retrieve the name of a Win32 exception code as a string
*/
static const char *
MR_find_exception_name(DWORD exception_code)
{
	int i;
	for (i = 0; i < sizeof(MR_exception_names)
			/ sizeof(MR_ExceptionName); i++)
	{
		if (MR_exception_names[i].exception_code == exception_code) {
			return MR_exception_names[i].exception_name;
		}
	}
	return "Unknown exception code";
}

/*
** Was a page accessed read/write?  The MSDN documentation doens't define
** symbolic constants for these alternatives.
*/
#define READ	0
#define WRITE	1

/*
** Explain an EXCEPTION_RECORD content into stderr.
*/
static void
MR_explain_exception_record(EXCEPTION_RECORD *rec)
{
	fprintf(stderr, "\n");
	fprintf(stderr, "\n*** Explanation of the exception record");
	if (rec == NULL) {
		fprintf(stderr, "\n***   Cannot explain because it is NULL");
		return;
	} else {
		void *address;
		int access_mode;
		
		/* If the exception is an access violation */
		if (MR_exception_record_is_access_violation(rec,
					&address, &access_mode))
		{
			MemoryZone *zone;

			/* Display AV address and access mode */
			fprintf(stderr, "\n***   An access violation occured"
					" at address 0x%08lx, while attempting"
					" to ", (unsigned long) address);
			
			if (access_mode == READ) {
				fprintf(stderr, "\n***   read "
						"inaccessible data");
			} else if (access_mode == WRITE) {
				fprintf(stderr, "\n***   write to an "
						"inaccessible (or protected)"
						" address");
			} else {
				fprintf(stderr, "\n***   ? [unknown access "
						"mode %d (strange...)]",
						access_mode);
			}
				
			fprintf(stderr, "\n***   Trying to see if this "
					"stands within a mercury zone...");
			/*
			** Browse the mercury memory zones to see if the
			** AV address references one of them.
			*/
			zone = get_used_memory_zones();
			while(zone != NULL) {
				fprintf(stderr,
						"\n***    Checking zone %s#%d: "
						"0x%08lx - 0x%08lx - 0x%08lx",
						zone->name, zone->id,
						(unsigned long) zone->bottom,
						(unsigned long) zone->redzone,
						(unsigned long) zone->top);

				if ((zone->redzone <= address) &&
						(address <= zone->top))
				{
					fprintf(stderr,
						"\n***     Address is within"
						" redzone of "
						"%s#%d (!!zone overflowed!!)\n",
						zone->name, zone->id);
				} else if ((zone->bottom <= address) &&
						(address <= zone->top))
				{
					fprintf(stderr, "\n***     Address is"
							" within zone %s#%d\n",
							zone->name, zone->id);
				}
				/*
				** Don't need to call handler, because it
				** has much less information than we do.
				*/
				/* return zone->handler(fault_addr,
				 		zone, rec); */
				zone = zone->next;
			}
		}
		return;
	}
}

/*
** Dump an EXCEPTION_RECORD content into stderr.
*/
static void
MR_dump_exception_record(EXCEPTION_RECORD *rec)
{
	int i;
	
	if (rec == NULL) {
		return;
	}
	
	fprintf(stderr, "\n***   Exception record at 0x%08lx:",
			(unsigned long) rec);
	fprintf(stderr, "\n***    MR_Code        : 0x%08lx (%s)",
			(unsigned long) rec->ExceptionCode,
			MR_find_exception_name(rec->ExceptionCode));
	fprintf(stderr, "\n***    Flags       : 0x%08lx",
			(unsigned long) rec->ExceptionFlags);
	fprintf(stderr, "\n***    Address     : 0x%08lx",
			(unsigned long) rec->ExceptionAddress);

	for (i = 0; i < rec->NumberParameters; i++) {
		fprintf(stderr, "\n***    Parameter %d : 0x%08lx", i,
				(unsigned long) rec->ExceptionInformation[i]);
	}
	fprintf(stderr, "\n***    Next record : 0x%08lx",
			(unsigned long) rec->ExceptionRecord);
	
	/* Try to explain the exception more "gracefully" */
	MR_explain_exception_record(rec);
	MR_dump_exception_record(rec->ExceptionRecord);
}


/*
** Return TRUE iff exception_ptrs indicates an access violation.
** If TRUE, the dereferenced address_ptr is set to the accessed address and
** the dereferenced access_mode_ptr is set to the desired access
** (0 = read, 1 = write)
*/
static bool
MR_exception_record_is_access_violation(EXCEPTION_RECORD *rec,
		void **address_ptr, int *access_mode_ptr)
{
	if (rec->ExceptionCode == EXCEPTION_ACCESS_VIOLATION) {
		if (rec->NumberParameters >= 2) {
			(*access_mode_ptr) = (int) rec->ExceptionInformation[0];
			(*address_ptr) = (void *) rec->ExceptionInformation[1];
			return TRUE;
		}
	}
	return FALSE;
}


/*
** Filter a Win32 exception (to be called in the __except filter part).
** Possible return values are:
**
** EXCEPTION_CONTINUE_EXECUTION (-1)
**  Exception is dismissed. Continue execution at the point where
**  the exception occurred.
**
** EXCEPTION_CONTINUE_SEARCH (0)
**  Exception is not recognized. Continue to search up the stack for
**  a handler, first for containing try-except statements, then for
**  handlers with the next highest precedence.
**
** EXCEPTION_EXECUTE_HANDLER (1)
**  Exception is recognized. Transfer control to the exception handler
**  by executing the __except compound statement, then continue
**  execution at the assembly instruction that was executing
**  when the exception was raised. 
*/
int
MR_filter_win32_exception(LPEXCEPTION_POINTERS exception_ptrs)
{
	void *address;
	int access_mode;

		/* If the exception is an access violation */
	if (MR_exception_record_is_access_violation(
			exception_ptrs->ExceptionRecord,
			&address, &access_mode))
	{

			/* If we can unprotect the memory zone */
		if (try_munprotect(address, exception_ptrs)) {
			if (MR_memdebug) {
				fprintf(stderr, "returning from "
						"signal handler\n\n");
			}
				/* Continue execution where it stopped */
			return  EXCEPTION_CONTINUE_EXECUTION;
		}
	}
		
	/*
	** We can't handle the exception. Just dump all the information we got
	*/
	fflush(stdout);
	fprintf(stderr, "\n*** Mercury runtime: Unhandled exception ");
	MR_dump_exception_record(exception_ptrs->ExceptionRecord);

	printf("\n");
	print_dump_stack();
	dump_prev_locations();
	
	fprintf(stderr, "\n\n*** Now passing exception to default handler\n\n");
	fflush(stderr);
		  
	/*
	** Pass exception back to upper handler. In most cases, this
	** means activating UnhandledExceptionFilter, which will display
	** a dialog box asking to user ro activate the Debugger or simply
	** to kill the application
	*/
	return  EXCEPTION_CONTINUE_SEARCH;
}
#endif /* MR_MSVC_STRUCTURED_EXCEPTIONS */


/*
** get_pc_from_context:
** 	Given the signal context, return the program counter at the time
** 	of the signal, if available.  If it is unavailable, return NULL.
*/
static MR_Code *
get_pc_from_context(void *the_context)
{
	MR_Code *pc_at_signal = NULL;
#if defined(HAVE_SIGCONTEXT_STRUCT)

  #ifdef PC_ACCESS
	struct sigcontext_struct *context = the_context;

	pc_at_signal = (MR_Code *) context->PC_ACCESS;
  #else
	pc_at_signal = (MR_Code *) NULL;
  #endif

#elif defined(HAVE_SIGINFO_T)

  #ifdef PC_ACCESS

	ucontext_t *context = the_context;

    #ifdef PC_ACCESS_GREG
	pc_at_signal = (MR_Code *) context->uc_mcontext.gregs[PC_ACCESS];
    #else
	pc_at_signal = (MR_Code *) context->uc_mcontext.PC_ACCESS;
    #endif

  #else /* not PC_ACCESS */

	/* if PC_ACCESS is not set, we don't know the context */
	pc_at_signal = (MR_Code *) NULL;

  #endif /* not PC_ACCESS */

#else /* not HAVE_SIGINFO_T && not HAVE_SIGCONTEXT_STRUCT */

	pc_at_signal = (MR_Code *) NULL;

#endif

	return pc_at_signal;
}

/*
** get_sp_from_context:
** 	Given the signal context, return the Mercury register "MR_sp" at
** 	the time of the signal, if available.  If it is unavailable,
** 	return NULL.
**
** XXX We only define this function in accurate gc grades for the moment,
** because it's unlikely to compile everywhere.  It relies on
** MR_real_reg_number_sp being defined, which is the name/number of the
** machine register that is used for MR_sp.
** Need to fix this so it works when the register is in a fake reg too.
*/
static MR_Word *
get_sp_from_context(void *the_context)
{
	MR_Word *sp_at_signal = NULL;
#ifdef NATIVE_GC
  #if defined(HAVE_SIGCONTEXT_STRUCT)

    #ifdef PC_ACCESS
	struct sigcontext_struct *context = the_context;

	sp_at_signal = (MR_Word *) context->MR_real_reg_number_sp;
    #else
	sp_at_signal = (MR_Word *) NULL;
    #endif

  #elif defined(HAVE_SIGINFO_T)

    #ifdef PC_ACCESS

	struct sigcontext *context = the_context;

      #ifdef PC_ACCESS_GREG
	sp_at_signal = (MR_Word *) context->gregs[MR_real_reg_number_sp];
      #else
	sp_at_signal = (MR_Word *) context->sc_regs[MR_real_reg_number_sp];
      #endif

    #else /* not PC_ACCESS */

	/* 
	** if PC_ACCESS is not set, we don't know how to get at the
	** registers
	*/
	sp_at_signal = (MR_Word *) NULL;

    #endif /* not PC_ACCESS */

  #else /* not HAVE_SIGINFO_T && not HAVE_SIGCONTEXT_STRUCT */

	sp_at_signal = (MR_Word *) NULL;

  #endif
#else /* !NATIVE_GC */
	sp_at_signal = (MR_Word *) NULL;
#endif /* !NATIVE_GC */

	return sp_at_signal;
}

/*
** get_sp_from_context:
** 	Given the signal context, return the Mercury register "MR_sp" at
** 	the time of the signal, if available.  If it is unavailable,
** 	return NULL.
**
** XXX We only define this function in accurate gc grades for the moment,
** because it's unlikely to compile everywhere.  It relies on
** MR_real_reg_number_sp being defined, which is the name/number of the
** machine register that is used for MR_sp.
** Need to fix this so it works when the register is in a fake reg too.
*/
static MR_Word *
get_curfr_from_context(void *the_context)
{
	MR_Word *curfr_at_signal;
	
	/*
	** XXX this is implementation dependent, need a better way
	** to do register accesses at signals.
	**
	** It's in mr8 or mr9 which is in the fake regs on some architectures,
	** and is a machine register on others.
	** So don't run the garbage collector on those archs.
	*/

	curfr_at_signal = MR_curfr;

	return curfr_at_signal;
}

static void 
print_dump_stack(void)
{

#ifndef	MR_LOWLEVEL_DEBUG

	const char *msg =
		"This may have been caused by a stack overflow, due to unbounded recursion.\n";
	write(STDERR, msg, strlen(msg));

#else /* MR_LOWLEVEL_DEBUG */
	int	i;
	int	start;
	int	count;
	char	buf[2560];

	strcpy(buf, "A dump of the det stack follows\n\n");
	write(STDERR, buf, strlen(buf));

	i = 0;
	while (i < dumpindex) {
		start = i;
		count = 1;
		i++;

		while (i < dumpindex &&
			strcmp(((char **)(dumpstack_zone->min))[i],
				((char **)(dumpstack_zone->min))[start]) == 0)
		{
			count++;
			i++;
		}

		if (count > 1) {
			sprintf(buf, "%s * %d\n",
				((char **)(dumpstack_zone->min))[start], count);
		} else {
			sprintf(buf, "%s\n",
				((char **)(dumpstack_zone->min))[start]);
		}

		write(STDERR, buf, strlen(buf));
	} /* end while */

	strcpy(buf, "\nend of stack dump\n");
	write(STDERR, buf, strlen(buf));

#endif /* MR_LOWLEVEL_DEBUG */

} /* end print_dump_stack() */


