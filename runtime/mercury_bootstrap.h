/*
** Copyright (C) 1998 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_bootstrap.h
**
** Temporary definitions only needed for bootstrapping and/or
** for backwards compatibility.  All of the definitions here
** will go away eventually, so don't use them!
*/

#ifndef	MERCURY_BOOTSTRAP_H
#define	MERCURY_BOOTSTRAP_H

#define	NONDET_FIXED_SIZE	MR_NONDET_FIXED_SIZE

#define succip			MR_succip
#define hp			MR_hp
#define sp			MR_sp
#define curfr			MR_curfr
#define maxfr			MR_maxfr

#define	detstackvar(n)		MR_stackvar(n)
#define	framevar(n)		MR_framevar((n) + 1)

#define	bt_prevfr(fr)		MR_prevfr_slot(fr)
#define	bt_redoip(fr)		MR_redoip_slot(fr)
#define	bt_redofr(fr)		MR_redofr_slot(fr)
#define	bt_succip(fr)		MR_succip_slot(fr)
#define	bt_succfr(fr)		MR_succfr_slot(fr)
#define	bt_prednm(fr)		MR_prednm_slot(fr)
#define	bt_var(fr, n)		MR_based_framevar(fr, (n) + 1)

#define	curprevfr		bt_prevfr(MR_curfr)
#define	curredoip		bt_redoip(MR_curfr)
#define	curredofr		bt_redofr(MR_curfr)
#define	cursuccip		bt_succip(MR_curfr)
#define	cursuccfr		bt_succfr(MR_curfr)
#define	curprednm		bt_prednm(MR_curfr)

/*
** This should be removed soon - the latest compiler does not generate it.
*/
#define modframe(redoip)						\
			do {						\
				curredoip = redoip;			\
			} while (0)


#define TYPELAYOUT_UNASSIGNED_VALUE	(MR_TYPELAYOUT_UNASSIGNED_VALUE)
#define TYPELAYOUT_UNUSED_VALUE		(MR_TYPELAYOUT_UNUSED_VALUE)
#define TYPELAYOUT_STRING_VALUE		(MR_TYPELAYOUT_STRING_VALUE)
#define TYPELAYOUT_FLOAT_VALUE		(MR_TYPELAYOUT_FLOAT_VALUE)
#define TYPELAYOUT_INT_VALUE		(MR_TYPELAYOUT_INT_VALUE)
#define TYPELAYOUT_CHARACTER_VALUE	(MR_TYPELAYOUT_CHARACTER_VALUE)
#define TYPELAYOUT_UNIV_VALUE		(MR_TYPELAYOUT_UNIV_VALUE)
#define TYPELAYOUT_PREDICATE_VALUE	(MR_TYPELAYOUT_PREDICATE_VALUE)
#define TYPELAYOUT_VOID_VALUE		(MR_TYPELAYOUT_VOID_VALUE)
#define TYPELAYOUT_ARRAY_VALUE		(MR_TYPELAYOUT_ARRAY_VALUE)
#define TYPELAYOUT_TYPEINFO_VALUE	(MR_TYPELAYOUT_TYPEINFO_VALUE)
#define TYPELAYOUT_C_POINTER_VALUE	(MR_TYPELAYOUT_C_POINTER_VALUE)

#endif	/* MERCURY_BOOTSTRAP_H */
