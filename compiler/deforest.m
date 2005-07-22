%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2005 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% File: deforest.m
% Main author: stayl.
%-----------------------------------------------------------------------------%
%
% Deforestation attempts to remove multiple traversals over data structures,
% and construction followed by immediate deconstruction of data structures.
% It does this by combining the bodies of pairs of called procedures in
% a conjunction where the top-level functor of one of the argument variables
% of the first called procedure is known at the end of some of the branches
% of the body of that procedure, and the second called procedure switches on
% that variable.
%
% The deforestation pass also inlines calls for which the top-level
% goal in the called procedure is a switch and the functor of the
% switched-on variable is known. This allows simplify.m to prune away
% the failing branches.
%
% The constraint propagation pass, which is called from the deforestation
% pass, transforms the code so that goals which could fail are executed as
% early as possible.
%
% For a more detailed description, see Simon Taylor's Honours thesis,
% available from
% <http://www.cs.mu.oz.au/research/mercury/information/papers/stayl_hons.ps.gz>
%
%-----------------------------------------------------------------------------%

:- module transform_hlds__deforest.

:- interface.

:- import_module hlds__hlds_module.

:- import_module io.

:- pred deforestation(module_info::in, module_info::out,
	io::di, io::uo) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds__det_analysis.
:- import_module check_hlds__det_report.
:- import_module check_hlds__inst_match.
:- import_module check_hlds__mode_info.
:- import_module check_hlds__mode_util.
:- import_module check_hlds__modes.
:- import_module check_hlds__purity.
:- import_module check_hlds__simplify.
:- import_module check_hlds__unique_modes.
:- import_module hlds__goal_util.
:- import_module hlds__hlds_data.
:- import_module hlds__hlds_goal.
:- import_module hlds__hlds_out.
:- import_module hlds__hlds_pred.
:- import_module hlds__instmap.
:- import_module hlds__passes_aux.
:- import_module hlds__quantification.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module mdbcomp__prim_data.
:- import_module parse_tree__prog_data.
:- import_module parse_tree__prog_out.
:- import_module parse_tree__prog_util.
:- import_module transform_hlds__dependency_graph.
:- import_module transform_hlds__inlining.
:- import_module transform_hlds__pd_cost.
:- import_module transform_hlds__pd_debug.
:- import_module transform_hlds__pd_info.
:- import_module transform_hlds__pd_term.
:- import_module transform_hlds__pd_util.

:- import_module assoc_list.
:- import_module bool.
:- import_module getopt_io.
:- import_module int.
:- import_module list.
:- import_module map.
:- import_module require.
:- import_module set.
:- import_module std_util.
:- import_module string.
:- import_module term.
:- import_module varset.

deforestation(!ModuleInfo, !IO) :-
	proc_arg_info_init(ProcArgInfo0),
	type_to_univ(ProcArgInfo0, UnivProcArgInfo0),

	% Find out which arguments of each procedure are switched on
	% at the top level or are constructed in a way which is
	% possibly deforestable.
	Task0 = update_module_cookie(deforest__get_branch_vars_proc,
		UnivProcArgInfo0),
	process_all_nonimported_procs(Task0, Task, !ModuleInfo, !IO),
	(
		Task = update_module_cookie(_, UnivProcArgInfo),
		univ_to_type(UnivProcArgInfo, ProcArgInfo1)
	->
		ProcArgInfo = ProcArgInfo1
	;
		error("deforestation: passes_aux stuffed up")
	),

	% We process the module bottom-up to make estimation of the
	% cost improvement of new versions a little more accurate and
	% also to avoid redoing optimizations.
	module_info_ensure_dependency_info(!ModuleInfo),
	module_info_dependency_info(!.ModuleInfo, DepInfo),
	hlds_dependency_info_get_dependency_ordering(DepInfo, DepOrdering),
	list__condense(DepOrdering, DepList),

	pd_info_init(!.ModuleInfo, ProcArgInfo, PDInfo0),
	list__foldl2(deforest__proc, DepList, PDInfo0, PDInfo, !IO),
	pd_info_get_module_info(PDInfo, !:ModuleInfo),
	module_info_clobber_dependency_info(!ModuleInfo),
	pd_info_get_versions(PDInfo, VersionIndex),

	map__keys(VersionIndex, Versions),

	globals__io_lookup_bool_option(constraint_propagation,
		Constraints, !IO),
	(
		Constraints = yes,
		Versions \= []
	->
		% We can sometimes improve efficiency by rerunning determinism
		% inference on the specialized versions after constraint
		% propagation, because some nondet predicates will have
		% become semidet.
		list__foldl(reset_inferred_proc_determinism, Versions,
			!ModuleInfo),
		module_info_num_errors(!.ModuleInfo, Errors5),

		disable_det_warnings(OptionsToRestore, !IO),
		determinism_pass(!ModuleInfo, !IO),
		restore_det_warnings(OptionsToRestore, !IO),

		module_info_num_errors(!.ModuleInfo, Errors),
		require(unify(Errors5, Errors),
			"determinism errors after deforestation")
	;
		true
	).

:- pred reset_inferred_proc_determinism(pred_proc_id::in,
	module_info::in, module_info::out) is det.

reset_inferred_proc_determinism(PredProcId, !ModuleInfo) :-
	module_info_pred_proc_info(!.ModuleInfo, PredProcId,
		PredInfo, ProcInfo0),
	proc_info_inferred_determinism(ProcInfo0, Detism0),
	( determinism_components(Detism0, _, at_most_many_cc) ->
		% `cc_multi' or `cc_nondet' determinisms are never inferred,
		% so resetting the determinism would cause determinism errors.
		true
	;
		proc_info_set_inferred_determinism(erroneous,
			ProcInfo0, ProcInfo),
		module_info_set_pred_proc_info(PredProcId, PredInfo, ProcInfo,
			!ModuleInfo)
	).

:- pred proc_arg_info_init(map(pred_proc_id, pd_proc_arg_info)::out) is det.

proc_arg_info_init(ProcArgInfo0) :-
	map__init(ProcArgInfo0).

:- pred deforest__get_branch_vars_proc(pred_id::in, proc_id::in,
	proc_info::in, proc_info::out, univ::in, univ::out,
	module_info::in, module_info::out) is det.

deforest__get_branch_vars_proc(PredId, ProcId, ProcInfo, ProcInfo,
		UnivProcArgInfo0, UnivProcArgInfo,
		ModuleInfo0, ModuleInfo) :-
	( univ_to_type(UnivProcArgInfo0, ProcArgInfo0) ->
		pd_util__get_branch_vars_proc(proc(PredId, ProcId), ProcInfo,
			ProcArgInfo0, ProcArgInfo, ModuleInfo0, ModuleInfo),
		type_to_univ(ProcArgInfo, UnivProcArgInfo)
	;
		error("deforest__get_branch_vars_proc")
	).

:- pred deforest__proc(pred_proc_id::in, pd_info::in, pd_info::out,
	io::di, io::uo) is det.

deforest__proc(PredProcId, !PDInfo, !IO) :-
	deforest__proc(PredProcId, _, _, !PDInfo, !IO).

