/*
** Copyright (C) 1998, 2001 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** All the functions in this file work around problems caused by
** our use of global registers conflicting with the use of registers
** by gcc, or asm fragments in the GNU headers.
*/

#include "mercury_conf.h"
#include "mercury_reg_workarounds.h"
#include <stdlib.h>

#ifdef	MR_CAN_DO_PENDING_IO

#include <sys/types.h>	/* for fd_set and FD_ZERO() */
#include <sys/time.h>	/* for FD_ZERO() */

#ifdef MR_HAVE_UNISTD_H
  #include <unistd.h>	/* for FD_ZERO() */
#endif

void
MR_fd_zero(fd_set *fdset)
{
	FD_ZERO(fdset);
}

#endif /* MR_CAN_DO_PENDING_IO */

/*
** See the header file for documentation on why we need this function.
*/

void
MR_memcpy(void *dest, const void *src, size_t nbytes)
{
	char		*d = (char *) dest;
	const char	*s = (const char *) src;

	while (nbytes-- > 0)
		*d++ = *s++;
}

/*
** See the header file for documentation on why we need this function.
*/

void
MR_memset(void *dest, char c, size_t nbytes)
{
	char		*d = (char *) dest;

	while (nbytes-- > 0)
		*d++ = c;
}
