%-----------------------------------------------------------------------------%
% Copyright (C) 2001-2004 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: inst_graph.m
% Author: dmo
%
% This module defines operations on instantiation graphs. The purpose of the
% data structure and of the operations on it are defined in chapter 6 of
% David Overton's PhD thesis.

:- module hlds__inst_graph.
:- interface.

:- import_module parse_tree__prog_data.

:- import_module list, map, io.

:- type inst_graph == map(prog_var, node).

:- type node
	--->	node(
			map(cons_id, list(prog_var)),
			% If the variable that maps to this node occurs on the
			% left hand side of any var-functor unifications,
			% this map gives, for each functor that occurs in such
			% unifications, the identities of the variables
			% chosen by the transformation to hyperhomogeneous form
			% to represent the arguments of that functor inside
			% the cell variable.

			maybe_parent
			% Specifies whether
		).

:- type maybe_parent
	--->	top_level
		% The variable in whose node this maybe_parent value occurs
		% doesn't appear on the right hand side of any var-functor
		% unifications.

	;	parent(prog_var).
		% The variable in whose node this maybe_parent value occurs
		% does appear on the right hand side of a var-functor
		% unification: the argument of parent identifies
		% the variable on the left hand side. The definition of
		% hyperhomogeneous form guarantees that this variable is
		% unique.

	% Initialise an inst_graph. Adds a node for each variable, and
	% initializes each node to have no parents and no children.
:- pred init(list(prog_var)::in, inst_graph::out) is det.

	% set_parent(Parent, Child, Graph0, Graph)
	%	Sets Parent to be the parent node of Child.  Aborts if
	%	Child already has a parent.
:- pred set_parent(prog_var::in, prog_var::in, inst_graph::in, inst_graph::out)
	is det.

	% top_level_node(InstGraph, VarA, VarB)
	%	Succeeds iff VarB is the top_level node reachable
	%	from VarA in InstGraph.
:- pred top_level_node(inst_graph::in, prog_var::in, prog_var::out) is det.

	% descendant(InstGraph, VarA, VarB)
	%	Succeeds iff VarB is a descendant of VarA in InstGraph.
:- pred descendant(inst_graph::in, prog_var::in, prog_var::out) is nondet.

	% reachable(InstGraph, VarA, VarB)
	%	Succeeds iff VarB is a descendant of VarA in InstGraph,
	%	or if VarB *is* VarA.
:- pred reachable(inst_graph::in, prog_var::in, prog_var::out) is multi.

	% reachable(InstGraph, Vars, VarB)
	%	Succeeds iff VarB is a descendant in InstGraph of any VarA
	%	in Vars.
:- pred reachable_from_list(inst_graph::in, list(prog_var)::in, prog_var::out)
	is nondet.

	% foldl_reachable(Pred, InstGraph, Var, Acc0, Acc):
	%	Performs a foldl operation over all variables V for which
	%	reachable(InstGraph, Var, V) is true.
:- pred foldl_reachable(pred(prog_var, T, T)::pred(in, in, out) is det,
	inst_graph::in, prog_var::in, T::in, T::out) is det.

	% foldl_reachable_from_list(Pred, InstGraph, Vars, Acc0, Acc):
	%	Performs a foldl operation over all variables V for which
	%	reachable_from_list(InstGraph, Vars, V) is true.
:- pred foldl_reachable_from_list(
	pred(prog_var, T, T)::pred(in, in, out) is det,
	inst_graph::in, list(prog_var)::in, T::in, T::out) is det.

	% A version of foldl_reachable with two accumulators.
:- pred foldl_reachable2(
	pred(prog_var, T, T, U, U)::pred(in, in, out, in, out) is det,
	inst_graph::in, prog_var::in, T::in, T::out, U::in, U::out) is det.

	% A version of foldl_reachable_from_list with two accumulators.
:- pred foldl_reachable_from_list2(
	pred(prog_var, T, T, U, U)::pred(in, in, out, in, out) is det,
	inst_graph::in, list(prog_var)::in, T::in, T::out, U::in, U::out)
	is det.

:- pred corresponding_nodes(inst_graph::in, prog_var::in, prog_var::in,
	prog_var::out, prog_var::out) is multi.

:- pred corresponding_nodes(inst_graph::in, inst_graph::in, prog_var::in,
	prog_var::in, prog_var::out, prog_var::out) is multi.

