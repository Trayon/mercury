%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% File: ml_call_gen.m
% Main author: fjh

% This module is part of the MLDS code generator.
% It handles code generation of procedures calls,
% calls to builtins, and other closely related stuff.

%-----------------------------------------------------------------------------%

:- module ml_call_gen.
:- interface.

:- import_module prog_data.
:- import_module hlds_pred, hlds_goal.
:- import_module mlds, ml_code_util.
:- import_module llds. % XXX for `code_model'

:- import_module list.

	% Generate MLDS code for an HLDS generic_call goal.
	% This includes boxing/unboxing the arguments if necessary.
:- pred ml_gen_generic_call(generic_call, list(prog_var), list(mode),
		code_model, prog_context, mlds__defns, mlds__statements,
		ml_gen_info, ml_gen_info).
:- mode ml_gen_generic_call(in, in, in, in, in, out, out, in, out) is det.

	%
	% Generate MLDS code for an HLDS procedure call, making sure to
	% box/unbox the arguments if necessary.
	%
:- pred ml_gen_call(pred_id, proc_id, list(var_name), list(mlds__lval),
		list(prog_data__type), code_model, prog_context,
		mlds__defns, mlds__statements, ml_gen_info, ml_gen_info).
:- mode ml_gen_call(in, in, in, in, in, in, in, out, out, in, out) is det.

	%
	% Generate MLDS code for a call to a builtin procedure.
	%
:- pred ml_gen_builtin(pred_id, proc_id, list(prog_var), code_model,
		prog_context, mlds__defns, mlds__statements,
		ml_gen_info, ml_gen_info).
:- mode ml_gen_builtin(in, in, in, in, in, out, out, in, out) is det.

	%
	% Generate an rval containing the address of the specified procedure.
	%
:- pred ml_gen_proc_addr_rval(pred_id, proc_id, mlds__rval,
		ml_gen_info, ml_gen_info).
:- mode ml_gen_proc_addr_rval(in, in, out, in, out) is det.

	% Given a source type and a destination type,
	% and given an source rval holding a value of the source type,
	% produce an rval that converts the source rval to the destination type.
	%
:- pred ml_gen_box_or_unbox_rval(prog_type, prog_type, mlds__rval, mlds__rval,
		ml_gen_info, ml_gen_info).
:- mode ml_gen_box_or_unbox_rval(in, in, in, out, in, out) is det.

	% ml_gen_box_or_unbox_lval(CallerType, CalleeType, VarLval, VarName,
	%	Context,
	%	ArgLval, ConvDecls, ConvInputStatements, ConvOutputStatements):
	%
	% This is like `ml_gen_box_or_unbox_rval', except that it
	% works on lvals rather than rvals.
	% Given a source type and a destination type,
	% a source lval holding a value of the source type,
	% and a name to base the name of the local temporary variable on,
	% this procedure produces an lval of the destination type,
	% the declaration for the local temporary used (if any),
	% code to assign from the source lval (suitable converted)
	% to the destination lval, and code to assign from the
	% destination lval (suitable converted) to the source lval.
	%
:- pred ml_gen_box_or_unbox_lval(prog_type, prog_type, mlds__lval, var_name,
		prog_context, mlds__lval, mlds__defns, mlds__statements,
		mlds__statements, ml_gen_info, ml_gen_info).
:- mode ml_gen_box_or_unbox_lval(in, in, in, in, in, out, out, out, out,
		in, out) is det.

        % Generate the appropriate MLDS type for a continuation function
        % for a nondet procedure whose output arguments have the
        % specified types.
        % 
        %
:- pred ml_gen_cont_params(list(mlds__type), mlds__func_params,
		ml_gen_info, ml_gen_info).
:- mode ml_gen_cont_params(in, out, in, out) is det.


%-----------------------------------------------------------------------------%

:- implementation.

:- import_module hlds_module.
:- import_module builtin_ops.
:- import_module type_util, mode_util, error_util.
:- import_module options, globals.

:- import_module bool, int, string, std_util, term, varset, require, map.

%-----------------------------------------------------------------------------%
%
% Code for procedure calls
%

	%
	% Generate MLDS code for an HLDS generic_call goal.
	% This includes boxing/unboxing the arguments if necessary.
	%
	% XXX For typeclass method calls, we do some unnecessary
	% boxing/unboxing of the arguments.
	%
