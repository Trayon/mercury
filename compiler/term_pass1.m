%-----------------------------------------------------------------------------%
% Copyright (C) 1997-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% term_pass1.m
%
% Main author: crs.
% Significant parts rewritten by zs.
%
% This file contains the first pass of the termination analysis,
% whose job is to discover an upper bound on the difference between
% the sizes of the output arguments of a procedure on the one hand and
% the sizes of a selected set of input arguments of the procedure
% on the other hand. We refer to this selected set of input arguments
% as the "output suppliers".
%
% For details, please refer to the papers mentioned in termination.m.
%
%-----------------------------------------------------------------------------%

:- module term_pass1.

:- interface.

:- import_module hlds_module, hlds_pred, term_util, term_errors.
:- import_module io, list, std_util.

:- type arg_size_result
	--->	ok(
			list(pair(pred_proc_id, int)),
					% Gives the gamma of each procedure
					% in the SCC.
			used_args
					% Gives the output suppliers of
					% each procedure in the SCC.
		)
	;	error(
			list(term_errors__error)
		).

:- pred find_arg_sizes_in_scc(list(pred_proc_id)::in, module_info::in,
	pass_info::in, arg_size_result::out, list(term_errors__error)::out,
	io__state::di, io__state::uo) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module term_traversal, term_errors, hlds_goal, hlds_data, prog_data.
:- import_module mode_util, type_util, lp.

:- import_module int, float, char, string, bool, set, bag, map.
:- import_module term, varset, require.

%-----------------------------------------------------------------------------%

:- type pass1_result
	--->	ok(
			list(path_info),
					% One entry for each path through the
					% code.
			used_args,
					% The next output_supplier map.
			list(term_errors__error)
					% There is an entry in this list for
					% each procedure in the SCC in which
					% the set of active vars is not
					% a subset of the input arguments.
		)
	;	error(
			list(term_errors__error)
		).

find_arg_sizes_in_scc(SCC, Module, PassInfo, ArgSize, TermErrors, S0, S) :-
	init_output_suppliers(SCC, Module, InitOutputSupplierMap),
	find_arg_sizes_in_scc_fixpoint(SCC, Module, PassInfo,
		InitOutputSupplierMap, Result, TermErrors),
	(
		Result = ok(Paths, OutputSupplierMap, SubsetErrors),

		( SubsetErrors = [_ | _] ->
			ArgSize = error(SubsetErrors),
			S = S0
		; Paths = [] ->
			get_context_from_scc(SCC, Module, Context),
			ArgSize = error([Context - no_eqns]),
			S = S0
		;
			solve_equations(Paths, SCC, MaybeSolution, S0, S),
			(
				MaybeSolution = yes(Solution),
				ArgSize = ok(Solution, OutputSupplierMap)
			;
				MaybeSolution = no,
				get_context_from_scc(SCC, Module, Context),
				ArgSize = error([Context - solver_failed])
			)
		)
	;
		Result = error(Errors),
		ArgSize = error(Errors),
		S = S0
	).

%-----------------------------------------------------------------------------%

% Initialise the output suppliers map.
% Initially, we consider that no input arguments contribute their size
% to the output arguments.

:- pred init_output_suppliers(list(pred_proc_id)::in, module_info::in,
	used_args::out) is det.

init_output_suppliers([], _Module, InitMap) :-
	map__init(InitMap).
init_output_suppliers([PPId | PPIds], Module, OutputSupplierMap) :-
	init_output_suppliers(PPIds, Module, OutputSupplierMap0),
	PPId = proc(PredId, ProcId),
	module_info_pred_proc_info(Module, PredId, ProcId, _, ProcInfo),
	proc_info_headvars(ProcInfo, HeadVars),
	MapToNo = lambda([_HeadVar::in, Bool::out] is det, (Bool = no)),
	list__map(MapToNo, HeadVars, BoolList),
	map__det_insert(OutputSupplierMap0, PPId, BoolList, OutputSupplierMap).

%-----------------------------------------------------------------------------%

:- pred find_arg_sizes_in_scc_fixpoint(list(pred_proc_id)::in,
	module_info::in, pass_info::in, used_args::in, pass1_result::out,
	list(term_errors__error)::out) is det.

find_arg_sizes_in_scc_fixpoint(SCC, Module, PassInfo, OutputSupplierMap0,
		Result, TermErrors) :-
	% unsafe_perform_io(io__write_string("find_arg_sizes_in_scc_pass\n")),
	% unsafe_perform_io(io__write(OutputSupplierMap0)),
	% unsafe_perform_io(io__write_string("\n")),
	find_arg_sizes_in_scc_pass(SCC, Module, PassInfo,
		OutputSupplierMap0, [], [], Result1, [], TermErrors1),
	(
		Result1 = error(_),
		Result = Result1,
		TermErrors = TermErrors1
	;
		Result1 = ok(_, OutputSupplierMap1, _),
		( OutputSupplierMap1 = OutputSupplierMap0 ->
			Result = Result1,
			TermErrors = TermErrors1
		;
			find_arg_sizes_in_scc_fixpoint(SCC, Module,
				PassInfo, OutputSupplierMap1,
				Result, TermErrors)
		)
	).

