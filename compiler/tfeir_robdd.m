%---------------------------------------------------------------------------%
% Copyright (C) 2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%

% File: xrobdd.m.
% Main author: dmo
% Stability: low

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module xrobdd.

:- interface.

:- import_module term, robdd.

:- type xrobdd(T).
:- type xrobdd == xrobdd(generic).

:- inst xrobdd == ground. % XXX

:- mode di_xrobdd == in. % XXX
:- mode uo_xrobdd == out. % XXX

% Constants.
:- func one = xrobdd(T).
:- func zero = xrobdd(T).

% Conjunction.
:- func xrobdd(T) * xrobdd(T) = xrobdd(T).

% Disjunction.
:- func xrobdd(T) + xrobdd(T) = xrobdd(T).

%-----------------------------------------------------------------------------%

:- func var(var(T)::in, xrobdd(T)::in(xrobdd)) = (xrobdd(T)::out(xrobdd))
		is det.

:- func not_var(var(T)::in, xrobdd(T)::in(xrobdd)) = (xrobdd(T)::out(xrobdd))
		is det.

:- func eq_vars(var(T)::in, var(T)::in, xrobdd(T)::di_xrobdd) =
		(xrobdd(T)::uo_xrobdd) is det.

:- func neq_vars(var(T)::in, var(T)::in, xrobdd(T)::di_xrobdd) =
		(xrobdd(T)::uo_xrobdd) is det.

:- func imp_vars(var(T)::in, var(T)::in, xrobdd(T)::di_xrobdd) =
		(xrobdd(T)::uo_xrobdd) is det.

:- func conj_vars(vars(T)::in, xrobdd(T)::di_xrobdd) = (xrobdd(T)::uo_xrobdd)
		is det.

:- func conj_not_vars(vars(T)::in, xrobdd(T)::di_xrobdd) =
		(xrobdd(T)::uo_xrobdd) is det.

:- func disj_vars(vars(T)::in, xrobdd(T)::di_xrobdd) = (xrobdd(T)::uo_xrobdd)
		is det.

:- func at_most_one_of(vars(T)::in, xrobdd(T)::di_xrobdd) =
		(xrobdd(T)::uo_xrobdd) is det.

:- func not_both(var(T)::in, var(T)::in, xrobdd(T)::di_xrobdd) =
		(xrobdd(T)::uo_xrobdd) is det.

:- func io_constraint(var(T)::in, var(T)::in, var(T)::in, xrobdd(T)::di_xrobdd)
		= (xrobdd(T)::uo_xrobdd) is det.

		% disj_vars_eq(Vars, Var) <=> (disj_vars(Vars) =:= Var).
:- func disj_vars_eq(vars(T)::in, var(T)::in, xrobdd(T)::di_xrobdd) =
		(xrobdd(T)::uo_xrobdd) is det.

:- func var_restrict_true(var(T)::in, xrobdd(T)::di_xrobdd) =
		(xrobdd(T)::uo_xrobdd) is det.

:- func var_restrict_false(var(T)::in, xrobdd(T)::di_xrobdd) =
		(xrobdd(T)::uo_xrobdd) is det.

%-----------------------------------------------------------------------------%

	% Succeed iff the var is entailed by the xROBDD.
:- pred var_entailed(xrobdd(T)::in, var(T)::in) is semidet.

	% Return the set of vars entailed by the xROBDD.
:- func vars_entailed(xrobdd(T)) = vars_entailed_result(T).

	% Return the set of vars disentailed by the xROBDD.
:- func vars_disentailed(xrobdd(T)) = vars_entailed_result(T).

	% Existentially quantify away the var in the xROBDD.
:- func restrict(var(T), xrobdd(T)) = xrobdd(T).

	% Existentially quantify away all vars greater than the specified var.
:- func restrict_threshold(var(T), xrobdd(T)) = xrobdd(T).

:- func restrict_filter(pred(var(T))::(pred(in) is semidet),
		xrobdd(T)::di_xrobdd) = (xrobdd(T)::uo_xrobdd) is det.

%-----------------------------------------------------------------------------%

	% labelling(Vars, xROBDD, TrueVars, FalseVars)
	%	Takes a set of Vars and an xROBDD and returns a value assignment
	%	for those Vars that is a model of the Boolean function
	%	represented by the xROBDD.
	%	The value assignment is returned in the two sets TrueVars (set
	%	of variables assigned the value 1) and FalseVars (set of
	%	variables assigned the value 0).
	%
	% XXX should try using sparse_bitset here.
