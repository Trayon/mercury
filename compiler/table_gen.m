%-----------------------------------------------------------------------------%
% Copyright (C) 1997-2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Main authors: ohutch, zs.
%
% This module transforms HLDS code to implement loop detection, memoing,
% minimal model evaluation, or I/O idempotence. The transformation involves
% adding calls to predicates defined in library/table_builtin.m and in
% runtime/mercury_tabling.c.
%
% The loop detection transformation adds code to a procedure that allows
% early detection of infinite loops. If such loops are detected the program
% will terminate with a helpful error message.
%
% The memo transformation adds code that allows a procedure to "memo"
% (remember) answers once they have been generated using program clause
% resolution.
%
% The minimal model transformation changes the semantics of the procedure
% being transformed. See the PhD thesis of K. Sagonas: `The SLG-WAM: A
% Search-Efficient Engine for Well-Founded Evaluation of Normal Logic
% Programs' from SUNY at Stony Brook in 1996 for a description of
% the semantics behind the transformation. Currently only SLGd is
% implemented.
%
% The current implementation does not attempt to do anything special
% to handle cases where tabling interacts with if-then-else, solutions,
% and negated contexts in general. Such situations are not even detected,
% since the cost of such detection is quite substantial, and this cost
% would be "distributed fat". Therefore in such cases the system may
% silently produce incorrect answers. For time being, this is not a bug,
% but a missing feature :-)
%
% Example of transformation for semidet minimal_model :
%
%	Given the following code for left recursive transitive closure :
%
%	:- pred p(int, int).
%	:- mode p(in, in) is semidet.
%
%	p(A, B) :- e(A, B).
%	p(A, B) :- p(A, C), e(C, B).
%
%	The transformed code would be :
%
%	p(A, B) :-
%			% Get a handle on the table.
%		T0 = <table pointer for p/2>,
%
%			% Look up the input arguments.
%		impure table_lookup_insert_int(T0, A, T1),
%		impure table_lookup_insert_int(T1, B, T2),
%		(if
%			semipure table_simple_is_complete(T2)
%		then
%				% If the subgoal has already succeeded,
%				% just return.
%			semipure table_simple_has_succeeded(T2)
%		else
%		   	(if
%					% If we are already working on
%					% an answer for this subgoal, fail.
%				semipure table_simple_is_inactive(T2),
%
%					% Mark this subgoal as being evaluated.
%				impure table_simple_mark_as_active(T2),
%
%				(
%					%
%					% Original goals
%					%
%				)
%			then
%				impure table_simple_mark_as_succeeded(T2)
%			else
%				impure table_simple_mark_as_failed(T2),
%				fail
%			)
%		).
%
% Example of transformation for nondet minimal_model :
%
%	Given the following code for left recursive transitive closure :
%
%	:- pred p(int, int).
%	:- mode p(in, out) is nondet
%
%	p(A, B) :- e(A, B).
%	p(A, B) :- p(A, C), e(C, B).
%
%	The transformed code would be :
%
%	p(A, B) :-
%			% Get a handle on the table.
%		T0 = <table pointer for p/2>,
%
%			% Look up the input arguments, and set up the table.
%		impure table_lookup_insert_int(T0, A, T1),
%		impure table_nondet_setup(T1, T2),
%		(if
%			semipure table_nondet_is_complete(T2)
%		then
%				% Return all the answers from the complete
%				% table.
%			impure table_nondet_return_all_ans(T2, Ans),
%			impure table_restore_int_ans(Ans, 0, B)
%		else if
%			semipure table_nondet_is_active(T2)
%		then
%				% Suspend the current computational branch.
%			impure table_nondet_suspend(T2, Ans),
%			impure table_restore_int_ans(Ans, 0, B)
%		else
%		   	(
%					% Mark that this subgoal is being
%					% evaluated.
%				impure table_nondet_mark_as_active(T2),
%
%				(
%					%
%					% Original goals
%					%
%				),
%
%					% Check for duplicate answers.
%				impure table_nondet_get_ans_table(T2, AT0),
%				impure table_lookup_insert_int(AT0, B, AT1),
%
%					% The following pred is semidet;
%					% it will fail if the answer is
%					% already in the table.
%				semipure
%				    table_nondet_answer_is_not_duplicate(AT1),
%
%					% Save the new answer in the table.
%				impure table_nondet_new_ans_slot(T2, AS),
%				impure table_create_ans_block(AS, 1, AB),
%				impure table_save_int_ans(AB, 0, B)
%			;
%					% Mark this subgoal as completely
%					% evaluated, modulo any dependencies
%					% on other subgoals.
%				impure table_nondet_resume(T2),
%				fail
%			)
%		).
%
% The memo and loopcheck transformations are very similar to the above
% transformations except that for the memo case the code for handling
% loops (fail in the semi_det case, suspend in the nondet case) is changed to
% a loop check. And in the loop_check case the code for memoing answers is
% dropped and the loop handling code is modified to call an error predicate.
%
% Example of transformation for tabling I/O, for I/O primitives (i.e.
% predicates defined by pragma c_code that take an input/output pair of
% io_state arguments) that have the tabled_for_io feature:
%
%	:- pred p(int, string, io__state, io__state).
%	:- mode p(in, out, di, uo) is det.
%
%	p(A, B, S0, S) :- $pragma(...)
%
%	The transformed code would be :
%
%	p(A, B, S0, S) :-
%		(if
%				% Get the global I/O table, the global I/O
%				% counter, and the starting point for tabling
%				% I/O actions, if we are in the tabled range.
%			table_io_in_range(T0, Counter, Start)
%		then
%				% Look up the input arguments.
%			impure table_lookup_insert_start_int(T0, Counter,
%				Start, T),
%			(if
%				semipure table_io_has_occurred(T)
%			then
%				impure table_restore_string_ans(T, 0, B)
%				table_io_copy_io_state(S0, S)
%			else
%				(
%					%
%					% Call original procedure
%					%
%				),
%					% Save the answers in the table.
%				impure table_io_create_ans_block(T, 1, AnsBl),
%				impure table_save_string_ans(AnsBl, 0, B)
%			)
%		else
%			%
%			% Call original procedure
%			%
%		).
%
% Note that copying the I/O state works only because variables of type
% io__state don't actually contain any information; the information is actually
% stored in global variables. However, if this ever changes, the transformation
% can be fixed simply by changing the value of --trace-table-io-states to yes,
% which will cause such values to be tabled along with the other output
% arguments.
%
% For I/O primitives that do not have tabled_for_io, we should require that
% they do not do any I/O in their own code, meaning that all their I/O is
% inside any Mercury code they call. We can then leave such primitives
% untransformed; the I/O primitives called from the inner Mercury engine
% will do the right thing. For now, this requirement is not enforced,
% which means that enabling I/O tabling (with --trace-table-io) does not
% guarantee that *all* I/O actions are tabled. This can cause inconsistent
% behavior after retry commands in mdb. This is the reason why retry across
% I/O is experimental for now.
%
% The reason why we require I/O primitives to be marked manually by a
% programmer with the tabled_for_io feature is to get the programmer to make
% sure that the primitive meets the requirement. Unfortunately, this cannot be
% automated, since automation would require analysis of arbitrary C code.
%
%-----------------------------------------------------------------------------%

:- module table_gen.

:- interface.

:- import_module hlds_module.

:- pred table_gen__process_module(module_info::in, module_info::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module hlds_out, prog_out.
:- import_module hlds_pred, instmap, polymorphism.
:- import_module code_aux, det_analysis, follow_code, goal_util, const_prop.
:- import_module hlds_module, hlds_goal, hlds_data, (inst), inst_match.
:- import_module globals, options, passes_aux, prog_data, mode_util, type_util.
:- import_module code_util, quantification, modes, purity, prog_util.
:- import_module code_model.

:- import_module term, varset.
:- import_module bool, list, set, map, require, std_util, int.
:- import_module assoc_list, string, llds.

%-----------------------------------------------------------------------------%

	% NOTE: following preds seem to duplicate the code in passes_aux.m.
	% The reason for this duplication is that this module needs a variant
	% of this code that is able to handle passing a module_info to
	% polymorphism and getting an updated module_info back.
table_gen__process_module(Module0, Module) :-
	module_info_preds(Module0, Preds0),
	map__keys(Preds0, PredIds),
	table_gen__process_preds(PredIds, Module0, Module).

:- pred table_gen__process_preds(list(pred_id)::in, module_info::in,
	module_info::out) is det.

table_gen__process_preds([], Module, Module).
table_gen__process_preds([PredId | PredIds], Module0, Module) :-
	table_gen__process_pred(PredId, Module0, Module1),
	table_gen__process_preds(PredIds, Module1, Module).

:- pred table_gen__process_pred(pred_id::in, module_info::in, module_info::out)
	is det.

table_gen__process_pred(PredId, Module0, Module) :-
	module_info_pred_info(Module0, PredId, PredInfo),
	pred_info_procids(PredInfo, ProcIds),
	table_gen__process_procs(PredId, ProcIds, Module0, Module).

:- pred table_gen__process_procs(pred_id::in, list(proc_id)::in,
	module_info::in, module_info::out) is det.

table_gen__process_procs(_PredId, [], Module, Module).
table_gen__process_procs(PredId, [ProcId | ProcIds], Module0,
		Module) :-
	module_info_preds(Module0, PredTable),
	map__lookup(PredTable, PredId, PredInfo),
	pred_info_procedures(PredInfo, ProcTable),
	map__lookup(ProcTable, ProcId, ProcInfo0),

	proc_info_eval_method(ProcInfo0, EvalMethod),

	( eval_method_requires_tabling_transform(EvalMethod) = yes ->
		table_gen__process_proc(EvalMethod, PredId, ProcId, ProcInfo0,
			PredInfo, Module0, Module1)
	;
		module_info_globals(Module0, Globals),
		globals__lookup_bool_option(Globals, trace_table_io, yes),
		proc_info_has_io_state_pair(Module0, ProcInfo0,
			_InArgNum, _OutArgNum),
		proc_info_interface_code_model(ProcInfo0, model_det),
		proc_info_goal(ProcInfo0, BodyGoal),
		some [SubGoal] (
			goal_contains_goal(BodyGoal, SubGoal),
			SubGoal = foreign_proc(Attrs, _,_,_,_,_,_)
				- _,
			tabled_for_io(Attrs, tabled_for_io)
		)
	->
		proc_info_set_eval_method(ProcInfo0, eval_table_io, ProcInfo1),
		table_gen__process_proc(eval_table_io, PredId, ProcId,
			ProcInfo1, PredInfo, Module0, Module1)
	;
		Module1 = Module0
	),

	table_gen__process_procs(PredId, ProcIds, Module1, Module).

%-----------------------------------------------------------------------------%

:- pred table_gen__process_proc(eval_method::in, pred_id::in, proc_id::in,
	proc_info::in, pred_info::in, module_info::in, module_info::out)
	is det.

table_gen__process_proc(EvalMethod, PredId, ProcId, ProcInfo0, PredInfo0,
		Module0, Module) :-
	table_info_init(Module0, PredInfo0, ProcInfo0, TableInfo0),

	% grab the appropriate fields from the pred_info and proc_info
	proc_info_interface_determinism(ProcInfo0, Detism),
	determinism_to_code_model(Detism, CodeModel),
	proc_info_headvars(ProcInfo0, HeadVars),
	proc_info_varset(ProcInfo0, VarSet0),
	proc_info_vartypes(ProcInfo0, VarTypes0),
	proc_info_goal(ProcInfo0, OrigGoal),
	proc_info_argmodes(ProcInfo0, ArgModes),

	( EvalMethod = eval_table_io ->
		module_info_globals(Module0, Globals),
		globals__lookup_bool_option(Globals, trace_table_io_states,
			TableIoStates),
		table_gen__create_new_io_goal(OrigGoal, TableIoStates,
			HeadVars, ArgModes, VarTypes0, VarTypes,
			VarSet0, VarSet, TableInfo0, TableInfo, Goal),
		MaybeCallTableTip = no
	;
		(
			CodeModel = model_det,
			table_gen__create_new_det_goal(EvalMethod, Detism,
				OrigGoal, PredId, ProcId, HeadVars, ArgModes,
				VarTypes0, VarTypes, VarSet0, VarSet,
				TableInfo0, TableInfo, CallTableTip, Goal),
			MaybeCallTableTip = yes(CallTableTip)
		;
			CodeModel = model_semi,
			table_gen__create_new_semi_goal(EvalMethod, Detism,
				OrigGoal, PredId, ProcId, HeadVars, ArgModes,
				VarTypes0, VarTypes, VarSet0, VarSet,
				TableInfo0, TableInfo, CallTableTip, Goal),
			MaybeCallTableTip = yes(CallTableTip)
		;
			CodeModel = model_non,
			table_gen__create_new_non_goal(EvalMethod, Detism,
				OrigGoal, PredId, ProcId, HeadVars, ArgModes,
				VarTypes0, VarTypes, VarSet0, VarSet,
				TableInfo0, TableInfo, CallTableTip, Goal),
			MaybeCallTableTip = yes(CallTableTip)
		)
	),

	table_info_extract(TableInfo, Module1, PredInfo1, ProcInfo1),

	% set the new values of the fields in proc_info and pred_info
	% and save in the module info
	proc_info_set_goal(ProcInfo1, Goal, ProcInfo2),
	proc_info_set_varset(ProcInfo2, VarSet, ProcInfo3),
	proc_info_set_vartypes(ProcInfo3, VarTypes, ProcInfo4),
	proc_info_set_call_table_tip(ProcInfo4, MaybeCallTableTip, ProcInfo5),

	% Some of the instmap_deltas generated in this module
	% are pretty dodgy (especially those for if-then-elses), so
	% recompute them here.

	RecomputeAtomic = no,
	recompute_instmap_delta_proc(RecomputeAtomic, ProcInfo5, ProcInfo,
		Module1, Module2),

	pred_info_procedures(PredInfo1, ProcTable1),
	map__det_update(ProcTable1, ProcId, ProcInfo, ProcTable),
	pred_info_set_procedures(PredInfo1, ProcTable, PredInfo2),
	repuritycheck_proc(Module2, proc(PredId, ProcId), PredInfo2, PredInfo),
	module_info_preds(Module2, PredTable1),
	map__det_update(PredTable1, PredId, PredInfo, PredTable),
	module_info_set_preds(Module2, PredTable, Module).

%-----------------------------------------------------------------------------%

		%
		% Transform procedures that do I/O.
		%

:- pred table_gen__create_new_io_goal(hlds_goal::in, bool::in,
	list(prog_var)::in, list(mode)::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	hlds_goal::out) is det.

table_gen__create_new_io_goal(OrigGoal, TableIoStates, HeadVars, HeadVarModes,
		VarTypes0, VarTypes, VarSet0, VarSet, TableInfo0, TableInfo,
		Goal) :-
	OrigGoal = _ - OrigGoalInfo,
	goal_info_get_nonlocals(OrigGoalInfo, OrigNonLocals),
	goal_info_get_context(OrigGoalInfo, Context),

	table_info_get_module_info(TableInfo0, Module),

	get_input_output_vars(HeadVars, HeadVarModes, Module, InputVars,
		OutputVars),
	(
		TableIoStates = yes,
		IoStateAssignToVars = [],
		SavedOutputVars = OutputVars
	;
		TableIoStates = no,
		list__filter(table_gen__var_is_io_state(VarTypes0),
			OutputVars, IoStateAssignToVars, SavedOutputVars)
	),

	generate_new_table_var("TableVar0", VarTypes0, VarTypes1,
		VarSet0, VarSet1, TableVar0),
	generate_new_table_var("CounterVar", VarTypes1, VarTypes2,
		VarSet1, VarSet2, CounterVar),
	generate_new_table_var("StartVar", VarTypes2, VarTypes3,
		VarSet2, VarSet3, StartVar),
	generate_call("table_io_in_range", [TableVar0, CounterVar, StartVar],
		semidet, yes(impure), [TableVar0 - ground(shared, none),
		CounterVar - ground(shared, none),
		StartVar - ground(shared, none)],
		Module, Context, InRangeGoal),

	generate_new_table_var("TableVar", VarTypes3, VarTypes4,
		VarSet3, VarSet4, TableVar),
	generate_call("table_lookup_insert_start_int",
		[TableVar0, StartVar, CounterVar, TableVar],
		det, yes(impure), [TableVar - ground(unique, none)],
		Module, Context, LookupGoal),

	generate_call("table_io_has_occurred", [TableVar],
		semidet, yes(semipure), [], Module, Context, OccurredGoal),

	generate_restore_goal(SavedOutputVars, TableVar, Module, Context,
		VarTypes4, VarTypes6, VarSet4, VarSet6, RestoreAnsGoal0),

	list__filter(table_gen__var_is_io_state(VarTypes), InputVars,
		IoStateAssignFromVars, _SavedInputVars),
	(
		TableIoStates = yes,
		RestoreAnsGoal = RestoreAnsGoal0
	;
		TableIoStates = no,
		(
			IoStateAssignFromVars = [IoStateAssignFromVarPrime],
			IoStateAssignToVars = [IoStateAssignToVarPrime]
		->
			IoStateAssignFromVar = IoStateAssignFromVarPrime,
			IoStateAssignToVar = IoStateAssignToVarPrime
		;
			% The call to proc_info_has_io_state_pair in 
			% table_gen__process_procs should ensure that we
			% never get here.
			error("create_new_io_goal: one in / one out violation")
		),

		generate_call("table_io_copy_io_state",
			[IoStateAssignFromVar, IoStateAssignToVar], det, no,
			[IoStateAssignFromVar - ground(clobbered, none),
			IoStateAssignToVar - ground(unique, none)],
			Module, Context, IoStateAssignGoal),

		RestoreAnsGoalEx = conj([RestoreAnsGoal0, IoStateAssignGoal]),
		create_instmap_delta([RestoreAnsGoal0, IoStateAssignGoal],
			RestoreAnsInstMapDelta0),
		RestoreAnsGoal0 = _ - RestoreAnsGoal0Info,
		goal_info_get_nonlocals(RestoreAnsGoal0Info,
			RestoreAns0NonLocals),
		set__insert_list(RestoreAns0NonLocals,
			[IoStateAssignFromVar, IoStateAssignToVar],
			RestoreAnsNonLocals),
		instmap_delta_restrict(RestoreAnsInstMapDelta0,
			RestoreAnsNonLocals, RestoreAnsInstMapDelta),
		init_goal_info(RestoreAnsNonLocals, RestoreAnsInstMapDelta,
			det, Context, RestoreAnsGoalInfo),
		RestoreAnsGoal = RestoreAnsGoalEx - RestoreAnsGoalInfo
	),
	generate_save_goal(OutputVars, TableVar, Context, VarTypes6, VarTypes,
		VarSet6, VarSet, TableInfo0, TableInfo, SaveAnsGoal),

	CallSaveAnsGoalEx = conj([OrigGoal, SaveAnsGoal]),
	create_instmap_delta([OrigGoal, SaveAnsGoal], CallSaveAnsInstMapDelta0),
	set__insert(OrigNonLocals, TableVar, CallSaveAnsNonLocals),
	instmap_delta_restrict(CallSaveAnsInstMapDelta0,
		CallSaveAnsNonLocals, CallSaveAnsInstMapDelta),
	init_goal_info(CallSaveAnsNonLocals, CallSaveAnsInstMapDelta, det,
		Context, CallSaveAnsGoalInfo),
	CallSaveAnsGoal = CallSaveAnsGoalEx - CallSaveAnsGoalInfo,

	map__init(StoreMap),
	GenIfNecGoalEx = if_then_else([], OccurredGoal,
		RestoreAnsGoal, CallSaveAnsGoal, StoreMap),
	create_instmap_delta([OccurredGoal, RestoreAnsGoal,
		CallSaveAnsGoal], GenIfNecInstMapDelta0),
	set__insert(OrigNonLocals, TableVar, GenIfNecNonLocals),
	instmap_delta_restrict(GenIfNecInstMapDelta0, GenIfNecNonLocals,
		GenIfNecInstMapDelta),
	init_goal_info(GenIfNecNonLocals, GenIfNecInstMapDelta, det, Context,
		GenIfNecGoalInfo),
	GenIfNecGoal = GenIfNecGoalEx - GenIfNecGoalInfo,

	CheckAndGenAnsGoalEx = conj([LookupGoal, GenIfNecGoal]),
	create_instmap_delta([LookupGoal, GenIfNecGoal],
		CheckAndGenAnsInstMapDelta0),
	set__insert_list(OrigNonLocals, [TableVar0, CounterVar, StartVar],
		CheckAndGenAnsNonLocals),
	instmap_delta_restrict(CheckAndGenAnsInstMapDelta0,
		CheckAndGenAnsNonLocals, CheckAndGenAnsInstMapDelta),
	init_goal_info(CheckAndGenAnsNonLocals, CheckAndGenAnsInstMapDelta,
		det, Context, CheckAndGenAnsGoalInfo),
	CheckAndGenAnsGoal = CheckAndGenAnsGoalEx - CheckAndGenAnsGoalInfo,

	BodyGoalEx = if_then_else([], InRangeGoal, CheckAndGenAnsGoal,
		OrigGoal, StoreMap),
	create_instmap_delta([InRangeGoal, CheckAndGenAnsGoal, OrigGoal],
		BodyInstMapDelta0),
	instmap_delta_restrict(BodyInstMapDelta0, OrigNonLocals,
		BodyInstMapDelta),
	init_goal_info(OrigNonLocals, BodyInstMapDelta, det, Context,
		BodyGoalInfo),
	Goal = BodyGoalEx - BodyGoalInfo.

		%
		% Transform deterministic procedures.
		%
:- pred table_gen__create_new_det_goal(eval_method::in, determinism::in,
	hlds_goal::in, pred_id::in, proc_id::in, list(prog_var)::in,
	list(mode)::in, map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	prog_var::out, hlds_goal::out) is det.

table_gen__create_new_det_goal(EvalMethod, Detism, OrigGoal, PredId, ProcId,
		HeadVars, HeadVarModes, VarTypes0, VarTypes,
		VarSet0, VarSet, TableInfo0, TableInfo, TableVar, Goal) :-
	% even if the original goal doesn't use all of the headvars,
	% the code generated by the tabling transformation does,
	% so we need to compute the nonlocals from the headvars rather
	% than getting it from the nonlocals field in the original goal
	set__list_to_set(HeadVars, OrigNonLocals),
	OrigGoal = _ - OrigGoalInfo,
	goal_info_get_instmap_delta(OrigGoalInfo, OrigInstMapDelta),
	goal_info_get_context(OrigGoalInfo, Context),

	table_info_get_module_info(TableInfo0, Module),

	get_input_output_vars(HeadVars, HeadVarModes, Module, InputVars,
		OutputVars),

	generate_simple_lookup_goal(InputVars, PredId, ProcId, Context,
		VarTypes0, VarTypes1, VarSet0, VarSet1, TableInfo0, TableInfo1,
		TableVar, LookUpGoal),
	generate_call("table_simple_is_complete", [TableVar], semidet,
		yes(semipure), [], Module, Context, CompleteCheckGoal),
	generate_save_goal(OutputVars, TableVar, Context, VarTypes1, VarTypes2,
		VarSet1, VarSet2, TableInfo1, TableInfo, SaveAnsGoal0),
	generate_restore_goal(OutputVars, TableVar, Module, Context,
		VarTypes2, VarTypes3, VarSet2, VarSet3, RestoreAnsGoal0),
	generate_call("table_simple_mark_as_inactive", [TableVar], det,
		yes(impure), [], Module, Context, MarkAsInactiveGoal),
	generate_loop_error_goal(TableInfo, Context, VarTypes3, VarTypes,
		VarSet3, VarSet, LoopErrorGoal),
	( Detism = erroneous ->
		% In this case, the RestoreAnsGoal will never be reached,
		% but to ensure that the generated code is determinism-correct,
		% we need to make sure that RestoreAnsGoal's determinism is
		% erroneous.  So we use the LoopErrorGoal (which calls error/1)
		% rather than RestoreAnsGoal0.
		RestoreAnsGoal = LoopErrorGoal
	;
		RestoreAnsGoal = RestoreAnsGoal0
	),

	set__insert(OrigNonLocals, TableVar, GenAnsNonLocals),

	( EvalMethod = eval_loop_check ->
		SaveAnsGoal = MarkAsInactiveGoal
	; EvalMethod = eval_memo ->
		SaveAnsGoal = SaveAnsGoal0
	;
		error(
    "table_gen__create_new_det_goal: unsupported evaluation model")
	),

	generate_call("table_simple_is_active", [TableVar], semidet,
		yes(semipure), [], Module, Context, ActiveCheckGoal),
	generate_call("table_simple_mark_as_active", [TableVar], det,
		yes(impure), [], Module, Context, MarkAsActiveGoal),

	NoLoopGenAnsGoalEx = conj([MarkAsActiveGoal, OrigGoal, SaveAnsGoal]),
	create_instmap_delta([MarkAsActiveGoal, OrigGoal, SaveAnsGoal],
		NoLoopGenInstMapDelta0),
	instmap_delta_restrict(NoLoopGenInstMapDelta0, GenAnsNonLocals,
		NoLoopGenInstMapDelta),
	init_goal_info(GenAnsNonLocals, NoLoopGenInstMapDelta, det, Context,
		NoLoopGenGoalInfo),
	NoLoopGenAnsGoal = NoLoopGenAnsGoalEx - NoLoopGenGoalInfo,

	map__init(StoreMap),
	GenAnsGoalEx = if_then_else([], ActiveCheckGoal,
		LoopErrorGoal, NoLoopGenAnsGoal, StoreMap),
	create_instmap_delta([ActiveCheckGoal, LoopErrorGoal,
		NoLoopGenAnsGoal], GenAnsInstMapDelta0),
	instmap_delta_restrict(GenAnsInstMapDelta0, GenAnsNonLocals,
		GenAnsInstMapDelta),
	init_goal_info(GenAnsNonLocals, GenAnsInstMapDelta, det, Context,
		GenAnsGoalInfo),

	GenAnsGoal = GenAnsGoalEx - GenAnsGoalInfo,

	ITEGoalEx = if_then_else([], CompleteCheckGoal, RestoreAnsGoal,
		GenAnsGoal, StoreMap),
	create_instmap_delta([CompleteCheckGoal, RestoreAnsGoal, GenAnsGoal],
		ITEInstMapDelta0),
	instmap_delta_restrict(ITEInstMapDelta0, GenAnsNonLocals,
		ITEInstMapDelta),
	init_goal_info(GenAnsNonLocals, ITEInstMapDelta, det, Context,
		ITEGoalInfo),
	ITEGoal = ITEGoalEx - ITEGoalInfo,

	GoalEx = conj([LookUpGoal, ITEGoal]),
	init_goal_info(OrigNonLocals, OrigInstMapDelta, det, Context,
		GoalInfo),

	Goal = GoalEx - GoalInfo.

%-----------------------------------------------------------------------------%

		%
		% Transform semi deterministic procedures
		%
:- pred table_gen__create_new_semi_goal(eval_method::in, determinism::in,
	hlds_goal::in, pred_id::in, proc_id::in, list(prog_var)::in,
	list(mode)::in, map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	prog_var::out, hlds_goal::out) is det.

table_gen__create_new_semi_goal(EvalMethod, Detism, OrigGoal, PredId, ProcId,
		HeadVars, HeadVarModes, VarTypes0, VarTypes,
		VarSet0, VarSet, TableInfo0, TableInfo, TableVar, Goal) :-
	% even if the original goal doesn't use all of the headvars,
	% the code generated by the tabling transformation does,
	% so we need to compute the nonlocals from the headvars rather
	% than getting it from the nonlocals field in the original goal
	set__list_to_set(HeadVars, OrigNonLocals),
	OrigGoal = _ - OrigGoalInfo,
	goal_info_get_instmap_delta(OrigGoalInfo, OrigInstMapDelta),
	goal_info_get_context(OrigGoalInfo, Context),

	table_info_get_module_info(TableInfo0, Module),
	get_input_output_vars(HeadVars, HeadVarModes, Module, InputVars,
		OutputVars),

	generate_simple_lookup_goal(InputVars, PredId, ProcId, Context,
		VarTypes0, VarTypes1, VarSet0, VarSet1, TableInfo0, TableInfo1,
		TableVar, LookUpGoal),
	generate_call("table_simple_is_complete", [TableVar], semidet,
		yes(semipure), [], Module, Context, CompleteCheckGoal),
	generate_save_goal(OutputVars, TableVar, Context, VarTypes1, VarTypes2,
		VarSet1, VarSet2, TableInfo1, TableInfo, SaveAnsGoal0),
	generate_restore_goal(OutputVars, TableVar, Module, Context,
		VarTypes2, VarTypes3, VarSet2, VarSet3, RestoreTrueAnsGoal),
	generate_loop_error_goal(TableInfo, Context,
		VarTypes3, VarTypes, VarSet3, VarSet, LoopErrorGoal),
	generate_call("table_simple_mark_as_failed", [TableVar],
		det, yes(impure), [], Module, Context, MarkAsFailedGoal0),
	append_fail(MarkAsFailedGoal0, MarkAsFailedGoal),
	generate_call("table_simple_has_succeeded", [TableVar], semidet,
		yes(semipure), [], Module, Context, HasSucceededCheckGoal),
	generate_call("table_simple_mark_as_inactive", [TableVar],
		det, yes(impure), [], Module, Context, MarkAsInactiveGoal),

	set__insert(OrigNonLocals, TableVar, GenAnsNonLocals),

	map__init(StoreMap),
	(
		(
			EvalMethod = eval_loop_check
		;
			EvalMethod = eval_memo
		)
	->
		(
			EvalMethod = eval_loop_check
		->
			SaveAnsGoal = MarkAsInactiveGoal
		;
			SaveAnsGoal = SaveAnsGoal0
		),
		generate_call("table_simple_is_active", [TableVar], semidet,
			yes(semipure), [], Module, Context, ActiveCheckGoal),
		generate_call("table_simple_mark_as_active", [TableVar], det,
			yes(impure), [], Module, Context, MarkAsActiveGoal),

		NoLoopGenAnsGoalEx = conj([MarkAsActiveGoal, OrigGoal]),
		create_instmap_delta([MarkAsActiveGoal, OrigGoal],
			NoLoopGenInstMapDelta0),
		instmap_delta_restrict(NoLoopGenInstMapDelta0, GenAnsNonLocals,
			NoLoopGenInstMapDelta),
		init_goal_info(GenAnsNonLocals, NoLoopGenInstMapDelta, semidet,
			Context, NoLoopGenGoalInfo),
		NoLoopGenAnsGoal = NoLoopGenAnsGoalEx - NoLoopGenGoalInfo,

		GenTrueAnsGoalEx = if_then_else([], ActiveCheckGoal,
			LoopErrorGoal, NoLoopGenAnsGoal, StoreMap),
		create_instmap_delta([ActiveCheckGoal, LoopErrorGoal,
			NoLoopGenAnsGoal], GenTrueAnsInstMapDelta0),
		instmap_delta_restrict(GenTrueAnsInstMapDelta0,
			GenAnsNonLocals, GenTrueAnsInstMapDelta),
		init_goal_info(GenAnsNonLocals, GenTrueAnsInstMapDelta,
			semidet, Context, GenTrueAnsGoalInfo),

		GenTrueAnsGoal = GenTrueAnsGoalEx - GenTrueAnsGoalInfo
	;
		EvalMethod = eval_minimal
	->
		SaveAnsGoal = SaveAnsGoal0,

		generate_call("table_simple_is_inactive", [TableVar], semidet,
			yes(semipure), [], Module, Context, InactiveCheckGoal),

		generate_call("table_simple_mark_as_active", [TableVar], det,
			yes(impure), [], Module, Context, MarkAsActiveGoal),

		GenTrueAnsGoalEx = conj([InactiveCheckGoal,
			MarkAsActiveGoal, OrigGoal]),

		create_instmap_delta([InactiveCheckGoal, MarkAsActiveGoal,
			OrigGoal, SaveAnsGoal], GenTrueAnsInstMapDelta0),
		instmap_delta_restrict(GenTrueAnsInstMapDelta0,
			GenAnsNonLocals, GenTrueAnsInstMapDelta),
		init_goal_info(GenAnsNonLocals, GenTrueAnsInstMapDelta,
			semidet, Context, GenTrueAnsGoalInfo),

		GenTrueAnsGoal = GenTrueAnsGoalEx - GenTrueAnsGoalInfo
	;
		error(
    "table_gen__create_new_semi_goal: unsupported evaluation model")
	),

	( Detism = failure ->
		% We need to treat this case specially,
		% otherwise the code that we generate would not
		% be statically determinism-correct: there would
		% be a path through the procedure which determinism
		% analysis thinks might succeed.  In fact that path
		% would never be executed, but if this case were not
		% treated specially, the determinism analysis algorithm
		% could not prove that.  So to ensure that the generated
		% code is determinism-correct, we replace the bit which
		% retrieves an answer from the table with an
		% explicit `fail'.
		fail_goal(Context, RestoreAnsGoal)
	;
		RestAnsGoalEx =
			conj([HasSucceededCheckGoal, RestoreTrueAnsGoal]),
		set__singleton_set(RestNonLocals0, TableVar),
		set__insert_list(RestNonLocals0, OutputVars, RestNonLocals),
		create_instmap_delta([HasSucceededCheckGoal,
			RestoreTrueAnsGoal], RestInstMapDelta0),
		instmap_delta_restrict(RestInstMapDelta0, RestNonLocals,
			RestInstMapDelta),
		init_goal_info(RestNonLocals, RestInstMapDelta, semidet,
			Context, RestAnsGoalInfo),
		RestoreAnsGoal = RestAnsGoalEx - RestAnsGoalInfo
	),

	GenAnsGoalEx = if_then_else([], GenTrueAnsGoal, SaveAnsGoal,
		MarkAsFailedGoal, StoreMap),
	create_instmap_delta([GenTrueAnsGoal, SaveAnsGoal, MarkAsFailedGoal],
		GenAnsGoalInstMapDelta0),
	instmap_delta_restrict(GenAnsGoalInstMapDelta0, GenAnsNonLocals,
		GenAnsGoalInstMapDelta),
	init_goal_info(GenAnsNonLocals, GenAnsGoalInstMapDelta, semidet,
		Context, GenAnsGoalInfo),
	GenAnsGoal = GenAnsGoalEx - GenAnsGoalInfo,

	ITEGoalEx = if_then_else([], CompleteCheckGoal, RestoreAnsGoal,
		GenAnsGoal, StoreMap),
	create_instmap_delta([CompleteCheckGoal, RestoreAnsGoal, GenAnsGoal],
		ITEInstMapDelta0),
	instmap_delta_restrict(ITEInstMapDelta0, GenAnsNonLocals,
		ITEInstMapDelta),
	init_goal_info(GenAnsNonLocals, ITEInstMapDelta, semidet,
		Context, ITEGoalInfo),
	ITEGoal = ITEGoalEx - ITEGoalInfo,

	GoalEx = conj([LookUpGoal, ITEGoal]),
	init_goal_info(OrigNonLocals, OrigInstMapDelta, semidet, Context,
		GoalInfo),

	Goal = GoalEx - GoalInfo.

