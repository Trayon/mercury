%-----------------------------------------------------------------------------%
% Copyright (C) 2001-2004 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: mode_constraint.m
% Main author: dmo
%
% This module implements the top level of the algorithm described in the
% paper "Constraint-based mode analysis of Mercury" by David Overton,
% Zoltan Somogyi and Peter Stuckey. That paper is the main documentation
% of the concepts behind the algorithm as well as the algorithm itself.

:- module check_hlds__mode_constraints.
:- interface.

:- import_module hlds__hlds_module.
:- import_module io.

:- pred mode_constraints__process_module(module_info::in, module_info::out,
	io__state::di, io__state::uo) is det.

:- implementation.

:- import_module check_hlds__goal_path.
:- import_module check_hlds__mode_constraint_robdd.
:- import_module check_hlds__mode_ordering.
:- import_module check_hlds__mode_util.
:- import_module hlds__hhf.
:- import_module hlds__hlds_data.
:- import_module hlds__hlds_goal.
:- import_module hlds__hlds_pred.
:- import_module hlds__inst_graph.
:- import_module hlds__passes_aux.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module mode_robdd.
% :- import_module mode_robdd__check.
% :- import_module mode_robdd__tfeir.
:- import_module mode_robdd__tfeirn.
:- import_module parse_tree__prog_data.
:- import_module parse_tree__prog_mode.
:- import_module transform_hlds__dependency_graph.

:- import_module list, map, std_util, bool, set, multi_map, require, int.
:- import_module robdd, term, string, assoc_list, sparse_bitset.
:- import_module varset, term_io.
:- import_module gc.

% :- import_module unsafe.

:- typeclass has_mc_info(T) where [
	func mc_info(T) = mode_constraint_info,
	func 'mc_info :='(T, mode_constraint_info) = T
].

:- typeclass has_module_info(T) where [
	func module_info(T) = module_info,
	func 'module_info :='(T, module_info) = T
].

:- typeclass has_ho_modes(T) where [
	func ho_modes(T) = ho_modes,
	func 'ho_modes :='(T, ho_modes) = T
].

mode_constraints__process_module(!ModuleInfo, !IO) :-
	module_info_predids(!.ModuleInfo, PredIds),
	globals__io_lookup_bool_option(simple_mode_constraints, Simple, !IO),
	list__foldl2(hhf__process_pred(Simple), PredIds, !ModuleInfo, !IO),

	get_predicate_sccs(!.ModuleInfo, SCCs),

	% Stage 1: Process SCCs bottom-up to determine variable producers.
	list__foldl3(mode_constraints__process_scc(Simple), SCCs,
		!ModuleInfo, map__init, PredConstraintMap, !IO),
		
	% Stage 2: Process SCCs top-down to determine execution order of
	% conjuctions and which modes are needed for each predicate.
	mode_ordering(PredConstraintMap, list__reverse(SCCs),
		!ModuleInfo, !IO),

	% Stage 3, which would turn the results of the mode analysis into goal
	% annotations that the rest of the compiler can understand, doesn't
	% exist yet. The whole point of this way of doing mode analysis is
	% to gain extra expressive power (e.g. partially instantiated data
	% structures), and the rest of the compiler doesn't handle the extra
	% expressive power yet.
		
	clear_caches(!IO).

:- pred mode_constraints__process_scc(bool::in, list(pred_id)::in,
	module_info::in, module_info::out,
	pred_constraint_map::in, pred_constraint_map::out,
	io__state::di, io__state::uo) is det.

mode_constraints__process_scc(Simple, SCC, !ModuleInfo, !PredConstraintMap,
		!IO) :-
	ModeConstraint0 = one,
	ModeConstraintInfo0 = init_mode_constraint_info(Simple),
	list__foldl2(number_robdd_variables_in_pred, SCC, !ModuleInfo,
		ModeConstraintInfo0, ModeConstraintInfo1),

	save_threshold(Threshold, ModeConstraintInfo1, ModeConstraintInfo2),
	mode_constraints__process_scc_pass_1(SCC, SCC, !ModuleInfo,
		ModeConstraint0, ModeConstraint1,
		ModeConstraintInfo2, ModeConstraintInfo, !IO),

	ModeConstraint2 = restrict_threshold(Threshold, ModeConstraint1),
	ModeConstraint = ensure_normalised(ModeConstraint2),
	mode_constraints__process_scc_pass_2(SCC, ModeConstraint,
		ModeConstraintInfo, !ModuleInfo, !IO),

	!:PredConstraintMap = list__foldl((func(PredId, PCM) =
		map__det_insert(PCM, PredId,
			pci(ModeConstraint,
				ModeConstraintInfo ^ pred_id := PredId))
		), SCC, !.PredConstraintMap).
		
	% clear_caches(!IO).

:- type number_robdd_info
	--->	number_robdd_info(
			n_mc_info	:: mode_constraint_info,
			n_module_info	:: module_info,
			vartypes	:: vartypes
		).

:- instance has_mc_info(number_robdd_info) where [
	func(mc_info/1) is n_mc_info,
	func('mc_info :='/2) is 'n_mc_info :='
].

:- instance has_module_info(number_robdd_info) where [
	func(module_info/1) is n_module_info,
	func('module_info :='/2) is 'n_module_info :='
].

:- pred update_mc_info(pred(T, mode_constraint_info, mode_constraint_info),
	T, C, C) <= has_mc_info(C).
:- mode update_mc_info(pred(out, in, out) is det, out, in, out) is det.

update_mc_info(P, R, !C) :-
	MCInfo0 = !.C ^ mc_info,
	P(R, MCInfo0, MCInfo),
	!:C = !.C ^ mc_info := MCInfo.

:- pred update_mc_info(pred(mode_constraint_info, mode_constraint_info),
	C, C) <= has_mc_info(C).
:- mode update_mc_info(pred(in, out) is det, in, out) is det.
:- mode update_mc_info(pred(in, out) is semidet, in, out) is semidet.

update_mc_info(P, !C) :-
	MCInfo0 = !.C ^ mc_info,
	P(MCInfo0, MCInfo),
	!:C = !.C ^ mc_info := MCInfo.

:- pred update_md_info(pred(T, mode_decl_info, mode_decl_info), T, C, C)
	<= (has_mc_info(C), has_ho_modes(C)).
:- mode update_md_info(pred(out, in, out) is det, out, in, out) is det.

update_md_info(P, R, !C) :-
	MCInfo0 = !.C ^ mc_info,
	HOModes0 = !.C ^ ho_modes,
	MDInfo0 = mode_decl_info(MCInfo0, HOModes0),
	P(R, MDInfo0, MDInfo),
	!:C = !.C ^ mc_info := MDInfo ^ mc_info,
	!:C = !.C ^ ho_modes := MDInfo ^ ho_modes.

	% Assign a number to all the ROBDD variables that we want to keep at
	% the end of the analysis.
	% This allows us to use `restrict_threshold' during the analysis
	% to remove all unwanted variables.
	% `Restrict_threshold' is much faster than using `robdd__filter'
	% or `robdd__restrict'.
:- pred number_robdd_variables_in_pred(pred_id::in, module_info::in,
	module_info::out, mode_constraint_info::in, mode_constraint_info::out)
	is det.

number_robdd_variables_in_pred(PredId, !ModuleInfo, !MCI) :-
	!:MCI = !.MCI ^ pred_id := PredId,
	module_info_pred_info(!.ModuleInfo, PredId, PredInfo0),

	save_min_var_for_pred(PredId, !MCI),

	% Variables in each branch of a branched goal are always equivalent.
	% Likewise, a variable in a negated or existentially quantified goal
	% will always be equivalent to the variable in the parent goal. This
	% means we can use the same mode_constraint_var for each of these
	% equivalent variables, avoiding adding lots of equivalence constraints
	% to the ROBDD. This is a good thing since equivalence constraints tend
	% to cause exponential explosions in ROBDDs. We achieve this by passing
	% `OmitModeEquivPrefix = yes' to `goal_path__fill_slots_in_clauses'.

	OmitModeEquivPrefix = yes,
	goal_path__fill_slots_in_clauses(!.ModuleInfo, OmitModeEquivPrefix,
		PredInfo0, PredInfo1),

	pred_info_clauses_info(PredInfo1, ClausesInfo0),
	clauses_info_headvars(ClausesInfo0, HeadVars),
	InstGraph = PredInfo1 ^ inst_graph_info ^ implementation_inst_graph,
	inst_graph__foldl_reachable_from_list(
		( pred(V::in, S0::in, S::out) is det :-
			mode_constraint_var(in(V), _, S0, S1),
			mode_constraint_var(out(V), _, S1, S2),
			mode_constraint_var(V `at` [], _, S2, S)
		), InstGraph, HeadVars, !MCI),

	( pred_info_is_imported(PredInfo0) ->
		true
	;
		clauses_info_clauses(ClausesInfo0, Clauses0),
		clauses_info_vartypes(ClausesInfo0, VarTypes),
		NRInfo0 = number_robdd_info(!.MCI, !.ModuleInfo, VarTypes),

		list__map_foldl(
			(pred(Clause0::in, Clause::out, S0::in, S::out)
					is det :-
				Clause0 = clause(A, Goal0, C, D),
				number_robdd_variables_in_goal(InstGraph,
					set__init, _, Goal0, Goal, S0, S),
				Clause = clause(A, Goal, C, D)
		), Clauses0, Clauses, NRInfo0, NRInfo),

		!:MCI = NRInfo ^ mc_info,
		clauses_info_set_clauses(Clauses, ClausesInfo0, ClausesInfo),
		pred_info_set_clauses_info(ClausesInfo, PredInfo1, PredInfo),
		module_info_set_pred_info(PredId, PredInfo, !ModuleInfo)
	),
	save_max_var_for_pred(PredId, !MCI).

:- pred number_robdd_variables_in_goal(inst_graph::in,
	set(prog_var)::in, set(prog_var)::out, hlds_goal::in, hlds_goal::out,
	number_robdd_info::in, number_robdd_info::out) is det.

number_robdd_variables_in_goal(InstGraph, ParentNonLocals, Occurring,
		GoalExpr0 - GoalInfo0, GoalExpr - GoalInfo, !RInfo) :-
	goal_info_get_nonlocals(GoalInfo0, NonLocals),
	goal_info_get_goal_path(GoalInfo0, GoalPath),
	number_robdd_variables_in_goal_2(InstGraph, GoalPath, ParentNonLocals,
		NonLocals, Occurring, GoalExpr0, GoalExpr, !RInfo),
	goal_info_set_occurring_vars(GoalInfo0, Occurring, GoalInfo).

:- pred number_robdd_variables_in_goal_2(inst_graph::in, goal_path::in,
	set(prog_var)::in, set(prog_var)::in, set(prog_var)::out,
	hlds_goal_expr::in, hlds_goal_expr::out,
	number_robdd_info::in, number_robdd_info::out) is det.

number_robdd_variables_in_goal_2(InstGraph, _, _, NonLocals, Occurring,
		conj(Goals0), conj(Goals), !RInfo) :-
	number_robdd_variables_in_goals(InstGraph, NonLocals, Occurring,
		Goals0, Goals, !RInfo).
number_robdd_variables_in_goal_2(InstGraph, _, _, NonLocals, Occurring,
		disj(Goals0), disj(Goals), !RInfo) :-
	number_robdd_variables_in_goals(InstGraph, NonLocals, Occurring,
		Goals0, Goals, !RInfo).
