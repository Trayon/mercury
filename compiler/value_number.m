%-----------------------------------------------------------------------------%
% Copyright (C) 1994-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% value_number.m - optimization of straight-line LLDS code.

% Author: zs.

%-----------------------------------------------------------------------------%

:- module value_number.

:- interface.

:- import_module llds.
:- import_module list, set, io, counter.

	% Find straight-line code sequences and optimize them using
	% value numbering.

:- pred value_number_main(list(instruction)::in, contains_reconstruction::in,
	set(label)::in, proc_label::in, counter::in, counter::out,
	list(instruction)::out, io__state::di, io__state::uo) is det.

	% The main value numbering pass introduces references to temporary
	% variables whose values need be preserved only within an extended
	% basic block. The post_main pass looks for references to temporaries
	% and introduces block instructions whenever it sees them. These
	% block instructions go from the first reference to a temporary
	% to the end of its extended basic block.

:- pred value_number__post_main(list(instruction), list(instruction)).
:- mode value_number__post_main(in, out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module builtin_ops.
:- import_module vn_type, vn_table, vn_block, vn_order, vn_flush, vn_temploc. 
:- import_module vn_cost, vn_debug, vn_util, vn_verify, vn_filter.
:- import_module opt_debug, opt_util, peephole, labelopt.
:- import_module globals, options, livemap, code_util.

:- import_module map, bimap, require, int, string, std_util, assoc_list.
:- import_module bool.

	% We can't find out what variables are used by C code sequences,
	% so we don't optimize any predicates containing them.

value_number_main(Instrs0, ContainsReconstruction, LayoutLabelSet,
		ProcLabel, C0, C, Instrs) -->
	{ opt_util__get_prologue(Instrs0, LabelInstr, Comments, Instrs1) },
	{ value_number__prepare_for_vn([LabelInstr | Instrs1], ProcLabel,
		no, ContainsReconstruction, AllocSet, BreakSet,
		C0, C1, Instrs2) },
	{ labelopt__build_useset(Instrs2, LayoutLabelSet, UseSet) },
	{ livemap__build(Instrs2, MaybeLiveMap) },
	(
		{ MaybeLiveMap = yes(LiveMap) },
		vn_debug__livemap_msg(LiveMap),
		value_number__procedure(Instrs2, LiveMap, UseSet,
			AllocSet, BreakSet, C1, C, Instrs3),
		{ list__append(Comments, Instrs3, Instrs) }
	;
		% Can't find live lvals and thus can't perform value numbering
		% if there is a c_code or a pragma_c in the instructions.
		{ MaybeLiveMap = no },
		{ C = C1 },
		{ Instrs = Instrs0 }
	).

%-----------------------------------------------------------------------------%

	% Instructions such as if_val(tag(r1) == 1 && field(1, r1, N) = X)
	% pose a problem for value numbering. The field reference will be
	% extracted into a register before the if, and this extraction will
	% cause an unaligned access if done before the tag test. Similar
	% problems can arise even if the code before the && does not contain
	% a tag operator, since this may have been applied earlier.
	%
	% By converting all boolean operations in if_vals into multiple
	% if_vals, we are preventing this from happening. 
	%
	% Value numbering currently combines multiple heap pointer
	% increments into a single heap pointer increment.  If we're
	% using conservative garbage collection, this would create
	% invalid code (unless the collector was compiled with
	% -DALL_INTERIOR_POINTERS, which would be very bad for
	% performance).  Hence, if GC=conservative we must not
	% perform value numbering on a block that contains more
	% than one heap pointer increment.
	%
	% We therefore insert new labels before every occurrence of incr_hp,
	% with the exception of the first one in each basic block. This allows
	% vn_block__divide_into_blocks to break up such blocks into smaller
	% blocks, with each smaller block having at most one incr_hp.
	%
	% Assignments to curfr change the meaning of framevars. Moving
	% any reference (read or write) to a framevar across such an assignment
	% will result in invalid code. The only really safe way to handle the
	% situation is to ensure that such assignments do not get lumped
	% together with other statements when doing value numbering. We
	% therefore insert labels before and after such assignments.
	% Our caller will break the code sequence at these labels.
	%
	% Mkframe operations also change curfr, and therefore get the
	% same treatment. We also apply this treatment to (1) assignments to
	% the control slots in nondet stack frames, since otherwise a bug
	% in the rest of value numbering may cause them to be improperly
	% deleted, and (b) uses of those control slots in the form of
	% branches to do_redo and do_fail, since otherwise assignments
	% to stack variables may be moved across them.
	%
	% Operations on a cell which is explicitly freed by a free_heap 
	% instruction should not be reordered with the free_heap.
	% We put labels before and after to avoid this.
	%
	% If the instruction list destructively updates a cell, we need
	% to be careful not to recorder extractions of fields of the
	% updated cell with the update. To do this, we put labels
	% before and after `assign' instructions for which the destination
	% is a `field' lval. The test for this case below is a bit too
	% conservative -- we could mark the assignments which need to be
	% treated this way during code generation.

:- pred value_number__prepare_for_vn(list(instruction)::in,
	proc_label::in, bool::in, contains_reconstruction::in,
	set(label)::out, set(label)::out,
	counter::in, counter::out, list(instruction)::out) is det.

value_number__prepare_for_vn([], _, _, _, AllocSet, BreakSet, C, C, []) :-
	set__init(AllocSet),
	set__init(BreakSet).
value_number__prepare_for_vn([Instr0 | Instrs0], ProcLabel, SeenAlloc,
		ContainsReconstruction, AllocSet, BreakSet, C0, C, Instrs) :-
	Instr0 = Uinstr0 - _Comment,
	( Uinstr0 = if_val(Test, TrueAddr) ->
		( ( TrueAddr = do_redo ; TrueAddr = do_fail ) ->
			counter__allocate(N0, C0, C1),
			MaybeBeforeLabel = yes(local(ProcLabel, N0))
		;
			MaybeBeforeLabel = no,
			C1 = C0
		),
		( Instrs0 = [label(OldFalseLabel) - _ | _] ->
			FalseLabel = OldFalseLabel,
			MaybeNewFalseLabel = no,
			C2 = C1
		;
			counter__allocate(N1, C1, C2),
			FalseLabel = local(ProcLabel, N1),
			MaybeNewFalseLabel = yes(FalseLabel)
		),
		FalseAddr = label(FalseLabel),
		value_number__breakup_complex_if(Test, TrueAddr, FalseAddr,
			FalseAddr, ProcLabel, C2, C3, IfInstrs),
		value_number__prepare_for_vn(Instrs0, ProcLabel, SeenAlloc,
			ContainsReconstruction, AllocSet, BreakSet0,
			C3, C, Instrs1),
		( MaybeNewFalseLabel = yes(NewFalseLabel) ->
			FalseInstr = label(NewFalseLabel) - "vn false label",
			list__append(IfInstrs, [FalseInstr | Instrs1], Instrs2)
		;
			list__append(IfInstrs, Instrs1, Instrs2)
		),
		( MaybeBeforeLabel = yes(BeforeLabel) ->
			set__insert(BreakSet0, BeforeLabel, BreakSet1),
			set__insert(BreakSet1, FalseLabel, BreakSet),
			BeforeInstr = label(BeforeLabel) - "vn before label",
			Instrs = [BeforeInstr | Instrs2]
		;
			BreakSet = BreakSet0,
			Instrs = Instrs2
		)
	; Uinstr0 = incr_hp(_, _, _, _) ->
		( SeenAlloc = yes ->
			counter__allocate(N0, C0, C1),
			NewLabel = local(ProcLabel, N0),
			value_number__prepare_for_vn(Instrs0, ProcLabel,
				yes, ContainsReconstruction,
				AllocSet0, BreakSet, C1, C, Instrs1),
			set__insert(AllocSet0, NewLabel, AllocSet),
			LabelInstr = label(NewLabel) - "vn incr divide label",
			Instrs = [LabelInstr, Instr0 | Instrs1]
		;
			value_number__prepare_for_vn(Instrs0, ProcLabel, yes,
				ContainsReconstruction, AllocSet, BreakSet,
				C0, C, Instrs1),
			Instrs = [Instr0 | Instrs1]
		)
	;
		(
			Uinstr0 = assign(Target, _),
			(
				Target = curfr
			;
				Target = maxfr
			;
				Target = redoip(_)
			;
				Target = succip(_)
			;
				Target = prevfr(_)
			;
				Target = succfr(_)
			;
				Target = field(_, _, _),
				ContainsReconstruction =
					contains_reconstruction
			)
		;
			Uinstr0 = mkframe(_, _)
		;
			Uinstr0 = free_heap(_)
		)
	->
		counter__allocate(N0, C0, C1),
		BeforeLabel = local(ProcLabel, N0),
		BeforeInstr = label(BeforeLabel) - "vn stack ctrl before label",
		counter__allocate(N1, C1, C2),
		AfterLabel = local(ProcLabel, N1),
		AfterInstr = label(AfterLabel) - "vn stack ctrl after label",
		value_number__prepare_for_vn(Instrs0, ProcLabel, yes,
			ContainsReconstruction, AllocSet, BreakSet0,
			C2, C, Instrs1),
		set__insert(BreakSet0, BeforeLabel, BreakSet1),
		set__insert(BreakSet1, AfterLabel, BreakSet),
		Instrs = [BeforeInstr, Instr0, AfterInstr | Instrs1]
	;
		value_number__prepare_for_vn(Instrs0, ProcLabel, SeenAlloc,
			ContainsReconstruction, AllocSet,
			BreakSet, C0, C, Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

:- pred value_number__breakup_complex_if(rval::in,
	code_addr::in, code_addr::in, code_addr::in, proc_label::in,
	counter::in, counter::out, list(instruction)::out) is det.

value_number__breakup_complex_if(Test, TrueAddr, FalseAddr, NextAddr,
		ProcLabel, C0, C, Instrs) :-
	( Test = binop(and, Test1, Test2) ->
		counter__allocate(N0, C0, C1),
		NewLabel = local(ProcLabel, N0),
		NewAddr = label(NewLabel),
		value_number__breakup_complex_if(Test1, NewAddr, FalseAddr,
			NewAddr, ProcLabel, C1, C2, Instrs1),
		value_number__breakup_complex_if(Test2, TrueAddr, FalseAddr,
			NextAddr, ProcLabel, C2, C, Instrs2),
		list__append(Instrs1, [label(NewLabel) - "" | Instrs2], Instrs)
	; Test = binop(or, Test1, Test2) ->
		counter__allocate(N0, C0, C1),
		NewLabel = local(ProcLabel, N0),
		NewAddr = label(NewLabel),
		value_number__breakup_complex_if(Test1, TrueAddr, NewAddr,
			NewAddr, ProcLabel, C1, C2, Instrs1),
		value_number__breakup_complex_if(Test2, TrueAddr, FalseAddr,
			NextAddr, ProcLabel, C2, C, Instrs2),
		list__append(Instrs1, [label(NewLabel) - "" | Instrs2], Instrs)
	; Test = unop(not, Test1) ->
		value_number__breakup_complex_if(Test1, FalseAddr, TrueAddr,
			NextAddr, ProcLabel, C0, C, Instrs)
	;
		C = C0,
		( NextAddr = FalseAddr ->
			Instrs = [if_val(Test, TrueAddr) - ""]
		; NextAddr = TrueAddr ->
			code_util__neg_rval(Test, NegTest),
			Instrs = [if_val(NegTest, FalseAddr) - ""]
		;
			Instrs = [if_val(Test, TrueAddr) - "",
				goto(FalseAddr) - ""]
		)
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% Optimize the code of a procedure.

:- pred value_number__procedure(list(instruction)::in, livemap::in,
	set(label)::in, set(label)::in, set(label)::in,
	counter::in, counter::out, list(instruction)::out,
	io__state::di, io__state::uo) is det.

value_number__procedure(Instrs0, LiveMap, UseSet, AllocSet, BreakSet,
		C0, C, OptInstrs) -->
	globals__io_get_globals(Globals),
	{ opt_util__gather_comments(Instrs0, Comments, Instrs1) },
	{ globals__get_gc_method(Globals, GC) },
	( { GC = conservative } ->
		{ set__union(UseSet, AllocSet, DivideSet0) }
	;
		{ DivideSet0 = UseSet }
	),
	{ set__union(DivideSet0, BreakSet, DivideSet) },
	vn_debug__cost_header_msg("procedure before value numbering"),
	vn_debug__dump_instrs(Instrs1),
	{ vn_block__divide_into_blocks(Instrs1, DivideSet, Blocks) },
	{ globals__get_options(Globals, OptionTable) },
	{ vn_type__init_params(OptionTable, Params) },
	value_number__optimize_blocks(Blocks, LiveMap, Params, C0, C1,
		OptBlocks0, [], RevTuples),
	{ list__condense([Comments | OptBlocks0], OptInstrs0) },
	{ opt_util__propagate_livevals(OptInstrs0, OptInstrs1) },
	vn_debug__cost_header_msg("procedure after non-pred value numbering"),
	vn_debug__dump_instrs(OptInstrs1),
	{ globals__lookup_bool_option(Globals, pred_value_number, PredVn) },
	( { PredVn = yes } ->
		% Predicate wide value numbering tries to delete assignments
		% to variables when the target location already contains the 
		% right value. However, if this assignment is in a loop,
		% then this eliminated assignment may be exactly what put the
		% right value in the right location. For example, we can't
		% delete the assignment to r1 in the following code:
		%
		% L1:
		%	r1 = r2
		%	goto L1
		%
		% If opt_util__propagate_livevals changes any livevals
		% instructions, we also can't apply predicate wide value
		% numbering, since its input (OptBlocks) contains the
		% old livevals sets.
		(
			{ value_number__has_no_backward_branches(Instrs0) },
			{ OptInstrs1 = OptInstrs0 }
		->
			{ list__reverse(RevTuples, Tuples) },
			value_number__process_parallel_tuples(Tuples,
				OptBlocks0, LiveMap, Params, OptBlocks, C1, C),
			{ list__condense([Comments | OptBlocks], OptInstrs2) },
			{ opt_util__propagate_livevals(OptInstrs2, OptInstrs) },
			vn_debug__cost_header_msg("procedure after parallels"),
			vn_debug__dump_instrs(OptInstrs)
		;
			vn_debug__cost_header_msg("parallels do not apply"),
			{ OptInstrs = OptInstrs0 },
			{ C = C1 }
		)
	;
		{ OptInstrs = OptInstrs0 },
		{ C = C1 }
	).

:- pred value_number__optimize_blocks(list(list(instruction)), livemap,
	vn_params, counter, counter, list(list(instruction)),
	list(maybe(vn_ctrl_tuple)), list(maybe(vn_ctrl_tuple)),
	io__state, io__state).
% :- mode value_number__optimize_blocks(in, in, in, in, out, out, di, uo,
%	di, uo) is det.
:- mode value_number__optimize_blocks(in, in, in, in, out, out, in, out,
	di, uo) is det.

value_number__optimize_blocks([], _, _, C, C, [], Tuples, Tuples) --> [].
value_number__optimize_blocks([Block0 | Blocks0], LiveMap, Params, C0, C,
		[Block | Blocks], RevTuples0, RevTuples) -->
	value_number__optimize_block(Block0, LiveMap, Params, [],
		C0, C1, Block, RevTuples0, RevTuples1),
	value_number__optimize_blocks(Blocks0, LiveMap, Params,
		C1, C, Blocks, RevTuples1, RevTuples).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred value_number__optimize_block(list(instruction), livemap, vn_params,
	list(parentry), counter, counter, list(instruction),
	list(maybe(vn_ctrl_tuple)), list(maybe(vn_ctrl_tuple)),
	io__state, io__state).
:- mode value_number__optimize_block(in, in, in, in, in, out, out, in, out,
	di, uo) is det.

value_number__optimize_block(Instrs0, LiveMap, Params, ParEntries, C0, C,
		Instrs, RevTuples0, RevTuples) -->
	(
		{ list__reverse(Instrs0, RevInstrs) },
		{ RevInstrs = [LastInstr - _ | _] },
		{ opt_util__can_instr_fall_through(LastInstr, yes) }
	->
		% The block ends with a call to an erroneous procedure
		% and its never to be used return label
		{ Instrs = Instrs0 },
		{ C = C0 },
		{ RevTuples = [no | RevTuples0] }
	;
		value_number__optimize_fragment(Instrs0, LiveMap, Params,
			ParEntries, C0, Tuple, Instrs),
		vn_debug__tuple_msg(no, Instrs, Tuple),
		{ Tuple = tuple(_, _, _, C, _) },
		{ RevTuples = [yes(Tuple) | RevTuples0] }
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% Optimize a fragment of a block. This may be the entire block,
	% or it may be a part of the block; we optimize parts of blocks if
	% a conflict prevents us from optimizing the whole block together.

:- pred value_number__optimize_fragment(list(instruction)::in, livemap::in,
	vn_params::in, list(parentry)::in, counter::in, vn_ctrl_tuple::out,
	list(instruction)::out, io__state::di, io__state::uo) is det.

value_number__optimize_fragment(Instrs0, LiveMap, Params, ParEntries, C0,
		Tuple, Instrs) -->
	globals__io_get_gc_method(GC),
	(
		{ GC = conservative },
		{ opt_util__count_incr_hp(Instrs0, NumIncrs) },
		{ NumIncrs >= 2 }
	->
		vn_debug__cost_header_msg("fragment with the error"),
		vn_debug__dump_instrs(Instrs0),
		{ error("instruction sequence with several incr_hps in value_number__optimize_fragment") }
	;
		value_number__optimize_fragment_2(Instrs0, LiveMap, Params,
			ParEntries, C0, Tuple, Instrs)
	).

:- pred value_number__optimize_fragment_2(list(instruction)::in, livemap::in,
	vn_params::in, list(parentry)::in, counter::in, vn_ctrl_tuple::out,
	list(instruction)::out, io__state::di, io__state::uo) is det.

value_number__optimize_fragment_2(Instrs0, LiveMap, Params, ParEntries,
		C0, Tuple, Instrs) -->
	( { Instrs0 = [Uinstr0Prime - _ | _] } ->
		{ Uinstr0 = Uinstr0Prime },
		vn_debug__fragment_msg(Uinstr0)
	;
		{ error("empty instruction sequence in value_number__optimize_fragment") }
	),
	{ vn_block__build_block_info(Instrs0, LiveMap, Params, ParEntries,
		C0, VnTables0, Liveset0, SeenIncr0, Tuple0) },
	{ Tuple0 = tuple(Ctrl, Ctrlmap, Flushmap, C, _Parmap) },

	{ vn_util__build_uses(Liveset0, Ctrlmap, VnTables0, VnTables1) },

	vn_order__order(Liveset0, VnTables1, SeenIncr0, Ctrl, Ctrlmap,
		Flushmap, Res),
	(
		{ Res = success(VnTables2, Order) },
		{ vn_temploc__init_templocs(Params, Liveset0, VnTables2,
			Templocs0) },
		vn_flush__nodelist(Order, Ctrlmap, VnTables2, Templocs0,
			Params, Instrs1),

		{ value_number__push_decr_sp_back(Instrs1, Instrs2) },
		{ value_number__push_incr_sp_forw(Instrs2, Instrs3) },
		{ value_number__push_livevals_back(Instrs3, Instrs4) },
		{ vn_filter__block(Instrs4, Instrs5) },
		globals__io_get_gc_method(GC_Method),
		{ peephole__optimize(GC_Method, Instrs5, Instrs6, _) },

		vn_debug__cost_header_msg("original code sequence"),
		vn_cost__block_cost(Instrs0, Params, yes, OrigCost),
		( { Instrs5 = Instrs6 } ->
			[]
		;
			vn_debug__cost_header_msg("unfiltered code sequence"),
			vn_cost__block_cost(Instrs4, Params, yes, _)
		),

		vn_debug__cost_header_msg("new code sequence"),
		vn_cost__block_cost(Instrs6, Params, yes, VnCost),

		globals__io_lookup_int_option(vn_fudge, VnFudge),

		(
			{ VnCost < OrigCost },
			{
				assoc_list__keys(Instrs0, Uinstrs0),
				assoc_list__keys(Instrs6, Uinstrs6),
				list__sublist(Uinstrs6, Uinstrs0)
			;
				VnCost * 1000 < OrigCost * VnFudge
			}
		->
			vn_debug__cost_msg(yes, OrigCost, VnCost),
			{ vn_block__build_block_info(Instrs6, LiveMap, Params,
				ParEntries, C0, VnTables6, Liveset6,
				SeenIncr6, Tuple6) },
			vn_verify__ok(Instrs6, Uinstr0, SeenIncr0, SeenIncr6,
				Liveset0, Liveset6, VnTables0, VnTables6, OK),
			( { OK = yes } ->
				{ Instrs = Instrs6 },
				{ Tuple = Tuple6 }
			;
				{ Instrs = Instrs0 },
				{ Tuple = Tuple0 }
			)
		;
			vn_debug__cost_msg(no, OrigCost, VnCost),
			{ Instrs = Instrs0 },
			{ Tuple = Tuple0 }
		),
		vn_debug__tuple_msg(yes(no), Instrs, Tuple)
	;
		{ Res = failure(MaybeLabel) },
		(
			{ MaybeLabel = yes(RestartLabel) }
%			( { MaybeLabel = yes(RestartLabelPrime) } ->
%				{ RestartLabel = RestartLabelPrime }
%			;
%				{ map__init(Positions) },
%				{ value_number__find_restart_label(0, Positions,
%					Ctrlmap, Flushmap, no, RestartLabel) }
%			)
		->
			value_number__try_again(Instrs0, [], RestartLabel,
				LiveMap, Params, C, Instrs)
		;
			value_number__last_ditch(Instrs0,
				LiveMap, Params, C, Instrs)
		),
		{ vn_block__build_block_info(Instrs, LiveMap, Params,
			ParEntries, C0, _, _, _, Tuple) },
		vn_debug__tuple_msg(yes(yes), Instrs, Tuple)
	).

%-----------------------------------------------------------------------------%

:- pred value_number__find_restart_label(int, flushmapentry, ctrlmap, flushmap,
	maybe(label), label).
:- mode value_number__find_restart_label(in, in, in, in, in, out) is semidet.

value_number__find_restart_label(Ctrl0, Positions0, Ctrlmap, Flushmap,
		PrevLabel0, RestartLabel) :-
	map__search(Ctrlmap, Ctrl0, VnInstr),
	map__search(Flushmap, Ctrl0, FlushmapEntry),
	(
		VnInstr = vn_label(Label)
	->
		PrevLabel1 = yes(Label)
	;
		PrevLabel1 = PrevLabel0
	),
	(
		map__to_assoc_list(FlushmapEntry, NewPositions),
		value_number__compatible_positions(NewPositions, Positions0,
			Positions1)
	->
		Ctrl1 is Ctrl0 + 1,
		value_number__find_restart_label(Ctrl1, Positions1,
			Ctrlmap, Flushmap, PrevLabel1, RestartLabel)
	;
		PrevLabel1 = yes(RestartLabel)
	).

:- pred value_number__compatible_positions(assoc_list(vnlval, vn),
	flushmapentry, flushmapentry).
:- mode value_number__compatible_positions(in, in, out) is semidet.

value_number__compatible_positions([], Positions, Positions).
value_number__compatible_positions([Entry | Entries], Positions0, Positions) :-
	Entry = Vnlval - Vn,
	( map__search(Positions0, Vnlval, OldVn) ->
		Vn = OldVn,
		Positions1 = Positions0
	;
		map__det_insert(Positions0, Vnlval, Vn, Positions1)
	),
	value_number__compatible_positions(Entries, Positions1, Positions).

:- pred value_number__try_again(list(instruction)::in, list(instruction)::in,
	label::in, livemap::in, vn_params::in, counter::in,
	list(instruction)::out, io__state::di, io__state::uo) is det.

value_number__try_again([], RevInstrs, _Label, LiveMap, Params, C0,
		Instrs) -->
	{ list__reverse(RevInstrs, Instrs0) },
	value_number__last_ditch(Instrs0, LiveMap, Params, C0, Instrs).
value_number__try_again([Instr0 | Instrs0], RevInstrs0, RestartLabel, LiveMap,
		Params, C0, Instrs) -->
	( { Instr0 = label(RestartLabel) - _ } ->
		( { RevInstrs0 = [] } ->
			value_number__last_ditch(Instrs0, LiveMap, Params,
				C0, Instrs1),
			{ Instrs = [Instr0 | Instrs1] }
		;
			vn_debug__divide_msg(Instr0),
			%
			% we need to append a `goto' instruction at the
			% end of the fragment so that optimize_fragment
			% can know what is live at the end.
			%
			{ GotoInstr = goto(label(RestartLabel)) - "" },
			{ list__reverse([GotoInstr | RevInstrs0],
				FrontInstrs0) },
			value_number__optimize_fragment(FrontInstrs0, LiveMap,
				Params, [], C0, _, FrontInstrs1),
			value_number__optimize_fragment(Instrs0, LiveMap,
				Params, [], C0, _, BackInstrs),
			%
			% we need to get rid of the introduced goto,
			% which should still be at the end of FrontInstrs1,
			% otherwise we would violate the invariant that
			% labels in the middle of a block are not targets
			% of branches.
			%
			{ list__reverse(FrontInstrs1, RevInstrs1) },
			{ RevInstrs1 = [GotoInstr | RevInstrs2] ->
				list__reverse(RevInstrs2, FrontInstrs)
			;
				error("value_number__try_again: lost goto")
			},
			{ list__append(FrontInstrs, [Instr0 | BackInstrs],
				Instrs) }
		)
	;
		{ RevInstrs1 = [Instr0 | RevInstrs0] },
		value_number__try_again(Instrs0, RevInstrs1, RestartLabel,
			LiveMap, Params, C0, Instrs)
	).

%-----------------------------------------------------------------------------%

:- pred value_number__last_ditch(list(instruction)::in, livemap::in,
	vn_params::in, counter::in, list(instruction)::out,
	io__state::di, io__state::uo) is det.

value_number__last_ditch([], _, _, _, []) --> [].
value_number__last_ditch([Instr0 | Instrs0], LiveMap, Params, C0,
		Instrs) -->
	(
		{ Instr0 = Uinstr0 - _ },
		{
			Uinstr0 = if_val(_, _)
		;
			Uinstr0 = restore_hp(_)
		;
			Uinstr0 = mark_hp(_)
		}
	->
		vn_debug__restart_msg(Instr0),
		value_number__optimize_fragment(Instrs0, LiveMap, Params,
			[], C0, _, Instrs1),
		{ Instrs = [Instr0 | Instrs1] }
	;
		value_number__last_ditch(Instrs0, LiveMap, Params,
			C0, Instrs1),
		{ Instrs = [Instr0 | Instrs1] }
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred value_number__process_parallel_tuples(list(maybe(vn_ctrl_tuple)),
	list(list(instruction)), livemap, vn_params, list(list(instruction)),
	counter, counter, io__state, io__state).
:- mode value_number__process_parallel_tuples(in, in, in, in, out, in, out,
	di, uo) is det.

value_number__process_parallel_tuples(Tuples0, Blocks0, LiveMap, Params,
		Blocks, C0, C) -->
	{ list__length(Tuples0, TupleLength) },
	{ list__length(Blocks0, BlockLength) },
	( { TupleLength = BlockLength } ->
		value_number__process_parallel_tuples_2(Blocks0, Tuples0,
			LiveMap, Params, Blocks0, Blocks1, Extras, C0, C),
		{ value_number__insert_new_blocks(Extras, Blocks1, Blocks) }
	;
		{ error("number of tuples and blocks differ") }
	).

:- pred value_number__insert_new_blocks(assoc_list(label, list(instruction)),
	list(list(instruction)), list(list(instruction))).
:- mode value_number__insert_new_blocks(in, in, out) is det.

value_number__insert_new_blocks([], Blocks, Blocks).
value_number__insert_new_blocks([Label - Extra | Extras], Blocks0, Blocks) :-
	value_number__find_block_by_label(Blocks0, Label, Before, LabelBlock,
		After),
	list__condense([Before, [Extra, LabelBlock], After], Blocks1),
	value_number__insert_new_blocks(Extras, Blocks1, Blocks).

:- pred value_number__process_parallel_tuples_2(list(list(instruction)),
	list(maybe(vn_ctrl_tuple)), livemap, vn_params,
	list(list(instruction)), list(list(instruction)),
	assoc_list(label, list(instruction)), counter, counter,
	io__state, io__state).
:- mode value_number__process_parallel_tuples_2(in, in, in, in, in, out, out,
	in, out, di, uo) is det.

value_number__process_parallel_tuples_2([], _, _, _, _, [], [], C, C) --> [].
value_number__process_parallel_tuples_2([Block0 | Blocks0], MaybeTuples0,
		LiveMap, Params, AllBlocks, [Block | Blocks], Extras, C0, C)
		-->
	{ MaybeTuples0 = [MaybeTuple0Prime | MaybeTuples1Prime] ->
		MaybeTuple0 = MaybeTuple0Prime,
		MaybeTuples1 = MaybeTuples1Prime
	;
		error("tuples and blocks not in sync")
	},
	(
		{ MaybeTuple0 = yes(Tuple) },
		value_number__process_parallel_tuple(Block0, Tuple,
			LiveMap, Params, AllBlocks, Block, Extras1, C0, C1)
	;
		{ MaybeTuple0 = no },
		{ Block = Block0 },
		{ Extras1 = [] },
		{ C1 = C0 }
	),
	value_number__process_parallel_tuples_2(Blocks0, MaybeTuples1,
		LiveMap, Params, AllBlocks, Blocks, Extras2, C1, C),
	{ list__append(Extras1, Extras2, Extras) }.

:- pred value_number__process_parallel_tuple(list(instruction), vn_ctrl_tuple,
	livemap, vn_params, list(list(instruction)), list(instruction),
	assoc_list(label, list(instruction)), counter, counter,
	io__state, io__state).
:- mode value_number__process_parallel_tuple(in, in, in, in, in, out, out,
	in, out, di, uo) is det.

value_number__process_parallel_tuple(Block0, tuple(_, _, _, _, Parmap),
		LiveMap, Params, AllBlocks, Block, Extras, C0, C) -->
	{ map__values(Parmap, ParList) },
	( { value_number__all_empty_lists(ParList) } ->
		{ Block = Block0 },
		{ Extras = [] },
		{ C = C0 }
	;
		value_number__process_parallel_nodes(ParList, LiveMap, Params,
			Block0, AllBlocks, Block, Extras, C0, C)
	).

:- pred value_number__all_empty_lists(list(list(T))).
:- mode value_number__all_empty_lists(in) is semidet.

value_number__all_empty_lists([]).
value_number__all_empty_lists([[] | Lists]) :-
	value_number__all_empty_lists(Lists).

:- pred value_number__process_parallel_nodes(list(list(parallel)), livemap,
	vn_params, list(instruction), list(list(instruction)),
	list(instruction), assoc_list(label, list(instruction)),
	counter, counter, io__state, io__state).
:- mode value_number__process_parallel_nodes(in, in, in, in, in, out, out,
	in, out, di, uo) is det.

value_number__process_parallel_nodes([], _, _, Block, _, Block, [], C, C)
		--> [].
value_number__process_parallel_nodes([Par0 | Pars1], LiveMap, Params,
		Block0, AllBlocks, Block, Extras, C0, C) -->
	{ vn_block__split_at_next_ctrl_instr(Block0, Start, NodeInstr,
		Block1) },
	value_number__process_parallels(Par0, LiveMap, Params,
		NodeInstr, NewNodeInstr, AllBlocks, Extras1, C0, C1),
	value_number__process_parallel_nodes(Pars1, LiveMap, Params,
		Block1, AllBlocks, Block2, Extras2, C1, C),
	{ list__condense([Start, [NewNodeInstr], Block2], Block) },
	{ list__append(Extras1, Extras2, Extras) }.

:- pred value_number__process_parallels(list(parallel), livemap, vn_params,
	instruction, instruction, list(list(instruction)),
	assoc_list(label, list(instruction)), counter, counter,
	io__state, io__state).
:- mode value_number__process_parallels(in, in, in, in, out, in, out, in, out,
	di, uo) is det.

value_number__process_parallels(Pars, LiveMap, Params, Instr0, Instr,
		AllBlocks, Extras, C0, C) -->
	{ Instr0 = Uinstr0 - Comment },
	( { Pars = [] } ->
		{ Instr = Instr0 },
		{ Extras = []},
		{ C = C0 }
	; { Uinstr0 = if_val(Rval, label(Label)) } ->
		( { Pars = [Par] } ->
			( { Par = parallel(Label, _NewLabel, _ParEntries) } ->
				value_number__process_parallel(Par, LiveMap,
					Params, AllBlocks, FinalLabel, Extras,
					C0, C),
				{ Instr = if_val(Rval, label(FinalLabel))
					- Comment }
			;
				{ error("wrong label in parallel for if_val") }
			)
		;
			{ error("more than one parallel for if_val") }
		)
	; { Uinstr0 = goto(label(Label)) } ->
		( { Pars = [Par] } ->
			( { Par = parallel(Label, _NewLabel, _ParEntries) } ->
				value_number__process_parallel(Par, LiveMap,
					Params, AllBlocks, FinalLabel, Extras,
					C0, C),
				{ Instr = goto(label(FinalLabel)) - Comment }
			;
				{ error("wrong label in parallel for goto") }
			)
		;
			{ error("more than one parallel for goto") }
		)
	; { Uinstr0 = computed_goto(Rval, Labels) } ->
		{ value_number__pair_labels_pars(Labels, Pars, LabelPars) },
		vn_debug__computed_goto_msg(Labels, Pars, LabelPars),
		value_number__process_parallel_list(LabelPars, LiveMap,
			Params, AllBlocks, FinalLabels, Extras, C0, C),
		{ Instr = computed_goto(Rval, FinalLabels) - Comment }
	;
		{ Instr = Instr0 },
		{ Extras = [] },
		{ C = C0 }
	).

:- pred value_number__pair_labels_pars(list(label), list(parallel),
	assoc_list(label, maybe(parallel))).
:- mode value_number__pair_labels_pars(in, in, out) is det.

value_number__pair_labels_pars([], Pars, []) :-
	( Pars = [] ->
		true
	;
		error("parallel without corresponding label")
	).
value_number__pair_labels_pars([Label | Labels0], Pars0,
		[Label - MaybePar | LabelPars]) :-
	( value_number__find_parallel_for_label(Pars0, Label, Par, Pars1) ->
		MaybePar = yes(Par),
		Pars2 = Pars1
	;
		MaybePar = no,
		Pars2 = Pars0
	),
	value_number__pair_labels_pars(Labels0, Pars2, LabelPars).

:- pred value_number__find_parallel_for_label(list(parallel), label, parallel,
	list(parallel)).
:- mode value_number__find_parallel_for_label(in, in, out, out) is semidet.

value_number__find_parallel_for_label([Par0 | Pars0], Label, Par, Rest) :-
	( Par0 = parallel(Label, _, _) ->
		Par = Par0,
		Rest = Pars0
	;
		value_number__find_parallel_for_label(Pars0, Label, Par, Rest1),
		Rest = [Par0 | Rest1]
	).

:- pred value_number__process_parallel_list(assoc_list(label, maybe(parallel)),
	livemap, vn_params, list(list(instruction)), list(label),
	assoc_list(label, list(instruction)), counter, counter,
	io__state, io__state).
:- mode value_number__process_parallel_list(in, in, in, in, out, out, in, out,
	di, uo) is det.

value_number__process_parallel_list([], _, _, _, [], [], C, C) --> [].
value_number__process_parallel_list([OldLabel - MaybePar | LabelPars], LiveMap,
		Params, AllBlocks, [Label | Labels], Extras, C0, C) -->
	( { MaybePar = yes(Par) } ->
		( { Par = parallel(OldLabel, _, _) } ->
			[]
		;
			{ error("wrong label in parallel for computed_goto") }
		),
		value_number__process_parallel(Par, LiveMap, Params,
			AllBlocks, Label, Extras1, C0, C1),
		value_number__process_parallel_list(LabelPars, LiveMap, Params,
			AllBlocks, Labels, Extras2, C1, C),
		{ list__append(Extras1, Extras2, Extras) }
	;
		{ Label = OldLabel },
		value_number__process_parallel_list(LabelPars, LiveMap, Params,
			AllBlocks, Labels, Extras, C0, C)
	).

:- pred value_number__process_parallel(parallel, livemap, vn_params,
	list(list(instruction)), label, assoc_list(label, list(instruction)),
	counter, counter, io__state, io__state).
:- mode value_number__process_parallel(in, in, in, in, out, out, in, out,
	di, uo) is det.

value_number__process_parallel(Par, LiveMap, Params, AllBlocks, FinalLabel,
		Extras, C0, C) -->
	vn_debug__parallel_msg(Par),
	{ Par = parallel(OldLabel, NewLabel, ParEntries) },
	{ value_number__find_block_by_label(AllBlocks, OldLabel, _, Block, _) },
	value_number__optimize_block(Block, LiveMap, Params, ParEntries,
		C0, C, NewBlock0, [], _),
	vn_cost__block_cost(Block, Params, no, OrigCost),
	vn_cost__block_cost(NewBlock0, Params, no, ParCost),
	{
		ParCost < OrigCost
	->
		FinalLabel = NewLabel,
		( NewBlock0 = [label(OldLabel) - Comment | Rest0] ->
			opt_util__filter_out_labels(Rest0, Rest),
			NewBlock = [label(NewLabel) - Comment | Rest],
			Extras = [OldLabel - NewBlock]
		;
			error("block starts with wrong label")
		)
	;
		FinalLabel = OldLabel,
		Extras = []
	}.

	% Given a list of blocks and a label, return the blocks before the
	% labelled block, the labelled block itself, and the following blocks.

:- pred value_number__find_block_by_label(list(list(instruction)), label,
	list(list(instruction)), list(instruction), list(list(instruction))).
% :- mode value_number__find_block_by_label(di, in, uo, uo, uo) is det.
:- mode value_number__find_block_by_label(in, in, out, out, out) is det.

value_number__find_block_by_label([], Label, _, _, _) :-
	opt_debug__dump_label(Label, L_str),
	string__append("Cannot find block with label ", L_str, Str),
	error(Str).
value_number__find_block_by_label([Block | Blocks], Label, Before, LabelBlock,
		After) :-
	( Block = [FirstInstr | _] ->
		( FirstInstr = label(Label) - _ ->
			Before = [],
			LabelBlock = Block,
			After = Blocks
		;
			value_number__find_block_by_label(Blocks, Label,
				Before0, LabelBlock, After),
			Before = [Block | Before0]
		)
	;
		error("found empty block")
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred value_number__push_decr_sp_back(list(instruction), list(instruction)).
% :- mode value_number__push_decr_sp_back(di, uo) is det.
:- mode value_number__push_decr_sp_back(in, out) is det.

value_number__push_decr_sp_back([], []).
value_number__push_decr_sp_back([Instr0 | Instrs0], Instrs) :-
	( Instr0 = decr_sp(N) - _ ->
		value_number__push_decr_sp_back_2(Instrs0, N, Instrs)
	;
		value_number__push_decr_sp_back(Instrs0, Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

:- pred value_number__push_decr_sp_back_2(list(instruction), int,
	list(instruction)).
% :- mode value_number__push_decr_sp_back_2(di, in, uo) is det.
:- mode value_number__push_decr_sp_back_2(in, in, out) is det.

value_number__push_decr_sp_back_2([], N, [decr_sp(N) - ""]).
value_number__push_decr_sp_back_2([Instr0 | Instrs0], N, Instrs) :-
	Instr0 = Uinstr0 - _,
	value_number__boundary_instr(Uinstr0, Boundary),
	(
		Boundary = yes,
		Instrs = [decr_sp(N) - "", Instr0 | Instrs0],
		opt_util__block_refers_stackvars([Instr0 | Instrs], Ref),
		(
			Ref = yes,
			error("cannot push decr_sp back enough")
		;
			Ref = no
		)
	;
		Boundary = no,
		value_number__push_decr_sp_back_2(Instrs0, N, Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

:- pred value_number__push_incr_sp_forw(list(instruction), list(instruction)).
% :- mode value_number__push_incr_sp_forw(di, uo) is det.
:- mode value_number__push_incr_sp_forw(in, out) is det.

value_number__push_incr_sp_forw(Instrs0, Instrs) :-
	list__reverse(Instrs0, Instrs1),
	value_number__push_incr_sp_forw_rev(Instrs1, MaybeFrameSize, Instrs2),
	(
		MaybeFrameSize = yes(N),
		value_number__push_save_succip_forw_rev(Instrs2, N, Instrs3)
	;
		MaybeFrameSize = no,
		Instrs3 = Instrs2
	),
	list__reverse(Instrs3, Instrs).

%-----------------------------------------------------------------------------%

:- pred value_number__push_incr_sp_forw_rev(list(instruction), maybe(int),
	list(instruction)).
% :- mode value_number__push_incr_sp_forw_rev(di, out, uo) is det.
:- mode value_number__push_incr_sp_forw_rev(in, out, out) is det.

value_number__push_incr_sp_forw_rev([], no, []).
value_number__push_incr_sp_forw_rev([Instr0 | Instrs0], MaybeFrameSize,
		Instrs) :-
	( Instr0 = incr_sp(N, Msg) - _ ->
		value_number__push_incr_sp_forw_rev_2(Instrs0, N, Msg, Instrs),
		MaybeFrameSize = yes(N)
	;
		value_number__push_incr_sp_forw_rev(Instrs0, MaybeFrameSize,
			Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

:- pred value_number__push_incr_sp_forw_rev_2(list(instruction), int, string,
	list(instruction)).
:- mode value_number__push_incr_sp_forw_rev_2(in, in, in, out) is det.

value_number__push_incr_sp_forw_rev_2([], N, Msg, [incr_sp(N, Msg) - ""]).
value_number__push_incr_sp_forw_rev_2([Instr0 | Instrs0], N, Msg, Instrs) :-
	Instr0 = Uinstr0 - _,
	value_number__boundary_instr(Uinstr0, Boundary),
	(
		Boundary = yes,
		Instrs = [incr_sp(N, Msg) - "", Instr0 | Instrs0],
		opt_util__block_refers_stackvars([Instr0 | Instrs], Ref),
		(
			Ref = yes,
			error("cannot push incr_sp forward enough")
		;
			Ref = no
		)
	;
		Boundary = no,
		value_number__push_incr_sp_forw_rev_2(Instrs0, N, Msg, Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

%-----------------------------------------------------------------------------%

:- pred value_number__push_save_succip_forw_rev(list(instruction), int,
	list(instruction)).
% :- mode value_number__push_save_succip_forw_rev(di, in, uo) is det.
:- mode value_number__push_save_succip_forw_rev(in, in, out) is det.

value_number__push_save_succip_forw_rev([], _, []).
value_number__push_save_succip_forw_rev([Instr0 | Instrs0], FrameSize,
		Instrs) :-
	( Instr0 = assign(stackvar(FrameSize), lval(succip)) - _ ->
		value_number__push_save_succip_forw_rev_2(Instrs0, FrameSize,
			Instrs)
	;
		value_number__push_save_succip_forw_rev(Instrs0, FrameSize,
			Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

:- pred value_number__push_save_succip_forw_rev_2(list(instruction), int,
	list(instruction)).
% :- mode value_number__push_save_succip_forw_rev_2(di, in, uo) is det.
:- mode value_number__push_save_succip_forw_rev_2(in, in, out) is det.

value_number__push_save_succip_forw_rev_2([], _FrameSize, _) :-
	error("succip save without incr_sp").
value_number__push_save_succip_forw_rev_2([Instr0 | Instrs0], FrameSize,
		Instrs) :-
	Instr0 = Uinstr0 - _,
	( Uinstr0 = incr_sp(FrameSize, _) ->
		Instrs = [assign(stackvar(FrameSize), lval(succip)) - "",
			Instr0 | Instrs0]
	;
		value_number__push_save_succip_forw_rev_2(Instrs0, FrameSize,
			Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

%-----------------------------------------------------------------------------%

:- pred value_number__push_livevals_back(list(instruction), list(instruction)).
% :- mode value_number__push_livevals_back(di, uo) is det.
:- mode value_number__push_livevals_back(in, out) is det.

value_number__push_livevals_back([], []).
value_number__push_livevals_back([Instr0 | Instrs0], Instrs) :-
	( Instr0 = livevals(Livevals) - _ ->
		value_number__push_livevals_back_2(Instrs0, Livevals, Instrs)
	;
		value_number__push_livevals_back(Instrs0, Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

:- pred value_number__push_livevals_back_2(list(instruction), lvalset,
	list(instruction)).
% :- mode value_number__push_livevals_back_2(di, in, uo) is det.
:- mode value_number__push_livevals_back_2(in, in, out) is det.

value_number__push_livevals_back_2([], Livevals, [livevals(Livevals) - ""]).
value_number__push_livevals_back_2([Instr0 | Instrs0], Livevals, Instrs) :-
	Instr0 = Uinstr0 - _,
	value_number__boundary_instr(Uinstr0, Boundary),
	opt_util__can_instr_branch_away(Uinstr0, CanBranch),
	( Boundary = yes, CanBranch = yes ->
		value_number__push_livevals_back([Instr0 | Instrs0], Instrs1),
		Instrs = [livevals(Livevals) - "" | Instrs1]
	;
		value_number__push_livevals_back_2(Instrs0, Livevals, Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

%-----------------------------------------------------------------------------%

	% Return true if we must treat this instruction as a boundary
	% instruction, i.e. an instruction across which it is neither safe
	% nor necessary to push stack frame setup or teardown instructions
	% (incr_sp, livevals and decr_sp).

:- pred value_number__boundary_instr(instr, bool).
:- mode value_number__boundary_instr(in, out) is det.

value_number__boundary_instr(comment(_), no).
value_number__boundary_instr(livevals(_), no).
value_number__boundary_instr(block(_, _, _), no).
value_number__boundary_instr(assign(Lval,_), Boundary) :-
	( Lval = redoip(_) ->
		Boundary = yes
	;
		Boundary = no
	).
value_number__boundary_instr(call(_, _, _, _, _, _), yes).
value_number__boundary_instr(mkframe(_, _), yes).
value_number__boundary_instr(label(_), yes).
value_number__boundary_instr(goto(_), yes).
value_number__boundary_instr(computed_goto(_, _), yes).
value_number__boundary_instr(c_code(_), yes).
value_number__boundary_instr(if_val(_, _), yes).
value_number__boundary_instr(incr_hp(_, _, _, _), no).
value_number__boundary_instr(mark_hp(_), no).
value_number__boundary_instr(restore_hp(_), no).
value_number__boundary_instr(free_heap(_), no).
value_number__boundary_instr(store_ticket(_), no).
value_number__boundary_instr(reset_ticket(_, _), no).
value_number__boundary_instr(discard_ticket, no).
value_number__boundary_instr(prune_ticket, no).
value_number__boundary_instr(mark_ticket_stack(_), no).
value_number__boundary_instr(prune_tickets_to(_), no).
value_number__boundary_instr(incr_sp(_, _), yes).
value_number__boundary_instr(decr_sp(_), yes).
value_number__boundary_instr(init_sync_term(_, _), no).
value_number__boundary_instr(fork(_, _, _), yes).
value_number__boundary_instr(join_and_terminate(_), yes).
value_number__boundary_instr(join_and_continue(_, _), yes).
value_number__boundary_instr(pragma_c(_, _, _, _, _, _, _), yes).

%-----------------------------------------------------------------------------%

:- pred value_number__has_no_backward_branches(list(instruction)).
:- mode value_number__has_no_backward_branches(in) is semidet.

value_number__has_no_backward_branches(Instrs) :-
	set__init(Labels),
	value_number__has_no_backward_branches_2(Instrs, Labels).

:- pred value_number__has_no_backward_branches_2(list(instruction), set(label)).
:- mode value_number__has_no_backward_branches_2(in, in) is semidet.

value_number__has_no_backward_branches_2([], _).
value_number__has_no_backward_branches_2([Instr - _ | Instrs], SoFar0) :-
	(
		Instr = label(Label)
	->
		set__insert(SoFar0, Label, SoFar)
	;
		opt_util__instr_labels(Instr, LabelRefs, _),
		value_number__no_old_labels(LabelRefs, SoFar0),
		SoFar = SoFar0
	),
	value_number__has_no_backward_branches_2(Instrs, SoFar).

:- pred value_number__no_old_labels(list(label), set(label)).
:- mode value_number__no_old_labels(in, in) is semidet.

value_number__no_old_labels([], _SoFar).
value_number__no_old_labels([Label | Labels], SoFar) :-
	\+ set__member(Label, SoFar),
	value_number__no_old_labels(Labels, SoFar).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

value_number__post_main(Instrs0, Instrs) :-
	value_number__post_main_2(Instrs0, 0, 0, [], Instrs).

	% R is the number of the highest numbered tempr variable seen so far;
	% R = 0 means we haven't seen any temp variables. Similarly, F is the
	% highest numbered tempf variable seen so far. RevSofar is a
	% reversed list of instructions starting with the first instruction
	% in this block that accesses a temp variable. Invariant: RevSofar
	% is always empty if R = 0 and F = 0.

:- pred value_number__post_main_2(list(instruction), int, int,
	list(instruction), list(instruction)).
:- mode value_number__post_main_2(in, in, in, in, out) is det.

value_number__post_main_2([], R, F, RevSofar, []) :-
	( RevSofar = [_|_] ->
		error("procedure ends with fallthrough")
	; ( R > 0 ; F > 0 ) ->
		error("procedure ends without closing block")
	;
		true
	).
value_number__post_main_2([Instr0 | Instrs0], R0, F0, RevSofar, Instrs) :-
	Instr0 = Uinstr0 - _Comment0,
	opt_util__count_temps_instr(Uinstr0, R0, R1, F0, F1),
	( ( R1 > 0 ; F1 > 0) ->
		( opt_util__can_instr_fall_through(Uinstr0, no) ->
			list__reverse([Instr0 | RevSofar], BlockInstrs),
			value_number__post_main_2(Instrs0, 0, 0, [], Instrs1),
			Instrs = [block(R1, F1, BlockInstrs) - "" | Instrs1]
		; Uinstr0 = label(_) ->
			list__reverse(RevSofar, BlockInstrs),
			value_number__post_main_2(Instrs0, 0, 0, [], Instrs1),
			Instrs = [block(R1, F1, BlockInstrs) - "", Instr0
				| Instrs1]
		;
			value_number__post_main_2(Instrs0, R1, F1,
				[Instr0 | RevSofar], Instrs)
		)
	;
		value_number__post_main_2(Instrs0, 0, 0, [], Instrs1),
		Instrs = [Instr0 | Instrs1]
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