%-----------------------------------------------------------------------------%

		%
		% Transform non deterministic procedures
		%
:- pred table_gen__create_new_non_goal(eval_method::in, determinism::in,
	hlds_goal::in, pred_id::in, proc_id::in, list(prog_var)::in,
	list(mode)::in, map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	prog_var::out, hlds_goal::out) is det.

table_gen__create_new_non_goal(EvalMethod, Detism, OrigGoal, PredId, ProcId,
		HeadVars, HeadVarModes, VarTypes0, VarTypes,
		VarSet0, VarSet, TableInfo0, TableInfo, TableVar, Goal) :-
	% even if the original goal doesn't use all of the headvars,
	% the code generated by the tabling transformation does,
	% so we need to compute the nonlocals from the headvars rather
	% than getting it from the nonlocals field in the original goal
	set__list_to_set(HeadVars, OrigNonLocals),
	OrigGoal = _ - OrigGoalInfo,
	goal_info_get_instmap_delta(OrigGoalInfo, OrigInstMapDelta),
	goal_info_get_context(OrigGoalInfo, Context),

	table_info_get_module_info(TableInfo0, Module),
	get_input_output_vars(HeadVars, HeadVarModes, Module, InputVars,
		OutputVars),

	generate_non_lookup_goal(InputVars, PredId, ProcId, Context,
		VarTypes0, VarTypes1, VarSet0, VarSet1, TableInfo0, TableInfo1,
		TableVar, LookUpGoal),
	generate_call("table_nondet_is_complete", [TableVar], semidet,
		yes(semipure), [], Module, Context, CompleteCheckGoal),
	generate_non_save_goal(OutputVars, TableVar, Context,
		VarTypes1, VarTypes2, VarSet1, VarSet2, TableInfo1, TableInfo,
		SaveAnsGoal0),
	generate_restore_all_goal(Detism, OutputVars, TableVar, Module, Context,
		VarTypes2, VarTypes3, VarSet2, VarSet3, RestoreAllAnsGoal),
	generate_call("table_nondet_is_active", [TableVar], semidet,
		yes(semipure), [], Module, Context, IsActiveCheckGoal),
	generate_suspend_goal(OutputVars, TableVar, Module, Context,
		VarTypes3, VarTypes4, VarSet3, VarSet4, SuspendGoal),
	generate_loop_error_goal(TableInfo, Context, VarTypes4, VarTypes,
		VarSet4, VarSet, LoopErrorGoal),
	generate_call("table_nondet_mark_as_active", [TableVar], det,
		yes(impure), [], Module, Context, MarkAsActiveGoal),
	generate_call("table_nondet_resume", [TableVar], det, yes(impure),
		[], Module, Context, ResumeGoal0),
	append_fail(ResumeGoal0, ResumeGoal1),

	true_goal(TrueGoal),
	fail_goal(FailGoal),

	map__init(StoreMap),
	(
		EvalMethod = eval_memo
	->
		SaveAnsGoal = SaveAnsGoal0,
		ActiveGoal = LoopErrorGoal
	;
		EvalMethod = eval_loop_check
	->
		SaveAnsGoal = TrueGoal,
		ActiveGoal = LoopErrorGoal
	;
		EvalMethod = eval_minimal
	->
		SaveAnsGoal = SaveAnsGoal0,
		ActiveGoal = SuspendGoal
	;
		error(
		"table_gen__create_new_non_goal: unsupported evaluation model")
	),

	GenAnsGoalPart1Ex = conj([MarkAsActiveGoal, OrigGoal, SaveAnsGoal]),
	set__insert(OrigNonLocals, TableVar, GenAnsGoalPart1NonLocals),
	create_instmap_delta([MarkAsActiveGoal, OrigGoal, SaveAnsGoal],
		GenAnsGoalPart1IMD0),
	instmap_delta_restrict(GenAnsGoalPart1IMD0, GenAnsGoalPart1NonLocals,
		GenAnsGoalPart1IMD),
	init_goal_info(GenAnsGoalPart1NonLocals, GenAnsGoalPart1IMD, nondet,
		Context, GenAnsGoalPart1GoalInfo),
	GenAnsGoalPart1 = GenAnsGoalPart1Ex - GenAnsGoalPart1GoalInfo,

	(
		EvalMethod = eval_minimal
	->
		ResumeGoal = ResumeGoal1
	;
		ResumeGoal = FailGoal
	),
	GenAnsGoalEx = disj([GenAnsGoalPart1, ResumeGoal], StoreMap),
	GenAnsGoal = GenAnsGoalEx - GenAnsGoalPart1GoalInfo,

	ITE1GoalEx = if_then_else([], IsActiveCheckGoal, ActiveGoal,
		GenAnsGoal, StoreMap),
	ITE1Goal = ITE1GoalEx - GenAnsGoalPart1GoalInfo,

	(
		EvalMethod = eval_loop_check
	->
		ITE2Goal = ITE1Goal
	;
		ITE2GoalEx = if_then_else([], CompleteCheckGoal,
			RestoreAllAnsGoal, ITE1Goal, StoreMap),
		ITE2Goal = ITE2GoalEx - GenAnsGoalPart1GoalInfo
	),

	GoalEx = conj([LookUpGoal, ITE2Goal]),
	init_goal_info(OrigNonLocals, OrigInstMapDelta, nondet, Context,
		GoalInfo),

	Goal = GoalEx - GoalInfo.