number_robdd_variables_in_goal_2(InstGraph, _, _, NonLocals, Occurring,
		switch(V, CF, Cases0), switch(V, CF, Cases), !RInfo) :-
	number_robdd_variables_in_cases(InstGraph, NonLocals, Occurring,
		Cases0, Cases, !RInfo).
number_robdd_variables_in_goal_2(InstGraph, _, _, NonLocals, Occurring,
		not(Goal0), not(Goal), !RInfo) :-
	number_robdd_variables_in_goal(InstGraph, NonLocals, Occurring,
		Goal0, Goal, !RInfo).
number_robdd_variables_in_goal_2(InstGraph, _, _, NonLocals, Occurring,
		some(V, CR, Goal0), some(V, CR, Goal), !RInfo) :-
	number_robdd_variables_in_goal(InstGraph, NonLocals, Occurring,
		Goal0, Goal, !RInfo).
number_robdd_variables_in_goal_2(InstGraph, _, _, NonLocals, Occurring,
		if_then_else(Vs, Cond0, Then0, Else0),
		if_then_else(Vs, Cond, Then, Else), !RInfo) :-
	number_robdd_variables_in_goal(InstGraph, NonLocals, OccCond,
		Cond0, Cond, !RInfo),
	number_robdd_variables_in_goal(InstGraph, NonLocals, OccThen,
		Then0, Then, !RInfo),
	number_robdd_variables_in_goal(InstGraph, NonLocals, OccElse,
		Else0, Else, !RInfo),
	Occurring = OccCond `set__union` OccThen `set__union` OccElse.
number_robdd_variables_in_goal_2(InstGraph, _, _, NonLocals, Occurring,
		par_conj(Goals0), par_conj(Goals), !RInfo) :-
	number_robdd_variables_in_goals(InstGraph, NonLocals, Occurring,
		Goals0, Goals, !RInfo).
number_robdd_variables_in_goal_2(_, _, _, _, _, shorthand(_), _, !RInfo) :-
	error("number_robdd_variables_in_goal_2: shorthand").

number_robdd_variables_in_goal_2(InstGraph, GoalPath, ParentNonLocals, _,
		Occurring, GoalExpr, GoalExpr, !RInfo) :-
	GoalExpr = call(_, _, Args, _, _, _),
	number_robdd_variables_at_goal_path(InstGraph, GoalPath,
		ParentNonLocals, Args, Occurring, !RInfo).
number_robdd_variables_in_goal_2(InstGraph, GoalPath, ParentNonLocals, _,
		Occurring, GoalExpr, GoalExpr, !RInfo) :-
	GoalExpr = generic_call(_, Args, _, _),
	number_robdd_variables_at_goal_path(InstGraph, GoalPath,
		ParentNonLocals, Args, Occurring, !RInfo).
number_robdd_variables_in_goal_2(InstGraph, GoalPath, ParentNonLocals, _,
		Occurring, GoalExpr0, GoalExpr, !RInfo) :-
	GoalExpr0 = unify(VarL, RHS0, _, _, _),
	number_robdd_variables_in_rhs(InstGraph, GoalPath, Vars, RHS0, RHS,
		!RInfo),
	GoalExpr = GoalExpr0 ^ unify_rhs := RHS,
	number_robdd_variables_at_goal_path(InstGraph, GoalPath,
		ParentNonLocals, [VarL | Vars], Occurring, !RInfo).
number_robdd_variables_in_goal_2(InstGraph, GoalPath, ParentNonLocals, _,
		Occurring, GoalExpr, GoalExpr, !RInfo) :-
	GoalExpr = foreign_proc(_, _, _, Args, _, _),
	ArgVars = list__map(foreign_arg_var, Args),
	number_robdd_variables_at_goal_path(InstGraph, GoalPath,
		ParentNonLocals, ArgVars, Occurring, !RInfo).

:- pred number_robdd_variables_in_rhs(inst_graph::in, goal_path::in,
	list(prog_var)::out, unify_rhs::in, unify_rhs::out,
	number_robdd_info::in, number_robdd_info::out) is det.

number_robdd_variables_in_rhs(_, _, Vars, !RHS, !NRInfo) :-
	!.RHS = var(VarR),
	Vars = [VarR].
number_robdd_variables_in_rhs(_, _, Vars, !RHS, !NRInfo) :-
	!.RHS = functor(_, _, Args),
	Vars = Args.
number_robdd_variables_in_rhs(InstGraph, GoalPath, Vars, !RHS, !NRInfo) :-
	!.RHS = lambda_goal(_, _, _, _, LambdaNonLocals, LambdaVars, _, _,
		LambdaGoal0),
	Vars = LambdaNonLocals,
	VarTypes = !.NRInfo ^ vartypes,
	ModuleInfo = !.NRInfo ^ module_info,
	goal_path__fill_slots_in_goal(LambdaGoal0, VarTypes, ModuleInfo,
		LambdaGoal1),
	update_mc_info(enter_lambda_goal(GoalPath), !NRInfo),

	% Number arguments to the lambda goal, i.e. the nonlocals and the
	% lambda-quantified variables.
	LambdaHeadVars = LambdaNonLocals `list__append` LambdaVars,
	update_mc_info(pred(in, out) is det -->
		inst_graph__foldl_reachable_from_list(
			( pred(V::in, in, out) is det -->
				mode_constraint_var(in(V), _),
				mode_constraint_var(out(V), _),
				mode_constraint_var(V `at` [], _)
			), InstGraph, LambdaHeadVars), !NRInfo),

	% Number variables within the lambda goal.
	number_robdd_variables_in_goal(InstGraph, set__init, _Occurring,
		LambdaGoal1, LambdaGoal, !NRInfo),

	update_mc_info(leave_lambda_goal, !NRInfo),
	!:RHS = !.RHS ^ rhs_lambda_goal := LambdaGoal.

:- pred number_robdd_variables_at_goal_path(inst_graph::in, goal_path::in,
	set(prog_var)::in, list(prog_var)::in, set(prog_var)::out,
	number_robdd_info::in, number_robdd_info::out) is det.

number_robdd_variables_at_goal_path(InstGraph, GoalPath, ParentNonLocals,
		Vars0, Occurring, !NRInfo) :-
	solutions_set(inst_graph__reachable_from_list(InstGraph, Vars0),
		Occurring),
	Vars = set__to_sorted_list(ParentNonLocals `set__union` 
		set__list_to_set(Vars0)),
	% XXX We may be able to make this more efficient.
	inst_graph__foldl_reachable_from_list(
		(pred(V::in, S0::in, S::out) is det :-
			update_mc_info(mode_constraint_var(V `at` GoalPath),
				_, S0, S)
		), InstGraph, Vars, !NRInfo).

:- pred number_robdd_variables_in_goals(inst_graph::in, set(prog_var)::in,
	set(prog_var)::out, hlds_goals::in, hlds_goals::out,
	number_robdd_info::in, number_robdd_info::out) is det.

number_robdd_variables_in_goals(_, _, Occurring, [], [], !RInfo) :-
	set__init(Occurring).
number_robdd_variables_in_goals(InstGraph, NonLocals, Occurring,
		[Goal0 | Goals0], [Goal | Goals], !RInfo) :-
	number_robdd_variables_in_goal(InstGraph, NonLocals, Occurring0,
		Goal0, Goal, !RInfo),
	number_robdd_variables_in_goals(InstGraph, NonLocals, Occurring1,
		Goals0, Goals, !RInfo),
	Occurring = Occurring0 `set__union` Occurring1.

:- pred number_robdd_variables_in_cases(inst_graph::in, set(prog_var)::in,
	set(prog_var)::out, list(case)::in, list(case)::out,
	number_robdd_info::in, number_robdd_info::out) is det.

number_robdd_variables_in_cases(_, _, Occurring, [], [], !RInfo) :-
	set__init(Occurring).
number_robdd_variables_in_cases(InstGraph, NonLocals, Occurring,
		[case(C, Goal0) | Cases0], [case(C, Goal) | Cases], !RInfo) :-
	number_robdd_variables_in_goal(InstGraph, NonLocals, Occurring0,
		Goal0, Goal, !RInfo),
	number_robdd_variables_in_cases(InstGraph, NonLocals, Occurring1,
		Cases0, Cases, !RInfo),
	Occurring = Occurring0 `set__union` Occurring1 .

:- pred mode_constraints__process_scc_pass_1(list(pred_id)::in,
	list(pred_id)::in, module_info::in,
	module_info::out, mode_constraint::in, mode_constraint::out,
	mode_constraint_info::in, mode_constraint_info::out,
	io__state::di, io__state::uo) is det.

mode_constraints__process_scc_pass_1([], _, !ModuleInfo,
		!ModeConstraint, !ModeConstraintInfo, !IO).
mode_constraints__process_scc_pass_1([PredId | PredIds], SCC,
		!ModuleInfo, !ModeConstraint, !ModeConstraintInfo, !IO) :-
	!:ModeConstraintInfo = !.ModeConstraintInfo ^ pred_id := PredId,
	mode_constraints__process_pred(PredId, SCC, !ModuleInfo,
		!ModeConstraint, !ModeConstraintInfo, !IO),
	mode_constraints__process_scc_pass_1(PredIds, SCC, !ModuleInfo,
		!ModeConstraint, !ModeConstraintInfo, !IO).

:- pred mode_constraints__process_scc_pass_2(list(pred_id)::in,
	mode_constraint::in, mode_constraint_info::in, module_info::in,
	module_info::out, io__state::di, io__state::uo) is det.

mode_constraints__process_scc_pass_2([], _, _, !ModuleInfo, !IO).
mode_constraints__process_scc_pass_2([PredId | PredIds], ModeConstraint,
		ModeConstraintInfo, !ModuleInfo, !IO) :-
	mode_constraints__process_pred_2(PredId, ModeConstraint,
		ModeConstraintInfo ^ pred_id := PredId, !ModuleInfo, !IO),
	mode_constraints__process_scc_pass_2(PredIds, ModeConstraint,
		ModeConstraintInfo, !ModuleInfo, !IO).

:- pred mode_constraints__process_pred(pred_id::in, list(pred_id)::in,
	module_info::in, module_info::out, mode_constraint::in,
	mode_constraint::out, mode_constraint_info::in,
	mode_constraint_info::out, io__state::di, io__state::uo) is det.

