/*
** Copyright (C) 1998-2000 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** Debugging support for the accurate garbage collector.
*/

#include "mercury_imp.h"
#include "mercury_layout_util.h"
#include "mercury_deep_copy.h"
#include "mercury_agc_debug.h"

#ifdef NATIVE_GC

/*
** Function prototypes.
*/
static	void	dump_long_value(MR_Long_Lval locn, MemoryZone *heap_zone,
			MR_Word * stack_pointer, MR_Word *current_frame,
			bool do_regs);
static	void	dump_short_value(MR_Short_Lval locn, MemoryZone *heap_zone,
			Word * stack_pointer, Word *current_frame,
			bool do_regs);
static  void	dump_live_variables(const MR_Stack_Layout_Label *layout, 
			MemoryZone *heap_zone, bool top_frame,
			Word *stack_pointer, Word *current_frame);

/*---------------------------------------------------------------------------*/


void
MR_agc_dump_roots(MR_RootList roots)
{
#ifdef NATIVE_GC
	MR_Word	saved_regs[MAX_FAKE_REG];

	fflush(NULL);
	fprintf(stderr, "Dumping roots\n");

  #ifdef MR_DEBUG_AGC_PRINT_VARS
	while (roots != NULL) {


		/*
		** Restore the registers, because we need to save them
		** to a more permanent backing store (we are going to
		** call Mercury soon, and we don't want it messing with
		** the saved registers).
		*/
		restore_registers();
		MR_copy_regs_to_saved_regs(MAX_FAKE_REG, saved_regs);

		MR_hp = MR_ENGINE(debug_heap_zone->min);
		MR_virtual_hp = MR_ENGINE(debug_heap_zone->min);

		fflush(NULL);
		MR_write_variable(roots->type_info, *roots->root);
		fflush(NULL);
		fprintf(stderr, "\n");

		MR_copy_saved_regs_to_regs(MAX_FAKE_REG, saved_regs);
		save_registers();
		roots = roots->next;
	}
  #endif /* MR_DEBUG_AGC_PRINT_VARS */
#endif /* NATIVE_GC */
}

void
MR_agc_dump_nondet_stack_frames(MR_Internal *label, MemoryZone *heap_zone,
	Word *stack_pointer, Word *current_frame, Word *max_frame)
{
	Code *success_ip;
	int frame_size;
	bool registers_valid;

	while (max_frame > MR_nondet_stack_trace_bottom) {

		registers_valid = (max_frame == current_frame);

		frame_size = max_frame - MR_prevfr_slot(max_frame);
		if (frame_size == MR_NONDET_TEMP_SIZE) {
			fprintf(stderr, "%p: nondet temp\n", max_frame);
			fprintf(stderr, " redoip: ");
			fflush(NULL);
			printlabel(MR_redoip_slot(max_frame));
			fflush(NULL);
			fprintf(stderr, " redofr: %p\n",
				MR_redofr_slot(max_frame));

			label = MR_lookup_internal_by_addr(MR_redoip_slot(
					max_frame));

			if (label && label->i_layout) {
				dump_live_variables(label->i_layout, heap_zone,
					registers_valid, stack_pointer,
					MR_redofr_slot(max_frame));
			}

		} else if (frame_size == MR_DET_TEMP_SIZE) {
			fprintf(stderr, "%p: nondet temp\n", max_frame);
			fprintf(stderr, " redoip: ");
			fflush(NULL);
			printlabel(MR_redoip_slot(max_frame));
			fflush(NULL);
			fprintf(stderr, " redofr: %p\n",
				MR_redofr_slot(max_frame));
			fprintf(stderr, " detfr:  %p\n",
				MR_detfr_slot(max_frame));

			label = MR_lookup_internal_by_addr(MR_redoip_slot(
					max_frame));

			if (label && label->i_layout) {
				dump_live_variables(label->i_layout, heap_zone,
					registers_valid,
					MR_detfr_slot(max_frame), max_frame);
				/* 
				** XXX should max_frame above be
				** MR_redoip_slot(max_frame) instead?
				*/
			}

		} else {
			fprintf(stderr, "%p: nondet ordinary\n", max_frame);
			fprintf(stderr, " redoip: ");
			fflush(NULL);
			printlabel(MR_redoip_slot(max_frame));
			fflush(NULL);
			fprintf(stderr, " redofr: %p\n",
				MR_redofr_slot(max_frame));
			fprintf(stderr, " succip: ");
			fflush(NULL);
			printlabel(MR_succip_slot(max_frame));
			fflush(NULL);
			fprintf(stderr, " succfr: %p\n",
				MR_succfr_slot(max_frame));
		
			/* XXX ??? */
			label = MR_lookup_internal_by_addr(MR_redoip_slot(
					max_frame));

			if (label && label->i_layout) {
				dump_live_variables(label->i_layout, heap_zone,
					registers_valid, stack_pointer,
					MR_redofr_slot(max_frame));
				fprintf(stderr, " this label: %s\n", label->i_name);
			}
		}

		max_frame = MR_prevfr_slot(max_frame);
	}

    	/* XXX Lookup the address (redoip?) and dump the variables */

	fflush(NULL);
}