%-----------------------------------------------------------------------------%

:- pred table_gen__var_is_io_state(map(prog_var, type)::in, prog_var::in)
	is semidet.

table_gen__var_is_io_state(VarTypes, Var) :-
	map__lookup(VarTypes, Var, VarType),
	type_util__type_is_io_state(VarType).

%-----------------------------------------------------------------------------%

:- pred generate_get_table_goal(pred_id::in, proc_id::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out,
	prog_var::out, hlds_goal::out) is det.

generate_get_table_goal(PredId, ProcId, VarTypes0, VarTypes, VarSet0, VarSet,
		PredTableVar, Goal) :-
	generate_new_table_var("PredTable", VarTypes0, VarTypes,
		VarSet0, VarSet, PredTableVar),
	ConsId = tabling_pointer_const(PredId, ProcId),
	make_const_construction(PredTableVar, ConsId, GoalExpr - GoalInfo0),
	goal_info_add_feature(GoalInfo0, impure, GoalInfo),
	Goal = GoalExpr - GoalInfo.

%-----------------------------------------------------------------------------%

:- pred generate_simple_lookup_goal(list(prog_var)::in,
	pred_id::in, proc_id::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	prog_var::out, hlds_goal::out) is det.

generate_simple_lookup_goal(Vars, PredId, ProcId, Context, VarTypes0, VarTypes,
		VarSet0, VarSet, TableInfo0, TableInfo, TableVar, Goal) :-
	generate_get_table_goal(PredId, ProcId, VarTypes0, VarTypes1,
		VarSet0, VarSet1, PredTableVar, GetTableGoal),
	generate_lookup_goals(Vars, Context, PredTableVar, TableVar,
		VarTypes1, VarTypes, VarSet1, VarSet, TableInfo0, TableInfo,
		LookupGoals),
	GoalEx = conj([GetTableGoal | LookupGoals]),
	set__singleton_set(NonLocals0, TableVar),
	set__insert_list(NonLocals0, Vars, NonLocals),
	instmap_delta_from_assoc_list([], InstMapDelta),
	init_goal_info(NonLocals, InstMapDelta, det, Context, GoalInfo0),
	goal_info_get_features(GoalInfo0, Features0),
	set__insert(Features0, call_table_gen, Features),
	goal_info_set_features(GoalInfo0, Features, GoalInfo),

	% We need to wrap the conjunction in a `some' which cannot be removed
	% to make sure the `call_table_gen' marker doesn't get removed by
	% any of the optimization passes (e.g. simplify.m flattening
	% conjunctions).
	Goal = some([], cannot_remove, GoalEx - GoalInfo0) - GoalInfo.