ml_gen_generic_call(GenericCall, ArgVars, ArgModes, CodeModel, Context,
		MLDS_Decls, MLDS_Statements) -->
	%
	% allocate some fresh type variables to use as the Mercury types
	% of the boxed arguments
	%
	{ NumArgs = list__length(ArgVars) },
	{ varset__init(TypeVarSet0) },
	{ varset__new_vars(TypeVarSet0, NumArgs, ArgTypeVars,
		_TypeVarSet) },
	{ term__var_list_to_term_list(ArgTypeVars, BoxedArgTypes) },

	%
	% create the boxed parameter types for the called function
	%
	=(MLDSGenInfo),
	{ ml_gen_info_get_module_info(MLDSGenInfo, ModuleInfo) },
	{ ml_gen_info_get_varset(MLDSGenInfo, VarSet) },
	{ ArgNames = ml_gen_var_names(VarSet, ArgVars) },
	{ PredOrFunc = generic_call_pred_or_func(GenericCall) },
	{ Params0 = ml_gen_params(ModuleInfo, ArgNames,
		BoxedArgTypes, ArgModes, PredOrFunc, CodeModel) },

	%
	% insert the `closure_arg' parameter
	%
	{ ClosureArgType = mlds__generic_type },
	{ ClosureArg = data(var("closure_arg")) - ClosureArgType },
	{ Params0 = mlds__func_params(ArgParams0, RetParam) },
	{ Params = mlds__func_params([ClosureArg | ArgParams0], RetParam) },
	{ Signature = mlds__get_func_signature(Params) },

	%
	% compute the function address
	%
	(
		{ GenericCall = higher_order(ClosureVar, _PredOrFunc,
			_Arity) },
		ml_gen_var(ClosureVar, ClosureLval),
		{ FieldId = offset(const(int_const(1))) },
			% XXX are these types right?
		{ FuncLval = field(yes(0), lval(ClosureLval), FieldId,
			mlds__generic_type, ClosureArgType) },
		{ FuncType = mlds__func_type(Params) },
		{ FuncRval = unop(unbox(FuncType), lval(FuncLval)) }
	;
		{ GenericCall = class_method(TypeClassInfoVar, MethodNum,
			_ClassId, _PredName) },
		%
		% create the lval for the typeclass_info,
		% which is also the closure in this case
		%
		ml_gen_var(TypeClassInfoVar, TypeClassInfoLval),
		{ ClosureLval = TypeClassInfoLval },
		%
		% extract the base_typeclass_info from the typeclass_info
		%
		{ BaseTypeclassInfoFieldId =
			offset(const(int_const(0))) },
		{ BaseTypeclassInfoLval = field(yes(0),
			lval(TypeClassInfoLval), BaseTypeclassInfoFieldId,
			mlds__generic_type, ClosureArgType) },
		%
		% extract the method address from the base_typeclass_info
		%
		{ Offset = ml_base_typeclass_info_method_offset },
		{ MethodFieldNum = MethodNum + Offset },
		{ MethodFieldId = offset(const(int_const(MethodFieldNum))) },
		{ FuncLval = field(yes(0), lval(BaseTypeclassInfoLval),
			MethodFieldId,
			mlds__generic_type, mlds__generic_type) },
		{ FuncType = mlds__func_type(Params) },
		{ FuncRval = unop(unbox(FuncType), lval(FuncLval)) }
	;
		{ GenericCall = aditi_builtin(_, _) },
		{ sorry(this_file, "Aditi builtins") }
	),

	%
	% Generate code to box/unbox the arguments
	% and compute the list of properly converted rvals/lvals
	% to pass as the function call's arguments and return values
	%
	ml_gen_var_list(ArgVars, ArgLvals),
	ml_variable_types(ArgVars, ActualArgTypes),
	ml_gen_arg_list(ArgNames, ArgLvals, ActualArgTypes, BoxedArgTypes,
		ArgModes, PredOrFunc, CodeModel, Context,
		InputRvals, OutputLvals, OutputTypes,
		ConvArgDecls, ConvOutputStatements),
	{ ClosureRval = unop(unbox(ClosureArgType), lval(ClosureLval)) },

	%
	% Prepare to generate the call, passing the closure as the first
	% argument.
	% (We can't actually generate the call yet, since it might be nondet,
	% and we don't yet know what its success continuation will be;
	% instead for now we just construct a higher-order term `DoGenCall',
	% which when called will generate it.)
	%
	{ ObjectRval = no },
	{ DoGenCall = ml_gen_mlds_call(Signature, ObjectRval, FuncRval,
		[ClosureRval | InputRvals], OutputLvals, OutputTypes,
		CodeModel, Context) },

	( { ConvArgDecls = [], ConvOutputStatements = [] } ->
		DoGenCall(MLDS_Decls, MLDS_Statements)
	;
		%
		% Construct a closure to generate code to 
		% convert the output arguments and then succeed
		%
		{ DoGenConvOutputAndSucceed = (
			pred(COAS_Decls::out, COAS_Statements::out, in, out)
			is det -->
				{ COAS_Decls = [] },
				ml_gen_success(CodeModel, Context,
					SucceedStmts),
				{ COAS_Statements = list__append(
					ConvOutputStatements, SucceedStmts) }
		) },

		%
		% Conjoin the code generated by the two closures that we
		% computed above.  `ml_combine_conj' will generate whatever
		% kind of sequence is necessary for this code model.
		%
		ml_combine_conj(CodeModel, Context,
			DoGenCall, DoGenConvOutputAndSucceed,
			CallAndConvOutputDecls, CallAndConvOutputStatements),
		{ MLDS_Decls = list__append(ConvArgDecls,
			CallAndConvOutputDecls) },
		{ MLDS_Statements = CallAndConvOutputStatements }
	).

	%
	% Generate code for the various parts that are needed for
	% a procedure call: declarations of variables needed for
	% boxing/unboxing output arguments,
	% a closure to generate code to call the function
	% with the input arguments appropriate boxed,
	% and code to unbox/box the return values.
	%
	% For example, if the callee is declared as
	%
	%	:- some [T2]
	%	   pred callee(float::in, T1::in, float::out, T2::out, ...).
	%
	% then for a call `callee(Arg1, Arg2, Arg3, Arg4, ...)'
	% with arguments of types `U1, float, U2, float, ...',
	% we generate the following fragments:
	%
	% 	/* declarations of variables needed for boxing/unboxing */
	%	Float conv_Arg3;
	%	MR_Box conv_Arg4;
	%	...
	%
	% 	/* code to call the function */
	%	func(unbox(Arg1), box(Arg2), &boxed_Arg3, &unboxed_Arg4);
	%
	%	/* code to box/unbox the output arguments */
	%	*Arg3 = unbox(boxed_Arg3);
	%	*Arg4 = box(unboxed_Arg4);
	%	...
	%
	% Note that of course in general not every argument will need
	% to be boxed/unboxed; for those where no conversion is required,
	% we just pass the original argument unchanged.
	%
ml_gen_call(PredId, ProcId, ArgNames, ArgLvals, ActualArgTypes, CodeModel,
		Context, MLDS_Decls, MLDS_Statements) -->
	%
	% Compute the function signature
	%
	{ Params = ml_gen_proc_params(ModuleInfo, PredId, ProcId) },
	{ Signature = mlds__get_func_signature(Params) },

	%
	% Compute the function address
	%
	ml_gen_proc_addr_rval(PredId, ProcId, FuncRval),

	%
	% Compute the callee's Mercury argument types and modes
	%
	=(MLDSGenInfo),
	{ ml_gen_info_get_module_info(MLDSGenInfo, ModuleInfo) },
	{ module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
		PredInfo, ProcInfo) },
	{ pred_info_get_is_pred_or_func(PredInfo, PredOrFunc) },
	{ pred_info_arg_types(PredInfo, PredArgTypes) },
	{ proc_info_argmodes(ProcInfo, ArgModes) },

	%
	% Generate code to box/unbox the arguments
	% and compute the list of properly converted rvals/lvals
	% to pass as the function call's arguments and return values
	%
	ml_gen_arg_list(ArgNames, ArgLvals, ActualArgTypes, PredArgTypes,
		ArgModes, PredOrFunc, CodeModel, Context,
		InputRvals, OutputLvals, OutputTypes,
		ConvArgDecls, ConvOutputStatements),

	%
	% Construct a closure to generate the call
	% (We can't actually generate the call yet, since it might be nondet,
	% and we don't yet know what its success continuation will be;
	% that's why for now we just construct a closure `DoGenCall'
	% to generate it.)
	%
	{ ObjectRval = no },
	{ DoGenCall = ml_gen_mlds_call(Signature, ObjectRval, FuncRval,
		InputRvals, OutputLvals, OutputTypes, CodeModel, Context) },

	( { ConvArgDecls = [], ConvOutputStatements = [] } ->
		DoGenCall(MLDS_Decls, MLDS_Statements)
	;
		%
		% Construct a closure to generate code to 
		% convert the output arguments and then succeed
		%
		{ DoGenConvOutputAndSucceed = (
			pred(COAS_Decls::out, COAS_Statements::out, in, out)
			is det -->
				{ COAS_Decls = [] },
				ml_gen_success(CodeModel, Context,
					SucceedStmts),
				{ COAS_Statements = list__append(
					ConvOutputStatements, SucceedStmts) }
		) },

		%
		% Conjoin the code generated by the two closures that we
		% computed above.  `ml_combine_conj' will generate whatever
		% kind of sequence is necessary for this code model.
		%
		ml_combine_conj(CodeModel, Context,
			DoGenCall, DoGenConvOutputAndSucceed,
			CallAndConvOutputDecls, CallAndConvOutputStatements),
		{ MLDS_Decls = list__append(ConvArgDecls,
			CallAndConvOutputDecls) },
		{ MLDS_Statements = CallAndConvOutputStatements }
	).

	%
	% This generates a call in the specified code model.
	% This is a lower-level routine called by both ml_gen_call
	% and ml_gen_generic_call.
	%
:- pred ml_gen_mlds_call(mlds__func_signature, maybe(mlds__rval), mlds__rval,
		list(mlds__rval), list(mlds__lval), list(mlds__type),
		code_model, prog_context, mlds__defns, mlds__statements,
		ml_gen_info, ml_gen_info).
:- mode ml_gen_mlds_call(in, in, in, in, in, in, in, in, out, out, in, out)
		is det.

ml_gen_mlds_call(Signature, ObjectRval, FuncRval, ArgRvals0, RetLvals0,
		RetTypes0, CodeModel, Context, MLDS_Decls, MLDS_Statements) -->
	%
	% append the extra arguments or return val for this code_model
	%
	(
		{ CodeModel = model_non },
		% create a new success continuation, if necessary
		ml_gen_success_cont(RetTypes0, RetLvals0, Context,
			Cont, ContDecls),
		% append the success continuation to the ordinary arguments
		{ Cont = success_cont(FuncPtrRval, EnvPtrRval, _, _) },
		ml_gen_info_use_gcc_nested_functions(UseNestedFuncs),
		( { UseNestedFuncs = yes } ->
			{ ArgRvals = list__append(ArgRvals0, [FuncPtrRval]) }
		;
			{ ArgRvals = list__append(ArgRvals0,
				[FuncPtrRval, EnvPtrRval]) }
		),
		% for --nondet-copy-out, the output arguments will be
		% passed to the continuation rather than being returned
		ml_gen_info_get_globals(Globals),
		{ globals__lookup_bool_option(Globals, nondet_copy_out,
			NondetCopyOut) },
		( { NondetCopyOut = yes } ->
			{ RetLvals = [] }
		;
			{ RetLvals = RetLvals0 }
		),
		{ MLDS_Decls = ContDecls }
	;
		{ CodeModel = model_semi },
		% return a bool indicating whether or not it succeeded
		ml_success_lval(Success),
		{ ArgRvals = ArgRvals0 },
		{ RetLvals = list__append([Success], RetLvals0) },
		{ MLDS_Decls = [] }
	;
		{ CodeModel = model_det },
		{ ArgRvals = ArgRvals0 },
		{ RetLvals = RetLvals0 },
		{ MLDS_Decls = [] }
	),

	%
	% build the MLDS call statement
	%
	{ CallOrTailcall = call },
	{ MLDS_Stmt = call(Signature, FuncRval, ObjectRval, ArgRvals, RetLvals,
			CallOrTailcall) },
	{ MLDS_Statement = mlds__statement(MLDS_Stmt,
			mlds__make_context(Context)) },
	{ MLDS_Statements = [MLDS_Statement] }.

:- pred ml_gen_success_cont(list(mlds__type), list(mlds__lval), prog_context,
		success_cont, mlds__defns, ml_gen_info, ml_gen_info).
:- mode ml_gen_success_cont(in, in, in, out, out, in, out) is det.

ml_gen_success_cont(OutputArgTypes, OutputArgLvals, Context,
		Cont, ContDecls) -->
	ml_gen_info_current_success_cont(CurrentCont),
	{ CurrentCont = success_cont(_FuncPtrRval, _EnvPtrRval,
		CurrentContArgTypes, CurrentContArgLvals) },
	(
		%
		% As an optimization, check if the parameters expected by
		% the current continuation are the same as the ones
		% expected by the new continuation that we're generating;
		% if so, we can just use the current continuation rather
		% than creating a new one.
		%
		{ CurrentContArgTypes = OutputArgTypes },
		{ CurrentContArgLvals = OutputArgLvals }
	->
		{ Cont = CurrentCont },
		{ ContDecls = [] }
	;
		% 
		% Create a new continuation function
		% that just copies the outputs to locals
		% and then calls the original current continuation
		%
		ml_gen_cont_params(OutputArgTypes, Params),
		ml_gen_new_func_label(yes(Params),
			ContFuncLabel, ContFuncLabelRval),
		/* push nesting level */
		ml_gen_copy_args_to_locals(OutputArgLvals, Context,
			CopyDecls, CopyStatements),
		ml_gen_call_current_success_cont(Context, CallCont),
		{ CopyStatement = ml_gen_block(CopyDecls,
			list__append(CopyStatements, [CallCont]), Context) },
		/* pop nesting level */
		ml_gen_label_func(ContFuncLabel, Params, Context,
			CopyStatement, ContFuncDefn),
		{ ContDecls = [ContFuncDefn] },

		ml_get_env_ptr(EnvPtrRval),
		{ NewSuccessCont = success_cont(ContFuncLabelRval,
			EnvPtrRval, OutputArgTypes, OutputArgLvals) },
		ml_gen_info_push_success_cont(NewSuccessCont),
		{ Cont = NewSuccessCont }
	).

ml_gen_cont_params(OutputArgTypes, Params) -->
	ml_gen_cont_params_2(OutputArgTypes, 1, Args0),
	ml_gen_info_use_gcc_nested_functions(UseNestedFuncs),
	( { UseNestedFuncs = yes } ->
		{ Args = Args0 }
	;
		ml_declare_env_ptr_arg(EnvPtrArg),
		{ Args = list__append(Args0, [EnvPtrArg]) }
	),
	{ Params = mlds__func_params(Args, []) }.

:- pred ml_gen_cont_params_2(list(mlds__type), int, mlds__arguments,
		ml_gen_info, ml_gen_info).
:- mode ml_gen_cont_params_2(in, in, out, in, out) is det.

ml_gen_cont_params_2([], _, []) --> [].
ml_gen_cont_params_2([Type | Types], ArgNum, [Argument | Arguments]) -->
	{ ArgName = ml_gen_arg_name(ArgNum) },
	{ Argument = data(var(ArgName)) - Type },
	ml_gen_cont_params_2(Types, ArgNum + 1, Arguments).

:- pred ml_gen_copy_args_to_locals(list(mlds__lval), prog_context,
		mlds__defns, mlds__statements, ml_gen_info, ml_gen_info).
:- mode ml_gen_copy_args_to_locals(in, in, out, out, in, out) is det.

ml_gen_copy_args_to_locals(ArgLvals, Context, CopyDecls, CopyStatements) -->
	{ CopyDecls = [] },
	ml_gen_copy_args_to_locals_2(ArgLvals, 1, Context, CopyStatements).

:- pred ml_gen_copy_args_to_locals_2(list(mlds__lval), int, prog_context,
		mlds__statements, ml_gen_info, ml_gen_info).
:- mode ml_gen_copy_args_to_locals_2(in, in, in, out, in, out) is det.

ml_gen_copy_args_to_locals_2([], _, _, []) --> [].
ml_gen_copy_args_to_locals_2([LocalLval | LocalLvals], ArgNum, Context,
		[Statement | Statements]) -->
	{ ArgName = ml_gen_arg_name(ArgNum) },
	ml_qualify_var(ArgName, ArgLval),
	{ Statement = ml_gen_assign(LocalLval, lval(ArgLval), Context) },
	ml_gen_copy_args_to_locals_2(LocalLvals, ArgNum + 1, Context,
		Statements).

:- func ml_gen_arg_name(int) = string.
ml_gen_arg_name(ArgNum) = ArgName :-
	string__format("arg%d", [i(ArgNum)], ArgName).

%
% Generate an rval containing the address of the specified procedure
%
ml_gen_proc_addr_rval(PredId, ProcId, CodeAddrRval) -->
	=(MLDSGenInfo),
	{ ml_gen_info_get_module_info(MLDSGenInfo, ModuleInfo) },
	{ ml_gen_pred_label(ModuleInfo, PredId, ProcId,
		PredLabel, PredModule) },
	{ Params = ml_gen_proc_params(ModuleInfo, PredId, ProcId) },
	{ Signature = mlds__get_func_signature(Params) },
	{ QualifiedProcLabel = qual(PredModule, PredLabel - ProcId) },
	{ CodeAddrRval = const(code_addr_const(proc(QualifiedProcLabel,
		Signature))) }.

%
% Generate rvals and lvals for the arguments of a procedure call
%
:- pred ml_gen_arg_list(list(var_name), list(mlds__lval), list(prog_type),
		list(prog_type), list(mode), pred_or_func, code_model,
		prog_context, list(mlds__rval), list(mlds__lval),
		list(mlds__type), mlds__defns, mlds__statements,
		ml_gen_info, ml_gen_info).
:- mode ml_gen_arg_list(in, in, in, in, in, in, in, in, out, out, out, out, out,
		in, out) is det.

ml_gen_arg_list(VarNames, VarLvals, CallerTypes, CalleeTypes, Modes,
		PredOrFunc, CodeModel, Context,
		InputRvals, OutputLvals, OutputTypes,
		ConvDecls, ConvOutputStatements) -->
	(
		{ VarNames = [] },
		{ VarLvals = [] },
		{ CallerTypes = [] },
		{ CalleeTypes = [] },
		{ Modes = [] }
	->
		{ InputRvals = [] },
		{ OutputLvals = [] },
		{ OutputTypes = [] },
		{ ConvDecls = [] },
		{ ConvOutputStatements = [] }
	;
		{ VarNames = [VarName | VarNames1] },
		{ VarLvals = [VarLval | VarLvals1] },
		{ CallerTypes = [CallerType | CallerTypes1] },
		{ CalleeTypes = [CalleeType | CalleeTypes1] },
		{ Modes = [Mode | Modes1] }
	->
		ml_gen_arg_list(VarNames1, VarLvals1,
			CallerTypes1, CalleeTypes1, Modes1,
			PredOrFunc, CodeModel, Context,
			InputRvals1, OutputLvals1, OutputTypes1,
			ConvDecls1, ConvOutputStatements1),
		=(MLDSGenInfo),
		{ ml_gen_info_get_module_info(MLDSGenInfo, ModuleInfo) },
		{ mode_to_arg_mode(ModuleInfo, Mode, CalleeType, ArgMode) },
		(
			{ type_util__is_dummy_argument_type(CalleeType) }
		->
			%
			% exclude arguments of type io__state etc.
			%
			{ InputRvals = InputRvals1 },
			{ OutputLvals = OutputLvals1 },
			{ OutputTypes = OutputTypes1 },
			{ ConvDecls = ConvDecls1 },
			{ ConvOutputStatements = ConvOutputStatements1 }
		; { ArgMode = top_in } ->
			%
			% it's an input argument
			%
			{ type_util__is_dummy_argument_type(CallerType) ->
				% The variable may not have been declared,
				% so we need to generate a dummy value for it.
				% Using `0' here is more efficient than
				% using private_builtin__dummy_var, which is
				% what ml_gen_var will have generated for this
				% variable.
				VarRval = const(int_const(0))
			;
				VarRval = lval(VarLval)
			},
			ml_gen_box_or_unbox_rval(CallerType, CalleeType,
				VarRval, ArgRval),
			{ InputRvals = [ArgRval | InputRvals1] },
			{ OutputLvals = OutputLvals1 },
			{ OutputTypes = OutputTypes1 },
			{ ConvDecls = ConvDecls1 },
			{ ConvOutputStatements = ConvOutputStatements1 }
		;
			%
			% it's an output argument
			%
			ml_gen_box_or_unbox_lval(CallerType, CalleeType,
				VarLval, VarName, Context, ArgLval,
				ThisArgConvDecls, _ThisArgConvInput,
				ThisArgConvOutput),
			{ ConvDecls = list__append(ThisArgConvDecls,
				ConvDecls1) },
			{ ConvOutputStatements = list__append(
				ThisArgConvOutput, ConvOutputStatements1) },
			ml_gen_info_get_globals(Globals),
			{ CopyOut = get_copy_out_option(Globals, CodeModel) },
			(
				(
					%
					% if the target language allows
					% multiple return values, then use them
					%
					{ CopyOut = yes }
				;
					%
					% if this is the result argument 
					% of a model_det function, and it has
					% an output mode, then return it as a
					% value
					%
					{ VarNames1 = [] },
					{ CodeModel = model_det },
					{ PredOrFunc = function },
					{ ArgMode = top_out }
				)
			->
				{ InputRvals = InputRvals1 },
				{ OutputLvals = [ArgLval | OutputLvals1] },
				ml_gen_type(CalleeType, OutputType),
				{ OutputTypes = [OutputType | OutputTypes1] }
			;
				%
				% otherwise use the traditional C style
				% of passing the address of the output value
				%
				{ InputRvals = [ml_gen_mem_addr(ArgLval)
					| InputRvals1] },
				{ OutputLvals = OutputLvals1 },
				{ OutputTypes = OutputTypes1 }
			)
		)
	;
		{ error("ml_gen_arg_list: length mismatch") }
	).

	% ml_gen_mem_addr(Lval) returns a value equal to &Lval.
	% For the case where Lval = *Rval, for some Rval,
	% we optimize &*Rval to just Rval.
