
/*
** Copyright (C) 1997,2000-2001 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
**
** This file contains the bytecode format and data types
** This must be the same as that in compiler/bytecode.m
*/

#ifndef MB_BYTECODE_H
#define MB_BYTECODE_H

#include <stdio.h>

#include "mercury_conf.h"
#include "mercury_types.h"
#include "mercury_float.h"

#include "mb_basetypes.h"
#include "mb_stack.h"
#include "mb_util.h"

typedef struct MB_Tag_Struct {
	MB_Byte	id;
	union {
		MB_Byte	primary;
		struct {
			MB_Byte	primary;
			MB_Word	secondary; 
		} pair;
		MB_Byte	enum_tag;
	} opt;
} MB_Tag;

/* 
 *	Possible values for Tag.id ...
 */
#define	MB_TAG_SIMPLE			0
#define	MB_TAG_COMPLICATED		1
#define	MB_TAG_COMPLICATED_CONSTANT	2
#define	MB_TAG_ENUM			3
#define	MB_TAG_NONE			4

typedef MB_Byte
	MB_Determinism;
/*
 *	Possible values for Determinism ...
 */
#define	MB_DET_DET			0
#define	MB_DET_SEMIDET			1
#define	MB_DET_MULTIDET			2
#define	MB_DET_NONDET			3
#define	MB_DET_CC_MULTIDET		4
#define	MB_DET_CC_NONDET		5
#define	MB_DET_ERRONEOUS		6
#define	MB_DET_FAILURE			7
	/*
	** Unusable is used to indicate that there is something wrong with
	** this predicate (probably contains foreign code) and the bytecode
	** version cannot be used
	*/
#define	MB_DET_UNUSABLE			99

/* Return true if determinism model is the same as that specified */
#define MB_model_det(x) (\
	((x) == MB_DET_DET) || \
	((x) == MB_DET_CC_MULTIDET) || \
	((x) == MB_DET_ERRONEOUS))

#define MB_model_semi(x) (\
	((x) == MB_DET_SEMIDET) || \
	((x) == MB_DET_CC_NONDET) || \
	((x) == MB_DET_FAILURE))

#define MB_model_nondet(x) (\
	((x) == MB_DET_NONDET) || \
	((x) == MB_DET_MULTIDET))

	
typedef struct MB_Op_arg_struct {
	MB_Byte	id;
	union {
		MB_Short	var;
		MB_Integer 	int_const;
		MB_Float	float_const;
	} opt;
} MB_Op_arg;

/*
 *	Possible values for Op_arg.id
 */
#define	MB_ARG_VAR			0
#define	MB_ARG_INT_CONST		1
#define	MB_ARG_FLOAT_CONST		2


typedef MB_Byte
	MB_Direction;

typedef struct MB_Var_dir_struct {
	MB_Short	var;
	MB_Direction	dir;
} MB_Var_dir;

/*
 *	Possible values for Direction ...
 */
#define	MB_DIR_TO_ARG		0
#define	MB_DIR_TO_VAR		1
#define	MB_DIR_TO_NONE		2

typedef struct {
	/* Whether call is a native code call */
	MB_Bool		is_native;
	/* code address to call */
	union {
		MB_Bytecode_Addr bc;
		MB_Native_Addr	native;
	} addr;
} MB_Code_Addr;

typedef struct MB_Cons_id_struct {
	MB_Byte	id;
	union {
		struct {
			MB_CString	module_name;
			MB_CString	string;
			MB_Short	arity;
			MB_Tag		tag;
		} cons;
		MB_Integer	int_const;	
		MB_CString	string_const;
		MB_Float	float_const;
		struct {
			MB_CString	module_name;
			MB_CString	pred_name;
			MB_Short	arity;
			MB_Bool		is_func;
			MB_Byte		mode_num;
			/* Actual call address */
			MB_Code_Addr	addr;
		} pred_const;
		struct {
			MB_CString	module_name;
			MB_CString	pred_name;
			MB_Short	arity;
			MB_Byte		mode_num;
		} code_addr_const;
		struct {
			MB_CString	module_name;
			MB_CString	type_name;
			MB_Byte		type_arity;
		} base_type_info_const;
		struct {
			MB_Byte		ch;
		} char_const;
	} opt;
} MB_Cons_id;