:- pred corresponding_nodes_from_lists(inst_graph::in, inst_graph::in,
	list(prog_var)::in, list(prog_var)::in, prog_var::out, prog_var::out)
	is nondet.

	% Merge two inst_graphs by renaming the variables in the second
	% inst_graph.  Also return the variable substitution map.
:- pred merge(inst_graph::in, prog_varset::in, inst_graph::in, prog_varset::in,
	inst_graph::out, prog_varset::out, map(prog_var, prog_var)::out)
	is det.

% 	% Join two inst_graphs together by taking the maximum unrolling
% 	% of the type tree of each variable from the two graphs.
% :- pred join(inst_graph::in, prog_varset::in, inst_graph::in,
% 	prog_varset::in, inst_graph::out, prog_varset::out) is det.

	% Print the given inst_graph over the given varset in a format
	% suitable for debugging output.
:- pred dump(inst_graph::in, prog_varset::in, io::di, io::uo) is det.

	% XXX this should probably go in list.m.
:- pred corresponding_members(list(T)::in, list(U)::in, T::out, U::out)
	is nondet.

	% Values of this type are intended to contain all the info related
	% to inst_graphs for a predicate that needs to be stored in the
	% pred_info.
:- type inst_graph_info.

	% Create an empty inst_graph_info.
:- func inst_graph_info_init = inst_graph_info.

:- func interface_inst_graph(inst_graph_info) = inst_graph.
:- func 'interface_inst_graph :='(inst_graph_info, inst_graph) =
	inst_graph_info.

:- func interface_vars(inst_graph_info) = list(prog_var).
:- func 'interface_vars :='(inst_graph_info, list(prog_var)) = inst_graph_info.

:- func interface_varset(inst_graph_info) = prog_varset.
:- func 'interface_varset :='(inst_graph_info, prog_varset) = inst_graph_info.

:- func implementation_inst_graph(inst_graph_info) = inst_graph.
:- func 'implementation_inst_graph :='(inst_graph_info, inst_graph) =
	inst_graph_info.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module hlds__hlds_data.
:- import_module hlds__hlds_out.

:- import_module require, set, std_util, varset, term, term_io.

init(Vars, InstGraph) :-
	map__init(InstGraph0),
	list__foldl(init_var, Vars, InstGraph0, InstGraph).

:- pred init_var(prog_var::in, inst_graph::in, inst_graph::out) is det.

init_var(Var, InstGraph0, InstGraph) :-
	map__det_insert(InstGraph0, Var, node(map__init, top_level), InstGraph).

set_parent(Parent, Child, InstGraph0, InstGraph) :-
	map__lookup(InstGraph0, Child, node(Functors, MaybeParent0)),
	( MaybeParent0 = top_level ->
		map__det_update(InstGraph0, Child,
			node(Functors, parent(Parent)), InstGraph)
	;
		error("set_parent: node already has parent")
	).

top_level_node(InstGraph, Var, TopLevel) :-
	map__lookup(InstGraph, Var, node(_, MaybeParent)),
	(
		MaybeParent = parent(Parent),
		top_level_node(InstGraph, Parent, TopLevel)
	;
		MaybeParent = top_level,
		TopLevel = Var
	).

descendant(InstGraph, Var, Descendant) :-
	set__init(Seen),
	descendant_2(InstGraph, Seen, Var, Descendant).

:- pred descendant_2(inst_graph::in, set(prog_var)::in, prog_var::in,
	prog_var::out) is nondet.

descendant_2(InstGraph, Seen, Var, Descendant) :-
	map__lookup(InstGraph, Var, node(Functors, _)),
	map__member(Functors, _ConsId, Args),
	list__member(Arg, Args),
	(
		Descendant = Arg
	;
		( Arg `set__member` Seen ->
			fail
		;
			descendant_2(InstGraph, Seen `set__insert` Arg,
				Arg, Descendant)
		)
	).

reachable(_InstGraph, Var, Var).
reachable(InstGraph, Var, Reachable) :-
	descendant(InstGraph, Var, Reachable).

reachable_from_list(InstGraph, Vars, Reachable) :-
	list__member(Var, Vars),
	reachable(InstGraph, Var, Reachable).

foldl_reachable(P, InstGraph, Var, !Acc) :-
	% a possible alternate implementation:
	% aggregate(reachable(InstGraph, Var), P, !Acc).
	foldl_reachable_aux(P, InstGraph, Var, set__init, !Acc).

:- pred foldl_reachable_aux(pred(prog_var, T, T)::pred(in, in, out) is det,
	inst_graph::in, prog_var::in, set(prog_var)::in, T::in, T::out) is det.