:- pred generate_non_lookup_goal(list(prog_var)::in, pred_id::in, proc_id::in,
	term__context::in, map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	prog_var::out, hlds_goal::out) is det.

generate_non_lookup_goal(Vars, PredId, ProcId, Context, VarTypes0, VarTypes,
		VarSet0, VarSet, TableInfo0, TableInfo, SubgoalVar, Goal) :-
	table_info_get_module_info(TableInfo0, Module),
	generate_get_table_goal(PredId, ProcId, VarTypes0, VarTypes1,
		VarSet0, VarSet1, PredTableVar, GetTableGoal),
	generate_lookup_goals(Vars, Context, PredTableVar, TableNodeVar,
		VarTypes1, VarTypes2, VarSet1, VarSet2, TableInfo0, TableInfo,
		LookupGoals),
	generate_new_table_var("SubgoalVar", VarTypes2, VarTypes,
		VarSet2, VarSet, SubgoalVar),
	generate_call("table_nondet_setup", [TableNodeVar, SubgoalVar],
		det, yes(impure), [SubgoalVar - ground(unique, none)],
		Module, Context, SetupGoal),

	list__append([GetTableGoal | LookupGoals], [SetupGoal], Goals),
	GoalEx = conj(Goals),
	set__singleton_set(NonLocals0, SubgoalVar),
	set__insert_list(NonLocals0, Vars, NonLocals),
	create_instmap_delta(Goals, InstMapDelta0),
	instmap_delta_restrict(InstMapDelta0, NonLocals, InstMapDelta),
	init_goal_info(NonLocals, InstMapDelta, det, Context, GoalInfo0),
	goal_info_get_features(GoalInfo0, Features0),
	set__insert(Features0, call_table_gen, Features),
	goal_info_set_features(GoalInfo0, Features, GoalInfo),

	% We need to wrap the conjunction in a `some' which cannot be removed
	% to make sure the `call_table_gen' marker doesn't get removed by
	% any of the optimization passes (e.g. simplify.m flattening
	% conjunctions).
	Goal = some([], cannot_remove, GoalEx - GoalInfo) - GoalInfo.