/*
 *	Possible values for Cons_id.id ...
 */
#define	MB_CONSID_CONS			0
#define	MB_CONSID_INT_CONST		1
#define	MB_CONSID_STRING_CONST		2
#define	MB_CONSID_FLOAT_CONST		3
#define	MB_CONSID_PRED_CONST		4
#define	MB_CONSID_CODE_ADDR_CONST	5
#define	MB_CONSID_BASE_TYPE_INFO_CONST	6
#define	MB_CONSID_CHAR_CONST		7

/*
** Internal label structure. At load time the index is read from the file
** and stored. translate_labels translates indexes into actual memory
** addresses. The module load and label translation functions are the only
** only functions that should access index, the rest of the program should
** only use addr.
*/
typedef union {
	MB_Short	index;
	MB_Bytecode_Addr addr;
} MB_Label;

typedef union MB_Bytecode_Arg_tag {
	struct {
		MB_CString	pred_name;
		MB_Short	pred_arity;
		MB_Bool		is_func;
		MB_Short	proc_count;
	} enter_pred;

	struct {
	} endof_pred;

	struct {
		MB_Byte		mode_num;
		MB_Determinism	det;
		MB_Short	label_count;
		MB_Label	end_label;
		MB_Short	temp_count;
		MB_Short	list_length;
		MB_CString	*var_info;
		
		/*
		** index onto label heap for label indexes
		** (not in the file)
		*/
		MB_Word		label_index; 	
	} enter_proc;

	struct {
		/* start of proc (not in file) */
		MB_Bytecode_Addr proc_start;
	} endof_proc;

	struct {
		MB_Short	label;
	} label;

	struct {
		MB_Label end_label;
	} enter_disjunction;

	struct {
	} endof_disjunction;

	struct {
		MB_Label next_label;
	} enter_disjunct;

	struct {
		MB_Label end_label;
	} endof_disjunct;

	struct {
		MB_Short	var;
		MB_Label	end_label;
	} enter_switch;

	struct {

	} endof_switch;

	struct {
		MB_Cons_id	cons_id;
		MB_Label	next_label;

		/* filled in at load time */
		MB_Short	var;
	} enter_switch_arm;

	struct {
		MB_Label	end_label;
	} endof_switch_arm;

	struct {
		MB_Label	else_label;
		MB_Label	end_label;
		MB_Short	frame_ptr_tmp;
	} enter_if;

	/* 
	** identical to enter_else: if you change this, modify instr_else
	** to reflect
	*/
	struct {
		MB_Short	frame_ptr_tmp;
	} enter_then;
	
	struct {
		MB_Label	follow_label;
	} endof_then;

	/* 
	** identical to enter_then: if you change this, modify instr_then
	** to reflect
	*/
	struct {
		MB_Short	frame_ptr_tmp;
	} enter_else;

	struct {

	} endof_if;

	struct {
		MB_Short	frame_ptr_tmp;
		MB_Label	end_label;
	} enter_negation;

	struct {
		MB_Short	frame_ptr_tmp;
	} endof_negation_goal;

	struct {
	} endof_negation;

	struct {
		MB_Short	frame_ptr_tmp;
	} enter_commit;

	struct {
		MB_Short	frame_ptr_tmp;
	} endof_commit;

	struct {
		MB_Short	to_var;
		MB_Short	from_var;
	} assign;

	struct {
		MB_Short	var1;
		MB_Short	var2;
	} test;

	struct {
		MB_Short	to_var;
		MB_Cons_id	consid;
		MB_Short	list_length;
		MB_Short	*var_list;
	} construct;

	struct {
		MB_Short	from_var;
		MB_Cons_id	consid;
		MB_Short	list_length;
		MB_Short	*var_list;
	} deconstruct;

	struct {
		MB_Short	to_var;
		MB_Cons_id	consid;
		MB_Short	list_length;
		MB_Var_dir	*var_dir;
	} complex_construct;

	struct {
		MB_Short	from_var;
		MB_Cons_id	consid;
		MB_Short	list_length;
		MB_Var_dir	*var_dir;
	} complex_deconstruct;

	struct {
		MB_Byte		to_reg;
		MB_Short	from_var;
	} place_arg;

	struct {
		MB_Byte		from_reg;
		MB_Short	to_var;
	} pickup_arg;
		
	struct {
		MB_CString	module_name;
		MB_CString	pred_name;
		MB_Short	arity;
		MB_Bool		is_func;
		MB_Byte		mode_num;
		/* actual call address */
		MB_Code_Addr	addr;
	} call;

	struct  {
		MB_Short	pred_var;
		MB_Short	in_var_count;
		MB_Short	out_var_count;
		MB_Determinism	det;
	} higher_order_call;

	struct {
		MB_Byte		binop;
		MB_Op_arg	arg1;
		MB_Op_arg	arg2;
		MB_Short	to_var;
	} builtin_binop;

	struct {
		MB_Byte		unop;
		MB_Op_arg	arg;
		MB_Short	to_var;
	} builtin_unop;

	struct {
		MB_Byte		binop;
		MB_Op_arg	arg1;
		MB_Op_arg	arg2;
	} builtin_bintest;	

	struct {
		MB_Byte		unop;
		MB_Op_arg	arg;
	} builtin_untest;	

	struct {
	} semidet_succeed;

	struct {
	} semidet_success_check;

	struct {
	} fail;

	struct {
		/* XXX: is this int or short?? */
		MB_Short	line_number;
	} context;

	struct {
	} not_supported;

} MB_Bytecode_Arg;