:- func ml_gen_mem_addr(mlds__lval) = mlds__rval.
ml_gen_mem_addr(Lval) =
	(if Lval = mem_ref(Rval, _) then Rval else mem_addr(Lval)).

	% Convert VarRval, of type SourceType,
	% to ArgRval, of type DestType.
ml_gen_box_or_unbox_rval(SourceType, DestType, VarRval, ArgRval) -->
	(
		%
		% if converting from polymorphic type to concrete type,
		% then unbox
		%
		{ SourceType = term__variable(_) },
		{ DestType = term__functor(_, _, _) }
	->
		ml_gen_type(DestType, MLDS_DestType),
		{ ArgRval = unop(unbox(MLDS_DestType), VarRval) }
	;
		%
		% if converting from concrete type to polymorphic type,
		% then box
		%
		{ SourceType = term__functor(_, _, _) },
		{ DestType = term__variable(_) }
	->
		ml_gen_type(SourceType, MLDS_SourceType),
		{ ArgRval = unop(box(MLDS_SourceType), VarRval) }
	;
		%
		% if converting to float, cast to mlds__generic_type
		% and then unbox
		%
		{ DestType = term__functor(term__atom("float"), [], _) },
		{ SourceType \= term__functor(term__atom("float"), [], _) }
	->
		ml_gen_type(DestType, MLDS_DestType),
		{ ArgRval = unop(unbox(MLDS_DestType),
			unop(cast(mlds__generic_type), VarRval)) }
	;
		%
		% if converting from float, box and then cast the result
		%
		{ SourceType = term__functor(term__atom("float"), [], _) },
		{ DestType \= term__functor(term__atom("float"), [], _) }
	->
		ml_gen_type(SourceType, MLDS_SourceType),
		ml_gen_type(DestType, MLDS_DestType),
		{ ArgRval = unop(cast(MLDS_DestType),
			unop(box(MLDS_SourceType), VarRval)) }
	;
		%
		% if converting from one concrete type to a different
		% one, then cast
		%
		% This is needed to handle construction/deconstruction
		% unifications for no_tag types.
		%
		{ \+ type_util__type_unify(SourceType, DestType,
			[], map__init, _) }
	->
		ml_gen_type(DestType, MLDS_DestType),
		{ ArgRval = unop(cast(MLDS_DestType), VarRval) }
	;
		%
		% otherwise leave unchanged
		%
		{ ArgRval = VarRval }
	).
	
