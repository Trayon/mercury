
/*
** Copyright (C) 1997 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
**
** $Id: util.h,v 1.11.4.1 1997-09-29 09:13:36 aet Exp $
*/


#ifndef MB_UTIL_H
#define	MB_UTIL_H

#include	<stdio.h>	/* for fprintf */

typedef int
	MB_Bool;

/*
** Since TRUE and FALSE are not prefixed with `MB_',
** we need to only define them if they are not defined elsewhere.
** Even this might cause trouble, if some other header file included
** after this one defines them as `enum { FALSE, TRUE };'.
** It might be better to just prefix them with `MB_' like everything
** else, even if it does look ugly...
*/
#ifndef TRUE
#define	TRUE		1
#endif
#ifndef FALSE
#define	FALSE		0
#endif

#define	MB_INT_SIZE	(sizeof(int))
#define	MB_FLOAT_SIZE	(sizeof(float))
#define	MB_DOUBLE_SIZE	(sizeof(double))

/*
 *	For debugging. E.g. XXXdebug("Bad integer value", d, some_var).
 *	XXX: We should implement some smarter tracing stuff that allows
 *	us to select a specific module or procedure to trace, or even
 *	a specific trace statement.
 */
#if	defined(DEBUGGING)
#define	XXXdebug(msg, fmt, val) \
	do { \
		fprintf(stderr, "%s: %s = %" #fmt "\n", #msg, #val, val); \
	} while(0)
#define	XXXdebug1(msg) \
	do { \
		fprintf(stderr, "%s\n", #msg); \
	} while(0)
#else
#define	XXXdebug(msg, fmt, val)	do {} while(0)
#define	XXXdebug1(msg) do {} while(0)
#endif	/* DEBUGGING */

void
MB_util_error(const char *fmt, ...);

void
MB_util_print(const char *fmt, ...);

void
MB_fatal(const char* message);

/*
** Returns copy of str. Allocs string which caller must free.
*/
char*
MB_strdup(const char *str);

/*
**
*/
#define	MB_streq(str1,str2) (strcmp((str1),(str2))==0)

/*
** Returns filename with file extension removed. Allocs string which
** caller must free.
*/
char *
MB_drop_extension(const char *filename);

/*
** XXX: STUB
*/
char *
MB_basename(char *filename);

MB_Bool
MB_has_extension(const char *filename, const char* extension);


#endif	/* MB_UTIL_H */