:- pred generate_lookup_goals(list(prog_var)::in, term__context::in,
	prog_var::in, prog_var::out,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	list(hlds_goal)::out) is det.

generate_lookup_goals([], _, TableVar, TableVar,
		VarTypes, VarTypes, VarSet, VarSet, TableInfo, TableInfo, []).
generate_lookup_goals([Var | Rest], Context, TableVar0, TableVar,
		VarTypes0, VarTypes, VarSet0, VarSet, TableInfo0, TableInfo,
		[Goal | RestGoals]) :-
	table_info_get_module_info(TableInfo0, Module),
	map__lookup(VarTypes0, Var, VarType),
	classify_type(VarType, Module, TypeCat),
	gen_lookup_call_for_type(TypeCat, VarType, TableVar0, Var, Context,
		VarTypes0, VarTypes1, VarSet0, VarSet1, TableInfo0, TableInfo1,
		TableVar1, Goal),
	generate_lookup_goals(Rest, Context, TableVar1, TableVar,
		VarTypes1, VarTypes, VarSet1, VarSet, TableInfo1, TableInfo,
		RestGoals).

:- pred gen_lookup_call_for_type(builtin_type::in, (type)::in,
	prog_var::in, prog_var::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	prog_var::out, hlds_goal::out) is det.

