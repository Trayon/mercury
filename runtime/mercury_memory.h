/*
** Copyright (C) 1994-2000 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_memory.h - 	general memory-allocation related stuff for the
**			Mercury runtime.
**
** This defines the different memory areas used by the Mercury runtime,
** including the det & nondet stacks, the heap (and solutions heap),
** and the fake_reg array for holding Mercury virtual registers.
** It also provides interfaces for constructing new memory zones,
** and for allocating (possibly shared) memory.
*/

#ifndef	MERCURY_MEMORY_H
#define	MERCURY_MEMORY_H

#include "mercury_memory_zones.h"

#include <stddef.h>		/* for size_t */

#include "mercury_types.h"	/* for MR_Word */
#include "mercury_std.h"	/* for bool */
#include "mercury_conf.h"	/* for CONSERVATIVE_GC, etc. */
#ifdef CONSERVATIVE_GC
  #include "gc.h"		/* for GC_FREE */
#endif

/*
** MR_round_up(amount, align) returns `amount' rounded up to the nearest
** alignment boundary.  `align' must be a power of 2.
*/

#define MR_round_up(amount, align)	((((amount) - 1) | ((align) - 1)) + 1)

/* 
** For these functions, see the comments in mercury_memory.c and 
** mercury_engine.c 
*/

extern	void	MR_init_memory(void);
extern	void	MR_init_heap(void);

#ifdef CONSERVATIVE_GC
  extern void	MR_init_conservative_GC(void);
#endif

/*---------------------------------------------------------------------------*/

/*
** MR_malloc() and MR_realloc() are like the standard C
** malloc() and realloc() functions, except that the return values
** are checked.
**
** Structures allocated with MR_malloc() and MR_realloc()
** must NOT contain pointers into GC'ed memory, because those
** pointers will never be traced by the conservative GC.
** Use MR_GC_malloc() or MR_GC_malloc_uncollectable() for that.
**
** MR_NEW(type):
**	allocates space for an object of the specified type.
**
** MR_NEW_ARRAY(type, num):
**	allocates space for an array of objects of the specified type.
**
** MR_RESIZE_ARRAY(ptr, type, num):
**	resizes the array, as with realloc().
**
** MR_malloc(bytes):
**	allocates the given number of bytes.
**
** MR_free(ptr):
**	deallocates the memory.
*/

extern	void	*MR_malloc(size_t n);
extern	void	*MR_realloc(void *old, size_t n);

#define MR_free(ptr) free(ptr)

#define MR_NEW(type) \
	((type *) MR_malloc(sizeof(type)))

#define MR_NEW_ARRAY(type, num) \
	((type *) MR_malloc((num) * sizeof(type)))

#define MR_RESIZE_ARRAY(ptr, type, num) \
	((type *) MR_realloc((ptr), (num) * sizeof(type)))


/*
** These routines all allocate memory that will be traced by the 
** conservative garbage collector, if conservative GC is enabled.
** (For the native GC, you need to call MR_add_root() to register roots.)
** These routines all check for a null return value themselves,
** so the caller need not check.
**
** MR_GC_NEW(type):
**	Allocates space for an object of the specified type.
**	If conservative GC is enabled, the object will be garbage collected
**	when it is no longer referenced from GC-traced memory.
**	Memory allocated with malloc() (or MR_malloc() or MR_NEW())
**	is not GC-traced.  Nor is thread-local storage.
**
** MR_GC_NEW_UNCOLLECTABLE(type):
**	allocates space for an object of the specified type.
**	The object will not be garbage collected even if it is
**	not reference or only referenced from thread-local
**	storage or storage allocated with malloc().
**	It should be explicitly deallocated with MR_GC_free().
**
** MR_GC_NEW_ARRAY(type, num):
**	allocates space for an array of objects of the specified type.
**
** MR_GC_RESIZE_ARRAY(ptr, type, num):
**	resizes the array, as with realloc().
**
** MR_GC_malloc(bytes):
**	allocates the given number of bytes.
**	If conservative GC is enabled, the memory will be garbage collected
**	when it is no longer referenced from GC-traced memory (see above).
**
** MR_GC_malloc_uncollectable(bytes):
**	allocates the given number of bytes.
**	The memory will not be garbage collected, and so
**	it should be explicitly deallocated using MR_GC_free().
**
** MR_GC_free(ptr):
**	deallocates the memory.
*/

extern	void	*MR_GC_malloc(size_t num_bytes);
extern	void	*MR_GC_malloc_uncollectable(size_t num_bytes);
extern	void	*MR_GC_realloc(void *ptr, size_t num_bytes);

#define MR_GC_NEW(type) \
	((type *) MR_GC_malloc(sizeof(type)))

#define MR_GC_NEW_UNCOLLECTABLE(type) \
	((type *) MR_GC_malloc_uncollectable(sizeof(type)))

#define MR_GC_NEW_ARRAY(type, num) \
	((type *) MR_GC_malloc((num) * sizeof(type)))

#define MR_GC_RESIZE_ARRAY(ptr, type, num) \
	((type *) MR_GC_realloc((ptr), (num) * sizeof(type)))

#ifdef CONSERVATIVE_GC
  #define MR_GC_free(ptr) GC_FREE(ptr)
#else
  #define MR_GC_free(ptr) free(ptr)
#endif

/*---------------------------------------------------------------------------*/

/*
** MR_copy_string makes a copy of the given string,
** using memory allocated with MR_malloc().
*/

char	*MR_copy_string(const char *s);

/*---------------------------------------------------------------------------*/

/*
** `MR_unit' is the size of the minimum unit of memory we allocate (in bytes).
** `MR_page_size' is the size of a single page of memory.
*/

extern	size_t          MR_unit;
extern	size_t          MR_page_size;

/*---------------------------------------------------------------------------*/

/*
** Users need to call MR_add_root() for any global variable which
** contains pointers to the Mercury heap.  This information is only
** used for agc grades.
*/
#ifdef NATIVE_GC
  #define MR_add_root(root_ptr, type_info) \
	MR_agc_add_root((root_ptr), (type_info))
#else
  #define MR_add_root(root_ptr, type_info) /* nothing */
#endif

/*---------------------------------------------------------------------------*/

#endif /* not MERCURY_MEMORY_H */