ml_gen_box_or_unbox_lval(CallerType, CalleeType, VarLval, VarName, Context,
		ArgLval, ConvDecls, ConvInputStatements, ConvOutputStatements)
		-->
	%
	% First see if we can just convert the lval as an rval;
	% if no boxing/unboxing is required, then ml_box_or_unbox_rval
	% will return its argument unchanged, and so we're done.
	%
	ml_gen_box_or_unbox_rval(CalleeType, CallerType, lval(VarLval),
		BoxedRval),
	(
		{ BoxedRval = lval(VarLval) }
	->
		{ ArgLval = VarLval },
		{ ConvDecls = [] },
		{ ConvInputStatements = [] },
		{ ConvOutputStatements = [] }
	;
		%
		% If that didn't work, then we need to declare a fresh variable
		% to use as the arg, and to generate statements to box/unbox
		% that fresh arg variable and assign it to/from the output argument
		% whose address we were passed.
		%

		% generate a declaration for the fresh variable
		ml_gen_info_new_conv_var(ConvVarNum),
		{ string__format("conv%d_%s", [i(ConvVarNum), s(VarName)],
			ArgVarName) },
		=(Info),
		{ ml_gen_info_get_module_info(Info, ModuleInfo) },
		{ ArgVarDecl = ml_gen_var_decl(ArgVarName, CalleeType,
			mlds__make_context(Context), ModuleInfo) },
		{ ConvDecls = [ArgVarDecl] },

		% create the lval for the variable and use it for the
		% argument lval
		ml_qualify_var(ArgVarName, ArgLval),

		( { type_util__is_dummy_argument_type(CallerType) } ->
			% if it is a dummy argument type (e.g. io__state),
			% then we don't need to bother assigning it
			{ ConvInputStatements = [] },
			{ ConvOutputStatements = [] }
		;
			%
			% generate statements to box/unbox the fresh variable
			% and assign it to/from the output argument whose
			% address we were passed.
			%

			% assign to the freshly generated arg variable
			ml_gen_box_or_unbox_rval(CallerType, CalleeType,
				lval(VarLval), ConvertedVarRval),
			{ AssignInputStatement = ml_gen_assign(ArgLval,
				ConvertedVarRval, Context) },
			{ ConvInputStatements = [AssignInputStatement] },

			% assign from the freshly generated arg variable
			ml_gen_box_or_unbox_rval(CalleeType, CallerType,
				lval(ArgLval), ConvertedArgRval),
			{ AssignOutputStatement = ml_gen_assign(VarLval,
				ConvertedArgRval, Context) },
			{ ConvOutputStatements = [AssignOutputStatement] }
		)
	).
	