void
MR_agc_dump_stack_frames(MR_Internal *label, MemoryZone *heap_zone,
	MR_Word *stack_pointer, MR_Word *current_frame)
{
#ifdef NATIVE_GC
	MR_Word saved_regs[MAX_FAKE_REG];
	int i, short_var_count, long_var_count;
	const MR_Stack_Layout_Vars *vars;
	MR_Word *type_params, type_info, value;
	MR_Stack_Layout_Entry *entry_layout;
	const MR_Stack_Layout_Label *layout;
	const MR_Code *success_ip;
	bool top_frame = TRUE;

	layout = label->i_layout;
	success_ip = label->i_addr;
	entry_layout = layout->MR_sll_entry;

	/* 
	** For each stack frame... 
	*/

	while (MR_DETISM_DET_STACK(entry_layout->MR_sle_detism)) {
		if (label->i_name != NULL) {
			fprintf(stderr, "    label: %s\n", label->i_name);
		} else {
			fprintf(stderr, "    label: unknown\n");
		}

		if (success_ip == MR_stack_trace_bottom) {
			break;
		}

		dump_live_variables(layout, heap_zone, top_frame,
			stack_pointer, current_frame);
		/* 
		** Move to the next stack frame.
		*/
		{
			MR_Long_Lval            location;
			MR_Long_Lval_Type            type;
			int                     number;

			location = entry_layout->MR_sle_succip_locn;
			type = MR_LONG_LVAL_TYPE(location);
			number = MR_LONG_LVAL_NUMBER(location);
			if (type != MR_LONG_LVAL_TYPE_STACKVAR) {
				fatal_error("can only handle stackvars");
			}
			                                
			success_ip = (MR_Code *) 
				MR_based_stackvar(stack_pointer, number);
			stack_pointer = stack_pointer - 
				entry_layout->MR_sle_stack_slots;
			label = MR_lookup_internal_by_addr(success_ip);
		}

		top_frame = FALSE;
		layout = label->i_layout;
		
		if (layout != NULL) {
			entry_layout = layout->MR_sll_entry;
		}
	}
#endif /* NATIVE_GC */
}