foldl_reachable_aux(P, InstGraph, Var, Seen, !Acc) :-
	P(Var, !Acc),
	map__lookup(InstGraph, Var, node(Functors, _)),
	map__foldl((pred(_ConsId::in, Args::in, MAcc0::in, MAcc::out) is det :-
		list__foldl((pred(Arg::in, LAcc0::in, LAcc::out) is det :-
			( Arg `set__member` Seen ->
				LAcc = LAcc0
			;
				foldl_reachable_aux(P,
					InstGraph, Arg, Seen `set__insert` Arg,
					LAcc0, LAcc)
			)
		), Args, MAcc0, MAcc)
	), Functors, !Acc).

foldl_reachable_from_list(P, InstGraph, Vars) -->
	list__foldl(foldl_reachable(P, InstGraph), Vars).

foldl_reachable2(P, InstGraph, Var, !Acc1, !Acc2) :-
	% a possible alternate implementation:
	% aggregate2(reachable(InstGraph, Var), P, !Acc1, !Acc2).
	foldl_reachable_aux2(P, InstGraph, Var, set__init,
		!Acc1, !Acc2).

:- pred foldl_reachable_aux2(
	pred(prog_var, T, T, U, U)::pred(in, in, out, in, out) is det,
	inst_graph::in, prog_var::in, set(prog_var)::in, T::in, T::out,
	U::in, U::out) is det.

foldl_reachable_aux2(P, InstGraph, Var, Seen, !Acc1, !Acc2) :-
	P(Var, !Acc1, !Acc2),
	map__lookup(InstGraph, Var, node(Functors, _)) ,
	map__foldl2((pred(_ConsId::in, Args::in, MAcc10::in, MAcc1::out,
			MAcc20::in, MAcc2::out) is det :-
		list__foldl2((pred(Arg::in, LAccA0::in, LAccA::out,
				LAccB0::in, LAccB::out) is det :-
			( Arg `set__member` Seen ->
				LAccA = LAccA0,
				LAccB = LAccB0
			;
				foldl_reachable_aux2(P,
					InstGraph, Arg, Seen `set__insert` Arg,
					LAccA0, LAccA, LAccB0, LAccB)
			)
		), Args, MAcc10, MAcc1, MAcc20, MAcc2)
	), Functors, !Acc1, !Acc2).

foldl_reachable_from_list2(P, InstGraph, Vars, !Acc1, !Acc2) :-
	list__foldl2(foldl_reachable2(P, InstGraph), Vars,
		!Acc1, !Acc2).

corresponding_nodes(InstGraph, A, B, V, W) :-
	corresponding_nodes(InstGraph, InstGraph, A, B, V, W).

corresponding_nodes(InstGraphA, InstGraphB, A, B, V, W) :-
	corresponding_nodes_2(InstGraphA, InstGraphB,
		set__init, set__init, A, B, V, W).

:- pred corresponding_nodes_2(inst_graph::in, inst_graph::in,
	set(prog_var)::in, set(prog_var)::in, prog_var::in, prog_var::in,
	prog_var::out, prog_var::out) is multi.

corresponding_nodes_2(_, _, _, _, A, B, A, B).
corresponding_nodes_2(InstGraphA, InstGraphB, SeenA0, SeenB0, A, B, V, W) :-
	not ( A `set__member` SeenA0, B `set__member` SeenB0 ),

	map__lookup(InstGraphA, A, node(FunctorsA, _)),
	map__lookup(InstGraphB, B, node(FunctorsB, _)),

	SeenA = SeenA0 `set__insert` A,
	SeenB = SeenB0 `set__insert` B,

	( map__member(FunctorsA, ConsId, ArgsA) ->
		( map__is_empty(FunctorsB) ->
			list__member(V0, ArgsA),
			corresponding_nodes_2(InstGraphA,
				InstGraphB, SeenA, SeenB, V0, B, V, W)
		;
			map__search(FunctorsB, ConsId, ArgsB),
			corresponding_members(ArgsA, ArgsB, V0, W0),
			corresponding_nodes_2(InstGraphA,
				InstGraphB, SeenA, SeenB, V0, W0, V, W)
		)
	;
		map__member(FunctorsB, _ConsId, ArgsB),
		list__member(W0, ArgsB),
		corresponding_nodes_2(InstGraphA, InstGraphB,
			SeenA, SeenB, A, W0, V, W)
	).

