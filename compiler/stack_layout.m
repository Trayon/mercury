%---------------------------------------------------------------------------%
% Copyright (C) 1997-2000 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% This module generates the LLDS code that defines global constants to
% hold the `stack_layout' structures of the stack frames defined by the
% current module.
%
% The tables generated have a number of `create' rvals within them.
% llds_common.m converts these into static data structures.
%
% We can create several types of stack layouts. Which kind we generate
% depends on the values of several options.
%
% Main authors: trd, zs.
%
% NOTE: If you make changes in this file, you may also need to modify
% runtime/mercury_stack_layout.h.
%
%---------------------------------------------------------------------------%
%
% Data Stucture: stack_layouts
%
% If the option basic_stack_layout is set, we generate a MR_Stack_Layout_Entry
% for each procedure. This will be stored in the global variable whose name is
%	mercury_data__layout__mercury__<proc_label>.
% This structure will always contain stack tracing information:
%
%	code address		(Code *) - address of entry
% 	succip stack location	(uint_least32_t) actually, type MR_Long_Lval
% 					(the location will be set to -1
% 					if there is no succip available).
% 	number of stack slots	(uint_least16_t)
% 	determinism		(uint_least16_t) actually, type MR_Determinism
%
% If the option procid_stack_layout is set, i.e. if we are doing stack
% tracing, execution tracing or profiling, the structure will also include
% information on the identity of the procedure. This information will take
% one of two forms. Almost all procedures use the first form:
%
%	predicate/function	(Integer) actually, MR_pred_func
%	declaring module name	(String)
%	defining module name	(String)
%	predicate name		(String)
%	predicate arity		(int_least16_t)
%	procedure number	(int_least16_t)
%
% Automatically generated unification, index and comparison predicates
% use the second form:
%
%	type name		(String)
%	type module's name	(String)
%	defining module name	(String)
%	predicate name		(String)
%	predicate arity		(int_least16_t)
%	procedure number	(int_least16_t)
%
% The runtime system can figure out which form is present by testing
% the value of the first slot. A value of 0 or 1 indicates the first form;
% any higher value indicates the second form. The distinguished value -1
% indicates that procid_stack_layout is not set, and that the later fields
% are not present.
%
% The meanings of the fields in both forms are the same as in procedure labels.
%
% If the option trace_stack_layout is set, i.e. if we are doing execution
% tracing, the structure will also include some extra fields:
%
%	call trace info		(MR_Stack_Layout_Label *) - points to the
%				layout structure of the call event
%	module layout		(MR_Module_Layout *) - points to the layout
%				struct of the containing module.
%	variable names		(int_least16_t *) - pointer to an array of
%				offsets into the module-wide string table
%	variable name count	(int_least16_t) - the number of offsets in the
%				variable names array
%	max reg at trace event	(int_least16_t) - the number of the highest
%				numbered rN register live at a trace event
%				inside the procedure
%	maybe from full		(int_least8_t) - number of the stack slot of
%				the from_full flag, if the procedure is
%				shallow traced
%	maybe trail		(int_least8_t) - number of the first of two
%				stack slots used for recording the state of
%				the trail, if trailing is enabled
%	maybe decl debug	(int_least8_t) - number of the first of two
%				stack slots used by the declarative debugger,
%				if --trace-decl is set
%
% The call trace info field will point to the label layout structure for the
% label associated with the call event at the entry to the procedure. The
% purpose of this information is to allow the runtime debugger to find out
% which variables are where on entry, so it can reexecute the procedure if
% asked to do so and if the values of the required variables are still
% available. (If trace_stack_layout is not set, this field will be present,
% but it will be set to NULL.)
%
% The module layout field will point to the layout structure of the entire
% module. Amongst other things, the string table for the module is stored
% there. The variable names field points to an array that contains offsets
% into the string table, with the offset at index i-1 giving the name of
% variable i (since variable numbers start at one). If a variable has no name
% or cannot be referred to from an event, the offset will be zero, at which
% offset the string table will contain an empty string. The string table
% is restricted to be small enough to be addressed with 16 bits;
% a string is reserved near the start for a string that says "too many
% variables". Stack_layout.m will generate a reference to this string
% instead of generating an offset that does not fit into 16 bits.
% Therefore using the stored offset to index into the string table
% is always safe.
%
% If the procedure is compiled with deep tracing, the from full field will
% contain a negative number. If it is compiled with shallow tracing, it will
% contain the number of the stack slot that holds the flag that says whether
% this incarnation of the procedure was called from deeply traced code or not.
% (The determinism of the procedure decides whether the stack slot refers
% to a stackvar or a framevar.)
%
% If --trace-decl is not set, the maybe decl debug field will contain a
% negative number. If it is set, it will contain the number of the first
% of two stack slots used by the declarative debugger; the other slot is
% the next higher numbered one. (The determinism of the procedure decides
% whether the stack slot refers to a stackvar or a framevar.)
%
% If the option basic_stack_layout is set, we generate stack layout tables
% for some labels internal to the procedure. This table will be stored in the
% global variable whose name is
%	mercury_data__layout__mercury__<proc_label>_i<label_number>.
% This table has the following format:
%
%	proc layout		(Word *) - pointer to the layout structure of
%				the procedure containing this label
% 	trace port		(int_least16) - a representation of the trace
%				port associated with the label, or -1
% 	goal path		(int_least16) - an index into the module's
%				string table giving the goal path associated
%				with the trace port of the label, or -1
% 	# of live data items	(Integer) - an encoded representation of
%				the number of live data items at the label
% 	live data types locns 	(void *) - pointer to an area of memory
%				containing information about where the live
%				data items are and what their types are
% 	live data var nums	(int_least16 *) - pointer to vector of ints
%				giving the HLDS var numbers (if any) of live
%				data items
%	type parameters		(MR_Long_Lval *) - pointer to vector of
%			 	MR_Long_Lval giving the locations of the
%				typeinfos for the type parameters that may
%				be referred to by the types of the live data
%				items; the first word of the vector is an
%				integer giving the number of entries in the
%				vector; a NULL pointer means no type parameters
%
% The layout of the memory area containing information about the locations
% and types of live data items is somewhat complicated, due to our desire
% to make this information compact. We can represent a location in one of
% two ways, as an 8-bit MR_Short_Lval or as a 32-bit MR_Long_Lval.
% We prefer representing a location as an MR_Short_Lval, but of course
% not all locations can be represented in this way, so those other locations
% are represented as MR_Long_Lvals.
%
% The field containing the number of live data items is encoded by the
% formula (#Long << short_count_bits + #Short), where #Short is the number
% data items whose descriptions fit into an MR_Short_Lval and #Long is the
% number of data items whose descriptions do not. (The field is not an integer
% so that people who attempt to use it without going through the decoding
% macros in runtime/mercury_stack_layout.h get an error from the C compiler.
% The number of distinct values that fit into a uint_least_t also fits into
% 8 bits, but since some locations hold the value of more than one variable
% at a time, not all the values need to be distinct; this is why
% short_count_bits is more than 8.)
%
% The memory area contains three vectors back to back. The first vector
% has #Long + #Short word-sized elements, each of which is a pointer to a
% MR_PseudoTypeInfo giving the type of a live data item, with a small
% integer instead of a pointer representing a special kind of live data item
% (e.g. a saved succip or hp). The second vector is an array of #Long
% MR_Long_Lvals, and the third is an array of #Short MR_Short_Lvals,
% each of which describes a location. The pseudotypeinfo pointed to by
% the slot at subscript i in the first vector describes the type of
% the data stored in slot i in the second vector if i < #Long, and
% the type of the data stored in slot i - #Long in the third vector
% otherwise.
%
% The live data pair vector will have an entry for each live variable.
% The entry will give the location of the variable and its type.
%
% The live data var nums vector pointer may be NULL. If it is not, the vector
% will have an entry consisting of a 16-bit number for each live data item.
% This is either the live data item's HLDS variable number, or one of two
% special values. Zero means that the live data item is not a variable
% (e.g. it is a saved copy of succip). The largest possible 16-bit number
% on the other hand means "the number of this variable does not fit into
% 16 bits". With the exception of these special values, the value in this
% slot uniquely identifies the variable.
%
% If the number of type parameters is not zero, we store the number,
% so that the code that needs the type parameters can materialize
% all the type parameters from their location descriptions in one go.
% This is an optimization, since the type parameter vector could simply
% be indexed on demand by the type variable's variable number stored within
% pseudo-typeinfos inside the elements of the live data pairs vectors.
%
% Since we allocate type variable numbers sequentially, the type parameter
% vector will usually be dense. However, after all variables whose types
% include e.g. type variable 2 have gone out of scope, variables whose
% types include type variable 3 may still be around. In cases like this,
% the entry for type variable 2 will be zero; this signals to the code
% in the internal debugger that materializes typeinfo structures that
% this typeinfo structure need not be materialized.
%
% We need detailed information about the variables that are live at an
% internal label in two kinds of circumstances. Stack layout information
% will be present only for labels that fall into one or both of these
% circumstances.
%
% -	The option trace_stack_layout is set, and the label represents
%	a traced event at which variable info is needed (call, exit,
%	or entrance to one branch of a branched control structure;
%	fail events have no variable information).
%
% -	The option agc_stack_layout is set or the trace level specifies
%	a capability for uplevel printing, and the label represents
% 	a point where execution can resume after a procedure call or
%	after backtracking.
%
% For labels that do not fall into one of these two categories, the
% "# of live vars" field will be negative to indicate the absence of
% information about the variables live at this label, and the last
% four fields will not be present.
%
% For labels that do fall into one of these two categories, the
% "# of live vars" field will hold the number of live variables, which
% will not be negative. If it is zero, the last four fields will not be
% present. Even if it is not zero, however, the pointer to the live data
% names vector will be NULL unless the label is used in execution tracing.
%
% XXX: Presently, inst information is ignored. We also do not yet enable
% procid stack layouts for profiling, since profiling does not yet use
% stack layouts.
%
%---------------------------------------------------------------------------%

:- module stack_layout.

:- interface.

:- import_module continuation_info, hlds_module, llds.
:- import_module std_util, list, set_bbbtree, counter.

:- pred stack_layout__generate_llds(module_info::in, module_info::out,
	global_data::in,
	list(comp_gen_c_data)::out, list(comp_gen_c_data)::out,
	set_bbbtree(label)::out) is det.

:- pred stack_layout__construct_closure_layout(proc_label::in,
	closure_layout_info::in, list(maybe(rval))::out,
	create_arg_types::out, counter::in, counter::out) is det.

:- implementation.

:- import_module globals, options, llds_out, trace_params, trace.
:- import_module hlds_data, hlds_goal, hlds_pred.
:- import_module prog_data, prog_util, prog_out, instmap.
:- import_module prog_rep, static_term.
:- import_module rtti, ll_pseudo_type_info, (inst), code_util.
:- import_module assoc_list, bool, string, int, require.
:- import_module map, term, set, varset.

%---------------------------------------------------------------------------%

	% Process all the continuation information stored in the HLDS,
	% converting it into LLDS data structures.

stack_layout__generate_llds(ModuleInfo0, ModuleInfo, GlobalData,
		PossiblyDynamicLayouts, StaticLayouts, LayoutLabels) :-
	global_data_get_all_proc_layouts(GlobalData, ProcLayoutList0),
	list__filter(stack_layout__valid_proc_layout, ProcLayoutList0,
		ProcLayoutList),

	module_info_globals(ModuleInfo0, Globals),
	globals__lookup_bool_option(Globals, agc_stack_layout, AgcLayout),
	globals__lookup_bool_option(Globals, trace_stack_layout, TraceLayout),
	globals__lookup_bool_option(Globals, procid_stack_layout,
		ProcIdLayout),
	globals__get_trace_level(Globals, TraceLevel),
	globals__get_trace_suppress(Globals, TraceSuppress),
	globals__have_static_code_addresses(Globals, StaticCodeAddr),
	set_bbbtree__init(LayoutLabels0),

	map__init(StringMap0),
	map__init(LabelTables0),
	StringTable0 = string_table(StringMap0, [], 0),
	LayoutInfo0 = stack_layout_info(ModuleInfo0,
		AgcLayout, TraceLayout, ProcIdLayout,
		TraceLevel, TraceSuppress,
		StaticCodeAddr, [], [], LayoutLabels0, [],
		StringTable0, LabelTables0, map__init),
	stack_layout__lookup_string_in_table("", _, LayoutInfo0, LayoutInfo1),
	stack_layout__lookup_string_in_table("<too many variables>", _,
		LayoutInfo1, LayoutInfo2),
	list__foldl(stack_layout__construct_layouts, ProcLayoutList,
		LayoutInfo2, LayoutInfo3),
		% This version of the layout info structure is final in all
		% respects except the cell count.
	ProcLayouts = LayoutInfo3 ^ proc_layouts,
	InternalLayouts = LayoutInfo3 ^ internal_layouts,
	LayoutLabels = LayoutInfo3 ^ label_set,
	ProcLayoutArgs = LayoutInfo3 ^ proc_layout_args,
	StringTable = LayoutInfo3 ^ string_table,
	LabelTables = LayoutInfo3 ^ label_tables,
	StringTable = string_table(_, RevStringList, StringOffset),
	list__reverse(RevStringList, StringList),
	stack_layout__concat_string_list(StringList, StringOffset,
		ConcatStrings),

	( TraceLayout = yes ->
		Exported = no,	% ignored; see linkage/2 in llds_out.m
		list__length(ProcLayoutList, NumProcLayouts),
		module_info_name(ModuleInfo0, ModuleName),
		llds_out__sym_name_mangle(ModuleName, ModuleNameStr),
		stack_layout__get_next_cell_number(ProcVectorCellNum,
			LayoutInfo3, LayoutInfo4),
		Reuse = no,
		ProcLayoutVector = create(0, ProcLayoutArgs,
			uniform(yes(data_ptr)), must_be_static, 
			ProcVectorCellNum, "proc_layout_vector", Reuse),
		globals__lookup_bool_option(Globals, rtti_line_numbers,
			LineNumbers),
		( LineNumbers = yes ->
			EffLabelTables = LabelTables
		;
			map__init(EffLabelTables)
		),
		stack_layout__format_label_tables(EffLabelTables,
			NumSourceFiles, SourceFileVectors,
			LayoutInfo4, LayoutInfo),
		Rvals = [yes(const(string_const(ModuleNameStr))),
			yes(const(int_const(StringOffset))),
			yes(const(multi_string_const(StringOffset,
				ConcatStrings))),
			yes(const(int_const(NumProcLayouts))),
			yes(ProcLayoutVector),
			yes(const(int_const(NumSourceFiles))),
			yes(SourceFileVectors)],
		ModuleLayouts = comp_gen_c_data(ModuleName, module_layout,
			Exported, Rvals, uniform(no), []),
		StaticLayouts = [ModuleLayouts | InternalLayouts]
	;
		StaticLayouts = InternalLayouts,
		LayoutInfo = LayoutInfo3
	),
	PossiblyDynamicLayouts = ProcLayouts,
	stack_layout__get_module_info(ModuleInfo, LayoutInfo, _).

:- pred stack_layout__valid_proc_layout(proc_layout_info::in) is semidet.

stack_layout__valid_proc_layout(ProcLayoutInfo) :-
	EntryLabel = ProcLayoutInfo ^ entry_label,
	code_util__extract_proc_label_from_label(EntryLabel, ProcLabel),
	(
		ProcLabel = proc(_, _, DeclModule, Name, Arity, _),
		\+ no_type_info_builtin(DeclModule, Name, Arity)
	;
		ProcLabel = special_proc(_, _, _, _, _, _)
	).

%---------------------------------------------------------------------------%

:- pred stack_layout__concat_string_list(list(string)::in, int::in,
	string::out) is det.

:- pragma c_code(stack_layout__concat_string_list(StringList::in,
		ArenaSize::in, Arena::out),
		[will_not_call_mercury, thread_safe], "{
	Word	cur_node;
	Integer	cur_offset;
	Word	tmp;

	incr_hp_atomic(tmp, (ArenaSize + sizeof(Word)) / sizeof(Word));
	Arena = (char *) tmp;

	cur_offset = 0;
	cur_node = StringList;

	while (! MR_list_is_empty(cur_node)) {
		(void) strcpy(&Arena[cur_offset],
			(char *) MR_list_head(cur_node));
		cur_offset += strlen((char *) MR_list_head(cur_node)) + 1;
		cur_node = MR_list_tail(cur_node);
	}

	if (cur_offset != ArenaSize) {
		char	msg[256];

		sprintf(msg, ""internal error in creating string table;\\n""
			""cur_offset = %ld, ArenaSize = %ld\\n"",
			(long) cur_offset, (long) ArenaSize);
		MR_fatal_error(msg);
	}
}").

%---------------------------------------------------------------------------%

:- pred stack_layout__format_label_tables(map(string, label_table)::in,
	int::out, rval::out, stack_layout_info::in, stack_layout_info::out)
	is det.

stack_layout__format_label_tables(LabelTableMap, NumSourceFiles,
		SourceFilesVector, LayoutInfo0, LayoutInfo) :-
	map__to_assoc_list(LabelTableMap, LabelTableList),
	list__length(LabelTableList, NumSourceFiles),
	list__map_foldl(stack_layout__format_label_table, LabelTableList,
		SourceFileRvals, LayoutInfo0, LayoutInfo1),
	stack_layout__get_next_cell_number(SourceFileVectorCellNum,
		LayoutInfo1, LayoutInfo),
	Reuse = no,
	SourceFilesVector = create(0, SourceFileRvals,
		uniform(yes(data_ptr)), must_be_static, 
		SourceFileVectorCellNum, "source_files_vector", Reuse).

:- pred stack_layout__format_label_table(pair(string, label_table)::in,
	maybe(rval)::out, stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__format_label_table(FileName - LineNoMap, yes(SourceFileVector),
		LayoutInfo0, LayoutInfo) :-
		% This step should produce a list ordered on line numbers.
	map__to_assoc_list(LineNoMap, LineNoList),
		% And this step should preserve that order.
	stack_layout__flatten_label_table(LineNoList, [], FlatLineNoList),
	list__length(FlatLineNoList, VectorLength),
	stack_layout__get_module_name(CurrentModule, LayoutInfo0, LayoutInfo1),

	ProjectLineNos = (pred(LabelInfo::in, LineNoRval::out) is det :-
		LabelInfo = LineNo - (_Label - _IsReturn),
		LineNoRval = yes(const(int_const(LineNo)))
	),
	ProjectLabels = (pred(LabelInfo::in, LabelRval::out) is det :-
		LabelInfo = _LineNo - (Label - _IsReturn),
		DataAddr = data_addr(CurrentModule, internal_layout(Label)),
		LabelRval = yes(const(data_addr_const(DataAddr)))
	),
% See the comment below.
%	ProjectCallees = lambda([LabelInfo::in, CalleeRval::out] is det, (
%		LabelInfo = _LineNo - (_Label - IsReturn),
%		(
%			IsReturn = not_a_return,
%			CalleeRval = yes(const(int_const(0)))
%		;
%			IsReturn = unknown_callee,
%			CalleeRval = yes(const(int_const(1)))
%		;
%			IsReturn = known_callee(Label),
%			code_util__extract_proc_label_from_label(Label,
%				ProcLabel),
%			(
%				ProcLabel = proc(ModuleName, _, _, _, _, _)
%			;
%				ProcLabel = special_proc(ModuleName, _, _,
%					_, _, _)
%			),
%			DataAddr = data_addr(ModuleName, proc_layout(Label)),
%			CalleeRval = yes(const(data_addr_const(DataAddr)))
%		)
%	)),

	list__map(ProjectLineNos, FlatLineNoList, LineNoRvals),
	stack_layout__get_next_cell_number(LineNoVectorCellNum,
		LayoutInfo1, LayoutInfo2),
	Reuse = no,
	LineNoVector = create(0, LineNoRvals,
		uniform(yes(int_least16)), must_be_static, 
		LineNoVectorCellNum, "line_number_vector", Reuse),

	list__map(ProjectLabels, FlatLineNoList, LabelRvals),
	stack_layout__get_next_cell_number(LabelsVectorCellNum,
		LayoutInfo2, LayoutInfo3),
	LabelsVector = create(0, LabelRvals,
		uniform(yes(data_ptr)), must_be_static, 
		LabelsVectorCellNum, "label_vector", Reuse),

% We do not include the callees vector in the table because it makes references
% to the proc layouts of procedures from other modules without knowing whether
% those modules were compiled with debugging. This works only if all procedures
% always have a proc layout structure, which we don't want to require yet.
%
% Callees vectors would allow us to use faster code to check at every event
% whether a breakpoint applies to that event, in the usual case that no context
% breakpoint is on a line contains a higher order call. Instead of always
% searching a separate data structure, as we now do, to check for the
% applicability of context breakpoints, the code could search this data
% structure only if the proc layout matched the proc layout of the caller
% Since we already search a table of proc layouts in order to check for plain,
% non-context breakpoints on procedures, this would incur no extra cost
% in most cases.
%
%	list__map(ProjectCallees, FlatLineNoList, CalleeRvals),
%	stack_layout__get_next_cell_number(CalleesVectorCellNum,
%		LayoutInfo3, LayoutInfo4),
%	CalleesVector = create(0, CalleeRvals,
%		uniform(no), must_be_static, 
%		CalleesVectorCellNum, "callee_vector", Reuse),

	SourceFileRvals = [
		yes(const(string_const(FileName))),
		yes(const(int_const(VectorLength))),
		yes(LineNoVector),
		yes(LabelsVector)
%		yes(CalleesVector)
	],
	stack_layout__get_next_cell_number(SourceFileVectorCellNum,
		LayoutInfo3, LayoutInfo),
	SourceFileVector = create(0, SourceFileRvals,
		initial([1 - yes(string), 1 - yes(integer),
			2 - yes(data_ptr)], none),
		must_be_static, 
		SourceFileVectorCellNum, "source_file_vector", Reuse).

:- pred stack_layout__flatten_label_table(
	assoc_list(int, list(line_no_info))::in,
	assoc_list(int, line_no_info)::in,
	assoc_list(int, line_no_info)::out) is det.

stack_layout__flatten_label_table([], RevList, List) :-
	list__reverse(RevList, List).
stack_layout__flatten_label_table([LineNo - LinesInfos | Lines],
		RevList0, List) :-
	list__foldl(stack_layout__add_line_no(LineNo), LinesInfos,
		RevList0, RevList1),
	stack_layout__flatten_label_table(Lines, RevList1, List).

:- pred stack_layout__add_line_no(int::in, line_no_info::in,
	assoc_list(int, line_no_info)::in,
	assoc_list(int, line_no_info)::out) is det.

stack_layout__add_line_no(LineNo, LineInfo, RevList0, RevList) :-
	RevList = [LineNo - LineInfo | RevList0].

%---------------------------------------------------------------------------%

	% Construct the layouts that concern a single procedure:
	% the procedure-specific layout and the layouts of the labels
	% inside that procedure. Also update the module-wide label table
	% with the labels defined in this procedure.

:- pred stack_layout__construct_layouts(proc_layout_info::in,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_layouts(ProcLayoutInfo) -->
	{ ProcLayoutInfo = proc_layout_info(EntryLabel, Detism,
		StackSlots, SuccipLoc, MaybeCallLabel, MaxTraceReg,
		Goal, InstMap, TraceSlotInfo, ForceProcIdLayout,
		VarSet, InternalMap) },
	{ map__to_assoc_list(InternalMap, Internals) },
	stack_layout__set_cur_proc_named_vars(map__init),
	list__foldl(stack_layout__construct_internal_layout(EntryLabel),
		Internals),
	stack_layout__get_cur_proc_named_vars(NamedVars),
	stack_layout__get_label_tables(LabelTables0),
	{ list__foldl(stack_layout__update_label_table, Internals,
		LabelTables0, LabelTables) },
	stack_layout__set_label_tables(LabelTables),
	stack_layout__construct_proc_layout(EntryLabel, Detism,
		StackSlots, SuccipLoc, MaybeCallLabel, MaxTraceReg,
		Goal, InstMap, TraceSlotInfo, ForceProcIdLayout,
		VarSet, NamedVars).

%---------------------------------------------------------------------------%

	% Add the given label to the module-wide label tables.

:- pred stack_layout__update_label_table(pair(label, internal_layout_info)::in,
	map(string, label_table)::in, map(string, label_table)::out) is det.

stack_layout__update_label_table(Label - InternalInfo,
		LabelTables0, LabelTables) :-
	InternalInfo = internal_layout_info(Port, _, Return),
	(
		Return = yes(return_layout_info(TargetsContexts, _)),
		stack_layout__find_valid_return_context(TargetsContexts,
			Target, Context)
	->
		( Target = label(TargetLabel) ->
			IsReturn = known_callee(TargetLabel)
		;
			IsReturn = unknown_callee
		),
		stack_layout__update_label_table_2(Label, Context, IsReturn,
			LabelTables0, LabelTables)
	;
		Port = yes(trace_port_layout_info(Context, _, _, _)),
		stack_layout__context_is_valid(Context)
	->
		stack_layout__update_label_table_2(Label, Context,
			not_a_return, LabelTables0, LabelTables)
	;
		LabelTables = LabelTables0
	).

:- pred stack_layout__update_label_table_2(label::in, context::in,
	is_label_return::in,
	map(string, label_table)::in, map(string, label_table)::out) is det.

stack_layout__update_label_table_2(Label, Context, IsReturn,
		LabelTables0, LabelTables) :-
	term__context_file(Context, File),
	term__context_line(Context, Line),
	( map__search(LabelTables0, File, LabelTable0) ->
		( map__search(LabelTable0, Line, LineInfo0) ->
			LineInfo = [Label - IsReturn | LineInfo0],
			map__det_update(LabelTable0, Line, LineInfo,
				LabelTable),
			map__det_update(LabelTables0, File, LabelTable,
				LabelTables)
		;
			LineInfo = [Label - IsReturn],
			map__det_insert(LabelTable0, Line, LineInfo,
				LabelTable),
			map__det_update(LabelTables0, File, LabelTable,
				LabelTables)
		)
	; stack_layout__context_is_valid(Context) ->
		map__init(LabelTable0),
		LineInfo = [Label - IsReturn],
		map__det_insert(LabelTable0, Line, LineInfo, LabelTable),
		map__det_insert(LabelTables0, File, LabelTable, LabelTables)
	;
			% We don't have a valid context for this label,
			% so we don't enter it into any tables.
		LabelTables = LabelTables0
	).

:- pred stack_layout__find_valid_return_context(
	assoc_list(code_addr, prog_context)::in,
	code_addr::out, prog_context::out) is semidet.

stack_layout__find_valid_return_context([Target - Context | TargetContexts],
		ValidTarget, ValidContext) :-
	( stack_layout__context_is_valid(Context) ->
		ValidTarget = Target,
		ValidContext = Context
	;
		stack_layout__find_valid_return_context(TargetContexts,
			ValidTarget, ValidContext)
	).

:- pred stack_layout__context_is_valid(prog_context::in) is semidet.

stack_layout__context_is_valid(Context) :-
	term__context_file(Context, File),
	term__context_line(Context, Line),
	File \= "",
	Line > 0.

%---------------------------------------------------------------------------%

	% Construct a procedure-specific layout.

:- pred stack_layout__construct_proc_layout(label::in, determinism::in,
	int::in, maybe(int)::in, maybe(label)::in, int::in,
	hlds_goal::in, instmap::in, trace_slot_info::in, bool::in,
	prog_varset::in, map(int, string)::in,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_proc_layout(EntryLabel, Detism, StackSlots,
		MaybeSuccipLoc, MaybeCallLabel, MaxTraceReg, Goal, InstMap,
		TraceSlotInfo, ForceProcIdLayout, VarSet, UsedVarNames) -->
	{
		MaybeSuccipLoc = yes(Location0)
	->
		Location = Location0
	;
			% Use a dummy location of -1 if there is
			% no succip on the stack.
			%
			% This case can arise in two circumstances.
			% First, procedures that use the nondet stack
			% have a special slot for the succip, so the
			% succip is not stored in a general purpose
			% slot. Second, procedures that use the det stack
			% but which do not call other procedures
			% do not save the succip on the stack.
			%
			% The tracing system does not care about the
			% location of the saved succip. The accurate
			% garbage collector does. It should know from
			% the determinism that the procedure uses the
			% nondet stack, which takes care of the first
			% possibility above. Procedures that do not call
			% other procedures do not establish resumption
			% points and thus agc is not interested in them.
			% As far as stack dumps go, calling error counts
			% as a call, so any procedure that may call error
			% (directly or indirectly) will have its saved succip
			% location recorded, so the stack dump will work.
			%
			% Future uses of stack layouts will have to have
			% similar constraints.
		Location = -1
	},
	stack_layout__get_static_code_addresses(StaticCodeAddr),
	{ StaticCodeAddr = yes ->
		CodeAddrRval = const(code_addr_const(label(EntryLabel)))
	;
		% This is a lie; the slot will be filled in for real
		% at initialization time.
		CodeAddrRval = const(int_const(0))
	},
	{ determinism_components(Detism, _, at_most_many) ->
		SuccipLval = framevar(Location)
	;
		SuccipLval = stackvar(Location)
	},
	{ stack_layout__represent_locn_as_int(direct(SuccipLval), SuccipRval) },
	{ StackSlotsRval = const(int_const(StackSlots)) },
	{ stack_layout__represent_determinism(Detism, DetismRval) },
	{ TraversalRvals = [yes(CodeAddrRval), yes(SuccipRval),
		yes(StackSlotsRval), yes(DetismRval)] },
	{ TraversalArgTypes = [1 - yes(code_ptr), 1 - yes(uint_least32),
		2 - yes(uint_least16)] },

	stack_layout__get_procid_stack_layout(ProcIdLayout0),
	{ bool__or(ProcIdLayout0, ForceProcIdLayout, ProcIdLayout) },
	( { ProcIdLayout = yes } ->
		{ code_util__extract_proc_label_from_label(EntryLabel,
			ProcLabel) },
		{ stack_layout__construct_procid_rvals(ProcLabel, IdRvals,
			IdArgTypes) },
		stack_layout__construct_trace_layout(MaybeCallLabel,
			MaxTraceReg, Goal, InstMap, TraceSlotInfo,
			VarSet, UsedVarNames, TraceRvals, TraceArgTypes),
		{ list__append(IdRvals, TraceRvals, IdTraceRvals) },
		{ IdTraceArgTypes = initial(IdArgTypes, TraceArgTypes) }
	;
		% Indicate the absence of the proc id and exec trace fields.
		{ IdTraceRvals = [yes(const(int_const(-1)))] },
		{ IdTraceArgTypes = initial([1 - yes(integer)], none) }
	),

	{ Exported = no },	% XXX With the new profiler, we will need to
				% set this to `yes' if the profiling option
				% is given and if the procedure is exported.
				% Beware however that linkage/2 in llds_out.m
				% assumes that this is `no'.
	{ list__append(TraversalRvals, IdTraceRvals, Rvals) },
	{ ArgTypes = initial(TraversalArgTypes, IdTraceArgTypes) },
	stack_layout__get_module_name(ModuleName),
	{ CDataName = proc_layout(EntryLabel) },
	{ CData = comp_gen_c_data(ModuleName, CDataName, Exported,
		Rvals, ArgTypes, []) },
	stack_layout__add_proc_layout_data(CData, CDataName, EntryLabel).

:- pred stack_layout__construct_trace_layout(maybe(label)::in, int::in,
	hlds_goal::in, instmap::in, trace_slot_info::in,
	prog_varset::in, map(int, string)::in,
	list(maybe(rval))::out, create_arg_types::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_trace_layout(MaybeCallLabel, MaxTraceReg,
		Goal, InstMap, TraceSlotInfo, VarSet, UsedVarNameMap,
		Rvals, ArgTypes) -->
	stack_layout__get_trace_stack_layout(TraceLayout),
	( { TraceLayout = yes } ->
		stack_layout__construct_var_name_vector(VarSet, UsedVarNameMap,
			VarNameCount, VarNameVector),
		stack_layout__get_trace_level(TraceLevel),
		stack_layout__get_trace_suppress(TraceSuppress),
		{ trace_needs_proc_body_reps(TraceLevel, TraceSuppress)
			= BodyReps },
		(
			{ BodyReps = no },
			{ GoalRepRval = yes(const(int_const(0))) }
		;
			{ BodyReps = yes },
			stack_layout__get_module_info(ModuleInfo0),
			{ prog_rep__represent_goal(Goal, InstMap, ModuleInfo0,
				GoalRep) },
			{ type_to_univ(GoalRep, GoalRepUniv) },
			stack_layout__get_cell_counter(CellCounter0),
			{ static_term__term_to_rval(GoalRepUniv, GoalRepRval,
				CellCounter0, CellCounter) },
			stack_layout__set_cell_counter(CellCounter)
		),
		stack_layout__get_module_info(ModuleInfo),
		{
		( MaybeCallLabel = yes(CallLabel) ->
			module_info_name(ModuleInfo, ModuleName),
			CallRval = yes(const(data_addr_const(
					data_addr(ModuleName,
						internal_layout(CallLabel)))))
		;
			error("stack_layout__construct_trace_layout: call label not present")
		),
		ModuleRval = yes(const(data_addr_const(
				data_addr(ModuleName, module_layout)))),
		MaxTraceRegRval = yes(const(int_const(MaxTraceReg))),
		TraceSlotInfo = trace_slot_info(MaybeFromFullSlot,
			MaybeDeclSlots, MaybeTrailSlot),
		( MaybeFromFullSlot = yes(FromFullSlot) ->
			FromFullRval = yes(const(int_const(FromFullSlot)))
		;
			FromFullRval = yes(const(int_const(-1)))
		),
		( MaybeDeclSlots = yes(DeclSlot) ->
			DeclRval = yes(const(int_const(DeclSlot)))
		;
			DeclRval = yes(const(int_const(-1)))
		),
		( MaybeTrailSlot = yes(TrailSlot) ->
			TrailRval = yes(const(int_const(TrailSlot)))
		;
			TrailRval = yes(const(int_const(-1)))
		),
		Rvals = [CallRval, ModuleRval, GoalRepRval, VarNameVector,
			VarNameCount, MaxTraceRegRval,
			FromFullRval, TrailRval, DeclRval],
		ArgTypes = initial([
			4 - yes(data_ptr),
			2 - yes(int_least16),
			3 - yes(int_least8)],
			none)
		}
	;
		% Indicate the absence of the trace layout fields.
		{ Rvals = [yes(const(int_const(0)))] },
		{ ArgTypes = initial([1 - yes(integer)], none) }
	).

:- pred stack_layout__construct_var_name_vector(prog_varset::in,
	map(int, string)::in, maybe(rval)::out, maybe(rval)::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_var_name_vector(VarSet, UsedVarNameMap, Count, Vector)
		-->
	stack_layout__get_trace_level(TraceLevel),
	stack_layout__get_trace_suppress(TraceSuppress),
	{ trace_needs_all_var_names(TraceLevel, TraceSuppress)
		= NeedsAllNames },
	(
		{ NeedsAllNames = yes },
		{ varset__var_name_list(VarSet, VarNameList) },
		{ list__map(stack_layout__convert_var_name_to_int,
			VarNameList, VarNames) }
	;
		{ NeedsAllNames = no },
		{ map__to_assoc_list(UsedVarNameMap, VarNames) }
	),
	(
		{ VarNames = [FirstVar - _ | _] }
	->
		stack_layout__construct_var_name_rvals(VarNames, 1,
			FirstVar, MaxVar, Rvals),
		{ Count = yes(const(int_const(MaxVar))) },
		stack_layout__get_cell_counter(C0),
		{ counter__allocate(CNum, C0, C) },
		stack_layout__set_cell_counter(C),
		{ Reuse = no },
		{ Vector = yes(create(0, Rvals, uniform(yes(uint_least16)),
			must_be_static, CNum,
			"stack_layout_var_names_vector", Reuse)) }
	;
		{ Count = yes(const(int_const(0))) },
		{ Vector = yes(const(int_const(0))) }
	).

:- pred stack_layout__construct_var_name_rvals(assoc_list(int, string)::in,
	int::in, int::in, int::out, list(maybe(rval))::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_var_name_rvals([], _CurNum, MaxNum, MaxNum, []) --> [].
stack_layout__construct_var_name_rvals([Var - Name | VarNames1], CurNum,
		MaxNum0, MaxNum, MaybeRvals) -->
	( { Var = CurNum } ->
		stack_layout__lookup_string_in_table(Name, Offset),
		{ Rval = const(int_const(Offset)) },
		{ MaxNum1 = Var },
		{ VarNames = VarNames1 }
	;
		{ Rval = const(int_const(0)) },
		{ MaxNum1 = MaxNum0 },
		{ VarNames = [Var - Name | VarNames1] }
	),
	stack_layout__construct_var_name_rvals(VarNames, CurNum + 1,
		MaxNum1, MaxNum, MaybeRvals1),
	{ MaybeRvals = [yes(Rval) | MaybeRvals1] }.

%---------------------------------------------------------------------------%

:- pred stack_layout__construct_procid_rvals(proc_label::in,
	list(maybe(rval))::out, initial_arg_types::out) is det.

stack_layout__construct_procid_rvals(ProcLabel, Rvals, ArgTypes) :-
	(
		ProcLabel = proc(DefModule, PredFunc, DeclModule,
			PredName, Arity, ProcId),
		stack_layout__represent_pred_or_func(PredFunc, PredFuncCode),
		prog_out__sym_name_to_string(DefModule, DefModuleString),
		prog_out__sym_name_to_string(DeclModule, DeclModuleString),
		proc_id_to_int(ProcId, Mode),
		Rvals = [
				yes(const(int_const(PredFuncCode))),
				yes(const(string_const(DeclModuleString))),
				yes(const(string_const(DefModuleString))),
				yes(const(string_const(PredName))),
				yes(const(int_const(Arity))),
				yes(const(int_const(Mode)))
			],
		ArgTypes = [4 - no, 2 - yes(int_least16)]
	;
		ProcLabel = special_proc(DefModule, PredName, TypeModule,
			TypeName, Arity, ProcId),
		prog_out__sym_name_to_string(TypeModule, TypeModuleString),
		prog_out__sym_name_to_string(DefModule, DefModuleString),
		proc_id_to_int(ProcId, Mode),
		Rvals = [
				yes(const(string_const(TypeName))),
				yes(const(string_const(TypeModuleString))),
				yes(const(string_const(DefModuleString))),
				yes(const(string_const(PredName))),
				yes(const(int_const(Arity))),
				yes(const(int_const(Mode)))
			],
		ArgTypes = [4 - no, 2 - yes(int_least16)]
	).

:- pred stack_layout__represent_pred_or_func(pred_or_func::in, int::out) is det.

stack_layout__represent_pred_or_func(predicate, 0).
stack_layout__represent_pred_or_func(function, 1).

%---------------------------------------------------------------------------%

	% Construct the layout describing a single internal label.

:- pred stack_layout__construct_internal_layout(label::in,
	pair(label, internal_layout_info)::in,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_internal_layout(EntryLabel, Label - Internal) -->
		% generate the required rvals
	stack_layout__get_module_name(ModuleName),
	{ EntryAddrRval = const(data_addr_const(data_addr(ModuleName,
		proc_layout(EntryLabel)))) },
	stack_layout__construct_internal_rvals(Internal, VarInfoRvals,
		VarInfoRvalTypes),
	{ LayoutRvals = [yes(EntryAddrRval) | VarInfoRvals] },
	{ ArgTypes = initial([1 - no], VarInfoRvalTypes) },
	{ CData = comp_gen_c_data(ModuleName, internal_layout(Label),
		no, LayoutRvals, ArgTypes, []) },
	stack_layout__add_internal_layout_data(CData, Label).

	% Construct the rvals required for accurate GC or for tracing.

:- pred stack_layout__construct_internal_rvals(internal_layout_info::in,
	list(maybe(rval))::out, create_arg_types::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_internal_rvals(Internal, RvalList, ArgTypes) -->
	{ Internal = internal_layout_info(Trace, Resume, Return) },
	(
		{ Trace = no },
		{ set__init(TraceLiveVarSet) },
		{ map__init(TraceTypeVarMap) }
	;
		{ Trace = yes(trace_port_layout_info(_, _, _, TraceLayout)) },
		{ TraceLayout = layout_label_info(TraceLiveVarSet,
			TraceTypeVarMap) }
	),
	{ TraceArgTypes = [2 - yes(int_least16)] },
	{
		Resume = no,
		set__init(ResumeLiveVarSet),
		map__init(ResumeTypeVarMap)
	;
		Resume = yes(ResumeLayout),
		ResumeLayout = layout_label_info(ResumeLiveVarSet,
			ResumeTypeVarMap)
	},
	(
		{ Trace = yes(trace_port_layout_info(_, Port, Path, _)) },
		{ Return = no },
		{ llds_out__trace_port_to_num(Port, PortNum) },
		{ trace__path_to_string(Path, PathStr) },
		stack_layout__lookup_string_in_table(PathStr, PathNum)
	;
		{ Trace = no },
		{ Return = yes(_) },
			% We only ever use the port and path fields of these
			% layout structures when we process exception events.
		{ llds_out__trace_port_to_num(exception, PortNum) },
		{ PathNum = 0 }
	;
		{ Trace = no },
		{ Return = no },
		{ PortNum = -1 },
		{ PathNum = -1 }
	;
		{ Trace = yes(_) },
		{ Return = yes(_) },
		{ error("label has both trace and return layout info") }
	),
	{ TraceRvals = [yes(const(int_const(PortNum))),
			yes(const(int_const(PathNum)))] },
	stack_layout__get_agc_stack_layout(AgcStackLayout),
	{
		Return = no,
		set__init(ReturnLiveVarSet),
		map__init(ReturnTypeVarMap)
	;
		Return = yes(return_layout_info(_, ReturnLayout)),
		ReturnLayout = layout_label_info(ReturnLiveVarSet0,
			ReturnTypeVarMap0),
		( AgcStackLayout = yes ->
			ReturnLiveVarSet = ReturnLiveVarSet0,
			ReturnTypeVarMap = ReturnTypeVarMap0
		;
			% This set of variables must be for uplevel printing
			% in execution tracing, so we are interested only
			% in (a) variables, not temporaries, (b) only named
			% variables, and (c) only those on the stack, not
			% the return values.
			set__to_sorted_list(ReturnLiveVarSet0,
				ReturnLiveVarList0),
			stack_layout__select_trace_return(
				ReturnLiveVarList0, ReturnTypeVarMap0,
				ReturnLiveVarList, ReturnTypeVarMap),
			set__list_to_set(ReturnLiveVarList, ReturnLiveVarSet)
		)
	},
	(
		{ Trace = no },
		{ Resume = no },
		{ Return = no }
	->
			% The -1 says that there is no info available
			% about variables at this label. (Zero would say
			% that there are no variables live at this label,
			% which may not be true.)
		{ RvalList = [yes(const(int_const(-1)))] },
		{ ArgTypes = initial([1 - yes(integer)], none) }
	;
			% XXX ignore differences in insts inside var_infos
		{ set__union(TraceLiveVarSet, ResumeLiveVarSet, LiveVarSet0) },
		{ set__union(LiveVarSet0, ReturnLiveVarSet, LiveVarSet) },
		{ map__union(set__intersect, TraceTypeVarMap, ResumeTypeVarMap,
			TypeVarMap0) },
		{ map__union(set__intersect, TypeVarMap0, ReturnTypeVarMap,
			TypeVarMap) },
		stack_layout__construct_livelval_rvals(LiveVarSet,
			TypeVarMap, LivelvalRvalList, LivelvalArgTypes),
		{ append(TraceRvals, LivelvalRvalList, RvalList) },
		{ ArgTypes = initial(TraceArgTypes, LivelvalArgTypes) }
	).

%---------------------------------------------------------------------------%

:- pred stack_layout__construct_livelval_rvals(set(var_info)::in,
	map(tvar, set(layout_locn))::in, list(maybe(rval))::out,
	create_arg_types::out, stack_layout_info::in, stack_layout_info::out)
	is det.

stack_layout__construct_livelval_rvals(LiveLvalSet, TVarLocnMap,
		RvalList, ArgTypes) -->
	{ set__to_sorted_list(LiveLvalSet, LiveLvals) },
	{ list__length(LiveLvals, Length) },
	( { Length > 0 } ->
		{ stack_layout__sort_livevals(LiveLvals, SortedLiveLvals) },
		stack_layout__construct_liveval_arrays(SortedLiveLvals,
			VarLengthRval, LiveValRval, NamesRval),
		stack_layout__get_cell_counter(C0),
		{ stack_layout__construct_tvar_vector(TVarLocnMap,
			TypeParamRval, C0, C) },
		stack_layout__set_cell_counter(C),
		{ RvalList = [yes(VarLengthRval), yes(LiveValRval),
			yes(NamesRval), yes(TypeParamRval)] },
		{ ArgTypes = initial([1 - yes(integer), 3 - yes(data_ptr)],
			none) }
	;
		{ RvalList = [yes(const(int_const(0)))] },
		{ ArgTypes = initial([1 - yes(integer)], none) }
	).

:- pred stack_layout__construct_tvar_vector(map(tvar, set(layout_locn))::in,
	rval::out, counter::in, counter::out) is det.

stack_layout__construct_tvar_vector(TVarLocnMap, TypeParamRval, C0, C) :-
	( map__is_empty(TVarLocnMap) ->
		TypeParamRval = const(int_const(0)),
		C = C0
	;
		stack_layout__construct_tvar_rvals(TVarLocnMap,
			Vector, VectorTypes),
		counter__allocate(CNum, C0, C),
		Reuse = no,
		TypeParamRval = create(0, Vector, VectorTypes,
			must_be_static, CNum,
			"stack_layout_type_param_locn_vector", Reuse)
	).

:- pred stack_layout__construct_tvar_rvals(map(tvar, set(layout_locn))::in,
	list(maybe(rval))::out, create_arg_types::out) is det.

stack_layout__construct_tvar_rvals(TVarLocnMap, Vector, VectorTypes) :-
	map__to_assoc_list(TVarLocnMap, TVarLocns),
	stack_layout__construct_type_param_locn_vector(TVarLocns, 1,
		TypeParamLocs),
	list__length(TypeParamLocs, TypeParamsLength),
	LengthRval = const(int_const(TypeParamsLength)),
	Vector = [yes(LengthRval) | TypeParamLocs],
	VectorTypes = uniform(yes(uint_least32)).

%---------------------------------------------------------------------------%

	% Given a list of var_infos and the type variables that occur in them,
	% select only the var_infos that may be required by up-level printing
	% in the trace-based debugger. At the moment the typeinfo list we
	% return may be bigger than necessary, but this does not compromise
	% correctness; we do this to avoid having to scan the types of all
	% the selected var_infos.

:- pred stack_layout__select_trace_return(
	list(var_info)::in, map(tvar, set(layout_locn))::in,
	list(var_info)::out, map(tvar, set(layout_locn))::out) is det.

stack_layout__select_trace_return(Infos, TVars, TraceReturnInfos, TVars) :-
	IsNamedReturnVar = (pred(LocnInfo::in) is semidet :-
		LocnInfo = var_info(Locn, LvalType),
		LvalType = var(_, Name, _, _),
		Name \= "",
		( Locn = direct(Lval) ; Locn = indirect(Lval, _)),
		( Lval = stackvar(_) ; Lval = framevar(_) )
	),
	list__filter(IsNamedReturnVar, Infos, TraceReturnInfos).

	% Given a list of var_infos, put the ones that tracing can be
	% interested in (whether at an internal port or for uplevel printing)
	% in a block at the start, and both this block and the remaining
	% block. The division into two blocks can make the job of the
	% debugger somewhat easier, the sorting of the named var block makes
	% the output of the debugger look nicer, and the sorting of the both
	% blocks makes it more likely that different labels' layout structures
	% will have common parts (e.g. name vectors) that can be optimized
	% by llds_common.m.

:- pred stack_layout__sort_livevals(list(var_info)::in, list(var_info)::out)
	is det.

stack_layout__sort_livevals(OrigInfos, FinalInfos) :-
	IsNamedVar = (pred(LvalInfo::in) is semidet :-
		LvalInfo = var_info(_Lval, LvalType),
		LvalType = var(_, Name, _, _),
		Name \= ""
	),
	list__filter(IsNamedVar, OrigInfos, NamedVarInfos0, OtherInfos0),
	CompareVarInfos = (pred(Var1::in, Var2::in, Result::out) is det :-
		Var1 = var_info(Lval1, LiveType1),
		Var2 = var_info(Lval2, LiveType2),
		stack_layout__get_name_from_live_value_type(LiveType1, Name1),
		stack_layout__get_name_from_live_value_type(LiveType2, Name2),
		compare(NameResult, Name1, Name2),
		( NameResult = (=) ->
			compare(Result, Lval1, Lval2)
		;
			Result = NameResult
		)
	),
	list__sort(CompareVarInfos, NamedVarInfos0, NamedVarInfos),
	list__sort(CompareVarInfos, OtherInfos0, OtherInfos),
	list__append(NamedVarInfos, OtherInfos, FinalInfos).

:- pred stack_layout__get_name_from_live_value_type(live_value_type::in,
	string::out) is det.

stack_layout__get_name_from_live_value_type(LiveType, Name) :-
	( LiveType = var(_, NamePrime, _, _) ->
		Name = NamePrime
	;
		Name = ""
	).

%---------------------------------------------------------------------------%

	% Given a association list of type variables and their locations
	% sorted on the type variables, represent them in an array of
	% location descriptions indexed by the type variable. The next
	% slot to fill is given by the second argument.

:- pred stack_layout__construct_type_param_locn_vector(
	assoc_list(tvar, set(layout_locn))::in,
	int::in, list(maybe(rval))::out) is det.

stack_layout__construct_type_param_locn_vector([], _, []).
stack_layout__construct_type_param_locn_vector([TVar - Locns | TVarLocns],
		CurSlot, Vector) :-
	term__var_to_int(TVar, TVarNum),
	NextSlot is CurSlot + 1,
	( TVarNum = CurSlot ->
		( set__remove_least(Locns, LeastLocn, _) ->
			Locn = LeastLocn
		;
			error("tvar has empty set of locations")
		),
		stack_layout__represent_locn_as_int(Locn, Rval),
		stack_layout__construct_type_param_locn_vector(TVarLocns,
			NextSlot, VectorTail),
		Vector = [yes(Rval) | VectorTail]
	; TVarNum > CurSlot ->
		stack_layout__construct_type_param_locn_vector(
			[TVar - Locns | TVarLocns], NextSlot, VectorTail),
			% This slot will never be referred to.
		Vector = [yes(const(int_const(0))) | VectorTail]
	;
		error("unsorted tvars in construct_type_param_locn_vector")
	).

%---------------------------------------------------------------------------%

:- type liveval_array_info
	--->	live_array_info(
			rval,	% Rval describing the location of a live value.
				% Always of llds type uint_least8 if the cell
				% is in the byte array, and uint_least32 if it
				% is in the int array.
			rval,	% Rval describing the type of a live value.
			llds_type, % The llds type of the rval describing the
				% type.
			rval	% Rval describing the variable number of a
				% live value. Always of llds type uint_least16.
				% Contains zero if the live value is not
				% a variable. Contains the hightest possible
				% uint_least16 value if the variable number
				% does not fit in 16 bits.
		).

	% Construct a vector of (locn, live_value_type) pairs,
	% and a corresponding vector of variable names.

:- pred stack_layout__construct_liveval_arrays(list(var_info)::in,
	rval::out, rval::out, rval::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_liveval_arrays(VarInfos, LengthRval,
		TypeLocnVector, NumVector) -->
	{ int__pow(2, stack_layout__short_count_bits, BytesLimit) },
	stack_layout__construct_liveval_array_infos(VarInfos,
		0, BytesLimit, IntArrayInfo, ByteArrayInfo),

	{ list__length(IntArrayInfo, IntArrayLength) },
	{ list__length(ByteArrayInfo, ByteArrayLength) },
	{ list__append(IntArrayInfo, ByteArrayInfo, AllArrayInfo) },

	{ EncodedLength is IntArrayLength << stack_layout__short_count_bits
		+ ByteArrayLength },
	{ LengthRval = const(int_const(EncodedLength)) },

	{ SelectLocns = (pred(ArrayInfo::in, MaybeLocnRval::out) is det :-
		ArrayInfo = live_array_info(LocnRval, _, _, _),
		MaybeLocnRval = yes(LocnRval)
	) },
	{ SelectTypes = (pred(ArrayInfo::in, MaybeTypeRval::out) is det :-
		ArrayInfo = live_array_info(_, TypeRval, _, _),
		MaybeTypeRval = yes(TypeRval)
	) },
	{ SelectTypeTypes = (pred(ArrayInfo::in, CountTypeType::out) is det :-
		ArrayInfo = live_array_info(_, _, TypeType, _),
		CountTypeType = 1 - yes(TypeType)
	) },
	{ AddRevNums = (pred(ArrayInfo::in, NumRvals0::in, NumRvals::out)
			is det :-
		ArrayInfo = live_array_info(_, _, _, NumRval),
		NumRvals = [yes(NumRval) | NumRvals0]
	) },

	{ list__map(SelectTypes, AllArrayInfo, AllTypes) },
	{ list__map(SelectTypeTypes, AllArrayInfo, AllTypeTypes) },
	{ list__map(SelectLocns, IntArrayInfo, IntLocns) },
	{ list__map(SelectLocns, ByteArrayInfo, ByteLocns) },
	{ list__append(IntLocns, ByteLocns, AllLocns) },
	{ list__append(AllTypes, AllLocns, TypeLocnVectorRvals) },
	{ LocnArgTypes = [IntArrayLength - yes(uint_least32),
			ByteArrayLength - yes(uint_least8)] },
	{ list__append(AllTypeTypes, LocnArgTypes, ArgTypes) },
	stack_layout__get_next_cell_number(CNum1),
	{ Reuse = no },
	{ TypeLocnVector = create(0, TypeLocnVectorRvals,
		initial(ArgTypes, none), must_be_static, CNum1,
		"stack_layout_locn_vector", Reuse) },

	stack_layout__get_trace_stack_layout(TraceStackLayout),
	( { TraceStackLayout = yes } ->
		{ list__foldl(AddRevNums, AllArrayInfo,
			[], RevVarNumRvals) },
		{ list__reverse(RevVarNumRvals, VarNumRvals) },
		stack_layout__get_next_cell_number(CNum2),
		{ NumVector = create(0, VarNumRvals,
			uniform(yes(uint_least16)), must_be_static,
			CNum2, "stack_layout_num_name_vector", Reuse) }
	;
		{ NumVector = const(int_const(0)) }
	).

:- pred stack_layout__construct_liveval_array_infos(list(var_info)::in,
	int::in, int::in,
	list(liveval_array_info)::out, list(liveval_array_info)::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_liveval_array_infos([], _, _, [], []) --> [].
stack_layout__construct_liveval_array_infos([VarInfo | VarInfos],
		BytesSoFar, BytesLimit, IntVars, ByteVars) -->
	{ VarInfo = var_info(Locn, LiveValueType) },
	stack_layout__represent_live_value_type(LiveValueType, TypeRval,
		TypeRvalType),
	stack_layout__construct_liveval_num_rval(VarInfo, VarNumRval),
	(
		{ BytesSoFar < BytesLimit },
		{ stack_layout__represent_locn_as_byte(Locn, LocnByteRval) }
	->
		{ Var = live_array_info(LocnByteRval, TypeRval, TypeRvalType,
			VarNumRval) },
		stack_layout__construct_liveval_array_infos(VarInfos,
			BytesSoFar + 1, BytesLimit, IntVars, ByteVars0),
		{ ByteVars = [Var | ByteVars0] }
	;
		{ stack_layout__represent_locn_as_int(Locn, LocnRval) },
		{ Var = live_array_info(LocnRval, TypeRval, TypeRvalType,
			VarNumRval) },
		stack_layout__construct_liveval_array_infos(VarInfos,
			BytesSoFar, BytesLimit, IntVars0, ByteVars),
		{ IntVars = [Var | IntVars0] }
	).

:- pred stack_layout__construct_liveval_num_rval(var_info::in, rval::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__construct_liveval_num_rval(var_info(_, LiveValueType),
		VarNumRval, SLI0, SLI) :-
	( LiveValueType = var(Var, Name, _, _) ->
		stack_layout__convert_var_to_int(Var, VarNum),
		VarNumRval = const(int_const(VarNum)),
		stack_layout__get_cur_proc_named_vars(NamedVars0, SLI0, SLI1),
		( map__insert(NamedVars0, VarNum, Name, NamedVars) ->
			stack_layout__set_cur_proc_named_vars(NamedVars,
				SLI1, SLI)
		;
			% The variable has been put into the map already at
			% another label.
			SLI = SLI1
		)
	;
		VarNumRval = const(int_const(0)),
		SLI = SLI0
	).

:- pred stack_layout__convert_var_name_to_int(pair(prog_var, string)::in,
	pair(int, string)::out) is det.

stack_layout__convert_var_name_to_int(Var - Name, VarNum - Name) :-
	stack_layout__convert_var_to_int(Var, VarNum).

:- pred stack_layout__convert_var_to_int(prog_var::in, int::out) is det.

stack_layout__convert_var_to_int(Var, VarNum) :-
	term__var_to_int(Var, VarNum0),
		% The variable number has to fit into two bytes.
		% We reserve the largest such number (Limit)
		% to mean that the variable number is too large
		% to be represented. This ought not to happen,
		% since compilation would be glacial at best
		% for procedures with that many variables.
	Limit = (1 << (2 * stack_layout__byte_bits)) - 1,
	int__min(VarNum0, Limit, VarNum).

%---------------------------------------------------------------------------%

	% The representation we build here should be kept in sync
	% with runtime/mercury_ho_call.h, which contains macros to access
	% the data structures we build here.

stack_layout__construct_closure_layout(ProcLabel, ClosureLayoutInfo,
		Rvals, ArgTypes, C0, C) :-
	stack_layout__construct_procid_rvals(ProcLabel, ProcIdRvals,
		ProcIdTypes),
	ClosureLayoutInfo = closure_layout_info(ClosureArgs,
		TVarLocnMap),
	stack_layout__construct_closure_arg_rvals(ClosureArgs,
		ClosureArgRvals, ClosureArgTypes, C0, C1),
	stack_layout__construct_tvar_vector(TVarLocnMap, TVarVectorRval,
		C1, C),
	TVarVectorRvals = [yes(TVarVectorRval)],
	TVarVectorTypes = [1 - yes(data_ptr)],
	list__append(TVarVectorRvals, ClosureArgRvals, LayoutRvals),
	list__append(ProcIdRvals, LayoutRvals, Rvals),
	ArgTypes = initial(ProcIdTypes, initial(TVarVectorTypes,
		initial(ClosureArgTypes, none))).

:- pred stack_layout__construct_closure_arg_rvals(list(closure_arg_info)::in,
	list(maybe(rval))::out, initial_arg_types::out,
	counter::in, counter::out) is det.

stack_layout__construct_closure_arg_rvals(ClosureArgs, ClosureArgRvals,
		ClosureArgTypes, C0, C) :-
	list__map_foldl(stack_layout__construct_closure_arg_rval,
		ClosureArgs, MaybeArgRvalsTypes, C0, C),
	assoc_list__keys(MaybeArgRvalsTypes, MaybeArgRvals),
	AddOne = (pred(Pair::in, CountLldsType::out) is det :-
		Pair = _ - LldsType,
		CountLldsType = 1 - yes(LldsType)
	),
	list__map(AddOne, MaybeArgRvalsTypes, ArgRvalTypes),
	list__length(MaybeArgRvals, Length),
	ClosureArgRvals = [yes(const(int_const(Length))) | MaybeArgRvals],
	ClosureArgTypes = [1 - yes(integer) | ArgRvalTypes].

:- pred stack_layout__construct_closure_arg_rval(closure_arg_info::in,
	pair(maybe(rval), llds_type)::out, counter::in, counter::out) is det.

stack_layout__construct_closure_arg_rval(ClosureArg,
		yes(ArgRval) - ArgRvalType, C0, C) :-
	ClosureArg = closure_arg_info(Type, _Inst),

		% For a stack layout, we can treat all type variables as
		% universally quantified. This is not the argument of a
		% constructor, so we do not need to distinguish between type
		% variables that are and aren't in scope; we can take the
		% variable number directly from the procedure's tvar set.
	ExistQTvars = [],
	NumUnivQTvars = -1,

	ll_pseudo_type_info__construct_typed_llds_pseudo_type_info(Type, 
		NumUnivQTvars, ExistQTvars, ArgRval, ArgRvalType, C0, C).

%---------------------------------------------------------------------------%

	% Construct a representation of the type of a value.
	%
	% For values representing variables, this will be a pseudo_type_info
	% describing the type of the variable.
	%
	% For the kinds of values used internally by the compiler,
	% this will be a pointer to a specific type_ctor_info (acting as a
	% type_info) defined by hand in builtin.m to stand for values of
	% each such kind; one for succips, one for hps, etc.

:- pred stack_layout__represent_live_value_type(live_value_type, rval,
	llds_type, stack_layout_info, stack_layout_info).
:- mode stack_layout__represent_live_value_type(in, out, out, in, out) is det.

stack_layout__represent_live_value_type(succip, Rval, data_ptr) -->
	{ RttiTypeId = rtti_type_id(unqualified(""), "succip", 0) },
	{ DataAddr = rtti_addr(RttiTypeId, type_ctor_info) },
	{ Rval = const(data_addr_const(DataAddr)) }.
stack_layout__represent_live_value_type(hp, Rval, data_ptr) -->
	{ RttiTypeId = rtti_type_id(unqualified(""), "hp", 0) },
	{ DataAddr = rtti_addr(RttiTypeId, type_ctor_info) },
	{ Rval = const(data_addr_const(DataAddr)) }.
stack_layout__represent_live_value_type(curfr, Rval, data_ptr) -->
	{ RttiTypeId = rtti_type_id(unqualified(""), "curfr", 0) },
	{ DataAddr = rtti_addr(RttiTypeId, type_ctor_info) },
	{ Rval = const(data_addr_const(DataAddr)) }.
stack_layout__represent_live_value_type(maxfr, Rval, data_ptr) -->
	{ RttiTypeId = rtti_type_id(unqualified(""), "maxfr", 0) },
	{ DataAddr = rtti_addr(RttiTypeId, type_ctor_info) },
	{ Rval = const(data_addr_const(DataAddr)) }.
stack_layout__represent_live_value_type(redofr, Rval, data_ptr) -->
	{ RttiTypeId = rtti_type_id(unqualified(""), "redofr", 0) },
	{ DataAddr = rtti_addr(RttiTypeId, type_ctor_info) },
	{ Rval = const(data_addr_const(DataAddr)) }.
stack_layout__represent_live_value_type(redoip, Rval, data_ptr) -->
	{ RttiTypeId = rtti_type_id(unqualified(""), "redoip", 0) },
	{ DataAddr = rtti_addr(RttiTypeId, type_ctor_info) },
	{ Rval = const(data_addr_const(DataAddr)) }.
stack_layout__represent_live_value_type(trail_ptr, Rval, data_ptr) -->
	{ RttiTypeId = rtti_type_id(unqualified(""), "trail_ptr", 0) },
	{ DataAddr = rtti_addr(RttiTypeId, type_ctor_info) },
	{ Rval = const(data_addr_const(DataAddr)) }.
stack_layout__represent_live_value_type(ticket, Rval, data_ptr) -->
	{ RttiTypeId = rtti_type_id(unqualified(""), "ticket", 0) },
	{ DataAddr = rtti_addr(RttiTypeId, type_ctor_info) },
	{ Rval = const(data_addr_const(DataAddr)) }.
stack_layout__represent_live_value_type(unwanted, Rval, data_ptr) -->
	{ RttiTypeId = rtti_type_id(unqualified(""), "unwanted", 0) },
	{ DataAddr = rtti_addr(RttiTypeId, type_ctor_info) },
	{ Rval = const(data_addr_const(DataAddr)) }.
stack_layout__represent_live_value_type(var(_, _, Type, _), Rval, LldsType)
		-->
	stack_layout__get_cell_counter(C0),

		% For a stack layout, we can treat all type variables as
		% universally quantified. This is not the argument of a
		% constructor, so we do not need to distinguish between type
		% variables that are and aren't in scope; we can take the
		% variable number directly from the procedure's tvar set.
	{ ExistQTvars = [] },
	{ NumUnivQTvars = -1 },
	{ ll_pseudo_type_info__construct_typed_llds_pseudo_type_info(Type,
		NumUnivQTvars, ExistQTvars,
		Rval, LldsType, C0, C) },
	stack_layout__set_cell_counter(C).

%---------------------------------------------------------------------------%

	% Construct a representation of a variable location as a 32-bit
	% integer.
	%
	% Most of the time, a layout specifies a location as an lval.
	% However, a type_info variable may be hidden inside a typeclass_info,
	% In this case, accessing the type_info requires indirection.
	% The address of the typeclass_info is given as an lval, and
	% the location of the typeinfo within the typeclass_info as an index;
	% private_builtin:type_info_from_typeclass_info interprets the index.
	%
	% This one level of indirection is sufficient, since type_infos
	% cannot be nested inside typeclass_infos any deeper than this.
	% A more general representation that would allow more indirection
	% would be much harder to fit into one machine word.

:- pred stack_layout__represent_locn_as_int(layout_locn, rval).
:- mode stack_layout__represent_locn_as_int(in, out) is det.

stack_layout__represent_locn_as_int(direct(Lval), Rval) :-
	stack_layout__represent_lval(Lval, Word),
	Rval = const(int_const(Word)).
stack_layout__represent_locn_as_int(indirect(Lval, Offset), Rval) :-
	stack_layout__represent_lval(Lval, BaseWord),
	require((1 << stack_layout__long_lval_offset_bits) > Offset,
	"stack_layout__represent_locn: offset too large to be represented"),
	BaseAndOffset is (BaseWord << stack_layout__long_lval_offset_bits)
		+ Offset,
	stack_layout__make_tagged_word(lval_indirect, BaseAndOffset, Word),
	Rval = const(int_const(Word)).

	% Construct a four byte representation of an lval.

:- pred stack_layout__represent_lval(lval, int).
:- mode stack_layout__represent_lval(in, out) is det.

stack_layout__represent_lval(reg(r, Num), Word) :-
	stack_layout__make_tagged_word(lval_r_reg, Num, Word).
stack_layout__represent_lval(reg(f, Num), Word) :-
	stack_layout__make_tagged_word(lval_f_reg, Num, Word).

stack_layout__represent_lval(stackvar(Num), Word) :-
	stack_layout__make_tagged_word(lval_stackvar, Num, Word).
stack_layout__represent_lval(framevar(Num), Word) :-
	stack_layout__make_tagged_word(lval_framevar, Num, Word).

stack_layout__represent_lval(succip, Word) :-
	stack_layout__make_tagged_word(lval_succip, 0, Word).
stack_layout__represent_lval(maxfr, Word) :-
	stack_layout__make_tagged_word(lval_maxfr, 0, Word).
stack_layout__represent_lval(curfr, Word) :-
	stack_layout__make_tagged_word(lval_curfr, 0, Word).
stack_layout__represent_lval(hp, Word) :-
	stack_layout__make_tagged_word(lval_hp, 0, Word).
stack_layout__represent_lval(sp, Word) :-
	stack_layout__make_tagged_word(lval_sp, 0, Word).

stack_layout__represent_lval(temp(_, _), _) :-
	error("stack_layout: continuation live value stored in temp register").

stack_layout__represent_lval(succip(_), _) :-
	error("stack_layout: continuation live value stored in fixed slot").
stack_layout__represent_lval(redoip(_), _) :-
	error("stack_layout: continuation live value stored in fixed slot").
stack_layout__represent_lval(redofr(_), _) :-
	error("stack_layout: continuation live value stored in fixed slot").
stack_layout__represent_lval(succfr(_), _) :-
	error("stack_layout: continuation live value stored in fixed slot").
stack_layout__represent_lval(prevfr(_), _) :-
	error("stack_layout: continuation live value stored in fixed slot").

stack_layout__represent_lval(field(_, _, _), _) :-
	error("stack_layout: continuation live value stored in field").
stack_layout__represent_lval(mem_ref(_), _) :-
	error("stack_layout: continuation live value stored in mem_ref").
stack_layout__represent_lval(lvar(_), _) :-
	error("stack_layout: continuation live value stored in lvar").

	% Some things in this module are encoded using a low tag.
	% This is not done using the normal compiler mkword, but by
	% doing the bit shifting here.
	%
	% This allows us to use more than the usual 2 or 3 bits, but
	% we have to use low tags and cannot tag pointers this way.

:- pred stack_layout__make_tagged_word(locn_type::in, int::in, int::out) is det.

stack_layout__make_tagged_word(Locn, Value, TaggedValue) :-
	stack_layout__locn_type_code(Locn, Tag),
	TaggedValue is (Value << stack_layout__long_lval_tag_bits) + Tag.

:- type locn_type
	--->	lval_r_reg
	;	lval_f_reg
	;	lval_stackvar
	;	lval_framevar
	;	lval_succip
	;	lval_maxfr
	;	lval_curfr
	;	lval_hp
	;	lval_sp
	;	lval_indirect.

:- pred stack_layout__locn_type_code(locn_type::in, int::out) is det.

stack_layout__locn_type_code(lval_r_reg,    0).
stack_layout__locn_type_code(lval_f_reg,    1).
stack_layout__locn_type_code(lval_stackvar, 2).
stack_layout__locn_type_code(lval_framevar, 3).
stack_layout__locn_type_code(lval_succip,   4).
stack_layout__locn_type_code(lval_maxfr,    5).
stack_layout__locn_type_code(lval_curfr,    6).
stack_layout__locn_type_code(lval_hp,       7).
stack_layout__locn_type_code(lval_sp,       8).
stack_layout__locn_type_code(lval_indirect, 9).

:- func stack_layout__long_lval_tag_bits = int.

% This number of tag bits must be able to encode all values of
% stack_layout__locn_type_code.

stack_layout__long_lval_tag_bits = 4.

% This number of tag bits must be able to encode the largest offset
% of a type_info within a typeclass_info.

:- func stack_layout__long_lval_offset_bits = int.

stack_layout__long_lval_offset_bits = 6.

%---------------------------------------------------------------------------%

	% Construct a representation of a variable location as a byte,
	% if this is possible.

:- pred stack_layout__represent_locn_as_byte(layout_locn::in, rval::out)
	is semidet.

stack_layout__represent_locn_as_byte(LayoutLocn, Rval) :-
	LayoutLocn = direct(Lval),
	stack_layout__represent_lval_as_byte(Lval, Byte),
	Rval = const(int_const(Byte)).

	% Construct a representation of an lval in a byte, if possible.

:- pred stack_layout__represent_lval_as_byte(lval::in, int::out) is semidet.

stack_layout__represent_lval_as_byte(reg(r, Num), Byte) :-
	stack_layout__make_tagged_byte(0, Num, Byte).

stack_layout__represent_lval_as_byte(stackvar(Num), Byte) :-
	stack_layout__make_tagged_byte(1, Num, Byte).
stack_layout__represent_lval_as_byte(framevar(Num), Byte) :-
	stack_layout__make_tagged_byte(2, Num, Byte).

stack_layout__represent_lval_as_byte(succip, Byte) :-
	stack_layout__locn_type_code(lval_succip, Val),
	stack_layout__make_tagged_byte(3, Val, Byte).
stack_layout__represent_lval_as_byte(maxfr, Byte) :-
	stack_layout__locn_type_code(lval_maxfr, Val),
	stack_layout__make_tagged_byte(3, Val, Byte).
stack_layout__represent_lval_as_byte(curfr, Byte) :-
	stack_layout__locn_type_code(lval_curfr, Val),
	stack_layout__make_tagged_byte(3, Val, Byte).
stack_layout__represent_lval_as_byte(hp, Byte) :-
	stack_layout__locn_type_code(lval_hp, Val),
	stack_layout__make_tagged_byte(3, Val, Byte).
stack_layout__represent_lval_as_byte(sp, Byte) :-
	stack_layout__locn_type_code(lval_succip, Val),
	stack_layout__make_tagged_byte(3, Val, Byte).

:- pred stack_layout__make_tagged_byte(int::in, int::in, int::out) is semidet.

stack_layout__make_tagged_byte(Tag, Value, TaggedValue) :-
	Limit = 1 << (stack_layout__byte_bits -
		stack_layout__short_lval_tag_bits),
	Value < Limit,
	TaggedValue is unchecked_left_shift(Value,
		stack_layout__short_lval_tag_bits) + Tag.

:- func stack_layout__short_lval_tag_bits = int.

stack_layout__short_lval_tag_bits = 2.

:- func stack_layout__short_count_bits = int.

stack_layout__short_count_bits = 10.

:- func stack_layout__byte_bits = int.

stack_layout__byte_bits = 8.

%---------------------------------------------------------------------------%

	% Construct a representation of the interface determinism of a
	% procedure. The code we have chosen is not sequential; instead
	% it encodes the various properties of each determinism.
	%
	% The 8 bit is set iff the context is first_solution.
	% The 4 bit is set iff the min number of solutions is more than zero.
	% The 2 bit is set iff the max number of solutions is more than zero.
	% The 1 bit is set iff the max number of solutions is more than one.

:- pred stack_layout__represent_determinism(determinism::in, rval::out) is det.

stack_layout__represent_determinism(Detism, const(int_const(Code))) :-
	(
		Detism = det,
		Code = 6		/* 0110 */
	;
		Detism = semidet,	/* 0010 */
		Code = 2
	;
		Detism = nondet,
		Code = 3		/* 0011 */
	;
		Detism = multidet,
		Code = 7		/* 0111 */
	;
		Detism = erroneous,
		Code = 4		/* 0100 */
	;
		Detism = failure,
		Code = 0		/* 0000 */
	;
		Detism = cc_nondet,
		Code = 10 		/* 1010 */
	;
		Detism = cc_multidet,
		Code = 14		/* 1110 */
	).

%---------------------------------------------------------------------------%

	% Access to the stack_layout data structure.

	% The per-sourcefile label table maps line numbers to the list of
	% labels that correspond to that line. Each label is accompanied
	% by a flag that says whether the label is the return site of a call
	% or not, and if it is, whether the called procedure is known.

:- type is_label_return
	--->	known_callee(label)
	;	unknown_callee
	;	not_a_return.

:- type line_no_info == pair(label, is_label_return).

:- type label_table == map(int, list(line_no_info)).

:- type stack_layout_info 	--->
	stack_layout_info(
		module_info		:: module_info,
		agc_stack_layout	:: bool, % generate agc info?
		trace_stack_layout	:: bool, % generate tracing info?
		procid_stack_layout	:: bool, % generate proc id info?
		trace_level		:: trace_level,
		trace_suppress_items	:: trace_suppress_items,
		static_code_addresses	:: bool, % have static code addresses?
		proc_layouts		:: list(comp_gen_c_data),
		internal_layouts	:: list(comp_gen_c_data),
		label_set		:: set_bbbtree(label),
					   % The set of labels (both entry
					   % and internal) with layouts.
		proc_layout_args	:: list(maybe(rval)),
					   % The list of proc_layouts in
					   % the module, represented as create
					   % args.
		string_table		:: string_table,
		label_tables		:: map(string, label_table),
					   % Maps each filename that
					   % contributes labels to this module
					   % to a table describing those
					   % labels.
		cur_proc_named_vars	:: map(int, string)
					   % Maps the number of each variable
					   % in the current procedure whose
					   % name is of interest in an internal
					   % label's layout structure to the
					   % name of that variable.
	).

:- pred stack_layout__get_module_info(module_info::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_agc_stack_layout(bool::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_trace_stack_layout(bool::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_procid_stack_layout(bool::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_trace_level(trace_level::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_trace_suppress(trace_suppress_items::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_static_code_addresses(bool::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_proc_layout_data(list(comp_gen_c_data)::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_internal_layout_data(list(comp_gen_c_data)::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_label_set(set_bbbtree(label)::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_string_table(string_table::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_label_tables(map(string, label_table)::out,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__get_cur_proc_named_vars(map(int, string)::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__get_module_info(LI ^ module_info, LI, LI).
stack_layout__get_agc_stack_layout(LI ^ agc_stack_layout, LI, LI).
stack_layout__get_trace_stack_layout(LI ^ trace_stack_layout, LI, LI).
stack_layout__get_procid_stack_layout(LI ^ procid_stack_layout, LI, LI).
stack_layout__get_trace_level(LI ^ trace_level, LI, LI).
stack_layout__get_trace_suppress(LI ^ trace_suppress_items, LI, LI).
stack_layout__get_static_code_addresses(LI ^ static_code_addresses, LI, LI).
stack_layout__get_proc_layout_data(LI ^ proc_layouts, LI, LI).
stack_layout__get_internal_layout_data(LI ^ internal_layouts, LI, LI).
stack_layout__get_label_set(LI ^ label_set, LI, LI).
stack_layout__get_string_table(LI ^ string_table, LI, LI).
stack_layout__get_label_tables(LI ^ label_tables, LI, LI).
stack_layout__get_cur_proc_named_vars(LI ^ cur_proc_named_vars, LI, LI).

:- pred stack_layout__get_module_name(module_name::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__get_module_name(ModuleName) -->
	stack_layout__get_module_info(ModuleInfo),
	{ module_info_name(ModuleInfo, ModuleName) }.

:- pred stack_layout__get_cell_counter(counter::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__get_cell_counter(CellCounter) -->
	stack_layout__get_module_info(ModuleInfo),
	{ module_info_get_cell_counter(ModuleInfo, CellCounter) }.

:- pred stack_layout__add_proc_layout_data(comp_gen_c_data::in, data_name::in,
	label::in, stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__add_proc_layout_data(NewProcLayout, NewDataName, NewLabel,
		LI0, LI) :-
	ProcLayouts0 = LI0 ^ proc_layouts,
	ProcLayouts = [NewProcLayout | ProcLayouts0],
	LabelSet0 = LI0 ^ label_set,
	set_bbbtree__insert(LabelSet0, NewLabel, LabelSet),
	ModuleInfo = LI0 ^ module_info,
	module_info_name(ModuleInfo, ModuleName),
	NewProcLayoutArg = yes(const(data_addr_const(
		data_addr(ModuleName, NewDataName)))),
	ProcLayoutArgs0 = LI0 ^ proc_layout_args,
	ProcLayoutArgs = [NewProcLayoutArg | ProcLayoutArgs0],
	LI = (((LI0 ^ proc_layouts := ProcLayouts)
		^ label_set := LabelSet)
		^ proc_layout_args := ProcLayoutArgs).

:- pred stack_layout__add_internal_layout_data(comp_gen_c_data::in,
	label::in, stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__add_internal_layout_data(NewInternalLayout, NewLabel, LI0, LI) :-
	InternalLayouts0 = LI0 ^ internal_layouts,
	InternalLayouts = [NewInternalLayout | InternalLayouts0],
	LabelSet0 = LI0 ^ label_set,
	set_bbbtree__insert(LabelSet0, NewLabel, LabelSet),
	LI = ((LI0 ^ internal_layouts := InternalLayouts)
		^ label_set := LabelSet).

:- pred stack_layout__get_next_cell_number(int::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__get_next_cell_number(CellNum) -->
	stack_layout__get_cell_counter(CellCounter0),
	{ counter__allocate(CellNum, CellCounter0, CellCounter) },
	stack_layout__set_cell_counter(CellCounter).

:- pred stack_layout__set_cell_counter(counter::in,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__set_cell_counter(CellCounter) -->
	stack_layout__get_module_info(ModuleInfo0),
	{ module_info_set_cell_counter(ModuleInfo0, CellCounter,
		ModuleInfo) },
	stack_layout__set_module_info(ModuleInfo).

:- pred stack_layout__set_module_info(module_info::in,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__set_string_table(string_table::in,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__set_label_tables(map(string, label_table)::in,
	stack_layout_info::in, stack_layout_info::out) is det.

:- pred stack_layout__set_cur_proc_named_vars(map(int, string)::in,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__set_module_info(MI, LI0, LI0 ^ module_info := MI).
stack_layout__set_string_table(ST, LI0, LI0 ^ string_table := ST).
stack_layout__set_label_tables(LT, LI0, LI0 ^ label_tables := LT).
stack_layout__set_cur_proc_named_vars(NV, LI0,
	LI0 ^ cur_proc_named_vars := NV).

%---------------------------------------------------------------------------%

	% Access to the string_table data structure.

:- type string_table 	--->
	string_table(
		map(string, int),	% Maps strings to their offsets.
		list(string),		% List of strings so far,
					% in reverse order.
		int			% Next available offset
	).

:- pred stack_layout__lookup_string_in_table(string::in, int::out,
	stack_layout_info::in, stack_layout_info::out) is det.

stack_layout__lookup_string_in_table(String, Offset) -->
	stack_layout__get_string_table(StringTable0),
	{ StringTable0 = string_table(TableMap0, TableList0, TableOffset0) },
	(
		{ map__search(TableMap0, String, OldOffset) }
	->
		{ Offset = OldOffset }
	;
		{ string__length(String, Length) },
		{ TableOffset is TableOffset0 + Length + 1 },
		{ TableOffset < (1 << (2 * stack_layout__byte_bits)) }
	->
		{ Offset = TableOffset0 },
		{ map__det_insert(TableMap0, String, TableOffset0,
			TableMap) },
		{ TableList = [String | TableList0] },
		{ StringTable = string_table(TableMap, TableList,
			TableOffset) },
		stack_layout__set_string_table(StringTable)
	;
		% Says that the name of the variable is "TOO_MANY_VARIABLES".
		{ Offset = 1 }
	).