gen_lookup_call_for_type(TypeCat, Type, TableVar, ArgVar, Context,
		VarTypes0, VarTypes, VarSet0, VarSet, TableInfo0, TableInfo,
		NextTableVar, Goal) :-
	table_info_get_module_info(TableInfo0, Module),

	( TypeCat = enum_type ->
		(
			type_to_type_id(Type, TypeId, _)
		->
			module_info_types(Module, TypeDefnTable),
			map__lookup(TypeDefnTable, TypeId, TypeDefn),
			hlds_data__get_type_defn_body(TypeDefn, TypeBody),
			(
				TypeBody = du_type(Ctors, _, yes, no)
			->
				list__length(Ctors, EnumRange)
			;
				error(
    "gen_lookup_call_for_type: enum type is not du_type?")
			),
			gen_int_construction("RangeVar", EnumRange, VarTypes0,
				VarTypes1, VarSet0, VarSet1, RangeVar,
				RangeUnifyGoal),

			generate_new_table_var("TableNodeVar",
				VarTypes1, VarTypes, VarSet1, VarSet,
				NextTableVar),
			generate_call("table_lookup_insert_enum",
				[TableVar, RangeVar, ArgVar, NextTableVar],
				det, yes(impure),
				[NextTableVar - ground(unique, none)],
				Module, Context, LookupGoal),
			set__init(NonLocals0),
			set__insert_list(NonLocals0, [TableVar, ArgVar],
				NonLocals),
			instmap_delta_from_assoc_list([], InstMapDelta),
			init_goal_info(NonLocals, InstMapDelta, det, Context,
				GoalInfo),
			Goal = conj([RangeUnifyGoal, LookupGoal]) - GoalInfo,
			TableInfo = TableInfo0
		;
			error("gen_lookup: unexpected type")
		)
	;
		generate_new_table_var("TableNodeVar", VarTypes0, VarTypes1,
			VarSet0, VarSet1, NextTableVar),
		InstMapAL = [NextTableVar - ground(unique, none)],
		(
			( TypeCat = pred_type
			; TypeCat = polymorphic_type
			; TypeCat = user_type
			)
		->
			( type_util__vars(Type, []) ->
				LookupPredName = "table_lookup_insert_user"
			;
				LookupPredName = "table_lookup_insert_poly"
			),
			make_type_info_var(Type, Context, VarTypes1, VarTypes,
				VarSet1, VarSet, TableInfo0, TableInfo,
				TypeInfoVar, ExtraGoals),

			generate_call(LookupPredName,
				[TypeInfoVar, TableVar, ArgVar, NextTableVar],
				det, yes(impure), InstMapAL, Module, Context,
				CallGoal),

			list__append(ExtraGoals, [CallGoal], ConjList),
			CallGoal = _ - GoalInfo,
			conj_list_to_goal(ConjList, GoalInfo, Goal)
		;
			builtin_type_to_string(TypeCat, CatString),
			string__append("table_lookup_insert_", CatString,
				LookupPredName),
			generate_call(LookupPredName,
				[TableVar, ArgVar, NextTableVar],
				det, yes(impure), InstMapAL, Module, Context,
				Goal),
			VarTypes = VarTypes1,
			VarSet = VarSet1,
			TableInfo = TableInfo0
		)
	).

%-----------------------------------------------------------------------------%

:- pred generate_save_goal(list(prog_var)::in, prog_var::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	hlds_goal::out) is det.

generate_save_goal(AnsList, TableVar, Context, VarTypes0, VarTypes,
		VarSet0, VarSet, TableInfo0, TableInfo, Goal) :-
	table_info_get_module_info(TableInfo0, Module),

	list__length(AnsList, NumAnsVars),
	(
		NumAnsVars \= 0
	->
		gen_int_construction("NumAnsVars", NumAnsVars, VarTypes0,
			VarTypes1, VarSet0, VarSet1, NumAnsVarsVar,
			NumAnsVarsUnifyGoal),

		generate_new_table_var("AnswerTableVar", VarTypes1, VarTypes2,
			VarSet1, VarSet2, AnsTableVar),

		generate_call("table_create_ans_block",
			[TableVar, NumAnsVarsVar, AnsTableVar], det,
			yes(impure),
			[AnsTableVar - ground(unique, none)], Module, Context,
			CreateAnsBlockGoal),

		generate_save_goals(AnsList, AnsTableVar, 0, Context,
			VarTypes2, VarTypes, VarSet2, VarSet,
			TableInfo0, TableInfo, SaveGoals),

		GoalEx = conj([NumAnsVarsUnifyGoal, CreateAnsBlockGoal |
			SaveGoals]),
		set__singleton_set(NonLocals0, TableVar),
		set__insert_list(NonLocals0, AnsList, NonLocals),
		create_instmap_delta([NumAnsVarsUnifyGoal, CreateAnsBlockGoal |
			SaveGoals], InstMapDelta0),
		instmap_delta_restrict(InstMapDelta0, NonLocals, InstMapDelta),
		init_goal_info(NonLocals, InstMapDelta, det, Context,
			GoalInfo),
		Goal = GoalEx - GoalInfo
	;
		VarTypes = VarTypes0,
		VarSet = VarSet0,
		generate_call("table_simple_mark_as_succeeded", [TableVar], det,
			yes(impure), [], Module, Context, Goal),
		TableInfo = TableInfo0
	).

:- pred generate_non_save_goal(list(prog_var)::in, prog_var::in,
	term__context::in, map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	hlds_goal::out) is det.

generate_non_save_goal(AnsList, TableVar, Context, VarTypes0, VarTypes,
		VarSet0, VarSet, TableInfo0, TableInfo, Goal) :-
	table_info_get_module_info(TableInfo0, Module),

	generate_new_table_var("AnswerTableVar", VarTypes0, VarTypes1,
		VarSet0, VarSet1, AnsTableVar0),
	generate_call("table_nondet_get_ans_table", [TableVar, AnsTableVar0],
		det, yes(impure), [AnsTableVar0 - ground(unique, none)],
		Module, Context, GetAnsTableGoal),
	generate_lookup_goals(AnsList, Context, AnsTableVar0, AnsTableVar1,
		VarTypes1, VarTypes2, VarSet1, VarSet2, TableInfo0, TableInfo1,
		LookupAnsGoals),
	generate_call("table_nondet_answer_is_not_duplicate", [AnsTableVar1],
		semidet, yes(impure), [], Module, Context, DuplicateCheckGoal),

	generate_new_table_var("AnswerSlotVar", VarTypes2, VarTypes3,
		VarSet2, VarSet3, AnsSlotVar),
	generate_call("table_nondet_new_ans_slot", [TableVar, AnsSlotVar], det,
		yes(impure), [AnsSlotVar - ground(unique, none)],
		Module, Context, NewAnsSlotGoal),

	list__length(AnsList, NumAnsVars),
	gen_int_construction("NumAnsVars", NumAnsVars, VarTypes3, VarTypes4,
		VarSet3, VarSet4, NumAnsVarsVar, NumAnsVarsUnifyGoal),
	generate_new_table_var("AnswerBlock", VarTypes4, VarTypes5,
		VarSet4, VarSet5, AnsBlockVar),
	generate_call("table_create_ans_block",
		[AnsSlotVar, NumAnsVarsVar, AnsBlockVar], det, yes(impure),
		[AnsBlockVar - ground(unique, none)],
		Module, Context, CreateAnsBlockGoal),

	generate_save_goals(AnsList, AnsBlockVar, 0, Context,
		VarTypes5, VarTypes, VarSet5, VarSet, TableInfo1, TableInfo,
		SaveGoals),

	list__append([GetAnsTableGoal | LookupAnsGoals],
		[DuplicateCheckGoal, NewAnsSlotGoal, NumAnsVarsUnifyGoal,
		CreateAnsBlockGoal | SaveGoals], Goals),

	GoalEx = conj(Goals),
	set__singleton_set(NonLocals0, TableVar),
	set__insert_list(NonLocals0, AnsList, NonLocals),
	create_instmap_delta(Goals, InstMapDelta0),
	instmap_delta_restrict(InstMapDelta0, NonLocals, InstMapDelta),
	init_goal_info(NonLocals, InstMapDelta, semidet, Context, GoalInfo),
	Goal = GoalEx - GoalInfo.

:- pred generate_save_goals(list(prog_var)::in, prog_var::in, int::in,
	term__context::in, map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	list(hlds_goal)::out) is det.

generate_save_goals([], _TableVar, _Offset, _Context,
		VarTypes, VarTypes, VarSet, VarSet, TableInfo, TableInfo, []).
generate_save_goals([Var | Rest], TableVar, Offset0, Context,
		VarTypes0, VarTypes, VarSet0, VarSet, TableInfo0, TableInfo,
		Goals) :-

	gen_int_construction("OffsetVar", Offset0, VarTypes0, VarTypes1,
		VarSet0, VarSet1, OffsetVar, OffsetUnifyGoal),

	table_info_get_module_info(TableInfo0, Module),
	map__lookup(VarTypes1, Var, VarType),
	classify_type(VarType, Module, TypeCat),

	gen_save_call_for_type(TypeCat, VarType, TableVar, Var, OffsetVar,
		Context, VarTypes1, VarTypes2, VarSet1, VarSet2,
		TableInfo0, TableInfo1, CallGoal),

	Offset is Offset0 + 1,
	generate_save_goals(Rest, TableVar, Offset, Context,
		VarTypes2, VarTypes, VarSet2, VarSet, TableInfo1, TableInfo,
		RestGoals),

	Goals =	[OffsetUnifyGoal, CallGoal | RestGoals].

:- pred gen_save_call_for_type(builtin_type::in, (type)::in,
	prog_var::in, prog_var::in, prog_var::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	hlds_goal::out) is det.

gen_save_call_for_type(TypeCat, Type, TableVar, Var, OffsetVar, Context,
		VarTypes0, VarTypes, VarSet0, VarSet, TableInfo0, TableInfo,
		Goal) :-
	table_info_get_module_info(TableInfo0, Module),
	( type_util__type_is_io_state(Type) ->
		LookupPredName = "table_save_io_state_ans",
		generate_call(LookupPredName, [TableVar, OffsetVar, Var],
			det, yes(impure), [], Module, Context, Goal),

		VarTypes = VarTypes0,
		VarSet = VarSet0,
		TableInfo = TableInfo0
	; not_builtin_type(TypeCat) ->
		make_type_info_var(Type, Context, VarTypes0, VarTypes,
			VarSet0, VarSet, TableInfo0, TableInfo,
			TypeInfoVar, ExtraGoals),

		generate_call("table_save_any_ans",
			[TypeInfoVar, TableVar, OffsetVar, Var],
			det, yes(impure), [], Module, Context, CallGoal),

		list__append(ExtraGoals, [CallGoal], ConjList),
		CallGoal = _ - GoalInfo,
		conj_list_to_goal(ConjList, GoalInfo, Goal)
	;
		builtin_type_to_string(TypeCat, CatString),
		string__append_list(["table_save_", CatString, "_ans"],
			LookupPredName),
		generate_call(LookupPredName, [TableVar, OffsetVar, Var],
			det, yes(impure), [], Module, Context, Goal),

		VarTypes = VarTypes0,
		VarSet = VarSet0,
		TableInfo = TableInfo0
	).