:- pred labelling(vars(T)::in, xrobdd(T)::in, vars(T)::out, vars(T)::out)
		is nondet.

	% minimal_model(Vars, xROBDD, TrueVars, FalseVars)
	%	Takes a set of Vars and an xROBDD and returns a value assignment
	%	for those Vars that is a minimal model of the Boolean function
	%	represented by the xROBDD.
	%	The value assignment is returned in the two sets TrueVars (set
	%	of variables assigned the value 1) and FalseVars (set of
	%	variables assigned the value 0).
	%
	% XXX should try using sparse_bitset here.
:- pred minimal_model(vars(T)::in, xrobdd(T)::in, vars(T)::out, vars(T)::out)
		is nondet.

%-----------------------------------------------------------------------------%

% XXX
:- func robdd(xrobdd(T)) = robdd(T).

%-----------------------------------------------------------------------------%


:- implementation.

:- include_module xrobdd__equiv_vars.
:- include_module xrobdd__implications.

:- import_module robdd, sparse_bitset, bool, int, list.
:- import_module xrobdd__equiv_vars.
:- import_module xrobdd__implications.

% T - true vars, F - False Vars, E - equivalent vars, N -
% non-equivalent vars, I - implications, R - ROBDD.
%
% Combinations to try:
%	R	(straight ROBDD)
%	TFR
%	TER	(Peter Schachte's extension)
%	TFEIR
%	TFENIR

:- type xrobdd(T)
	--->	xrobdd(
			true_vars :: vars(T),
			false_vars :: vars(T),
			equiv_vars :: equiv_vars(T),
			imp_vars :: imp_vars(T),
			robdd :: robdd(T)
		).


one = xrobdd(init, init, init_equiv_vars, init_imp_vars, one).

zero = xrobdd(init, init, init_equiv_vars, init_imp_vars, zero).

xrobdd(TA, FA, EA, IA, RA) * xrobdd(TB, FB, EB, IB, RB) = 
		normalise(xrobdd(TA1 `union` TB1, FA1 `union` FB1,
			EA1 * EB1, IA1 * IB1, RA1 * RB1)) :-
	TU = TA `union` TB,
	FU = FA `union` FB,
	EU = EA * EB,
	IU = IA * IB,
	xrobdd(TA1, FA1, EA1, IA1, RA1) = normalise(xrobdd(TU, FU, EU, IU, RA)),
	xrobdd(TB1, FB1, EB1, IB1, RB1) = normalise(xrobdd(TU, FU, EU, IU, RB)).

xrobdd(TA0, FA0, EA0, IA0, RA0) + xrobdd(TB0, FB0, EB0, IB0, RB0) = X :-
	( RA0 = zero ->
	    X = xrobdd(TB0, FB0, EB0, IB0, RB0)
	; RB0 = zero ->
	    X = xrobdd(TA0, FA0, EA0, IA0, RA0)
	;
	    X = xrobdd(T, F, E, I, R),
	    T = TA0 `intersect` TB0,
	    F = FA0 `intersect` FB0,
	    E = EA + EB,
	    I = IA + IB,
	    R = RA + RB,

	    TAB = TA0 `difference` TB0,
	    FAB = FA0 `difference` FB0,
	    EA = EA0 ^ add_equalities(TAB) ^ add_equalities(FAB),

	    TBA = TB0 `difference` TA0,
	    FBA = FB0 `difference` FA0,
	    EB = EB0 ^ add_equalities(TBA) ^ add_equalities(FBA),

	    EAB = EA `difference` EB,
	    IA = IA0 ^ add_equalities_to_imp_vars(EAB),

	    EBA = EB `difference` EA,
	    IB = IB0 ^ add_equalities_to_imp_vars(EBA),

	    RA1 = foldl(func(V, R0) = R0 * var(E ^ det_leader(V)), TAB, RA0),
	    RA2 = foldl(func(V, R0) = R0 * 
			    not_var(E ^ det_leader(V)), FAB, RA1),
	    EA1 = (EA `difference` EB) + EA0,
	    RA3 = expand_equiv(EA1, RA2),
	    IA1 = (IA `difference` IB) + IA0,
	    RA = expand_implications(IA1, RA3),

	    RB1 = foldl(func(V, R0) = R0 * var(E ^ det_leader(V)), TBA, RB0),
	    RB2 = foldl(func(V, R0) = R0 *
			    not_var(E ^ det_leader(V)), FBA, RB1),
	    EB1 = (EB `difference` EA) + EB0,
	    RB3 = expand_equiv(EB1, RB2),
	    IB1 = (IB `difference` IA) + IB0,
	    RB = expand_implications(IB1, RB3)
	).

var_entailed(X, V) :-
	(X ^ robdd = zero ; X ^ true_vars `contains` V).

vars_entailed(X) =
	(X ^ robdd = zero ->
		all_vars
	;
		some_vars(X ^ true_vars)
	).

vars_disentailed(X) =
	(X ^ robdd = zero ->
		all_vars
	;
		some_vars(X ^ false_vars)
	).

restrict(V, xrobdd(T, F, E, I, R)) =
	( T `contains` V ->
	    xrobdd(T `delete` V, F, E, I, R)
	; F `contains` V ->
	    xrobdd(T, F `delete` V, E, I, R)
	; L = E ^ leader(V) ->
	    ( L \= V ->
		xrobdd(T, F, E `delete` V, I, R)
	    ;
		xrobdd(T, F, E `delete` V, I `delete` V, restrict(V, R))
	    )
	;
	    xrobdd(T, F, E, I `delete` V, restrict(V, R))
	).

restrict_threshold(V, xrobdd(T, F, E, I, R)) =
	xrobdd(remove_gt(T, V), remove_gt(F, V), restrict_threshold(V, E),
		restrict_threshold(V, I), restrict_threshold(V, R)).

var(V, X) =
	( T `contains` V ->
		X
	; F `contains` V ->
		zero
	;
		normalise(xrobdd(T `insert` V, F, E, I, R))
	) :-
	X = xrobdd(T, F, E, I, R).

not_var(V, X) =
	( F `contains` V ->
		X
	; T `contains` V ->
		zero
	;
		normalise(xrobdd(T, F `insert` V, E, I, R))
	) :-
	X = xrobdd(T, F, E, I, R).

eq_vars(VarA, VarB, X) = 
	( 
		( T `contains` VarA, T `contains` VarB
		; F `contains` VarA, F `contains` VarB
		)
	->
		X
	;
		( T `contains` VarA, F `contains` VarB
		; F `contains` VarA, T `contains` VarB
		)
	->
		zero
	;
		normalise(xrobdd(T, F, add_equality(VarA, VarB, E), I, R))
	) :-
	X = xrobdd(T, F, E, I, R).

neq_vars(VarA, VarB, X) = 
	( 
		( T `contains` VarA, T `contains` VarB
		; F `contains` VarA, F `contains` VarB
		)
	->
		zero
	;
		( T `contains` VarA, F `contains` VarB
		; F `contains` VarA, T `contains` VarB
		)
	->
		X
	;
		normalise(xrobdd(T, F, E, I ^ neq_vars(VarA, VarB), R))
	) :-
	X = xrobdd(T, F, E, I, R).

imp_vars(VarA, VarB, X) =
	( T `contains` VarA, F `contains` VarB ->
		zero
	; T `contains` VarB ->
		X
	; F `contains` VarA ->
		X
	;
		normalise(xrobdd(T, F, E, I ^ imp_vars(VarA, VarB), R))
	) :-
	X = xrobdd(T, F, E, I, R).

conj_vars(Vars, X) =
	( Vars `subset` T ->
		X
	; \+ empty(Vars `intersect` F) ->
		zero
	;
		normalise(xrobdd(T `union` Vars, F, E, I, R))
	) :-
	X = xrobdd(T, F, E, I, R).

conj_not_vars(Vars, X) =
	( Vars `subset` F ->
		X
	; \+ empty(Vars `intersect` T) ->
		zero
	;
		normalise(xrobdd(T, F `union` Vars, E, I, R))
	) :-
	X = xrobdd(T, F, E, I, R).

disj_vars(Vars, X) =
	( \+ empty(Vars `intersect` T) ->
		X
	; Vars `subset` F ->
		zero
	;
		X `x` disj_vars(Vars)
	) :-
	X = xrobdd(T, F, _E, _I, _R).

at_most_one_of(Vars, X) =
	( count(Vars `difference` F) =< 1 ->
		X
	; count(Vars `intersect` T) > 1 ->
		zero
	;
		normalise(xrobdd(T, F, E, I ^ at_most_one_of(Vars), R))
	) :-
	X = xrobdd(T, F, E, I, R).

not_both(VarA, VarB, X) =
	( F `contains` VarA ->
		X
	; F `contains` VarB ->
		X
	; T `contains` VarA ->
		not_var(VarB, X)
	; T `contains` VarB ->
		not_var(VarA, X)
	;
		normalise(xrobdd(T, F, E, I ^ not_both(VarA, VarB), R))
	) :-
	X = xrobdd(T, F, E, I, R).

io_constraint(V_in, V_out, V_, X) = 
	X ^ not_both(V_in, V_) ^ disj_vars_eq(Vars, V_out) :-
	Vars = list_to_set([V_in, V_]).

disj_vars_eq(Vars, Var, X) = 
	( F `contains` Var ->
		( Vars `subset` F ->
			X
		;
			X ^ conj_not_vars(Vars)
		)
	; T `contains` Var ->
		( Vars `subset` F ->
			zero
		;
			X ^ disj_vars(Vars)
		)
	;
		X `x` (disj_vars(Vars) =:= var(Var))
	) :-
	X = xrobdd(T, F, _E, _I, _R).

var_restrict_true(V, xrobdd(T, F, E, I, R)) = X :-
	( F `contains` V ->
	    X = zero
	; T `contains` V ->
	    X = xrobdd(T `delete` V, F, E, I, R)
	;
	    X0 = normalise(xrobdd(T `insert` V, F, E, I, R)),
	    X = X0 ^ true_vars := X0 ^ true_vars `delete` V
	).

var_restrict_false(V, xrobdd(T, F, E, I, R)) = X :-
	( T `contains` V ->
	    X = zero
	; F `contains` V ->
	    X = xrobdd(T, F `delete` V, E, I, R)
	;
	    X0 = normalise(xrobdd(T, F `insert` V, E, I, R)),
	    X = X0 ^ false_vars := X0 ^ false_vars `delete` V
	).

restrict_filter(P, xrobdd(T, F, E, I, R)) =
	xrobdd(filter(P, T), filter(P, F), filter(P, E), filter(P, I),
		restrict_filter(P, R)).

labelling(Vars0, xrobdd(T, F, E, I, R), TrueVars, FalseVars) :-
	TrueVars0 = T `intersect` Vars0,
	FalseVars0 = F `intersect` Vars0,
	Vars = Vars0 `difference` TrueVars0 `difference` FalseVars0,

	( empty(Vars) ->
	    TrueVars = TrueVars0,
	    FalseVars = FalseVars0
	;
	    labelling_2(Vars, xrobdd(init, init, E, I, R), TrueVars1,
	    	FalseVars1),
	    TrueVars = TrueVars0 `union` TrueVars1,
	    FalseVars = FalseVars0 `union` FalseVars1
	).

:- pred labelling_2(vars(T)::in, xrobdd(T)::in, vars(T)::out, vars(T)::out)
		is nondet.

labelling_2(Vars0, X0, TrueVars, FalseVars) :-
	( remove_least(Vars0, V, Vars) ->
	    (
		X = var_restrict_false(V, X0),
		X ^ robdd \= zero,
		labelling_2(Vars, X, TrueVars, FalseVars0),
		FalseVars = FalseVars0 `insert` V
	    ;
		X = var_restrict_true(V, X0),
		X ^ robdd \= zero,
		labelling_2(Vars, X, TrueVars0, FalseVars),
		TrueVars = TrueVars0 `insert` V
	    )
	;
	    TrueVars = init,
	    FalseVars = init
	).


minimal_model(Vars, X0, TrueVars, FalseVars) :-
	( empty(Vars) ->
	    TrueVars = init,
	    FalseVars = init
	;
	    minimal_model_2(Vars, X0, TrueVars0, FalseVars0),
	    (
		TrueVars = TrueVars0,
		FalseVars = FalseVars0
	    ;
		X = X0 `x` (~conj_vars(TrueVars0)),
		minimal_model(Vars, X, TrueVars, FalseVars)
	    )
	).

:- pred minimal_model_2(vars(T)::in, xrobdd(T)::in, vars(T)::out, vars(T)::out)
	is semidet.

minimal_model_2(Vars0, X0, TrueVars, FalseVars) :-
	( remove_least(Vars0, V, Vars) ->
	    X1 = var_restrict_false(V, X0),
	    ( X1 ^ robdd \= zero ->
		minimal_model_2(Vars, X1, TrueVars, FalseVars0),
		FalseVars = FalseVars0 `insert` V
	    ;
		X2 = var_restrict_true(V, X0),
		X2 ^ robdd \= zero,
		minimal_model_2(Vars, X2, TrueVars0, FalseVars),
		TrueVars = TrueVars0 `insert` V
	    )
	;
	    TrueVars = init,
	    FalseVars = init
	).


%-----------------------------------------------------------------------------%

:- func normalise(xrobdd(T)::di_xrobdd) = (xrobdd(T)::uo_xrobdd) is det.

normalise(xrobdd(TrueVars0, FalseVars0, EQVars0, ImpVars0, Robdd0)) = X :-
	% T <-> F
	( \+ empty(TrueVars0 `intersect` FalseVars0) ->
	    X = zero
	;
	    % TF <-> E
	    normalise_true_false_equivalent_vars(Changed0, TrueVars0,
		TrueVars1, FalseVars0, FalseVars1, EQVars0, EQVars1),

	    % TF <-> I
	    normalise_true_false_implication_vars(Changed1, TrueVars1,
		TrueVars2, FalseVars1, FalseVars2, ImpVars0, ImpVars1),
	    Changed2 = Changed0 `bool__or` Changed1,

	    % TF -> R
	    Robdd1 = restrict_true_false_vars(TrueVars2, FalseVars2,
			Robdd0),
	    Changed3 = Changed2 `bool__or` ( Robdd1 \= Robdd0 -> yes ; no),

	    (
		% TF <- R
		definite_vars(Robdd1,
				some_vars(NewTrueVars), some_vars(NewFalseVars))
	    ->
		(
		    empty(NewTrueVars),
		    empty(NewFalseVars)
		->
		    Changed4 = Changed3,
		    TrueVars = TrueVars2,
		    FalseVars = FalseVars2
		;
		    Changed4 = yes,
		    TrueVars = TrueVars2 `union` NewTrueVars,
		    FalseVars = FalseVars2 `union` NewFalseVars
		),

		% E <-> I
		(
		    propagate_equivalences_into_implications(EQVars1,
			Changed5, ImpVars1, ImpVars2)
		->
		    propagate_implications_into_equivalences(Changed6,
			EQVars1, EQVars2, ImpVars2, ImpVars3),
		    Changed7 = Changed4 `bool__or` Changed5 `bool__or` Changed6,

		    % E <-> R
		    extract_equivalent_vars_from_robdd(Changed8, Robdd1, Robdd2,
			EQVars2, EQVars),
		    Changed9 = Changed7 `bool__or` Changed8,

		    % I <-> R
		    extract_implication_vars_from_robdd(Changed10, Robdd2,
			Robdd, ImpVars3, ImpVars),
		    Changed = Changed9 `bool__or` Changed10,

		    X0 = xrobdd(TrueVars, FalseVars, EQVars, ImpVars, Robdd),
		    X = ( Changed = yes ->
			normalise(X0)
		    ;
			X0
		    )
		;
		    X = zero
		)
	    ;
		X = zero
	    )
	).

:- pred normalise_true_false_equivalent_vars(bool::out, vars(T)::in,
	vars(T)::out, vars(T)::in, vars(T)::out, equiv_vars(T)::in,
	equiv_vars(T)::out) is det.

normalise_true_false_equivalent_vars(Changed, T0, T, F0, F) -->
	normalise_known_equivalent_vars(Changed0, T0, T),
	normalise_known_equivalent_vars(Changed1, F0, F),
	{ Changed = Changed0 `bool__or` Changed1 }.

:- pred extract_equivalent_vars_from_robdd(bool::out, robdd(T)::in,
	robdd(T)::out, equiv_vars(T)::in, equiv_vars(T)::out) is det.

extract_equivalent_vars_from_robdd(Changed, Robdd0, Robdd, EQVars0, EQVars) :-
	( RobddEQVars = equivalent_vars_in_robdd(Robdd0) ->
		( empty(RobddEQVars) ->
			Changed0 = no,
			Robdd1 = Robdd0,
			EQVars = EQVars0
		;
			Changed0 = yes,

			% Remove any equalities we have just found from the
			% ROBDD.
			Robdd1 = squeeze_equiv(RobddEQVars, Robdd0),

			EQVars = EQVars0 * RobddEQVars
		)
	;
		EQVars = init_equiv_vars,
		Changed0 = ( EQVars = EQVars0 -> no ; yes ),
		Robdd1 = Robdd0
	),
	
	% Remove any other equalities from the ROBDD.
	% Note that we can use EQVars0 here since we have already removed the
	% equivalences in RobddEQVars using squeeze_equiv.
	Robdd = remove_equiv(EQVars0, Robdd1),
	Changed = Changed0 `bool__or` ( Robdd \= Robdd1 -> yes ; no ).

:- func x(xrobdd(T)::di_xrobdd, robdd(T)::in) = (xrobdd(T)::uo_xrobdd) is det.

x(X, R) = X * xrobdd(init, init, init_equiv_vars, init_imp_vars, R).

%---------------------------------------------------------------------------%
