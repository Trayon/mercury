/*
INIT mercury_sys_init_call
ENDINIT
*/
/*
** Copyright (C) 1995-2001 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

#define	MR_UNIFY_COMPARE_BY_CTOR_REP_SPEC_1
#define	MR_UNIFY_COMPARE_BY_CTOR_REP_SPEC_2

/*
** This module provides much of the functionality for doing higher order
** calls (with the rest provided by code generation of the generic_call
** HLDS construct), and most of the functionality for doing generic
** unifications and comparisons (with the rest provided by the
** compiler-generated unify, index and compare predicates).
*/

#include "mercury_imp.h"
#include "mercury_ho_call.h"

#ifndef MR_HIGHLEVEL_CODE
static	MR_Word	MR_generic_compare(MR_TypeInfo type_info, MR_Word x, MR_Word y);
static	MR_Word	MR_generic_unify(MR_TypeInfo type_info, MR_Word x, MR_Word y);

/*
** The called closure may contain only input arguments. The extra arguments
** provided by the higher-order call may be input or output, and may appear
** in any order.
**
** The input arguments to do_call_*_closure are the closure in MR_r1,
** the number of additional input arguments in MR_r2, the number of output
** arguments to expect in MR_r3, and the additional input arguments themselves
** in MR_r4, MR_r5, etc. The output arguments are returned in registers MR_r1,
** MR_r2, etc for det and nondet calls or registers MR_r2, MR_r3, etc for
** semidet calls.
**
** The placement of the extra input arguments into MR_r4, MR_r5 etc is done by
** the code generator, as is the movement of the output arguments to their
** eventual destinations.
*/

	/*
	** Number of input arguments to do_call_*_closure,
	** MR_r1 -> closure
	** MR_r2 -> number of immediate input arguments.
	** MR_r3 -> number of output arguments (unused).
	*/
#define MR_HO_CALL_INPUTS		3

	/*
	** Number of input arguments to do_call_*_class_method,
	** MR_r1 -> typeclass info
	** MR_r2 -> index of method in typeclass info
	** MR_r3 -> number of immediate input arguments.
	** MR_r4 -> number of output arguments (unused).
	*/
#define MR_CLASS_METHOD_CALL_INPUTS	4

/*
** These are the real implementations of higher order calls and method calls.
*/

MR_define_extern_entry(mercury__do_call_closure);
MR_define_extern_entry(mercury__do_call_class_method);

/*
** These are the real implementations of unify and compare.
*/

MR_define_extern_entry(mercury__unify_2_0);
MR_define_extern_entry(mercury__compare_3_0);
MR_define_extern_entry(mercury__compare_3_1);
MR_define_extern_entry(mercury__compare_3_2);
MR_define_extern_entry(mercury__compare_3_3);
MR_declare_label(mercury__compare_3_0_i1);

MR_BEGIN_MODULE(call_module)
	MR_init_entry_ai(mercury__do_call_closure);
	MR_init_entry_ai(mercury__do_call_class_method);
	MR_init_entry_ai(mercury__unify_2_0);
	MR_init_entry_ai(mercury__compare_3_0);
	MR_init_entry_ai(mercury__compare_3_1);
	MR_init_entry_ai(mercury__compare_3_2);
	MR_init_entry_ai(mercury__compare_3_3);
MR_BEGIN_CODE

/*
** Note: this routine gets ignored for profiling.
** That means it should be called using noprof_call()
** rather than call().  See comment in output_call in
** compiler/llds_out for explanation.
*/
MR_define_entry(mercury__do_call_closure);
{
	MR_Closure	*closure;
	int		num_extra_args;	/* # of args provided by our caller */
	int		num_hidden_args;/* # of args hidden in the closure  */
	int		i;

	closure = (MR_Closure *) MR_r1;
	num_extra_args = MR_r2;
	num_hidden_args = closure->MR_closure_num_hidden_args;

	MR_save_registers();

	if (num_hidden_args < MR_HO_CALL_INPUTS) {
		/* copy to the left, from the left */
		for (i = 1; i <= num_extra_args; i++) {
			MR_virtual_reg(i + num_hidden_args) =
				MR_virtual_reg(i + MR_HO_CALL_INPUTS);
		}
	} else if (num_hidden_args > MR_HO_CALL_INPUTS) {
		/* copy to the right, from the right */
		for (i = num_extra_args; i > 0; i--) {
			MR_virtual_reg(i + num_hidden_args) =
				MR_virtual_reg(i + MR_HO_CALL_INPUTS);
		}
	} /* else the new args are in the right place */

	for (i = 1; i <= num_hidden_args; i++) {
		MR_virtual_reg(i) = closure->MR_closure_hidden_args(i);
	}

	MR_restore_registers();

	/*
	** Note that we pass MR_prof_ho_caller_proc rather than
	** MR_LABEL(mercury__do_call_closure), so that the call gets recorded
	** as having come from our caller.
	*/
	MR_tailcall(closure->MR_closure_code, MR_prof_ho_caller_proc);
}

	/*
	** MR_r1: the typeclass_info
	** MR_r2: index of class method
	** MR_r3: number of immediate input arguments
	** MR_r4: number of output arguments
	** MR_r5+:input args
	*/

