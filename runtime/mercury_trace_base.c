/*
INIT mercury_sys_init_trace
ENDINIT
*/
/*
** Copyright (C) 1997-2001 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_trace_base.c implements the interface between the main part
** of the runtime system (mainly mercury_wrapper.c) and the part of the
** tracing subsystem that has to be present even if no module in the program
** is compiled with execution tracing.
**
** Main author: Zoltan Somogyi.
*/

#include "mercury_imp.h"
#include "mercury_trace_base.h"
#include "mercury_engine.h"
#include "mercury_wrapper.h"
#include "mercury_misc.h"
#include "mercury_signal.h"	/* for MR_setup_signal() */
#include <signal.h>		/* for SIGINT */
#include <stdio.h>
#include <errno.h>

#ifdef HAVE_UNISTD_H
  #include <unistd.h>		/* for the write system call */
#endif

/*
** Do we want to use the debugger within this process, or do want to use
** the Opium-style trace analyzer debugger implemented by an external process.
** This variable is set in mercury_wrapper.c and never modified afterwards.
*/

MR_Trace_Type	MR_trace_handler = MR_TRACE_INTERNAL;

/*
** Compiler generated tracing code will check whether MR_trace_enabled is true,
** before calling MR_trace.
** MR_trace_enabled should keep the same value throughout the execution of
** the entire program after being set in mercury_wrapper.c. There is one
** exception to this: the Mercury routines called as part of the functionality
** of the tracer itself (e.g. the term browser) should always be executed
** with MR_trace_enabled set to FALSE.
*/

bool		MR_trace_enabled = FALSE;

/*
** MR_trace_call_seqno counts distinct calls. The prologue of every
** procedure assigns the current value of this counter as the sequence number
** of that invocation and increments the counter. This is the only way that
** MR_trace_call_seqno is modified.
**
** MR_trace_call_depth records the current depth of the call tree. The prologue
** of every procedure assigns the current value of this variable plus one
** as the depth of that invocation. Just before making a call, the caller
** will set MR_trace_call_depth to its own remembered depth value. 
** These are the only ways in which MR_trace_call_depth is modified.
**
** Although neither MR_trace_call_seqno nor MR_trace_call_depth are used
** directly in this module, the seqno and depth arguments of MR_trace
** always derive their values from the saved values of these two global
** variables.
*/

MR_Unsigned	MR_trace_call_seqno = 0;
MR_Unsigned	MR_trace_call_depth = 0;

/*
** MR_trace_event_number is a simple counter of events. This is used in
** two places: here, for display to the user and for skipping a given number
** of events, and when printing an abort message, so that the programmer
** can zero in on the source of the problem more quickly.
*/

MR_Unsigned	MR_trace_event_number = 0;

/*
** MR_trace_from_full is a boolean that is set before every call;
** it states whether the caller is being deep traced, or only shallow
** traced. If the called code is shallow traced, it will generate
** interface trace events only if MR_trace_from_full is true.
** (It will never generate internal events.) If the called code is deep
** traced, it will always generate all trace events, external and internal,
** regardless of the setting of this variable on entry.
**
** The initial value is set to TRUE to allow the programmer to gain
** control in the debugger when main/2 is called.
*/

bool		MR_trace_from_full = TRUE;

/*
** I/O tabling is documented in library/table_builtin.m
*/

MR_IoTablingPhase	MR_io_tabling_phase = MR_IO_TABLING_UNINIT;
bool			MR_io_tabling_enabled = FALSE;
MR_TableNode		MR_io_tabling_pointer = { 0 };
MR_Unsigned		MR_io_tabling_counter = 0;
MR_Unsigned		MR_io_tabling_counter_hwm = 0;
MR_Unsigned		MR_io_tabling_start = 0;
MR_Unsigned		MR_io_tabling_end = 0;

#ifdef	MR_TRACE_HISTOGRAM

int		*MR_trace_histogram_all = NULL;
int		*MR_trace_histogram_exp = NULL;
int		MR_trace_histogram_max  = 0;
int		MR_trace_histogram_hwm  = 0;

#define	MR_TRACE_HISTOGRAM_FILENAME	".mercury_histogram"

#endif

const char	*MR_port_names[] =
{
	"CALL",
	"EXIT",
	"REDO",
	"FAIL",
	"EXCP",
	"COND",
	"THEN",
	"ELSE",
	"NEGE",
	"NEGS",
	"NEGF",
	"DISJ",
	"SWTC",
	"FRST",
	"LATR",
	"NONE",
};

