%-----------------------------------------------------------------------------%
% Copyright (C) 1997-2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Main author: zs.
%
% This module defines a representation for basic blocks, sequences of
% instructions with one entry and one exit, and provides predicates
% that convert a list of instructions into a list of basic blocks
% and vice versa.

%-----------------------------------------------------------------------------%

:- module basic_block.

:- interface.

:- import_module llds.
:- import_module list, map, std_util, counter.

:- type block_map	==	map(label, block_info).

:- type block_info
	--->	block_info(
			label,
				% The label starting the block.
			instruction,
				% The instruction containing the label.
			list(instruction),
				% The code of the block without the initial
				% label.
			list(label),
				% The labels we can jump to
				% (not falling through).
			maybe(label)
				% The label we fall through to
				% (if there is one).
		).

:- pred create_basic_blocks(list(instruction)::in, list(instruction)::out,
	proc_label::in, counter::in, counter::out,
	list(label)::out, block_map::out) is det.

:- pred flatten_basic_blocks(list(label)::in, block_map::in,
        list(instruction)::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module opt_util.
:- import_module bool, int, require.

create_basic_blocks(Instrs0, Comments, ProcLabel, C0, C,
		LabelSeq, BlockMap) :-
	opt_util__get_prologue(Instrs0, LabelInstr, Comments,
		AfterLabelInstrs),
	Instrs1 = [LabelInstr | AfterLabelInstrs],
	map__init(BlockMap0),
	build_block_map(Instrs1, LabelSeq, BlockMap0, BlockMap,
		ProcLabel, C0, C).

	% Add labels to the given instruction sequence so that
	% every basic block has labels around it.

%-----------------------------------------------------------------------------%

:- pred build_block_map(list(instruction)::in, list(label)::out,
	block_map::in, block_map::out, proc_label::in,
	counter::in, counter::out) is det.

build_block_map([], [], BlockMap, BlockMap, _, C, C).
build_block_map([OrigInstr0 | OrigInstrs0], LabelSeq, BlockMap0, BlockMap,
		ProcLabel, C0, C) :-
	( OrigInstr0 = label(OrigLabel) - _ ->
		Label = OrigLabel,
		LabelInstr = OrigInstr0,
		RestInstrs = OrigInstrs0,
		C1 = C0
	;
		counter__allocate(N, C0, C1),
		Label = local(N, ProcLabel),
		LabelInstr = label(Label) - "",
		RestInstrs = [OrigInstr0 | OrigInstrs0]
	),
	( 
		take_until_end_of_block(RestInstrs, BlockInstrs, Instrs1),
		build_block_map(Instrs1, LabelSeq0,
			BlockMap0, BlockMap1, ProcLabel, C1, C),
		( list__last(BlockInstrs, LastInstr) ->
			LastInstr = LastUinstr - _,
			opt_util__possible_targets(LastUinstr, SideLabels),
			opt_util__can_instr_fall_through(LastUinstr,
				CanFallThrough),
			( CanFallThrough = yes ->
				get_fallthrough_from_seq(LabelSeq0,
					MaybeFallThrough)
			;
				MaybeFallThrough = no
			)
		;
			SideLabels = [],
			get_fallthrough_from_seq(LabelSeq0,
				MaybeFallThrough)
		),
		BlockInfo = block_info(Label, LabelInstr, BlockInstrs,
			SideLabels, MaybeFallThrough),
		map__det_insert(BlockMap1, Label, BlockInfo, BlockMap),
		LabelSeq = [Label | LabelSeq0]
	).

%-----------------------------------------------------------------------------%

:- pred take_until_end_of_block(list(instruction)::in,
	list(instruction)::out, list(instruction)::out) is det.

take_until_end_of_block([], [], []).
take_until_end_of_block([Instr0 | Instrs0], BlockInstrs, Rest) :-
	Instr0 = Uinstr0 - _Comment,
	( Uinstr0 = label(_) ->
		BlockInstrs = [],
		Rest = [Instr0 | Instrs0]
	; opt_util__can_instr_branch_away(Uinstr0, yes) ->
		BlockInstrs = [Instr0],
		Rest = Instrs0
	;
		take_until_end_of_block(Instrs0, BlockInstrs1, Rest),
		BlockInstrs = [Instr0 | BlockInstrs1]
	).

%-----------------------------------------------------------------------------%

:- pred get_fallthrough_from_seq(list(label)::in, maybe(label)::out) is det.

get_fallthrough_from_seq(LabelSeq, MaybeFallThrough) :-
	( LabelSeq = [NextLabel | _] ->
		MaybeFallThrough = yes(NextLabel)
	;
		MaybeFallThrough = no
	).

%-----------------------------------------------------------------------------%

flatten_basic_blocks([], _, []).
flatten_basic_blocks([Label | Labels], BlockMap, Instrs) :-
	flatten_basic_blocks(Labels, BlockMap, RestInstrs),
	map__lookup(BlockMap, Label, BlockInfo),
	BlockInfo = block_info(_, BlockLabelInstr, BlockInstrs, _, _),
	list__append([BlockLabelInstr | BlockInstrs], RestInstrs, Instrs).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