/*
** Note: this routine gets ignored for profiling.
** That means it should be called using noprof_call()
** rather than call().  See comment in output_call in
** compiler/llds_out for explanation.
*/
MR_define_entry(mercury__do_call_class_method);
{
	MR_Code 	*destination;
	int	num_in_args;
	int	num_extra_instance_args;
	int	i;

	destination = MR_typeclass_info_class_method(MR_r1, MR_r2);
	num_extra_instance_args = 
		(int) MR_typeclass_info_num_extra_instance_args(MR_r1);

	num_in_args = MR_r3; /* number of input args */

	MR_save_registers();

	if (num_extra_instance_args < MR_CLASS_METHOD_CALL_INPUTS) {
		/* copy to the left, from the left */
		for (i = 1; i <= num_in_args; i++) {
			MR_virtual_reg(i + num_extra_instance_args) =
				MR_virtual_reg(i +
					MR_CLASS_METHOD_CALL_INPUTS);
		}
	} else if (num_extra_instance_args > MR_CLASS_METHOD_CALL_INPUTS) {
		/* copy to the right, from the right */
		for (i = num_in_args; i > 0; i--) {
			MR_virtual_reg(i + num_extra_instance_args) =
				MR_virtual_reg(i +
					MR_CLASS_METHOD_CALL_INPUTS);
		}
	} /* else the new args are in the right place */

	for (i = num_extra_instance_args; i > 0; i--) {
		MR_virtual_reg(i) = 
			MR_typeclass_info_arg_typeclass_info(MR_virtual_reg(1),
				i);
	}

	MR_restore_registers();

	/*
	** Note that we pass MR_prof_ho_caller_proc rather than
	** MR_LABEL(mercury__do_call_class_method), so that the call gets
	** recorded as having come from our caller.
	*/
	MR_tailcall(destination, MR_prof_ho_caller_proc);
}

/*
** mercury__unify_2_0 is called as `unify(TypeInfo, X, Y)'
** in the mode `unify(in, in, in) is semidet'.
*/

MR_define_entry(mercury__unify_2_0);
{

#define	DECLARE_LOCALS							\
	MR_TypeCtorInfo	type_ctor_info;					\
	MR_TypeInfo	type_info;					\
	MR_Word		x, y;						\
	MR_Code		*saved_succip;

#define initialize()							\
	do {								\
		type_info = (MR_TypeInfo) MR_r1;			\
		x = MR_r2;						\
		y = MR_r3;						\
		saved_succip = MR_succip;				\
	} while(0)

#define return_answer(answer)						\
	do {								\
		MR_r1 = (answer);					\
		MR_succip = saved_succip;				\
		MR_proceed();						\
	} while(0)

#define	tailcall_user_pred()						\
	MR_tailcall(type_ctor_info->unify_pred, MR_LABEL(mercury__unify_2_0))

#define	start_label		unify_start
#define	call_user_code_label	call_unify_in_proc
#define	type_stat_struct	MR_type_stat_mer_unify
#define	attempt_msg		"attempt to unify "

#include "mercury_unify_compare_body.h"

#undef  DECLARE_LOCALS
#undef  initialize
#undef  return_answer
#undef	tailcall_user_pred
#undef  start_label
#undef	call_user_code_label
#undef  type_stat_struct
#undef  attempt_msg

}

/*
** mercury__compare_3_3 is called as `compare(TypeInfo, Result, X, Y)'
** in the mode `compare(in, out, in, in) is det'.
**
** (The additional entry points replace either or both "in"s with "ui"s.)
*/