corresponding_nodes_from_lists(InstGraphA, InstGraphB, VarsA, VarsB, V, W) :-
	corresponding_members(VarsA, VarsB, A, B),
	corresponding_nodes(InstGraphA, InstGraphB, A, B, V, W).

corresponding_members([A | _], [B | _], A, B).
corresponding_members([_ | As], [_ | Bs], A, B) :-
	corresponding_members(As, Bs, A, B).

merge(InstGraph0, VarSet0, NewInstGraph, NewVarSet, InstGraph, VarSet, Sub) :-
	varset__merge_subst_without_names(VarSet0, NewVarSet, VarSet, Sub0),
	(
		map__map_values(
			pred(_::in, term__variable(V)::in, V::out) is semidet,
			Sub0, Sub1)
	->
		Sub = Sub1
	;
		error("merge: non-variable terms in substitution")
	),
	map__foldl((pred(Var0::in, Node0::in, IG0::in, IG::out) is det :-
		Node0 = node(Functors0, MaybeParent),
		map__map_values(
			(pred(_::in, Args0::in, Args::out) is det :-
				map__apply_to_list(Args0, Sub, Args)),
			Functors0, Functors),
		Node = node(Functors, MaybeParent),
		map__lookup(Sub, Var0, Var),
		map__det_insert(IG0, Var, Node, IG)
	), NewInstGraph, InstGraph0, InstGraph).

%-----------------------------------------------------------------------------%

% join(InstGraphA, VarSetA, InstGraphB, VarSetB,
% 		InstGraph, VarSet) :-
% 	solutions((pred(V::out) is nondet :-
% 			map__member(InstGraphB, V, node(_, top_level))
% 		), VarsB),
% 	list__foldl2(join_nodes(InstGraphB, VarSetB), VarsB, InstGraphA,
% 		InstGraph, VarSetA, VarSet).
% 
% :- pred join_nodes(inst_graph, prog_varset, prog_var, inst_graph, inst_graph,
% 		prog_varset, prog_varset).
% :- mode join_nodes(in, in, in, in, out, in, out) is det.
% 
% join_nodes(_, _, _, _, _, _, _) :- error("join_nodes: NYI").

%-----------------------------------------------------------------------------%

dump(InstGraph, VarSet, !IO) :-
	map__foldl(dump_node(VarSet), InstGraph, !IO).

:- pred dump_node(prog_varset::in, prog_var::in, node::in,
	io::di, io::uo) is det.

dump_node(VarSet, Var, Node, !IO) :-
	Node = node(Functors, MaybeParent),
	io__write_string("%% ", !IO),
	term_io__write_variable(Var, VarSet, !IO),
	io__write_string(": ", !IO),
	(
		MaybeParent = parent(Parent),
		term_io__write_variable(Parent, VarSet, !IO)
	;
		MaybeParent = top_level
	),
	io__nl(!IO),
	map__foldl(dump_functor(VarSet), Functors, !IO).

:- pred dump_functor(prog_varset::in, cons_id::in, list(prog_var)::in,
	io::di, io::uo) is det.

dump_functor(VarSet, ConsId, Args, !IO) :-
	io__write_string("%%\t", !IO),
	hlds_out__write_cons_id(ConsId, !IO),
	(
		Args = [_ | _],
		io__write_char('(', !IO),
		io__write_list(Args, ", ", dump_var(VarSet), !IO),
		io__write_char(')', !IO)
	;
		Args = []
	),
	io__nl(!IO).

:- pred dump_var(prog_varset::in, prog_var::in, io::di, io::uo) is det.

dump_var(VarSet, Var, !IO) :-
	term_io__write_variable(Var, VarSet, !IO).

%-----------------------------------------------------------------------------%

:- type inst_graph_info --->
	inst_graph_info(
		interface_inst_graph	:: inst_graph,
					% Inst graph derived from the mode
					% declarations, if there are any.
					% If there are no mode declarations
					% for the pred, this is the same as
					% the implementation_inst_graph.
		interface_vars		:: list(prog_var),
					% Vars that appear in the head of the
					% mode declaration constraint.
		interface_varset	:: prog_varset,
					% Varset used for interface_inst_graph.
		implementation_inst_graph :: inst_graph
					% Inst graph derived from the body of
					% the predicate.
	).

inst_graph_info_init = inst_graph_info(InstGraph, [], VarSet, InstGraph) :-
	varset__init(VarSet),
	map__init(InstGraph).

%-----------------------------------------------------------------------------%