%---------------------------------------------------------------------------%
% Copyright (C) 1997 University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%

% File: prolog.m.
% Main author: fjh.

% This file contains predicates that are intended to help people
% porting Prolog programs, or writing programs in the intersection
% of Mercury and Prolog.

%-----------------------------------------------------------------------------%
:- module prolog.
:- interface.
:- import_module std_util, list.

% We define !/0 (and !/2 for dcgs) to be equivalent to `true'.  This is for
% backwards compatibility with Prolog systems.  But of course it only works
% if all your cuts are green cuts.

/********
cut is currently defined in mercury_builtin.m, for historical reasons.

:- pred ! is det.

:- pred !(T, T).
:- mode !(di, uo) is det.
:- mode !(in, out) is det.
********/

% Prolog arithmetic operators.

:- pred T =:= T.			% In Mercury, just use =
:- mode in =:= in is semidet.

:- pred T =\= T.			% In Mercury, just use \=
:- mode in =\= in is semidet.

/*******
is/2 is currently defined in int.m, for historical reasons.

:- pred is(T, T) is det.		% In Mercury, just use =
:- mode is(uo, di) is det.
:- mode is(out, in) is det.
******/

% Prolog term comparison operators.

:- pred T == T.				% In Mercury, just use =
:- mode in == in is semidet.

:- pred T \== T.			% In Mercury, just use \=
:- mode in \== in is semidet.

:- pred T @< T.
:- mode in @< in is semidet.

:- pred T @=< T.
:- mode in @=< in is semidet.

:- pred T @> T.
:- mode in @> in is semidet.

:- pred T @>= T.
:- mode in @>= in is semidet.

% Prolog's so-called "univ" operator, `=..'.
% Note: this is not related to Mercury's "univ" type!
% In Mercury, use `expand' (defined in module `std_util') instead.

:- pred T =.. univ_result.
:- mode in =.. out is det.
	%
	% Note that the Mercury =.. is a bit different to the Prolog
	% one.  We could make it slightly more similar by overloading '.'/2,
	% but that would cause ambiguities that might prevent type
	% inference in a lot of cases.
	% 
% :- type univ_result ---> '.'(string, list(univ)).
:- type univ_result == pair(string, list(univ)).

	% arg/3.  In Mercury, use argument/3 (defined in module std_util)
	% instead:
	%      arg(ArgNum, Term, Data) :- argument(Term, ArgNum - 1, Data).
	%
:- pred arg(int::in, T::in, univ::out) is semidet.

	% det_arg/3: like arg/3, but calls error/1 rather than failing
	% if the index is out of range.
	%
:- pred det_arg(int::in, T::in, univ::out) is det.
%-----------------------------------------------------------------------------%

:- implementation.
:- import_module require, int.

/*********
% !/0 and !/2 currently defined in mercury_builtin.m, for historical reasons.
!.
!(X, X).
*********/

X == X.
X \== Y :- X \= Y.

X =:= X.
X =\= Y :- X \= Y.

X @< Y :- compare(<, X, Y).
X @> Y :- compare(>, X, Y).
X @=< Y :- compare(R, X, Y), R \= (>).
X @>= Y :- compare(R, X, Y), R \= (<).

% we use a module qualifier here to avoid
% overriding the builtin Prolog version
'prolog__=..'(Term, Functor - Args) :-
	deconstruct(Term, Functor, _Arity, Args).

% we use a module qualifier here to avoid
% overriding the builtin Prolog version
prolog__arg(ArgumentIndex, Type, argument(Type, ArgumentIndex - 1)).

det_arg(ArgumentIndex, Type, Argument) :-
	( arg(ArgumentIndex, Type, Arg) ->
		Argument = Arg
	;
		error("det_arg: arg failed")
	).

%-----------------------------------------------------------------------------%
