%-----------------------------------------------------------------------------%
% Copyright (C) 1998-1999 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% File: rl_exprn.m
% Main author: stayl
%
% This module should only be imported by rl_out.m. XXX make it a sub-module.
% 
% Generate RL "expressions" to evaluate join conditions.
% 
% The code generated here is pretty awful. Each variable used in the
% expression is assigned its own register. All calls are generated inline -
% recursive calls and calls to imported predicates result in an abort.
% Unifications are generated eagerly.
%
% For complicated join conditions (for example anything containing
% calls to non-builtin predicates) we will probably generate Mercury bytecode,
% when the interpreter is done.
%
% Expressions are arranged into fragments. Each fragment consists of
% rl_PROC_expr_frag(N) followed by rl_EXP_* bytecodes to implement the
% fragment. Jumps addresses start at zero at the first instruction following
% the rl_PROC_expr_frag.
% 0 - initialisation: run once before anything else. Used to initialise
% 	the rule numbers (see below).
% 1 - group initialisation: has access to the first tuple in an aggregate group
% 2 - test - returns either zero/non-zero or -1/0/1 as for strcmp,
% 	depending on the operation.
% 3 - project - constructs an output tuple.
% 4 - cleanup - currently not used.
%
% Expressions have their own constant table separate from the procedure
% constant table. This is set up using rl_HEAD_const_* bytecodes before
% any fragments.
%
% Each expression has zero, one or two input tuples, a tuple to store
% local variables and zero, one or two output tuples.
%
% Expressions also need to set up rule numbers to identify data constructors.
% This is done with rl_EXP_define_var_rule(RuleNo, TypeIndex, NameIndex, Arity)
% (`var' refers to the schema of the tuple holding the local expression
% variables). TypeIndex and NameIndex are indices into the expression's
% constant table holding the type name and constructor name. `RuleNo' is
% used for bytecodes such as rl_EXP_test_functor and rl_EXP_construct_term
% to specify which constructor to use.
%
%-----------------------------------------------------------------------------%
:- module rl_exprn.

:- interface.

:- import_module hlds_module, hlds_pred, rl, rl_code, rl_file, prog_data.
:- import_module list.

	% Generate an expression to compare tuples with the
	% given schema on the given attributes.
:- pred rl_exprn__generate_compare_exprn(module_info::in, sort_spec::in,
	list(type)::in, list(bytecode)::out) is det.

	% Generate an expression to produce the upper and lower
	% bounds for a B-tree access.
:- pred rl_exprn__generate_key_range(module_info::in, key_range::in,
	list(bytecode)::out, int::out, list(type)::out, list(type)::out,
	int::out) is det.

	% Generate an expression for a join/project/subtract condition.
:- pred rl_exprn__generate(module_info::in, rl_goal::in, list(bytecode)::out,
	int::out, exprn_mode::out, list(type)::out) is det.

	% Given the closures used to create the initial accumulator for each
	% group and update the accumulator for each tuple, create
	% an expression to evaluate the aggregate.
:- pred rl_exprn__aggregate(module_info::in, pred_proc_id::in,
		pred_proc_id::in, (type)::in, (type)::in, (type)::in,
		list(bytecode)::out, list(type)::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module code_util, hlds_pred, hlds_data, inst_match.
:- import_module instmap, mode_util, tree, type_util, prog_out.
:- import_module rl_out, llds, inlining, hlds_goal.
:- import_module assoc_list, bool, char, int, map.
:- import_module require, set, std_util, string, term, varset.

	% A compare expression tests each attribute in a list of attributes
	% in turn.
rl_exprn__generate_compare_exprn(_ModuleInfo, Spec, Schema, Code) :-
	(
		Spec = attributes(Attrs),
		list__foldl(rl_exprn__generate_compare_instrs(Schema),
				Attrs, empty, CompareCode)
	;
		Spec = sort_var(_),
		error("rl_exprn__generate_compare_exprn: unbound sort_var")
	),

	ExprnCode = 
		tree(node([rl_PROC_expr_frag(2)]),
		tree(CompareCode,
		node([
			rl_EXP_int_immed(0), % return equal
			rl_EXP_int_result,
			rl_PROC_expr_end
		])
	)),

	tree__flatten(ExprnCode, Instrs0),
	list__condense(Instrs0, Code).

:- pred rl_exprn__generate_compare_instrs(list(type)::in,
	pair(int, sort_dir)::in, byte_tree::in, byte_tree::out) is det.

rl_exprn__generate_compare_instrs(Types, Attr - Dir, Code0, Code) :-
	list__index0_det(Types, Attr, Type),
	rl_exprn__type_to_aditi_type(Type, AType),
	rl_exprn__compare_bytecode(AType, CompareByteCode),
	rl_exprn__get_input_field_code(one, AType, Attr, FieldCode1),
	rl_exprn__get_input_field_code(two, AType, Attr, FieldCode2),
	(
		Dir = ascending,
		CompareAttr = node([
				FieldCode1,
				FieldCode2,
				CompareByteCode,
				rl_EXP_return_if_nez
			])
	;
		Dir = descending,
		CompareAttr = node([
				FieldCode2,
				FieldCode1,
				CompareByteCode,
				rl_EXP_return_if_nez
			])
	),
	Code = tree(Code0, CompareAttr).

%-----------------------------------------------------------------------------%

rl_exprn__generate_key_range(ModuleInfo,
		key_range(LowerBound, UpperBound, MaybeArgTypes, KeyTypes),
		Code, NumParams, Output1Schema, Output2Schema, MaxDepth) :-
	( MaybeArgTypes = yes(_) ->
		NumParams = 1
	;
		NumParams = 0
	),
	rl_exprn_info_init(ModuleInfo, Info0),
	% Generate code to produce the lower bound term.
	rl_exprn__generate_bound(ModuleInfo, MaybeArgTypes, KeyTypes,
		one, LowerBound, LowerBoundCode, Output1Schema,
		MaxDepth0, Info0, Info1),
	% Generate code to produce the upper bound term.
	rl_exprn__generate_bound(ModuleInfo, MaybeArgTypes, KeyTypes,
		two, UpperBound, UpperBoundCode, Output2Schema,
		MaxDepth1, Info1, Info2),
	int__max(MaxDepth0, MaxDepth1, MaxDepth),
	rl_exprn__generate_init_fragment(InitCode, Info2, Info),
	rl_exprn_info_get_consts(Consts - _, Info, _),
	map__to_assoc_list(Consts, ConstsAL),
	assoc_list__reverse_members(ConstsAL, ConstsLA0),
	list__sort(ConstsLA0, ConstsLA),
	list__map(rl_exprn__generate_const_decl, ConstsLA, ConstCode),
	CodeTree =
		tree(node(ConstCode),
		tree(InitCode,
		tree(node([rl_PROC_expr_frag(3)]),
		tree(LowerBoundCode,
		UpperBoundCode
	)))),
	tree__flatten(CodeTree, Code0),
	list__condense(Code0, Code).

:- pred rl_exprn__generate_bound(module_info::in, maybe(list(type))::in,
	list(type)::in, tuple_num::in, bounding_tuple::in, byte_tree::out,
	list(type)::out, int::out, rl_exprn_info::in,
	rl_exprn_info::out) is det.

	% An output schema of [] signals to the relational operation that
	% that end of the key range has no bound (it doesn't make sense
	% to have a key with no attributes).
rl_exprn__generate_bound(_, _, _, _, infinity, empty, [], 0) --> [].
rl_exprn__generate_bound(ModuleInfo, MaybeArgTypes, KeyTypes,
		TupleNum, bound(Attrs), Code, KeyTypes, MaxDepth) -->
	{ assoc_list__values(Attrs, AttrValues) },
	rl_exprn__generate_bound_2(ModuleInfo, MaybeArgTypes,
		TupleNum, no, AttrValues, empty, Code, 0, 1, MaxDepth).

:- pred rl_exprn__generate_bound_2(module_info::in, maybe(list(type))::in,
	tuple_num::in, bool::in, list(key_attr)::in, byte_tree::in,
	byte_tree::out, int::in, int::in, int::out, rl_exprn_info::in,
	rl_exprn_info::out) is det.

rl_exprn__generate_bound_2(_, _, _, _, [], Code, Code,
		_, MaxDepth, MaxDepth) --> [].
rl_exprn__generate_bound_2(ModuleInfo, MaybeArgTypes, TupleNum, IsSubTerm,
		[Attr | Attrs], Code0, Code, Index0, MaxDepth0, MaxDepth) -->
	rl_exprn__generate_bound_3(ModuleInfo, MaybeArgTypes, IsSubTerm,
		Index0, TupleNum, Attr, AttrCode, Depth),
	{ int__max(MaxDepth0, Depth, MaxDepth1) },
	{ Index is Index0 + 1 },
	rl_exprn__generate_bound_2(ModuleInfo, MaybeArgTypes, TupleNum,
		IsSubTerm, Attrs, tree(Code0, AttrCode),
		Code, Index, MaxDepth1, MaxDepth).

:- pred rl_exprn__generate_bound_3(module_info::in, maybe(list(type))::in,
	bool::in, int::in, tuple_num::in, key_attr::in, byte_tree::out,
	int::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__generate_bound_3(_, _, _, _, _, infinity, _, _, _, _) :-
	% Eventually the B-tree lookup code will be able to handle this case.
	% For now we have to be careful not to generate it in rl_key.m.
	error("rl_exprn__generate_bound_3: embedded infinities NYI").

rl_exprn__generate_bound_3(_ModuleInfo, MaybeArgTypes, IsSubTerm, FieldNum,
		TupleNum, input_field(InputFieldNum), Code, 1, Info, Info) :-
	rl_exprn__get_key_arg(MaybeArgTypes, InputFieldNum, FieldType0),
	rl_exprn__type_to_aditi_type(FieldType0, FieldType),
	rl_exprn__get_input_field_code(one, FieldType, InputFieldNum, GetCode),
	(
		IsSubTerm = yes,
		rl_exprn__set_term_arg_code(FieldType, FieldNum, PutCode)
	;
		IsSubTerm = no,
		rl_exprn__set_output_field_code(TupleNum, FieldType,
			FieldNum, PutCode)
	),
	Code = node([GetCode, PutCode]).
		
rl_exprn__generate_bound_3(ModuleInfo, MaybeArgTypes, IsSubTerm, FieldNum,
		TupleNum, functor(ConsId, Type, Attrs), Code, Depth) -->
	rl_exprn__set_term_arg_cons_id_code(ConsId, Type, TupleNum,
		FieldNum, IsSubTerm, CreateTerm, NeedPop),
	rl_exprn__generate_bound_2(ModuleInfo, MaybeArgTypes, TupleNum, yes,
		Attrs, node(CreateTerm), Code0, 0, 1, Depth0),
	{ NeedPop = yes ->
		Code = tree(Code0, node([rl_EXP_term_pop]))
	;
		Code = Code0
	},
	{ Depth is Depth0 + 1 }.

:- pred rl_exprn__get_key_arg(maybe(list(T))::in, int::in, T::out) is det.

rl_exprn__get_key_arg(yes(Args), Index, Arg) :-
	list__index0_det(Args, Index, Arg).
rl_exprn__get_key_arg(no, _, _) :-
	error("rl_exprn__get_key_arg").

:- pred rl_exprn__set_term_arg_cons_id_code(cons_id::in, (type)::in,
	tuple_num::in, int::in, bool::in, list(bytecode)::out, bool::out,
	rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__set_term_arg_cons_id_code(cons(SymName, Arity), Type, TupleNum,
		FieldNum, IsSubTerm, Code, NeedPop) -->
	( { rl_exprn__is_char_cons_id(cons(SymName, Arity), Type, Int) } ->
		rl_exprn__set_term_arg_cons_id_code(int_const(Int), Type,
			TupleNum, FieldNum, IsSubTerm, Code, NeedPop)
	;
		{
			TupleNum = one,
			ExprnTuple = output1
		;
			TupleNum = two,
			ExprnTuple = output2
		},
		rl_exprn__cons_id_to_rule_number(cons(SymName, Arity), Type,
			ExprnTuple, Rule),
		{
			IsSubTerm = no,
			(
				TupleNum = one,
				Code = [rl_EXP_new_term_output1(FieldNum,
					Rule)]
			;
				TupleNum = two,
				Code = [rl_EXP_new_term_output2(FieldNum,
					Rule)]
			),
			NeedPop = no
		;
			IsSubTerm = yes,
			Code = [
				rl_EXP_term_dup,
				rl_EXP_set_term_arg(FieldNum, Rule)
			],
			NeedPop = yes
		}
	).
rl_exprn__set_term_arg_cons_id_code(int_const(Int), _, TupleNum, FieldNum,
		IsSubTerm, Code, no) -->
	rl_exprn_info_lookup_const(int(Int), Index),
	{ rl_exprn__set_term_arg_cons_id_code_2(int, TupleNum,
		FieldNum, IsSubTerm, SetArgCode) },
	{ Code0 = [rl_EXP_int_push(Index), SetArgCode] },
	{ IsSubTerm = yes ->
		Code = [rl_EXP_term_dup | Code0]
	;
		Code = Code0
	}.
rl_exprn__set_term_arg_cons_id_code(float_const(Float), _, TupleNum, FieldNum,
		IsSubTerm, Code, no) -->
	rl_exprn_info_lookup_const(float(Float), Index),
	{ rl_exprn__set_term_arg_cons_id_code_2(float, TupleNum,
		FieldNum, IsSubTerm, SetArgCode) },
	{ Code0 = [rl_EXP_flt_push(Index), SetArgCode] },
	{ IsSubTerm = yes ->
		Code = [rl_EXP_term_dup | Code0]
	;
		Code = Code0
	}.
rl_exprn__set_term_arg_cons_id_code(string_const(Str), _, TupleNum, FieldNum,
		IsSubTerm, Code, no) -->
	rl_exprn_info_lookup_const(string(Str), Index),
	{ rl_exprn__set_term_arg_cons_id_code_2(string, TupleNum,
		FieldNum, IsSubTerm, SetArgCode) },
	{ Code0 = [rl_EXP_str_push(Index), SetArgCode] },
	{ IsSubTerm = yes ->
		Code = [rl_EXP_term_dup | Code0]
	;
		Code = Code0
	}.
rl_exprn__set_term_arg_cons_id_code(pred_const(_, _), _, _, _, _, _, _) -->
	{ error("rl_exprn__set_term_arg_cons_id_code") }.
rl_exprn__set_term_arg_cons_id_code(code_addr_const(_, _),
		_, _, _, _, _, _) -->
	{ error("rl_exprn__set_term_arg_cons_id_code") }.
rl_exprn__set_term_arg_cons_id_code(type_ctor_info_const(_, _, _),
		_, _, _, _, _, _) -->
	{ error("rl_exprn__set_term_arg_cons_id_code") }.
rl_exprn__set_term_arg_cons_id_code(base_typeclass_info_const(_, _, _, _),
		_, _, _, _, _, _) -->
	{ error("rl_exprn__set_term_arg_cons_id_code") }.
rl_exprn__set_term_arg_cons_id_code(tabling_pointer_const(_, _),
		_, _, _, _, _, _) -->
	{ error("rl_exprn__set_term_arg_cons_id_code") }.

:- pred rl_exprn__set_term_arg_cons_id_code_2(aditi_type::in, tuple_num::in,
		int::in, bool::in, bytecode::out) is det.

rl_exprn__set_term_arg_cons_id_code_2(int, one, FieldNum,
		no, rl_EXP_output1_int(FieldNum)).
rl_exprn__set_term_arg_cons_id_code_2(int, two, FieldNum,
		no, rl_EXP_output2_int(FieldNum)).
rl_exprn__set_term_arg_cons_id_code_2(int, _, FieldNum,
		yes, rl_EXP_set_int_arg(FieldNum)).
rl_exprn__set_term_arg_cons_id_code_2(float, one, FieldNum,
		no, rl_EXP_output1_flt(FieldNum)).
rl_exprn__set_term_arg_cons_id_code_2(float, two, FieldNum,
		no, rl_EXP_output2_flt(FieldNum)).
rl_exprn__set_term_arg_cons_id_code_2(float, _, FieldNum,
		yes, rl_EXP_set_flt_arg(FieldNum)).
rl_exprn__set_term_arg_cons_id_code_2(string, one, FieldNum,
		no, rl_EXP_output1_str(FieldNum)).
rl_exprn__set_term_arg_cons_id_code_2(string, two, FieldNum,
		no, rl_EXP_output2_str(FieldNum)).
rl_exprn__set_term_arg_cons_id_code_2(string, _, FieldNum,
		yes, rl_EXP_set_str_arg(FieldNum)).
rl_exprn__set_term_arg_cons_id_code_2(term(_), _, _, _, _) :-
	error("rl_exprn__set_term_arg_cons_id_code_2").

%-----------------------------------------------------------------------------%

rl_exprn__generate(ModuleInfo, RLGoal, Code, NumParams, Mode, Decls) :-
	RLGoal = rl_goal(_, VarSet, VarTypes, InstMap,
		Inputs, MaybeOutputs, Goals, _), 
	rl_exprn_info_init(ModuleInfo, InstMap, VarTypes, VarSet, Info0),
	rl_exprn__generate_2(Inputs, MaybeOutputs, Goals,
		Code, NumParams, Mode, Decls, Info0, _).

:- pred rl_exprn__generate_2(rl_goal_inputs::in, rl_goal_outputs::in,
	list(hlds_goal)::in, list(bytecode)::out, int::out, exprn_mode::out,
	list(type)::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__generate_2(Inputs, MaybeOutputs, GoalList, 
		Code, NumParams, Mode, Decls) -->
	{ goal_list_determinism(GoalList, Detism) },
	{ determinism_components(Detism, CanFail, _) },
	{ goal_list_nonlocals(GoalList, NonLocals0) },
	{ MaybeOutputs = yes(OutputNonLocals) ->
		set__insert_list(NonLocals0, OutputNonLocals, NonLocals)
	;
		NonLocals = NonLocals0
	},
	( 
		{ Inputs = no_inputs },
		{ NumParams = 0 },
		{ InputCode = empty }
	;
		{ Inputs = one_input(InputVars) },
		{ NumParams = 1 },
		rl_exprn__deconstruct_input_tuple(one, 0, InputVars,
			NonLocals, InputCode)
	;
		{ Inputs = two_inputs(InputVars1, InputVars2) },
		{ NumParams = 2 },
		rl_exprn__deconstruct_input_tuple(one, 0,
			InputVars1, NonLocals, InputCode1),
		rl_exprn__deconstruct_input_tuple(two, 0,
			InputVars2, NonLocals, InputCode2),
		{ InputCode = tree(InputCode1, InputCode2) }
	),

	{ CanFail = can_fail ->
		Fail = node([rl_EXP_return_false])
	;
		% Should cause an error if it is encountered.
		Fail = node([rl_EXP_last_bytecode])
	},

	rl_exprn__goals(GoalList, Fail, GoalCode),

	( { MaybeOutputs = yes(OutputVars) } ->
		rl_exprn__construct_output_tuple(GoalList,
			OutputVars, OutputCode),
		{ Mode = generate }
	;
		{ OutputCode = empty },
		{ Mode = test }
	),

	{ 
		CanFail = can_fail,
		EvalCode0 =
			tree(InputCode,
			GoalCode
		),
		rl_exprn__resolve_addresses(EvalCode0, EvalCode1),
		EvalCode = tree(node([rl_PROC_expr_frag(2)]), EvalCode1),
		( OutputCode = empty ->
			ProjectCode = empty	
		;
			ProjectCode =
				tree(node([rl_PROC_expr_frag(3)]),
				OutputCode)
		)
	;
		CanFail = cannot_fail,
		% For projections, the eval fragment is not run.
		EvalCode = empty,
		ProjectCode0 =
			tree(InputCode,
			tree(GoalCode,
			OutputCode
		)),
		rl_exprn__resolve_addresses(ProjectCode0, ProjectCode1),
		ProjectCode = tree(node([rl_PROC_expr_frag(3)]), ProjectCode1)
	},

	% Need to do the init code last, since it also needs to define
	% the rule constants for the other fragments.
	rl_exprn__generate_init_fragment(InitCode),

	rl_exprn_info_get_consts(Consts - _),
	{ map__to_assoc_list(Consts, ConstsAL) },
	{ assoc_list__reverse_members(ConstsAL, ConstsLA0) },
	{ list__sort(ConstsLA0, ConstsLA) },
	{ list__map(rl_exprn__generate_const_decl, ConstsLA, ConstCode) },
	rl_exprn_info_get_decls(Decls),

	{ CodeTree = 
		tree(node(ConstCode),
		tree(InitCode,
		tree(EvalCode,
		tree(ProjectCode,
		node([rl_PROC_expr_end])
	)))) },
	{ tree__flatten(CodeTree, CodeLists) },
	{ list__condense(CodeLists, Code) }.

:- pred rl_exprn__generate_init_fragment(byte_tree::out,
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__generate_init_fragment(Code) -->
	rl_exprn_info_get_rules(Rules - _),
	{ map__to_assoc_list(Rules, RulesAL) },
	{ assoc_list__reverse_members(RulesAL, RulesLA0) },
	{ list__sort(RulesLA0, RulesLA) },
	list__map_foldl(rl_exprn__generate_rule, RulesLA, RuleCodes),
	( { RuleCodes = [] } ->
		{ Code = empty }
	;
		{ Code = 
			tree(node([rl_PROC_expr_frag(0)]),
			node(RuleCodes)
		) }
	).

:- pred rl_exprn__generate_const_decl(pair(int, rl_const)::in, 
		bytecode::out) is det.

rl_exprn__generate_const_decl(Addr - Const, Code) :-
	( 
		Const = int(Int),
		Code = rl_HEAD_const_int(Addr, Int)
	;
		Const = float(Float),
		Code = rl_HEAD_const_flt(Addr, Float)
	;
		Const = string(Str),
		Code = rl_HEAD_const_str(Addr, Str)
	).

:- pred rl_exprn__generate_rule(pair(int, pair(rl_rule, exprn_tuple))::in,			 bytecode::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__generate_rule(RuleNo - (Rule - RuleTuple), Code) -->
	{ Rule = rl_rule(Type, Name, Arity) },
	rl_exprn_info_lookup_const(string(Type), TypeIndex),
	rl_exprn_info_lookup_const(string(Name), NameIndex),
	{
		RuleTuple = input1,
		Code = rl_EXP_define_input1_rule(RuleNo,
			TypeIndex, NameIndex, Arity)
	;
		RuleTuple = input2,
		Code = rl_EXP_define_input2_rule(RuleNo,
			TypeIndex, NameIndex, Arity)
	;
		RuleTuple = variables,
		Code = rl_EXP_define_var_rule(RuleNo,
			TypeIndex, NameIndex, Arity)
	;
		RuleTuple = output1,
		Code = rl_EXP_define_output1_rule(RuleNo,
			TypeIndex, NameIndex, Arity)
	;
		RuleTuple = output2,
		Code = rl_EXP_define_output2_rule(RuleNo,
			TypeIndex, NameIndex, Arity)
	}.

%-----------------------------------------------------------------------------%

	% Shift the inputs to the expression out of the input tuple.
:- pred rl_exprn__deconstruct_input_tuple(tuple_num::in, int::in, 
	list(prog_var)::in, set(prog_var)::in, byte_tree::out,
	rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__deconstruct_input_tuple(_, _, [], _, empty) --> [].
rl_exprn__deconstruct_input_tuple(TupleNo, FieldNo, [Var | Vars],
		NonLocals, Code) -->
	( { set__member(Var, NonLocals) } ->
		rl_exprn_info_lookup_var(Var, VarReg),
		rl_exprn_info_lookup_var_type(Var, Type),
		rl_exprn__assign(reg(VarReg),
			input_field(TupleNo, FieldNo), Type, Code0)
	;
		{ Code0 = empty }
	),
	{ NextField is FieldNo + 1 },
	rl_exprn__deconstruct_input_tuple(TupleNo, NextField, Vars,
		NonLocals, Code1),
	{ Code = tree(Code0, Code1) }.

	% Move the outputs of the expression into the output tuple.
:- pred rl_exprn__construct_output_tuple(list(hlds_goal)::in,
	list(prog_var)::in, byte_tree::out,
	rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__construct_output_tuple(Goals, Vars, Code) -->
	{ goal_list_determinism(Goals, Detism) },
	( { determinism_components(Detism, _, at_most_zero) } ->
		% The condition never succeeds, so don't try to 
		% construct the output.
		{ Code = empty }	
	;
		{ FirstField = 0 },
		rl_exprn__construct_output_tuple_2(FirstField, Vars, Code)
	).

:- pred rl_exprn__construct_output_tuple_2(int::in, list(prog_var)::in, 
		byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__construct_output_tuple_2(_, [], empty) --> [].
rl_exprn__construct_output_tuple_2(FieldNo, [Var | Vars], Code) -->
	rl_exprn_info_lookup_var(Var, VarReg),
	rl_exprn_info_lookup_var_type(Var, Type),
	rl_exprn__assign(output_field(FieldNo), reg(VarReg), Type, Code0),
	{ NextField is FieldNo + 1 },
	rl_exprn__construct_output_tuple_2(NextField, Vars, Code1),
	{ Code = tree(Code0, Code1) }.

%-----------------------------------------------------------------------------%

:- pred rl_exprn__goals(list(hlds_goal)::in, byte_tree::in,
	byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__goals([], _, empty) --> [].
rl_exprn__goals([Goal | Goals], Fail, Code) --> 
	rl_exprn__goal(Goal, Fail, Code0),
	rl_exprn__goals(Goals, Fail, Code1),
	{ Code = tree(Code0, Code1) }.

:- pred rl_exprn__goal(hlds_goal::in, byte_tree::in, 
	byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__goal(unify(_, _, _, Uni, _) - Info, Fail, Code) -->
	rl_exprn__unify(Uni, Info, Fail, Code).
rl_exprn__goal(call(PredId, ProcId, Args, _, _, _) - Info, Fail, Code) -->
	rl_exprn__call(PredId, ProcId, Args, Info, Fail, Code).
rl_exprn__goal(not(NegGoal) - _, Fail, Code) -->
	rl_exprn_info_get_next_label_id(EndLabel),
	{ NotFail = node([rl_EXP_jmp(EndLabel)]) },
	rl_exprn__goal(NegGoal, NotFail, NegCode),
	{ Code = 
		tree(NegCode, 
		tree(Fail, 
		node([rl_PROC_label(EndLabel)])
	)) }.
rl_exprn__goal(if_then_else(_, Cond, Then, Else, _) - _, Fail, Code) -->
	rl_exprn_info_get_next_label_id(StartElse),
	rl_exprn_info_get_next_label_id(EndIte),
	{ CondFail = node([rl_EXP_jmp(StartElse)]) },
	rl_exprn__goal(Cond, CondFail, CondCode),
	rl_exprn__goal(Then, Fail, ThenCode),
	rl_exprn__goal(Else, Fail, ElseCode),
	{ Code =
		tree(CondCode, 
		tree(ThenCode, 
		tree(node([rl_EXP_jmp(EndIte), rl_PROC_label(StartElse)]),
		tree(ElseCode, 
		node([rl_PROC_label(EndIte)])
	)))) }.
rl_exprn__goal(conj(Goals) - _, Fail, Code) -->
	rl_exprn__goals(Goals, Fail, Code).
rl_exprn__goal(par_conj(_, _) - _, _, _) -->
	{ error("rl_exprn__goal: par_conj not yet implemented") }.
rl_exprn__goal(disj(Goals, _) - _Info, Fail, Code) -->
		% Nondet disjunctions should have been transformed into
		% separate Aditi predicates by dnf.m.
	rl_exprn_info_get_next_label_id(EndDisj),
	{ GotoEnd = node([rl_EXP_jmp(EndDisj)]) },
	rl_exprn__disj(Goals, GotoEnd, Fail, DisjCode),
	{ Code = tree(DisjCode, node([rl_PROC_label(EndDisj)])) }.
rl_exprn__goal(switch(Var, _, Cases, _) - _, Fail, Code) -->
	rl_exprn_info_get_next_label_id(EndSwitch),
	{ GotoEnd = node([rl_EXP_jmp(EndSwitch)]) },
	rl_exprn__cases(Var, Cases, GotoEnd, Fail, SwitchCode),
	{ Code = tree(SwitchCode, node([rl_PROC_label(EndSwitch)])) }.
rl_exprn__goal(higher_order_call(_, _, _, _, _, _) - _, _, _) -->
	{ error("rl_exprn__goal: higher-order call not yet implemented") }.
rl_exprn__goal(class_method_call(_, _, _, _, _, _) - _, _, _) -->
	{ error("rl_exprn__goal: class method calls not yet implemented") }.
rl_exprn__goal(pragma_c_code(_, _, _, _, _, _, _) - _, _, _) -->
	{ error("rl_exprn__goal: pragma_c_code not yet implemented") }.
rl_exprn__goal(some(_, Goal) - _, Fail, Code) -->
	rl_exprn__goal(Goal, Fail, Code).

:- pred rl_exprn__cases(prog_var::in, list(case)::in, byte_tree::in,
		byte_tree::in, byte_tree::out, 
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__cases(_, [], _, Fail, Fail) --> [].
rl_exprn__cases(Var, [case(ConsId, Goal) | Cases], Succeed, Fail, Code) -->
	rl_exprn_info_get_next_label_id(NextCase),
	{ Jmp = rl_EXP_jmp(NextCase) },
	rl_exprn__functor_test(Var, ConsId, node([Jmp]), TestCode),
	rl_exprn__goal(Goal, Fail, GoalCode),
	rl_exprn__cases(Var, Cases, Succeed, Fail, Code1),
	{ Code = 
		tree(TestCode,
		tree(GoalCode,
		tree(Succeed, 
		tree(node([rl_PROC_label(NextCase)]),
		Code1
	)))) }.

:- pred rl_exprn__disj(list(hlds_goal)::in, byte_tree::in,
		byte_tree::in, byte_tree::out, 
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__disj([], _, Fail, Fail) --> [].
rl_exprn__disj([Goal | Goals], Succeed, Fail, Code) -->
	rl_exprn_info_get_next_label_id(NextDisj),
	{ TryNext = node([rl_EXP_jmp(NextDisj)]) },
	{ NextLabel = node([rl_PROC_label(NextDisj)]) },
	rl_exprn__goal(Goal, TryNext, GoalCode),
	rl_exprn__disj(Goals, Succeed, Fail, Code1),
	{ Code = 
		tree(GoalCode,
		tree(Succeed,
		tree(NextLabel,
		Code1
	))) }.

%-----------------------------------------------------------------------------%

:- pred rl_exprn__call(pred_id::in, proc_id::in, list(prog_var)::in, 
		hlds_goal_info::in, byte_tree::in, byte_tree::out, 
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__call(PredId, ProcId, Vars, _GoalInfo, Fail, Code) -->
	rl_exprn_info_get_module_info(ModuleInfo),
	{ module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
		PredInfo, ProcInfo) },
	{ proc_info_inferred_determinism(ProcInfo, Detism) },
	( { determinism_components(Detism, _, at_most_many) } ->
		{ error("Sorry, not yet implemented - nondeterministic Mercury calls in Aditi procedures") }
	;
		{ pred_info_is_imported(PredInfo) },
		{ \+ code_util__predinfo_is_builtin(PredInfo) }
	->
		{ error("Sorry, not yet implemented - calls to imported Mercury procedures from Aditi") }
	;
		rl_exprn__call_body(PredId, ProcId, PredInfo, ProcInfo,
			Fail, Vars, Code)
	).

:- pred rl_exprn__call_body(pred_id::in, proc_id::in, pred_info::in,
	proc_info::in, byte_tree::in, list(prog_var)::in, byte_tree::out,
	rl_exprn_info::in, rl_exprn_info::out) is det.  

rl_exprn__call_body(PredId, ProcId, PredInfo, ProcInfo, Fail, Args, Code) -->
	{ pred_info_name(PredInfo, PredName) },
	{ pred_info_arity(PredInfo, Arity) },
	( { code_util__predinfo_is_builtin(PredInfo) } ->
		rl_exprn__generate_builtin_call(PredId, ProcId, PredInfo,
			Args, Fail, Code)
	;
		% Handle unify/2 specially, since it is possibly recursive,
		% which will cause the code below to fall over. Also, magic.m
		% doesn't add type_info arguments yet.
		{ PredName = "__Unify__" },
		{ Arity = 2 },
		{ list__reverse(Args, [Arg1, Arg2 | _]) },
		{ hlds_pred__in_in_unification_proc_id(ProcId) }
	->
		rl_exprn_info_lookup_var(Arg1, Arg1Loc),
		rl_exprn_info_lookup_var(Arg2, Arg2Loc),
		rl_exprn_info_lookup_var_type(Arg1, Type),
		rl_exprn__test(reg(Arg1Loc), reg(Arg2Loc), Type, Fail, Code)
	;
		% Handle compare/3 specially for the same reason
		% as unify/2 above.
		{ PredName = "__Compare__" },
		{ Arity = 3 },
		{ list__reverse(Args, [Arg2, Arg1, Res | _]) }
	->
		rl_exprn_info_lookup_var(Arg1, Arg1Loc),
		rl_exprn_info_lookup_var(Arg2, Arg2Loc),
		rl_exprn_info_lookup_var(Res, ResultReg),
		rl_exprn_info_lookup_var_type(Arg1, Type),
		rl_exprn_info_lookup_var_type(Res, ResType),
		rl_exprn__generate_push(reg(Arg1Loc), Type, PushCode1),
		rl_exprn__generate_push(reg(Arg2Loc), Type, PushCode2),
		{ rl_exprn__type_to_aditi_type(Type, AditiType) },
		{ rl_exprn__compare_bytecode(AditiType, Compare) },

		{ EQConsId = cons(qualified(unqualified("mercury_builtin"),
				"="), 0) },
		{ LTConsId = cons(qualified(unqualified("mercury_builtin"),
				"<"), 0) },
		{ GTConsId = cons(qualified(unqualified("mercury_builtin"),
				">"), 0) },
		rl_exprn__cons_id_to_rule_number(EQConsId, ResType, EQRuleNo),
		rl_exprn__cons_id_to_rule_number(GTConsId, ResType, GTRuleNo),
		rl_exprn__cons_id_to_rule_number(LTConsId, ResType, LTRuleNo),
		
		rl_exprn_info_get_next_label_id(GTLabel),
		rl_exprn_info_get_next_label_id(LTLabel),
		rl_exprn_info_get_next_label_id(EndLabel),

		{ Code = 
			tree(PushCode1,
			tree(PushCode2,
			node([
				Compare,
				rl_EXP_b3way(LTLabel, GTLabel),
				rl_EXP_new_term_var(ResultReg, EQRuleNo),
				rl_EXP_term_pop,
				rl_EXP_jmp(EndLabel),
				rl_PROC_label(LTLabel),
				rl_EXP_new_term_var(ResultReg, LTRuleNo),
				rl_EXP_term_pop,
				rl_EXP_jmp(EndLabel),
				rl_PROC_label(GTLabel),
				rl_EXP_new_term_var(ResultReg, GTRuleNo),
				rl_EXP_term_pop,
				rl_PROC_label(EndLabel)
			])
		)) }
	;
		% XXX temporary hack until we allow Mercury calls from Aditi -
		% generate the goal of the called procedure, not a call to 
		% the called procedure, checking first that the call is not
		% recursive.

		rl_exprn_info_get_parent_pred_proc_ids(Parents0),
		( { set__member(proc(PredId, ProcId), Parents0) } ->
			{ error("sorry, recursive Mercury calls in Aditi-RL code are not yet implemented") }
		;	
			[]
		),
		{ set__insert(Parents0, proc(PredId, ProcId), Parents) },
		rl_exprn_info_set_parent_pred_proc_ids(Parents),
		rl_exprn__inline_call(PredId, ProcId,
			PredInfo, ProcInfo, Args, Goal),
		rl_exprn__goal(Goal, Fail, Code),
		rl_exprn_info_set_parent_pred_proc_ids(Parents0)
	).

:- pred rl_exprn__inline_call(pred_id::in, proc_id::in, pred_info::in,
		proc_info::in, list(prog_var)::in, hlds_goal::out,
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__inline_call(_PredId, _ProcId, CalledPredInfo,
		CalledProcInfo, Args, Goal) -->

	rl_exprn_info_get_varset(VarSet0),
	rl_exprn_info_get_vartypes(VarTypes0),
	{ varset__init(TVarSet0) },
	{ map__init(TVarMap0) },
	{ inlining__do_inline_call([], Args, CalledPredInfo, CalledProcInfo,
		VarSet0, VarSet, VarTypes0, VarTypes, TVarSet0, _, TVarMap0, _,
		Goal) },

	rl_exprn_info_set_varset(VarSet),
	rl_exprn_info_set_vartypes(VarTypes).

%-----------------------------------------------------------------------------%

:- pred rl_exprn__unify(unification::in, hlds_goal_info::in, 
		byte_tree::in, byte_tree::out,
		rl_exprn_info::in, rl_exprn_info::out) is det.
	
rl_exprn__unify(construct(Var, ConsId, Args, UniModes), 
		GoalInfo, _Fail, Code) -->
	rl_exprn_info_lookup_var_type(Var, Type),
	rl_exprn_info_lookup_var(Var, VarReg),
	( 
		{ ConsId = cons(SymName, _) },
		(
			{ SymName = qualified(unqualified("mercury_builtin"),
					TypeInfo) },
			( { TypeInfo = "type_info" }
			; { TypeInfo = "type_ctor_info" }
			)
		->
			% XXX for now we ignore these and hope it doesn't
			% matter. They may be introduced for calls to the
			% automatically generated unification and comparison
			% procedures.
			{ Code = empty }
		;
			{ rl_exprn__is_char_cons_id(ConsId, Type, Int) }
		->
			rl_exprn__assign(reg(VarReg), const(int(Int)),
				Type, Code)
		;
			rl_exprn__cons_id_to_rule_number(ConsId, Type, RuleNo),
			{ Create = rl_EXP_new_term_var(VarReg, RuleNo) },
			{ goal_info_get_nonlocals(GoalInfo, NonLocals) },
			rl_exprn__handle_functor_args(Args, UniModes,
				NonLocals, 0, ConsId, ArgCodes),
			{ Code =
				tree(node([Create]),
				tree(ArgCodes,
				node([rl_EXP_term_pop])
			)) }
		)
	;
		{ ConsId = int_const(Int) },
		rl_exprn__assign(reg(VarReg), const(int(Int)), Type, Code)
	;
		{ ConsId = string_const(String) },
		rl_exprn__assign(reg(VarReg), const(string(String)),
			Type, Code)
	;
		{ ConsId = float_const(Float) },
		rl_exprn__assign(reg(VarReg), const(float(Float)), Type, Code)
	; 
		{ ConsId = pred_const(_, _) },
		{ error("rl_exprn__unify: unsupported cons_id - pred_const") }
	; 
		{ ConsId = code_addr_const(_, _) },
		{ error("rl_exprn__unify: unsupported cons_id - code_addr_const") }
	; 
		{ ConsId = type_ctor_info_const(_, _, _) },
		% XXX for now we ignore these and hope it doesn't matter.
		% They may be introduced for calls to the automatically
		% generated unification and comparison procedures.
		{ Code = empty }
	; 
		{ ConsId = base_typeclass_info_const(_, _, _, _) },
		{ error("rl_exprn__unify: unsupported cons_id - base_typeclass_info_const") }
	; 
		{ ConsId = tabling_pointer_const(_, _) },
		{ error("rl_exprn__unify: unsupported cons_id - tabling_pointer_const") }
	).
		
rl_exprn__unify(deconstruct(Var, ConsId, Args, UniModes, CanFail),
		GoalInfo, Fail, Code) -->
	rl_exprn_info_lookup_var(Var, VarLoc),
	rl_exprn_info_lookup_var_type(Var, Type),
	( { CanFail = can_fail } ->
		rl_exprn__functor_test(Var, ConsId, Fail, TestCode)
	;
		{ TestCode = empty }
	),
	( { Args \= [] } ->
		{ goal_info_get_nonlocals(GoalInfo, NonLocals) },
		rl_exprn__generate_push(reg(VarLoc), Type, PushCode),
		rl_exprn__handle_functor_args(Args, UniModes, 
			NonLocals, 0, ConsId, ArgCodes0),
		{ ArgCodes =
			tree(PushCode,
			tree(ArgCodes0,
			node([rl_EXP_term_pop])
		)) }
	;
		{ ArgCodes = empty }
	),
	{ Code = tree(TestCode, ArgCodes) }.
rl_exprn__unify(complicated_unify(_, _, _), _, _, _) -->
	{ error("rl_gen__unify: complicated_unify") }.
rl_exprn__unify(assign(Var1, Var2), _GoalInfo, _Fail, Code) -->
	rl_exprn_info_lookup_var(Var1, Var1Loc),
	rl_exprn_info_lookup_var(Var2, Var2Loc),
	rl_exprn_info_lookup_var_type(Var1, Type),
	rl_exprn__assign(reg(Var1Loc), reg(Var2Loc), Type, Code).
rl_exprn__unify(simple_test(Var1, Var2), _GoalInfo, Fail, Code) -->
	% Note that the type here isn't necessarily one of the builtins - 
	% magic.m uses simple_test for all in-in unifications it introduces.
	rl_exprn_info_lookup_var(Var1, Var1Loc),
	rl_exprn_info_lookup_var(Var2, Var2Loc),
	rl_exprn_info_lookup_var_type(Var1, Type),
	rl_exprn__test(reg(Var1Loc), reg(Var2Loc), Type, Fail, Code).

:- pred rl_exprn__assign(rl_lval::in, rl_rval::in, (type)::in,
	byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__assign(Lval, Rval, Type, Code) -->
	rl_exprn__generate_push(Rval, Type, PushCode),
	rl_exprn__generate_pop(Lval, Type, PopCode),
	{ Code = tree(PushCode, PopCode) }.

:- pred rl_exprn__test(rl_rval::in, rl_rval::in, (type)::in, byte_tree::in,
	byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__test(Var1Loc, Var2Loc, Type, Fail, Code) -->
	rl_exprn__generate_push(Var1Loc, Type, PushCode1),
	rl_exprn__generate_push(Var2Loc, Type, PushCode2),
	rl_exprn_info_get_next_label_id(Label),
	{ rl_exprn__type_to_aditi_type(Type, AditiType) },
	{
		AditiType = int,
		EqInstr = rl_EXP_int_eq
	;
		AditiType = float,
		EqInstr = rl_EXP_flt_eq
	;
		AditiType = string,
		EqInstr = rl_EXP_str_eq
	;
		AditiType = term(_),
		EqInstr = rl_EXP_term_eq
	},
	{ Code = 
		tree(PushCode1, 
		tree(PushCode2, 
		tree(node([EqInstr]), 
		tree(node([rl_EXP_bnez(Label)]),
		tree(Fail,
		node([rl_PROC_label(Label)])
	))))) }.

:- pred rl_exprn__functor_test(prog_var::in, cons_id::in, byte_tree::in, 
	byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__functor_test(Var, ConsId, Fail, Code) -->
	rl_exprn_info_lookup_var(Var, VarReg),
	rl_exprn_info_lookup_var_type(Var, Type),
	( { ConsId = int_const(Int) } ->
		rl_exprn__test(reg(VarReg), const(int(Int)), Type, Fail, Code)
	; { ConsId = string_const(String) } ->
		rl_exprn__test(reg(VarReg), const(string(String)),
			Type, Fail, Code)
	; { ConsId = float_const(Float) } ->
		rl_exprn__test(reg(VarReg), const(float(Float)),
			Type, Fail, Code)
	; { rl_exprn__is_char_cons_id(ConsId, Type, Int) } ->
		rl_exprn__test(reg(VarReg), const(int(Int)), Type, Fail, Code)
	; { ConsId = cons(_, _) } ->
		rl_exprn_info_get_next_label_id(Label),
		rl_exprn__cons_id_to_rule_number(ConsId, Type, RuleNo),
		rl_exprn__generate_push(reg(VarReg), Type, PushCode),
		{ Code = 
			tree(PushCode,
			tree(node([
				rl_EXP_test_functor(RuleNo),
				rl_EXP_bnez(Label)
			]),
			tree(Fail,
			node([rl_PROC_label(Label)])
		))) }
	;
		{ error("rl_exprn__functor_test: unsupported cons_id") }
	).

:- pred rl_exprn__is_char_cons_id(cons_id::in, 
		(type)::in, int::out) is semidet.

rl_exprn__is_char_cons_id(ConsId, Type, Int) :-
	ConsId = cons(unqualified(CharStr), 0),
	type_to_type_id(Type, unqualified("character") - 0, _),
		% Convert characters to integers.
	( string__to_char_list(CharStr, [Char]) ->
		char__to_int(Char, Int)
	;
		error("rl_exprn__unify: invalid char")
	).

:- pred rl_exprn__handle_functor_args(list(prog_var)::in, list(uni_mode)::in,
		set(prog_var)::in, int::in, cons_id::in, byte_tree::out,
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__handle_functor_args([], [_|_], _, _, _, _) -->
	{ error("rl_exprn__handle_functor_args") }.
rl_exprn__handle_functor_args([_|_], [], _, _, _, _) -->
	{ error("rl_exprn__handle_functor_args") }.
rl_exprn__handle_functor_args([], [], _, _, _, empty) --> [].
rl_exprn__handle_functor_args([Arg | Args], [Mode | Modes], NonLocals,
		Index, ConsId, Code) -->
	{ NextIndex is Index + 1 },
	rl_exprn__handle_functor_args(Args, Modes, NonLocals,
		NextIndex, ConsId, Code0),
	( { set__member(Arg, NonLocals) } ->
		rl_exprn_info_lookup_var_type(Arg, Type),
		rl_exprn_info_get_module_info(ModuleInfo),

		{ Mode = ((LI - RI) -> (LF - RF)) },
		{ mode_to_arg_mode(ModuleInfo, (LI -> LF), Type, LeftMode) },
		{ mode_to_arg_mode(ModuleInfo, (RI -> RF), Type, RightMode) },
		(
			{ LeftMode = top_in },
			{ RightMode = top_in }
		->
			% Can't have test in arg unification.
			{ error("test in arg of [de]construction") }
		;
			{ LeftMode = top_in },
			{ RightMode = top_out }
		->
			rl_exprn_info_lookup_var(Arg, ArgReg),
			{ rl_exprn__type_to_aditi_type(Type, AditiType) },
			{ rl_exprn__get_term_arg_code(AditiType,
				Index, TermArgCode) },
			rl_exprn__generate_pop(reg(ArgReg), Type, PopCode),
			{ Code1 =
				tree(node([rl_EXP_term_dup]),
				tree(node([TermArgCode]),
				PopCode
			)) }
		;
			{ LeftMode = top_out },
			{ RightMode = top_in }
		->
			rl_exprn_info_lookup_var(Arg, ArgLoc),
			{ rl_exprn__type_to_aditi_type(Type, AditiType) },
			{ rl_exprn__set_term_arg_code(AditiType,
				Index, TermArgCode) },
			rl_exprn__generate_push(reg(ArgLoc), Type, PushCode),
			{ Code1 =
				tree(node([rl_EXP_term_dup]),
				tree(PushCode,
				node([TermArgCode])
			)) }
		;
			{ LeftMode = top_unused },
			{ RightMode = top_unused }
		->
			{ Code1 = empty }
		;	
			{ error("rl_exprn__handle_functor_args: weird unification") }
		),
		{ Code = tree(Code1, Code0) }
	;
		{ Code = Code0 }
	).

%-----------------------------------------------------------------------------%

:- pred rl_exprn__cons_id_to_rule_number(cons_id::in, (type)::in, int::out, 
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__cons_id_to_rule_number(ConsId, Type, RuleNo) -->
	rl_exprn__cons_id_to_rule_number(ConsId, Type, variables, RuleNo).

:- pred rl_exprn__cons_id_to_rule_number(cons_id::in, (type)::in,
		exprn_tuple::in, int::out,
		rl_exprn_info::in, rl_exprn_info::out) is det.
	
rl_exprn__cons_id_to_rule_number(ConsId, Type, ExprnTuple, RuleNo) -->
	( 
		{ ConsId = cons(ConsName, Arity) },
		{ type_to_type_id(Type, TypeId, Args) }
	->
		% These names should not be quoted, since they are not
		% being parsed, just compared against other strings.
		{ rl__mangle_type_name(TypeId, Args, MangledTypeName) },
		{ rl__mangle_ctor_name(ConsName, Arity, MangledConsName) },
		{ Rule = rl_rule(MangledTypeName, MangledConsName, Arity) },
		rl_exprn_info_lookup_rule(Rule - ExprnTuple, RuleNo)
	;
		{ error("rl_exprn__cons_id_to_rule_number") }
	).

%-----------------------------------------------------------------------------%

	% Put a value on top of the expression stack.
:- pred rl_exprn__generate_push(rl_rval::in, (type)::in, byte_tree::out,
		rl_exprn_info::in, rl_exprn_info::out) is det.
	
rl_exprn__generate_push(reg(Reg), Type0, Code) -->
	{ rl_exprn__type_to_aditi_type(Type0, Type) },
	rl_exprn__do_generate_push_var(Reg, Type, Code).

rl_exprn__generate_push(const(Const), _Type, node([ByteCode])) -->
	rl_exprn_info_lookup_const(Const, ConstNo),
	{
		Const = int(_),
		ByteCode = rl_EXP_int_push(ConstNo)
	;
		Const = float(_),
		ByteCode = rl_EXP_flt_push(ConstNo)
	;
		Const = string(_),
		ByteCode = rl_EXP_str_push(ConstNo)
	}.
rl_exprn__generate_push(input_field(TupleNo, FieldNo), 
		Type0, node([ByteCode])) -->
	{ rl_exprn__type_to_aditi_type(Type0, Type) },
	{ rl_exprn__get_input_field_code(TupleNo, Type, FieldNo, ByteCode) }.
rl_exprn__generate_push(term_arg(TermLoc, _ConsId, Field, TermType), 
		Type0, ByteCodes) -->
	{ rl_exprn__type_to_aditi_type(Type0, AditiType) },
	rl_exprn__generate_push(TermLoc, TermType, PushCodes),
	{ 
		AditiType = int,
		ByteCode = rl_EXP_get_int_arg(Field)
	;
		AditiType = float,
		ByteCode = rl_EXP_get_flt_arg(Field)
	;
		AditiType = string,
		ByteCode = rl_EXP_get_str_arg(Field)
	;
		AditiType = term(_),
		ByteCode = rl_EXP_get_term_arg(Field)
	},
	{ ByteCodes = 
		tree(PushCodes, 
		node([ByteCode])
	) }.

:- pred rl_exprn__do_generate_push_var(int::in, aditi_type::in,
	byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__do_generate_push_var(Index, Type, node([ByteCode])) -->
	{
		Type = int,
		ByteCode = rl_EXP_int_push_var(Index)
	;
		Type = float,
		ByteCode = rl_EXP_flt_push_var(Index)
	;
		Type = string,
		ByteCode = rl_EXP_str_push_var(Index)
	;
		Type = term(_),
		ByteCode = rl_EXP_term_push_var(Index)
	}.

%-----------------------------------------------------------------------------%

	% Get the value on top of the expression stack and put it in the 
	% specified rl_lval.
:- pred rl_exprn__generate_pop(rl_lval::in, (type)::in, byte_tree::out,
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__generate_pop(reg(Reg), Type0, ByteCode) -->
	{ rl_exprn__type_to_aditi_type(Type0, Type) },
	rl_exprn__do_generate_pop_var(Reg, Type, ByteCode).

rl_exprn__generate_pop(output_field(FieldNo), Type0, node([ByteCode])) -->
	{ rl_exprn__type_to_aditi_type(Type0, Type) },
	{
		Type = int,
		ByteCode = rl_EXP_output_int(FieldNo)
	;
		Type = float,
		ByteCode = rl_EXP_output_flt(FieldNo)
	;
		Type = string,
		ByteCode = rl_EXP_output_str(FieldNo)
	;
		Type = term(_),
		% This bytecode copies the argument term adjusting rule numbers
		% if the schemas of the argument term and the output tuple 
		% do not match.
		ByteCode = rl_EXP_put_term_output(FieldNo)
	}.
rl_exprn__generate_pop(term_arg(Reg, _ConsId, Field, TermType), Type0, Code) -->
	% There's no swap operation (and to do a swap, the expression
	% evaluator would probably need to know the types of the top
	% two elements of the stack, so rl_EXP_swap_int_int,
	% rl_EXP_swap_int_flt, etc). 
	{ rl_exprn__type_to_aditi_type(Type0, Type) },
	rl_exprn_info_get_free_reg(Type0, TmpIndex),
	rl_exprn__generate_pop(reg(TmpIndex), Type0, PopCode1),
	rl_exprn__generate_push(reg(Reg), TermType, PushCode1),
	rl_exprn__generate_push(reg(TmpIndex), Type0, PushCode2),
	(
		{ Type = int },
		{ SetArg = rl_EXP_set_int_arg(Field) }
	;
		{ Type = float },
		{ SetArg = rl_EXP_set_flt_arg(Field) }
	;
		{ Type = string },
		{ SetArg = rl_EXP_set_str_arg(Field) }
	;
		{ Type = term(_) },
		{ SetArg = rl_EXP_put_term_arg(Field) }
	),
	{ Code = 
		tree(PopCode1, 
		tree(PushCode1, 
		tree(PushCode2, 
		node([SetArg])
	))) }.

:- pred rl_exprn__do_generate_pop_var(int::in, aditi_type::in, byte_tree::out,
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__do_generate_pop_var(Index, Type, node([ByteCode])) -->
	{
		Type = int,
		ByteCode = rl_EXP_int_pop_var(Index)
	;
		Type = float,
		ByteCode = rl_EXP_flt_pop_var(Index)
	;
		Type = string,
		ByteCode = rl_EXP_str_pop_var(Index)
	;
		Type = term(_),
		ByteCode = rl_EXP_put_term_var(Index)
	}.	

%-----------------------------------------------------------------------------%

:- pred rl_exprn__generate_builtin_call(pred_id::in, proc_id::in,
	pred_info::in, list(prog_var)::in, byte_tree::in,
	byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__generate_builtin_call(_PredId, ProcId,
		PredInfo, Args, Fail, Code) -->
	{ pred_info_module(PredInfo, PredModule0) },
	{ pred_info_name(PredInfo, PredName) },

	%
	% Generate LLDS for the builtin, then convert that to Aditi bytecode.
	%
	(
		{ code_util__translate_builtin(PredModule0, PredName, 
			ProcId, Args, MaybeTest, MaybeAsg) } 
	->
		( { MaybeTest = yes(TestRval) } ->
			( rl_exprn__llds_rval_to_rl_rval(TestRval, RvalCode) ->
				rl_exprn_info_get_next_label_id(SuccLabel),
				{ Code =
					tree(RvalCode,
					tree(node([rl_EXP_bnez(SuccLabel)]),
					tree(Fail,
					node([rl_PROC_label(SuccLabel)])
				))) }
			;
				{ error("rl_exprn__generate_exprn_instr: invalid test") }
			)
		 ; { MaybeAsg = yes(OutputVar - AsgRval) } ->
			rl_exprn_info_lookup_var(OutputVar, OutputLoc),
			rl_exprn_info_lookup_var_type(OutputVar, Type),
			{ rl_exprn__type_to_aditi_type(Type, AditiType) },
			rl_exprn__maybe_llds_rval_to_rl_rval(yes(AsgRval),
				AditiType, RvalCode),
			rl_exprn__generate_pop(reg(OutputLoc), Type, PopCode),
			{ Code = tree(RvalCode, PopCode) }
		;
			{ error("rl_exprn__builtin_call: invalid builtin result") }
		)
	;
		{ prog_out__sym_name_to_string(PredModule0, PredModule) },
		{ pred_info_arity(PredInfo, Arity) },
		{ string__format("Sorry, not implemented in Aditi: %s:%s/%i",
			[s(PredModule), s(PredName), i(Arity)], Msg) },
		{ error(Msg) }
	).

:- pred rl_exprn__maybe_llds_rval_to_rl_rval(maybe(rval)::in, 
		aditi_type::in, byte_tree::out,
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__maybe_llds_rval_to_rl_rval(no, _, empty) --> [].
rl_exprn__maybe_llds_rval_to_rl_rval(yes(LLDSRval), _ResultType, Code) -->
	( rl_exprn__llds_rval_to_rl_rval(LLDSRval, RvalCode) ->
		{ Code = RvalCode }
	;
		{ error("rl_exprn__maybe_llds_rval_to_rl_rval: invalid llds rval") }
	).

:- pred rl_exprn__llds_rval_to_rl_rval(rval::in, byte_tree::out,
		rl_exprn_info::in, rl_exprn_info::out) is semidet.

rl_exprn__llds_rval_to_rl_rval(var(Var), Code) -->
	rl_exprn_info_lookup_var(Var, VarLoc),
	rl_exprn_info_lookup_var_type(Var, Type),
	rl_exprn__generate_push(reg(VarLoc), Type, Code).
rl_exprn__llds_rval_to_rl_rval(const(RvalConst), PushCode) -->
	{ 
		RvalConst = true,
		Const = int(1),
		Type = int
	;
		RvalConst = false,
		Const = int(0),
		Type = int
	;
		RvalConst = int_const(Int),
		Const = int(Int),
		Type = int
	;
		RvalConst = float_const(Float),
		Const = float(Float), 
		Type = float
	;
		RvalConst = string_const(String),
		Const = string(String),
		Type = string
	},
	{ rl_exprn__aditi_type_to_type(Type, Type1) },
	rl_exprn__generate_push(const(Const), Type1, PushCode).
rl_exprn__llds_rval_to_rl_rval(binop(BinOp, Rval1, Rval2), Code) -->
	rl_exprn__llds_rval_to_rl_rval(Rval1, Code1),
	rl_exprn__llds_rval_to_rl_rval(Rval2, Code2),
	{ rl_exprn__binop_bytecode(BinOp, Bytecode) },
	{ Code = 
		tree(Code1, 
		tree(Code2, 
		node([Bytecode])
	)) }.

:- pred rl_exprn__binop_bytecode(binary_op::in, bytecode::out) is semidet.

rl_exprn__binop_bytecode((+), rl_EXP_int_add).
rl_exprn__binop_bytecode((-), rl_EXP_int_sub).
rl_exprn__binop_bytecode((*), rl_EXP_int_mult).
rl_exprn__binop_bytecode((/), rl_EXP_int_div).
rl_exprn__binop_bytecode((mod), rl_EXP_int_mod).
rl_exprn__binop_bytecode(eq, rl_EXP_int_eq).
rl_exprn__binop_bytecode(ne, rl_EXP_int_ne).
rl_exprn__binop_bytecode(str_eq, rl_EXP_str_eq).
rl_exprn__binop_bytecode(str_ne, rl_EXP_str_ne).
rl_exprn__binop_bytecode(str_lt, rl_EXP_str_lt).
rl_exprn__binop_bytecode(str_gt, rl_EXP_str_gt).
rl_exprn__binop_bytecode(str_le, rl_EXP_str_le).
rl_exprn__binop_bytecode(str_ge, rl_EXP_str_ge).
rl_exprn__binop_bytecode((<), rl_EXP_int_lt).
rl_exprn__binop_bytecode((>), rl_EXP_int_gt).
rl_exprn__binop_bytecode((>=), rl_EXP_int_ge).
rl_exprn__binop_bytecode((<=), rl_EXP_int_le).
rl_exprn__binop_bytecode(float_plus, rl_EXP_flt_add).
rl_exprn__binop_bytecode(float_minus, rl_EXP_flt_sub).
rl_exprn__binop_bytecode(float_times, rl_EXP_flt_mult).
rl_exprn__binop_bytecode(float_divide, rl_EXP_flt_div).
rl_exprn__binop_bytecode(float_eq, rl_EXP_flt_eq).
rl_exprn__binop_bytecode(float_ne, rl_EXP_flt_ne).
rl_exprn__binop_bytecode(float_lt, rl_EXP_flt_lt).
rl_exprn__binop_bytecode(float_gt, rl_EXP_flt_gt).
rl_exprn__binop_bytecode(float_le, rl_EXP_flt_le).
rl_exprn__binop_bytecode(float_ge, rl_EXP_flt_ge).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

rl_exprn__aggregate(ModuleInfo, ComputeInitial, UpdateAcc, GrpByType, 
		NonGrpByType, AccType, AggCode, Decls) :-

	map__init(VarTypes),
	varset__init(VarSet),
	instmap__init_reachable(InstMap),
	rl_exprn_info_init(ModuleInfo, InstMap, VarTypes, VarSet, Info0),
	rl_exprn__aggregate_2(ComputeInitial, UpdateAcc, GrpByType,
		NonGrpByType, AccType, AggCode, Decls, Info0, _).

:- pred rl_exprn__aggregate_2(pred_proc_id::in, pred_proc_id::in,
	(type)::in, (type)::in, (type)::in, list(bytecode)::out,
	list(type)::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__aggregate_2(ComputeInitial, UpdateAcc, GrpByType,
		NonGrpByType, AccType, AggCode, Decls) -->

	rl_exprn_info_get_free_reg(GrpByType, GrpByReg),
	rl_exprn_info_get_free_reg(AccType, AccReg),

	%
	% Initialise the accumulator and group-by variables.
	%
	rl_exprn__aggregate_init(ComputeInitial, GrpByReg, GrpByType, 
		NonGrpByType, AccReg, AccType, InitCode),

	%
	% Generate a test to check whether the current tuple is
	% in the current group.
	%
	rl_exprn__test(reg(GrpByReg), input_field(one, 0),
		GrpByType, node([rl_EXP_return_false]), TestCode),

	%
	% Generate code to update the accumulator.
	%
	rl_exprn__aggregate_update(UpdateAcc, GrpByReg, GrpByType,
		NonGrpByType, AccReg, AccType, UpdateCode),	
	{ EvalCode0 = tree(TestCode, UpdateCode) },
	{ rl_exprn__resolve_addresses(EvalCode0, EvalCode1) },
	{ EvalCode = tree(node([rl_PROC_expr_frag(2)]), EvalCode1) },

	%
	% Create the output tuple.
	%

	rl_exprn__assign(output_field(0), reg(GrpByReg),
		GrpByType, GrpByOutputCode), 
	rl_exprn__assign(output_field(1), reg(AccReg),
		AccType, AccOutputCode),

	rl_exprn_info_get_decls(Decls),

	{ AggCode0 =
		tree(InitCode,
		tree(EvalCode,
		tree(node([rl_PROC_expr_frag(3)]),
		tree(GrpByOutputCode,
		AccOutputCode
	)))) },
	{ tree__flatten(AggCode0, AggCode1) },
	{ list__condense(AggCode1, AggCode) }.
			
%-----------------------------------------------------------------------------%

	% Generate code to initialise the accumulator for a group and
	% put the group-by variable in a known place.
:- pred rl_exprn__aggregate_init(pred_proc_id::in, reg_id::in, (type)::in,
		(type)::in, reg_id::in, (type)::in, byte_tree::out, 
		rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__aggregate_init(ComputeClosure, GrpByReg, GrpByType, NonGrpByType,
		AccReg, AccType, InitCode) -->

	% Put the group-by value for this group in its place.
	rl_exprn__assign(reg(GrpByReg), input_field(one, 0),
		GrpByType, GrpByAssign),

	rl_exprn_info_get_free_reg(NonGrpByType, NonGrpByReg),
	rl_exprn__assign(reg(NonGrpByReg), input_field(one, 1),
		GrpByType, NonGrpByAssign),

	rl_exprn_info_get_free_reg(AccType, InitialAccReg),

	%
	% Compute the initial accumulator given the first tuple in
	% the group, and assign it to a register.
	% 
	{ Args = [GrpByReg, NonGrpByReg, InitialAccReg] },
	rl_exprn__closure(ComputeClosure, Args, IsConst, AccCode0),

	% Restore the initial value of the accumulator at the start
	% of a new group.
	rl_exprn__assign(reg(AccReg), reg(InitialAccReg), AccType, AccAssign),

	{ IsConst = yes ->
		% If the initial accumulator is constant, it can be
		% computed once in the init fragment, rather than
		% once per group.
		rl_exprn__resolve_addresses(AccCode0, AccCode),
		InitCode =
			tree(node([rl_PROC_expr_frag(0)]),
			tree(AccCode,
			tree(node([rl_PROC_expr_frag(1)]),
			tree(GrpByAssign,
			AccAssign
		))))
	;
		InitCode0 =
			tree(GrpByAssign,
			tree(NonGrpByAssign,
			tree(AccCode0,
			AccAssign
		))),

		% If the initial accumulator is not constant, it must be
		% computed in the group init fragment.
		rl_exprn__resolve_addresses(InitCode0, InitCode1),
		InitCode =
			tree(node([rl_PROC_expr_frag(1)]),
			InitCode1
		)
	}.

%-----------------------------------------------------------------------------%

	% Generate code to compute the new accumulator given the
	% next element in the group, then destructively update the
	% old accumulator.
:- pred rl_exprn__aggregate_update(pred_proc_id::in, reg_id::in,
	(type)::in, (type)::in, reg_id::in, (type)::in,
	byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__aggregate_update(UpdateClosure, GrpByReg, GrpByType, NonGrpByType,
		AccReg, AccType, Code) -->

	rl_exprn_info_get_free_reg(NonGrpByType, NonGrpByReg),
	rl_exprn__assign(reg(NonGrpByReg), input_field(one, 1),
		NonGrpByType, NonGrpByCode),

	% Allocate a location to collect the new accumulator.
	rl_exprn_info_get_free_reg(GrpByType, OutputAccReg),
	rl_exprn__assign(reg(AccReg), reg(OutputAccReg),
		AccType, AccAssignCode),

	{ Args = [GrpByReg, NonGrpByReg, AccReg, OutputAccReg] },

	rl_exprn__closure(UpdateClosure, Args, _, UpdateCode),
	{ Code =
		tree(NonGrpByCode,
		tree(UpdateCode,
		AccAssignCode
	)) }.

%-----------------------------------------------------------------------------%

	% Evaluate a deterministic closure to compute the initial value
	% or update the accumulator for an aggregate.
	% Return whether the input arguments are actually used in
	% constructing the outputs. If not, the closure is constant
	% and can be evaluated once, instead of once per group.
:- pred rl_exprn__closure(pred_proc_id::in, list(reg_id)::in, bool::out,
		byte_tree::out, rl_exprn_info::in, rl_exprn_info::out) is det.

rl_exprn__closure(proc(PredId, ProcId), ArgLocs, IsConst, Code) -->
	rl_exprn_info_get_module_info(ModuleInfo),
	{ module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
		PredInfo, ProcInfo) },
	{ proc_info_vartypes(ProcInfo, VarTypes) },
	{ proc_info_varset(ProcInfo, VarSet) },
	rl_exprn_info_set_vartypes(VarTypes),
	rl_exprn_info_set_varset(VarSet),

	{ proc_info_headvars(ProcInfo, HeadVars) },
	{ map__from_corresponding_lists(HeadVars, ArgLocs, VarLocs) },
	{ list__length(HeadVars, NextVar) },
	rl_exprn_info_set_vars(VarLocs - NextVar),

	% Check if the closure depends on the input arguments.
	{ proc_info_goal(ProcInfo, Goal) },
	{ Goal = _ - GoalInfo },
	{ goal_info_get_nonlocals(GoalInfo, NonLocals) },
	{ proc_info_argmodes(ProcInfo, ArgModes) },
	{ partition_args(ModuleInfo, ArgModes, HeadVars, InputArgs, _) },
	{ set__list_to_set(InputArgs, InputArgSet) },
	{ set__intersect(InputArgSet, NonLocals, UsedInputArgs) },
	( { set__empty(UsedInputArgs) } ->
		{ IsConst = yes }
	;
		{ IsConst = no }
	),

	{ Fail = node([rl_EXP_return_false]) },
	rl_exprn__call_body(PredId, ProcId, PredInfo, ProcInfo,
			Fail, HeadVars, Code).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% Return the bytecode used to get a field from an input term.
:- pred rl_exprn__get_input_field_code(tuple_num::in, aditi_type::in,
		int::in, bytecode::out) is det. 

rl_exprn__get_input_field_code(one, int, Attr, rl_EXP_int_field1(Attr)).
rl_exprn__get_input_field_code(one, string, Attr, rl_EXP_str_field1(Attr)).
rl_exprn__get_input_field_code(one, float, Attr, rl_EXP_flt_field1(Attr)).
rl_exprn__get_input_field_code(one, term(_), Attr, rl_EXP_term_field1(Attr)).
rl_exprn__get_input_field_code(two, int, Attr, rl_EXP_int_field2(Attr)).
rl_exprn__get_input_field_code(two, string, Attr, rl_EXP_str_field2(Attr)).
rl_exprn__get_input_field_code(two, float, Attr, rl_EXP_flt_field2(Attr)).
rl_exprn__get_input_field_code(two, term(_), Attr, rl_EXP_term_field2(Attr)).

	% Return the bytecode used to set a field in the output term.
:- pred rl_exprn__set_output_field_code(tuple_num::in,
		aditi_type::in, int::in, bytecode::out) is det.

rl_exprn__set_output_field_code(one, int, Attr, rl_EXP_output1_int(Attr)).
rl_exprn__set_output_field_code(one, string, Attr, rl_EXP_output1_str(Attr)).
rl_exprn__set_output_field_code(one, float, Attr, rl_EXP_output1_flt(Attr)).
rl_exprn__set_output_field_code(one, term(_), Attr,
				rl_EXP_put_term_output1(Attr)).
rl_exprn__set_output_field_code(two, int, Attr, rl_EXP_output2_int(Attr)).
rl_exprn__set_output_field_code(two, string, Attr, rl_EXP_output2_str(Attr)).
rl_exprn__set_output_field_code(two, float, Attr, rl_EXP_output2_flt(Attr)).
rl_exprn__set_output_field_code(two, term(_), Attr,
				rl_EXP_put_term_output2(Attr)).

	% Return the bytecode used to extract a field from a term.
:- pred rl_exprn__get_term_arg_code(aditi_type::in,
		int::in, bytecode::out) is det.

rl_exprn__get_term_arg_code(int, Index, rl_EXP_get_int_arg(Index)).
rl_exprn__get_term_arg_code(float, Index, rl_EXP_get_flt_arg(Index)).
rl_exprn__get_term_arg_code(string, Index, rl_EXP_get_str_arg(Index)).
rl_exprn__get_term_arg_code(term(_), Index, rl_EXP_get_term_arg(Index)).

	% Return the bytecode used to set a field in a term.
:- pred rl_exprn__set_term_arg_code(aditi_type::in,
		int::in, bytecode::out) is det.

rl_exprn__set_term_arg_code(int, Index, rl_EXP_set_int_arg(Index)).
rl_exprn__set_term_arg_code(float, Index, rl_EXP_set_flt_arg(Index)).
rl_exprn__set_term_arg_code(string, Index, rl_EXP_set_str_arg(Index)).
	% This bytecode copies the argument term adjusting rule numbers
	% if the schemas of the argument term and the term having its
	% argument set do not match.
rl_exprn__set_term_arg_code(term(_), Index, rl_EXP_put_term_arg(Index)).

:- pred rl_exprn__compare_bytecode(aditi_type::in, bytecode::out) is det.

rl_exprn__compare_bytecode(int, rl_EXP_int_cmp).
rl_exprn__compare_bytecode(float, rl_EXP_flt_cmp).
rl_exprn__compare_bytecode(string, rl_EXP_str_cmp).
rl_exprn__compare_bytecode(term(_), rl_EXP_term_cmp).

%-----------------------------------------------------------------------------%

:- type aditi_type
	--->	int
	;	string
	;	float
	;	term(type).

:- pred rl_exprn__type_to_aditi_type((type)::in, aditi_type::out) is det.

rl_exprn__type_to_aditi_type(Type, AditiType) :-
	( type_to_type_id(Type, TypeId, _) ->
		( TypeId = unqualified("int") - 0 ->
			AditiType = int
		; TypeId = unqualified("character") - 0 ->
			AditiType = int
		; TypeId = unqualified("string") - 0 ->
			AditiType = string
		; TypeId = unqualified("float") - 0 ->
			AditiType = float
		;
			AditiType = term(Type)
		)
	;
		% All types in Aditi relations must be bound. This case
		% can happen if an argument of an aggregate init or update
		% closure is not used. int is a bit of a lie, but since
		% the argument is not used, it should be harmless.
		AditiType = int
	).	

:- pred rl_exprn__aditi_type_to_type(aditi_type::in, (type)::out) is det.

rl_exprn__aditi_type_to_type(int, Int) :-
	construct_type(unqualified("int") - 0, [], Int).
rl_exprn__aditi_type_to_type(float, Float) :-
	construct_type(unqualified("float") - 0, [], Float).
rl_exprn__aditi_type_to_type(string, Str) :-
	construct_type(unqualified("string") - 0, [], Str).
rl_exprn__aditi_type_to_type(term(Type), Type).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred rl_exprn__resolve_addresses(byte_tree::in, byte_tree::out) is det.

rl_exprn__resolve_addresses(ByteTree0, ByteTree) :-
	map__init(Labels0),
	rl_exprn__get_exprn_labels(0, _, Labels0, Labels,
		ByteTree0, ByteTree1),
	ResolveAddr =
		lambda([Code0::in, Code::out] is det, (
			% This is incomplete, but we don't generate any
			% of the other jump instructions.
			( Code0 = rl_EXP_jmp(Label0) ->
				map__lookup(Labels, Label0, Label),
				Code = rl_EXP_jmp(Label)
			; Code0 = rl_EXP_beqz(Label0) ->
				map__lookup(Labels, Label0, Label),
				Code = rl_EXP_beqz(Label)
			; Code0 = rl_EXP_bnez(Label0) ->
				map__lookup(Labels, Label0, Label),
				Code = rl_EXP_bnez(Label)
			; Code0 = rl_EXP_bltz(Label0) ->
				map__lookup(Labels, Label0, Label),
				Code = rl_EXP_bltz(Label)
			; Code0 = rl_EXP_blez(Label0) ->
				map__lookup(Labels, Label0, Label),
				Code = rl_EXP_blez(Label)
			; Code0 = rl_EXP_bgez(Label0) ->
				map__lookup(Labels, Label0, Label),
				Code = rl_EXP_bgez(Label)
			; Code0 = rl_EXP_bgtz(Label0) ->
				map__lookup(Labels, Label0, Label),
				Code = rl_EXP_bgtz(Label)
			; Code0 = rl_EXP_bt(Label0) ->
				map__lookup(Labels, Label0, Label),
				Code = rl_EXP_bt(Label)
			; Code0 = rl_EXP_bf(Label0) ->
				map__lookup(Labels, Label0, Label),
				Code = rl_EXP_bf(Label)
			;
				Code = Code0
			)
		)),
	rl_out__resolve_addresses(ResolveAddr, ByteTree1, ByteTree).

:- pred rl_exprn__get_exprn_labels(int::in, int::out, map(label_id, int)::in,
		map(label_id, int)::out, byte_tree::in, byte_tree::out) is det.

rl_exprn__get_exprn_labels(PC0, PC0, Labels, Labels, empty, empty).
rl_exprn__get_exprn_labels(PC0, PC, Labels0, Labels,
		tree(CodeA0, CodeB0), tree(CodeA, CodeB)) :-
	rl_exprn__get_exprn_labels(PC0, PC1, Labels0, Labels1, CodeA0, CodeA),
	rl_exprn__get_exprn_labels(PC1, PC, Labels1, Labels, CodeB0, CodeB).
rl_exprn__get_exprn_labels(PC0, PC, Labels0, Labels,
		node(Instrs0), node(Instrs)) :-
	rl_exprn__get_exprn_labels_list(PC0, PC,
		Labels0, Labels, Instrs0, Instrs).

:- pred rl_exprn__get_exprn_labels_list(int::in, int::out,
		map(label_id, int)::in, map(label_id, int)::out,
		list(bytecode)::in, list(bytecode)::out) is det.

rl_exprn__get_exprn_labels_list(PC, PC, Labels, Labels, [], []).
rl_exprn__get_exprn_labels_list(PC0, PC, Labels0, Labels,
		[Instr | Instrs0], Instrs) :-
	( Instr = rl_PROC_label(_) ->
		PC1 = PC0
	;
		functor(Instr, _, Arity),
		PC1 is PC0 + Arity + 1		% +1 for the opcode
	),
	rl_exprn__get_exprn_labels_list(PC1, PC, Labels0, Labels1,
		Instrs0, Instrs1),
	( Instr = rl_PROC_label(Label) ->
		% Register the label and remove the instruction.
		map__det_insert(Labels1, Label, PC0, Labels),
		Instrs = Instrs1
	;
		Labels = Labels1,
		Instrs = [Instr | Instrs1]
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- type rl_lval
	--->	reg(reg_id)

		% A field in the output tuple
	;	output_field(
			int 	% field no
		)

		% A field of a term.
	;	term_arg(
			reg_id,
			cons_id,
			int,
			type		% type of the term
		).

:- type rl_rval
	--->	reg(reg_id)

	;	const(rl_const)
	
		% A field in one of the input tuples
	;	input_field(
			tuple_num,
			int		% field no
		)
		
		% An argument of a term in a register
	;	term_arg(
			rl_rval,	% register holding the term
			cons_id,
			int,		% arg no
			type		% type of the term
		).

:- type input_tuple
	--->	one
	;	two.

:- type reg_id == int.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- type rl_exprn_info.

:- pred rl_exprn_info_init(module_info, instmap, map(prog_var, type),
		prog_varset, rl_exprn_info).
:- mode rl_exprn_info_init(in, in, in, in, out) is det.

:- pred rl_exprn_info_init(module_info, rl_exprn_info).
:- mode rl_exprn_info_init(in, out) is det.

:- pred rl_exprn_info_get_module_info(module_info,
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_get_module_info(out, in, out) is det.

:- pred rl_exprn_info_get_instmap(instmap, rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_get_instmap(out, in, out) is det.

:- pred rl_exprn_info_set_instmap(instmap, rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_set_instmap(in, in, out) is det.

:- pred rl_exprn_info_get_vartypes(map(prog_var, type),
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_get_vartypes(out, in, out) is det.

:- pred rl_exprn_info_set_vartypes(map(prog_var, type),
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_set_vartypes(in, in, out) is det.

:- pred rl_exprn_info_get_varset(prog_varset, rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_get_varset(out, in, out) is det.

:- pred rl_exprn_info_set_varset(prog_varset, rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_set_varset(in, in, out) is det.

:- pred rl_exprn_info_set_vars(id_map(prog_var), rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_set_vars(in, in, out) is det.

:- pred rl_exprn_info_lookup_var(prog_var, int, rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_lookup_var(in, out, in, out) is det.

:- pred rl_exprn_info_get_free_reg((type), reg_id,
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_get_free_reg(in, out, in, out) is det.

:- pred rl_exprn_info_get_next_label_id(label_id,
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_get_next_label_id(out, in, out) is det.

:- pred rl_exprn_info_lookup_const(rl_const, int,
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_lookup_const(in, out, in, out) is det.

:- pred rl_exprn_info_get_consts(id_map(rl_const), 
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_get_consts(out, in, out) is det.

:- pred rl_exprn_info_lookup_rule(pair(rl_rule, exprn_tuple), int,
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_lookup_rule(in, out, in, out) is det.

:- pred rl_exprn_info_get_rules(id_map(pair(rl_rule, exprn_tuple)), 
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_get_rules(out, in, out) is det.

:- pred rl_exprn_info_get_parent_pred_proc_ids(set(pred_proc_id),
		rl_exprn_info, rl_exprn_info) is det.
:- mode rl_exprn_info_get_parent_pred_proc_ids(out, in, out) is det.

:- pred rl_exprn_info_set_parent_pred_proc_ids(set(pred_proc_id),
		rl_exprn_info, rl_exprn_info) is det.
:- mode rl_exprn_info_set_parent_pred_proc_ids(in, in, out) is det.

:- pred rl_exprn_info_lookup_var_type(prog_var, type,
		rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_lookup_var_type(in, out, in, out) is det.

:- pred rl_exprn_info_get_decls(list(type), rl_exprn_info, rl_exprn_info).
:- mode rl_exprn_info_get_decls(out, in, out) is det.

:- type rl_exprn_info
	---> rl_exprn_info(
		module_info,
		instmap,		% not yet used.
		map(prog_var, type),
		prog_varset,
		id_map(prog_var),
		label_id,		% next label.
		id_map(rl_const),
		id_map(pair(rl_rule, exprn_tuple)),
		set(pred_proc_id),	% parent pred_proc_ids, used
					% to abort on recursion.
		list(type)		% variable declarations in reverse.
	).

:- type rl_rule
	---> rl_rule(
		string,		% mangled type name Module__Name
		string,		% mangled functor name Module__Name
		int		% arity
	).

	% Each expression has a number of tuples associated with it,
	% each of which has its own rule table.
:- type exprn_tuple
	---> 	input1
	;	input2
	;	variables
	;	output1
	;	output2
	.

:- type id_map(T) == pair(map(T, int), int).

:- pred id_map_init(id_map(T)::out) is det.

id_map_init(Empty - 0) :-
	map__init(Empty).

:- pred id_map_lookup(T::in, int::out, bool::out,
		id_map(T)::in, id_map(T)::out) is det.

id_map_lookup(Id, IdIndex, Added, Map0 - Index0, Map - Index) :-
	( map__search(Map0, Id, IdIndex0) ->
		IdIndex = IdIndex0,
		Map = Map0,
		Index = Index0,
		Added = no
	;
		IdIndex = Index0,
		Index is Index0 + 1,
		Added = yes,
		map__det_insert(Map0, Id, Index0, Map)
	).

:- pred id_map_lookup(T::in, int::out, id_map(T)::in, id_map(T)::out) is det.

id_map_lookup(Id, IdIndex, Map0, Map) :-
	id_map_lookup(Id, IdIndex, _, Map0, Map).

rl_exprn_info_init(ModuleInfo, Info0) :-
	map__init(VarTypes),
	varset__init(VarSet),
	instmap__init_reachable(InstMap),
	rl_exprn_info_init(ModuleInfo, InstMap, VarTypes, VarSet, Info0).

rl_exprn_info_init(ModuleInfo, InstMap, VarTypes, VarSet, Info) :-
	id_map_init(VarMap),
	id_map_init(ConstMap),
	id_map_init(RuleMap),
	set__init(Parents),
	Label = 0,
	Info = rl_exprn_info(ModuleInfo, InstMap, VarTypes, VarSet,
		VarMap, Label, ConstMap, RuleMap, Parents, []).

rl_exprn_info_get_module_info(A, Info, Info) :-
	Info = rl_exprn_info(A,_,_,_,_,_,_,_,_,_).
rl_exprn_info_get_instmap(B, Info, Info) :-
	Info = rl_exprn_info(_,B,_,_,_,_,_,_,_,_).
rl_exprn_info_get_vartypes(C, Info, Info) :-
	Info = rl_exprn_info(_,_,C,_,_,_,_,_,_,_).
rl_exprn_info_get_varset(D, Info, Info) :-
	Info = rl_exprn_info(_,_,_,D,_,_,_,_,_,_).
rl_exprn_info_get_consts(G, Info, Info) :-
	Info = rl_exprn_info(_,_,_,_,_,_,G,_,_,_).
rl_exprn_info_get_rules(H, Info, Info) :-
	Info = rl_exprn_info(_,_,_,_,_,_,_,H,_,_).
rl_exprn_info_get_parent_pred_proc_ids(I, Info, Info) :-
	Info = rl_exprn_info(_,_,_,_,_,_,_,_,I,_).
rl_exprn_info_get_decls(J, Info, Info) :-
	Info = rl_exprn_info(_,_,_,_,_,_,_,_,_,J0),
	list__reverse(J0, J).

rl_exprn_info_set_instmap(B, Info0, Info) :-
	Info0 = rl_exprn_info(A,_,C,D,E,F,G,H,I,J),
	Info = rl_exprn_info(A,B,C,D,E,F,G,H,I,J).
rl_exprn_info_set_vartypes(C, Info0, Info) :-
	Info0 = rl_exprn_info(A,B,_,D,E,F,G,H,I,J),
	Info = rl_exprn_info(A,B,C,D,E,F,G,H,I,J).
rl_exprn_info_set_varset(D, Info0, Info) :-
	Info0 = rl_exprn_info(A,B,C,_,E,F,G,H,I,J),
	Info = rl_exprn_info(A,B,C,D,E,F,G,H,I,J).
rl_exprn_info_set_vars(E, Info0, Info) :-
	Info0 = rl_exprn_info(A,B,C,D,_,F,G,H,I,J),
	Info = rl_exprn_info(A,B,C,D,E,F,G,H,I,J).
rl_exprn_info_set_parent_pred_proc_ids(I, Info0, Info) :-
	Info0 = rl_exprn_info(A,B,C,D,E,F,G,H,_,J),
	Info = rl_exprn_info(A,B,C,D,E,F,G,H,I,J).
rl_exprn_info_get_free_reg(Type, Loc, Info0, Info) :-
	Info0 = rl_exprn_info(A,B,C,D,VarMap0,F,G,H,I,RegTypes0),
	VarMap0 = Map - Loc,
	Loc1 is Loc + 1,
	VarMap = Map - Loc1,
	RegTypes = [Type | RegTypes0],
	Info = rl_exprn_info(A,B,C,D,VarMap,F,G,H,I,RegTypes).
rl_exprn_info_lookup_var(Var, Loc, Info0, Info) :-
	Info0 = rl_exprn_info(A,B,VarTypes,D,VarMap0,F,G,H,I,RegTypes0),
	id_map_lookup(Var, Loc, Added, VarMap0, VarMap),
	( Added = yes ->
		map__lookup(VarTypes, Var, Type),
		RegTypes = [Type | RegTypes0]
	;
		RegTypes = RegTypes0
	),
	Info = rl_exprn_info(A,B,VarTypes,D,VarMap,F,G,H,I,RegTypes).
rl_exprn_info_get_next_label_id(Label0, Info0, Info) :-
	Info0 = rl_exprn_info(A,B,C,D,E,Label0,G,H,I,J),
	Label is Label0 + 1,
	Info = rl_exprn_info(A,B,C,D,E,Label,G,H,I,J).
rl_exprn_info_lookup_const(Const, Loc, Info0, Info) :-
	Info0 = rl_exprn_info(A,B,C,D,E,F,Consts0,H,I,J),
	id_map_lookup(Const, Loc, Consts0, Consts), 
	Info = rl_exprn_info(A,B,C,D,E,F,Consts,H,I,J).
rl_exprn_info_lookup_rule(Rule, Loc, Info0, Info) :-
	Info0 = rl_exprn_info(A,B,C,D,E,F,G,Rules0,I,J),
	id_map_lookup(Rule, Loc, Rules0, Rules),
	Info = rl_exprn_info(A,B,C,D,E,F,G,Rules,I,J).

rl_exprn_info_lookup_var_type(Var, Type) -->
	rl_exprn_info_get_vartypes(VarTypes),
	{ map__lookup(VarTypes, Var, Type) }.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
