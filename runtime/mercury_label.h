/*
** Copyright (C) 1994-1998, 2000-2001 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_label.h defines the interface to the label table, which is a pair of
** hash tables, one mapping from procedure names and the other from
** addresses to label information.
** The label information includes the name, address of the code, and
** layout information for that label.
*/

#ifndef	MERCURY_LABEL_H
#define	MERCURY_LABEL_H

#include "mercury_types.h"		/* for `MR_Code *' */
#include "mercury_dlist.h" 		/* for `List' */
#include "mercury_stack_layout.h"	/* for `MR_Proc_Layout' etc */

#if     defined(NATIVE_GC) || defined(MR_DEBUG_GOTOS)
  #define	MR_NEED_ENTRY_LABEL_ARRAY
#endif

#if     defined(MR_NEED_ENTRY_LABEL_ARRAY) || defined(MR_MPROF_PROFILE_CALLS)
  #define	MR_NEED_ENTRY_LABEL_INFO
#endif

/*
** This struct records information about entry labels. Elements in the
** entry label array are of this type. The table is sorted on address,
** to allow the garbage collector to locate the entry label of the procedure 
** to which an internal label belongs by a variant of binary search.
**
** The name field is needed only for low-level debugging.
*/

typedef struct s_entry {
	const MR_Code		*e_addr;
	const MR_Proc_Layout	*e_layout;
	const char		*e_name;
} MR_Entry;

/*
** This struct records information about internal (non-entry) labels.
** The internal label table is organized as a hash table, with the address
** being the key.
**
** The name field is needed only for low-level debugging.
*/

typedef struct s_internal {
	const MR_Code		*i_addr;
	const MR_Label_Layout	*i_layout;
	const char		*i_name;
} MR_Internal;

extern	void		MR_do_init_label_tables(void);

#ifdef	MR_NEED_ENTRY_LABEL_INFO
  extern void		MR_insert_entry_label(const char *name, MR_Code *addr,
				const MR_Proc_Layout *entry_layout);
#else
  #define MR_insert_entry_label(n, a, l)	/* nothing */
#endif	/* not MR_NEED_ENTRY_LABEL_INFO */

#ifdef	MR_NEED_ENTRY_LABEL_ARRAY
  extern MR_Entry	*MR_prev_entry_by_addr(const MR_Code *addr);
#endif	/* MR_NEED_ENTRY_LABEL_ARRAY */

extern	void		MR_insert_internal_label(const char *name,
				MR_Code *addr,
				const MR_Label_Layout *label_layout);
extern	MR_Internal	*MR_lookup_internal_by_addr(const MR_Code *addr);
extern	void		MR_process_all_internal_labels(void f(const void *));

#endif /* not MERCURY_LABEL_H */