%-----------------------------------------------------------------------------%

:- pred generate_restore_goal(list(prog_var)::in, prog_var::in,
	module_info::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, hlds_goal::out) is det.

generate_restore_goal(OutputVars, TableVar, Module, Context,
		VarTypes0, VarTypes, VarSet0, VarSet, Goal) :-

	generate_restore_goals(OutputVars, TableVar, 0, Module, Context,
		VarTypes0, VarTypes, VarSet0, VarSet, RestoreGoals),

	GoalEx = conj(RestoreGoals),
	set__singleton_set(NonLocals0, TableVar),
	set__insert_list(NonLocals0, OutputVars, NonLocals),
	create_instmap_delta(RestoreGoals, InstMapDelta0),
	instmap_delta_restrict(InstMapDelta0, NonLocals, InstMapDelta),
	init_goal_info(NonLocals, InstMapDelta, det, Context, GoalInfo),
	Goal = GoalEx - GoalInfo.

:- pred generate_restore_all_goal(determinism::in, list(prog_var)::in,
	prog_var::in, module_info::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, hlds_goal::out) is det.

generate_restore_all_goal(Detism, OutputVars, TableVar, Module, Context,
		VarTypes0, VarTypes, VarSet0, VarSet, Goal) :-

	generate_new_table_var("AnswerTable", VarTypes0, VarTypes1,
		VarSet0, VarSet1, AnsTableVar),
	( Detism = multidet ->
		ReturnAllAns = "table_multi_return_all_ans"
	; Detism = nondet ->
		ReturnAllAns = "table_nondet_return_all_ans"
	;
		error("generate_restore_all_goal: invalid determinism")
	),
	generate_call(ReturnAllAns, [TableVar, AnsTableVar],
		Detism, yes(semipure), [AnsTableVar - ground(unique, none)],
		Module, Context, ReturnAnsBlocksGoal),

	generate_restore_goals(OutputVars, AnsTableVar, 0, Module, Context,
		VarTypes1, VarTypes, VarSet1, VarSet, RestoreGoals),

	GoalEx = conj([ReturnAnsBlocksGoal | RestoreGoals]),
	set__singleton_set(NonLocals0, TableVar),
	set__insert_list(NonLocals0, OutputVars, NonLocals),
	create_instmap_delta([ReturnAnsBlocksGoal | RestoreGoals],
		InstMapDelta0),
	instmap_delta_restrict(InstMapDelta0, NonLocals, InstMapDelta),
	init_goal_info(NonLocals, InstMapDelta, nondet, Context, GoalInfo),
	Goal = GoalEx - GoalInfo.

:- pred generate_restore_goals(list(prog_var)::in, prog_var::in, int::in,
	module_info::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, list(hlds_goal)::out) is det.

generate_restore_goals([], _TableVar, _Offset, _Module, _Context,
		VarTypes, VarTypes, VarSet, VarSet, []).
generate_restore_goals([Var | Rest], TableVar, Offset0, Module, Context,
		VarTypes0, VarTypes, VarSet0, VarSet,
		[OffsetUnifyGoal, CallGoal | RestGoals]) :-

	gen_int_construction("OffsetVar", Offset0, VarTypes0, VarTypes1,
		VarSet0, VarSet1, OffsetVar, OffsetUnifyGoal),

	map__lookup(VarTypes1, Var, VarType),
	classify_type(VarType, Module, TypeCat),

	gen_restore_call_for_type(TypeCat, VarType, TableVar, Var, OffsetVar,
		Module, Context, CallGoal),

	Offset is Offset0 + 1,
	generate_restore_goals(Rest, TableVar, Offset, Module, Context,
		VarTypes1, VarTypes, VarSet1, VarSet, RestGoals).

:- pred gen_restore_call_for_type(builtin_type::in, (type)::in,
	prog_var::in, prog_var::in, prog_var::in, module_info::in,
	term__context::in, hlds_goal::out) is det.

gen_restore_call_for_type(TypeCat, Type, TableVar, Var, OffsetVar, Module,
		Context, Goal) :-
	( type_util__type_is_io_state(Type) ->
		LookupPredName = "table_restore_io_state_ans"
	; not_builtin_type(TypeCat) ->
		LookupPredName = "table_restore_any_ans"
	;
		builtin_type_to_string(TypeCat, CatString),
		string__append_list(["table_restore_", CatString, "_ans"],
			LookupPredName)
	),
	generate_call(LookupPredName, [TableVar, OffsetVar, Var], det,
		yes(impure), [Var - ground(shared, none)],
		Module, Context, Goal).

%-----------------------------------------------------------------------------%

:- pred generate_suspend_goal(list(prog_var)::in, prog_var::in,
	module_info::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, hlds_goal::out) is det.

generate_suspend_goal(OutputVars, TableVar, Module, Context,
		VarTypes0, VarTypes, VarSet0, VarSet, Goal) :-

	generate_new_table_var("AnswerTable", VarTypes0, VarTypes1,
		VarSet0, VarSet1, AnsTableVar),
	generate_call("table_nondet_suspend", [TableVar, AnsTableVar],
		nondet, yes(semipure), [AnsTableVar - ground(unique, none)],
		Module, Context, ReturnAnsBlocksGoal),

	generate_restore_goals(OutputVars, AnsTableVar, 0, Module, Context,
		VarTypes1, VarTypes, VarSet1, VarSet, RestoreGoals),

	GoalEx = conj([ReturnAnsBlocksGoal | RestoreGoals]),
	set__singleton_set(NonLocals0, TableVar),
	set__insert_list(NonLocals0, OutputVars, NonLocals),
	create_instmap_delta([ReturnAnsBlocksGoal | RestoreGoals],
		InstMapDelta0),
	instmap_delta_restrict(InstMapDelta0, NonLocals, InstMapDelta),
	init_goal_info(NonLocals, InstMapDelta, nondet, Context, GoalInfo),
	Goal = GoalEx - GoalInfo.

%-----------------------------------------------------------------------------%

:- pred generate_loop_error_goal(table_info::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, hlds_goal::out) is det.

generate_loop_error_goal(TableInfo, Context, VarTypes0, VarTypes,
		VarSet0, VarSet, Goal) :-
	table_info_get_module_info(TableInfo, ModuleInfo),
	table_info_get_pred_info(TableInfo, PredInfo),

	pred_info_module(PredInfo, Module),
	pred_info_name(PredInfo, Name),
	pred_info_arity(PredInfo, Arity),
	pred_info_get_is_pred_or_func(PredInfo, PredOrFunc),
	hlds_out__pred_or_func_to_str(PredOrFunc, PredOrFuncS),
	prog_out__sym_name_to_string(qualified(Module, Name), NameS),
	string__int_to_string(Arity, ArityS),
	string__append_list(["detected infinite recursion in ", PredOrFuncS,
		" ", NameS, "/", ArityS], Message),

	gen_string_construction("MessageS", Message, VarTypes0, VarTypes,
		VarSet0, VarSet, MessageVar, MessageConsGoal),
	generate_call("table_loopcheck_error", [MessageVar], erroneous,
		no, [], ModuleInfo, Context, CallGoal),

	GoalEx = conj([MessageConsGoal, CallGoal]),
	set__init(NonLocals),
	create_instmap_delta([MessageConsGoal, CallGoal],
		InstMapDelta0),
	instmap_delta_restrict(InstMapDelta0, NonLocals, InstMapDelta),
	init_goal_info(NonLocals, InstMapDelta, erroneous, Context, GoalInfo),
	Goal = GoalEx - GoalInfo.

%-----------------------------------------------------------------------------%

:- pred generate_new_table_var(string::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, prog_var::out) is det.

generate_new_table_var(Name, VarTypes0, VarTypes, VarSet0, VarSet, Var) :-
	varset__new_named_var(VarSet0, Name, Var, VarSet),
	get_table_var_type(Type),
	map__set(VarTypes0, Var, Type, VarTypes).

:- pred generate_call(string::in, list(prog_var)::in, determinism::in,
	maybe(goal_feature)::in, assoc_list(prog_var, inst)::in,
	module_info::in, term__context::in, hlds_goal::out) is det.