:- pred find_arg_sizes_in_scc_pass(list(pred_proc_id)::in,
	module_info::in, pass_info::in, used_args::in,
	list(path_info)::in, list(term_errors__error)::in, pass1_result::out,
	list(term_errors__error)::in, list(term_errors__error)::out) is det.

find_arg_sizes_in_scc_pass([], _, _, OutputSupplierMap, Paths, SubsetErrors,
		Result, TermErrors, TermErrors) :-
	Result = ok(Paths, OutputSupplierMap, SubsetErrors).
find_arg_sizes_in_scc_pass([PPId | PPIds], Module, PassInfo,
		OutputSupplierMap0, Paths0, SubsetErrors0, Result,
		TermErrors0, TermErrors) :-
	find_arg_sizes_pred(PPId, Module, PassInfo, OutputSupplierMap0,
		Result1, TermErrors1),
	list__append(TermErrors0, TermErrors1, TermErrors2),
	PassInfo = pass_info(_, MaxErrors, _),
	list__take_upto(MaxErrors, TermErrors2, TermErrors3),
	(
		Result1 = error(_),
		Result = Result1,
		TermErrors = TermErrors3
	;
		Result1 = ok(Paths1, OutputSupplierMap1, SubsetErrors1),
		list__append(Paths0, Paths1, Paths),
		list__append(SubsetErrors0, SubsetErrors1, SubsetErrors),
		find_arg_sizes_in_scc_pass(PPIds, Module, PassInfo,
			OutputSupplierMap1, Paths, SubsetErrors, Result,
			TermErrors3, TermErrors)
	).

%-----------------------------------------------------------------------------%

:- pred find_arg_sizes_pred(pred_proc_id::in, module_info::in,
	pass_info::in, used_args::in, pass1_result::out,
	list(term_errors__error)::out) is det.

find_arg_sizes_pred(PPId, Module, PassInfo, OutputSupplierMap0, Result,
		TermErrors) :-
	PPId = proc(PredId, ProcId),
	module_info_pred_proc_info(Module, PredId, ProcId, PredInfo, ProcInfo),
	pred_info_context(PredInfo, Context),
	proc_info_headvars(ProcInfo, Args),
	proc_info_argmodes(ProcInfo, ArgModes),
	proc_info_vartypes(ProcInfo, VarTypes),
	proc_info_goal(ProcInfo, Goal),
	map__init(EmptyMap),
	PassInfo = pass_info(FunctorInfo, MaxErrors, MaxPaths),
	init_traversal_params(Module, FunctorInfo, PPId, Context, VarTypes,
		OutputSupplierMap0, EmptyMap, MaxErrors, MaxPaths, Params),

	partition_call_args(Module, ArgModes, Args, InVars, OutVars),
	Path0 = path_info(PPId, no, 0, [], OutVars),
	set__singleton_set(PathSet0, Path0),
	Info0 = ok(PathSet0, []),
	traverse_goal(Goal, Params, Info0, Info),

	(
		Info = ok(Paths, TermErrors),
		set__to_sorted_list(Paths, PathList),
		upper_bound_active_vars(PathList, AllActiveVars),
		map__lookup(OutputSupplierMap0, PPId,
			OutputSuppliers0),
		update_output_suppliers(Args, AllActiveVars,
			OutputSuppliers0, OutputSuppliers),
		map__det_update(OutputSupplierMap0, PPId,
			OutputSuppliers, OutputSupplierMap),
		( bag__is_subbag(AllActiveVars, InVars) ->
			SubsetErrors = []
		;
			SubsetErrors = [Context -
				not_subset(PPId, AllActiveVars, InVars)]
		),
		Result = ok(PathList, OutputSupplierMap, SubsetErrors)
	;
		Info = error(Errors, TermErrors),
		Result = error(Errors)
	).

:- pred update_output_suppliers(list(prog_var)::in, bag(prog_var)::in,
		list(bool)::in, list(bool)::out) is det.

update_output_suppliers([], _ActiveVars, [], []).
update_output_suppliers([_ | _], _ActiveVars, [], []) :-
	error("update_output_suppliers: Unmatched variables").
update_output_suppliers([], _ActiveVars, [_ | _], []) :-
	error("update_output_suppliers: Unmatched variables").
update_output_suppliers([Arg | Args], ActiveVars,
		[OutputSupplier0 | OutputSuppliers0],
		[OutputSupplier | OutputSuppliers]) :-
	( bag__contains(ActiveVars, Arg) ->
		OutputSupplier = yes
	;
		% This guarantees that the set of output suppliers can only
		% increase, which in turn guarantees that our fixpoint
		% computation is monotonic and therefore terminates.
		OutputSupplier = OutputSupplier0
	),
	update_output_suppliers(Args, ActiveVars,
		OutputSuppliers0, OutputSuppliers).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

% Solve the list of constraints