mode_constraints__process_pred(PredId, SCC, !ModuleInfo, !ModeConstraint,
		!ModeConstraintInfo, !IO) :-
	module_info_pred_info(!.ModuleInfo, PredId, PredInfo0),
	write_pred_progress_message("% Calculating mode constraints for ",
		PredId, !.ModuleInfo, !IO),
	io__flush_output(!IO),

	InstGraph = PredInfo0 ^ inst_graph_info ^ implementation_inst_graph,
	pred_info_procedures(PredInfo0, ProcTable0),
	pred_info_clauses_info(PredInfo0, ClausesInfo0),
	clauses_info_headvars(ClausesInfo0, HeadVars),

	HOModes0 = map__init,
	( ( map__is_empty(ProcTable0) ; pred_info_infer_modes(PredInfo0) ) ->
		DeclConstraint = one,
		HOModes = HOModes0,
		PredInfo1 = PredInfo0
	;
		ModeDeclInfo0 = mode_decl_info(!.ModeConstraintInfo, HOModes0),
		map__map_foldl2(
			mode_constraints__mode_decl_to_constraint(!.ModuleInfo,
				InstGraph, HeadVars, PredInfo0),
			ProcTable0, ProcTable,
			zero, DeclConstraint, ModeDeclInfo0, ModeDeclInfo),
		!:ModeConstraintInfo = ModeDeclInfo ^ mc_info,
		HOModes = ModeDeclInfo ^ ho_modes,
		pred_info_set_procedures(ProcTable, PredInfo0, PredInfo1)
	),
	!:ModeConstraint = !.ModeConstraint * DeclConstraint,
	set_input_nodes(!ModeConstraint, !ModeConstraintInfo),

	% clauses_info_varset(ClausesInfo0, ProgVarSet),
	% pred_id_to_int(PredId, PredIdInt),
	% robdd_to_dot(DeclConstraint, ProgVarSet, ModeConstraintInfo1,
	% 	format("mode_decl_%d.dot", [i(PredIdInt)]), !IO),
	% robdd_to_dot(ModeConstraint1, ProgVarSet, ModeConstraintInfo1,
	% 	format("mode_constraint1_%d.dot", [i(PredIdInt)]), !IO),
	% io__flush_output(!IO),

	( pred_info_is_imported(PredInfo1) ->
		PredInfo = PredInfo1
	;

		mode_constraints__process_clauses_info(!.ModuleInfo, SCC,
			ClausesInfo0, ClausesInfo, InstGraph, HOModes,
			!ModeConstraint, !ModeConstraintInfo, !IO),
		pred_info_set_clauses_info(ClausesInfo,
			PredInfo1, PredInfo)
	),
	module_info_set_pred_info(PredId, PredInfo, !ModuleInfo).

:- pred mode_constraints__process_pred_2(pred_id::in, mode_constraint::in,
	mode_constraint_info::in, module_info::in, module_info::out,
	io__state::di, io__state::uo) is det.

mode_constraints__process_pred_2(PredId, ModeConstraint, ModeConstraintInfo0,
		!ModuleInfo, !IO) :-

	module_info_pred_info(!.ModuleInfo, PredId, PredInfo0),
	InstGraph = PredInfo0 ^ inst_graph_info ^ implementation_inst_graph,
	pred_info_clauses_info(PredInfo0, ClausesInfo),
	clauses_info_headvars(ClausesInfo, HeadVars),

	% DMO document this better
	% XXX Needed for analysing calls. May want to store the constraint
	% as an ROBDD instead.
	solutions(arg_modes_map(HeadVars, InstGraph, ModeConstraint,
		ModeConstraintInfo0), Modes),
	PredInfo = PredInfo0 ^ modes := Modes,
	% PredInfo = PredInfo0,

	% DEBUGGING CODE
	% dump_mode_constraints(!.ModuleInfo, PredInfo0, InstGraph,
	% 	ModeConstraint, ModeConstraintInfo0),
	% io__flush_output(!IO),
	% 
	% list__foldl((pred(M - _::in, di, uo) is det -->
	% 	map__foldl((pred(_MV::in, Val::in, di, uo) is det -->
	% 		io__write_string(Val = yes -> "1 " ; "0 ")
	% 	), M),
	% 	io__nl
	% ), Modes),
	% 
	% io__nl(!IO),
	% 
	% solutions(inst_graph__reachable_from_list(InstGraph, HeadVars),
	% 	ReachVars),
	% list__map_foldl((pred(PV::in, MV::out, in, out) is det -->
	% 	mode_constraint_var(in(PV), MV)
	% ), ReachVars, InVars, ModeConstraintInfo0, ModeConstraintInfo),
	% 
	% InVarConstraint = restrict_filter((pred(in(V)::in) is semidet :-
	% 		list__member(V, ReachVars)),
	% 	ModeConstraintInfo, ModeConstraint),
	% aggregate(fundamental_mode(set__list_to_set(InVars), InVarConstraint),
	% 	(pred(M::in, di, uo) is det -->
	% 		map__foldl((pred(_MV::in, Val::in, di, uo) is det -->
	% 			io__write_string(Val = yes -> "1 " ; "0 ")
	% 		), M),
	% 	io__nl
	% ), !IO),

	% DMO justify or delete
	% split_constraint_into_modes(PredId, HeadVars, InstGraph,
	% 	ModeConstraint, _ProcConstraints, ModeConstraintInfo0,
	% 	ModeConstraintInfo),

	% DEBUGGING CODE
	% clauses_info_varset(ClausesInfo, ProgVarSet),
	% pred_info_name(PredInfo, Name),
	% robdd_to_dot(ModeConstraint, ProgVarSet, ModeConstraintInfo,
	% 	Name `string__append` ".dot", !IO),
	% io__flush_output(!IO),

	module_info_set_pred_info(PredId, PredInfo, !ModuleInfo).

:- type goal_constraints_info
	--->	goal_constraints_info(
			g_module_info	:: module_info,
			scc		:: list(pred_id),
			inst_graph	:: inst_graph,
			headvars	:: list(prog_var),
			prog_varset	:: prog_varset,
			atomic_goals	:: set(goal_path),
			g_mc_info	:: mode_constraint_info,
			g_ho_modes	:: ho_modes,
			ho_calls	:: ho_calls
		).

:- instance has_mc_info(goal_constraints_info) where [
	func(mc_info/1) is g_mc_info,
	func('mc_info :='/2) is 'g_mc_info :='
].

:- instance has_module_info(goal_constraints_info) where [
	func(module_info/1) is g_module_info,
	func('module_info :='/2) is 'g_module_info :='
].

:- instance has_ho_modes(goal_constraints_info) where [
	func(ho_modes/1) is g_ho_modes,
	func('ho_modes :='/2) is 'g_ho_modes :='
].

:- type ho_modes ==
	multi_map(prog_var_and_level, list(mode)).

:- type ho_calls ==
	multi_map(prog_var_and_level, pair(goal_path, list(prog_var))).

