/* runtime/conf.h.  Generated automatically by configure.  */
/*
** Copyright (C) 1995-1997 University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** conf.h.in -
**	Various configuration parameters, determined automatically by
**	the auto-configuration script.
*/

#ifndef CONF_H
#define CONF_H

/*
** WORD_TYPE: the base type for the definition of Word.
** This must be a C integral type (e.g. int, long, or long long)
** without any explicit signedness.
** It ought to be the same size as the machine's general-purpose registers.
*/
#define	WORD_TYPE long

/*
** LOW_TAG_BITS: an integer, specifying the number of low-order tag bits
** we can use.  Normally this is the base-2 log of the word size in bytes.
*/
#define	LOW_TAG_BITS 3

/*
** BOXED_FLOAT: defined if double precision floats might not fit
** in a Word, and hence must be boxed.
** Note that when bootstrapping from the source distribution,
** we initially build things without BOXED_FLOAT even on machines
** for which sizeof(Float) <= sizeof(Word).
** Conversely if BOXED_FLOAT is undefined, it implies that
** sizeof(Float) <= sizeof(Word).
*/
/* #undef	BOXED_FLOAT */

/*
** The following macros are defined iff the corresponding header file
** is available:
**
**	HAVE_SYS_SIGINFO	we have <sys/siginfo.h>
**	HAVE_UCONTEXT		we have <ucontext.h>
**	HAVE_SYS_UCONTEXT	we have <sys/ucontext.h>
**	HAVE_ASM_SIGCONTEXT	we have <asm/sigcontext.h> (e.g. i386 Linux)
**	HAVE_SYS_TIME		we have <sys/time.h>
**	HAVE_SYS_PARAM		we have <sys/param.h>
*/
#define	HAVE_SYS_SIGINFO 1
#define	HAVE_UCONTEXT 1
/* #undef	HAVE_SYS_UCONTEXT */
/* #undef	HAVE_ASM_SIGCONTEXT */
#define	HAVE_SYS_TIME 1
#define	HAVE_SYS_PARAM 1

/*
** The following macros are defined iff the corresponding function or
** system call is available:
**
**	HAVE_SYSCONF     	we have the sysconf() system call.
**	HAVE_SIGACTION		we have the sigaction() sysstem call.
**	HAVE_GETPAGESIZE 	we have the getpagesize() system call.
**	HAVE_MPROTECT    	we have the mprotect() system call.
**	HAVE_MEMALIGN    	we have the memalign() function.
**	HAVE_STRERROR    	we have the strerror() function.
**	HAVE_SETITIMER   	we have the setitimer() function.
*/
#define	HAVE_SYSCONF 1
#define	HAVE_SIGACTION 1
#define	HAVE_GETPAGESIZE 1
/* #undef	HAVE_MEMALIGN */
#define	HAVE_MPROTECT 1
#define	HAVE_STRERROR 1
#define	HAVE_SETITIMER 1

/*
** RETSIGTYPE: the return type of signal handlers.
** Either `int' or `void'.
*/
#define	RETSIGTYPE void

/*
** We use mprotect() and signals to catch stack and heap overflows.
** In order to detect such overflows, we need to be able to figure
** out what address we were trying to read from or write to when we
** get a SIGSEGV signal.  This is a fairly non-portable thing, so
** it has to be done differently on different systems.
** The following macros specify whether we can do it and if so, how.
**
**	HAVE_SIGINFO		defined iff we can _somehow_ figure out the
**				fault address for SIGSEGVs.
**	HAVE_SIGINFO_T		defined iff we can figure out the
**				fault address for SIGSEGVs using sigaction
**				and siginfo_t.
**	HAVE_SIGCONTEXT_STRUCT	defined iff normal signal handlers are given
**				sigcontext_struct arguments that we can use to
**				figure out the fault address for SIGSEGVs.
*/
#define	HAVE_SIGINFO 1
#define	HAVE_SIGINFO_T 1
/* #undef	HAVE_SIGCONTEXT_STRUCT */

/*
** For debugging purposes, if we get a fatal signal, we print out the
** program counter (PC) at which the signal occurred.
**
** PC_ACCESS, PC_ACCESS_GREG: the way to access the saved PC in ucontexts.
**
** If PC_ACCESS_GREG is defined, then PC_ACCESS specifies an index into
** the `gregs' (general registers) array, which is a field of the `ucontext'
** struct.  Otherwise, if PC_ACCESS is defined then it is a field name
** in the `ucontext' struct.  If PC_ACCESS is not defined, then we don't
** have any way of getting the saved PC.
*/
#define	PC_ACCESS sc_pc
/* #undef	PC_ACCESS_GREG */

/*
** SIGACTION_FIELD: the name of the field in the sigaction struct
** (either sa_handler or sa_sigaction).  Defined only if HAVE_SIGACTION
** is defined.
*/
#define	SIGACTION_FIELD sa_sigaction

/*
** PARALLEL: defined iff we are configuring for parallel execution.
** (This is work in progress... parallel execution is not yet supported.)
*/
/* #undef	PARALLEL */

/*
** The bytecode files represent floats in 64-bit IEEE format.
**
** MR_FLOAT_IS_64_BITS: defined iff the C type `float' is exactly 64 bits.
** MR_DOUBLE_IS_64_BITS: defined iff the C type `double' is exactly 64 bits.
** MR_LONG_DOUBLE_IS_64_BITS: defined iff the C type `long double' is exactly
** 64-bits.
**
** XXX why not just have a single MR_64_BIT_FLOAT_TYPE macro,
** defined to `float', `double', or `long double' as appropriate?
*/
/* #undef	MR_FLOAT_IS_64_BIT */
#define	MR_DOUBLE_IS_64_BIT 1
#define	MR_LONG_DOUBLE_IS_64_BIT 1

/*
** The following macros specify the ordering of bytes within
** are used by the bytecode compiler and the
** bytecode interpreter when writing/reading floats from/to bytecode files.
**
** MR_BIG_ENDIAN: defined iff the host system is big-endian.
** MR_LITTLE_ENDIAN: defined iff the host system is little-endian.
** (Wierd-endian systems should define neither of these.) 
*/
/* #undef	MR_BIG_ENDIAN */
#define	MR_LITTLE_ENDIAN 1

/*
** The following macro specifies whether the non-ANSI, non-POSIX,
** but usually available standard library function `tempnam' is
** available.
*/
#define	IO_HAVE_TEMPNAM 1

#endif /* CONF_H */