% output is of the form required by lp_solve.
% which is given the input = [eqn(Const, PPid, [PPidList])]
% max: .......
% c1: PPid - (PPidList) > Const;
% c2: PPid - (PPidList) > Const;
% where PPid (proc(PredId, ProcId)) is printed as ' aPredId_ProcId - b '
% The choice of the letter `a' is arbitrary, and is chosen as lp_solve does
% not allow variables to start with digits.
% The variable `b' is used as lp_solve will only solve for positive values
% of variables.  replacing each variable occurance with ` a#_# - b ', this
% avoids the problem of only allowing positive variables as  a#_# - b can
% be negative even when a#_# and b are both positive.

:- pred solve_equations(list(path_info)::in, list(pred_proc_id)::in,
	maybe(list(pair(pred_proc_id, int)))::out,
	io__state::di, io__state::uo) is det.

solve_equations(Paths, PPIds, Result, S0, S) :-
	(
		convert_equations(Paths, Varset, Equations,
			Objective, PPVars)
	->
		map__values(PPVars, AllVars0),
		list__sort_and_remove_dups(AllVars0, AllVars),
		% unsafe_perform_io(io__write_string("before\n")),
		% unsafe_perform_io(io__write(Equations)),
		% unsafe_perform_io(io__write_string("\n")),
		% unsafe_perform_io(io__write(Objective)),
		% unsafe_perform_io(io__write_string("\n")),
		% unsafe_perform_io(io__write(AllVars)),
		% unsafe_perform_io(io__write_string("\n")),
		lp_solve(Equations, min, Objective, Varset, AllVars, Soln,
			S0, S),
		% unsafe_perform_io(io__write_string("after\n")),
		(
			Soln = unsatisfiable,
			Result = no
		;
			Soln = satisfiable(_ObjVal, SolnVal),
			list__map(lookup_coeff(PPVars, SolnVal), PPIds,
				SolutionList),
			Result = yes(SolutionList)
		)
	;
		Result = no,
		S = S0
	).

:- pred convert_equations(list(path_info)::in, varset::out, lp__equations::out,
	objective::out, map(pred_proc_id, var)::out) is semidet.

convert_equations(Paths, Varset, Equations, Objective, PPVars) :-
	varset__init(Varset0),
	map__init(PredProcVars0),
	set__init(EqnSet0),
	convert_equations_2(Paths, PredProcVars0, PPVars, Varset0, Varset,
		EqnSet0, EqnSet),
	set__to_sorted_list(EqnSet, Equations),
	map__values(PPVars, Vars),
	Convert = lambda([Var::in, Coeff::out] is det,
	(
		Coeff = Var - 1.0
	)),
	list__map(Convert, Vars, Objective).

:- pred convert_equations_2(list(path_info)::in,
	map(pred_proc_id, var)::in, map(pred_proc_id, var)::out,
	varset::in, varset::out,
	set(lp__equation)::in, set(lp__equation)::out) is semidet.

convert_equations_2([], PPVars, PPVars, Varset, Varset, Eqns, Eqns).
convert_equations_2([Path | Paths], PPVars0, PPVars, Varset0, Varset,
		Eqns0, Eqns) :-
	Path = path_info(ThisPPId, _, IntGamma, PPIds, _),
	int__to_float(IntGamma, FloatGamma),
	Eqn = eqn(Coeffs, (>=), FloatGamma),
	pred_proc_var(ThisPPId, ThisVar, Varset0, Varset2, PPVars0, PPVars1),
	Coeffs = [ThisVar - 1.0 | RestCoeffs],
	Convert = lambda([PPId::in, Coeff::out, Pair0::in, Pair::out] is det,
	(
		Pair0 = VS0 - PPV0,
		pred_proc_var(PPId, Var, VS0, VS, PPV0, PPV),
		Coeff = Var - (-1.0),
		Pair = VS - PPV
	)),
	list__map_foldl(Convert, PPIds, RestCoeffs, Varset2 - PPVars1,
		Varset3 - PPVars2),
	set__insert(Eqns0, Eqn, Eqns1),
	convert_equations_2(Paths, PPVars2, PPVars, Varset3, Varset,
		Eqns1, Eqns).

:- pred lookup_coeff(map(pred_proc_id, var)::in, map(var, float)::in,
	pred_proc_id::in, pair(pred_proc_id, int)::out) is det.

lookup_coeff(PPIds, Soln, PPId, PPId - ICoeff) :-
	map__lookup(PPIds, PPId, Var),
	map__lookup(Soln, Var, Coeff),
	float__ceiling_to_int(Coeff, ICoeff).

:- pred pred_proc_var(pred_proc_id::in, var::out, varset::in, varset::out,
	map(pred_proc_id, var)::in, map(pred_proc_id, var)::out) is det.

pred_proc_var(PPId, Var, Varset0, Varset, PPVars0, PPVars) :-
	( map__search(PPVars0, PPId, Var0) ->
		Var = Var0,
		Varset = Varset0,
		PPVars = PPVars0
	;
		varset__new_var(Varset0, Var, Varset),
		map__det_insert(PPVars0, PPId, Var, PPVars)
	).

%-----------------------------------------------------------------------------%
