/*
** Copyright (C) 1996-1998 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

#include	"mercury_imp.h"
#include	"mercury_dlist.h"
#include	"mercury_regs.h"
#include	"mercury_trace_base.h"
#include	"mercury_label.h"
#include	"mercury_misc.h"

#include	<stdio.h>
#include	<stdarg.h>

/*--------------------------------------------------------------------*/

static void print_ordinary_regs(void);

/* debugging messages */

#ifdef MR_LOWLEVEL_DEBUG

void 
mkframe_msg(void)
{
	restore_transient_registers();

	printf("\nnew choice point for procedure %s\n",
		MR_prednm_slot(MR_curfr));
	printf("new  fr: "); printnondstack(MR_curfr);
	printf("prev fr: "); printnondstack(MR_prevfr_slot(MR_curfr));
	printf("succ fr: "); printnondstack(MR_succfr_slot(MR_curfr));
	printf("succ ip: "); printlabel(MR_succip_slot(MR_curfr));
	printf("redo ip: "); printlabel(MR_redoip_slot(MR_curfr));

	if (MR_detaildebug) {
		dumpnondstack();
	}

	return;
}

void 
succeed_msg(void)
{
	restore_transient_registers();

	printf("\nsucceeding from procedure %s\n", MR_prednm_slot(MR_curfr));
	printf("curr fr: "); printnondstack(MR_curfr);
	printf("succ fr: "); printnondstack(MR_succfr_slot(MR_curfr));
	printf("succ ip: "); printlabel(MR_succip_slot(MR_curfr));

	if (MR_detaildebug) {
		printregs("registers at success");
	}
	
	return;
}

void 
succeeddiscard_msg(void)
{
	restore_transient_registers();

	printf("\nsucceeding from procedure %s, discarding frame\n", MR_prednm_slot(MR_curfr));
	printf("curr fr: "); printnondstack(MR_curfr);
	printf("succ fr: "); printnondstack(MR_succfr_slot(MR_curfr));
	printf("succ ip: "); printlabel(MR_succip_slot(MR_curfr));

	if (MR_detaildebug) {
		printregs("registers at success");
	}

	return;
}

void 
fail_msg(void)
{
	restore_transient_registers();

	printf("\nfailing from procedure %s\n", MR_prednm_slot(MR_curfr));
	printf("curr fr: "); printnondstack(MR_curfr);
	printf("fail fr: "); printnondstack(MR_prevfr_slot(MR_curfr));
	printf("fail ip: "); printlabel(MR_redoip_slot(curprevfr_slot(MR_curfr)));

	return;
}

void 
redo_msg(void)
{
	restore_transient_registers();

	printf("\nredo from procedure %s\n", MR_prednm_slot(MR_curfr));
	printf("curr fr: "); printnondstack(MR_curfr);
	printf("redo fr: "); printnondstack(MR_maxfr);
	printf("redo ip: "); printlabel(MR_redoip_slot(MR_maxfr));

	return;
}

void 
call_msg(/* const */ Code *proc, /* const */ Code *succcont)
{
	printf("\ncalling      "); printlabel(proc);
	printf("continuation "); printlabel(succcont);
	printregs("registers at call");

	return;
}

void 
tailcall_msg(/* const */ Code *proc)
{
	restore_transient_registers();

	printf("\ntail calling "); printlabel(proc);
	printf("continuation "); printlabel(MR_succip);
	printregs("registers at tailcall");

	return;
}

void 
proceed_msg(void)
{
	printf("\nreturning from determinate procedure\n");
	printregs("registers at proceed");

	return;
}

void 
cr1_msg(Word val0, const Word *addr)
{
	printf("put value %9lx at ", (long) (Integer) val0);
	printheap(addr);

	return;
}

void 
cr2_msg(Word val0, Word val1, const Word *addr)
{
	printf("put values %9lx,%9lx at ",	
		(long) (Integer) val0, (long) (Integer) val1);
	printheap(addr);

	return;
}

void 
incr_hp_debug_msg(Word val, const Word *addr)
{
#ifdef CONSERVATIVE_GC
	printf("allocated %ld words at 0x%p\n", (long) (Integer) val, addr);
#else
	printf("increment hp by %ld from ", (long) (Integer) val);
	printheap(addr);
#endif
	return;
}