generate_call(PredName, Args, Detism, MaybeFeature, InstMap, Module, Context,
		CallGoal) :-
	list__length(Args, Arity),
	mercury_table_builtin_module(BuiltinModule),
	module_info_get_predicate_table(Module, PredTable),
	(
		predicate_table_search_pred_m_n_a(PredTable,
			BuiltinModule, PredName, Arity,
			[PredId0])
	->
		PredId = PredId0
	;
		% Some of the table builtins are polymorphic,
		% and for them we need to subtract one from the arity
		% to take into account the type_info argument.
		predicate_table_search_pred_m_n_a(PredTable,
			BuiltinModule, PredName, Arity - 1,
			[PredId0])
	->
		PredId = PredId0
	;
		string__int_to_string(Arity, ArityS),
		string__append_list(["can't locate ", PredName,
			"/", ArityS], ErrorMessage),
		error(ErrorMessage)
	),
	module_info_pred_info(Module, PredId, PredInfo),
	(
		pred_info_procids(PredInfo, [ProcId0])
	->
		ProcId = ProcId0
	;
		string__int_to_string(Arity, ArityS),
		string__append_list(["too many modes for pred ",
			PredName, "/", ArityS], ErrorMessage),
		error(ErrorMessage)

	),
	Call = call(PredId, ProcId, Args, not_builtin, no,
		qualified(BuiltinModule, PredName)),
	set__init(NonLocals0),
	set__insert_list(NonLocals0, Args, NonLocals),
	determinism_components(Detism, _CanFail, NumSolns),
	(
		NumSolns = at_most_zero
	->
		instmap_delta_init_unreachable(InstMapDelta)
	;
		instmap_delta_from_assoc_list(InstMap, InstMapDelta)
	),
	init_goal_info(NonLocals, InstMapDelta, Detism, Context,
		CallGoalInfo0),
	(
		MaybeFeature = yes(Feature),
		goal_info_add_feature(CallGoalInfo0, Feature, CallGoalInfo)
	;
		MaybeFeature = no,
		CallGoalInfo = CallGoalInfo0
	),
	CallGoal = Call - CallGoalInfo.

:- pred append_fail(hlds_goal::in, hlds_goal::out) is det.

append_fail(Goal, GoalAndThenFail) :-
	Goal = _ - GoalInfo,
	goal_info_get_nonlocals(GoalInfo, NonLocals),
	goal_info_get_context(GoalInfo, Context),
	instmap_delta_init_unreachable(UnreachInstMapDelta),
	init_goal_info(NonLocals, UnreachInstMapDelta, failure,
		Context, ConjGoalInfo),
	fail_goal(FailGoal),
	GoalAndThenFail = conj([Goal, FailGoal]) - ConjGoalInfo.

:- pred gen_int_construction(string::in, int::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out,
	prog_var::out, hlds_goal::out) is det.

gen_int_construction(VarName, VarValue, VarTypes0, VarTypes, VarSet0, VarSet,
		Var, Goal) :-
	make_int_const_construction(VarValue, Goal, Var,
		VarTypes0, VarTypes, VarSet0, VarSet1),
	varset__name_var(VarSet1, Var, VarName, VarSet).

:- pred gen_string_construction(string::in, string::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out,
	prog_var::out, hlds_goal::out) is det.

gen_string_construction(VarName, VarValue, VarTypes0, VarTypes, VarSet0, VarSet,
		Var, Goal) :-
	make_string_const_construction(VarValue, Goal, Var,
		VarTypes0, VarTypes, VarSet0, VarSet1),
	varset__name_var(VarSet1, Var, VarName, VarSet).

:- pred get_table_var_type((type)::out) is det.

get_table_var_type(Type) :-
	mercury_public_builtin_module(BuiltinModule),
	construct_type(qualified(BuiltinModule, "c_pointer") - 0, [], Type).

:- pred get_input_output_vars(list(prog_var)::in, list(mode)::in,
	module_info::in, list(prog_var)::out, list(prog_var)::out) is det.

get_input_output_vars([], [], _, [], []).
get_input_output_vars([_|_], [], _, _, _) :-
	error("get_input_output_vars: lists not same length").
get_input_output_vars([], [_|_], _, _, _) :-
	error("get_input_output_vars: lists not same length").
get_input_output_vars([Var | RestV], [Mode | RestM], Module, InVars, OutVars) :-
	( mode_is_fully_input(Module, Mode) ->
		get_input_output_vars(RestV, RestM, Module, InVars0, OutVars),
		InVars = [Var | InVars0]
	; mode_is_fully_output(Module, Mode) ->
		get_input_output_vars(RestV, RestM, Module, InVars, OutVars0),
		OutVars = [Var | OutVars0]
	;
		error(
    "Only fully input/output arguments are allowed in tabled code!")
	).

:- pred create_instmap_delta(hlds_goals::in, instmap_delta::out) is det.

create_instmap_delta([], IMD) :-
	instmap_delta_from_assoc_list([], IMD).
create_instmap_delta([Goal | Rest], IMD) :-
	Goal = _ - GoalInfo,
	goal_info_get_instmap_delta(GoalInfo, IMD0),
	create_instmap_delta(Rest, IMD1),
	instmap_delta_apply_instmap_delta(IMD0, IMD1, IMD).

:- pred not_builtin_type(builtin_type::in) is semidet.

not_builtin_type(pred_type).
not_builtin_type(enum_type).
not_builtin_type(polymorphic_type).
not_builtin_type(tuple_type).
not_builtin_type(user_type).

:- pred builtin_type_to_string(builtin_type::in, string::out) is det.

builtin_type_to_string(int_type, 	 "int").
builtin_type_to_string(char_type, 	 "char").
builtin_type_to_string(str_type, 	 "string").
builtin_type_to_string(float_type, 	 "float").
builtin_type_to_string(pred_type, 	 "pred").
builtin_type_to_string(tuple_type,	 "any").
builtin_type_to_string(enum_type, 	 "enum").
builtin_type_to_string(polymorphic_type, "any").
builtin_type_to_string(user_type, 	 "any").

%-----------------------------------------------------------------------------%

:- pred table_gen__make_type_info_var((type)::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	prog_var::out, list(hlds_goal)::out) is det.

table_gen__make_type_info_var(Type, Context,
		VarTypes0, VarTypes, VarSet0, VarSet, TableInfo0, TableInfo,
		TypeInfoVar, TypeInfoGoals) :-
	table_gen__make_type_info_vars([Type], Context,
		VarTypes0, VarTypes, VarSet0, VarSet, TableInfo0, TableInfo,
		TypeInfoVars, TypeInfoGoals),
	( TypeInfoVars = [TypeInfoVar0] ->
		TypeInfoVar = TypeInfoVar0
	;
		error("table_gen__make_type_info_var: list length != 1")
	).

:- pred table_gen__make_type_info_vars(list(type)::in, term__context::in,
	map(prog_var, type)::in, map(prog_var, type)::out,
	prog_varset::in, prog_varset::out, table_info::in, table_info::out,
	list(prog_var)::out, list(hlds_goal)::out) is det.

table_gen__make_type_info_vars(Types, Context,
		VarTypes0, VarTypes, VarSet0, VarSet, TableInfo0, TableInfo,
		TypeInfoVars, TypeInfoGoals) :-
	%
	% Extract the information from table_info
	%
	table_info_extract(TableInfo0, ModuleInfo0, PredInfo0, ProcInfo0),

	%
	% Put the varset and vartypes from the simplify_info
	% back in the proc_info
	%
	proc_info_set_vartypes(ProcInfo0, VarTypes0, ProcInfo1),
	proc_info_set_varset(ProcInfo1, VarSet0, ProcInfo2),

	%
	% Call polymorphism.m to create the type_infos
	%
	create_poly_info(ModuleInfo0, PredInfo0, ProcInfo2, PolyInfo0),
	polymorphism__make_type_info_vars(Types, Context,
		TypeInfoVars, TypeInfoGoals, PolyInfo0, PolyInfo),
	poly_info_extract(PolyInfo, PredInfo0, PredInfo,
		ProcInfo0, ProcInfo, ModuleInfo),

	%
	% Get the new varset and vartypes from the proc_info
	%
	proc_info_vartypes(ProcInfo, VarTypes),
	proc_info_varset(ProcInfo, VarSet),

	%
	% Put the new module_info, pred_info, and proc_info back in the
	% table_info.
	%
	table_info_init(ModuleInfo, PredInfo, ProcInfo, TableInfo).

%-----------------------------------------------------------------------------%

	% The goal_info_init/4 predicate in hlds_goal.m does almost everything
	% tabling wants in initializing the goal_infos of the new goals it
	% creates, but it does not fill in the context.  We need to use the
	% predicate init_goal_info/5 (below) to fill in the context, so that
	% when debugging is enabled, the call event and the internal events
	% that record the working of tabling get the correct contexts recorded
	% for them in the RTTI.

:- pred init_goal_info(set(prog_var)::in, instmap_delta::in, determinism::in,
	term__context::in, hlds_goal_info::out) is det.

init_goal_info(NonLocals, InstMapDelta, Detism, Context, GoalInfo) :-
	goal_info_init(NonLocals, InstMapDelta, Detism, GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo).

%-----------------------------------------------------------------------------%

:- type table_info ---> table_info(module_info, pred_info, proc_info).

:- pred table_info_init(module_info::in, pred_info::in, proc_info::in,
	table_info::out) is det.
:- pred table_info_extract(table_info::in,
	module_info::out, pred_info::out, proc_info::out) is det.

:- pred table_info_get_module_info(table_info::in, module_info::out) is det.
:- pred table_info_get_pred_info(table_info::in, pred_info::out) is det.
:- pred table_info_get_proc_info(table_info::in, proc_info::out) is det.

table_info_init(ModuleInfo, PredInfo, ProcInfo, TableInfo) :-
	TableInfo = table_info(ModuleInfo, PredInfo, ProcInfo).

table_info_extract(TableInfo, ModuleInfo, PredInfo, ProcInfo) :-
	TableInfo = table_info(ModuleInfo, PredInfo, ProcInfo).

table_info_get_module_info(TableInfo, ModuleInfo) :-
	TableInfo = table_info(ModuleInfo, _PredInfo, _ProcInfo).

table_info_get_pred_info(TableInfo, PredInfo) :-
	TableInfo = table_info(_ModuleInfo, PredInfo, _ProcInfo).

table_info_get_proc_info(TableInfo, ProcInfo) :-
	TableInfo = table_info(_ModuleInfo, _PredInfo, ProcInfo).

%-----------------------------------------------------------------------------%
