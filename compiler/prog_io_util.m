%-----------------------------------------------------------------------------%
% Copyright (C) 1996-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: prog_io_util.m.
% Main author: fjh.
%
% This module defines the types used by prog_io and its subcontractors
% to return the results of parsing, and some utility predicates needed
% by several of prog_io's submodules.
%
% Most parsing predicates must check for errors. They return either the
% item(s) they were looking for, or an error indication.
%
% Most of the parsing predicates return a `maybe1(T)'
% or a `maybe2(T1, T2)', which will either be the
% `ok(ParseTree)' (or `ok(ParseTree1, ParseTree2)'),
% if the parse is successful, or `error(Message, Term)'
% if it is not.  The `Term' there should be the term which
% is syntactically incorrect.

:- module prog_io_util.

:- interface.

:- import_module prog_data, hlds_data, (inst).
:- import_module term.
:- import_module list, map, term, io.

:- type maybe2(T1, T2)	--->	error(string, term)
			;	ok(T1, T2).

:- type maybe1(T)	--->	error(string, term)
			;	ok(T).

:- type maybe1(T, U)	--->	error(string, term(U))
			;	ok(T).

:- type maybe_functor	== 	maybe2(sym_name, list(term)).
:- type maybe_functor(T) == 	maybe2(sym_name, list(term(T))).

:- type maybe_item_and_context
			==	maybe2(item, prog_context).

:- type var2tvar	==	map(var, tvar).

:- type var2pvar	==	map(var, prog_var).

:- pred add_context(maybe1(item), prog_context, maybe_item_and_context).
:- mode add_context(in, in, out) is det.

%
% Various predicates to parse small bits of syntax.
% These predicates simply fail if they encounter a syntax error.
%

:- pred parse_list_of_vars(term(T), list(var(T))).
:- mode parse_list_of_vars(in, out) is semidet.

:- pred convert_mode_list(list(term), list(mode)).
:- mode convert_mode_list(in, out) is semidet.

:- pred convert_mode(term, mode).
:- mode convert_mode(in, out) is semidet.

:- pred convert_inst_list(list(term), list(inst)).
:- mode convert_inst_list(in, out) is semidet.

:- pred convert_inst(term, inst).
:- mode convert_inst(in, out) is semidet.

:- pred standard_det(string, determinism).
:- mode standard_det(in, out) is semidet.

	% convert a "disjunction" (bunch of terms separated by ';'s) to a list

:- pred disjunction_to_list(term(T), list(term(T))).
:- mode disjunction_to_list(in, out) is det.

	% convert a "conjunction" (bunch of terms separated by ','s) to a list

:- pred conjunction_to_list(term(T), list(term(T))).
:- mode conjunction_to_list(in, out) is det.

	% convert a "sum" (bunch of terms separated by '+' operators) to a list

:- pred sum_to_list(term(T), list(term(T))).
:- mode sum_to_list(in, out) is det.

% The following /3, /4 and /5 predicates are to be used for reporting
% warnings to stderr.  This is preferable to using io__write_string, as
% this checks the halt-at-warn option.
%
% This predicate is best used by predicates that do not have access to
% module_info for a particular module.  It sets the exit status to error
% when a warning is encountered in a module, and the --halt-at-warn
% option is set.

:- pred report_warning(string::in, io__state::di, io__state::uo) is det.

:- pred report_warning(io__output_stream::in, string::in, io__state::di,
                      io__state::uo) is det.

:- pred report_warning(string::in, int::in, string::in, io__state::di,
                      io__state::uo) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module prog_io, prog_io_goal, hlds_pred, options, globals.
:- import_module bool, string, std_util, term.

add_context(error(M, T), _, error(M, T)).
add_context(ok(Item), Context, ok(Item, Context)).

parse_list_of_vars(term__functor(term__atom("[]"), [], _), []).
parse_list_of_vars(term__functor(term__atom("."), [Head, Tail], _), [V|Vs]) :-
	Head = term__variable(V),
	parse_list_of_vars(Tail, Vs).

convert_mode_list([], []).
convert_mode_list([H0|T0], [H|T]) :-
	convert_mode(H0, H),
	convert_mode_list(T0, T).

