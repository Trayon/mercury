/*
 *	$Id: mbi.c,v 1.1 1997-01-24 07:10:19 aet Exp $
 *
 *	Copyright: The University of Melbourne, 1996
 */

/* Imports */
#include	<stdlib.h>
#include	<stdio.h>
#include	<unistd.h>

#include	<mbi.h>


/* Exports */
int
heapsize	= 0;


/* Local declarations */
static void
usage(void);

static char*
program_name	= NULL;

/* Implementation */

void
main(int argc, char* argv[])
{
	char	c;

	/* We do this in case we change the program name. */
	program_name = argv[0];

	/* Don't use default error messages from getopt() */
	opterr = 0;

	/* Read options */
	while ((c = getopt(argc,argv,"h:")) != EOF)
	{
		switch (c) 
		{
		case 'h':
			heapsize = atoi(optarg);
			if (heapsize <= 0)
				usage();
			break;
			
		default:
			usage();
			break;
		}
	}

	exit(EXIT_SUCCESS);
}

void
usage()
{
	fprintf(stderr, "Usage: %s [-h heapsize] <bytecode files>\n",
		program_name
	);
	exit(EXIT_FAILURE);
}

