%-----------------------------------------------------------------------------%
% Copyright (C) 1994-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% unify_proc.m: 
%
%	This module encapsulates access to the proc_requests table,
%	and constructs the clauses for out-of-line complicated
%	unification procedures.
%	It also generates the code for other compiler-generated type-specific
%	predicates such as compare/3.
%
% During mode analysis, we notice each different complicated unification
% that occurs.  For each one we add a new mode to the out-of-line
% unification predicate for that type, and we record in the `proc_requests'
% table that we need to eventually modecheck that mode of the unification
% procedure.
%
% After we've done mode analysis for all the ordinary predicates, we then
% do mode analysis for the out-of-line unification procedures.  Note that
% unification procedures may call other unification procedures which have
% not yet been encountered, causing new entries to be added to the
% proc_requests table.  We store the entries in a queue and continue the
% process until the queue is empty.
%
% The same queuing mechanism is also used for procedures created by
% mode inference during mode analysis and unique mode analysis.
%
% Currently if the same complicated unification procedure is called by
% different modules, each module will end up with a copy of the code for
% that procedure.  In the long run it would be desireable to either delay
% generation of complicated unification procedures until link time (like
% Cfront does with C++ templates) or to have a smart linker which could
% merge duplicate definitions (like Borland C++).  However the amount of
% code duplication involved is probably very small, so it's definitely not
% worth worrying about right now.

% XXX What about complicated unification of an abstract type in a partially
% instantiated mode?  Currently we don't implement it correctly. Probably 
% it should be disallowed, but we should issue a proper error message.

%-----------------------------------------------------------------------------%

:- module unify_proc.

:- interface.
:- import_module hlds_module, hlds_pred, hlds_goal, hlds_data.
:- import_module mode_info, prog_data, special_pred.
:- import_module bool, std_util, io, list.

:- type proc_requests.

:- type unify_proc_id == pair(type_id, uni_mode).

	% Initialize the proc_requests table.

:- pred unify_proc__init_requests(proc_requests).
:- mode unify_proc__init_requests(out) is det.

	% Add a new request for a unification procedure to the
	% proc_requests table.

:- pred unify_proc__request_unify(unify_proc_id, determinism, term__context,
				module_info, module_info).
:- mode unify_proc__request_unify(in, in, in, in, out) is det.

	% Add a new request for a procedure (not necessarily a unification)
	% to the request queue.  Return the procedure's newly allocated
	% proc_id.  (This is used by unique_modes.m.)

:- pred unify_proc__request_proc(pred_id, list(mode), maybe(list(is_live)),
				maybe(determinism), term__context,
				module_info, proc_id, module_info).
:- mode unify_proc__request_proc(in, in, in, in, in, in, out, out) is det.

	% Do mode analysis of the queued procedures.
	% If the first argument is `unique_mode_check',
	% then also go on and do full determinism analysis and unique mode
	% analysis on them as well.

:- pred modecheck_queued_procs(how_to_check_goal, module_info, module_info,
				bool,
				io__state, io__state).
:- mode modecheck_queued_procs(in, in, out, out, di, uo) is det.

	% Given the type and mode of a unification, look up the
	% mode number for the unification proc.

:- pred unify_proc__lookup_mode_num(module_info, type_id, uni_mode,
					determinism, proc_id).
:- mode unify_proc__lookup_mode_num(in, in, in, in, out) is det.

	% Generate the clauses for one of the compiler-generated
	% special predicates (compare/3, index/3, unify, etc.)

:- pred unify_proc__generate_clause_info(special_pred_id, type,
			hlds_type_body, term__context, module_info,
			clauses_info).