static void
dump_live_variables(const MR_Stack_Layout_Label *layout, 
		MemoryZone *heap_zone, bool top_frame,
		Word *stack_pointer, Word *current_frame)
{
	int short_var_count, long_var_count, i;
	const MR_Stack_Layout_Vars *vars;
	MR_TypeInfo type_info;
	MR_Word value;
	MR_TypeInfoParams type_params;
        MR_Word saved_regs[MAX_FAKE_REG];
        MR_Word *current_regs;

	vars = &(layout->MR_sll_var_info);
	short_var_count = MR_short_desc_var_count(vars);
	long_var_count = MR_long_desc_var_count(vars);

	/*
	** For the top stack frame, we should pass a pointer to
	** a filled-in saved_regs instead of NULL. For other stack
	** frames, passing NULL is fine, since output arguments are
	** not live yet for any call except the top one.
	*/
	restore_registers();
	MR_copy_regs_to_saved_regs(MAX_FAKE_REG, saved_regs);
	if (top_frame) {
		current_regs = saved_regs;
	} else {
		current_regs = NULL;
	}
	type_params = MR_materialize_typeinfos_base(vars,
		current_regs, stack_pointer, current_frame);

	for (i = 0; i < long_var_count; i++) {
		fprintf(stderr, "%-12s\t", "");
		MR_print_proc_id(stderr, layout->MR_sll_entry);

		dump_long_value(MR_long_desc_var_locn(vars, i), heap_zone,
			stack_pointer, current_frame, top_frame);
		fprintf(stderr, "\n");
		fflush(NULL);

#ifdef MR_DEBUG_AGC_PRINT_VARS
		/*
		** Call Mercury but use the debugging heap. 
		*/

		MR_hp = MR_ENGINE(debug_heap_zone->min);
		MR_virtual_hp = MR_ENGINE(debug_heap_zone->min);

		if (MR_get_type_and_value_base(vars, i,
				current_regs, stack_pointer,
				current_frame, type_params,
				&type_info, &value)) {
			printf("\t");
			MR_write_variable(type_info, value);
			printf("\n");
		}

#endif	/* MR_DEBUG_AGC_PRINT_VARS */

		fflush(NULL);
	}

	for (; i < short_var_count; i++) {
		fprintf(stderr, "%-12s\t", "");
		MR_print_proc_id(stderr, layout->MR_sll_entry);

		dump_short_value(MR_short_desc_var_locn(vars, i), heap_zone,
			stack_pointer, current_frame, top_frame);
		fprintf(stderr, "\n");
		fflush(NULL);
		
#ifdef MR_DEBUG_AGC_PRINT_VARS
		/*
		** Call Mercury but use the debugging heap. 
		*/

		MR_hp = MR_ENGINE(debug_heap_zone->min);
		MR_virtual_hp = MR_ENGINE(debug_heap_zone->min);

		if (MR_get_type_and_value_base(vars, i,
				current_regs, stack_pointer,
				current_frame, type_params,
				&type_info, &value)) {
			printf("\t");
			MR_write_variable(type_info, value);
			printf("\n");
		}

#endif	/* MR_DEBUG_AGC_PRINT_VARS */

		fflush(NULL);
	}


	MR_copy_saved_regs_to_regs(MAX_FAKE_REG, saved_regs);
	save_registers();
	free(type_params);
}

