%-----------------------------------------------------------------------------%
% Copyright (C) 1997-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Author: zs.
%
% This module handles the generation of traces for the trace analysis system.
%
% For the general basis of trace analysis systems, see the paper
% "Opium: An extendable trace analyser for Prolog" by Mireille Ducasse,
% available from http://www.irisa.fr/lande/ducasse.
%
% We reserve two slots in the stack frame of the traced procedure.
% One contains the call sequence number, which is set in the procedure prologue
% by incrementing a global counter. The other contains the call depth, which
% is also set by incrementing a global variable containing the depth of the
% caller. The caller sets this global variable from its own saved depth
% just before the call.
%
% Each event has a label associated with it. The stack layout for that label
% records what variables are live and where they are at the time of the event.
% These labels are generated by the same predicate that generates the code
% for the event, and are initially not used for anything else.
% However, some of these labels may be fallen into from other places,
% and thus optimization may redirect references from labels to one of these
% labels. This cannot happen in the opposite direction, due to the reference
% to each event's label from the event's pragma C code instruction.
% (This prevents labelopt from removing the label.)
%
% We classify events into three kinds: external events (call, exit, fail),
% internal events (switch, disj, ite_then, ite_else), and nondet pragma C
% events (first, later). Code_gen.m, which calls this module to generate
% all external events, checks whether tracing is required before calling us;
% the predicates handing internal and nondet pragma C events must check this
% themselves. The predicates generating internal events need the goal
% following the event as a parameter. For the first and later arms of
% nondet pragma C code, there is no such hlds_goal, which is why these events
% need a bit of special treatment.

%-----------------------------------------------------------------------------%

:- module trace.

:- interface.

:- import_module hlds_goal, hlds_pred, hlds_module.
:- import_module globals, prog_data, llds, code_info.
:- import_module std_util, assoc_list, set, term.

	% The kinds of external ports for which the code we generate will
	% call MR_trace. The redo port is not on this list, because for that
	% port the code that calls MR_trace is not in compiler-generated code,
	% but in the runtime system.
:- type external_trace_port
	--->	call
	;	exit
	;	fail.

:- type nondet_pragma_trace_port
	--->	nondet_pragma_first
	;	nondet_pragma_later.

:- type trace_info.

	% Return the set of input variables whose values should be preserved
	% until the exit and fail ports. This will be all the input variables,
	% except those that can be totally clobbered during the evaluation
	% of the procedure (those partially clobbered may still be of interest,
	% although to handle them properly we need to record insts in stack
	% layouts).
:- pred trace__fail_vars(module_info::in, proc_info::in, set(var)::out) is det.

	% Return the number of slots reserved for tracing information.
	% If there are N slots, the reserved slots will be 1 through N.
:- pred trace__reserved_slots(proc_info::in, globals::in, int::out) is det.

	% Reserve the non-fixed stack slots needed for tracing.
	% The fixed slots for the event number, call number, call depth and
	% (for trace levels that specify redo events) the stack layout of
	% the redo event are reserved in live_vars.m; this predicate reserves
	% only the slots that do not need to be in fixed slots. At the moment
	% the only such slot is the flag that says whether this call should be
	% traced, which is required only for shallow tracing.
	%
	% The predicate returns the number of this slot if it is used,
	% and an abstract struct that represents the tracing-specific part
	% of the code generator state.
:- pred trace__setup(globals::in, maybe(int)::out, trace_info::out,
	code_info::in, code_info::out) is det.

	% Generate code to fill in the reserevd stack slots.
:- pred trace__generate_slot_fill_code(trace_info::in, code_tree::out,
	code_info::in, code_info::out) is det.

	% If we are doing execution tracing, generate code to prepare for
	% a call.
:- pred trace__prepare_for_call(code_tree::out, code_info::in, code_info::out)
	is det.

	% If we are doing execution tracing, generate code for an internal
	% trace event. This predicate must be called just before generating
	% code for the given goal.