MR_Code *
MR_trace(const MR_Label_Layout *layout)
{
	if (! MR_trace_enabled) {
		return NULL;
	}

	return (*MR_trace_func_ptr)(layout);
}

void
MR_tracing_not_enabled(void)
{
	MR_fatal_error("This executable is not set up for debugging.\n"
		"Rebuild the <main>_init.c file, "
		"and give the `-t' (or `--trace')\n"
		"option to c2init when you do so.  "
		"If you are using mmake, you\n"
		"can do this by including "
		"`-t' (or `--trace') in C2INITFLAGS.\n"
		"For further details, please see the \"Debugging\" chapter "
		"of the\n"
		"Mercury User's Guide.\n");
}

MR_Code *
MR_trace_fake(const MR_Label_Layout *layout)
{
	MR_tracing_not_enabled();
	/*NOTREACHED*/
	return NULL;
}

#ifdef	MR_TABLE_DEBUG
bool	MR_saved_tabledebug;
#endif

void
MR_trace_init(void)
{
#ifdef	MR_TABLE_DEBUG
	/*
	** We don't want to see any tabling debugging messages from
	** initialization code about entering and leaving commit goals.
	*/

	MR_saved_tabledebug = MR_tabledebug;
	MR_tabledebug = FALSE;
#endif

#ifdef MR_USE_EXTERNAL_DEBUGGER
	if (MR_trace_handler == MR_TRACE_EXTERNAL) {
		if (MR_address_of_trace_init_external != NULL) {
			MR_address_of_trace_init_external();
		} else {
			MR_tracing_not_enabled();
		}
	}
#endif
}

void
MR_trace_final(void)
{
#ifdef MR_USE_EXTERNAL_DEBUGGER
	if (MR_trace_handler == MR_TRACE_EXTERNAL) {
		if (MR_address_of_trace_final_external != NULL) {
			MR_address_of_trace_final_external();
		} else {
			MR_tracing_not_enabled();
		}
	}
#endif
}

void
MR_trace_start(bool enabled)
{
	MR_trace_event_number = 0;
	MR_trace_call_seqno = 0;
	MR_trace_call_depth = 0;
	MR_trace_from_full = TRUE;
	MR_trace_enabled = enabled;

#ifdef	MR_TABLE_DEBUG
	/*
	** Restore the value saved by MR_trace_init.
	*/

	MR_tabledebug = MR_saved_tabledebug;
#endif

	/*
	** Install the SIGINT signal handler.
	** We only do this if tracing is enabled, and only
	** for the internal debugger.  (This is a bit conservative:
	** it might work fine for the external debugger too,
	** but I'm just not certain of that.)
	*/
	if (enabled &&
		MR_address_of_trace_interrupt_handler != NULL &&
		MR_trace_handler == MR_TRACE_INTERNAL)
	{
		MR_setup_signal(SIGINT,
			(MR_Code *) MR_address_of_trace_interrupt_handler,
			FALSE, "mdb: cannot install SIGINT signal handler");
	}
}

void
MR_trace_end(void)
{
	MR_trace_enabled = FALSE;
}

void
MR_trace_report(FILE *fp)
{
	if (MR_trace_event_number > 0) {
		/*
		** This means that the executable was compiled with tracing,
		** which implies that the user wants trace info on abort.
		*/

		fprintf(fp, "Last trace event was event #%ld.\n",
			(long) MR_trace_event_number);

#ifdef	MR_TRACE_HISTOGRAM
		{
			FILE	*hfp;

			hfp = fopen(MR_TRACE_HISTOGRAM_FILENAME, "w");
			if (hfp != NULL) {
				MR_trace_print_histogram(hfp, "All-inclusive",
					MR_trace_histogram_all,
					MR_trace_histogram_hwm);
				if (fclose(hfp) == 0) {
					fprintf(fp, "Event histogram put into "
						"file `%s'.\n",
						MR_TRACE_HISTOGRAM_FILENAME);
				} else {
					fprintf(fp, "Cannot put event "
						"histogram into `%s': %s."
						MR_TRACE_HISTOGRAM_FILENAME,
						strerror(errno));
				}
			} else {
				fprintf(fp, "Cannot open `%s': %s.\n"
					MR_TRACE_HISTOGRAM_FILENAME,
					strerror(errno));
			}
		}
#endif	/* MR_TRACE_HISTOGRAM */
	}
}

