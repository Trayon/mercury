%-----------------------------------------------------------------------------%
% Copyright (C) 2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% File: gcc.m
% Main author: fjh

% This module is the Mercury interface to the GCC compiler back-end.

% This module provides a thin wrapper around the C types,
% constants, and functions defined in gcc/tree.{c,h,def}
% and gcc/mercury/mercury-gcc.c in the GCC source.
% (The functions in gcc/mercury/mercury-gcc.c are in turn a thick
% wrapper around GCC's source-language-independent back-end.)

% Note that we want to keep this code as simple as possible.
% Anything complicated, which might require changes for new versions
% of gcc, should go in gcc/mercury/mercury-gcc.c rather than in
% inline C code here.

:- module gcc.
:- interface.
:- import_module io, bool.

%-----------------------------------------------------------------------------%

% The GCC `tree' type.
:- type gcc__tree.
:- type gcc__tree_code.

%-----------------------------------------------------------------------------%
%
% Types
%

% A GCC `tree' representing a type.
:- type gcc__type.
:- func void_type_node = gcc__type.
:- func integer_type_node = gcc__type.
:- func string_type_node = gcc__type.
:- func double_type_node = gcc__type.
:- func char_type_node = gcc__type.
:- func boolean_type_node = gcc__type.
:- func ptr_type_node = gcc__type.	% `void *'
	
	% Given a type `T', produce a pointer type `T *'.
:- pred build_pointer_type(gcc__type::in, gcc__type::out,
		io__state::di, io__state::uo) is det.

% A GCC `tree' representing a list of parameter types.
:- type gcc__param_types.
:- func empty_param_types = gcc__param_types.
:- func cons_param_types(gcc__type, gcc__param_types) = gcc__param_types.

%-----------------------------------------------------------------------------%
%
% Declarations
%

% A GCC `tree' representing a declaration.
:- type gcc__decl.

% A GCC `tree' representing a local variable.
:- type gcc__var_decl.

% A GCC `tree' representing a function parameter.
:- type gcc__param_decl == gcc__var_decl.

:- type var_name == string.

	% build an extern variable declaration
:- pred build_extern_var_decl(var_name::in, gcc__type::in, gcc__var_decl::out,
		io__state::di, io__state::uo) is det.

	% build a local variable declaration
:- pred build_local_var_decl(var_name::in, gcc__type::in, gcc__var_decl::out,
		io__state::di, io__state::uo) is det.

	% build a function parameter declaration
:- type param_name == string.
:- pred build_param_decl(param_name::in, gcc__type::in, gcc__param_decl::out,
		io__state::di, io__state::uo) is det.

% A GCC `tree' representing a list of parameters.
:- type gcc__param_decls.

	% routines for building parameter lists
:- func empty_param_decls = gcc__param_decls.
:- func cons_param_decls(gcc__param_decl, gcc__param_decls) = gcc__param_decls.

% A GCC `tree' representing a function declaration.
:- type gcc__func_decl.

	% build a function declaration
:- type func_name == string.
:- type func_asm_name == string.
:- pred build_function_decl(func_name, func_asm_name, gcc__type,
		gcc__param_types, gcc__param_decls, gcc__func_decl,
		io__state, io__state).
:- mode build_function_decl(in, in, in, in, in, out, di, uo) is det.

	% the declaration for GC_malloc()
:- func alloc_func_decl = gcc__func_decl.

%-----------------------------------------------------------------------------%
%
% Operators
%

% GCC tree_codes for operators
:- type gcc__op.

:- func plus_expr  = gcc__op.		% +
:- func minus_expr = gcc__op.		% *
:- func mult_expr  = gcc__op.		% -
:- func trunc_div_expr = gcc__op.	% / (truncating integer division)
:- func trunc_mod_expr = gcc__op.	% % (remainder after truncating
					%    integer division)

:- func eq_expr = gcc__op.		% ==
:- func ne_expr = gcc__op.		% !=
:- func lt_expr = gcc__op.		% <
:- func gt_expr = gcc__op.		% >
:- func le_expr = gcc__op.		% <=
:- func ge_expr = gcc__op.		% >=

:- func truth_andif_expr = gcc__op.	% &&
:- func truth_orif_expr = gcc__op.	% ||
:- func truth_not_expr = gcc__op.	% !

:- func bit_ior_expr = gcc__op.		% | (bitwise inclusive or)
:- func bit_xor_expr = gcc__op.		% ^ (bitwise exclusive or)
:- func bit_and_expr = gcc__op.		% & (bitwise and)
:- func bit_not_expr = gcc__op.		% ~ (bitwise complement)

:- func lshift_expr = gcc__op.		% << (left shift)
:- func rshift_expr = gcc__op.		% >> (left shift)

%-----------------------------------------------------------------------------%
%
% Expressions
%

% A GCC `tree' representing an expression.
:- type gcc__expr.

	% look up the type of an expression
:- pred expr_type(gcc__expr, gcc__type, io__state, io__state).
:- mode expr_type(in, out, di, uo) is det.

%
% constants
%

	% build an expression for an integer constant
:- pred build_int(int, gcc__expr, io__state, io__state).
:- mode build_int(in, out, di, uo) is det.

	% build an expression for a Mercury string constant
:- pred build_string(string, gcc__expr, io__state, io__state).
:- mode build_string(in, out, di, uo) is det.

	% Build an expression for a string constant,
	% with the specified length.  This length must
	% include the terminating null, if one is desired.
:- pred build_string(int, string, gcc__expr, io__state, io__state).
:- mode build_string(in, in, out, di, uo) is det.

	% build an expression for a null pointer
:- pred build_null_pointer(gcc__expr, io__state, io__state).
:- mode build_null_pointer(out, di, uo) is det.

%
% operator expressions
%

	% build a unary expression
:- pred build_unop(gcc__op, gcc__type, gcc__expr, gcc__expr,
		io__state, io__state).
:- mode build_unop(in, in, in, out, di, uo) is det.

	% build a binary expression
:- pred build_binop(gcc__op, gcc__type, gcc__expr, gcc__expr, gcc__expr,
		io__state, io__state).
:- mode build_binop(in, in, in, in, out, di, uo) is det.

	% take the address of an expression
:- pred build_addr_expr(gcc__expr, gcc__expr, io__state, io__state).
:- mode build_addr_expr(in, out, di, uo) is det.

	% build a pointer dereference expression
:- pred build_pointer_deref(gcc__expr, gcc__expr, io__state, io__state).
:- mode build_pointer_deref(in, out, di, uo) is det.

	% build a type conversion expression
:- pred convert_type(gcc__expr, gcc__type, gcc__expr, io__state, io__state).
:- mode convert_type(in, in, out, di, uo) is det.

%
% variables
%

	% build an expression for a variable
:- func var_expr(gcc__var_decl) = gcc__expr.

%
% stuff for function calls
%

	% build a function pointer expression
	% i.e. take the address of a function
:- pred build_func_addr_expr(gcc__func_decl, gcc__expr, io__state, io__state).
:- mode build_func_addr_expr(in, out, di, uo) is det.

	% A GCC `tree' representing a list of arguments.
:- type gcc__expr_list.

:- pred empty_expr_list(gcc__expr_list, io__state, io__state).
:- mode empty_expr_list(out, di, uo) is det.

:- pred cons_expr_list(gcc__expr, gcc__expr_list, gcc__expr_list, io__state, io__state).
:- mode cons_expr_list(in, in, out, di, uo) is det.

	% build an expression for a function call
:- pred build_call_expr(gcc__expr, gcc__expr_list, bool, gcc__expr,
		io__state, io__state).
:- mode build_call_expr(in, in, in, out, di, uo) is det.

%-----------------------------------------------------------------------------%
%
% Functions
%

	% start generating code for a function
:- pred start_function(gcc__func_decl, io__state, io__state).
:- mode start_function(in, di, uo) is det.

	% finish generating code for a function
:- pred end_function(io__state, io__state).
:- mode end_function(di, uo) is det.

%-----------------------------------------------------------------------------%
%
% Statements
%

%
% routines to generate code for an if-then-else
%

	% start generating code for an if-then-else
	% the argument is the gcc tree for the condition
:- pred gen_start_cond(gcc__expr, io__state, io__state).
:- mode gen_start_cond(in, di, uo) is det.

	% start the else part (optional)
:- pred gen_start_else(io__state, io__state).
:- mode gen_start_else(di, uo) is det.

	% finish the if-then-else
:- pred gen_end_cond(io__state, io__state).
:- mode gen_end_cond(di, uo) is det.

%
% routines to generate code for switches
%

:- pred gen_start_switch(gcc__expr, gcc__type, io__state, io__state).
:- mode gen_start_switch(in, in, di, uo) is det.

:- pred gen_case_label(gcc__expr, gcc__label, io__state, io__state).
:- mode gen_case_label(in, in, di, uo) is det.

:- pred gen_default_case_label(gcc__label, io__state, io__state).
:- mode gen_default_case_label(in, di, uo) is det.

:- pred gen_break(io__state, io__state).
:- mode gen_break(di, uo) is det.

:- pred gen_end_switch(gcc__expr, io__state, io__state).
:- mode gen_end_switch(in, di, uo) is det.

%
% routines to generate code for calls/returns
%

	% generate code for an expression with side effects
	% (e.g. a call)
:- pred gen_expr_stmt(gcc__expr, io__state, io__state).
:- mode gen_expr_stmt(in, di, uo) is det.

	% generate code for a return statement
:- pred gen_return(gcc__expr, io__state, io__state).
:- mode gen_return(in, di, uo) is det.

%
% assignment
%

	% gen_assign(LHS, RHS):
	% generate code for an assignment statement
:- pred gen_assign(gcc__expr, gcc__expr, io__state, io__state).
:- mode gen_assign(in, in, di, uo) is det.

%
% labels and goto
%

:- type gcc__label.
:- type gcc__label_name == string.

	% Build a gcc tree node for a label.
	% Note that you also need to use gen_label
	% (or gen_case_label) to define the label.
:- pred build_label(gcc__label_name, gcc__label, io__state, io__state).
:- mode build_label(in, out, di, uo) is det.

:- pred build_unnamed_label(gcc__label, io__state, io__state).
:- mode build_unnamed_label(out, di, uo) is det.

:- pred gen_label(gcc__label, io__state, io__state).
:- mode gen_label(in, di, uo) is det.

:- pred gen_goto(gcc__label, io__state, io__state).
:- mode gen_goto(in, di, uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.
:- import_module int, string.

:- pragma c_header_code("

#include ""config.h""
#include ""system.h""
#include ""gansidecl.h""
#include ""tree.h""
#include ""flags.h""
#include ""output.h""
#include <stdio.h>

#include ""c-lex.h""
#include ""c-tree.h""
#include ""rtl.h""
#include ""tm_p.h""
#include ""ggc.h""
#include ""toplev.h""

#include ""mercury-gcc.h""

").


:- type gcc__tree == c_pointer.
:- type gcc__tree_code == int.

%-----------------------------------------------------------------------------%
%
% Types
%

:- type gcc__type == gcc__tree.

:- type gcc__func_decl == gcc__type.

:- pragma c_code(void_type_node = (Type::out), [will_not_call_mercury], "
	Type = (MR_Word) void_type_node;
").
:- pragma c_code(integer_type_node = (Type::out), [will_not_call_mercury], "
	Type = (MR_Word) integer_type_node;
").
:- pragma c_code(string_type_node = (Type::out), [will_not_call_mercury], "
	/*
	** XXX we should consider using const when appropriate,
	** i.e. when the string doesn't have a unique mode
	*/
	Type = (MR_Word) string_type_node;
").
:- pragma c_code(double_type_node = (Type::out), [will_not_call_mercury], "
	Type = (MR_Word) double_type_node;
").
:- pragma c_code(char_type_node = (Type::out), [will_not_call_mercury], "
	Type = (MR_Word) char_type_node;
").
:- pragma c_code(boolean_type_node = (Type::out), [will_not_call_mercury], "
	Type = (MR_Word) boolean_type_node;
").
:- pragma c_code(ptr_type_node = (Type::out), [will_not_call_mercury], "
	Type = (MR_Word) ptr_type_node;
").

:- pragma c_code(build_pointer_type(Type::in, PtrType::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	PtrType = (MR_Word) build_pointer_type((tree) Type);
").

:- type gcc__param_types == gcc__tree.

:- pragma c_code(empty_param_types = (ParamTypes::out), [will_not_call_mercury],
"
	ParamTypes = (MR_Word) merc_empty_param_type_list();
").

:- pragma c_code(cons_param_types(Type::in, Types0::in) = (Types::out),
		[will_not_call_mercury],
"
	Types = (MR_Word)
		merc_cons_param_type_list((tree) Type, (tree) Types0);
").

%-----------------------------------------------------------------------------%
%
% Declarations
%

:- type gcc__var_decl == gcc__tree.

:- pragma c_code(build_extern_var_decl(Name::in, Type::in, Decl::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	Decl = (MR_Word) merc_build_extern_var_decl(Name, (tree) Type);
").

:- pragma c_code(build_local_var_decl(Name::in, Type::in, Decl::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	Decl = (MR_Word) merc_build_local_var_decl(Name, (tree) Type);
").

:- pragma c_code(build_param_decl(Name::in, Type::in, Decl::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	Decl = (MR_Word) merc_build_param_decl(Name, (tree) Type);
").

:- type gcc__param_decls == gcc__tree.

:- pragma c_code(empty_param_decls = (Decl::out), [will_not_call_mercury],
"
	Decl = (MR_Word) merc_empty_param_list();
").

:- pragma c_code(cons_param_decls(Decl::in, Decls0::in) = (Decls::out),
		[will_not_call_mercury],
"
	Decls = (MR_Word) merc_cons_param_list((tree) Decl, (tree) Decls0);
").

:- pragma c_code(build_function_decl(Name::in, AsmName::in,
	RetType::in, ParamTypes::in, Params::in, Decl::out, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	Decl = (MR_Word) merc_build_function_decl(Name, AsmName,
			(tree) RetType, (tree) ParamTypes, (tree) Params);
").

:- pragma c_code(alloc_func_decl = (Decl::out),
	[will_not_call_mercury],
"
	Decl = (MR_Word) merc_alloc_function_node
").

%-----------------------------------------------------------------------------%
%
% Operators
%

:- type gcc__op == gcc__tree_code.

:- pragma c_code(plus_expr = (Code::out), [will_not_call_mercury], "
	Code = PLUS_EXPR;
").
:- pragma c_code(minus_expr = (Code::out), [will_not_call_mercury], "
	Code = MINUS_EXPR;
").
:- pragma c_code(mult_expr = (Code::out), [will_not_call_mercury], "
	Code = MULT_EXPR;
").
:- pragma c_code(trunc_div_expr = (Code::out), [will_not_call_mercury], "
	Code = TRUNC_DIV_EXPR;
").
:- pragma c_code(trunc_mod_expr = (Code::out), [will_not_call_mercury], "
	Code = TRUNC_MOD_EXPR;
").

:- pragma c_code(eq_expr = (Code::out), [will_not_call_mercury], "
	Code = EQ_EXPR;
").
:- pragma c_code(ne_expr = (Code::out), [will_not_call_mercury], "
	Code = NE_EXPR;
").
:- pragma c_code(lt_expr = (Code::out), [will_not_call_mercury], "
	Code = LT_EXPR;
").
:- pragma c_code(gt_expr = (Code::out), [will_not_call_mercury], "
	Code = GT_EXPR;
").
:- pragma c_code(le_expr = (Code::out), [will_not_call_mercury], "
	Code = LE_EXPR;
").
:- pragma c_code(ge_expr = (Code::out), [will_not_call_mercury], "
	Code = GE_EXPR;
").

:- pragma c_code(truth_andif_expr = (Code::out), [will_not_call_mercury], "
	Code = TRUTH_ANDIF_EXPR;
").
:- pragma c_code(truth_orif_expr = (Code::out), [will_not_call_mercury], "
	Code = TRUTH_ORIF_EXPR;
").
:- pragma c_code(truth_not_expr = (Code::out), [will_not_call_mercury], "
	Code = TRUTH_NOT_EXPR;
").

:- pragma c_code(bit_ior_expr = (Code::out), [will_not_call_mercury], "
	Code = BIT_IOR_EXPR;
").
:- pragma c_code(bit_xor_expr = (Code::out), [will_not_call_mercury], "
	Code = BIT_XOR_EXPR;
").
:- pragma c_code(bit_and_expr = (Code::out), [will_not_call_mercury], "
	Code = BIT_AND_EXPR;
").
:- pragma c_code(bit_not_expr = (Code::out), [will_not_call_mercury], "
	Code = BIT_NOT_EXPR;
").

:- pragma c_code(lshift_expr = (Code::out), [will_not_call_mercury], "
	Code = LSHIFT_EXPR;
").
:- pragma c_code(rshift_expr = (Code::out), [will_not_call_mercury], "
	Code = RSHIFT_EXPR;
").

%-----------------------------------------------------------------------------%
%
% Expressions
%

:- type gcc__expr == gcc__tree.

:- pragma c_code(expr_type(Expr::in, Type::out, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	Type = (MR_Word) TREE_TYPE((tree) Expr);
").

%
% constants
%

build_int(Val, IntExpr) -->
	{ Lowpart = Val },
	{ Highpart = (if Val < 0 then -1 else 0) },
	build_int_2(Lowpart, Highpart, IntExpr).

	% build_int_2(Lowpart, Highpart):
	% build an expression for an integer constant.
	% Lowpart gives the low word, and Highpart gives the high word.
:- pred build_int_2(int, int, gcc__expr, io__state, io__state).
:- mode build_int_2(in, in, out, di, uo) is det.

:- pragma c_code(build_int_2(Low::in, High::in, Expr::out, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	Expr = (MR_Word) build_int_2(Low, High);
").

build_string(String, Expr) -->
	build_string(string__length(String) + 1, String, Expr).

:- pragma c_code(build_string(Len::in, String::in, Expr::out, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	Expr = (MR_Word) merc_build_string(Len, String);
").

:- pragma c_code(build_null_pointer(NullPointerExpr::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	NullPointerExpr = (MR_Word) null_pointer_node;
").

%
% operator expressions
%

:- pragma c_code(build_unop(Op::in, Type::in, Arg::in, Expr::out, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	Expr = (MR_Word) build1(Op, (tree) Type, (tree) Arg);
").

:- pragma c_code(build_binop(Op::in, Type::in, Arg1::in, Arg2::in, Expr::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	Expr = (MR_Word) build(Op, (tree) Type, (tree) Arg1, (tree) Arg2);
").

:- pragma c_code(build_pointer_deref(Pointer::in, DerefExpr::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	/* XXX should move to mercury-gcc.c */
	tree ptr = (tree) Pointer;
	tree ptr_type = TREE_TYPE (ptr);
	tree type = TREE_TYPE (ptr_type);
	DerefExpr = (MR_Word) build1 (INDIRECT_REF, type, ptr);
").

:- pragma c_code(convert_type(Expr::in, Type::in, ResultExpr::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	/*
	** XXX should we use convert() instead?
	** if not, should we expose the CONVERT_EXPR gcc__op
	** and just use gcc__build_binop?
	*/
	ResultExpr = (MR_Word) build1 (CONVERT_EXPR, (tree) Type, (tree) Expr);
").

	% We building an address expression, we need to call
	% mark_addressable to let the gcc back-end know that we've
	% taken the address of this expression, so that (e.g.)
	% if the expression is a variable, then gcc will know to
	% put it in a stack slot rather than a register.
	% To make the interface to this module safer,
	% we don't export the `addr_expr' operator directly.
	% Instead, we only export the procedure `build_addr_expr'
	% which includes the necessary call to mark_addressable.

build_addr_expr(Expr, AddrExpr) -->
	mark_addressable(Expr),
	expr_type(Expr, Type),
	build_pointer_type(Type, PtrType),
	build_unop(addr_expr, PtrType, Expr, AddrExpr).

:- func addr_expr = gcc__op.		% & (address-of)
:- pragma c_code(addr_expr = (Code::out), [will_not_call_mercury], "
	Code = ADDR_EXPR;
").

:- pred mark_addressable(gcc__expr::in, io__state::di, io__state::uo) is det.
:- pragma c_code(mark_addressable(Expr::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	mark_addressable((tree) Expr);
").

%
% variables
%


	% GCC represents variable expressions just by (the pointer to)
	% their declaration tree node.
var_expr(Decl) = Decl.

%
% stuff for function calls
%

	% GCC represents functions pointer expressions just as ordinary
	% ADDR_EXPR nodes whose operand the function declaration tree node.
build_func_addr_expr(FuncDecl, Expr) -->
	build_addr_expr(FuncDecl, Expr).

:- type gcc__expr_list == gcc__tree.

:- pragma c_code(empty_expr_list(ExprList::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	ExprList = (MR_Word) merc_empty_expr_list();
").

:- pragma c_code(cons_expr_list(Expr::in, ExprList0::in, ExprList::out,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	ExprList = (MR_Word)
		merc_cons_expr_list((tree) Expr, (tree) ExprList0);
").

:- pragma c_code(build_call_expr(Func::in, Args::in, IsTailCall::in,
	CallExpr::out, _IO0::di, _IO::uo), [will_not_call_mercury],
"
	CallExpr = (MR_Word) merc_build_call_expr((tree) Func, (tree) Args,
		(int) IsTailCall);
").

%-----------------------------------------------------------------------------%
%
% Functions
%

:- pragma c_code(start_function(FuncDecl::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	merc_start_function((tree) FuncDecl);
").

:- pragma import(end_function(di, uo), [will_not_call_mercury],
	"merc_end_function").

%-----------------------------------------------------------------------------%
%
% Statements.
%

%
% if-then-else
%

:- pragma c_code(gen_start_cond(Cond::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	expand_start_cond((tree) Cond, 0);
").

:- pragma import(gen_start_else(di, uo), [will_not_call_mercury],
	"expand_start_else").

:- pragma import(gen_end_cond(di, uo), [will_not_call_mercury],
	"expand_end_cond").

%
% switch statements
%

:- pragma c_code(gen_start_switch(Expr::in, Type::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	expand_start_case(1, (tree) Expr, (tree) Type, ""switch"");
").

:- pragma c_code(gen_case_label(Value::in, Label::in,
	_IO0::di, _IO::uo), [will_not_call_mercury],
"
	merc_gen_switch_case_label ((tree) Value, (tree) Label);
").

:- pragma c_code(gen_default_case_label(Label::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	merc_gen_switch_case_label (NULL_TREE, (tree) Label);
").

:- pragma c_code(gen_break(_IO0::di, _IO::uo), [will_not_call_mercury],
"
	int result = expand_exit_something();
	assert (result != 0);
").

:- pragma c_code(gen_end_switch(Expr::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	expand_end_case((tree) Expr);
").

%
% calls and return
%

:- pragma c_code(gen_expr_stmt(Expr::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	merc_gen_expr_stmt((tree) Expr);
").

:- pragma c_code(gen_return(Expr::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	merc_gen_return((tree) Expr);
").

%
% assignment
%

:- pragma c_code(gen_assign(LHS::in, RHS::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	merc_gen_assign((tree) LHS, (tree) RHS);
").

%
% labels and gotos
%

:- type gcc__label == gcc__tree.

:- pragma c_code(build_label(Name::in, Label::out, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	Label = (MR_Word) merc_build_label(Name);
").

:- pragma c_code(build_unnamed_label(Label::out, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	Label = (MR_Word) merc_build_label(NULL);
").

:- pragma c_code(gen_label(Label::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	expand_label((tree) Label);
").

:- pragma c_code(gen_goto(Label::in, _IO0::di, _IO::uo),
	[will_not_call_mercury],
"
	expand_goto((tree) Label);
").

%-----------------------------------------------------------------------------%