:- mode unify_proc__generate_clause_info(in, in, in, in, in, out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.
:- import_module tree, map, queue, int, string, require, term.

:- import_module code_util, code_info, type_util, varset.
:- import_module mercury_to_mercury, hlds_out.
:- import_module make_hlds, prog_util, prog_out, inst_match.
:- import_module quantification, clause_to_proc.
:- import_module globals, options, modes, mode_util, (inst).
:- import_module switch_detection, cse_detection, det_analysis, unique_modes.

	% We keep track of all the complicated unification procs we need
	% by storing them in the proc_requests structure.
	% For each unify_proc_id (i.e. type & mode), we store the proc_id
	% (mode number) of the unification procedure which corresponds to
	% that mode.

:- type unify_req_map == map(unify_proc_id, proc_id).

:- type req_queue == queue(pred_proc_id).

:- type proc_requests --->
		proc_requests(
			unify_req_map,		% the assignment of proc_id
						% numbers to unify_proc_ids
			req_queue		% queue of procs we still need
						% to generate code for
		).

%-----------------------------------------------------------------------------%

unify_proc__init_requests(Requests) :-
	map__init(UnifyReqMap),
	queue__init(ReqQueue),
	Requests = proc_requests(UnifyReqMap, ReqQueue).

%-----------------------------------------------------------------------------%

	% Boring access predicates

:- pred unify_proc__get_unify_req_map(proc_requests, unify_req_map).
:- mode unify_proc__get_unify_req_map(in, out) is det.

:- pred unify_proc__get_req_queue(proc_requests, req_queue).
:- mode unify_proc__get_req_queue(in, out) is det.

:- pred unify_proc__set_unify_req_map(proc_requests, unify_req_map,
					proc_requests).
:- mode unify_proc__set_unify_req_map(in, in, out) is det.

:- pred unify_proc__set_req_queue(proc_requests, req_queue, proc_requests).
:- mode unify_proc__set_req_queue(in, in, out) is det.

unify_proc__get_unify_req_map(proc_requests(UnifyReqMap, _), UnifyReqMap).

unify_proc__get_req_queue(proc_requests(_, ReqQueue), ReqQueue).

unify_proc__set_unify_req_map(proc_requests(_, B), UnifyReqMap,
			proc_requests(UnifyReqMap, B)).

unify_proc__set_req_queue(proc_requests(A, _), ReqQueue,
			proc_requests(A, ReqQueue)).

%-----------------------------------------------------------------------------%

unify_proc__lookup_mode_num(ModuleInfo, TypeId, UniMode, Det, Num) :-
	( unify_proc__search_mode_num(ModuleInfo, TypeId, UniMode, Det, Num1) ->
		Num = Num1
	;
		error("unify_proc.m: unify_proc__search_num failed")
	).

:- pred unify_proc__search_mode_num(module_info, type_id, uni_mode, determinism,
					proc_id).
:- mode unify_proc__search_mode_num(in, in, in, in, out) is semidet.

	% Given the type, mode, and determinism of a unification, look up the
	% mode number for the unification proc.
	% We handle semidet unifications with mode (in, in) specially - they
	% are always mode zero.  Similarly for unifications of `any' insts.
	% (It should be safe to use the `in, in' mode for any insts, since
	% we assume that `ground' and `any' have the same representation.)
	% For unreachable unifications, we also use mode zero.

unify_proc__search_mode_num(ModuleInfo, TypeId, UniMode, Determinism, ProcId) :-
	UniMode = (XInitial - YInitial -> _Final),
	(
		Determinism = semidet,
		inst_is_ground_or_any(ModuleInfo, XInitial),
		inst_is_ground_or_any(ModuleInfo, YInitial)
	->
		hlds_pred__in_in_unification_proc_id(ProcId)
	;
		XInitial = not_reached
	->
		hlds_pred__in_in_unification_proc_id(ProcId)
	;
		YInitial = not_reached
	->
		hlds_pred__in_in_unification_proc_id(ProcId)
	;
		module_info_get_proc_requests(ModuleInfo, Requests),
		unify_proc__get_unify_req_map(Requests, UnifyReqMap),
		map__search(UnifyReqMap, TypeId - UniMode, ProcId)
	).

%-----------------------------------------------------------------------------%

unify_proc__request_unify(UnifyId, Determinism, Context, ModuleInfo0,
		ModuleInfo) :-
	%
	% check if this unification has already been requested
	%
	UnifyId = TypeId - UnifyMode,
	(
		unify_proc__search_mode_num(ModuleInfo0, TypeId, UnifyMode,
			Determinism, _)
	->
		ModuleInfo = ModuleInfo0
	;
		%
		% lookup the pred_id for the unification procedure
		% that we are going to generate
		%
		module_info_get_special_pred_map(ModuleInfo0, SpecialPredMap),
		map__lookup(SpecialPredMap, unify - TypeId, PredId),

		% convert from `uni_mode' to `list(mode)'
		UnifyMode = ((X_Initial - Y_Initial) -> (X_Final - Y_Final)),
		ArgModes = [(X_Initial -> X_Final), (Y_Initial -> Y_Final)],

		ArgLives = no,  % XXX ArgLives should be part of the UnifyId

		unify_proc__request_proc(PredId, ArgModes, ArgLives,
			yes(Determinism), Context, ModuleInfo0,
			ProcId, ModuleInfo1),

		%
		% save the proc_id for this unify_proc_id
		%
		module_info_get_proc_requests(ModuleInfo1, Requests0),
		unify_proc__get_unify_req_map(Requests0, UnifyReqMap0),
		map__set(UnifyReqMap0, UnifyId, ProcId, UnifyReqMap),
		unify_proc__set_unify_req_map(Requests0, UnifyReqMap, Requests),
		module_info_set_proc_requests(ModuleInfo1, Requests,
			ModuleInfo)
	).

unify_proc__request_proc(PredId, ArgModes, ArgLives, MaybeDet, Context,
		ModuleInfo0, ProcId, ModuleInfo) :-
	%
	% create a new proc_info for this procedure
	%
	module_info_preds(ModuleInfo0, Preds0),
	map__lookup(Preds0, PredId, PredInfo0),
	list__length(ArgModes, Arity),
	DeclaredArgModes = no,
	module_info_globals(ModuleInfo0, Globals),
	globals__get_args_method(Globals, ArgsMethod),
	add_new_proc(PredInfo0, Arity, ArgModes, DeclaredArgModes,
		ArgLives, MaybeDet, Context, ArgsMethod, PredInfo1, ProcId),

	%
	% copy the clauses for the procedure from the pred_info to the
	% proc_info, and mark the procedure as one that cannot
	% be processed yet
	%
	pred_info_procedures(PredInfo1, Procs1),
	pred_info_clauses_info(PredInfo1, ClausesInfo),
	map__lookup(Procs1, ProcId, ProcInfo0),
	proc_info_set_can_process(ProcInfo0, no, ProcInfo1),

	copy_clauses_to_proc(ProcId, ClausesInfo, ProcInfo1, ProcInfo2),
	map__det_update(Procs1, ProcId, ProcInfo2, Procs2),
	pred_info_set_procedures(PredInfo1, Procs2, PredInfo2),
	map__det_update(Preds0, PredId, PredInfo2, Preds2),
	module_info_set_preds(ModuleInfo0, Preds2, ModuleInfo2),

	%
	% insert the pred_proc_id into the request queue
	%
	module_info_get_proc_requests(ModuleInfo2, Requests0),
	unify_proc__get_req_queue(Requests0, ReqQueue0),
	queue__put(ReqQueue0, proc(PredId, ProcId), ReqQueue),
	unify_proc__set_req_queue(Requests0, ReqQueue, Requests),
	module_info_set_proc_requests(ModuleInfo2, Requests, ModuleInfo).

%-----------------------------------------------------------------------------%

	% XXX these belong in modes.m

modecheck_queued_procs(HowToCheckGoal, ModuleInfo0, ModuleInfo, Changed) -->
	{ module_info_get_proc_requests(ModuleInfo0, Requests0) },
	{ unify_proc__get_req_queue(Requests0, RequestQueue0) },
	(
		{ queue__get(RequestQueue0, PredProcId, RequestQueue1) }
	->
		{ unify_proc__set_req_queue(Requests0, RequestQueue1,
			Requests1) },
		{ module_info_set_proc_requests(ModuleInfo0, Requests1,
			ModuleInfo1) },
		%
		% Check that the procedure is valid (i.e. type-correct),
		% before we attempt to do mode analysis on it.
		% This check is necessary to avoid internal errors
		% caused by doing mode analysis on type-incorrect code.
		% XXX inefficient! This is O(N*M).
		%
		{ PredProcId = proc(PredId, _ProcId) },
		{ module_info_predids(ModuleInfo1, ValidPredIds) },
		( { list__member(PredId, ValidPredIds) } ->
			queued_proc_progress_message(PredProcId,
				HowToCheckGoal, ModuleInfo1),
			modecheck_queued_proc(HowToCheckGoal, PredProcId,
				ModuleInfo1, ModuleInfo2, Changed1)
		;
			{ ModuleInfo2 = ModuleInfo1 },
			{ Changed1 = no }
		),
		modecheck_queued_procs(HowToCheckGoal, ModuleInfo2, ModuleInfo,
			Changed2),
		{ bool__or(Changed1, Changed2, Changed) }
	;
		{ ModuleInfo = ModuleInfo0 },
		{ Changed = no }
	).

:- pred queued_proc_progress_message(pred_proc_id, how_to_check_goal,
			module_info, io__state, io__state).
:- mode queued_proc_progress_message(in, in, in, di, uo) is det.

queued_proc_progress_message(PredProcId, HowToCheckGoal, ModuleInfo) -->
	globals__io_lookup_bool_option(very_verbose,
		VeryVerbose),
	( { VeryVerbose = yes } ->
		%
		% print progress message
		%
		( { HowToCheckGoal = check_unique_modes(_) } ->
			io__write_string(
		    "% Analyzing modes, determinism, and unique-modes for\n% ")
		;
			io__write_string("% Mode-analyzing ")
		),
		{ PredProcId = proc(PredId, ProcId) },
		hlds_out__write_pred_proc_id(ModuleInfo, PredId, ProcId),
		io__write_string("\n")
		/*****
		{ mode_list_get_initial_insts(Modes, ModuleInfo1,
			InitialInsts) },
		io__write_string("% Initial insts: `"),
		{ varset__init(InstVarSet) },
		mercury_output_inst_list(InitialInsts, InstVarSet),
		io__write_string("'\n")
		*****/
	;
		[]
	).

:- pred modecheck_queued_proc(how_to_check_goal, pred_proc_id,
				module_info, module_info, bool,
				io__state, io__state).
:- mode modecheck_queued_proc(in, in, in, out, out, di, uo) is det.

modecheck_queued_proc(HowToCheckGoal, PredProcId, ModuleInfo0, ModuleInfo,
			Changed) -->
	{
	%
	% mark the procedure as ready to be processed
	%
	PredProcId = proc(PredId, ProcId),
	module_info_preds(ModuleInfo0, Preds0),
	map__lookup(Preds0, PredId, PredInfo0),
	pred_info_procedures(PredInfo0, Procs0),
	map__lookup(Procs0, ProcId, ProcInfo0),
	proc_info_set_can_process(ProcInfo0, yes, ProcInfo1),
	map__det_update(Procs0, ProcId, ProcInfo1, Procs1),
	pred_info_set_procedures(PredInfo0, Procs1, PredInfo1),
	map__det_update(Preds0, PredId, PredInfo1, Preds1),
	module_info_set_preds(ModuleInfo0, Preds1, ModuleInfo1)
	},

	%
	% modecheck the procedure
	%
	modecheck_proc(ProcId, PredId, ModuleInfo1, ModuleInfo2, NumErrors,
		Changed1),
	(
		{ NumErrors \= 0 }
	->
		io__set_exit_status(1),
		{ ModuleInfo = ModuleInfo2 },
		{ Changed = Changed1 }
	;
		( { HowToCheckGoal = check_unique_modes(_) } ->
			{ detect_switches_in_proc(ProcId, PredId,
						ModuleInfo2, ModuleInfo3) },
			detect_cse_in_proc(ProcId, PredId,
						ModuleInfo3, ModuleInfo4),
			determinism_check_proc(ProcId, PredId,
						ModuleInfo4, ModuleInfo5),
			unique_modes__check_proc(ProcId, PredId,
						ModuleInfo5, ModuleInfo,
						Changed2),
			{ bool__or(Changed1, Changed2, Changed) }
		;	
			{ ModuleInfo = ModuleInfo2 },
			{ Changed = Changed1 }
		)
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

unify_proc__generate_clause_info(SpecialPredId, Type, TypeBody, Context,
		ModuleInfo, ClauseInfo) :-
	unify_proc__info_init(ModuleInfo, VarTypeInfo0),
	( TypeBody = eqv_type(EqvType) ->
		HeadVarType = EqvType
	;
		HeadVarType = Type
	),
	special_pred_info(SpecialPredId, HeadVarType,
			_PredName, ArgTypes, _Modes, _Det),
	unify_proc__make_fresh_vars_from_types(ArgTypes, Args,
					VarTypeInfo0, VarTypeInfo1),
	( SpecialPredId = unify, Args = [H1, H2] ->
		unify_proc__generate_unify_clauses(TypeBody, H1, H2, Context,
					Clauses, VarTypeInfo1, VarTypeInfo)
	; SpecialPredId = index, Args = [X, Index] ->
		unify_proc__generate_index_clauses(TypeBody, X, Index, Context,
					Clauses, VarTypeInfo1, VarTypeInfo)
	; SpecialPredId = compare, Args = [Res, X, Y] ->
		unify_proc__generate_compare_clauses(TypeBody, Res, X, Y,
					Context,
					Clauses, VarTypeInfo1, VarTypeInfo)
	;
		error("unknown special pred")
	),
	unify_proc__info_extract(VarTypeInfo, VarSet, Types),
	ClauseInfo = clauses_info(VarSet, Types, Types, Args, Clauses).

:- pred unify_proc__generate_unify_clauses(hlds_type_body, var, var,
				term__context, list(clause),
				unify_proc_info, unify_proc_info).
:- mode unify_proc__generate_unify_clauses(in, in, in, in, out, in, out)
	is det.

unify_proc__generate_unify_clauses(TypeBody, H1, H2, Context, Clauses) -->
	( { TypeBody = du_type(Ctors, _, IsEnum, MaybeEqPred), IsEnum = no } ->
		( { MaybeEqPred = yes(PredName) } ->
			%
			% Just generate a call to the specified predicate,
			% which is the user-defined equality pred for this
			% type.
			% (The pred_id and proc_id will be figured
			% out by type checking and mode analysis.)
			%
			{ invalid_pred_id(PredId) },
			{ invalid_proc_id(ModeId) },
			{ Call = call(PredId, ModeId, [H1, H2], not_builtin,
					no, PredName) },
			{ goal_info_init(GoalInfo0) },
			{ goal_info_set_context(GoalInfo0, Context,
				GoalInfo) },
			{ Goal = Call - GoalInfo },
			unify_proc__quantify_clause_body([H1, H2], Goal,
				Context, Clauses)
		;
			unify_proc__generate_du_unify_clauses(Ctors, H1, H2,
				Context, Clauses)
		)
	;
		{ create_atomic_unification(H1, var(H2), Context, explicit, [],
			Goal) },
		unify_proc__quantify_clause_body([H1, H2], Goal, Context,
			Clauses)
	).

:- pred unify_proc__generate_index_clauses(hlds_type_body, var, var,
				term__context, list(clause),
				unify_proc_info, unify_proc_info).
:- mode unify_proc__generate_index_clauses(in, in, in, in, out, in, out)
	is det.

unify_proc__generate_index_clauses(TypeBody, X, Index, Context, Clauses) -->
	( { TypeBody = du_type(Ctors, _, IsEnum, MaybeEqPred), IsEnum = no } ->
		( { MaybeEqPred = yes(_) } ->
			%
			% For non-canonical types, we just give up and
			% always return -1 (meaning "index not available")
			% from index/1.
			%
			{ ArgVars = [X, Index] },
			unify_proc__build_call(
				"builtin_index_non_canonical_type",
				ArgVars, Context, Goal),
			unify_proc__quantify_clause_body(ArgVars, Goal,
				Context, Clauses)
		;
			unify_proc__generate_du_index_clauses(Ctors, X, Index,
				Context, 0, Clauses)
		)
	;
		{ ArgVars = [X, Index] },
		unify_proc__build_call("index", ArgVars, Context, Goal),
		unify_proc__quantify_clause_body(ArgVars, Goal, Context,
			Clauses)
	).

:- pred unify_proc__generate_compare_clauses(hlds_type_body, var, var, var,
				term__context,
				list(clause), unify_proc_info, unify_proc_info).
:- mode unify_proc__generate_compare_clauses(in, in, in, in, in, out, in, out)
	is det.

unify_proc__generate_compare_clauses(TypeBody, Res, H1, H2, Context, Clauses)
		-->
	( { TypeBody = du_type(Ctors, _, IsEnum, MaybeEqPred), IsEnum = no } ->
		( { MaybeEqPred = yes(_) } ->
			%
			% just generate code that will call error/1
			%
			{ ArgVars = [Res, H1, H2] },
			unify_proc__build_call(
				"builtin_compare_non_canonical_type",
				ArgVars, Context, Goal),
			unify_proc__quantify_clause_body(ArgVars, Goal,
				Context, Clauses)
		;
			unify_proc__generate_du_compare_clauses(Ctors,
				Res, H1, H2, Context, Clauses)
		)
	;
		{ ArgVars = [Res, H1, H2] },
		unify_proc__build_call("compare", ArgVars, Context, Goal),
		unify_proc__quantify_clause_body(ArgVars, Goal, Context,
			Clauses)
	).

:- pred unify_proc__quantify_clause_body(list(var), hlds_goal, term__context,
			list(clause), unify_proc_info, unify_proc_info).
:- mode unify_proc__quantify_clause_body(in, in, in, out, in, out) is det.

unify_proc__quantify_clause_body(HeadVars, Goal, Context, Clauses) -->
	unify_proc__info_get_varset(Varset0),
	unify_proc__info_get_types(Types0),
	{ implicitly_quantify_clause_body(HeadVars, Goal,
		Varset0, Types0, Body, Varset, Types, _Warnings) },
	unify_proc__info_set_varset(Varset),
	unify_proc__info_set_types(Types),
	{ Clauses = [clause([], Body, Context)] }.

%-----------------------------------------------------------------------------%

/*
	For a type such as

		type t(X) ---> a ; b(int) ; c(X); d(int, X, t)

	we want to generate code

		eq(H1, H2) :-
			(
				H1 = a,
				H2 = a
			;
				H1 = b(X1),
				H2 = b(X2),
				X1 = X2,
			;
				H1 = c(Y1),
				H2 = c(Y2),
				Y1 = Y2,
			;
				H1 = d(A1, B1, C1),
				H2 = c(A2, B2, C2),
				A1 = A2,
				B1 = B2,
				C1 = C2
			).
*/

:- pred unify_proc__generate_du_unify_clauses(list(constructor), var, var,
				term__context, list(clause),
				unify_proc_info, unify_proc_info).
:- mode unify_proc__generate_du_unify_clauses(in, in, in, in, out, in, out)
	is det.

unify_proc__generate_du_unify_clauses([], _H1, _H2, _Context, []) --> [].
unify_proc__generate_du_unify_clauses([Ctor | Ctors], H1, H2, Context,
		[Clause | Clauses]) -->
	{ Ctor = ctor(_ExistQVars, _Constraints, FunctorName, ArgTypes) },
	{ list__length(ArgTypes, FunctorArity) },
	{ FunctorConsId = cons(FunctorName, FunctorArity) },
	unify_proc__make_fresh_vars(ArgTypes, Vars1),
	unify_proc__make_fresh_vars(ArgTypes, Vars2),
	{ create_atomic_unification(
		H1, functor(FunctorConsId, Vars1), Context, explicit, [], 
		UnifyH1_Goal) },
	{ create_atomic_unification(
		H2, functor(FunctorConsId, Vars2), Context, explicit, [], 
		UnifyH2_Goal) },
	{ unify_proc__unify_var_lists(Vars1, Vars2, UnifyArgs_Goal) },
	{ GoalList = [UnifyH1_Goal, UnifyH2_Goal | UnifyArgs_Goal] },
	{ goal_info_init(GoalInfo0) },
	{ goal_info_set_context(GoalInfo0, Context,
		GoalInfo) },
	{ conj_list_to_goal(GoalList, GoalInfo, Goal) },
	unify_proc__info_get_varset(Varset0),
	unify_proc__info_get_types(Types0),
	{ implicitly_quantify_clause_body([H1, H2], Goal,
		Varset0, Types0, Body, Varset, Types, _Warnings) },
	unify_proc__info_set_varset(Varset),
	unify_proc__info_set_types(Types),
	{ Clause = clause([], Body, Context) },
	unify_proc__generate_du_unify_clauses(Ctors, H1, H2, Context, Clauses).

%-----------------------------------------------------------------------------%

/*
	For a type such as 

		:- type foo ---> f ; g(a, b, c) ; h(foo).

	we want to generate code

		index(X, Index) :-
			(
				X = f,
				Index = 0
			;
				X = g(_, _, _),
				Index = 1
			;
				X = h(_),
				Index = 2
			).
*/

:- pred unify_proc__generate_du_index_clauses(list(constructor), var, var,
				term__context, int, list(clause),
				unify_proc_info, unify_proc_info).
:- mode unify_proc__generate_du_index_clauses(in, in, in, in, in, out, in, out)
	is det.

unify_proc__generate_du_index_clauses([], _X, _Index, _Context, _N, []) --> [].
unify_proc__generate_du_index_clauses([Ctor | Ctors], X, Index, Context, N,
		[Clause | Clauses]) -->
	{ Ctor = ctor(_ExistQVars, _Constraints, FunctorName, ArgTypes) },
	{ list__length(ArgTypes, FunctorArity) },
	{ FunctorConsId = cons(FunctorName, FunctorArity) },
	unify_proc__make_fresh_vars(ArgTypes, ArgVars),
	{ create_atomic_unification(
		X, functor(FunctorConsId, ArgVars), Context, explicit, [], 
		UnifyX_Goal) },
	{ create_atomic_unification(
		Index, functor(int_const(N), []), Context, explicit, [], 
		UnifyIndex_Goal) },
	{ GoalList = [UnifyX_Goal, UnifyIndex_Goal] },
	{ goal_info_init(GoalInfo0) },
	{ goal_info_set_context(GoalInfo0, Context,
		GoalInfo) },
	{ conj_list_to_goal(GoalList, GoalInfo, Goal) },
	unify_proc__info_get_varset(Varset0),
	unify_proc__info_get_types(Types0),
	{ implicitly_quantify_clause_body([X, Index], Goal,
		Varset0, Types0, Body, Varset, Types, _Warnings) },
	unify_proc__info_set_varset(Varset),
	unify_proc__info_set_types(Types),
	{ Clause = clause([], Body, Context) },
	{ N1 is N + 1 },
	unify_proc__generate_du_index_clauses(Ctors, X, Index, Context, N1,
		Clauses).

%-----------------------------------------------------------------------------%

/*	For a type such as 

		:- type foo ---> f ; g(a) ; h(b, foo).

   	we want to generate code

		compare(Res, X, Y) :-
			index(X, X_Index),	% Call_X_Index
			index(Y, Y_Index),	% Call_Y_Index
			( X_Index < Y_Index ->	% Call_Less_Than
				Res = (<)	% Return_Less_Than
			; X_Index > Y_Index ->	% Call_Greater_Than
				Res = (>)	% Return_Greater_Than
			;
				% This disjunction is generated by
				% unify_proc__generate_compare_cases, below.
				(
					X = f, Y = f,
					R = (=)
				;
					X = g(X1), Y = g(Y1),
					compare(R, X1, Y1)
				;
					X = h(X1, X2), Y = h(Y1, Y2),
					( compare(R1, X1, Y1), R1 \= (=) ->
						R = R1
					; 
						compare(R, X2, Y2)
					)
				)
			->
				Res = R		% Return_R
			;
				compare_error 	% Abort
			).
*/

:- pred unify_proc__generate_du_compare_clauses(
			list(constructor), var, var, var, term__context,
			list(clause), unify_proc_info, unify_proc_info).
:- mode unify_proc__generate_du_compare_clauses(in, in, in, in, in,
			out, in, out) is det.

unify_proc__generate_du_compare_clauses(Ctors, Res, X, Y, Context, [Clause]) -->
	( { Ctors = [SingleCtor] } ->
		unify_proc__generate_compare_case(SingleCtor, Res, X, Y,
			Context, Goal)
	;
		unify_proc__generate_du_compare_clauses_2(Ctors, Res, X, Y,
			Context, Goal)
	),
	{ ArgVars = [Res, X, Y] },
	unify_proc__info_get_varset(Varset0),
	unify_proc__info_get_types(Types0),
	{ implicitly_quantify_clause_body(ArgVars, Goal,
		Varset0, Types0, Body, Varset, Types, _Warnings) },
	unify_proc__info_set_varset(Varset),
	unify_proc__info_set_types(Types),
	{ Clause = clause([], Body, Context) }.

:- pred unify_proc__generate_du_compare_clauses_2(
			list(constructor), var, var, var, term__context,
			hlds_goal, unify_proc_info, unify_proc_info).
:- mode unify_proc__generate_du_compare_clauses_2(in, in, in, in, in,
			out, in, out) is det.

unify_proc__generate_du_compare_clauses_2(Ctors, Res, X, Y, Context, Goal) -->
	{ construct_type(unqualified("int") - 0, [], IntType) },
	{ mercury_public_builtin_module(MercuryBuiltin) },
	{ construct_type(qualified(MercuryBuiltin, "comparison_result") - 0,
					[], ResType) },
	unify_proc__info_new_var(IntType, X_Index),
	unify_proc__info_new_var(IntType, Y_Index),
	unify_proc__info_new_var(ResType, R),

	{ goal_info_init(GoalInfo0) },
	{ goal_info_set_context(GoalInfo0, Context,
		GoalInfo) },

	unify_proc__build_call("index", [X, X_Index], Context, Call_X_Index),

	unify_proc__build_call("index", [Y, Y_Index], Context, Call_Y_Index),

	unify_proc__build_call("builtin_int_lt", [X_Index, Y_Index], Context,
		Call_Less_Than),

	unify_proc__build_call("builtin_int_gt", [X_Index, Y_Index], Context,
		Call_Greater_Than),

	{ create_atomic_unification(
		Res, functor(cons(unqualified("<"), 0), []),
			Context, explicit, [], 
		Return_Less_Than) },

	{ create_atomic_unification(
		Res, functor(cons(unqualified(">"), 0), []),
			Context, explicit, [], 
		Return_Greater_Than) },

	{ create_atomic_unification(Res, var(R), Context, explicit, [],
		Return_R) },

	unify_proc__generate_compare_cases(Ctors, R, X, Y, Context, Cases),
	{ map__init(Empty) },
	{ CasesGoal = disj(Cases, Empty) - GoalInfo },

	unify_proc__build_call("compare_error", [], Context, Abort),

	{ Goal = conj([
		Call_X_Index,
		Call_Y_Index, 
		if_then_else([], Call_Less_Than, Return_Less_Than,
		    if_then_else([], Call_Greater_Than, Return_Greater_Than,
		        if_then_else([], CasesGoal, Return_R, Abort, Empty
		        ) - GoalInfo, Empty
		    ) - GoalInfo, Empty
		) - GoalInfo
	]) - GoalInfo }.

/*	
	unify_proc__generate_compare_cases: for a type such as 

		:- type foo ---> f ; g(a) ; h(b, foo).

   	we want to generate code
		(
			X = f,		% UnifyX_Goal
			Y = f,		% UnifyY_Goal
			R = (=)		% CompareArgs_Goal
		;
			X = g(X1),	
			Y = g(Y1),
			compare(R, X1, Y1)
		;
			X = h(X1, X2),
			Y = h(Y1, Y2),
			( compare(R1, X1, Y1), R1 \= (=) ->
				R = R1
			; 
				compare(R, X2, Y2)
			)
		)
*/

:- pred unify_proc__generate_compare_cases(list(constructor), var, var, var,
			term__context, list(hlds_goal),
			unify_proc_info, unify_proc_info).
:- mode unify_proc__generate_compare_cases(in, in, in, in, in, out, in, out)
	is det.

unify_proc__generate_compare_cases([], _R, _X, _Y, _Context, []) --> [].
unify_proc__generate_compare_cases([Ctor | Ctors], R, X, Y, Context,
		[Case | Cases]) -->
	unify_proc__generate_compare_case(Ctor, R, X, Y, Context, Case),
	unify_proc__generate_compare_cases(Ctors, R, X, Y, Context, Cases).

:- pred unify_proc__generate_compare_case(constructor, var, var, var,
			term__context, hlds_goal,
			unify_proc_info, unify_proc_info).
:- mode unify_proc__generate_compare_case(in, in, in, in, in, out, in, out)
	is det.

unify_proc__generate_compare_case(Ctor, R, X, Y, Context, Case) -->
	{ Ctor = ctor(_ExistQVars, _Constraints, FunctorName, ArgTypes) },
	{ list__length(ArgTypes, FunctorArity) },
	{ FunctorConsId = cons(FunctorName, FunctorArity) },
	unify_proc__make_fresh_vars(ArgTypes, Vars1),
	unify_proc__make_fresh_vars(ArgTypes, Vars2),
	{ create_atomic_unification(
		X, functor(FunctorConsId, Vars1), Context, explicit, [], 
		UnifyX_Goal) },
	{ create_atomic_unification(
		Y, functor(FunctorConsId, Vars2), Context, explicit, [], 
		UnifyY_Goal) },
	unify_proc__compare_args(Vars1, Vars2, R, Context, CompareArgs_Goal),
	{ GoalList = [UnifyX_Goal, UnifyY_Goal, CompareArgs_Goal] },
	{ goal_info_init(GoalInfo0) },
	{ goal_info_set_context(GoalInfo0, Context,
		GoalInfo) },
	{ conj_list_to_goal(GoalList, GoalInfo, Case) }.

/*	unify_proc__compare_args: for a constructor such as

		h(list(int), foo, string)

	we want to generate code

		(
			compare(R1, X1, Y1),	% Do_Comparison
			R1 \= (=)		% Check_Not_Equal
		->
			R = R1			% Return_R1
		;
			compare(R2, X2, Y2),
			R2 \= (=)
		->
			R = R2
		; 
			compare(R, X3, Y3)	% Return_Comparison
		)

	For a constructor with no arguments, we want to generate code

		R = (=)		% Return_Equal

*/

:- pred unify_proc__compare_args(list(var), list(var), var, term__context,
				hlds_goal, unify_proc_info, unify_proc_info).
:- mode unify_proc__compare_args(in, in, in, in, out, in, out) is det.

unify_proc__compare_args([], [], R, Context, Return_Equal) -->
	{ create_atomic_unification(
		R, functor(cons(unqualified("="), 0), []),
		Context, explicit, [], 
		Return_Equal) }.
unify_proc__compare_args([X|Xs], [Y|Ys], R, Context, Goal) -->
	{ goal_info_init(GoalInfo0) },
	{ goal_info_set_context(GoalInfo0, Context, GoalInfo) },
	( { Xs = [], Ys = [] } ->
		unify_proc__build_call("compare", [R, X, Y], Context, Goal)
	;
		{ mercury_public_builtin_module(MercuryBuiltin) },
		{ construct_type(
			qualified(MercuryBuiltin, "comparison_result") - 0,
			[], ResType) },
		unify_proc__info_new_var(ResType, R1),

		unify_proc__build_call("compare", [R1, X, Y], Context,
			Do_Comparison),

		{ create_atomic_unification(
			R1, functor(cons(unqualified("="), 0), []),
			Context, explicit, [],
			Check_Equal) },
		{ Check_Not_Equal = not(Check_Equal) - GoalInfo },

		{ create_atomic_unification(
			R, var(R1), Context, explicit, [], Return_R1) },
		{ Condition = conj([Do_Comparison, Check_Not_Equal])
					- GoalInfo },
		{ map__init(Empty) },
		{ Goal = if_then_else([], Condition, Return_R1, ElseCase, Empty)
					- GoalInfo},
		unify_proc__compare_args(Xs, Ys, R, Context, ElseCase)
	).
unify_proc__compare_args([], [_|_], _, _, _) -->
	{ error("unify_proc__compare_args: length mismatch") }.
unify_proc__compare_args([_|_], [], _, _, _) -->
	{ error("unify_proc__compare_args: length mismatch") }.

%-----------------------------------------------------------------------------%

:- pred unify_proc__build_call(string, list(var), term__context, hlds_goal,
			unify_proc_info, unify_proc_info).
:- mode unify_proc__build_call(in, in, in, out, in, out) is det.

unify_proc__build_call(Name, ArgVars, Context, Goal) -->
	unify_proc__info_get_module_info(ModuleInfo),
	{ module_info_get_predicate_table(ModuleInfo, PredicateTable) },
	{ list__length(ArgVars, Arity) },
	%
	% We assume that the special preds compare/3, index/2, and unify/2
	% are the only public builtins called by code generated
	% by this module.
	%
	{ special_pred_name_arity(_, Name, _, Arity) ->
		mercury_public_builtin_module(MercuryBuiltin)
	;
		mercury_private_builtin_module(MercuryBuiltin)
	},
	{
		predicate_table_search_pred_m_n_a(PredicateTable,
			MercuryBuiltin, Name, Arity, [PredId])
	->
		IndexPredId = PredId
	;
		prog_out__sym_name_to_string(qualified(MercuryBuiltin, Name),
			QualName),
		string__int_to_string(Arity, ArityString),
		string__append_list(["unify_proc__build_call: ",
			"invalid/ambiguous pred `",
			QualName, "/", ArityString, "'"],
			ErrorMessage),
		error(ErrorMessage)
	},
	{ hlds_pred__initial_proc_id(ModeId) },
	{ Call = call(IndexPredId, ModeId, ArgVars, not_builtin,
			no, unqualified(Name)) },
	{ goal_info_init(GoalInfo0) },
	{ goal_info_set_context(GoalInfo0, Context, GoalInfo) },
	{ Goal = Call - GoalInfo }.

%-----------------------------------------------------------------------------%

:- pred unify_proc__make_fresh_vars_from_types(list(type), list(var),
					unify_proc_info, unify_proc_info).
:- mode unify_proc__make_fresh_vars_from_types(in, out, in, out) is det.

unify_proc__make_fresh_vars_from_types([], []) --> [].
unify_proc__make_fresh_vars_from_types([Type | Types], [Var | Vars]) -->
	unify_proc__info_new_var(Type, Var),
	unify_proc__make_fresh_vars_from_types(Types, Vars).

:- pred unify_proc__make_fresh_vars(list(constructor_arg), list(var),
					unify_proc_info, unify_proc_info).
:- mode unify_proc__make_fresh_vars(in, out, in, out) is det.

unify_proc__make_fresh_vars([], []) --> [].
unify_proc__make_fresh_vars([_Name - Type | Args], [Var | Vars]) -->
	unify_proc__info_new_var(Type, Var),
	unify_proc__make_fresh_vars(Args, Vars).

:- pred unify_proc__unify_var_lists(list(var), list(var), list(hlds_goal)).
:- mode unify_proc__unify_var_lists(in, in, out) is det.

unify_proc__unify_var_lists([], [_|_], _) :-
	error("unify_proc__unify_var_lists: length mismatch").
unify_proc__unify_var_lists([_|_], [], _) :-
	error("unify_proc__unify_var_lists: length mismatch").
unify_proc__unify_var_lists([], [], []).
unify_proc__unify_var_lists([Var1 | Vars1], [Var2 | Vars2], [Goal | Goals]) :-
	term__context_init(Context),
	create_atomic_unification(Var1, var(Var2), Context, explicit, [],
		Goal),
	unify_proc__unify_var_lists(Vars1, Vars2, Goals).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

% It's a pity that we don't have nested modules.

% :- begin_module unify_proc_info.
% :- interface.

:- type unify_proc_info.

:- pred unify_proc__info_init(module_info, unify_proc_info).
:- mode unify_proc__info_init(in, out) is det.

:- pred unify_proc__info_new_var(type, var, unify_proc_info, unify_proc_info).
:- mode unify_proc__info_new_var(in, out, in, out) is det.

:- pred unify_proc__info_extract(unify_proc_info, varset, map(var, type)).
:- mode unify_proc__info_extract(in, out, out) is det.

:- pred unify_proc__info_get_varset(varset, unify_proc_info, unify_proc_info).
:- mode unify_proc__info_get_varset(out, in, out) is det.

:- pred unify_proc__info_set_varset(varset, unify_proc_info, unify_proc_info).
:- mode unify_proc__info_set_varset(in, in, out) is det.

:- pred unify_proc__info_get_types(map(var, type), unify_proc_info, unify_proc_info).
:- mode unify_proc__info_get_types(out, in, out) is det.

:- pred unify_proc__info_set_types(map(var, type), unify_proc_info, unify_proc_info).
:- mode unify_proc__info_set_types(in, in, out) is det.

:- pred unify_proc__info_get_module_info(module_info,
					unify_proc_info, unify_proc_info).
:- mode unify_proc__info_get_module_info(out, in, out) is det.

%-----------------------------------------------------------------------------%

% :- implementation

:- type unify_proc_info
	--->	unify_proc_info(
			varset,
			map(var, type),
			module_info
		).

unify_proc__info_init(ModuleInfo, VarTypeInfo) :-
	varset__init(VarSet),
	map__init(Types),
	VarTypeInfo = unify_proc_info(VarSet, Types, ModuleInfo).

unify_proc__info_new_var(Type, Var,
		unify_proc_info(VarSet0, Types0, ModuleInfo),
		unify_proc_info(VarSet, Types, ModuleInfo)) :-
	varset__new_var(VarSet0, Var, VarSet),
	map__det_insert(Types0, Var, Type, Types).

unify_proc__info_extract(unify_proc_info(VarSet, Types, _ModuleInfo),
			VarSet, Types).

unify_proc__info_get_varset(VarSet, ProcInfo, ProcInfo) :-
	ProcInfo = unify_proc_info(VarSet, _Types, _ModuleInfo).

unify_proc__info_set_varset(VarSet, unify_proc_info(_VarSet, Types, ModuleInfo),
				unify_proc_info(VarSet, Types, ModuleInfo)).

unify_proc__info_get_types(Types, ProcInfo, ProcInfo) :-
	ProcInfo = unify_proc_info(_VarSet, Types, _ModuleInfo).

unify_proc__info_set_types(Types, unify_proc_info(VarSet, _Types, ModuleInfo),
				unify_proc_info(VarSet, Types, ModuleInfo)).

unify_proc__info_get_module_info(ModuleInfo, VarTypeInfo, VarTypeInfo) :-
	VarTypeInfo = unify_proc_info(_VarSet, _Types, ModuleInfo).

% :- end_module unify_proc_info.

%-----------------------------------------------------------------------------%