void 
incr_sp_msg(Word val, const Word *addr)
{
	printf("increment sp by %ld from ", (long) (Integer) val);
	printdetstack(addr);

	return;
}

void 
decr_sp_msg(Word val, const Word *addr)
{
	printf("decrement sp by %ld from ", (long) (Integer) val);
	printdetstack(addr);

	return;
}

void 
push_msg(Word val, const Word *addr)
{
	printf("push value %9lx to ", (long) (Integer) val);
	printdetstack(addr);

	return;
}

void 
pop_msg(Word val, const Word *addr)
{
	printf("pop value %9lx from ", (long) (Integer) val);
	printdetstack(addr);

	return;
}

#endif /* defined(MR_LOWLEVEL_DEBUG) */

#ifdef MR_DEBUG_GOTOS

void 
goto_msg(/* const */ Code *addr)
{
	printf("\ngoto ");
	printlabel(addr);
}

void 
reg_msg(void)
{
	int	i;
	Integer	x;

	for(i=1; i<=8; i++) {
		x = (Integer) get_reg(i);
#ifndef CONSERVATIVE_GC
		if ((Integer) MR_ENGINE(heap_zone)->min <= x
				&& x < (Integer) MR_ENGINE(heap_zone)->top) {
			x -= (Integer) MR_ENGINE(heap_zone)->min;
		}
#endif
		printf("%8lx ", (long) x);
	}
	printf("\n");

	return;
}

#endif /* defined(MR_DEBUG_GOTOS) */

/*--------------------------------------------------------------------*/

#ifdef MR_LOWLEVEL_DEBUG

/* debugging printing tools */

void 
printint(Word n)
{
	printf("int %ld\n", (long) (Integer) n);

	return;
}

void 
printstring(const char *s)
{
	printf("string 0x%p %s\n", (const void *) s, s);

	return;
}

void 
printheap(const Word *h)
{
#ifndef CONSERVATIVE_GC
	printf("ptr 0x%p, offset %3ld words\n",
		(const void *) h,
		(long) (Integer) (h - MR_ENGINE(heap_zone)->min));
#else
	printf("ptr 0x%p\n",
		(const void *) h);
#endif
	return;
}

void 
printdetstack(const Word *s)
{
	printf("ptr 0x%p, offset %3ld words\n",
		(const void *) s,
		(long) (Integer) (s - MR_CONTEXT(detstack_zone)->min));
	return;
}

void 
printnondstack(const Word *s)
{
#ifndef	MR_DEBUG_NONDET_STACK
	printf("ptr 0x%p, offset %3ld words\n",
		(const void *) s,
		(long) (Integer) (s - MR_CONTEXT(nondetstack_zone)->min));
#else
	if (s > MR_CONTEXT(nondetstack_zone)->min) {
		printf("ptr 0x%p, offset %3ld words, procedure %s\n",
			(const void *) s, 
			(long) (Integer)
				(s - MR_CONTEXT(nondetstack_zone)->min),
			(const char *) s[PREDNM]);
	} else {
		/*
		** This handles the case where the prevfr of the first frame
		** is being printed.
		*/
		printf("ptr 0x%p, offset %3ld words\n",
			(const void *) s, 
			(long) (Integer)
				(s - MR_CONTEXT(nondetstack_zone)->min));
	}
#endif
	return;
}

void 
dumpframe(/* const */ Word *fr)
{
	reg	int	i;

	printf("frame at ptr 0x%p, offset %3ld words\n",
		(const void *) fr, 
		(long) (Integer) (fr - MR_CONTEXT(nondetstack_zone)->min));
#ifdef	MR_DEBUG_NONDET_STACK
	printf("\t predname  %s\n", MR_prednm_slot(fr));
#endif
	printf("\t succip    "); printlabel(MR_succip_slot(fr));
	printf("\t redoip    "); printlabel(MR_redoip_slot(fr));
	printf("\t succfr    "); printnondstack(MR_succfr_slot(fr));
	printf("\t prevfr    "); printnondstack(MR_prevfr_slot(fr));

	for (i = 1; &MR_based_framevar(fr,i) > MR_prevfr_slot(fr); i++) {
		printf("\t framevar(%d)  %ld 0x%lx\n",
			i, (long) (Integer) MR_based_framevar(fr,i),
			(unsigned long) MR_based_framevar(fr,i));
	}
	return;
}