void
MR_trace_report_raw(int fd)
{
	char	buf[80];	/* that ought to be more than long enough */

	if (MR_trace_event_number > 0) {
		/*
		** This means that the executable was compiled with tracing,
		** which implies that the user wants trace info on abort.
		*/

		sprintf(buf, "Last trace event was event #%ld.\n",
			(long) MR_trace_event_number);
		write(fd, buf, strlen(buf));
	}
}

static	MR_Word		MR_trace_exception_value = (MR_Word) NULL;

void
MR_trace_set_exception_value(MR_Word exception)
{
	MR_trace_exception_value = exception;
}

MR_Word
MR_trace_get_exception_value(void)
{
	return MR_trace_exception_value;
}

#ifdef	MR_TRACE_HISTOGRAM

void
MR_trace_print_histogram(FILE *fp, const char *which, int *histogram, int max)
{
	int	i;

	fprintf(fp, "%s histogram\n", which);
	for (i = 1; i <= max; i++) {
		fprintf(fp, "depth %4d: %10d", i, histogram[i]);
		if (i + 1 <= max && histogram[i] != 0) {
			fprintf(fp, ", branching factor %7.2f\n",
				(float) histogram[i+1] / (float) histogram[i]);
		} else {
			fprintf(fp, "\n");
		}
	}
}

#endif	/* MR_TRACE_HISTOGRAM */

MR_define_extern_entry(MR_do_trace_redo_fail_shallow);
MR_define_extern_entry(MR_do_trace_redo_fail_deep);

MR_BEGIN_MODULE(MR_trace_labels_module)
	MR_init_entry_ai(MR_do_trace_redo_fail_shallow);
	MR_init_entry_ai(MR_do_trace_redo_fail_deep);
MR_BEGIN_CODE

MR_define_entry(MR_do_trace_redo_fail_shallow);
	/*
	** If this code ever needs changing, you may also need to change
	** the code in extras/exceptions/exception.m similarly.
	*/
	if (MR_redo_fromfull_framevar(MR_redofr_slot(MR_curfr)))
	{
		MR_Code	*MR_jumpaddr;
		MR_save_transient_registers();
		MR_jumpaddr = MR_trace((const MR_Label_Layout *)
			MR_redo_layout_framevar(MR_redofr_slot(MR_curfr)));
		MR_restore_transient_registers();
		if (MR_jumpaddr != NULL) {
			MR_GOTO(MR_jumpaddr);
		}
	}
	MR_fail();

MR_define_entry(MR_do_trace_redo_fail_deep);
#if 0
	/* For use in case this ever needs to be debugged again. */
	printf("MR_curfr = %p\n", MR_curfr);
	printf("MR_redofr_slot(MR_curfr) = %p\n", MR_redofr_slot(MR_curfr));
	printf("&MR_redo_layout_framevar(MR_redofr_slot(MR_curfr) = %p\n",
		&MR_redo_layout_framevar(MR_redofr_slot(MR_curfr)));
	printf("MR_redo_layout_framevar(MR_redofr_slot(MR_curfr) = %p\n",
		MR_redo_layout_framevar(MR_redofr_slot(MR_curfr)));
#endif
	/*
	** If this code ever needs changing, you may also need to change
	** the code in library/exception.m similarly.
	*/
	{
		MR_Code	*MR_jumpaddr;
		MR_save_transient_registers();
		MR_jumpaddr = MR_trace((const MR_Label_Layout *)
			MR_redo_layout_framevar(MR_redofr_slot(MR_curfr)));
		MR_restore_transient_registers();
		if (MR_jumpaddr != NULL) {
			MR_GOTO(MR_jumpaddr);
		}
	}
	MR_fail();

MR_END_MODULE

/* forward decls to suppress gcc warnings */
void mercury_sys_init_trace_init(void);
void mercury_sys_init_trace_init_type_tables(void);
#ifdef	MR_DEEP_PROFILING
void mercury_sys_init_trace_write_out_proc_statics(FILE *fp);
#endif

void mercury_sys_init_trace_init(void)
{
	MR_trace_labels_module();
}

void mercury_sys_init_trace_init_type_tables(void)
{
	/* no types to register */
}

#ifdef	MR_DEEP_PROFILING
void mercury_sys_init_trace_write_out_proc_statics(FILE *fp)
{
	/* no proc_statics to write out */
}
#endif