static void
dump_long_value(MR_Long_Lval locn, MemoryZone *heap_zone, 
	MR_Word *stack_pointer, MR_Word *current_frame, bool do_regs)
{
#ifdef NATIVE_GC
	int	locn_num;
	MR_Word	value = 0;
	int	difference;
	bool 	have_value = FALSE;

	locn_num = MR_LONG_LVAL_NUMBER(locn);
	switch (MR_LONG_LVAL_TYPE(locn)) {
		case MR_LONG_LVAL_TYPE_R:
			if (do_regs) {
				value = virtual_reg(locn_num);
				have_value = TRUE;
				fprintf(stderr, "r%d\t", locn_num);
			} else {
				fprintf(stderr, "r%d (invalid)\t", locn_num);
			}
			break;

		case MR_LONG_LVAL_TYPE_F:
			fprintf(stderr, "f%d\t", locn_num);
			break;

		case MR_LONG_LVAL_TYPE_STACKVAR:
			value = MR_based_stackvar(stack_pointer, locn_num);
			have_value = TRUE;
			fprintf(stderr, "stackvar%d", locn_num);
			break;

		case MR_LONG_LVAL_TYPE_FRAMEVAR:
			value = MR_based_framevar(current_frame, locn_num);
			have_value = TRUE;
			fprintf(stderr, "framevar%d", locn_num);
			break;

		case MR_LONG_LVAL_TYPE_SUCCIP:
			fprintf(stderr, "succip");
			break;

		case MR_LONG_LVAL_TYPE_MAXFR:
			fprintf(stderr, "maxfr");
			break;

		case MR_LONG_LVAL_TYPE_CURFR:
			fprintf(stderr, "curfr");
			break;

		case MR_LONG_LVAL_TYPE_HP:
			fprintf(stderr, "hp");
			break;

		case MR_LONG_LVAL_TYPE_SP:
			fprintf(stderr, "sp");
			break;

		case MR_LONG_LVAL_TYPE_INDIRECT:
			fprintf(stderr, "offset %d from ",
				MR_LONG_LVAL_INDIRECT_OFFSET(locn_num));
			/* XXX Tyson will have to complete this */
			/* based on what he wants this function to do */

		case MR_LONG_LVAL_TYPE_UNKNOWN:
			fprintf(stderr, "unknown");
			break;

		default:
			fprintf(stderr, "LONG DEFAULT");
			break;
	}
	if (have_value) {
		if (value >= (Word) heap_zone->min && 
				value < (Word) heap_zone->hardmax) {
			difference = (Word *) value - (Word *) heap_zone->min;
			fprintf(stderr, "\thp[%d]\t(%lx)", difference,
				(long) value);
		} else {
			fprintf(stderr, "\t       \t(%lx)", (long) value);
		}
	}
#endif /* NATIVE_GC */
}

static void
dump_short_value(MR_Short_Lval locn, MemoryZone *heap_zone, Word *stack_pointer,
	Word *current_frame, bool do_regs)
{
#ifdef NATIVE_GC
	int	locn_num;
	Word	value = 0;
	int	difference;
	bool 	have_value = FALSE;

	locn_num = (int) locn >> MR_SHORT_LVAL_TAGBITS;
	switch (MR_SHORT_LVAL_TYPE(locn)) {
		case MR_SHORT_LVAL_TYPE_R:
			if (do_regs) {
				value = virtual_reg(locn_num);
				have_value = TRUE;
				fprintf(stderr, "r%d\t", locn_num);
			} else {
				fprintf(stderr, "r%d (invalid)\t", locn_num);
			}
			break;

		case MR_SHORT_LVAL_TYPE_STACKVAR:
			value = MR_based_stackvar(stack_pointer, locn_num);
			have_value = TRUE;
			fprintf(stderr, "stackvar%d", locn_num);
			break;

		case MR_SHORT_LVAL_TYPE_FRAMEVAR:
			value = MR_based_framevar(current_frame, locn_num);
			have_value = TRUE;
			fprintf(stderr, "framevar%d", locn_num);
			break;

		case MR_SHORT_LVAL_TYPE_SPECIAL:
			switch (locn_num) {
				case MR_LONG_LVAL_TYPE_SUCCIP:
					fprintf(stderr, "succip");
				break;
				case MR_LONG_LVAL_TYPE_MAXFR:
					fprintf(stderr, "succip");
				break;
				case MR_LONG_LVAL_TYPE_CURFR:
					fprintf(stderr, "curfr");
				break;
				case MR_LONG_LVAL_TYPE_HP:
					fprintf(stderr, "hp");
				break;
				case MR_LONG_LVAL_TYPE_SP:
					fprintf(stderr, "sp");
				break;
				default:
					fprintf(stderr, "SPECIAL DEFAULT");
				break;
			}
			break;

		default:
			fprintf(stderr, "SHORT DEFAULT");
			break;
	}
	if (have_value) {
		if (value >= (MR_Word) heap_zone->min && 
				value < (MR_Word) heap_zone->hardmax) {
			difference = (MR_Word *) value - (MR_Word *) heap_zone->min;
			fprintf(stderr, "\thp[%d]\t(%lx)", difference,
				(long) value);
		} else {
			fprintf(stderr, "\t       \t(%lx)", (long) value);
		}
	}
#endif /* NATIVE_GC */
}

#endif /* NATIVE_GC */