%-----------------------------------------------------------------------------%
%
% Code for builtins
%

	%
	% Generate MLDS code for a call to a builtin procedure.
	%
ml_gen_builtin(PredId, ProcId, ArgVars, CodeModel, Context,
		MLDS_Decls, MLDS_Statements) -->
	
	ml_gen_var_list(ArgVars, ArgLvals),

	=(Info),
	{ ml_gen_info_get_module_info(Info, ModuleInfo) },
	{ predicate_module(ModuleInfo, PredId, ModuleName) },
	{ predicate_name(ModuleInfo, PredId, PredName) },
	{
		builtin_ops__translate_builtin(ModuleName, PredName,
			ProcId, ArgLvals, SimpleCode0)
	->
		SimpleCode = SimpleCode0
	;
		error("ml_gen_builtin: unknown builtin predicate")
	},
	(
		{ CodeModel = model_det },
		(
			{ SimpleCode = assign(Lval, SimpleExpr) }
		->
			{ Rval = ml_gen_simple_expr(SimpleExpr) },
			{ MLDS_Statement = ml_gen_assign(Lval, Rval,
				Context) }
		;
			{ error("Malformed det builtin predicate") }
		)
	;
		{ CodeModel = model_semi },
		(
			{ SimpleCode = test(SimpleTest) }
		->
			{ TestRval = ml_gen_simple_expr(SimpleTest) },
			ml_gen_set_success(TestRval, Context, MLDS_Statement)
		;
			{ error("Malformed semi builtin predicate") }
		)
	;
		{ CodeModel = model_non },
		{ error("Nondet builtin predicate") }
	),
	{ MLDS_Statements = [MLDS_Statement] },
	{ MLDS_Decls = [] }.

:- func ml_gen_simple_expr(simple_expr(mlds__lval)) = mlds__rval.
ml_gen_simple_expr(leaf(Lval)) = lval(Lval).
ml_gen_simple_expr(int_const(Int)) = const(int_const(Int)).
ml_gen_simple_expr(float_const(Float)) = const(float_const(Float)).
ml_gen_simple_expr(unary(Op, Expr)) = unop(std_unop(Op), ml_gen_simple_expr(Expr)).
ml_gen_simple_expr(binary(Op, Expr1, Expr2)) =
	binop(Op, ml_gen_simple_expr(Expr1), ml_gen_simple_expr(Expr2)).


:- func this_file = string.
this_file = "ml_call_gen.m".

:- end_module ml_call_gen.