convert_mode(Term, Mode) :-
	(
		Term = term__functor(term__atom("->"), [InstA, InstB], _Context)
	->
		convert_inst(InstA, ConvertedInstA),
		convert_inst(InstB, ConvertedInstB),
		Mode = (ConvertedInstA -> ConvertedInstB)
	;
		% Handle higher-order predicate modes:
		% a mode of the form
		%	pred(<Mode1>, <Mode2>, ...) is <Det>
		% is an abbreviation for the inst mapping
		% 	(  pred(<Mode1>, <Mode2>, ...) is <Det>
		%	-> pred(<Mode1>, <Mode2>, ...) is <Det>
		%	)

		Term = term__functor(term__atom("is"), [PredTerm, DetTerm], _),
		PredTerm = term__functor(term__atom("pred"), ArgModesTerms, _)
	->
		DetTerm = term__functor(term__atom(DetString), [], _),
		standard_det(DetString, Detism),
		convert_mode_list(ArgModesTerms, ArgModes),
		PredInstInfo = pred_inst_info(predicate, ArgModes, Detism),
		Inst = ground(shared, yes(PredInstInfo)),
		Mode = (Inst -> Inst)
	;
		% Handle higher-order function modes:
		% a mode of the form
		%	func(<Mode1>, <Mode2>, ...) = <RetMode> is <Det>
		% is an abbreviation for the inst mapping
		% 	(  func(<Mode1>, <Mode2>, ...) = <RetMode> is <Det>
		%	-> func(<Mode1>, <Mode2>, ...) = <RetMode> is <Det>
		%	)

		Term = term__functor(term__atom("is"), [EqTerm, DetTerm], _),
		EqTerm = term__functor(term__atom("="),
					[FuncTerm, RetModeTerm], _),
		FuncTerm = term__functor(term__atom("func"), ArgModesTerms, _)
	->
		DetTerm = term__functor(term__atom(DetString), [], _),
		standard_det(DetString, Detism),
		convert_mode_list(ArgModesTerms, ArgModes0),
		convert_mode(RetModeTerm, RetMode),
		list__append(ArgModes0, [RetMode], ArgModes),
		FuncInstInfo = pred_inst_info(function, ArgModes, Detism),
		Inst = ground(shared, yes(FuncInstInfo)),
		Mode = (Inst -> Inst)
	;
		parse_qualified_term(Term, Term, "mode definition", R),
		R = ok(Name, Args),	% should improve error reporting
		convert_inst_list(Args, ConvertedArgs),
		Mode = user_defined_mode(Name, ConvertedArgs)
	).

convert_inst_list([], []).
convert_inst_list([H0|T0], [H|T]) :-
	convert_inst(H0, H),
	convert_inst_list(T0, T).

convert_inst(term__variable(V0), inst_var(V)) :-
	term__coerce_var(V0, V).
convert_inst(Term, Result) :-
	Term = term__functor(Name, Args0, _Context),
	% `free' insts
	( Name = term__atom("free"), Args0 = [] ->
		Result = free

	% `any' insts
	; Name = term__atom("any"), Args0 = [] ->
		Result = any(shared)
	; Name = term__atom("unique_any"), Args0 = [] ->
		Result = any(unique)
	; Name = term__atom("mostly_unique_any"), Args0 = [] ->
		Result = any(mostly_unique)
	; Name = term__atom("clobbered_any"), Args0 = [] ->
		Result = any(clobbered)
	; Name = term__atom("mostly_clobbered_any"), Args0 = [] ->
		Result = any(mostly_clobbered)

	% `ground' insts
	; Name = term__atom("ground"), Args0 = [] ->
		Result = ground(shared, no)
	; Name = term__atom("unique"), Args0 = [] ->
		Result = ground(unique, no)
	; Name = term__atom("mostly_unique"), Args0 = [] ->
		Result = ground(mostly_unique, no)
	; Name = term__atom("clobbered"), Args0 = [] ->
		Result = ground(clobbered, no)
	; Name = term__atom("mostly_clobbered"), Args0 = [] ->
		Result = ground(mostly_clobbered, no)
	;
		% The syntax for a higher-order pred inst is
		%
		%	pred(<Mode1>, <Mode2>, ...) is <Detism>
		%
		% where <Mode1>, <Mode2>, ... are a list of modes,
		% and <Detism> is a determinism.

		Name = term__atom("is"), Args0 = [PredTerm, DetTerm],
		PredTerm = term__functor(term__atom("pred"), ArgModesTerm, _)
	->
		DetTerm = term__functor(term__atom(DetString), [], _),
		standard_det(DetString, Detism),
		convert_mode_list(ArgModesTerm, ArgModes),
		PredInst = pred_inst_info(predicate, ArgModes, Detism),
		Result = ground(shared, yes(PredInst))
	;

		% The syntax for a higher-order func inst is
		%
		%	func(<Mode1>, <Mode2>, ...) = <RetMode> is <Detism>
		%
		% where <Mode1>, <Mode2>, ... are a list of modes,
		% <RetMode> is a mode, and <Detism> is a determinism.

		Name = term__atom("is"), Args0 = [EqTerm, DetTerm],
		EqTerm = term__functor(term__atom("="),
					[FuncTerm, RetModeTerm], _),
		FuncTerm = term__functor(term__atom("func"), ArgModesTerm, _)
	->
		DetTerm = term__functor(term__atom(DetString), [], _),
		standard_det(DetString, Detism),
		convert_mode_list(ArgModesTerm, ArgModes0),
		convert_mode(RetModeTerm, RetMode),
		list__append(ArgModes0, [RetMode], ArgModes),
		FuncInst = pred_inst_info(function, ArgModes, Detism),
		Result = ground(shared, yes(FuncInst))

	% `not_reached' inst
	; Name = term__atom("not_reached"), Args0 = [] ->
		Result = not_reached

	% `bound' insts
	; Name = term__atom("bound"), Args0 = [Disj] ->
		parse_bound_inst_list(Disj, shared, Result)
/* `bound_unique' is for backwards compatibility - use `unique' instead */
	; Name = term__atom("bound_unique"), Args0 = [Disj] ->
		parse_bound_inst_list(Disj, unique, Result)
	; Name = term__atom("unique"), Args0 = [Disj] ->
		parse_bound_inst_list(Disj, unique, Result)
	; Name = term__atom("mostly_unique"), Args0 = [Disj] ->
		parse_bound_inst_list(Disj, mostly_unique, Result)

	% anything else must be a user-defined inst
	;
		parse_qualified_term(Term, Term, "inst",
			ok(QualifiedName, Args1)),
		convert_inst_list(Args1, Args),
		Result = defined_inst(user_inst(QualifiedName, Args))
	).