MR_define_entry(mercury__compare_3_0);
#ifdef PROFILE_CALLS
{
	MR_tailcall(MR_ENTRY(mercury__compare_3_3), MR_LABEL(mercury__compare_3_0));
}
#endif
MR_define_entry(mercury__compare_3_1);
#ifdef PROFILE_CALLS
{
	MR_tailcall(MR_ENTRY(mercury__compare_3_3), MR_LABEL(mercury__compare_3_1));
}
#endif
MR_define_entry(mercury__compare_3_2);
#ifdef PROFILE_CALLS
{
	MR_tailcall(MR_ENTRY(mercury__compare_3_3), MR_LABEL(mercury__compare_3_2));
}
#endif
MR_define_entry(mercury__compare_3_3);
{

#define	DECLARE_LOCALS							\
	MR_TypeCtorInfo	type_ctor_info;					\
	MR_TypeInfo	type_info;					\
	MR_Word		x, y;						\
	MR_Code		*saved_succip;

#define initialize()							\
	do {								\
		type_info = (MR_TypeInfo) MR_r1;			\
		x = MR_r2;						\
		y = MR_r3;						\
		saved_succip = MR_succip;				\
	} while(0)

#define return_answer(answer)						\
	do {								\
		MR_r1 = (answer);					\
		MR_succip = saved_succip;				\
		MR_proceed();						\
	} while(0)

#define	tailcall_user_pred()						\
	MR_tailcall(type_ctor_info->compare_pred,			\
		MR_LABEL(mercury__compare_3_3))

#define	start_label		compare_start
#define	call_user_code_label	call_compare_in_proc
#define	type_stat_struct	MR_type_stat_mer_compare
#define	attempt_msg		"attempt to compare "
#define	select_compare_code

#include "mercury_unify_compare_body.h"

#undef  DECLARE_LOCALS
#undef  initialize
#undef  return_answer
#undef	tailcall_user_pred
#undef  start_label
#undef	call_user_code_label
#undef  type_stat_struct
#undef  attempt_msg
#undef	select_compare_code

}
MR_END_MODULE

static MR_Word
MR_generic_unify(MR_TypeInfo type_info, MR_Word x, MR_Word y)
{

#define	DECLARE_LOCALS							\
	MR_TypeCtorInfo	type_ctor_info;

#define initialize()							\
	do {								\
		(void) 0; /* do nothing */				\
	} while(0)

#define return_answer(answer)						\
	return (answer)

#define	tailcall_user_pred()						\
	do {								\
		MR_save_transient_registers();				\
		(void) MR_call_engine(type_ctor_info->unify_pred, FALSE);\
		MR_restore_transient_registers();			\
		return (MR_r1);						\
	} while (0)

#define	start_label		unify_func_start
#define	call_user_code_label	call_unify_in_func
#define	type_stat_struct	MR_type_stat_c_unify
#define	attempt_msg		"attempt to unify "

#include "mercury_unify_compare_body.h"

#undef  DECLARE_LOCALS
#undef  initialize
#undef  return_answer
#undef	tailcall_user_pred
#undef  start_label
#undef	call_user_code_label
#undef  type_stat_struct
#undef  attempt_msg
}

static MR_Word
MR_generic_compare(MR_TypeInfo type_info, MR_Word x, MR_Word y)
{

#define	DECLARE_LOCALS							\
	MR_TypeCtorInfo	type_ctor_info;

#define initialize()							\
	do {								\
		(void) 0; /* do nothing */				\
	} while(0)

#define return_answer(answer)						\
	return (answer)

#define	tailcall_user_pred()						\
	do {								\
		MR_save_transient_registers();				\
		(void) MR_call_engine(type_ctor_info->compare_pred, FALSE);\
		MR_restore_transient_registers();			\
		return (MR_r1);						\
	} while (0)

#define	start_label		compare_func_start
#define	call_user_code_label	call_compare_in_func
#define	type_stat_struct	MR_type_stat_c_compare
#define	attempt_msg		"attempt to compare "
#define	select_compare_code

#include "mercury_unify_compare_body.h"

#undef  DECLARE_LOCALS
#undef  initialize
#undef  return_answer
#undef	tailcall_user_pred
#undef  start_label
#undef	call_user_code_label
#undef  type_stat_struct
#undef  attempt_msg
#undef	select_compare_code
}

#endif /* not MR_HIGHLEVEL_CODE */

/*
** The initialization function needs to be defined even when
** MR_HIGHLEVEL_CODE is set, because it will get included
** in the list of initialization functions that get called.
** So for MR_HIGHLEVEL_CODE it just does nothing.
*/
void mercury_sys_init_call(void); /* suppress gcc warning */
void mercury_sys_init_call(void) {
#ifndef MR_HIGHLEVEL_CODE
	call_module();
#endif /* not MR_HIGHLEVEL_CODE */
}
