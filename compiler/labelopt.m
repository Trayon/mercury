%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% labelopt.m - module to eliminate useless labels and dead code.

% Author: zs.

%-----------------------------------------------------------------------------%

:- module labelopt.

:- interface.

:- import_module list, llds.

	% Build up a set showing which labels are branched to,
	% then traverse the instruction list removing unnecessary labels.
	% If the instruction before the label branches away, we also
	% remove the instruction block following the label.

:- pred labelopt__main(list(instruction), bool, list(instruction), bool).
:- mode labelopt__main(in, in, out, out) is det.

	% Build up a set showing which labels are branched to.

:- pred labelopt__build_usemap(list(instruction), set(label)).
:- mode labelopt__build_usemap(in, out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module opt_util, std_util, set.

labelopt__main(Instrs0, Final, Instrs, Mod) :-
	labelopt__build_usemap(Instrs0, Usemap),
	labelopt__instr_list(Instrs0, yes, Usemap, Instrs1, Mod),
	( Final = yes, Mod = yes ->
		labelopt__main(Instrs1, Final, Instrs, _)
	;
		Instrs = Instrs1
	).

%-----------------------------------------------------------------------------%

labelopt__build_usemap(Instrs, Usemap) :-
	set__init(Usemap0),
	labelopt__build_usemap_2(Instrs, Usemap0, Usemap).

:- pred labelopt__build_usemap_2(list(instruction), set(label), set(label)).
:- mode labelopt__build_usemap_2(in, di, uo) is det.

labelopt__build_usemap_2([], Usemap, Usemap).
labelopt__build_usemap_2([Instr | Instructions], Usemap0, Usemap) :-
	Instr = Uinstr - _Comment,
	opt_util__instr_labels(Uinstr, Labels, CodeAddresses),
	labelopt__label_list_build_usemap(Labels, Usemap0, Usemap1),
	labelopt__code_addr_list_build_usemap(CodeAddresses, Usemap1, Usemap2),
	labelopt__build_usemap_2(Instructions, Usemap2, Usemap).

	% We are not interested in code addresses that are not labels.

:- pred labelopt__code_addr_list_build_usemap(list(code_addr),
	set(label), set(label)).
:- mode labelopt__code_addr_list_build_usemap(in, di, uo) is det.

labelopt__code_addr_list_build_usemap([], Usemap, Usemap).
labelopt__code_addr_list_build_usemap([Code_addr | Rest], Usemap0, Usemap) :-
	( Code_addr = label(Label) ->
		copy(Label, Label1),
		set__insert(Usemap0, Label1, Usemap1)
	;
		Usemap1 = Usemap0
	),
	labelopt__code_addr_list_build_usemap(Rest, Usemap1, Usemap).

:- pred labelopt__label_list_build_usemap(list(label), set(label), set(label)).
:- mode labelopt__label_list_build_usemap(in, di, uo) is det.

labelopt__label_list_build_usemap([], Usemap, Usemap).
labelopt__label_list_build_usemap([Label | Labels], Usemap0, Usemap) :-
	copy(Label, Label1),
	set__insert(Usemap0, Label1, Usemap1),
	labelopt__label_list_build_usemap(Labels, Usemap1, Usemap).

%-----------------------------------------------------------------------------%

	% Go through the given instruction sequence. When we find a label,
	% we check whether the label can be branched to either from within
	% the procedure or from the outside. If yes, we leave it alone.
	% If not, we delete it. We delete the following code as well if
	% the label was preceded by code that cannot fall through.

:- pred labelopt__instr_list(list(instruction), bool, set(label),
	list(instruction), bool).
:- mode labelopt__instr_list(in, in, in, out, out) is det.

labelopt__instr_list([], _Fallthrough, _Usemap, [], no).
labelopt__instr_list([Instr0 | MoreInstrs0],
		Fallthrough, Usemap, MoreInstrs, Mod) :-
	Instr0 = Uinstr0 - _Comment,
	( Uinstr0 = label(Label) ->
		(
			( Label = exported(_)
			; Label = local(_)
			; set__member(Label, Usemap)
			)
		->
			ReplInstrs = [Instr0],
			Fallthrough1 = yes,
			Mod0 = no
		;
			labelopt__eliminate(Instr0, yes(Fallthrough),
				ReplInstrs, Mod0),
			Fallthrough1 = Fallthrough
		)
	;
		( Fallthrough = yes ->
			ReplInstrs = [Instr0],
			Mod0 = no
		;
			labelopt__eliminate(Instr0, no, ReplInstrs, Mod0)
		),
		opt_util__can_instr_fall_through(Uinstr0, Canfallthrough),
		( Canfallthrough = yes ->
			Fallthrough1 = Fallthrough
		;
			Fallthrough1 = no
		)
	),
	labelopt__instr_list(MoreInstrs0, Fallthrough1, Usemap,
		MoreInstrs1, Mod1),
	list__append(ReplInstrs, MoreInstrs1, MoreInstrs),
	( Mod0 = no, Mod1 = no ->
		Mod = no
	;
		Mod = yes
	).

	% Instead of removing eliminated instructions from the instruction list,
	% we can replace them by placeholder comments. The original comment field
	% on the instruction is often enough to deduce what the eliminated
	% instruction was.

:- pred labelopt__eliminate(instruction, maybe(bool), list(instruction), bool).
:- mode labelopt__eliminate(in, in, out, out) is det.

labelopt__eliminate(Uinstr0 - Comment0, Label, Instr, Mod) :-
	labelopt_eliminate_total(Total),
	(
		Total = yes,
		Instr = [],
		Mod = yes
	;
		Total = no,
		( Uinstr0 = comment(_) ->
			Comment = Comment0,
			Uinstr = Uinstr0,
			Mod = no
		;
			( Label = yes(Follow) ->
				( Follow = yes ->
					Uinstr = comment("eliminated label only")
				;
					% Follow = no,
					Uinstr = comment("eliminated label and block")
				)
			;
				% Label = no,
				Uinstr = comment("eliminated instruction")
			),
			Comment = Comment0,
			Mod = yes
		),
		Instr = [Uinstr - Comment]
	).

:- pred labelopt_eliminate_total(bool).
:- mode labelopt_eliminate_total(out) is det.

labelopt_eliminate_total(yes).

%-----------------------------------------------------------------------------%