standard_det("det", det).
standard_det("cc_nondet", cc_nondet).
standard_det("cc_multi", cc_multidet).
standard_det("nondet", nondet).
standard_det("multi", multidet).
standard_det("multidet", multidet).
standard_det("semidet", semidet).
standard_det("erroneous", erroneous).
standard_det("failure", failure).

:- pred parse_bound_inst_list(term::in, uniqueness::in, (inst)::out) is semidet.

parse_bound_inst_list(Disj, Uniqueness, bound(Uniqueness, Functors)) :-
	disjunction_to_list(Disj, List),
	convert_bound_inst_list(List, Functors0),
	list__sort_and_remove_dups(Functors0, Functors).

:- pred convert_bound_inst_list(list(term), list(bound_inst)).
:- mode convert_bound_inst_list(in, out) is semidet.

convert_bound_inst_list([], []).
convert_bound_inst_list([H0|T0], [H|T]) :-
	convert_bound_inst(H0, H),
	convert_bound_inst_list(T0, T).

:- pred convert_bound_inst(term, bound_inst).
:- mode convert_bound_inst(in, out) is semidet.

convert_bound_inst(InstTerm, functor(ConsId, Args)) :-
	InstTerm = term__functor(Functor, Args0, _),
	( Functor = term__atom(_) ->
		parse_qualified_term(InstTerm, InstTerm, "inst",
			ok(SymName, Args1)),
		list__length(Args1, Arity),
		ConsId = cons(SymName, Arity)
	;
		Args1 = Args0,
		list__length(Args1, Arity),
		make_functor_cons_id(Functor, Arity, ConsId)
	),
	convert_inst_list(Args1, Args).

disjunction_to_list(Term, List) :-
	binop_term_to_list(";", Term, List).

conjunction_to_list(Term, List) :-
	binop_term_to_list(",", Term, List).

sum_to_list(Term, List) :-
	binop_term_to_list("+", Term, List).

	% general predicate to convert terms separated by any specified
	% operator into a list

:- pred binop_term_to_list(string, term(T), list(term(T))).
:- mode binop_term_to_list(in, in, out) is det.

binop_term_to_list(Op, Term, List) :-
	binop_term_to_list_2(Op, Term, [], List).

:- pred binop_term_to_list_2(string, term(T), list(term(T)), list(term(T))).
:- mode binop_term_to_list_2(in, in, in, out) is det.

binop_term_to_list_2(Op, Term, List0, List) :-
	(
		Term = term__functor(term__atom(Op), [L, R], _Context)
	->
		binop_term_to_list_2(Op, R, List0, List1),
		binop_term_to_list_2(Op, L, List1, List)
	;
		List = [Term|List0]
	).

report_warning(Message) -->
	io__stderr_stream(StdErr),
	globals__io_lookup_bool_option(halt_at_warn, HaltAtWarn),
	( { HaltAtWarn = yes } ->
		io__set_exit_status(1)
	;
		[]
	),
	io__write_string(StdErr, Message).

report_warning(Stream, Message) -->
	globals__io_lookup_bool_option(halt_at_warn, HaltAtWarn),
	( { HaltAtWarn = yes } ->
		io__set_exit_status(1)
	;
		[]
	),
	io__write_string(Stream, Message).

report_warning(FileName, LineNum, Message) -->
	{ string__format("%s:%3d: Warning: %s\n",
		[s(FileName), i(LineNum), s(Message)], FullMessage) },
	io__stderr_stream(StdErr),
	io__write_string(StdErr, FullMessage),
	globals__io_lookup_bool_option(halt_at_warn, HaltAtWarn),
	( { HaltAtWarn = yes } ->
		io__set_exit_status(1)
	;
		[]
	).

%-----------------------------------------------------------------------------%