typedef struct MB_Bytecode_struct {
	MB_Byte	id;	/* Which bytecode instruction. e.g. BC_fail */
	MB_Bytecode_Arg	opt;
} MB_Bytecode;

/*
** Possible Bytecode.id values
*/
#define	MB_BC_enter_pred		0
#define	MB_BC_endof_pred		1
#define	MB_BC_enter_proc		2
#define	MB_BC_endof_proc		3
#define	MB_BC_label			4
#define MB_BC_enter_disjunction		5
#define	MB_BC_endof_disjunction		6
#define	MB_BC_enter_disjunct		7
#define	MB_BC_endof_disjunct		8
#define	MB_BC_enter_switch		9
#define	MB_BC_endof_switch		10
#define	MB_BC_enter_switch_arm		11
#define	MB_BC_endof_switch_arm		12
#define	MB_BC_enter_if			13
#define	MB_BC_enter_then		14
#define	MB_BC_endof_then		15
#define	MB_BC_endof_if			16
#define	MB_BC_enter_negation		17
#define	MB_BC_endof_negation		18
#define	MB_BC_enter_commit		19
#define	MB_BC_endof_commit		20
#define	MB_BC_assign			21
#define	MB_BC_test			22
#define	MB_BC_construct			23
#define	MB_BC_deconstruct		24
#define	MB_BC_complex_construct		25
#define	MB_BC_complex_deconstruct	26
#define	MB_BC_place_arg			27
#define	MB_BC_pickup_arg		28
#define	MB_BC_call			29
#define	MB_BC_higher_order_call		30
#define	MB_BC_builtin_binop		31
#define	MB_BC_builtin_unop		32
#define	MB_BC_builtin_bintest		33
#define	MB_BC_builtin_untest		34
#define	MB_BC_semidet_succeed		35
#define	MB_BC_semidet_success_check	36
#define	MB_BC_fail			37
#define	MB_BC_context			38
#define	MB_BC_not_supported		39
#define	MB_BC_enter_else		40
#define	MB_BC_endof_negation_goal	41

/* These are used internally by the interpreter */
/* all codes above MB_BC_debug are debugging values */
#define	MB_BC_debug			0x3d
#define	MB_BC_debug_trap		0x3e
#define	MB_BC_debug_invalid		0x3f
/*
** Note that the limit to these is determined in mb_module.c by the
** number of bits allocated to an id
*/

/*
**	Read the next bytecode from the stream fp.
**	If no bytecode can be read, return FALSE.
**	Otherwise, return TRUE.
*/
MB_Bool
MB_read_bytecode(FILE *fp, MB_Bytecode *bc_p);

/*
**	Read the bytecode version number from the stream fp.
**	If the version number cannot be read, return FALSE.
**	Otherwise, return TRUE.
*/
MB_Bool
MB_read_bytecode_version_number(FILE *fp, MB_Short *version_number_p);

#endif	/* MB_BYTECODE_H */