:- pred get_var(rep_var::in, mode_constraint_var::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

get_var(RepVar, MCVar, !GCInfo) :-
	update_mc_info(mode_constraint_var(RepVar), MCVar, !GCInfo).

:- pred get_var(pred_id::in, rep_var::in, mode_constraint_var::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

get_var(PredId, RepVar, MCVar, !GCInfo) :-
	update_mc_info(mode_constraint_var(PredId, RepVar), MCVar, !GCInfo).

:- pred save_thresh(threshold::out, goal_constraints_info::in,
	goal_constraints_info::out) is det.

save_thresh(Thresh, !GCInfo) :-
	update_mc_info(save_threshold, Thresh, !GCInfo).

:- pred add_atomic_goal(goal_path::in, goal_constraints_info::in,
	goal_constraints_info::out) is det.

add_atomic_goal(GoalPath, !GCInfo) :-
	AtomicGoals = !.GCInfo ^ atomic_goals,
	!:GCInfo = !.GCInfo ^ atomic_goals :=
		AtomicGoals `set__insert` GoalPath.

:- type mode_decl_info
	--->	mode_decl_info(
			d_mc_info :: mode_constraint_info,
			d_ho_modes :: ho_modes
		).

:- instance has_mc_info(mode_decl_info) where [
	func(mc_info/1) is d_mc_info,
	func('mc_info :='/2) is 'd_mc_info :='
].

:- instance has_ho_modes(mode_decl_info) where [
	func(ho_modes/1) is d_ho_modes,
	func('ho_modes :='/2) is 'd_ho_modes :='
].

	% Convert a procedure's arg_modes to a constraint.
:- pred mode_constraints__mode_decl_to_constraint(module_info::in,
	inst_graph::in, list(prog_var)::in, pred_info::in, proc_id::in,
	proc_info::in, proc_info::out,
	mode_constraint::in, mode_constraint::out,
	mode_decl_info::in, mode_decl_info::out) is det.

mode_constraints__mode_decl_to_constraint(ModuleInfo, InstGraph, HeadVars,
		_PredInfo, _ProcId, !ProcInfo, !Constraint, !Info) :-
	mode_constraints__process_mode_decl_for_proc(ModuleInfo,
		InstGraph, HeadVars,
		false_var(initial), true_var(initial), yes,
		false_var(final), true_var(final), no,
		!.ProcInfo, zero, DeclConstraint, !Info),

	% proc_id_to_int(ProcId, ProcIdInt),
	% pred_info_name(PredInfo, Name),
	% pred_info_clauses_info(PredInfo, ClausesInfo),
	% clauses_info_varset(ClausesInfo, ProgVarSet),
	% unsafe_perform_io(robdd_to_dot(DeclConstraint, ProgVarSet,
	%	Info ^ mc_info, Name ++ int_to_string(ProcIdInt) ++ ".dot")),

	!:Constraint = !.Constraint + DeclConstraint,
	proc_info_set_head_modes_constraint(DeclConstraint, !ProcInfo).

:- pred mode_constraints__process_mode_decl_for_proc(module_info::in,
	inst_graph::in, list(prog_var)::in,
	constrain_var::in(constrain_var), constrain_var::in(constrain_var),
	bool::in,
	constrain_var::in(constrain_var), constrain_var::in(constrain_var),
	bool::in,
	proc_info::in, mode_constraint::in, mode_constraint::out,
	mode_decl_info::in, mode_decl_info::out) is det.

mode_constraints__process_mode_decl_for_proc(ModuleInfo, InstGraph, HeadVars,
		InitialFree, InitialBound, InitialHO,
		FinalFree, FinalBound, FinalHO,
		ProcInfo, !Constraint, !MDI) :-
	% proc_info_declared_argmodes(ProcInfo, ArgModes),
	proc_info_argmodes(ProcInfo, ArgModes),
	mode_constraints__process_mode_decl(ModuleInfo, InstGraph, HeadVars,
		InitialFree, InitialBound, InitialHO,
		FinalFree, FinalBound, FinalHO,
		ArgModes, !Constraint, !MDI).

:- pred mode_constraints__process_mode_decl(module_info::in,
	inst_graph::in, list(prog_var)::in, constrain_var::in(constrain_var),
	constrain_var::in(constrain_var), bool::in,
	constrain_var::in(constrain_var), constrain_var::in(constrain_var),
	bool::in, list(mode)::in, mode_constraint::in, mode_constraint::out,
	mode_decl_info::in, mode_decl_info::out) is det.

mode_constraints__process_mode_decl(ModuleInfo, InstGraph, HeadVars,
		InitialFree, InitialBound, InitialHO,
		FinalFree, FinalBound, FinalHO, ArgModes, !Constraint, !MDI) :-
	assoc_list__from_corresponding_lists(HeadVars, ArgModes, VarModes),
	list__foldl2(mode_constraints__process_arg_modes(ModuleInfo, InstGraph,
		InitialFree, InitialBound, InitialHO,
		FinalFree, FinalBound, FinalHO),
		VarModes, one, NewConstraint, !MDI),
	!:Constraint = !.Constraint + NewConstraint.

:- pred mode_constraints__process_arg_modes(module_info::in, inst_graph::in,
	constrain_var::in(constrain_var), constrain_var::in(constrain_var),
	bool::in,
	constrain_var::in(constrain_var), constrain_var::in(constrain_var),
	bool::in,
	pair(prog_var, mode)::in,
	mode_constraint::in, mode_constraint::out,
	mode_decl_info::in, mode_decl_info::out) is det.

mode_constraints__process_arg_modes(ModuleInfo, InstGraph,
		InitialFree, InitialBound, InitialHO,
		FinalFree, FinalBound, FinalHO,
		Var - Mode, !Constraint, !MDI) :-
	mode_get_insts(ModuleInfo, Mode, InitialInst, FinalInst),
	mode_constraints__process_inst(ModuleInfo, InstGraph,
		InitialFree, InitialBound, InitialHO, InitialInst,
		set__init, Var, !Constraint, !MDI),
	mode_constraints__process_inst(ModuleInfo, InstGraph,
		FinalFree, FinalBound, FinalHO, FinalInst,
		set__init, Var, !Constraint, !MDI).

:- func initial(prog_var) = rep_var.

initial(Var) = in(Var).

:- func final(prog_var) = rep_var.

final(Var) = out(Var).

:- func goal_path(goal_path, prog_var) = rep_var.

goal_path(Path, Var) = Var `at` Path.

:- pred true_var(func(prog_var) = rep_var, prog_var, mode_constraint,
	mode_constraint, mode_constraint_info, mode_constraint_info).
:- mode true_var(func(in) = out is det, in, in, out, in, out) is det.

true_var(F, V, !C, !MCI) :-
	mode_constraint_var(F(V), CV, !MCI),
	!:C = !.C ^ var(CV).

:- pred false_var(func(prog_var) = rep_var, prog_var, mode_constraint,
	mode_constraint, mode_constraint_info, mode_constraint_info).
:- mode false_var(func(in) = out is det, in, in, out, in, out) is det.

false_var(F, V, !C, !MCI) :-
	mode_constraint_var(F(V), CV, !MCI),
	!:C = !.C ^ not_var(CV).

:- pred ignore(prog_var::in, mode_constraint::in, mode_constraint::out,
	mode_constraint_info::in, mode_constraint_info::out) is det.

ignore(_, !C, !MCI).

:- pred call_in(goal_path::in, prog_var::in,
	mode_constraint::in, mode_constraint::out,
	mode_constraint_info::in, mode_constraint_info::out) is det.

call_in(Path, Var, !C, !MCI) :-
	mode_constraint_var(Var `at` Path, VarGP, !MCI),
	mode_constraint_var(out(Var), VarOut, !MCI),
	!:C = !.C ^ not_var(VarGP) ^ var(VarOut).

:- pred call_out(goal_path::in, prog_var::in,
	mode_constraint::in, mode_constraint::out,
	mode_constraint_info::in, mode_constraint_info::out) is det.

call_out(Path, Var, C0, C, !MCI) :-
	mode_constraint_var(Var `at` Path, VarGP, !MCI),
	C1 = C0 ^ var(VarGP),
	( C1 \= zero ->
		C = C1
	;
		C = C0
	).

:- type constrain_var == pred(prog_var, mode_constraint, mode_constraint,
	mode_constraint_info, mode_constraint_info).
:- inst constrain_var = (pred(in, in, out, in, out) is det).

:- pred mode_constraints__process_inst(module_info::in, inst_graph::in,
	constrain_var::in(constrain_var), constrain_var::in(constrain_var),
	bool::in, (inst)::in, set(prog_var)::in, prog_var::in,
	mode_constraint::in, mode_constraint::out,
	mode_decl_info::in, mode_decl_info::out) is det.

mode_constraints__process_inst(ModuleInfo, InstGraph, Free, Bound, DoHO, Inst,
		Seen, Var, !Constraint, !MDI) :-
	( Var `set__member` Seen ->
		true
	;
		( Inst = defined_inst(InstName) ->
			inst_lookup(ModuleInfo, InstName, Inst1),
			mode_constraints__process_inst(ModuleInfo, InstGraph,
				Free, Bound, DoHO, Inst1, Seen, Var,
				!Constraint, !MDI)
		;
			mode_constraints__do_process_inst(ModuleInfo,
				InstGraph, Free, Bound, DoHO, Inst,
				Seen, Var, !Constraint, !MDI)
		)
	).

:- pred mode_constraints__do_process_inst(module_info::in, inst_graph::in,
	constrain_var::in(constrain_var), constrain_var::in(constrain_var),
	bool::in, (inst)::in, set(prog_var)::in, prog_var::in,
	mode_constraint::in, mode_constraint::out,
	mode_decl_info::in, mode_decl_info::out) is det.

mode_constraints__do_process_inst(ModuleInfo, InstGraph, Free, Bound, DoHO,
		Inst, Seen, Var, !Constraint, !MDI) :-
	update_mc_info((pred(C::out, S0::in, S::out) is det :-
		(
			( Inst = any(_)
			; Inst = bound(_, _)
			; Inst = ground(_, _)
			)
		->
			Bound(Var, !.Constraint, C, S0, S)
		;
			( Inst = free ; Inst = free(_) )
		->
			Free(Var, !.Constraint, C, S0, S)
		;
			C = !.Constraint,
			S = S0
		)), !:Constraint, !MDI),

	map__lookup(InstGraph, Var, node(Functors, _)),
	map__foldl2(
		(pred(ConsId::in, Vs::in, C0::in, C::out, S0::in, S::out)
			is det :-
		( Inst = bound(_, BIs) ->
			( cons_id_in_bound_insts(ConsId, BIs, Insts) ->
				assoc_list__from_corresponding_lists(Vs,
					Insts, VarInsts),
				list__foldl2((pred((V - I)::in, C1::in, C2::out,
						T0::in, T::out) is det :-
					mode_constraints__process_inst(
						ModuleInfo, InstGraph,
						Free, Bound, DoHO, I,
						Seen `set__insert` Var,
						V, C1, C2, T0, T)
					), VarInsts, C0, C, S0, S)
			;
				C = C0,
				S = S0
			)
		;
			list__foldl2(mode_constraints__process_inst(
				ModuleInfo, InstGraph, Free, Bound, DoHO, Inst,
				Seen `set__insert` Var), Vs, C0, C, S0, S)
		)), Functors, !Constraint, !MDI),

	(
		DoHO = yes,
		Inst = ground(_, higher_order(pred_inst_info(_, ArgModes, _)))
	->
		HoModes0 = !.MDI ^ ho_modes,
		update_mc_info(get_prog_var_level(Var), VarLevel, !MDI),
		multi_map__set(HoModes0, VarLevel, ArgModes, HoModes),
		!:MDI = !.MDI ^ ho_modes := HoModes
	;
		true
	).

:- pred mode_constraints__process_clauses_info(module_info::in,
	list(pred_id)::in, clauses_info::in, clauses_info::out, inst_graph::in,
	ho_modes::in, mode_constraint::in, mode_constraint::out,
	mode_constraint_info::in, mode_constraint_info::out, io__state::di,
	io__state::uo) is det.

mode_constraints__process_clauses_info(ModuleInfo, SCC, !ClausesInfo,
		InstGraph, HOModes0, !Constraint, !ConstraintInfo, !IO) :-
	clauses_info_varset(!.ClausesInfo, VarSet0),
	globals__io_lookup_bool_option(very_verbose, VeryVerbose, !IO),
	( VeryVerbose = yes ->
		inst_graph__dump(InstGraph, VarSet0, !IO)
	;
		true
	),

	clauses_info_headvars(!.ClausesInfo, HeadVars),
	map__foldl2(input_output_constraints(HeadVars, InstGraph),
		InstGraph, !Constraint, !ConstraintInfo),

	clauses_info_clauses(!.ClausesInfo, Clauses),
	list__map(pred(clause(_, Goal, _, _)::in, Goal::out) is det, Clauses,
		Goals),
	DisjGoal = disj(Goals),
	EmptyGoalPath = [],
	AtomicGoals0 = set__init,
	Info0 = goal_constraints_info(ModuleInfo, SCC, InstGraph, HeadVars,
		VarSet0, AtomicGoals0, !.ConstraintInfo, HOModes0,
		map__init),
	NonLocals = set__list_to_set(HeadVars),
	GoalVars = set__sorted_list_to_set(map__sorted_keys(InstGraph)),

	goal_constraints_2(EmptyGoalPath, NonLocals, GoalVars, _CanSucceed,
		DisjGoal, _, !Constraint, Info0, Info1),

	% DMO justify this or eliminate it
	% constrict_to_vars(HeadVars, GoalVars, [], !Constraint,
	% 	Info1, Info2),
	Info2 = Info1,

	% robdd_to_dot(!.Constraint, Info2 ^ prog_varset,
	% 	Info2 ^ mc_info, "before_higher_order.dot, !IO"),
	% io__flush_output(!IO),

	higher_order_call_constraints(!Constraint, Info2, Info),

	% robdd_to_dot(!.Constraint, Info ^ prog_varset,
	% 	Info ^ mc_info, "after_higher_order.dot", !IO),
	% io__flush_output(!IO),

	clauses_info_set_varset(Info ^ prog_varset, !ClausesInfo),
	!:ConstraintInfo = Info ^ mc_info.

	% 1.2.1 Input output constraints.
	% These constraints relate the relationships between the above
	% variables and relationships of boundedness on input and output.
:- pred input_output_constraints(list(prog_var)::in, inst_graph::in,
	prog_var::in, inst_graph__node::in,
	mode_constraint::in, mode_constraint::out,
	mode_constraint_info::in, mode_constraint_info::out) is det.

input_output_constraints(HeadVars, InstGraph, V, Node, !Constraint, !MCI) :-
	% For each node V not reachable from an argument node, add
	%	Vin = 0
	inst_graph__top_level_node(InstGraph, V, TopLevel),
	mode_constraint_var(in(V), V_in, !MCI),
	mode_constraint_var(out(V), V_out, !MCI),
	mode_constraint_var(V `at` [], V_, !MCI),
	( TopLevel `list__member` HeadVars ->
		% For each variable V in the instantiation graph, add
		%	(Vout = Vin + V), ~(Vin * V)
		!:Constraint = !.Constraint ^
			io_constraint(V_in, V_out, V_)
	;
		!:Constraint = !.Constraint ^
			not_var(V_in) ^ eq_vars(V_out, V_)
	),

	% For each node V in the graph with child f with child W, add
	%	Wout -> Vout, Win -> Vin
	Node = node(Functors, _),
	map__values(Functors, Children0),
	list__condense(Children0, Children),
	list__foldl2((pred(W::in, Cs0::in, Cs::out, S0::in, S::out) is det :-
			( W = V ->
				Cs = Cs0,
				S = S0
			;
				mode_constraint_var(in(W), W_in, S0, S1),
				mode_constraint_var(out(W), W_out, S1, S),
				Cs = Cs0 ^ imp_vars(W_out, V_out)
					^ imp_vars(W_in, V_in)
			)
		), Children, !Constraint, !MCI).

:- type can_succeed == bool.

:- pred goal_constraints(set(prog_var)::in, can_succeed::out, hlds_goal::in,
	hlds_goal::out, mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

goal_constraints(ParentNonLocals, CanSucceed, GoalExpr0 - GoalInfo0,
		GoalExpr - GoalInfo, !Constraint, !GCInfo) :-
	( goal_is_atomic(GoalExpr0) ->
		add_atomic_goal(GoalPath, !GCInfo)
	;
		true
	),

	goal_info_get_goal_path(GoalInfo0, GoalPath),
	goal_info_get_occurring_vars(GoalInfo0, Vars),

	% Number the vars we want to keep for this goal.
	% XXX
	list__foldl((pred(V::in, S0::in, S::out) is det :-
			get_var(V `at` GoalPath, _, S0, S)
		), set__to_sorted_list(Vars), !GCInfo),
	save_thresh(Threshold, !GCInfo),

	goal_info_get_nonlocals(GoalInfo0, NonLocals),

	InstGraph = !.GCInfo ^ inst_graph,
	NonLocalReachable = solutions_set(inst_graph__reachable_from_list(
		InstGraph, to_sorted_list(NonLocals))),
	LocalVars = Vars `difference` NonLocalReachable,

	( update_mc_info(using_simple_mode_constraints, !GCInfo) ->
		% With simple mode constraints, it is more efficient to do this
		% constraint before doing the goal constraints.
		constrain_local_vars(LocalVars, GoalPath, !Constraint, !GCInfo)
	;
		true
	),

	goal_constraints_2(GoalPath, NonLocals, Vars, CanSucceed, GoalExpr0,
		GoalExpr, !Constraint, !GCInfo),

	( update_mc_info(using_simple_mode_constraints, !GCInfo) ->
		true
	;
		constrain_local_vars(LocalVars, GoalPath, !Constraint, !GCInfo)
	),

	% DEBUGGING CODE
	% ModuleInfo = !GCInfo ^ module_info,
	% ProgVarset = !GCInfo ^ prog_varset,
	% functor(GoalExpr, Functor, _),
	% unsafe_perform_io(io__format("\nFunctor: %s\n", [s(Functor)])),
	% unsafe_perform_io(dump_constraints(ModuleInfo, ProgVarset,
	%	!.Constraint)),

	% DMO document
	% constrict_to_vars(set__to_sorted_list(NonLocals), Vars,
	%	GoalPath, !Constraint, !GCInfo)

	% DEBUGGING CODE
	% size(Constraint1, NumNodes1, Depth1),
	% unsafe_perform_io(io__format(
	% 	"Pre restrict Size: %d, Depth: %d\n",
	% 	[i(NumNodes1), i(Depth1)])),
	% unsafe_perform_io(io__flush_output),

	!:Constraint = restrict_threshold(Threshold, !.Constraint),

	% DEBUGGING CODE
	% size(Constraint2, NumNodes2, Depth2),
	% unsafe_perform_io(io__format(
	% 	"Post restrict Size: %d, Depth: %d\n",
	% 	[i(NumNodes2), i(Depth2)])),
	% unsafe_perform_io(io__flush_output),

	constrain_non_occurring_vars(CanSucceed, ParentNonLocals, Vars,
		GoalPath, !Constraint, !GCInfo),

	% DEBUGGING CODE
	% unsafe_perform_io(dump_constraints(ModuleInfo, ProgVarset,
	% 	!.Constraint)),
	% goal_info_set_mode_constraint(GoalInfo0, !.Constraint, GoalInfo).

	GoalInfo = GoalInfo0.

% :- pragma promise_pure(goal_constraints_2/9).

:- pred goal_constraints_2(goal_path::in, set(prog_var)::in,
	set(prog_var)::in, can_succeed::out, hlds_goal_expr::in,
	hlds_goal_expr::out, mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

goal_constraints_2(GoalPath, NonLocals, _, CanSucceed, conj(Goals0),
		conj(Goals), !Constraint, !GCInfo) :-
	multi_map__init(Usage0),

	Usage = list__foldl(func(G, U0) =
		list__foldl((func(V, U1) = U :-
				multi_map__set(U1, V, goal_path(G), U)),
			set__to_sorted_list(vars(G)), U0),
		Goals0, Usage0),

	known_vars(ensure_normalised(!.Constraint), KnownTrue, KnownFalse),

	% Generate conj constraints for known vars first since these should be
	% more efficient and provide lots of useful information for the subgoal
	% constraints.
	conj_constraints(yes, KnownTrue, KnownFalse, GoalPath, Usage,
		!Constraint, !GCInfo),

	conj_subgoal_constraints(NonLocals, CanSucceed, !Constraint,
		Goals0, Goals, !GCInfo),

	% Generate the rest of the constraints.
	conj_constraints(no, KnownTrue, KnownFalse, GoalPath, Usage,
		!Constraint, !GCInfo).

goal_constraints_2(GoalPath, NonLocals, Vars, CanSucceed, disj(Goals0),
		disj(Goals), !Constraint, !GCInfo) :-
	disj_constraints(NonLocals, CanSucceed, !Constraint, Goals0, Goals,
		[], DisjunctPaths, !GCInfo),
	list__foldl2((pred(V::in, Cons0::in, Cons::out, in, out) is det -->
		get_var(V `at` GoalPath, Vgp),
		list__foldl2((pred(Path::in, C0::in, C::out, in, out) is det -->
			get_var(V `at` Path, VPath),
			{ C = C0 ^ eq_vars(Vgp, VPath) }
		), DisjunctPaths, Cons0, Cons)
	), set__to_sorted_list(Vars), !Constraint, !GCInfo).

goal_constraints_2(GoalPath, _NonLocals, _, CanSucceed, GoalExpr0, GoalExpr,
		!Constraint, !GCInfo) :-
	GoalExpr0 = unify(Var, RHS0, _, _, _),
	unify_constraints(Var, GoalPath, RHS0, RHS, !Constraint, !GCInfo),
	GoalExpr = GoalExpr0 ^ unify_rhs := RHS,
	CanSucceed = yes. 	% XXX Can we be more precise here?

goal_constraints_2(GoalPath, _NonLocals, _, CanSucceed, GoalExpr, GoalExpr,
		!Constraint, !GCInfo) :-
	GoalExpr = call(PredId, _, Args, _, _, _),
	SCC = !.GCInfo ^ scc,
	InstGraph = !.GCInfo ^ inst_graph,
	ModuleInfo = !.GCInfo ^ module_info,
	module_info_pred_info(ModuleInfo, PredId, PredInfo),

	CanSucceed = ( pred_can_succeed(PredInfo) -> yes ; no ),

	( PredId `list__member` SCC ->
		% This is a recursive call.
		% XXX we currently assume that all recursive calls are to the
		% same mode of the predicate.
		pred_info_clauses_info(PredInfo, ClausesInfo),
		clauses_info_headvars(ClausesInfo, HeadVars),
		call_constraints(GoalPath, PredId, HeadVars, Args,
			!Constraint, !GCInfo)
	;
		% This is a non-recursive call.
		( pred_has_mode_decl(ModuleInfo, PredId) ->
			% The predicate has mode declarations so use them
			% to obtain the constraints for the call.

			pred_info_procedures(PredInfo, ProcTable),
			map__values(ProcTable, ProcInfos),
			update_md_info((pred(C::out, S0::in, S::out) is det :-
				list__foldl2(
					mode_constraints__process_mode_decl_for_proc(
						ModuleInfo, InstGraph, Args,
						ignore,
						call_in(GoalPath), no,
						false_var(goal_path(GoalPath)),
						call_out(GoalPath), yes
					), ProcInfos, zero, C, S0, S)),
				CallConstraint, !GCInfo)

		;
			% The called predicate is from a lower (i.e. already
			% mode-analysed) SCC, but does not have any mode
			% declarations.
			ArgModes = PredInfo ^ modes,
			PredInstGraph = PredInfo ^ inst_graph_info
				^ interface_inst_graph,
			pred_info_clauses_info(PredInfo, PredClausesInfo),
			clauses_info_headvars(PredClausesInfo, PredHeadVars),
			solutions((pred((V - W)::out) is nondet :-
				inst_graph__corresponding_nodes_from_lists(
					PredInstGraph, InstGraph, PredHeadVars,
					Args, V, W)
				), CorrespondingNodes),
			list__foldl2((pred(ArgMap::in, Cn0::in, Cn::out,
					S0::in, S::out) is det :-
				ArgMap = InArgs - OutArgs,
				list__foldl2((pred((V - W)::in, C0::in, C::out,
					T0::in, T::out) is det :-
					get_var(W `at` GoalPath, Wgp, T0, T1),
					get_var(out(W), Wout, T1, T),
					( map__lookup(InArgs, V, yes) ->
						C = C0 ^ var(Wout)
							^ not_var(Wgp)
					; map__lookup(OutArgs, V, yes) ->
						C = C0 ^ var(Wgp)
					;
						C = C0 ^ not_var(Wgp)
					)
				), CorrespondingNodes, one, Cn1, S0, S),
				Cn = Cn0 + Cn1
			), ArgModes, zero, CallConstraint, !GCInfo)
			% XXX ArgModes is [] for `odd' - why?
		),
		!:Constraint = !.Constraint * CallConstraint
	).

goal_constraints_2(GoalPath, _NonLocals, _Vars, CanSucceed, GoalExpr, GoalExpr,
		!Constraint, !GCInfo) :-
	GoalExpr = generic_call(GenericCall, Args, _Modes, _Det),
	% Note: `_Modes' is invalid for higher-order calls at this point.
	(
		GenericCall = higher_order(Var, _, _, _),
		generic_call_constrain_var(Var, GoalPath, !Constraint,
			!GCInfo),

		% Record that the argument vars need to be constrained
		% once we know the higher order mode of the Var we are calling.
		HoCalls0 = !.GCInfo ^ ho_calls,
		update_mc_info(get_prog_var_level(Var), VarLevel, !GCInfo),
		multi_map__set(HoCalls0, VarLevel, GoalPath - Args, HoCalls),
		!:GCInfo = !.GCInfo ^ ho_calls := HoCalls,

		CanSucceed = yes % XXX should check this
	;
		GenericCall = class_method(Var, _, _, _),
		generic_call_constrain_var(Var, GoalPath, !Constraint,
			!GCInfo),
		error("mode_constraints.m: class_method call in clause")
	;
		GenericCall = unsafe_cast,
		error("mode_constraints.m: unsafe_cast call NYI")
	;
		GenericCall = aditi_builtin(_, _),
		error("mode_constraints.m: aditi_builtin call NYI")
	).

goal_constraints_2(_,_,_,_,switch(_,_,_),_,_,_,_,_) :-
	error("mode_constraints.goal_constraints_2: switch (should be disj)").

goal_constraints_2(GoalPath, NonLocals, Vars, CanSucceed,
		not(Goal0), not(Goal), !Constraint, !GCInfo) :-
	goal_constraints(NonLocals, _, Goal0, Goal, !Constraint, !GCInfo),

	CanSucceed = yes,

	list__foldl2((pred(V::in, C0::in, C::out, in, out) is det -->
			get_var(V `at` GoalPath, Vgp),
			get_var(V `at` goal_path(Goal), Vneg),
			{ C = C0 ^ eq_vars(Vgp, Vneg) }
		), set__to_sorted_list(Vars), !Constraint, !GCInfo),

	% Make sure the negation doesn't bind any nonlocal variables.
	negation_constraints(GoalPath, NonLocals, !Constraint, !GCInfo).

goal_constraints_2(GoalPath, NonLocals, Vars, CanSucceed, some(A, B, Goal0),
		some(A, B, Goal), !Constraint, !GCInfo) :-
	goal_constraints(NonLocals, CanSucceed, Goal0, Goal, !Constraint,
		!GCInfo),

	list__foldl2((pred(V::in, C0::in, C::out, in, out) is det -->
			get_var(V `at` GoalPath, Vgp),
			get_var(V `at` goal_path(Goal), Vexist),
			{ C = C0 ^ eq_vars(Vgp, Vexist) }
		), set__to_sorted_list(Vars), !Constraint, !GCInfo).

goal_constraints_2(GoalPath, NonLocals, Vars, CanSucceed,
		if_then_else(IteNonLocals, Cond0, Then0, Else0),
		if_then_else(IteNonLocals, Cond, Then, Else),
		!Constraint, !GCInfo) :-

	% Make sure that the condition doesn't bind any variables that are
	% non-local to the if-then-else.
	negation_constraints(goal_path(Cond0), NonLocals,
		!Constraint, !GCInfo),

	goal_constraints(NonLocals, CanSucceedC, Cond0, Cond, !Constraint,
		!GCInfo),
	goal_constraints(NonLocals, CanSucceedT, Then0, Then, !Constraint,
		!GCInfo),
	goal_constraints(NonLocals, CanSucceedE, Else0, Else, !Constraint,
		!GCInfo),

	CanSucceed = (CanSucceedC `and` CanSucceedT) `or` CanSucceedE,

	InstGraph = !.GCInfo ^ inst_graph,
	NonLocalReachable = solutions(inst_graph__reachable_from_list(
		InstGraph, to_sorted_list(NonLocals))),

	% Make sure variables have the same bindings in both the then and else
	% branches.
	list__foldl2((pred(V::in, C0::in, C::out, S0::in, S::out) is det :-
			get_var(V `at` GoalPath, Vgp, S0, S1),
			get_var(V `at` goal_path(Then0), Vthen, S1, S2),
			get_var(V `at` goal_path(Else0), Velse, S2, S),
			C = C0 ^ eq_vars(Vgp, Vthen) ^ eq_vars(Vgp, Velse)
		), NonLocalReachable, !Constraint, !GCInfo),

	% Make sure variables are bound in at most one of the cond and then
	% goals.
	list__foldl2((pred(V::in, C0::in, C::out, S0::in, S::out) is det :-
			get_var(V `at` goal_path(Cond0), Vcond, S0, S1),
			get_var(V `at` goal_path(Then0), Vthen, S1, S),
			C = C0 ^ not_both(Vcond, Vthen)
		), set__to_sorted_list(vars(Cond0) `set__union` vars(Then0)),
		!Constraint, !GCInfo),

	% Local variables bound in cond, then or else should be treated as
	% though they are bound in the ite as well. (Although all such
	% variables will be local to the ite, the _out constraints still need to
	% be satisfied.)
	Locals = to_sorted_list(
		Vars `difference` sorted_list_to_set(NonLocalReachable)),
	list__foldl2((pred(V::in, C0::in, C::out, S0::in, S::out) is det :-
			get_var(V `at` goal_path(Cond), Vcond, S0, S1),
			get_var(V `at` goal_path(Then), Vthen, S1, S2),
			get_var(V `at` goal_path(Else), Velse, S2, S3),
			get_var(V `at` GoalPath, Vgp, S3, S),
			Vs = list_to_set([Vcond, Vthen, Velse]),
			C = C0 ^ disj_vars_eq(Vs, Vgp)
		), Locals, !Constraint, !GCInfo).

goal_constraints_2(_,_,_,_,foreign_proc(_,_,_,_,_,_),_,_,_,_,_) :-
	error("mode_constraints.goal_constraints_2: foreign_proc NYI").
goal_constraints_2(_,_,_,_,par_conj(_),_,_,_,_,_) :-
	error("mode_constraints.goal_constraints_2: par_conj NYI").
goal_constraints_2(_,_,_,_,shorthand(_),_,_,_,_,_) :-
	error("mode_constraints.goal_constraints_2: shorthand").

	% Constraints for the conjunction. If UseKnownVars = yes, generate
	% constraints only for the vars in KnownVars, otherwise generate
	% constraints only for the vars _not_ is KnownVars.
:- pred conj_constraints(bool::in, mode_constraint_vars::in,
	mode_constraint_vars::in, goal_path::in,
	multi_map(prog_var, goal_path)::in,
	mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

conj_constraints(UseKnownVars, KnownTrue, KnownFalse, GoalPath, UsageMap,
		!Constraint, !GCInfo) :-
	UsageList = map__to_assoc_list(UsageMap), % XXX needed for deep profiler
	list__foldl2(conj_constraints_process_var(UseKnownVars,
		KnownTrue, KnownFalse, GoalPath),
		UsageList, !Constraint, !GCInfo).

:- pred conj_constraints_process_var(bool::in, mode_constraint_vars::in,
	mode_constraint_vars::in, goal_path::in,
	pair(prog_var, list(goal_path))::in,
	mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

conj_constraints_process_var(UseKnownVars, KnownTrue, KnownFalse, GoalPath,
		Var - Paths, !Constraint, !GCInfo) :-
	list__map_foldl((pred(P::in, CV::out, in, out) is det -->
		get_var(Var `at` P, CV)
	), Paths, ConstraintVars, !GCInfo),
	get_var(Var `at` GoalPath, VConj, !GCInfo),
	ConstraintVarSet = list_to_set(ConstraintVars),

	% If UseKnownVars = yes we want to only generate the constraints
	% which are 2-sat. If UseKnownVars = no, we generate the other
	% constraints.
	( KnownFalse `contains` VConj ->
		( UseKnownVars = yes ->
			!:Constraint = !.Constraint ^
				conj_not_vars(ConstraintVarSet)
		;
			true
		)
	; KnownTrue `contains` VConj ->
		( ConstraintVars = [] ->
			!:Constraint = zero
		; ConstraintVars = [ConstraintVar] ->
			( UseKnownVars = yes ->
				!:Constraint = !.Constraint
					^ var(ConstraintVar)
			;
				true
			)
		; ConstraintVars = [ConstraintVar1, ConstraintVar2] ->
			( UseKnownVars = yes ->
				!:Constraint = !.Constraint
					^ neq_vars(ConstraintVar1,
						ConstraintVar2)
			;
				true
			)
		;
			( UseKnownVars = yes ->
				true
			;
				!:Constraint = !.Constraint
					^ at_most_one_of(ConstraintVarSet)
					^ disj_vars_eq(ConstraintVarSet, VConj)
			)
		)
	;
		( UseKnownVars = yes ->
			true
		;
			!:Constraint = !.Constraint
				^ at_most_one_of(ConstraintVarSet)
				^ disj_vars_eq(ConstraintVarSet, VConj)
		)
	).

:- pred conj_subgoal_constraints(set(prog_var)::in, can_succeed::out,
	mode_constraint::in, mode_constraint::out,
	hlds_goals::in, hlds_goals::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

conj_subgoal_constraints(_, yes, !Constraint, [], [], !GCInfo).
conj_subgoal_constraints(NonLocals, CanSucceed, !Constraint,
		[Goal0 | Goals0], [Goal | Goals], !GCInfo) :-
	goal_constraints(NonLocals, CanSucceed0, Goal0, Goal, !Constraint,
		!GCInfo),
	conj_subgoal_constraints(NonLocals, CanSucceed1, !Constraint,
		Goals0, Goals, !GCInfo),
	CanSucceed = CanSucceed0 `bool__and` CanSucceed1.

:- pred disj_constraints(set(prog_var)::in, can_succeed::out,
	mode_constraint::in, mode_constraint::out,
	hlds_goals::in, hlds_goals::out,
	list(goal_path)::in, list(goal_path)::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

disj_constraints(_, no, !Constraint, [], [], Paths, Paths, !GCInfo).
disj_constraints(NonLocals, CanSucceed, !Constraint,
		[Goal0 | Goals0], [Goal | Goals], Paths0, Paths, !GCInfo) :-
	goal_constraints(NonLocals, CanSucceed0, Goal0, Goal,
		!Constraint, !GCInfo),
	disj_constraints(NonLocals, CanSucceed1, !Constraint,
		Goals0, Goals, [goal_path(Goal) | Paths0], Paths, !GCInfo),
	CanSucceed = CanSucceed0 `bool__or` CanSucceed1.

	% See 1.2.3 The literals themselves
:- pred unify_constraints(prog_var::in, goal_path::in, unify_rhs::in,
	unify_rhs::out, mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

unify_constraints(A, GoalPath, RHS, RHS, !Constraint, !GCInfo) :-
	RHS = var(B),
	InstGraph = !.GCInfo ^ inst_graph,
	Generator =
		(pred((V - W)::out) is multi :-
			inst_graph__corresponding_nodes(InstGraph, A, B, V, W)
		),
	Accumulator =
		(pred((V - W)::in, C0::in, C::out, S0::in, S::out) is det :-
			get_var(out(V), Vout, S0, S1),
			get_var(out(W), Wout, S1, S2),
			get_var(V `at` GoalPath, Vgp, S2, S3),
			get_var(W `at` GoalPath, Wgp, S3, S),
			C = C0 ^ eq_vars(Vout, Wout) ^ not_both(Vgp, Wgp)
		),
	aggregate2(Generator, Accumulator, !Constraint, !GCInfo),
	get_var(out(A), Aout, !GCInfo),
	!:Constraint = !.Constraint ^ var(Aout),

	HoModes0 = !.GCInfo ^ ho_modes,
	update_mc_info(share_ho_modes(A, B, HoModes0), HoModes, !GCInfo),
	!:GCInfo = !.GCInfo ^ ho_modes := HoModes.

unify_constraints(A, GoalPath, RHS, RHS, !Constraint, !GCInfo) :-
	RHS = functor(_ConsId, _IsExistConstruct, Args),
	get_var(out(A), Aout, !GCInfo),
	!:Constraint = !.Constraint ^ var(Aout),
	( update_mc_info(using_simple_mode_constraints, !GCInfo) ->
		% In the simple system a var-functor unification must be either
		% a construction or a deconstruction.
		list__map_foldl(
			( pred(ProgVar::in, RepVar::out, S0::in, S::out)
					is det :-
				get_var(ProgVar `at` GoalPath, RepVar, S0, S)
			), Args, ArgsGp0, !GCInfo),
		ArgsGp = list_to_set(ArgsGp0),
		get_var(A `at` GoalPath, Agp, !GCInfo),
		( remove_least(ArgsGp, Arg1gp, ArgsGp1) ->
			!:Constraint = !.Constraint
				^ neq_vars(Arg1gp, Agp)
				^ fold(eq_vars(Arg1gp), ArgsGp1)
		;
			!:Constraint = !.Constraint
		)
		%{ Constraint = Constraint1 * 
		%	( one ^ var(Agp) ^ conj_not_vars(ArgsGp)
		%	+ one ^ not_var(Agp) ^ conj_vars(ArgsGp)
		%	) }
	;
		InstGraph = !.GCInfo ^ inst_graph,
		inst_graph__foldl_reachable_from_list2(
			( pred(V::in, C0::in, C::out, S0::in, S::out) is det :-
				( V \= A ->
					get_var(V `at` GoalPath, Vgp, S0, S),
					C = C0 ^ not_var(Vgp)
				;
					C = C0,
					S = S0
				)
			), InstGraph, Args, !Constraint, !GCInfo)
	).

unify_constraints(Var, GoalPath, RHS0, RHS, !Constraint, !GCInfo) :-
	RHS0 = lambda_goal(_, _, _, _, NonLocals, LambdaVars, Modes, _, Goal0),
	InstGraph = !.GCInfo ^ inst_graph,

	% Variable Var is made ground by this goal.
	inst_graph__foldl_reachable2(
		( pred(V::in, Cn0::in, Cn::out, in, out) is det -->
			get_var(V `at` GoalPath, Vgp),
			{ Cn = Cn0 ^ var(Vgp) }
		), InstGraph, Var, !Constraint, !GCInfo),

	% The lambda NonLocals are not bound by this goal.
	inst_graph__foldl_reachable_from_list2(
		( pred(V::in, Cn0::in, Cn::out, in, out) is det -->
			get_var(V `at` GoalPath, Vgp),
			{ Cn = Cn0 ^ not_var(Vgp) }
		), InstGraph, NonLocals, !Constraint, !GCInfo),

	% Record the higher-order mode of this lambda goal.
	HoModes0 = !.GCInfo ^ ho_modes,
	update_mc_info(get_prog_var_level(Var), VarLevel, !GCInfo),
	multi_map__set(HoModes0, VarLevel, Modes, HoModes),
	!:GCInfo = !.GCInfo ^ ho_modes := HoModes,

	% Analyse the lambda goal.
	update_mc_info(enter_lambda_goal(GoalPath), !GCInfo),

	% XXX rather than adding `in' modes for lambda nonlocals we
	% should just place a constraint `V_prod = 0' for all nodes
	% reachable from these variables in the lambda goal.
	ArgModes = list__duplicate(length(NonLocals), in_mode) ++ Modes,
	LambdaHeadVars = NonLocals ++ LambdaVars,
	ModuleInfo = !.GCInfo ^ module_info,
	update_md_info(mode_constraints__process_mode_decl(ModuleInfo,
		InstGraph, LambdaHeadVars, false_var(initial),
		true_var(initial), yes, false_var(final), true_var(final), no,
		ArgModes, zero), DeclConstraint, !GCInfo),
	!:Constraint = !.Constraint * DeclConstraint,

	% XXX This will put constraints on variables that do not occur in
	% the lambda goal. These constraints will be removed at the next
	% restrict, but it would be more efficient not to put them in in the
	% first place.

	% DEBUGGING CODE
	% size(!.Constraint, NumNodes3, Depth3, _),
	% unsafe_perform_io(io__format(
	% 	"Pre lambda Size: %d, Depth: %d\n",
	% 	[i(NumNodes3), i(Depth3)])),

	update_mc_info((pred(C::out, S0::in, S::out) is det :-
			map__foldl2(
				input_output_constraints(LambdaHeadVars,
					InstGraph),
				InstGraph, !.Constraint, C, S0, S)
		), !:Constraint, !GCInfo),

	% DEBUGGING CODE
	% size(!.Constraint, NumNodes5, Depth5, _),
	% unsafe_perform_io(io__format(
	% 	"lambda io_constraints Size: %d, Depth: %d\n",
	% 	[i(NumNodes5), i(Depth5)])),

	goal_constraints(set__init, _CanSucceed, Goal0, Goal, !Constraint,
		!GCInfo),

	% DEBUGGING CODE
	% size(Constraint, NumNodes, Depth),
	% unsafe_perform_io(io__format(
	% 	"post lambda Size: %d, Depth: %d\n",
	% 	[i(NumNodes), i(Depth)])),

	update_mc_info(leave_lambda_goal, !GCInfo),
	RHS = RHS0 ^ rhs_lambda_goal := Goal.

:- pred call_constraints(goal_path::in, pred_id::in, list(prog_var)::in,
	list(prog_var)::in, mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

call_constraints(GoalPath, PredId, HeadVars, Args, !Constraint, !GCInfo) :-
	InstGraph = !.GCInfo ^ inst_graph,
	Generator =
		(pred((V - W)::out) is nondet :-
			corresponding_members(HeadVars, Args, X, Y),
			inst_graph__corresponding_nodes(InstGraph, X, Y, V, W)
		),
	Accumulator = 
		(pred((V - W)::in, C0::in, C::out, S0::in, S::out) is det :-
			get_var(PredId, V `at` [], V_, S0, S1),
			get_var(W `at` GoalPath, Wgp, S1, S2),
			get_var(PredId, in(V), Vin, S2, S3),
			get_var(out(W), Wout, S3, S),
			C = C0 ^ eq_vars(V_, Wgp) ^ imp_vars(Vin, Wout)
		),
	aggregate2(Generator, Accumulator, !Constraint, !GCInfo).

:- pred higher_order_call_constraints(mode_constraint::in,
	mode_constraint::out, goal_constraints_info::in,
	goal_constraints_info::out) is det.

higher_order_call_constraints(Constraint0, Constraint, !GCInfo) :-
	HoModes = !.GCInfo ^ ho_modes,
	HoCalls = !.GCInfo ^ ho_calls,
	ModuleInfo = !.GCInfo ^ module_info,
	InstGraph = !.GCInfo ^ inst_graph,
	update_md_info(
	    (pred(Constraint1::out, in, out) is det -->
		map__foldl2(
		    (pred(HoVarLevel::in, Calls::in, Cons0::in, Cons::out,
			    in, out) is det -->
			update_mc_info(set_level_from_var(HoVarLevel)),
			( { map__search(HoModes, HoVarLevel, ArgModesList) } ->
			    list__foldl2(
				(pred((GoalPath - Args)::in, C0::in, C::out,
					in, out) is det -->
				    list__foldl2(
					mode_constraints__process_mode_decl(
					    ModuleInfo, InstGraph, Args, ignore,
					    call_in(GoalPath), no,
					    false_var(goal_path(GoalPath)),
					    call_out(GoalPath), no
					), ArgModesList, zero, C1),
					{ C = C0 * C1 } ),
				Calls, Cons0, Cons)
			;
			    { Cons = Cons0 }
			)
		    ), HoCalls, Constraint0, Constraint1)),
	    Constraint, !GCInfo).

:- pred negation_constraints(goal_path::in, set(prog_var)::in,
	mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

negation_constraints(GoalPath, NonLocals, !Constraint, !GCInfo) :-
	InstGraph = !.GCInfo ^ inst_graph,
	inst_graph__foldl_reachable_from_list2(
		(pred(V::in, C0::in, C::out, in, out) is det -->
			get_var(V `at` GoalPath, Vgp),
			{ C = C0 ^ not_var(Vgp) }
		), InstGraph, to_sorted_list(NonLocals),
		!Constraint, !GCInfo).

:- pred generic_call_constrain_var(prog_var::in, goal_path::in,
	mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

generic_call_constrain_var(Var, GoalPath, !Constraint, !GCInfo) :-
	InstGraph = !.GCInfo ^ inst_graph,
	inst_graph__foldl_reachable2(
		( pred(V::in, C0::in, C::out, in, out) is det -->
			get_var(out(V), Vout),
			get_var(V `at` GoalPath, Vgp),
			{ C = C0 ^ var(Vout) ^ not_var(Vgp) }
		), InstGraph, Var, !Constraint, !GCInfo).

:- pred constrict_to_vars(list(prog_var)::in, set(prog_var)::in, goal_path::in, 
	mode_constraint::in, mode_constraint::out, goal_constraints_info::in,
	goal_constraints_info::out) is det.

constrict_to_vars(NonLocals, GoalVars, GoalPath, !Constraint, !Info) :-
	!:Constraint = restrict_filter(keep_var(NonLocals, GoalVars, GoalPath,
		!.Info ^ atomic_goals, !.Info ^ inst_graph), !.Info ^ mc_info,
		!.Constraint).

:- pred keep_var(list(prog_var)::in, set(prog_var)::in, goal_path::in,
	set(goal_path)::in, inst_graph::in, rep_var::in) is semidet.

keep_var(_, _, _, AtomicGoals, _, _V `at` GoalPath) :-
	set__member(GoalPath, AtomicGoals).
keep_var(NonLocals, GoalVars, GoalPath, _AtomicGoals, InstGraph, RepVar) :-
	(
		( RepVar = in(V)
		; RepVar = out(V)
		; RepVar = V `at` _
		),
		set__member(V, GoalVars)
	)
  	=>
  	(
		list__member(NonLocal, NonLocals),
		inst_graph__reachable(InstGraph, NonLocal, V),
		\+ (
			RepVar = _ `at` GoalPath1,
			list__remove_suffix(GoalPath1, GoalPath, [_|_])
		)
	).

:- type sccs == list(list(pred_id)).

:- pred get_predicate_sccs(module_info::in, sccs::out) is det.

get_predicate_sccs(ModuleInfo, SCCs) :-
	% Obtain the SCCs for the module.
	dependency_graph__build_pred_dependency_graph(ModuleInfo, no, DepInfo),
	hlds_dependency_info_get_dependency_ordering(DepInfo, SCCs0),

	% Remove predicates that have mode declarations and place them in
	% their own ``SCC'' at the end of the list.
	% Predicates with mode declarations do not need to be processed with
	% the rest of their SCC since the mode declaration can be used in any
	% calls to them.  Such predicates should be processed last to take
	% advantage of mode info inferred from other predicates.
	extract_mode_decl_preds(ModuleInfo, [], SCCs0, SCCs1),

	% We add imported preds to the end of the SCC list, one SCC per pred.
	% This allows a constraint to be created for each imported pred
	% based on its mode declarations.
	add_imported_preds(ModuleInfo, SCCs1, SCCs).

:- pred extract_mode_decl_preds(module_info::in, sccs::in, sccs::in, sccs::out)
	is det.

extract_mode_decl_preds(_ModuleInfo, DeclaredPreds, [], DeclaredPreds).
extract_mode_decl_preds(ModuleInfo, DeclaredPreds0, [SCC0 | SCCs0], SCCs) :-
	list__filter(pred_has_mode_decl(ModuleInfo), SCC0, Declared, SCC),
	( Declared = [] ->
		DeclaredPreds = DeclaredPreds0
	;
		list__foldl((pred(Pred::in, Preds0::in, Preds::out) is det :-
				Preds = [[Pred] | Preds0]
			), Declared, DeclaredPreds0, DeclaredPreds)
	),
	extract_mode_decl_preds(ModuleInfo, DeclaredPreds, SCCs0, SCCs1),
	( SCC = [] ->
		SCCs = SCCs1
	;
		SCCs = [SCC | SCCs1]
	).

:- pred pred_has_mode_decl(module_info::in, pred_id::in) is semidet.

pred_has_mode_decl(ModuleInfo, PredId) :-
	module_info_pred_info(ModuleInfo, PredId, PredInfo),
	\+ pred_info_infer_modes(PredInfo).

:- pred add_imported_preds(module_info::in, sccs::in, sccs::out) is det.

add_imported_preds(ModuleInfo, SCCs0, SCCs) :-
	module_info_predids(ModuleInfo, PredIds),
	list__filter_map((pred(PredId::in, [PredId]::out) is semidet :-
			module_info_pred_info(ModuleInfo, PredId, PredInfo),
			pred_info_is_imported(PredInfo)
		), PredIds, ImportedPredIds),
	SCCs = SCCs0 ++ ImportedPredIds.

:- pred cons_id_in_bound_insts(cons_id::in, list(bound_inst)::in,
		list(inst)::out) is semidet.

cons_id_in_bound_insts(ConsId, [functor(ConsId0, Insts0) | BIs], Insts) :-
	( equivalent_cons_ids(ConsId0, ConsId) ->
		Insts = Insts0
	;
		cons_id_in_bound_insts(ConsId, BIs, Insts)
	).

:- pred equivalent_cons_ids(cons_id, cons_id).
:- mode equivalent_cons_ids(in, in) is semidet.

equivalent_cons_ids(ConsIdA, ConsIdB) :-
	(
		ConsIdA = cons(NameA, ArityA),
		ConsIdB = cons(NameB, ArityB)
	->
		ArityA = ArityB,
		equivalent_sym_names(NameA, NameB)
	;
		ConsIdA = ConsIdB
	).

:- pred equivalent_sym_names(sym_name, sym_name).
:- mode equivalent_sym_names(in, in) is semidet.

equivalent_sym_names(unqualified(S), unqualified(S)).
equivalent_sym_names(qualified(_, S), unqualified(S)).
equivalent_sym_names(unqualified(S), qualified(_, S)).
equivalent_sym_names(qualified(QualA, S), qualified(QualB, S)) :-
	equivalent_sym_names(QualA, QualB).

%------------------------------------------------------------------------%

% For local variables, V_ must be equivalent to Vgp.

:- pred constrain_local_vars(set(prog_var)::in, goal_path::in,
	mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

constrain_local_vars(Locals, GoalPath, !Constraint, !GCInfo) :-
	list__foldl2((pred(V::in, C0::in, C::out, in, out) is det -->
		get_var(V `at` GoalPath, Vgp),
		get_var(out(V), Vout),
		( update_mc_info(using_simple_mode_constraints) ->
			% For simple_mode_constraints, local variables must all be
			% bound within the goal.
			{ C = C0 ^ var(Vgp) ^ var(Vout) }
		;
			{ C = C0 ^ eq_vars(Vgp, Vout) }
		)
	), to_sorted_list(Locals), !Constraint, !GCInfo).

:- pred constrain_non_occurring_vars(can_succeed::in, set(prog_var)::in,
	set(prog_var)::in, goal_path::in,
	mode_constraint::in, mode_constraint::out,
	goal_constraints_info::in, goal_constraints_info::out) is det.

constrain_non_occurring_vars(no, _, _, _, !Constraint, !GCInfo).
constrain_non_occurring_vars(yes, ParentNonLocals, OccurringVars, GoalPath,
		!Constraint, !GCInfo) :-
	InstGraph = !.GCInfo ^ inst_graph,
	Generator =
		(pred(V::out) is nondet :-
			set__member(U, ParentNonLocals),
			inst_graph__reachable(InstGraph, U, V),
			\+ set__member(V, OccurringVars)
		),
	Accumulator = 
		(pred(V::in, Vs0::in, Vs::out, in, out) is det -->
			get_var(V `at` GoalPath, VGP),
			{ Vs = Vs0 `insert` VGP }
		),
	aggregate2(Generator, Accumulator, empty_vars_set, NonOccurringVars,
		!GCInfo),
	!:Constraint = !.Constraint ^ conj_not_vars(NonOccurringVars).

%	aggregate2((pred(V::out) is nondet :-
%		set__member(U, ParentNonLocals),
%		inst_graph__reachable(InstGraph, U, V),
%		\+ set__member(V, OccurringVars)
%	    ), (pred(V::in, C0::in, C::out, in, out) is det -->
%	    	get_var(V `at` GoalPath, VGP),
%	    	{ C = C0 ^ not_var(VGP) }
%	    ), Constraint0, Constraint).

%------------------------------------------------------------------------%

:- pred share_ho_modes(prog_var::in, prog_var::in, ho_modes::in, ho_modes::out,
	mode_constraint_info::in, mode_constraint_info::out) is det.

share_ho_modes(VarA, VarB, HoModes0, HoModes, !MCI) :-
	get_prog_var_level(VarA, A, !MCI),
	get_prog_var_level(VarB, B, !MCI),
	( map__search(HoModes0, A, AModes) ->
		( map__search(HoModes0, B, BModes) ->
			Modes = list__sort_and_remove_dups(
					AModes `list__append` BModes),
			map__det_update(HoModes0, A, Modes, HoModes1),
			map__det_update(HoModes1, B, Modes, HoModes)
		;
			map__det_insert(HoModes0, B, AModes, HoModes)
		)
	; map__search(HoModes0, B, BModes) ->
		map__det_insert(HoModes0, A, BModes, HoModes)
	;
		HoModes = HoModes0
	).

%------------------------------------------------------------------------%
%------------------------------------------------------------------------%

:- pred arg_modes_map(list(prog_var)::in, inst_graph::in, mode_constraint::in,
	mode_constraint_info::in, arg_modes_map::out) is nondet.

arg_modes_map(HeadVars, InstGraph, Constraint0, Info0, ArgModes) :-
	solutions(inst_graph__reachable_from_list(InstGraph, HeadVars), Vars),
	list__map_foldl((pred(PV::in, (MV - in(PV))::out, in, out) is det -->
		mode_constraint_var(in(PV), MV)), Vars, InVars, Info0, Info1),
	list__map_foldl((pred(PV::in, (MV - out(PV))::out, in, out) is det -->
		mode_constraint_var(out(PV), MV)), Vars, OutVars, Info0, Info1),
	MVars = list__sort_and_remove_dups(InVars `list__append` OutVars),
	MVarKeys = assoc_list__keys(MVars),
	Constraint = restrict_filter(
		(pred(V::in) is semidet :- list__member(V, MVarKeys)),
		ensure_normalised(Constraint0)),
	ArgModes0 = map__init - map__init,
	list__foldl2(arg_modes_map_2, MVars, Constraint, _, 
		ArgModes0, ArgModes).

:- pred arg_modes_map_2(pair(mode_constraint_var, rep_var)::in,
	mode_constraint::in, mode_constraint::out, 
	arg_modes_map::in, arg_modes_map::out) is nondet.

arg_modes_map_2(MV - RV, Constraint0, Constraint, ArgModes0, ArgModes) :-
	(
		Constraint = var_restrict_true(MV, Constraint0),
		Bool = yes
	;
		Constraint = var_restrict_false(MV, Constraint0),
		Bool = no
	),
	Constraint \= zero,
	ArgModes0 = InModes0 - OutModes0,
	(
		RV = in(PV),
		ArgModes = map__det_insert(InModes0, PV, Bool) - OutModes0
	;
		RV = out(PV),
		ArgModes = InModes0 - map__det_insert(OutModes0, PV, Bool)
	).

% :- type labelling == map(mode_constraint_var, bool).
% 
% :- pred labelling(set(mode_constraint_var)::in, mode_constraint::in,
% 		labelling::out) is nondet.
% 
% labelling(Vs, Constraint, Map) :-
% 	labelling(Vs, Constraint, TrueVars, FalseVars),
% 	Map = true_false_sets_to_labelling_map(TrueVars, FalseVars).
% 
% 	% Return a ``fundamental mode'' (i.e. non-implied mode) for the given
% 	% mode constraint. This is calculated by computing a minimal model for
% 	% the initial insts of the head variables of the predicate.
% :- pred fundamental_mode(set(mode_constraint_var)::in, mode_constraint::in,
% 		mode_constraint::out) is nondet.
% 
% fundamental_mode(Vs, Constraint0, Constraint) :-
% 	minimal_model(Vs, Constraint0, TrueVars, FalseVars),
% 
% 	% XXX There's probably a more efficient way to do this.
% 	Constraint = Constraint0 * conj_vars(TrueVars) *
% 			(~disj_vars(FalseVars)).
% 
% :- func true_false_sets_to_labelling_map(set(mode_constraint_var),
% 		set(mode_constraint_var)) = labelling.
% 
% true_false_sets_to_labelling_map(TrueVars, FalseVars) =
% 	list__foldl(func(V, M) = map__det_insert(M, V, no),
% 		set__to_sorted_list(FalseVars),
% 		list__foldl(func(V, M) = map__det_insert(M, V, yes),
% 			set__to_sorted_list(TrueVars), map__init)).
% 
% 	% implied_mode(L0, L1) is true iff mode L0 is implied by mode L1.
% :- pred implied_mode(labelling::in, labelling::in) is semidet.
% 
% implied_mode(L0, L1) :-
% 	all [V] ( map__member(L1, V, yes) => map__lookup(L0, V, yes) ).
% 
% :- pred split_constraint_into_modes(pred_id::in, list(prog_var)::in,
% 	inst_graph::in, mode_constraint::in, list(labelling)::out,
% 	mode_constraint_info::in, mode_constraint_info::out) is det.
% 
% split_constraint_into_modes(PredId, HeadVars, InstGraph, ModeConstraint0,
% 		Labellings) -->
% 	{ solutions(inst_graph__reachable_from_list(InstGraph, HeadVars),
% 		ReachVars) },
% 	list__map_foldl((pred(PV::in, MV::out, in, out) is det -->
% 		mode_constraint_var(in(PV), MV)
% 	), ReachVars, InVars),
% 
% 	get_interesting_vars_for_pred(PredId, InterestingVars),
% 	{ solutions((pred(Labelling::out) is nondet :-
% 		fundamental_mode(set__list_to_set(InVars), ModeConstraint0,
% 			ModeConstraint1),
% 		labelling(InterestingVars, ModeConstraint1, Labelling)
% 	), Labellings) }.

%------------------------------------------------------------------------%
%------------------------------------------------------------------------%

:- func goal_path(hlds_goal) = goal_path.

goal_path(_ - GoalInfo) = GoalPath :-
	goal_info_get_goal_path(GoalInfo, GoalPath).

:- func vars(hlds_goal) = set(prog_var).

vars(_ - GoalInfo) = OccurringVars :-
	goal_info_get_occurring_vars(GoalInfo, OccurringVars).

%------------------------------------------------------------------------%

	% A predicate can succeed if at least one of its procedures
	% can succeed.
:- pred pred_can_succeed(pred_info::in) is semidet.

pred_can_succeed(PredInfo) :-
	pred_info_procedures(PredInfo, ProcTable),
	some [ProcInfo] (
		map__member(ProcTable, _ProcId, ProcInfo),
		proc_can_succeed(ProcInfo)
	).
		
	% A procedure can possibly succeed if it has no declared determinism or
	% it has a declared determinism that allows more than zero solutions.
	% (This is a conservative approximation since we can't use the results
	% of determinism inference -- it hasn't been run yet.)
:- pred proc_can_succeed(proc_info::in) is semidet.

proc_can_succeed(ProcInfo) :-
	proc_info_declared_determinism(ProcInfo, MaybeDet),
	(
		MaybeDet = no
	;
		MaybeDet = yes(Detism),
		determinism_components(Detism, _, SolnCount),
		SolnCount \= at_most_zero
	).

%------------------------------------------------------------------------%

% DEBUGGING CODE
%
% :- impure pred conj_to_dot(mode_constraint::in, prog_varset::in,
% 	mode_constraint_info::in, io__state::di, io__state::uo) is det.
%
% conj_to_dot(MC, VS, CI) -->
% 	robdd_to_dot(MC, VS, CI, string__format("conj%d.dot", [i(conjnum)])).
% 
% :- impure func conjnum = int.
% 
% :- pragma foreign_code("C",
% "
% static MR_Integer conjnum = 0;
% ").
% 
% :- pragma foreign_proc("C",
% 	conjnum = (N::out),
% 	[will_not_call_mercury],
% "
% 	N = conjnum++;
% ").

%------------------------------------------------------------------------%