:- pred deforest__proc(pred_proc_id::in, int::out, int::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__proc(proc(PredId, ProcId), CostDelta, SizeDelta, !PDInfo, !IO) :-
	pd_info_get_module_info(!.PDInfo, ModuleInfo0),
	write_proc_progress_message("% Deforesting ",
		PredId, ProcId, ModuleInfo0, !IO),
	module_info_pred_proc_info(ModuleInfo0, PredId, ProcId,
		PredInfo0, ProcInfo0),
	pd_info_init_unfold_info(proc(PredId, ProcId), PredInfo0, ProcInfo0,
		!PDInfo),
	proc_info_goal(ProcInfo0, Goal0),

	% Inlining may have created some opportunities for simplification.
	globals__io_get_globals(Globals, !IO),
	simplify__find_simplifications(no, Globals, Simplifications),
	pd_util__simplify_goal(Simplifications, Goal0, Goal1, !PDInfo),

	pd_util__propagate_constraints(Goal1, Goal2, !PDInfo, !IO),

	pd_debug__output_goal(!.PDInfo, "after constraints\n", Goal2, !IO),
	deforest__goal(Goal2, Goal3, !PDInfo, !IO),

	pd_info_get_proc_info(!.PDInfo, ProcInfo1),
	proc_info_set_goal(Goal3, ProcInfo1, ProcInfo2),
	pd_info_get_changed(!.PDInfo, Changed),

	(
		Changed = yes,
		pd_info_get_module_info(!.PDInfo, ModuleInfo2),
		requantify_proc(ProcInfo2, ProcInfo3),
		proc_info_goal(ProcInfo3, Goal4),
		proc_info_get_initial_instmap(ProcInfo3,
			ModuleInfo2, InstMap0),
		proc_info_vartypes(ProcInfo3, VarTypes),
		proc_info_inst_varset(ProcInfo3, InstVarSet),
		recompute_instmap_delta(yes, Goal4, Goal, VarTypes,
			InstVarSet, InstMap0, ModuleInfo2, ModuleInfo3),
		pd_info_set_module_info(ModuleInfo3, !PDInfo),

		pd_info_get_pred_info(!.PDInfo, PredInfo),
		proc_info_set_goal(Goal, ProcInfo3, ProcInfo),
		module_info_set_pred_proc_info(PredId, ProcId,
			PredInfo, ProcInfo, ModuleInfo3, ModuleInfo4),

		pd_info_get_rerun_det(!.PDInfo, RerunDet),

		(
			RerunDet = yes,
			% If the determinism of some sub-goals has changed,
			% then we re-run determinism analysis. As with
			% inlining.m, this avoids problems with inlining
			% erroneous procedures.
			det_infer_proc(PredId, ProcId, ModuleInfo4,
				ModuleInfo5, Globals, _, _, _)
		;
			RerunDet = no,
			ModuleInfo5 = ModuleInfo4
		),

		% Recompute the branch_info for the procedure.
		pd_info_get_proc_arg_info(!.PDInfo, ProcArgInfo0),
		pd_util__get_branch_vars_proc(proc(PredId, ProcId), ProcInfo,
			ProcArgInfo0, ProcArgInfo, ModuleInfo5, ModuleInfo6),
		pd_info_set_proc_arg_info(ProcArgInfo, !PDInfo),
		pd_info_set_module_info(ModuleInfo6, !PDInfo)
	;
		Changed = no,
		pd_info_get_module_info(!.PDInfo, ModuleInfo2),
		pd_info_get_pred_info(!.PDInfo, PredInfo),
		module_info_set_pred_proc_info(PredId, ProcId,
			PredInfo, ProcInfo2, ModuleInfo2, ModuleInfo3),
		pd_info_set_module_info(ModuleInfo3, !PDInfo)
	),

	pd_info_get_module_info(!.PDInfo, ModuleInfo),
	write_proc_progress_message("% Finished deforesting ",
		PredId, ProcId, ModuleInfo, !IO),
	pd_info_get_cost_delta(!.PDInfo, CostDelta),
	pd_info_get_size_delta(!.PDInfo, SizeDelta),
	pd_info_unset_unfold_info(!PDInfo).

:- pred deforest__goal(hlds_goal::in, hlds_goal::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__goal(conj(Goals0) - Info, conj(Goals) - Info, !PDInfo, !IO) :-
	pd_info_get_instmap(!.PDInfo, InstMap0),
	deforest__partially_evaluate_conj_goals(Goals0, [], Goals1, !PDInfo,
		!IO),
	pd_info_set_instmap(InstMap0, !PDInfo),
	goal_info_get_nonlocals(Info, NonLocals),
	globals__io_lookup_bool_option(deforestation, Deforestation, !IO),
	(
		Deforestation = yes,
		deforest__compute_goal_infos(Goals1, Goals2, !PDInfo),
		pd_info_set_instmap(InstMap0, !PDInfo),
		deforest__conj(Goals2, NonLocals, [], Goals3, !PDInfo, !IO)
	;
		Deforestation = no,
		Goals3 = Goals1
	),
	globals__io_lookup_bool_option(constraint_propagation, Constraints,
		!IO),
	pd_info_set_instmap(InstMap0, !PDInfo),
	(
		Constraints = yes,
		deforest__propagate_conj_constraints(Goals3,
			NonLocals, [], Goals, !PDInfo, !IO)
	;
		Constraints = no,
		Goals = Goals3
	),
	pd_info_set_instmap(InstMap0, !PDInfo).

	% XXX cannot deforest across parallel_conjunctions!
deforest__goal(par_conj(Goals) - Info, par_conj(Goals) - Info, !PDInfo, !IO).

deforest__goal(disj(Goals0) - Info, disj(Goals) - Info, !PDInfo, !IO) :-
	deforest__disj(Goals0, Goals, !PDInfo, !IO).

deforest__goal(if_then_else(Vars, Cond0, Then0, Else0) - Info,
		if_then_else(Vars, Cond, Then, Else) - Info, !PDInfo, !IO) :-
	pd_info_get_instmap(!.PDInfo, InstMap0),
	deforest__goal(Cond0, Cond, !PDInfo, !IO),
	pd_info_update_goal(Cond, !PDInfo),
	deforest__goal(Then0, Then, !PDInfo, !IO),
	pd_info_set_instmap(InstMap0, !PDInfo),
	deforest__goal(Else0, Else, !PDInfo, !IO),
	pd_info_set_instmap(InstMap0, !PDInfo).

deforest__goal(switch(Var, CanFail, Cases0) - Info,
		switch(Var, CanFail, Cases) - Info, !PDInfo, !IO) :-
	deforest__cases(Var, Cases0, Cases, !PDInfo, !IO).

deforest__goal(Goal, Goal, !PDInfo, !IO) :-
	Goal = foreign_proc(_, _, _, _, _, _) - _.

deforest__goal(Goal, Goal, !PDInfo, !IO) :-
	Goal = generic_call(_, _, _, _) - _.

deforest__goal(not(Goal0) - Info, not(Goal) - Info, !PDInfo, !IO) :-
	deforest__goal(Goal0, Goal, !PDInfo, !IO).

deforest__goal(scope(Reason, Goal0) - Info,
		scope(Reason, Goal) - Info, !PDInfo, !IO) :-
	deforest__goal(Goal0, Goal, !PDInfo, !IO).

deforest__goal(Goal0, Goal, !PDInfo, !IO) :-
	Goal0 = call(PredId, ProcId, Args, BuiltinState, _, Name) - _,
	deforest__call(PredId, ProcId, Args, Name, BuiltinState, Goal0, Goal,
		!PDInfo, !IO).

deforest__goal(Goal, Goal, !PDInfo, !IO) :-
	Goal = unify(_, _, _, _, _) - _.

deforest__goal(shorthand(_) - _, _, !PDInfo, !IO) :-
	% these should have been expanded out by now
	error("deforest__goal: unexpected shorthand").

%-----------------------------------------------------------------------------%

:- pred deforest__disj(list(hlds_goal)::in, list(hlds_goal)::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__disj([], [], !PDInfo, !IO).
deforest__disj([Goal0 | Goals0], [Goal | Goals], !PDInfo, !IO) :-
	pd_info_get_instmap(!.PDInfo, InstMap0),
	deforest__goal(Goal0, Goal, !PDInfo, !IO),
	pd_info_set_instmap(InstMap0, !PDInfo),
	deforest__disj(Goals0, Goals, !PDInfo, !IO).

%-----------------------------------------------------------------------------%

:- pred deforest__cases(prog_var::in, list(case)::in, list(case)::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__cases(_, [], [], !PDInfo, !IO).
deforest__cases(Var, [case(ConsId, Goal0) | Cases0],
		[case(ConsId, Goal) | Cases], !PDInfo, !IO) :-
	% Bind Var to ConsId in the instmap before processing this case.
	pd_info_get_instmap(!.PDInfo, InstMap0),
	pd_info_bind_var_to_functor(Var, ConsId, !PDInfo),
	deforest__goal(Goal0, Goal, !PDInfo, !IO),
	pd_info_set_instmap(InstMap0, !PDInfo),
	deforest__cases(Var, Cases0, Cases, !PDInfo, !IO).

%-----------------------------------------------------------------------------%

	% Perform partial evaluation on the goals of a conjunction.
:- pred deforest__partially_evaluate_conj_goals(list(hlds_goal)::in,
	list(hlds_goal)::in, list(hlds_goal)::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__partially_evaluate_conj_goals([], RevGoals, Goals, !PDInfo, !IO) :-
	list__reverse(RevGoals, Goals).
deforest__partially_evaluate_conj_goals([Goal0 | Goals0], RevGoals0, Goals,
		!PDInfo, !IO) :-
	deforest__goal(Goal0, Goal1, !PDInfo, !IO),
	pd_info_update_goal(Goal1, !PDInfo),
	( Goal1 = conj(Goals1) - _ ->
		list__reverse(Goals1, RevGoals1),
		list__append(RevGoals1, RevGoals0, RevGoals2)
	;
		RevGoals2 = [Goal1 | RevGoals0]
	),
	deforest__partially_evaluate_conj_goals(Goals0, RevGoals2, Goals,
		!PDInfo, !IO).

%-----------------------------------------------------------------------------%

	% Compute the branch info for each goal in a conjunction.
:- pred deforest__compute_goal_infos(list(hlds_goal)::in, annotated_conj::out,
	pd_info::in, pd_info::out) is det.

deforest__compute_goal_infos([], [], !PDInfo).
deforest__compute_goal_infos([Goal | Goals0],
		[Goal - MaybeBranchInfo | Goals], !PDInfo) :-
	deforest__get_branch_vars_goal(Goal, MaybeBranchInfo, !PDInfo),
	pd_info_update_goal(Goal, !PDInfo),
	deforest__compute_goal_infos(Goals0, Goals, !PDInfo).

:- pred deforest__get_branch_vars_goal(hlds_goal::in,
	maybe(pd_branch_info(prog_var))::out, pd_info::in, pd_info::out)
	is det.

deforest__get_branch_vars_goal(Goal, MaybeBranchInfo, !PDInfo) :-
	Goal = GoalExpr - _,
	( goal_util__goal_is_branched(GoalExpr) ->
		pd_util__get_branch_vars_goal(Goal, MaybeBranchInfo, !PDInfo)
	; GoalExpr = call(PredId, ProcId, Args, _, _, _) ->
		pd_info_get_proc_arg_info(!.PDInfo, ProcBranchInfos),
		(
			map__search(ProcBranchInfos, proc(PredId, ProcId),
				BranchInfo0)
		->
			% Rename the branch_info for the called procedure
			% onto the argument variables.
			pd_util__convert_branch_info(BranchInfo0, Args,
				BranchInfo),
			MaybeBranchInfo = yes(BranchInfo)
		;
			MaybeBranchInfo = no
		)
	;
		MaybeBranchInfo = no
	).

%-----------------------------------------------------------------------------%

:- pred deforest__propagate_conj_constraints(list(hlds_goal)::in,
	set(prog_var)::in, list(hlds_goal)::in, list(hlds_goal)::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__propagate_conj_constraints([], _, RevGoals, Goals, !PDInfo, !IO) :-
	list__reverse(RevGoals, Goals).
deforest__propagate_conj_constraints([Goal0 | Goals0],
		NonLocals, RevGoals0, Goals, !PDInfo, !IO) :-
	pd_info_get_module_info(!.PDInfo, ModuleInfo),
	(
		% constraint.m ensures that only constraints relevant
		% to this goal are placed adjacent to it.
		Goal0 = call(PredId, _ProcId, _Args, _, _, SymName) - _,
		module_info_pred_info(ModuleInfo, PredId, PredInfo),
		\+ pred_info_is_imported(PredInfo),
		list__takewhile((pred(CnstrGoal::in) is semidet :-
			CnstrGoal = _ - CnstrGoalInfo,
			goal_info_has_feature(CnstrGoalInfo, constraint)
		), Goals0, Constraints, Goals1),
		Constraints \= []
	->
		mdbcomp__prim_data__sym_name_to_string(SymName, SymNameString),
		pd_debug__message("propagating constraints into call to %s\n",
			[s(SymNameString)], !IO),

		deforest__get_sub_conj_nonlocals(NonLocals, RevGoals0, [],
			Goal0, Constraints, no, [], Goals1, ConjNonLocals),
		deforest__call_call(ConjNonLocals, Goal0, Constraints, no,
			MaybeGoal, !PDInfo, !IO),
		(
			MaybeGoal = yes(Goal),
			pd_info_set_rerun_det(yes, !PDInfo),
			pd_info_update_goal(Goal, !PDInfo),
			deforest__propagate_conj_constraints(Goals1,
				NonLocals, [Goal | RevGoals0], Goals,
				!PDInfo, !IO)
		;
			MaybeGoal = no,
			pd_info_update_goal(Goal0, !PDInfo),
			deforest__propagate_conj_constraints(Goals0,
				NonLocals, [Goal0 | RevGoals0], Goals,
				!PDInfo, !IO)
		)
	;
		pd_info_update_goal(Goal0, !PDInfo),
		deforest__propagate_conj_constraints(Goals0, NonLocals,
			[Goal0 | RevGoals0], Goals, !PDInfo, !IO)
	).

%-----------------------------------------------------------------------------%

:- type annotated_conj ==
		assoc_list(hlds_goal, maybe(pd_branch_info(prog_var))).

:- pred deforest__conj(annotated_conj::in, set(prog_var)::in,
	list(hlds_goal)::in, list(hlds_goal)::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__conj([], _, RevGoals, Goals, !PDInfo, !IO) :-
	list__reverse(RevGoals, Goals).
deforest__conj([Goal0 - MaybeBranchInfo | Goals0], NonLocals,
		RevGoals0, RevGoals, !PDInfo, !IO) :-
	(
		% Look for a goal later in the conjunction to deforest with.
		MaybeBranchInfo = yes(GoalBranchInfo),
		deforest__detect_deforestation(Goal0, GoalBranchInfo,
			Goals0, Goals1, DeforestInfo)
	->
		deforest__handle_deforestation(NonLocals, DeforestInfo,
			RevGoals0, RevGoals1, Goals1, Goals2, Optimized,
			!PDInfo, !IO),
		( Optimized = yes ->
			deforest__conj(Goals2, NonLocals, RevGoals1, RevGoals,
				!PDInfo, !IO)
		;
			pd_info_update_goal(Goal0, !PDInfo),
			RevGoals2 = [Goal0 | RevGoals0],
			deforest__conj(Goals0, NonLocals, RevGoals2, RevGoals,
				!PDInfo, !IO)
		)
	;
		pd_info_update_goal(Goal0, !PDInfo),
		RevGoals1 = [Goal0 | RevGoals0],
		deforest__conj(Goals0, NonLocals, RevGoals1, RevGoals,
			!PDInfo, !IO)
	).

%-----------------------------------------------------------------------------%

:- type deforest_info --->
	deforest_info(
		hlds_goal,		% earlier goal in conjunction
		pd_branch_info(prog_var),
					%branch_info for earlier goal
		list(hlds_goal),	% goals in between
		hlds_goal,		% later goal in conjunction
		pd_branch_info(prog_var),
					% branch_info for later goal
		set(int)		% branches for which there is
					% extra information about the second
					% goal, numbering starts at 1.
	).

	% Search backwards through the conjunction for the last
	% goal which contains extra information about the variable
	% being switched on.
:- pred deforest__detect_deforestation(hlds_goal::in,
	pd_branch_info(prog_var)::in, annotated_conj::in,
	annotated_conj::out, deforest_info::out) is semidet.

deforest__detect_deforestation(EarlierGoal, BranchInfo,
		Goals0, Goals1, DeforestInfo) :-
	deforest__search_for_deforest_goal(EarlierGoal, BranchInfo, [],
		Goals0, Goals1, DeforestInfo).

:- pred deforest__search_for_deforest_goal(hlds_goal::in,
	pd_branch_info(prog_var)::in, annotated_conj::in,
	annotated_conj::in, annotated_conj::out,
	deforest_info::out) is semidet.

deforest__search_for_deforest_goal(EarlierGoal, EarlierBranchInfo,
		RevBetweenGoals0, [Goal | Goals0], Goals, DeforestInfo) :-
	(
		Goal = LaterGoal - yes(LaterBranchInfo),
		deforest__potential_deforestation(EarlierBranchInfo,
			LaterBranchInfo, DeforestBranches)
	->
		list__reverse(RevBetweenGoals0, BetweenGoals1),
		assoc_list__keys(BetweenGoals1, BetweenGoals),
		Goals = Goals0,
		DeforestInfo = deforest_info(
				EarlierGoal,
				EarlierBranchInfo,
				BetweenGoals,
				LaterGoal,
				LaterBranchInfo,
				DeforestBranches
			)
	;
		deforest__search_for_deforest_goal(EarlierGoal,
			EarlierBranchInfo, [Goal | RevBetweenGoals0],
			Goals0, Goals, DeforestInfo)
	).

	% Look for a variable in the second branch_info for which
	% we have more information in the first than in the instmap.
	% Get the branches in the first goal which contain this extra
	% information.
:- pred deforest__potential_deforestation(pd_branch_info(prog_var)::in,
	pd_branch_info(prog_var)::in, set(int)::out) is semidet.

deforest__potential_deforestation(Info1, Info2, DeforestBranches) :-
	Info1 = pd_branch_info(VarMap1, _, _),
	Info2 = pd_branch_info(_, LeftVars2, _),

	map__select(VarMap1, LeftVars2, VarMap),
	map__to_assoc_list(VarMap, VarAssoc),
	\+ map__is_empty(VarMap),

		% Work out which branches of the first goal should
		% contain unfolded versions of the second goal.
	GetBranches =
		(pred(VarInfo::in, Branches0::in, Branches::out) is det :-
			VarInfo = _ - Branches1,
			set__union(Branches0, Branches1, Branches)
	),
	set__init(DeforestBranches0),
	list__foldl(GetBranches, VarAssoc,
		DeforestBranches0, DeforestBranches).

%-----------------------------------------------------------------------------%

	% Take the part of a conjunction found to have potential
	% for deforestation and attempt the optimization.
:- pred deforest__handle_deforestation(set(prog_var)::in, deforest_info::in,
	list(hlds_goal)::in, list(hlds_goal)::out,
	annotated_conj::in, annotated_conj::out, bool::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__handle_deforestation(NonLocals, DeforestInfo0,
		!RevBeforeGoals, !AfterGoals, Optimized, !PDInfo, !IO) :-

	pd_info_get_instmap(!.PDInfo, InstMap0),
	pd_info_get_created_versions(!.PDInfo, CreatedVersions0),

	pd_info_get_depth(!.PDInfo, Depth0),
	pd_debug__message("checking for deforestation at depth %i\n",
		[i(Depth0)], !IO),

	deforest__reorder_conj(DeforestInfo0, DeforestInfo,
		BeforeIrrelevant, AfterIrrelevant, !.PDInfo, !IO),

	deforest__get_sub_conj_nonlocals(NonLocals, DeforestInfo,
		!.RevBeforeGoals, BeforeIrrelevant, AfterIrrelevant,
		!.AfterGoals, ConjNonLocals),

		% Update the instmap.
	list__foldl(pd_info_update_goal, BeforeIrrelevant, !PDInfo),

	pd_info_get_pred_proc_id(!.PDInfo, CurrPredProcId),
	pd_info_get_parents(!.PDInfo, Parents0),
	pd_info_get_cost_delta(!.PDInfo, CostDelta0),
	pd_info_get_size_delta(!.PDInfo, SizeDelta0),
	pd_info_get_module_info(!.PDInfo, ModuleInfo),

	DeforestInfo = deforest_info(EarlierGoal, _, BetweenGoals,
		LaterGoal, _, DeforestBranches),

	deforest__should_try_deforestation(DeforestInfo, ShouldOptimize,
		!PDInfo, !IO),
	(
		ShouldOptimize = no
	->
		Optimized0 = no,
		Goals = []
	;
		EarlierGoal = call(PredId1, _, _, _, _, _) - _,
		LaterGoal = call(PredId2, _, _, _, _, _) - _
	->
		%
		% If both goals are calls create a new predicate
		% for the conjunction to be deforested and process it.
		%
		pd_info_get_module_info(!.PDInfo, ModuleInfo0),
		predicate_name(ModuleInfo0, PredId1, PredName1),
		predicate_name(ModuleInfo0, PredId2, PredName2),
		pd_debug__message("deforesting calls to %s and %s\n",
			[s(PredName1), s(PredName2)], !IO),
		deforest__call_call(ConjNonLocals, EarlierGoal, BetweenGoals,
			yes(LaterGoal), MaybeGoal, !PDInfo, !IO),
		(
			MaybeGoal = yes(Goal),
			Optimized0 = yes,
			Goals = [Goal]
		;
			MaybeGoal = no,
			Optimized0 = no,
			Goals = []
		)
	;
		%
		% If the first goal is branched and the second goal is
		% a call, attempt to push the call into the branches.
		% Don't push a recursive call or a call to a predicate we
		% have already pushed into a switch, since it is difficult
		% to stop the process.
		%
		EarlierGoal = EarlierGoalExpr - _,
		goal_util__goal_is_branched(EarlierGoalExpr),
		LaterGoal = call(PredId, ProcId, _, _, _, _) - _,
		PredProcId = proc(PredId, ProcId),
		PredProcId \= CurrPredProcId,
		\+ set__member(PredProcId, Parents0)
	->
		predicate_name(ModuleInfo, PredId, CurrPredName),
		pd_debug__message("Pushing call to %s into goal\n",
			[s(CurrPredName)], !IO),
		set__insert(Parents0, proc(PredId, ProcId), Parents),
		pd_info_set_parents(Parents, !PDInfo),
		deforest__push_goal_into_goal(ConjNonLocals, DeforestBranches,
			EarlierGoal, BetweenGoals, LaterGoal, Goal,
			!PDInfo, !IO),
		Goals = [Goal],
		Optimized0 = yes
	;
		%
		% If both goals are branched, push the second into the
		% branches of the first.
		%
		EarlierGoal = EarlierGoalExpr - _,
		LaterGoal = LaterGoalExpr - _,
		goal_util__goal_is_branched(EarlierGoalExpr),
		goal_util__goal_is_branched(LaterGoalExpr)
	->
		pd_debug__message("Pushing goal into goal\n", [], !IO),
		deforest__push_goal_into_goal(ConjNonLocals, DeforestBranches,
			EarlierGoal, BetweenGoals, LaterGoal, Goal,
			!PDInfo, !IO),
		Goals = [Goal],
		goals_size([EarlierGoal | BetweenGoals], ConjSize1),
		goal_size(LaterGoal, ConjSize2),
		goal_size(Goal, NewSize),
		SizeDiff = NewSize - ConjSize1 - ConjSize2,
		pd_info_incr_size_delta(SizeDiff, !PDInfo),
		Optimized0 = yes
	;
		pd_debug__message("not optimizing\n", [], !IO),
		Goals = [],
		Optimized0 = no
	),
	deforest__check_improvement(Optimized0, CostDelta0, SizeDelta0,
		Optimized, !.PDInfo, !IO),
	%
	% Clean up.
	%
	pd_info_set_depth(Depth0, !PDInfo),
	pd_info_set_instmap(InstMap0, !PDInfo),
	(
		Optimized = no,

		% XXX currently this only attempts to deforest the
		% first goal with the first matching goal later in
		% the conjunction. If the deforestation failed,
		% other later goals should be tried.
		%
		% Return everything to the state it was in before
		% the attempted optimization.
		pd_info_set_cost_delta(CostDelta0, !PDInfo),
		pd_info_set_size_delta(SizeDelta0, !PDInfo),

		% Remove any versions which were created.
		pd_info_get_created_versions(!.PDInfo, CreatedVersions),
		set__difference(CreatedVersions,
			CreatedVersions0, NewVersions0),
		set__to_sorted_list(NewVersions0, NewVersions),
		list__foldl(pd_info__remove_version, NewVersions, !PDInfo)

		% AfterGoals will be restored properly in deforest__conj.
	;
		Optimized = yes,
		% We want to reprocess the deforested goal to see
		% if it can be deforested with other goals later in
		% the conjunction.
		list__condense([BeforeIrrelevant, Goals, AfterIrrelevant],
			GoalsToProcess),
		deforest__compute_goal_infos(GoalsToProcess, GoalsAndInfo,
			!PDInfo),
		list__append(GoalsAndInfo, !AfterGoals),
		pd_info_set_instmap(InstMap0, !PDInfo),
		pd_info_set_changed(yes, !PDInfo),
		pd_info_set_rerun_det(yes, !PDInfo)
	),
	pd_debug__message("finished deforestation at depth %i\n",
		[i(Depth0)], !IO),
	pd_info_set_parents(Parents0, !PDInfo).

	% Check whether deforestation is legal and worthwhile.
:- pred deforest__should_try_deforestation(deforest_info::in,
	bool::out, pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__should_try_deforestation(DeforestInfo, ShouldTry, !PDInfo, !IO) :-
	DeforestInfo = deforest_info(EarlierGoal, EarlierBranchInfo,
		BetweenGoals, LaterGoal, _, _),
	pd_info_get_useless_versions(!.PDInfo, UselessVersions),
	(
		EarlierGoal = call(PredId1, ProcId1, _, _, _, _) - _,
		LaterGoal = call(PredId2, ProcId2, _, _, _, _) - _,
		set__member(proc(PredId1, ProcId1) - proc(PredId2, ProcId2),
			UselessVersions)
	->
		pd_debug__message("version tried before, not worthwhile\n",
			[], !IO),
		ShouldTry = no
	;
		%
		% If some later goal depends on a variable such as an io__state
		% for which the construction cannot be reversed, recursive
		% folding will be impossible, so give up on the optimization.
		%
		EarlierBranchInfo = pd_branch_info(_, _, OpaqueVars),
		( list__member(OpaqueGoal, BetweenGoals)
		; OpaqueGoal = LaterGoal
		),
		OpaqueGoal = _ - OpaqueGoalInfo,
		goal_info_get_nonlocals(OpaqueGoalInfo, OpaqueNonLocals),
		set__intersect(OpaqueNonLocals, OpaqueVars,
			UsedOpaqueVars),
		\+ set__empty(UsedOpaqueVars)
	->
		pd_debug__message("later goals depend on opaque vars\n", [],
			!IO),
		ShouldTry = no
	;
		ShouldTry = yes
	).

:- pred deforest__can_optimize_conj(hlds_goal::in, list(hlds_goal)::in,
	maybe(hlds_goal)::in, bool::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__can_optimize_conj(EarlierGoal, BetweenGoals, MaybeLaterGoal,
		ShouldTry, !PDInfo, !IO) :-
	pd_info_get_pred_info(!.PDInfo, PredInfo),
	globals__io_lookup_option(deforestation_depth_limit, DepthLimitOpt,
		!IO),
	pd_info_get_depth(!.PDInfo, Depth0),
	Depth = Depth0 + 1,
	pd_info_set_depth(Depth, !PDInfo),
	globals__io_lookup_int_option(deforestation_size_threshold, SizeLimit,
		!IO),
	pd_info_get_module_info(!.PDInfo, ModuleInfo),
	globals__io_lookup_option(fully_strict, FullyStrictOp, !IO),
	(
		DepthLimitOpt = int(MaxDepth),
		MaxDepth \= -1, 	% no depth limit set
		Depth0 >= MaxDepth
	->
		% The depth limit was exceeded. This should not
		% occur too often in practice - the depth limit
		% is just a safety net.
		pd_debug__message("\n\n*****Depth limit exceeded*****\n\n",
			[], !IO),
		ShouldTry = no
	;
		% Check whether either of the goals to be
		% deforested is too large. XXX This is
		% probably a bit too crude, especially for
		% LaterGoal, which should be reduced in size
		% in the specialized version (the specialized
		% version will only include one branch of the
		% top-level switch).
		SizeLimit \= -1,
		( EarlierGoal = call(PredId, ProcId, _, _, _, _) - _
		; MaybeLaterGoal = yes(call(PredId, ProcId, _, _, _, _) - _)
		),
		module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
			_, CalledProcInfo),
		proc_info_goal(CalledProcInfo, CalledGoal),
		goal_size(CalledGoal, CalledGoalSize),
		SizeLimit \= -1,
		CalledGoalSize > SizeLimit
	->
		pd_debug__message("goal too large\n", [], !IO),
		ShouldTry = no
	;
		% Check whether either of the goals to be
		% deforested can't be inlined.
		( EarlierGoal = call(PredId, ProcId, _, BuiltinState, _, _) - _
		; MaybeLaterGoal = yes(
			call(PredId, ProcId, _, BuiltinState, _, _) - _)
		),

		% We don't attempt to deforest predicates which are
		% promised pure because the extra impurity propagated
		% through the goal when such predicates are inlined
		% will defeat any attempt at deforestation.
		% XXX We should probably allow deforestation of
		% semipure goals.
		InlinePromisedPure = no,
		pred_info_get_markers(PredInfo, CallerMarkers),
		\+ inlining__can_inline_proc(PredId, ProcId, BuiltinState,
			InlinePromisedPure, CallerMarkers, ModuleInfo)
	->
		pd_debug__message("non-inlineable calls\n", [], !IO),
		ShouldTry = no
	;
		%
		% Don't optimize if that would require duplicating
		% branched goal structures.
		%
		\+ deforest__is_simple_goal_list(BetweenGoals)
	->
		pd_debug__message("between goals not simple enough\n", [],
			!IO),
		ShouldTry = no
	;
		%
		% Give up if there are any impure goals involved.
		% XXX We should probably allow deforestation of
		% semipure goals.
		%
		( list__member(ImpureGoal, BetweenGoals)
		; ImpureGoal = EarlierGoal
		; MaybeLaterGoal = yes(ImpureGoal)
		),
		ImpureGoal = _ - ImpureGoalInfo,
		\+ goal_info_is_pure(ImpureGoalInfo)
	->
		pd_debug__message("goal list contains impure goal(s)\n", [],
			!IO),
		ShouldTry = no
	;
		%
		% Check whether interleaving the execution of the goals could
		% alter the termination behaviour in a way which is
		% illegal according to the semantics options.
		%
		FullyStrictOp = bool(FullyStrict),
		( list__member(OtherGoal, BetweenGoals)
		; MaybeLaterGoal = yes(LaterGoal), OtherGoal = LaterGoal
		),
		\+ goal_util__reordering_maintains_termination(ModuleInfo,
			FullyStrict, EarlierGoal, OtherGoal)
	->
		pd_debug__message("interleaving execution could change " ++
			"termination behaviour\n", [], !IO),
		ShouldTry = no
	;
		ShouldTry = yes
	).

	% Check that the code size increase is justified by the
	% estimated performance increase. This should err towards
	% allowing optimization - without any check at all the
	% code size of the library only increases ~10%.
:- pred deforest__check_improvement(bool::in, int::in, int::in, bool::out,
	pd_info::in, io::di, io::uo) is det.

deforest__check_improvement(Optimized0, CostDelta0, SizeDelta0, Optimized,
		PDInfo, !IO) :-
	pd_info_get_cost_delta(PDInfo, CostDelta),
	pd_info_get_size_delta(PDInfo, SizeDelta),
	Improvement = CostDelta - CostDelta0,
	SizeDifference = SizeDelta - SizeDelta0,
	globals__io_lookup_int_option(deforestation_cost_factor, Factor, !IO),
	(
		Optimized0 = yes,
		deforest__check_deforestation_improvement(Factor,
			Improvement, SizeDifference)
	->
		Optimized = yes,
		pd_debug__message("Enough improvement: cost(%i) size(%i)\n",
			[i(Improvement), i(SizeDifference)], !IO)
	;
		Optimized = no,
		pd_debug__message(
			"Not enough improvement: cost(%i) size(%i)\n",
			[i(Improvement), i(SizeDifference)], !IO)
	).

%-----------------------------------------------------------------------------%

	% Attempt deforestation on a pair of calls.
:- pred deforest__call_call(set(prog_var)::in, hlds_goal::in,
	list(hlds_goal)::in, maybe(hlds_goal)::in, maybe(hlds_goal)::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__call_call(ConjNonLocals, EarlierGoal, BetweenGoals,
		MaybeLaterGoal, MaybeGoal, !PDInfo, !IO) :-
	deforest__can_optimize_conj(EarlierGoal, BetweenGoals,
		MaybeLaterGoal, ShouldTry, !PDInfo, !IO),
	(
		ShouldTry = yes,
		deforest__call_call(ConjNonLocals, EarlierGoal, BetweenGoals,
			MaybeLaterGoal, MaybeGoal, !PDInfo, !IO)
	;
		ShouldTry = no,
		MaybeGoal = no
	).

	% Attempt deforestation on a pair of calls.
:- pred deforest__call_call_2(set(prog_var)::in, hlds_goal::in,
	list(hlds_goal)::in, maybe(hlds_goal)::in, maybe(hlds_goal)::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__call_call_2(ConjNonLocals, EarlierGoal, BetweenGoals,
		MaybeLaterGoal, MaybeGoal, !PDInfo, !IO) :-
	deforest__create_conj(EarlierGoal, BetweenGoals,
		MaybeLaterGoal, ConjNonLocals, FoldGoal),

	pd_info__search_version(!.PDInfo, FoldGoal, MaybeVersion, !IO),
	pd_info_get_parent_versions(!.PDInfo, Parents),
	(
		MaybeVersion = version(_, VersionPredProcId,
			VersionInfo, Renaming, TypeRenaming)
	->
		% If we see an opportunity to fold, take it.
		VersionPredProcId = proc(VersionPredId, _),
		pd_info_get_module_info(!.PDInfo, ModuleInfo0),
		predicate_name(ModuleInfo0, VersionPredId, FoldPredName),
		pd_debug__message("Folded with %s\n", [s(FoldPredName)], !IO),
		( set__member(VersionPredProcId, Parents) ->
			pd_cost__recursive_fold(FoldCostDelta)
		;
			pd_cost__fold(FoldCostDelta)
		),
		pd_info_incr_cost_delta(FoldCostDelta, !PDInfo),
		goals_size([EarlierGoal | BetweenGoals], NegSizeDelta),
		SizeDelta = - NegSizeDelta,
		pd_info_incr_size_delta(SizeDelta, !PDInfo),
		deforest__create_call_goal(VersionPredProcId,
			VersionInfo, Renaming, TypeRenaming, Goal, !PDInfo),
		MaybeGoal = yes(Goal)
	;
		pd_info_get_global_term_info(!.PDInfo, TermInfo0),
		pd_info_get_parent_versions(!.PDInfo, ParentVersions0),

		pd_debug__do_io(io__write_string("Parents: "), !IO),
		pd_debug__write(ParentVersions0, !IO),
		pd_debug__do_io(io__nl, !IO),

		pd_info_get_module_info(!.PDInfo, ModuleInfo),
		pd_info_get_versions(!.PDInfo, Versions),
		pd_info_get_instmap(!.PDInfo, InstMap),
		pd_term__global_check(ModuleInfo, EarlierGoal, BetweenGoals,
			MaybeLaterGoal, InstMap, Versions, TermInfo0,
			TermInfo, CheckResult),
		(
			CheckResult = ok(ProcPair, Size),
			pd_debug__message(
				"global termination check succeeded - " ++
				"creating new version\n", [], !IO),
			pd_info_set_global_term_info(TermInfo, !PDInfo),
			RunModes = no,
			MaybeGeneralised = no,
			deforest__create_deforest_goal(EarlierGoal,
				BetweenGoals, MaybeLaterGoal, FoldGoal,
				ConjNonLocals, RunModes, ProcPair, Size,
				MaybeGeneralised, MaybeGoal, !PDInfo, !IO)
		;
			CheckResult = possible_loop(ProcPair, Size,
				CoveringPredProcId),
			% The termination check found the same
			% pair of end-points with the same length goal.
			% If the goal matches the goal for the "covering"
			% predicate, perform a most specific
			% generalisation on the insts then keep
			% on going.
			deforest__try_generalisation(EarlierGoal,
				BetweenGoals, MaybeLaterGoal, FoldGoal,
				ConjNonLocals, ProcPair, Size,
				CoveringPredProcId, MaybeGoal, !PDInfo, !IO)
		;
			CheckResult = loop,
			pd_debug__message("global termination check failed\n",
				[], !IO),
			MaybeGoal = no
		),
		pd_info_set_global_term_info(TermInfo0, !PDInfo)
	).

%-----------------------------------------------------------------------------%

	% Create a new procedure for a conjunction to be deforested, then
	% recursively process that procedure.
:- pred deforest__create_deforest_goal(hlds_goal::in, hlds_goals::in,
	maybe(hlds_goal)::in, hlds_goal::in, set(prog_var)::in, bool::in,
	proc_pair::in, int::in, maybe(pred_proc_id)::in,
	maybe(hlds_goal)::out, pd_info::in, pd_info::out,
	io::di, io::uo) is det.

deforest__create_deforest_goal(EarlierGoal, BetweenGoals, MaybeLaterGoal,
		FoldGoal0, NonLocals, RunModes, ProcPair, Size,
		MaybeGeneralised, MaybeCallGoal, !PDInfo, !IO) :-
	pd_info_get_module_info(!.PDInfo, ModuleInfo0),
	globals__io_lookup_int_option(deforestation_vars_threshold, VarsOpt,
		!IO),
	(
		EarlierGoal = call(PredId1, ProcId1, Args1, _, _, _) - _,
		(
				% no threshold set.
			VarsOpt = -1
		;
			%
			% Check that we're not creating a procedure
			% with a massive number of variables. We assume
			% that all the variables in the first called
			% goal are present in the final version. If the
			% number of variables in the first called goal
			% plus the number of variables in BetweenGoals
			% is less than --deforestation-vars-threshold, go
			% ahead and optimize.
			%
			module_info_pred_proc_info(ModuleInfo0,
				PredId1, ProcId1, _, CalledProcInfo1),
			proc_info_goal(CalledProcInfo1, CalledGoal1),
			goal_util__goal_vars(CalledGoal1, GoalVars1),
			set__to_sorted_list(GoalVars1, GoalVarsList1),
			set__init(GoalVars2),
			goal_util__goals_goal_vars(BetweenGoals,
				GoalVars2, GoalVars3),
			set__to_sorted_list(GoalVars3, GoalVarsList3),

			list__length(GoalVarsList1, NumVars1),
			list__length(GoalVarsList3, NumVars3),
			NumVars = NumVars1 + NumVars3,
			NumVars < VarsOpt
		)
	->
		%
		% Create the goal for the new predicate,
		% unfolding the first call.
		%

		pd_info_get_instmap(!.PDInfo, InstMap0),
		pd_info_get_proc_info(!.PDInfo, ProcInfo0),
		pd_debug__message("unfolding first call\n", [], !IO),

		deforest__unfold_call(no, no, PredId1, ProcId1, Args1,
			EarlierGoal, UnfoldedCall, DidUnfold, !PDInfo, !IO),
		deforest__create_conj(UnfoldedCall, BetweenGoals,
			MaybeLaterGoal, NonLocals, DeforestGoal0),
		set__to_sorted_list(NonLocals, NonLocalsList),

		(
			DidUnfold = yes,
			RunModes = yes
		->

			%
			% If we did a generalisation step when creating this
			% version, we need to modecheck to propagate through
			% the new insts. If this causes mode errors, don't
			% create the new version. This can happen if a
			% procedure expected an input to be bound to a
			% particular functor but the extra information
			% was generalised away.
			%
			pd_debug__message("running modes on deforest goal\n",
				[], !IO),
			pd_util__unique_modecheck_goal(DeforestGoal0,
				DeforestGoal, Errors1, !PDInfo, !IO),
			pd_util__unique_modecheck_goal(FoldGoal0, FoldGoal,
				Errors2, !PDInfo, !IO),
			list__append(Errors1, Errors2, Errors)
		;
			DeforestGoal = DeforestGoal0,
			FoldGoal = FoldGoal0,
			Errors = []
		),

		% We must have been able to unfold the first call to proceed
		% with the optimization, otherwise we will introduce an
		% infinite loop in the generated code.
		(
			DidUnfold = yes,
			Errors = []
		->
			%
			% Create the new version.
			%

			pd_info__define_new_pred(created(deforestation),
				DeforestGoal, PredProcId, CallGoal, !PDInfo),
			PredProcId = proc(PredId, _),

			pd_info_get_module_info(!.PDInfo, ModuleInfo),

			predicate_name(ModuleInfo, PredId, PredName),
			pd_debug__message("\nCreated predicate %s\n",
				[s(PredName)], !IO),
			(
				MaybeLaterGoal = yes(
					call(PredId2, ProcId2, _, _, _, _) - _)
			->
				CalledPreds = [proc(PredId1, ProcId1),
					proc(PredId2, ProcId2)]
			;
				CalledPreds = [proc(PredId1, ProcId1)]
			),
			pd_info_get_parent_versions(!.PDInfo, Parents0),

			pd_info_get_proc_info(!.PDInfo, ProcInfo1),
			proc_info_vartypes(ProcInfo1, VarTypes),
			map__apply_to_list(NonLocalsList,
				VarTypes, ArgTypes),
			VersionInfo = version_info(FoldGoal, CalledPreds,
				NonLocalsList, ArgTypes, InstMap0,
				0, 0, Parents0, MaybeGeneralised),
			pd_info_get_global_term_info(!.PDInfo, TermInfo0),
			pd_term__update_global_term_info(ProcPair, PredProcId,
				Size, TermInfo0, TermInfo),
			pd_info_set_global_term_info(TermInfo, !PDInfo),
			set__insert_list(Parents0, [PredProcId | CalledPreds],
				Parents),
			pd_info_set_parent_versions(Parents, !PDInfo),
			pd_info__register_version(PredProcId, VersionInfo,
				!PDInfo, !IO),

			% Run deforestation on the new predicate
			% to do the folding.
			pd_info_get_unfold_info(!.PDInfo, UnfoldInfo),
			deforest__proc(PredProcId, CostDelta, SizeDelta,
				!PDInfo, !IO),
			pd_info_set_unfold_info(UnfoldInfo, !PDInfo),
			pd_info_incr_cost_delta(CostDelta, !PDInfo),
			pd_info_incr_size_delta(SizeDelta, !PDInfo),
			pd_info_set_parent_versions(Parents0, !PDInfo),
			pd_info_get_pred_proc_id(!.PDInfo,
				proc(CurrPredId, CurrProcId)),
			write_proc_progress_message("% Back in ",
				CurrPredId, CurrProcId, ModuleInfo, !IO),
			MaybeCallGoal = yes(CallGoal)
		;
			pd_debug__message(
				"Generalisation produced mode errors\n", [],
				!IO),
			MaybeCallGoal = no
		),

		% The varset and vartypes fields were increased when
		% we unfolded the first call, but all the new variables
		% are only used in the new version, so it is safe to
		% reset the proc_info.
		pd_info_set_proc_info(ProcInfo0, !PDInfo),
		pd_info_set_instmap(InstMap0, !PDInfo)
	;
		pd_debug__message("vars threshold exceeded\n", [], !IO),
		MaybeCallGoal = no
	).

%-----------------------------------------------------------------------------%

	% Create a goal to call a newly created version.
:- pred deforest__create_call_goal(pred_proc_id::in, version_info::in,
	map(prog_var, prog_var)::in, tsubst::in, hlds_goal::out,
	pd_info::in, pd_info::out) is det.

deforest__create_call_goal(proc(PredId, ProcId), VersionInfo,
		Renaming, TypeSubn, Goal, !PDInfo) :-
	OldArgs = VersionInfo ^ version_arg_vars,
	pd_info_get_module_info(!.PDInfo, ModuleInfo),
	module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
		CalledPredInfo, CalledProcInfo),
	pred_info_arg_types(CalledPredInfo, CalledTVarSet, _CalledExistQVars,
		ArgTypes0),

		% Rename the arguments in the version.
	pd_info_get_proc_info(!.PDInfo, ProcInfo0),
	pd_info_get_pred_info(!.PDInfo, PredInfo0),

	proc_info_vartypes(ProcInfo0, VarTypes0),
	proc_info_varset(ProcInfo0, VarSet0),
	pred_info_typevarset(PredInfo0, TVarSet0),

		% Rename the argument types using the current pred's tvarset.
	varset__merge_subst(TVarSet0, CalledTVarSet,
		TVarSet, TypeRenaming),
	pred_info_set_typevarset(TVarSet, PredInfo0, PredInfo),
	pd_info_set_pred_info(PredInfo, !PDInfo),
	term__apply_substitution_to_list(ArgTypes0,
		TypeRenaming, ArgTypes1),

	deforest__create_deforest_call_args(OldArgs, ArgTypes1, Renaming,
		TypeSubn, Args, VarSet0, VarSet, VarTypes0, VarTypes),
	proc_info_set_vartypes(VarTypes, ProcInfo0, ProcInfo1),
	proc_info_set_varset(VarSet, ProcInfo1, ProcInfo),
	pd_info_set_proc_info(ProcInfo, !PDInfo),

		% Compute a goal_info.
	proc_info_argmodes(CalledProcInfo, ArgModes),
	instmap_delta_from_mode_list(Args, ArgModes,
		ModuleInfo, InstMapDelta),
	proc_info_interface_determinism(ProcInfo, Detism),
	set__list_to_set(Args, NonLocals),
	pred_info_get_purity(CalledPredInfo, Purity),
	goal_info_init(NonLocals, InstMapDelta, Detism, Purity, GoalInfo),

	PredModule = pred_info_module(CalledPredInfo),
	PredName = pred_info_name(CalledPredInfo),
	Goal = call(PredId, ProcId, Args, not_builtin, no,
		qualified(PredModule, PredName)) - GoalInfo.

:- pred deforest__create_deforest_call_args(list(prog_var)::in, list(type)::in,
	map(prog_var, prog_var)::in, tsubst::in,
	list(prog_var)::out, prog_varset::in, prog_varset::out,
	map(prog_var, type)::in, map(prog_var, type)::out) is det.

deforest__create_deforest_call_args([], [], _, _, [],
		VarSet, VarSet, VarTypes, VarTypes).
deforest__create_deforest_call_args([], [_|_], _, _, _, _, _, _, _) :-
	error("deforest__create_deforest_call_args: length mismatch").
deforest__create_deforest_call_args([_|_], [], _, _, _, _, _, _, _) :-
	error("deforest__create_deforest_call_args: length mismatch").
deforest__create_deforest_call_args([OldArg | OldArgs], [ArgType | ArgTypes],
		Renaming, TypeSubn, [Arg | Args], VarSet0, VarSet,
		VarTypes0, VarTypes) :-
	( map__search(Renaming, OldArg, Arg0) ->
		Arg = Arg0,
		VarSet1 = VarSet0,
		VarTypes1 = VarTypes0
	;
		% The variable is local to the call. Create a fresh variable.
		varset__new_var(VarSet0, Arg, VarSet1),
		term__apply_substitution(ArgType, TypeSubn, ArgType1),
		map__det_insert(VarTypes0, Arg, ArgType1, VarTypes1)
	),
	deforest__create_deforest_call_args(OldArgs, ArgTypes, Renaming,
		TypeSubn, Args, VarSet1, VarSet, VarTypes1, VarTypes).

%-----------------------------------------------------------------------------%

	% Combine the two goals to be deforested and the
	% goals in between into a conjunction.
:- pred deforest__create_conj(hlds_goal::in, list(hlds_goal)::in,
	maybe(hlds_goal)::in, set(prog_var)::in, hlds_goal::out) is det.

deforest__create_conj(EarlierGoal, BetweenGoals, MaybeLaterGoal,
			NonLocals, FoldGoal) :-
	( MaybeLaterGoal = yes(LaterGoal) ->
		list__append([EarlierGoal | BetweenGoals], [LaterGoal],
			DeforestConj)
	;
		DeforestConj = [EarlierGoal | BetweenGoals]
	),
	goal_list_determinism(DeforestConj, Detism),
	goal_list_instmap_delta(DeforestConj, InstMapDelta0),
	instmap_delta_restrict(InstMapDelta0, NonLocals, InstMapDelta),
	goal_list_purity(DeforestConj, Purity),
	goal_info_init(NonLocals, InstMapDelta, Detism, Purity, ConjInfo0),

	% Give the conjunction a context so that the generated predicate
	% name points to the location of the first goal.
	EarlierGoal = _ - EarlierGoalInfo,
	goal_info_get_context(EarlierGoalInfo, EarlierContext),
	goal_info_set_context(ConjInfo0, EarlierContext, ConjInfo),
	FoldGoal = conj(DeforestConj) - ConjInfo.

%-----------------------------------------------------------------------------%

	% "Round-off" some of the extra information that caused the
	% termination check to fail and/or the insts of the versions
	% not to match in an attempt to achieve folding.
:- pred deforest__try_generalisation(hlds_goal::in, list(hlds_goal)::in,
	maybe(hlds_goal)::in, hlds_goal::in, set(prog_var)::in,
	proc_pair::in, int::in, pred_proc_id::in, maybe(hlds_goal)::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__try_generalisation(EarlierGoal, BetweenGoals, MaybeLaterGoal,
		FoldGoal, ConjNonLocals, ProcPair, Size,
		CoveringPredProcId, MaybeGoal, !PDInfo, !IO) :-
	pd_debug__message("trying generalisation\n", [], !IO),
	pd_info_get_versions(!.PDInfo, VersionIndex),
	map__lookup(VersionIndex, CoveringPredProcId, Version),
	pd_info_get_module_info(!.PDInfo, ModuleInfo),
	Version = version_info(VersionGoal, _, VersionArgs,
		VersionArgTypes, VersionInstMap, _, _, _, _),
	pd_info_get_versions(!.PDInfo, Versions),
	pd_info_get_proc_info(!.PDInfo, ProcInfo),
	proc_info_vartypes(ProcInfo, VarTypes),
	(
		pd_util__goals_match(ModuleInfo, VersionGoal, VersionArgs,
			VersionArgTypes, FoldGoal, VarTypes, Renaming, _)
	->
		deforest__do_generalisation(VersionArgs, Renaming,
			VersionInstMap, EarlierGoal, BetweenGoals,
			MaybeLaterGoal, FoldGoal, ConjNonLocals, ProcPair,
			Size, CoveringPredProcId, MaybeGoal, !PDInfo, !IO)
	;
		% If the earlier goal is a generalisation of another
		% version, try matching against that. This happens
		% when attempting two deforestations in a row and
		% the first deforestation required generalisation.
		proc_info_varset(ProcInfo, VarSet),
		deforest__match_generalised_version(ModuleInfo,
			VersionGoal, VersionArgs, VersionArgTypes,
			EarlierGoal, BetweenGoals, MaybeLaterGoal,
			ConjNonLocals, VarSet, VarTypes, Versions, Renaming)
	->
		pd_debug__message("matched with generalised version\n", [],
			!IO),
		deforest__do_generalisation(VersionArgs, Renaming,
			VersionInstMap, EarlierGoal, BetweenGoals,
			MaybeLaterGoal, FoldGoal, ConjNonLocals, ProcPair,
			Size, CoveringPredProcId, MaybeGoal, !PDInfo, !IO)
	;
		pd_debug__message("goals don't match\n", [], !IO),
		MaybeGoal = no
	).

:- pred deforest__do_generalisation(list(prog_var)::in,
	map(prog_var, prog_var)::in, instmap::in, hlds_goal::in,
	list(hlds_goal)::in, maybe(hlds_goal)::in, hlds_goal::in,
	set(prog_var)::in, proc_pair::in, int::in,
	pred_proc_id::in, maybe(hlds_goal)::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__do_generalisation(VersionArgs, Renaming, VersionInstMap, EarlierGoal,
		BetweenGoals, MaybeLaterGoal, FoldGoal, ConjNonLocals,
		ProcPair, Size, Generalised, MaybeGoal, !PDInfo, !IO) :-
	pd_debug__message("goals match, trying MSG\n", [], !IO),
	pd_info_get_module_info(!.PDInfo, ModuleInfo),
	pd_info_get_instmap(!.PDInfo, InstMap0),
	instmap__lookup_vars(VersionArgs, VersionInstMap,
		VersionInsts),
	pd_util__inst_list_size(ModuleInfo, VersionInsts,
		VersionInstSizes),
	set__to_sorted_list(ConjNonLocals, ConjNonLocalsList),
	(
		% Check whether we can do a most specific
		% generalisation of insts of the non-locals.
		deforest__try_MSG(ModuleInfo, VersionInstMap,
			VersionArgs, Renaming, InstMap0, InstMap),
		instmap__lookup_vars(ConjNonLocalsList, InstMap,
			ArgInsts),
		pd_util__inst_list_size(ModuleInfo, ArgInsts,
			NewInstSizes),
		NewInstSizes < VersionInstSizes
	->
		pd_debug__message("MSG succeeded", [], !IO),
		pd_info_set_instmap(InstMap, !PDInfo),
		deforest__create_deforest_goal(EarlierGoal, BetweenGoals,
			MaybeLaterGoal, FoldGoal, ConjNonLocals, yes, ProcPair,
			Size, yes(Generalised), MaybeGoal, !PDInfo, !IO)
	;
		pd_debug__message("MSG failed\n", [], !IO),
		MaybeGoal = no
	),
	pd_info_set_instmap(InstMap0, !PDInfo).

:- pred deforest__try_MSG(module_info::in, instmap::in, list(prog_var)::in,
	map(prog_var, prog_var)::in, instmap::in, instmap::out) is semidet.

deforest__try_MSG(_, _, [], _, !InstMap).
deforest__try_MSG(ModuleInfo, VersionInstMap, [VersionArg | VersionArgs],
		Renaming, !InstMap) :-
	instmap__lookup_var(VersionInstMap, VersionArg, VersionInst),
	(
		map__search(Renaming, VersionArg, Arg),
		instmap__lookup_var(!.InstMap, Arg, VarInst),
		inst_MSG(VersionInst, VarInst, ModuleInfo, Inst)
	->
		instmap__set(!.InstMap, Arg, Inst, !:InstMap)
	;
		true
	),
	deforest__try_MSG(ModuleInfo, VersionInstMap, VersionArgs,
		Renaming, !InstMap).

%-----------------------------------------------------------------------------%

	% If the global termination check and generalisation failed and
	% the first goal in the conjunction to be specialised is a
	% generalisation of another version, try matching and generalising
	% using that (non-generalised) version.
	%
 	% This predicate maps the call to the generalised predicate back
	% onto the non-generalised version. This makes the goal match
	% with the previous conjunction, so the generalisation can be
	% reapplied to the entire conjunction.
	%
	% XXX this only undoes one level of generalisation.
:- pred deforest__match_generalised_version(module_info::in,
	hlds_goal::in, list(prog_var)::in, list(type)::in,
	hlds_goal::in, list(hlds_goal)::in, maybe(hlds_goal)::in,
	set(prog_var)::in, prog_varset::in, map(prog_var, type)::in,
	version_index::in, map(prog_var, prog_var)::out) is semidet.

deforest__match_generalised_version(ModuleInfo, VersionGoal, VersionArgs,
		VersionArgTypes, FirstGoal, BetweenGoals, MaybeLastGoal,
		ConjNonLocals, VarSet0, VarTypes0, Versions, Renaming) :-

	FirstGoal = call(FirstPredId, FirstProcId, FirstArgs, _, _, _) - _,

	%
	% Look up the version which the first goal calls.
	%
	map__search(Versions, proc(FirstPredId, FirstProcId),
		FirstVersionInfo),
	FirstVersionInfo = version_info(FirstVersionGoal, _, FirstVersionArgs,
			_,_,_,_,_, MaybeNonGeneralisedVersion),
	MaybeNonGeneralisedVersion = yes(NonGeneralisedPredProcId),
	map__from_corresponding_lists(FirstVersionArgs,
		FirstArgs, FirstRenaming0),

	goal_util__goal_vars(FirstVersionGoal, FirstVersionVars0),
	set__to_sorted_list(FirstVersionVars0, FirstVersionVars),

	module_info_pred_proc_info(ModuleInfo, FirstPredId, FirstProcId,
		_, FirstProcInfo),
	proc_info_varset(FirstProcInfo, FirstVersionVarSet),
	proc_info_vartypes(FirstProcInfo, FirstVersionVarTypes),

	goal_util__create_variables(FirstVersionVars,
		FirstVersionVarSet, FirstVersionVarTypes,
		VarSet0, VarSet, VarTypes0, VarTypes,
		FirstRenaming0, FirstRenaming),
	goal_util__must_rename_vars_in_goal(FirstVersionGoal, FirstRenaming,
		RenamedFirstVersionGoal),

	%
	% Look up the version which was generalised to create the version
	% which the first goal calls.
	%
	NonGeneralisedPredProcId = proc(NonGeneralisedPredId,
					NonGeneralisedProcId),
	goal_to_conj_list(VersionGoal, VersionGoalList),
	VersionGoalList = [call(NonGeneralisedPredId, NonGeneralisedProcId,
		_, _, _, _) - _ | _],

	%
	% Find a renaming from the argument variables of the generalised
	% version to the version which was generalised.
	%
	map__search(Versions, NonGeneralisedPredProcId,
		NonGeneralisedVersion),
	NonGeneralisedVersion = version_info(NonGeneralisedGoal, _,
		NonGeneralisedArgs, NonGeneralisedArgTypes,_,_,_,_,_),
	pd_util__goals_match(ModuleInfo, NonGeneralisedGoal,
		NonGeneralisedArgs, NonGeneralisedArgTypes,
		RenamedFirstVersionGoal, VarTypes, GeneralRenaming,
		TypeRenaming),

	module_info_pred_info(ModuleInfo, NonGeneralisedPredId,
		NonGeneralisedPredInfo),
	pred_info_arg_types(NonGeneralisedPredInfo, NonGeneralisedArgTypes),
	deforest__create_deforest_call_args(NonGeneralisedArgs,
		NonGeneralisedArgTypes, GeneralRenaming, TypeRenaming,
		NewArgs, VarSet, _, VarTypes, _),

	% Only fill in as much as pd_util__goals_match actually looks at.
	goal_info_init(GoalInfo),
	NonGeneralFirstGoal = call(NonGeneralisedPredId,
		NonGeneralisedProcId, NewArgs, not_builtin,
		no, unqualified("")) - GoalInfo,
	deforest__create_conj(NonGeneralFirstGoal, BetweenGoals, MaybeLastGoal,
		ConjNonLocals, GoalToMatch),

	%
	% Check whether the entire conjunction matches.
	%
	pd_util__goals_match(ModuleInfo, VersionGoal, VersionArgs,
		VersionArgTypes, GoalToMatch, VarTypes, Renaming, _).

%-----------------------------------------------------------------------------%

	% Work out the nonlocals of a sub-conjunction from the non-locals of
	% the entire conjunction and the goals before and after the
	% sub-conjunction. This is needed to ensure that the temporary
	% list in double_append is found to be local to the conjunction
	% and can be removed.
:- pred deforest__get_sub_conj_nonlocals(set(prog_var)::in, deforest_info::in,
	list(hlds_goal)::in, list(hlds_goal)::in, list(hlds_goal)::in,
	annotated_conj::in, set(prog_var)::out) is det.

deforest__get_sub_conj_nonlocals(NonLocals0, DeforestInfo,
		RevBeforeGoals, BeforeIrrelevant, AfterIrrelevant,
		AfterGoals0, SubConjNonLocals) :-
	DeforestInfo = deforest_info(EarlierGoal, _, BetweenGoals, LaterGoal,
		_, _),
	assoc_list__keys(AfterGoals0, AfterGoals),
	deforest__get_sub_conj_nonlocals(NonLocals0, RevBeforeGoals,
		BeforeIrrelevant, EarlierGoal, BetweenGoals, yes(LaterGoal),
		AfterIrrelevant, AfterGoals, SubConjNonLocals).

:- pred deforest__get_sub_conj_nonlocals(set(prog_var)::in,
	list(hlds_goal)::in, list(hlds_goal)::in, hlds_goal::in,
	list(hlds_goal)::in, maybe(hlds_goal)::in, list(hlds_goal)::in,
	list(hlds_goal)::in, set(prog_var)::out) is det.

deforest__get_sub_conj_nonlocals(NonLocals0, RevBeforeGoals, BeforeIrrelevant,
		EarlierGoal, BetweenGoals, MaybeLaterGoal,
		AfterIrrelevant, AfterGoals, SubConjNonLocals) :-
	AddGoalNonLocals = (pred(Goal::in, Vars0::in, Vars::out) is det :-
		Goal = _ - GoalInfo,
		goal_info_get_nonlocals(GoalInfo, GoalNonLocals),
		set__union(Vars0, GoalNonLocals, Vars)
	),
	list__foldl(AddGoalNonLocals, RevBeforeGoals, NonLocals0, NonLocals1),
	list__foldl(AddGoalNonLocals, BeforeIrrelevant,
		NonLocals1, NonLocals2),
	list__foldl(AddGoalNonLocals, AfterIrrelevant, NonLocals2, NonLocals3),
	list__foldl(AddGoalNonLocals, AfterGoals, NonLocals3, NonLocals),

	set__init(SubConjNonLocals0),
	list__foldl(AddGoalNonLocals, [EarlierGoal | BetweenGoals],
		SubConjNonLocals0, SubConjNonLocals1),
	( MaybeLaterGoal = yes(LaterGoal) ->
		call(AddGoalNonLocals, LaterGoal, SubConjNonLocals1,
			SubConjNonLocals2)
	;
		SubConjNonLocals2 = SubConjNonLocals1
	),
	set__intersect(NonLocals, SubConjNonLocals2, SubConjNonLocals).

%-----------------------------------------------------------------------------%

	% Attempt to move irrelevant goals out of the conjunction.
	% This does a safe re-ordering that is guaranteed not to require
	% rescheduling of the conjunction, since it does not reorder goals
	% that depend on each other.
	% We favor moving goals backward to avoid removing tail recursion.
:- pred deforest__reorder_conj(deforest_info::in, deforest_info::out,
	list(hlds_goal)::out, list(hlds_goal)::out, pd_info::in,
	io::di, io::uo) is det.

deforest__reorder_conj(DeforestInfo0, DeforestInfo,
		BeforeIrrelevant, AfterIrrelevant, PDInfo, !IO) :-
	pd_debug__message("Reordering conjunction\n", [], !IO),
	DeforestInfo0 = deforest_info(EarlierGoal, EarlierBranchInfo,
		BetweenGoals0, LaterGoal, LaterBranchInfo, DeforestBranches),

	pd_info_get_module_info(PDInfo, ModuleInfo),
	globals__io_lookup_bool_option(fully_strict, FullyStrict, !IO),

	deforest__move_goals(deforest__can_move_goal_backward, ModuleInfo,
		FullyStrict, BetweenGoals0, [], RevBetweenGoals1, EarlierGoal,
		[], RevBeforeIrrelevant),
	deforest__move_goals(deforest__can_move_goal_forward,
		ModuleInfo, FullyStrict, RevBetweenGoals1,
		[], BetweenGoals, LaterGoal, [], AfterIrrelevant),

	list__reverse(RevBeforeIrrelevant, BeforeIrrelevant),
	DeforestInfo = deforest_info(EarlierGoal, EarlierBranchInfo,
		BetweenGoals, LaterGoal, LaterBranchInfo, DeforestBranches).

:- pred deforest__move_goals(can_move::can_move, module_info::in, bool::in,
	hlds_goals::in, hlds_goals::in, hlds_goals::out,
	hlds_goal::in, hlds_goals::in, hlds_goals::out) is det.

deforest__move_goals(_, _, _, [], !BetweenGoals, _, !MovedGoal).
deforest__move_goals(CanMove, ModuleInfo, FullyStrict,
		[BetweenGoal | RevBetweenGoals0], !BetweenGoals, EndGoal,
		!MovedGoals) :-
	(
		call(CanMove, ModuleInfo, FullyStrict, BetweenGoal,
			[EndGoal | !.BetweenGoals])
	->
		!:MovedGoals = [BetweenGoal | !.MovedGoals]
	;
		!:BetweenGoals = [BetweenGoal | !.BetweenGoals]
	),
	deforest__move_goals(CanMove, ModuleInfo, FullyStrict,
		RevBetweenGoals0, !BetweenGoals, EndGoal, !MovedGoals).

:- type can_move == pred(module_info, bool, hlds_goal, hlds_goals).
:- mode can_move == (pred(in, in, in, in) is semidet).

	% Check all goals occurring later in the conjunction to
	% see if they depend on the current goal. A goal
	% depends on the current goal if any of the non-locals
	% of the later goal have their instantiatedness changed
	% by the current goal.
:- pred deforest__can_move_goal_forward(module_info::in, bool::in,
	hlds_goal::in, list(hlds_goal)::in) is semidet.

deforest__can_move_goal_forward(ModuleInfo, FullyStrict, ThisGoal, Goals) :-
	\+ (
		list__member(LaterGoal, Goals),
		\+ pd_util__can_reorder_goals(ModuleInfo, FullyStrict,
			ThisGoal, LaterGoal)
	).

	% Check all goals occurring earlier in the conjunction to
	% see if the current goal depends on them.
:- pred deforest__can_move_goal_backward(module_info::in, bool::in,
	hlds_goal::in, list(hlds_goal)::in) is semidet.

deforest__can_move_goal_backward(ModuleInfo, FullyStrict, ThisGoal, Goals) :-
	\+ (
		list__member(EarlierGoal, Goals),
		\+ pd_util__can_reorder_goals(ModuleInfo, FullyStrict,
			EarlierGoal, ThisGoal)
	).

%-----------------------------------------------------------------------------%

	% Tack the second goal and the goals in between onto the end
	% of each branch of the first goal, unfolding the second goal
	% in the branches which have extra information about the arguments.
:- pred deforest__push_goal_into_goal(set(prog_var)::in, set(int)::in,
	hlds_goal::in, hlds_goals::in, hlds_goal::in, hlds_goal::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__push_goal_into_goal(NonLocals, DeforestInfo, EarlierGoal,
		BetweenGoals, LaterGoal, Goal, !PDInfo, !IO) :-
	pd_info_get_instmap(!.PDInfo, InstMap0),
	EarlierGoal = EarlierGoalExpr - _,
	( EarlierGoalExpr = switch(Var1, CanFail1, Cases1) ->
		set__insert(NonLocals, Var1, CaseNonLocals),
		deforest__append_goal_to_cases(Var1, BetweenGoals, LaterGoal,
			CaseNonLocals, 1, DeforestInfo, Cases1, Cases,
			!PDInfo, !IO),
		GoalExpr = switch(Var1, CanFail1, Cases)
	; EarlierGoalExpr = if_then_else(Vars, Cond, Then0, Else0) ->
		pd_info_update_goal(Cond, !PDInfo),
		Cond = _ - CondInfo,
		goal_info_get_nonlocals(CondInfo, CondNonLocals),
		set__union(CondNonLocals, NonLocals, ThenNonLocals),
		deforest__append_goal(Then0, BetweenGoals, LaterGoal,
			ThenNonLocals, 1, DeforestInfo, Then, !PDInfo, !IO),
		pd_info_set_instmap(InstMap0, !PDInfo),
		deforest__append_goal(Else0, BetweenGoals, LaterGoal,
			NonLocals, 2, DeforestInfo, Else, !PDInfo, !IO),
		GoalExpr = if_then_else(Vars, Cond, Then, Else)
	; EarlierGoalExpr = disj(Disjuncts0) ->
		deforest__append_goal_to_disjuncts(BetweenGoals, LaterGoal,
			NonLocals, 1, DeforestInfo, Disjuncts0, Disjuncts,
			!PDInfo, !IO),
		GoalExpr = disj(Disjuncts)
	;
		error("deforest__push_goal_into_goal")
	),
	pd_info_set_instmap(InstMap0, !PDInfo),
	goal_list_instmap_delta([EarlierGoal | BetweenGoals], Delta0),
	LaterGoal = _ - LaterInfo,
	goal_info_get_instmap_delta(LaterInfo, Delta1),
	instmap_delta_apply_instmap_delta(Delta0, Delta1, test_size, Delta2),
	instmap_delta_restrict(Delta2, NonLocals, Delta),
	goal_list_determinism([EarlierGoal | BetweenGoals], Detism0),
	goal_info_get_determinism(LaterInfo, Detism1),
	det_conjunction_detism(Detism0, Detism1, Detism),
	goal_list_purity([EarlierGoal | BetweenGoals], Purity0),
	infer_goal_info_purity(LaterInfo, Purity1),
	worst_purity(Purity0, Purity1) = Purity,
	goal_info_init(NonLocals, Delta, Detism, Purity, GoalInfo),
	Goal2 = GoalExpr - GoalInfo,

	pd_info_get_module_info(!.PDInfo, ModuleInfo),
	module_info_globals(ModuleInfo, Globals),
	simplify__find_simplifications(no, Globals, Simplifications0),

	% Be a bit more aggressive with common structure elimination.
	% This helps achieve folding in some cases.
	Simplifications = [extra_common_struct | Simplifications0],
	pd_util__simplify_goal(Simplifications, Goal2, Goal3, !PDInfo),
	pd_info_set_instmap(InstMap0, !PDInfo),

	% Perform any folding which may now be possible.
	deforest__goal(Goal3, Goal, !PDInfo, !IO),
	pd_info_set_instmap(InstMap0, !PDInfo).

:- pred deforest__append_goal_to_disjuncts(hlds_goals::in, hlds_goal::in,
	set(prog_var)::in, int::in, set(int)::in,
	hlds_goals::in, hlds_goals::out, pd_info::in, pd_info::out,
	io::di, io::uo) is det.

deforest__append_goal_to_disjuncts(_, _, _, _, _, [], [], !PDInfo, !IO).
deforest__append_goal_to_disjuncts(BetweenGoals, GoalToAppend, NonLocals,
		CurrBranch, Branches, [Goal0 | Goals0], [Goal | Goals],
		!PDInfo, !IO) :-
	pd_info_get_instmap(!.PDInfo, InstMap0),
	deforest__append_goal(Goal0, BetweenGoals, GoalToAppend,
		NonLocals, CurrBranch, Branches, Goal, !PDInfo, !IO),
	NextBranch = CurrBranch + 1,
	pd_info_set_instmap(InstMap0, !PDInfo),
	deforest__append_goal_to_disjuncts(BetweenGoals, GoalToAppend,
		NonLocals, NextBranch, Branches, Goals0, Goals, !PDInfo, !IO).

:- pred deforest__append_goal_to_cases(prog_var::in, hlds_goals::in,
	hlds_goal::in, set(prog_var)::in, int::in, set(int)::in,
	list(case)::in,list(case)::out, pd_info::in, pd_info::out,
	io::di, io::uo) is det.

deforest__append_goal_to_cases(_, _, _, _, _, _, [], [], !PDInfo, !IO).
deforest__append_goal_to_cases(Var, BetweenGoals, GoalToAppend, NonLocals,
		CurrCase, Branches, [case(ConsId, Goal0) | Cases0],
		[case(ConsId, Goal) | Cases], !PDInfo, !IO) :-
	pd_info_get_instmap(!.PDInfo, InstMap0),
	pd_info_bind_var_to_functor(Var, ConsId, !PDInfo),
	deforest__append_goal(Goal0, BetweenGoals, GoalToAppend, NonLocals,
		CurrCase, Branches, Goal, !PDInfo, !IO),
	NextCase = CurrCase + 1,
	pd_info_set_instmap(InstMap0, !PDInfo),
	deforest__append_goal_to_cases(Var, BetweenGoals, GoalToAppend,
		NonLocals, NextCase, Branches, Cases0, Cases, !PDInfo, !IO).

:- pred deforest__append_goal(hlds_goal::in, hlds_goals::in,
	hlds_goal::in, set(prog_var)::in, int::in, set(int)::in,
	hlds_goal::out, pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__append_goal(Goal0, BetweenGoals, GoalToAppend0,
		NonLocals0, CurrBranch, Branches, Goal, !PDInfo, !IO) :-
	( set__member(CurrBranch, Branches) ->
		% Unfold the call.
		pd_info_get_instmap(!.PDInfo, InstMap0),
		list__foldl(pd_info_update_goal, [Goal0 | BetweenGoals],
			!PDInfo),
		deforest__goal(GoalToAppend0, GoalToAppend, !PDInfo, !IO),
		pd_info_set_instmap(InstMap0, !PDInfo)
	;
		GoalToAppend = GoalToAppend0
	),
	goal_to_conj_list(Goal0, GoalList0),
	goal_to_conj_list(GoalToAppend, GoalListToAppend),
	list__condense([GoalList0, BetweenGoals, GoalListToAppend], Goals),

	goal_list_nonlocals(Goals, SubNonLocals),
	set__intersect(NonLocals0, SubNonLocals, NonLocals),
	goal_list_instmap_delta(Goals, Delta0),
	instmap_delta_restrict(Delta0, NonLocals, Delta),
	goal_list_determinism(Goals, Detism),
	goal_list_purity(Goals, Purity),
	goal_info_init(NonLocals, Delta, Detism, Purity, GoalInfo),
	Goal = conj(Goals) - GoalInfo.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred deforest__call(pred_id::in, proc_id::in, list(prog_var)::in,
	sym_name::in, builtin_state::in, hlds_goal::in, hlds_goal::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__call(PredId, ProcId, Args, SymName, BuiltinState, Goal0, Goal,
		!PDInfo, !IO) :-
	pd_info_get_proc_arg_info(!.PDInfo, ProcArgInfos),
	pd_info_get_module_info(!.PDInfo, ModuleInfo),
	pd_info_get_instmap(!.PDInfo, InstMap),
	unqualify_name(SymName, Name),
	list__length(Args, Arity),
	Goal0 = GoalExpr0 - GoalInfo0,
	goal_info_get_context(GoalInfo0, Context),

	pd_info_get_local_term_info(!.PDInfo, LocalTermInfo0),

	pd_info_get_pred_info(!.PDInfo, PredInfo),
	globals__io_lookup_int_option(deforestation_size_threshold,
		SizeThreshold, !IO),
	pred_info_get_markers(PredInfo, CallerMarkers),
	(
		% Check for extra information to the call.
		map__search(ProcArgInfos, proc(PredId, ProcId),
			ProcArgInfo),
		ProcArgInfo = pd_branch_info(_, LeftArgs, _),
		set__member(LeftArg, LeftArgs),
		list__index1_det(Args, LeftArg, Arg),
		instmap__lookup_var(InstMap, Arg, ArgInst),
		inst_is_bound_to_functors(ModuleInfo, ArgInst, [_]),

		% We don't attempt to deforest predicates which are
		% promised pure because the extra impurity propagated
		% through the goal when such predicates are inlined
		% will defeat any attempt at deforestation.
		% XXX We should probably allow deforestation of
		% semipure goals.
		InlinePromisedPure = no,
		inlining__can_inline_proc(PredId, ProcId, BuiltinState,
			InlinePromisedPure, CallerMarkers, ModuleInfo),

		% Check the goal size.
		module_info_pred_proc_info(ModuleInfo, PredId, ProcId, _,
			CalledProcInfo),
		proc_info_goal(CalledProcInfo, CalledGoal),
		goal_size(CalledGoal, CalledGoalSize),
		( SizeThreshold = -1
		; CalledGoalSize < SizeThreshold
		)
	->
		pd_debug__message(Context,
			"Found extra information for call to %s/%i\n",
			[s(Name), i(Arity)], !IO),
		(
			pd_term__local_check(ModuleInfo, Goal0, InstMap,
				LocalTermInfo0, LocalTermInfo)
		->
			pd_debug__message(
				"Local termination check succeeded\n", [],
				!IO),
			pd_info_set_local_term_info(LocalTermInfo, !PDInfo),
			deforest__unfold_call(yes, yes, PredId, ProcId,
				Args, Goal0, Goal1, Optimized, !PDInfo, !IO),
			( Optimized = yes ->
				deforest__goal(Goal1, Goal, !PDInfo, !IO)
			;
				Goal = Goal1
			),
			pd_info_set_local_term_info(LocalTermInfo0, !PDInfo)
		;
			pd_debug__message("Local termination check failed\n",
				[], !IO),
			Goal = GoalExpr0 - GoalInfo0
		)
	;
		pd_debug__message(Context,
			"No extra information for call to %s/%i\n",
			[s(Name), i(Arity)], !IO),
		Goal = Goal0
	).

:- pred deforest__unfold_call(bool::in, bool::in, pred_id::in, proc_id::in,
	list(prog_var)::in, hlds_goal::in, hlds_goal::out, bool::out,
	pd_info::in, pd_info::out, io::di, io::uo) is det.

deforest__unfold_call(CheckImprovement, CheckVars, PredId, ProcId, Args,
		Goal0, Goal, Optimized, !PDInfo, !IO) :-
	globals__io_lookup_int_option(deforestation_vars_threshold, VarsOpt,
		!IO),
	pd_info_get_proc_info(!.PDInfo, ProcInfo0),
	proc_info_varset(ProcInfo0, VarSet0),
	varset__vars(VarSet0, Vars),
	list__length(Vars, NumVars),
	(
		%
		% Check that we haven't already got too many variables.
		%
		(
			CheckVars = no
		;
			VarsOpt = -1
		;
			VarsOpt = MaxVars,
			NumVars < MaxVars
		)
	->
		pd_info_get_pred_info(!.PDInfo, PredInfo0),
		pd_info_get_module_info(!.PDInfo, ModuleInfo0),
		module_info_pred_proc_info(ModuleInfo0, PredId, ProcId,
			CalledPredInfo, CalledProcInfo),
		pred_info_typevarset(PredInfo0, TypeVarSet0),
		pred_info_get_univ_quant_tvars(PredInfo0, UnivQVars),
		proc_info_vartypes(ProcInfo0, VarTypes0),
		proc_info_rtti_varmaps(ProcInfo0, RttiVarMaps0),
		inlining__do_inline_call(UnivQVars, Args, CalledPredInfo,
			CalledProcInfo, VarSet0, VarSet, VarTypes0, VarTypes,
			TypeVarSet0, TypeVarSet, RttiVarMaps0, RttiVarMaps,
			Goal1),
		pred_info_set_typevarset(TypeVarSet, PredInfo0, PredInfo),
		proc_info_set_varset(VarSet, ProcInfo0, ProcInfo1),
		proc_info_set_vartypes(VarTypes, ProcInfo1, ProcInfo2),
		proc_info_set_rtti_varmaps(RttiVarMaps, ProcInfo2, ProcInfo),
		pd_info_set_pred_info(PredInfo, !PDInfo),
		pd_info_set_proc_info(ProcInfo, !PDInfo),

		pd_cost__goal(Goal1, OriginalCost),
		pd_info_get_cost_delta(!.PDInfo, CostDelta0),
		pd_info_get_size_delta(!.PDInfo, SizeDelta0),
		pd_info_get_changed(!.PDInfo, Changed0),

			% update the quantification if not all the output
			% arguments are used.
		Goal1 = _ - GoalInfo1,
		goal_info_get_nonlocals(GoalInfo1, NonLocals1),
		set__list_to_set(Args, NonLocals),
		( \+ set__equal(NonLocals1, NonLocals) ->
			pd_util__requantify_goal(NonLocals, Goal1, Goal2,
				!PDInfo)
		;
			Goal2 = Goal1
		),

			% Push the extra information from the call
			% through the goal.
		pd_debug__message("Running unique modes\n", [], !IO),
		proc_info_arglives(CalledProcInfo, ModuleInfo0, ArgLives),
		get_live_vars(Args, ArgLives, LiveVars0),
		set__list_to_set(LiveVars0, LiveVars1),
		set__intersect(NonLocals, LiveVars1, LiveVars),
		pd_util__unique_modecheck_goal(LiveVars, Goal2, Goal3, Errors,
			!PDInfo, !IO),

		( Errors = [] ->
			Optimized0 = yes
		;
			% This can happen because common.m does not
			% maintain unique mode correctness. This should
			% eventually be fixed.
			Optimized0 = no
		),

		pd_debug__message("Running simplify\n", [], !IO),
		pd_info_get_module_info(!.PDInfo, ModuleInfo),
		module_info_globals(ModuleInfo, Globals),
		simplify__find_simplifications(no, Globals, Simplifications),
		pd_util__simplify_goal(Simplifications, Goal3, Goal4, !PDInfo),

		pd_info_get_cost_delta(!.PDInfo, CostDelta1),
		CostDelta = CostDelta1 - CostDelta0,
		goal_size(Goal4, GoalSize),
		pd_cost__call(CallCost),
		SizeDelta = GoalSize - CallCost,
		globals__io_lookup_int_option(deforestation_cost_factor,
			Factor, !IO),
		(
			Optimized0 = yes,
			(
				CheckImprovement = no
			;
				CheckImprovement = yes,
				% XXX Should this test Goal4? zs
				( deforest__is_simple_goal(Goal3) ->
					true
				;
					deforest__check_improvement(Factor,
						GoalSize, OriginalCost,
						CostDelta)
				)
			)
		->
			Goal = Goal4,
			pd_debug__message("inlined: cost(%i) size(%i)\n",
				[i(CostDelta), i(SizeDelta)], !IO),
			pd_info_incr_size_delta(SizeDelta, !PDInfo),
			pd_info_set_changed(yes, !PDInfo),
			Goal0 = _ - GoalInfo0,
			goal_info_get_determinism(GoalInfo0, Det0),
			Goal = _ - GoalInfo,
			goal_info_get_determinism(GoalInfo, Det),

			% Rerun determinism analysis later if
			% the determinism of any of the sub-goals
			% changes - this avoids problems with inlining
			% erroneous predicates.
			( Det = Det0 ->
				true
			;
				pd_info_set_rerun_det(yes, !PDInfo)
			),

			Optimized = yes
		;
			pd_debug__message("not enough improvement - " ++
				"not inlining: cost(%i) size(%i)\n",
				[i(CostDelta), i(SizeDelta)], !IO),
			pd_info_set_pred_info(PredInfo0, !PDInfo),
			pd_info_set_proc_info(ProcInfo0, !PDInfo),
			pd_info_set_size_delta(SizeDelta0, !PDInfo),
			pd_info_set_cost_delta(CostDelta0, !PDInfo),
			pd_info_set_changed(Changed0, !PDInfo),
			Goal = Goal0,
			Optimized = no
		)
	;
		pd_debug__message("too many variables - not inlining\n", [],
			!IO),
		Goal = Goal0,
		Optimized = no
	).

%-----------------------------------------------------------------------------%

:- pred deforest__is_simple_goal_list(list(hlds_goal)::in) is semidet.

deforest__is_simple_goal_list([]).
deforest__is_simple_goal_list([Goal | Goals]) :-
	deforest__is_simple_goal(Goal),
	deforest__is_simple_goal_list(Goals).

:- pred deforest__is_simple_goal(hlds_goal::in) is semidet.

deforest__is_simple_goal(Goal - _) :-
	(
		goal_is_atomic(Goal)
	;
		Goal = not(Goal1),
		% Handle a call or builtin + tests on the output.
		goal_to_conj_list(Goal1, GoalList1),
		deforest__is_simple_goal_list(GoalList1)
	).

%-----------------------------------------------------------------------------%

	% Very rough heuristics for checking improvement. This should lean
	% towards allowing optimizations.

:- pred deforest__check_improvement(int::in, int::in, int::in, int::in)
	is semidet.

deforest__check_improvement(_Factor, Size, OriginalCost, CostDelta) :-
	( Size =< 5 ->
			% For small increases in size,
			% accept any amount of optimization.
		CostDelta > 0
	;
		PercentChange = CostDelta * 100 // OriginalCost,
		PercentChange >= 5
	).

:- pred deforest__check_deforestation_improvement(int::in, int::in, int::in)
	is semidet.

deforest__check_deforestation_improvement(Factor, CostDelta, SizeChange) :-
	( SizeChange =< 5 ->
			% For small increases in size,
			% accept any amount of optimization.
		CostDelta > 0
	;
			% Accept the optimization if we save the equivalent
			% of a heap increment per 3 extra atomic goals.
			% Note that folding is heavily rewarded by pd_cost.m,
			% so this isn't very restrictive if a fold occurs.
		pd_cost__heap_incr(HeapCost),
		ExpectedCostDelta = 1000 * HeapCost * SizeChange // 3,
		FudgedCostDelta = CostDelta * Factor,
		FudgedCostDelta >= ExpectedCostDelta
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