void 
dumpnondstack(void)
{
	reg	Word	*fr;

	printf("\nnondstack dump\n");
	for (fr = MR_maxfr; fr > MR_CONTEXT(nondetstack_zone)->min;
			fr = MR_prevfr_slot(fr)) {
		dumpframe(fr);
	}
	return;
}

void 
printframe(const char *msg)
{
	printf("\n%s\n", msg);
	dumpframe(MR_curfr);

	print_ordinary_regs();
	return;
}

void 
printregs(const char *msg)
{
	restore_transient_registers();

	printf("\n%s\n", msg);

	printf("%-9s", "succip:");  printlabel(MR_succip);
	printf("%-9s", "curfr:");   printnondstack(MR_curfr);
	printf("%-9s", "maxfr:");   printnondstack(MR_maxfr);
	printf("%-9s", "hp:");      printheap(MR_hp);
	printf("%-9s", "sp:");      printdetstack(MR_sp);

	print_ordinary_regs();

	return;
}

static void 
print_ordinary_regs(void)
{
	int	i;
	Integer	value;

	for (i = 0; i < 8; i++) {
		printf("r%d:      ", i + 1);
		value = (Integer) get_reg(i+1);

#ifndef	CONSERVATIVE_GC
		if ((Integer) MR_ENGINE(heap_zone)->min <= value &&
				value < (Integer) MR_ENGINE(heap_zone)->top) {
			printf("(heap) ");
		}
#endif

		printf("%ld\n", (long) value);
	}
}

#endif /* defined(MR_DEBUG_GOTOS) */

void 
printlabel(/* const */ Code *w)
{
	MR_Internal	*internal;

	internal = MR_lookup_internal_by_addr(w);
	if (internal != NULL) {
		printf("label %s (0x%p)\n", internal->i_name, w);
	} else {
#ifdef	MR_DEBUG_GOTOS
		MR_Entry	*entry;
		entry = MR_prev_entry_by_addr(w);
		if (entry->e_addr == w) {
			printf("label %s (0x%p)\n", entry->e_name, w);
		} else {
			printf("label UNKNOWN (0x%p)\n", w);
		}
#else
		printf("label UNKNOWN (0x%p)\n", w);
#endif	/* not MR_DEBUG_GOTOS */
	}
}

void *
newmem(size_t n)
{
	reg	void	*p;

#ifdef CONSERVATIVE_GC
	p = GC_MALLOC(n);
#else
	p = malloc(n);
#endif
	if (p == NULL && n != 0) {
		fatal_error("ran out of memory");
	}

	return p;
}

void 
oldmem(void *p)
{
#ifdef CONSERVATIVE_GC
	GC_FREE(p);
#else
	free(p);
#endif
}

void* 
resizemem(void *p, size_t size)
{
#ifdef CONSERVATIVE_GC
	p = GC_REALLOC(p, size);
#else
	p = realloc(p, size);
#endif
	if (p == NULL) {
		fatal_error("ran out of memory");
	}

	return p;
}

void
MR_warning(const char *fmt, ...)
{
	va_list args;

	fflush(stdout);		/* in case stdout and stderr are the same */

	fprintf(stderr, "Mercury runtime: ");
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, "\n");

	fflush(stderr);
}

/*
** XXX will need to modify this to kill other threads if MR_THREAD_SAFE
** (and cleanup resources, etc....)
*/

void 
fatal_error(const char *fmt, ...)
{
	va_list args;

	fflush(stdout);		/* in case stdout and stderr are the same */

	fprintf(stderr, "Mercury runtime: ");
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, "\n");

	MR_trace_report(stderr);

	fflush(NULL);		/* flushes all stdio output streams */

	exit(EXIT_FAILURE);
}

	/* See header file for documentation on why we need this function */
void
MR_memcpy(char *dest, const char *src, size_t nbytes)
{
	while (nbytes-- > 0)
		*dest++ = *src++;
}

/*
**  Note that hash_string is actually defined as a macro in mercury_imp.h,
**  if we're using GNU C.  We define it here whether or not we're using
**  gcc, so that users can easily switch between gcc and cc without
**  rebuilding the libraries.
*/

#undef hash_string

int 
hash_string(Word s)
{
	HASH_STRING_FUNC_BODY
}