:- pred trace__maybe_generate_internal_event_code(hlds_goal::in,
	code_tree::out, code_info::in, code_info::out) is det.

	% If we are doing execution tracing, generate code for a nondet
	% pragma C code trace event.
:- pred trace__maybe_generate_pragma_event_code(nondet_pragma_trace_port::in,
	code_tree::out, code_info::in, code_info::out) is det.

	% Generate code for an external trace event.
	% Besides the trace code, we return the label on which we have hung
	% the trace liveness information and data on the type variables in the
	% liveness information, since some of our callers also need this
	% information.
:- pred trace__generate_external_event_code(external_trace_port::in,
	trace_info::in, label::out, assoc_list(tvar, lval)::out, code_tree::out,
	code_info::in, code_info::out) is det.

	% If the trace level calls for redo events, generate code that pushes
	% a temporary nondet stack frame whose redoip slot contains the
	% address of one of the labels in the runtime that calls MR_trace
	% for a redo event. Otherwise, generate empty code.
:- pred trace__maybe_setup_redo_event(trace_info::in, code_tree::out) is det.

:- pred trace__path_to_string(goal_path::in, string::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module continuation_info, type_util, llds_out, tree.
:- import_module (inst), instmap, inst_match, mode_util, options.
:- import_module list, bool, int, string, map, std_util, varset, require.

	% The redo port is not included in this type; see the comment
	% on the type external_trace_port above.
:- type trace_port
	--->	call
	;	exit
	;	fail
	;	ite_then
	;	ite_else
	;	switch
	;	disj
	;	nondet_pragma_first
	;	nondet_pragma_later.

	% Information specific to a trace port.
:- type trace_port_info
	--->	external
	;	internal(
			goal_path,	% The path of the goal whose start
					% this port represents.
			set(var)	% The pre-death set of this goal.
		)
	;	nondet_pragma.

:- type trace_type
	--->	deep_trace
	;	shallow_trace(lval).	% This holds the saved value of a bool
					% that is true iff we were called from
					% code with full tracing.

	% Information for tracing that is valid throughout the execution
	% of a procedure.
:- type trace_info
	--->	trace_info(
			trace_type,	% The trace level (which cannot be
					% none), and if it is shallow, the
					% lval of the slot that holds the
					% from-full flag.
			bool,		% The value of --trace-internal.
			bool,		% The value of --trace-return.
			maybe(label)	% If we are generating redo events,
					% this has the label associated with
					% the fail event, which we then reserve
					% in advance, so we can put the
					% address of its layout struct
					% into the slot which holds the
					% layout for the redo event (the
					% two events have identical layouts).
		).

trace__fail_vars(ModuleInfo, ProcInfo, FailVars) :-
	proc_info_headvars(ProcInfo, HeadVars),
	proc_info_argmodes(ProcInfo, Modes),
	proc_info_arg_info(ProcInfo, ArgInfos),
	mode_list_get_final_insts(Modes, ModuleInfo, Insts),
	(
		trace__build_fail_vars(HeadVars, Insts, ArgInfos,
			ModuleInfo, FailVarsList)
	->
		set__list_to_set(FailVarsList, FailVars)
	;
		error("length mismatch in trace__fail_vars")
	).

trace__reserved_slots(ProcInfo, Globals, ReservedSlots) :-
	globals__get_trace_level(Globals, TraceLevel),
	(
		TraceLevel = none
	->
		ReservedSlots = 0
	;
		globals__lookup_bool_option(Globals, trace_redo, yes),
		proc_info_interface_code_model(ProcInfo, model_non)
	->
		( TraceLevel = deep ->
			% event#, call#, call depth, redo layout
			ReservedSlots = 4
		;
			% event#, call#, call depth, redo layout, from full
			ReservedSlots = 5
		)
	;
		( TraceLevel = deep ->
			% event#, call#, call depth
			ReservedSlots = 3
		;
			% event#, call#, call depth, from full
			ReservedSlots = 4
		)
	).

trace__setup(Globals, MaybeFromFullSlot, TraceInfo) -->
	% These slots were reserved by allocate_stack_slots in live_vars.m.
	code_info__get_proc_model(CodeModel),
	{ globals__lookup_bool_option(Globals, trace_return, TraceReturn) },
	{ globals__lookup_bool_option(Globals, trace_redo, TraceRedo) },
	(
		{ TraceRedo = yes },
		{ CodeModel = model_non }
	->
		code_info__get_next_label(RedoLayoutLabel),
		{ MaybeRedoLayoutSlot = yes(RedoLayoutLabel) }
	;
		{ MaybeRedoLayoutSlot = no }
	),
	{ globals__get_trace_level(Globals, deep) ->
		TraceType = deep_trace,
		globals__lookup_bool_option(Globals, trace_internal,
			TraceInternal),
		MaybeFromFullSlot = no
	;
		% Trace level must be shallow.
		%
		% Debugger code in the runtime is not interested in the
		% call-from-full flag, so does not have to be in a fixed slot.
		% Even if we put in a fixed slot, the runtime won't know
		% whether a procedure has interface or full tracing, and so it
		% wouldn't know whether the slot was used for this purpose
		% or not.
		( CodeModel = model_non ->
			( TraceRedo = yes ->
				CallFromFullSlot = framevar(5),
				MaybeFromFullSlot = yes(4)
			;
				CallFromFullSlot = framevar(4),
				MaybeFromFullSlot = yes(4)
			)
		;
			CallFromFullSlot = stackvar(4),
			MaybeFromFullSlot = yes(4)
		),
		TraceType = shallow_trace(CallFromFullSlot),
		% Shallow traced procs never generate internal events.
		TraceInternal = no
	},
	{ TraceInfo = trace_info(TraceType, TraceInternal, TraceReturn,
		MaybeRedoLayoutSlot) }.

trace__generate_slot_fill_code(TraceInfo, TraceCode) -->
	code_info__get_proc_model(CodeModel),
	{
	TraceInfo = trace_info(TraceType, _, _, MaybeRedoLayoutSlot),
	trace__event_num_slot(CodeModel, EventNumLval),
	trace__call_num_slot(CodeModel, CallNumLval),
	trace__call_depth_slot(CodeModel, CallDepthLval),
	trace__stackref_to_string(EventNumLval, EventNumStr),
	trace__stackref_to_string(CallNumLval, CallNumStr),
	trace__stackref_to_string(CallDepthLval, CallDepthStr),
	string__append_list([
		"\t\t", EventNumStr, " = MR_trace_event_number;\n",
		"\t\t", CallNumStr, " = MR_trace_incr_seq();\n",
		"\t\t", CallDepthStr, " = MR_trace_incr_depth();"
	], FillThreeSlots),
	( MaybeRedoLayoutSlot = yes(RedoLayoutLabel) ->
		trace__redo_layout_slot(CodeModel, RedoLayoutLval),
		trace__stackref_to_string(RedoLayoutLval, RedoLayoutStr),
		llds_out__make_stack_layout_name(RedoLayoutLabel,
			LayoutAddrStr),
		string__append_list([
			FillThreeSlots, "\n",
			"\t\t", RedoLayoutStr, " = (Word) (const Word *) &",
			LayoutAddrStr, ";"
		], FillFourSlots)
	;
		FillFourSlots = FillThreeSlots
	),
	(
		TraceType = shallow_trace(CallFromFullSlot),
		trace__stackref_to_string(CallFromFullSlot,
			CallFromFullSlotStr),
		string__append_list([
			"\t\t", CallFromFullSlotStr, " = MR_trace_from_full;\n",
			"\t\tif (MR_trace_from_full) {\n",
			FillFourSlots, "\n",
			"\t\t}"
		], TraceStmt)
	;
		TraceType = deep_trace,
		TraceStmt = FillFourSlots
	),
	TraceCode = node([
		pragma_c([], [pragma_c_raw_code(TraceStmt)],
			will_not_call_mercury, no, yes) - ""
	])
	}.

trace__prepare_for_call(TraceCode) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	code_info__get_proc_model(CodeModel),
	{
		MaybeTraceInfo = yes(TraceInfo)
	->
		TraceInfo = trace_info(TraceType, _, _, _),
		trace__call_depth_slot(CodeModel, CallDepthLval),
		trace__stackref_to_string(CallDepthLval, CallDepthStr),
		string__append_list([
			"MR_trace_reset_depth(", CallDepthStr, ");\n"
		], ResetDepthStmt),
		(
			TraceType = shallow_trace(_),
			ResetFromFullStmt = "MR_trace_from_full = FALSE;\n"
		;
			TraceType = deep_trace,
			ResetFromFullStmt = "MR_trace_from_full = TRUE;\n"
		),
		TraceCode = node([
			c_code(ResetFromFullStmt) - "",
			c_code(ResetDepthStmt) - ""
		])
	;
		TraceCode = empty
	}.

trace__maybe_generate_internal_event_code(Goal, Code) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	(
		{ MaybeTraceInfo = yes(TraceInfo) },
		{ TraceInfo = trace_info(_, yes, _, _) }
	->
		{ Goal = _ - GoalInfo },
		{ goal_info_get_goal_path(GoalInfo, Path) },
		{ goal_info_get_pre_deaths(GoalInfo, PreDeaths) },
		{
			Path = [LastStep | _],
			(
				LastStep = switch(_),
				PortPrime = switch
			;
				LastStep = disj(_),
				PortPrime = disj
			;
				LastStep = ite_then,
				PortPrime = ite_then
			;
				LastStep = ite_else,
				PortPrime = ite_else
			)
		->
			Port = PortPrime
		;
			error("trace__generate_internal_event_code: bad path")
		},
		trace__generate_event_code(Port, internal(Path, PreDeaths),
			TraceInfo, _, _, Code)
	;
		{ Code = empty }
	).

trace__maybe_generate_pragma_event_code(PragmaPort, Code) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	(
		{ MaybeTraceInfo = yes(TraceInfo) },
		{ TraceInfo = trace_info(_, yes, _, _) }
	->
		{ trace__convert_nondet_pragma_port_type(PragmaPort, Port) },
		trace__generate_event_code(Port, nondet_pragma, TraceInfo,
			_, _, Code)
	;
		{ Code = empty }
	).

trace__generate_external_event_code(ExternalPort, TraceInfo,
		Label, TvarDataList, Code) -->
	{ trace__convert_external_port_type(ExternalPort, Port) },
	trace__generate_event_code(Port, external, TraceInfo,
		Label, TvarDataList, Code).

:- pred trace__generate_event_code(trace_port::in, trace_port_info::in,
	trace_info::in, label::out, assoc_list(tvar, lval)::out,
	code_tree::out, code_info::in, code_info::out) is det.

trace__generate_event_code(Port, PortInfo, TraceInfo, Label, TvarDataList,
		Code) -->
	(
		{ Port = fail },
		{ TraceInfo = trace_info(_, _, _, yes(RedoLabel)) }
	->
		% The layout information for the redo event is the same as
		% for the fail event; all the non-clobbered inputs in their
		% stack slots. It is convenient to generate this common layout
		% when the code generator state is set up for the fail event;
		% generating it for the redo event would be much harder.
		% On the other hand, the address of the layout structure
		% for the redo event should be put into its fixed stack slot
		% at procedure entry. Therefore trace__setup reserves a label
		% whose layout structure serves for both the fail and redo
		% events.
		{ Label = RedoLabel }
	;
		code_info__get_next_label(Label)
	),
	code_info__get_known_variables(LiveVars0),
	(
		{ PortInfo = external },
		{ LiveVars = LiveVars0 },
		{ PathStr = "" }
	;
		{ PortInfo = internal(Path, PreDeaths) },
		code_info__current_resume_point_vars(ResumeVars),
		{ set__difference(PreDeaths, ResumeVars, RealPreDeaths) },
		{ set__to_sorted_list(RealPreDeaths, RealPreDeathList) },
		{ list__delete_elems(LiveVars0, RealPreDeathList, LiveVars) },
		{ trace__path_to_string(Path, PathStr) }
	;
		{ PortInfo = nondet_pragma },
		{ LiveVars = [] },
		{ PathStr = "" }
	),
	code_info__get_varset(VarSet),
	code_info__get_instmap(InstMap),
	{ set__init(TvarSet0) },
	trace__produce_vars(LiveVars, VarSet, InstMap, TvarSet0, TvarSet,
		VarInfoList, ProduceCode),
	{ set__to_sorted_list(TvarSet, TvarList) },
	code_info__variable_locations(VarLocs),
        code_info__get_proc_info(ProcInfo),
	{ proc_info_typeinfo_varmap(ProcInfo, TypeInfoMap) },
	{ trace__find_typeinfos_for_tvars(TvarList, VarLocs, TypeInfoMap,
		TvarDataList) },
	code_info__max_reg_in_use(MaxReg),
	{
	set__list_to_set(VarInfoList, VarInfoSet),
	set__list_to_set(TvarDataList, TvarDataSet),
	LayoutLabelInfo = layout_label_info(VarInfoSet, TvarDataSet),
	llds_out__get_label(Label, yes, LabelStr),
	Quote = """",
	Comma = ", ",
	trace__port_to_string(Port, PortStr),
	DeclStmt = "\t\tCode *MR_jumpaddr;\n",
	SaveStmt = "\t\tsave_transient_registers();\n",
	RestoreStmt = "\t\trestore_transient_registers();\n",
	string__int_to_string(MaxReg, MaxRegStr),
	string__append_list([
		"\t\tMR_jumpaddr = MR_trace(\n",
		"\t\t\t(const MR_Stack_Layout_Label *)\n",
		"\t\t\t&mercury_data__layout__", LabelStr, Comma, "\n",
		"\t\t\t", PortStr, Comma, Quote, PathStr, Quote, Comma,
		MaxRegStr, ");\n"],
		CallStmt),
	GotoStmt = "\t\tif (MR_jumpaddr != NULL) GOTO(MR_jumpaddr);",
	string__append_list([DeclStmt, SaveStmt, CallStmt, RestoreStmt,
		GotoStmt], TraceStmt),
	TraceCode =
		node([
			label(Label)
				- "A label to hang trace liveness on",
				% Referring to the label from the pragma_c
				% prevents the label from being renamed
				% or optimized away.
				% The label is before the trace code
				% because sometimes this pair is preceded
				% by another label, and this way we can
				% eliminate this other label.
			pragma_c([], [pragma_c_raw_code(TraceStmt)],
				may_call_mercury, yes(Label), yes)
				- ""
		]),
	Code = tree(ProduceCode, TraceCode)
	},
	code_info__add_trace_layout_for_label(Label, LayoutLabelInfo).

trace__maybe_setup_redo_event(TraceInfo, Code) :-
	TraceInfo = trace_info(_, _, _, TraceRedo),
	( TraceRedo = yes(_) ->
		Code = node([
			mkframe(temp_frame(nondet_stack_proc),
				do_trace_redo_fail)
				- "set up deep redo event"
		])
	;
		Code = empty
	).

:- pred trace__produce_vars(list(var)::in, varset::in, instmap::in,
	set(tvar)::in, set(tvar)::out, list(var_info)::out, code_tree::out,
	code_info::in, code_info::out) is det.

trace__produce_vars([], _, _, Tvars, Tvars, [], empty) --> [].
trace__produce_vars([Var | Vars], VarSet, InstMap, Tvars0, Tvars,
		[VarInfo | VarInfos], tree(VarCode, VarsCode)) -->
	code_info__produce_variable_in_reg_or_stack(Var, VarCode, Rval),
	code_info__variable_type(Var, Type),
	{
	( Rval = lval(LvalPrime) ->
		Lval = LvalPrime
	;
		error("var not an lval in trace__produce_vars")
		% If the value of the variable is known,
		% we record it as living in a nonexistent location, r0.
		% The code that interprets layout information must know this.
		% Lval = reg(r, 0)
	),
	varset__lookup_name(VarSet, Var, "V_", Name),
	instmap__lookup_var(InstMap, Var, Inst),
	LiveType = var(Var, Name, Type, Inst),
	VarInfo = var_info(Lval, LiveType),
	type_util__vars(Type, TypeVars),
	set__insert_list(Tvars0, TypeVars, Tvars1)
	},
	trace__produce_vars(Vars, VarSet, InstMap, Tvars1, Tvars,
		VarInfos, VarsCode).

	% For each type variable in the given list, find out where the
	% typeinfo var for that type variable is.

:- pred trace__find_typeinfos_for_tvars(list(tvar)::in,
	map(var, set(rval))::in, map(tvar, type_info_locn)::in,
	assoc_list(tvar, lval)::out) is det.

trace__find_typeinfos_for_tvars(TypeVars, VarLocs, TypeInfoMap, TypeInfoDatas)
		:-
	map__apply_to_list(TypeVars, TypeInfoMap, TypeInfoLocns),
	list__map(type_info_locn_var, TypeInfoLocns, TypeInfoVars),

	map__apply_to_list(TypeInfoVars, VarLocs, TypeInfoLvalSets),
	FindSingleLval = lambda([Set::in, Lval::out] is det, (
		(
			set__remove_least(Set, Value, _),
			Value = lval(Lval0)
		->
			Lval = Lval0
		;
			error("trace__find_typeinfos_for_tvars: typeinfo var not available")
		))
	),
	list__map(FindSingleLval, TypeInfoLvalSets, TypeInfoLvals),
	assoc_list__from_corresponding_lists(TypeVars, TypeInfoLvals,
		TypeInfoDatas).

%-----------------------------------------------------------------------------%

:- pred trace__build_fail_vars(list(var)::in, list(inst)::in,
	list(arg_info)::in, module_info::in, list(var)::out) is semidet.

trace__build_fail_vars([], [], [], _, []).
trace__build_fail_vars([Var | Vars], [Inst | Insts], [Info | Infos],
		ModuleInfo, FailVars) :-
	trace__build_fail_vars(Vars, Insts, Infos, ModuleInfo, FailVars0),
	Info = arg_info(_Loc, ArgMode),
	(
		ArgMode = top_in,
		\+ inst_is_clobbered(ModuleInfo, Inst)
	->
		FailVars = [Var | FailVars0]
	;
		FailVars = FailVars0
	).

%-----------------------------------------------------------------------------%

:- pred trace__port_to_string(trace_port::in, string::out) is det.

trace__port_to_string(call, "MR_PORT_CALL").
trace__port_to_string(exit, "MR_PORT_EXIT").
trace__port_to_string(fail, "MR_PORT_FAIL").
trace__port_to_string(ite_then, "MR_PORT_THEN").
trace__port_to_string(ite_else, "MR_PORT_ELSE").
trace__port_to_string(switch,   "MR_PORT_SWITCH").
trace__port_to_string(disj,     "MR_PORT_DISJ").
trace__port_to_string(nondet_pragma_first, "MR_PORT_PRAGMA_FIRST").
trace__port_to_string(nondet_pragma_later, "MR_PORT_PRAGMA_LATER").

:- pred trace__code_model_to_string(code_model::in, string::out) is det.

trace__code_model_to_string(model_det,  "MR_MODEL_DET").
trace__code_model_to_string(model_semi, "MR_MODEL_SEMI").
trace__code_model_to_string(model_non,  "MR_MODEL_NON").

:- pred trace__stackref_to_string(lval::in, string::out) is det.

trace__stackref_to_string(Lval, LvalStr) :-
	( Lval = stackvar(Slot) ->
		string__int_to_string(Slot, SlotString),
		string__append_list(["MR_stackvar(", SlotString, ")"], LvalStr)
	; Lval = framevar(Slot) ->
		string__int_to_string(Slot, SlotString),
		string__append_list(["MR_framevar(", SlotString, ")"], LvalStr)
	;
		error("non-stack lval in stackref_to_string")
	).

%-----------------------------------------------------------------------------%

trace__path_to_string(Path, PathStr) :-
	trace__path_steps_to_strings(Path, StepStrs),
	list__reverse(StepStrs, RevStepStrs),
	string__append_list(RevStepStrs, PathStr).

:- pred trace__path_steps_to_strings(goal_path::in, list(string)::out) is det.

trace__path_steps_to_strings([], []).
trace__path_steps_to_strings([Step | Steps], [StepStr | StepStrs]) :-
	trace__path_step_to_string(Step, StepStr),
	trace__path_steps_to_strings(Steps, StepStrs).

:- pred trace__path_step_to_string(goal_path_step::in, string::out) is det.

trace__path_step_to_string(conj(N), Str) :-
	string__int_to_string(N, NStr),
	string__append_list(["c", NStr, ";"], Str).
trace__path_step_to_string(disj(N), Str) :-
	string__int_to_string(N, NStr),
	string__append_list(["d", NStr, ";"], Str).
trace__path_step_to_string(switch(N), Str) :-
	string__int_to_string(N, NStr),
	string__append_list(["s", NStr, ";"], Str).
trace__path_step_to_string(ite_cond, "?;").
trace__path_step_to_string(ite_then, "t;").
trace__path_step_to_string(ite_else, "e;").
trace__path_step_to_string(neg, "~;").
trace__path_step_to_string(exist, "q;").

:- pred trace__convert_external_port_type(external_trace_port::in,
	trace_port::out) is det.

trace__convert_external_port_type(call, call).
trace__convert_external_port_type(exit, exit).
trace__convert_external_port_type(fail, fail).

:- pred trace__convert_nondet_pragma_port_type(nondet_pragma_trace_port::in,
	trace_port::out) is det.

trace__convert_nondet_pragma_port_type(nondet_pragma_first,
	nondet_pragma_first).
trace__convert_nondet_pragma_port_type(nondet_pragma_later,
	nondet_pragma_later).

%-----------------------------------------------------------------------------%

:- pred trace__event_num_slot(code_model::in, lval::out) is det.
:- pred trace__call_num_slot(code_model::in, lval::out) is det.
:- pred trace__call_depth_slot(code_model::in, lval::out) is det.
:- pred trace__redo_layout_slot(code_model::in, lval::out) is det.

trace__event_num_slot(CodeModel, EventNumSlot) :-
	( CodeModel = model_non ->
		EventNumSlot  = framevar(1)
	;
		EventNumSlot  = stackvar(1)
	).

trace__call_num_slot(CodeModel, CallNumSlot) :-
	( CodeModel = model_non ->
		CallNumSlot   = framevar(2)
	;
		CallNumSlot   = stackvar(2)
	).

trace__call_depth_slot(CodeModel, CallDepthSlot) :-
	( CodeModel = model_non ->
		CallDepthSlot = framevar(3)
	;
		CallDepthSlot = stackvar(3)
	).

trace__redo_layout_slot(CodeModel, RedoLayoutSlot) :-
	( CodeModel = model_non ->
		RedoLayoutSlot = framevar(4)
	;
		error("attempt to access redo layout slot for det or semi procedure")
	).

%-----------------------------------------------------------------------------%
