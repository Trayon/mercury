%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
% File: declarative_execution.m
% Author: Mark Brown
%
% This module defines a Mercury representation of Mercury program
% execution, the annotated trace.  This structure is described in
% papers/decl_debug.  The declarative debugging infrastructure in the
% trace directory builds an annotated trace, using predicates exported
% from this module.  Once built, the structure is passed to the front
% end (in browser/declarative_debugger.m) where it is analysed
% to produce a bug diagnosis.

:- module mdb__declarative_execution.
:- interface.
:- import_module list, std_util, string, io, bool.
:- import_module mdb__util.

	% This type represents a port in the annotated trace.
	% The type R is the type of references to other nodes
	% in the store.
	%
	% If this type is modified, the procedures below which
	% do destructive update on values of this type may also
	% need to be modified.
	%
:- type trace_node(R)
	--->	call(
			R,			% Preceding event.
			R,			% Last EXIT or REDO event.
			trace_atom,		% Atom that was called.
			sequence_number,	% Call sequence number.
			event_number,		% Trace event number.
			bool			% At the maximum depth?
		)
	;	exit(
			R,			% Preceding event.
			R,			% CALL event.
			R,			% Previous REDO event, if any.
			trace_atom,		% Atom in its final state.
			event_number		% Trace event number.
		)
	;	redo(
			R,			% Preceding event.
			R			% EXIT event.
		)
	;	fail(
			R,			% Preceding event.
			R,			% CALL event.
			R,			% Previous REDO event, if any.
			event_number		% Trace event number.
		)
	;	excp(
			R, 			% Preceding event.
			R,			% Call event.
			R,			% Previous redo, if any.
			univ,			% Exception thrown.
			event_number		% Trace event number.
		)
	;	switch(
			R,			% Preceding event.
			goal_path		% Path for this event.
		)
	;	first_disj(
			R,			% Preceding event.
			goal_path		% Path for this event.
		)
	;	later_disj(
			R,			% Preceding event.
			goal_path,		% Path for this event.
			R			% Event of the first DISJ.
		)
	;	cond(
			R,			% Preceding event.
			goal_path,		% Path for this event.
			goal_status		% Whether we have reached
						% a THEN or ELSE event.
		)
	;	then(
			R,			% Preceding event.
			R			% COND event.
		)
	;	else(
			R,			% Preceding event.
			R			% COND event.
		)
	;	neg(
			R,			% Preceding event.
			goal_path,		% Path for this event.
			goal_status		% Whether we have reached
						% a NEGS or NEGF event.
		)
	;	neg_succ(
			R,			% Preceding event.
			R			% NEGE event.
		)
	;	neg_fail(
			R,			% Preceding event.
			R			% NEGE event.
		)
	.

:- type trace_atom
	--->	atom(
			pred_or_func,

				% Procedure name.
				%
			string,

				% Arguments.
				% XXX this representation will not be
				% able to handle partially instantiated
				% data structures.
				%
			list(maybe(univ))
		).

	% If the following type is modified, some of the macros in
	% trace/mercury_trace_declarative.h may need to be updated.
	%
:- type goal_status
	--->	succeeded
	;	failed
	;	undecided.

:- type goal_path == goal_path_string.

:- type sequence_number == int.
:- type event_number == int.

	% Members of this typeclass represent an entire annotated
	% trace.  The second parameter is the type of identifiers
	% for trace nodes, and the first parameter is the type of
	% an abstract mapping from identifiers to the nodes they
	% identify.
	%
:- typeclass annotated_trace(S, R) where [

		% Dereference the identifier.  This fails if the
		% identifier does not refer to any trace_node (ie.
		% it is a NULL pointer).
		%
	pred trace_node_from_id(S, R, trace_node(R)),
	mode trace_node_from_id(in, in, out) is semidet
].

	% Given any node in an annotated trace, find the most recent
	% node in the same contour (ie. the last node which has not been
	% backtracked over, skipping negations, failed conditions, the
	% bodies of calls, and alternative disjuncts).  Throw an exception
	% if there is no such node (ie. if we are at the start of a
	% negation, call, or failed condition).
	%
	% In some cases the contour may reach a dead end.  This can
	% happen if, for example, a DISJ node is not present because
	% it is beyond the depth bound or in a module that is not traced;
	% "stepping left" will arrive at a FAIL, REDO or NEGF node.  Since
	% it is not possible to follow the original contour in these
	% circumstances, we follow the previous contour instead.
	%
:- func step_left_in_contour(S, trace_node(R)) = R <= annotated_trace(S, R).

	% Given any node in an annotated trace, find the most recent
	% node in the same stratum (ie. the most recent node, skipping
	% negations, failed conditions, and the bodies of calls).
	% Throw an exception if there is no such node (ie. if we are at
	% the start of a negation, call, or failed negation).
	%
:- func step_in_stratum(S, trace_node(R)) = R <= annotated_trace(S, R).

	% The following procedures also dereference the identifiers,
	% but they give an error if the node is not of the expected type.
	%
:- pred det_trace_node_from_id(S, R, trace_node(R)) <= annotated_trace(S, R).
:- mode det_trace_node_from_id(in, in, out) is det.

:- inst trace_node_call =
		bound(call(ground, ground, ground, ground, ground, ground)).

:- pred call_node_from_id(S, R, trace_node(R)) <= annotated_trace(S, R).
:- mode call_node_from_id(in, in, out(trace_node_call)) is det.

:- inst trace_node_redo = bound(redo(ground, ground)).

	% maybe_redo_node_from_id/3 fails if the argument is a
	% NULL reference.
	% 
:- pred maybe_redo_node_from_id(S, R, trace_node(R)) <= annotated_trace(S, R).
:- mode maybe_redo_node_from_id(in, in, out(trace_node_redo)) is semidet.

:- inst trace_node_exit = bound(exit(ground, ground, ground, ground, ground)).

:- pred exit_node_from_id(S, R, trace_node(R)) <= annotated_trace(S, R).
:- mode exit_node_from_id(in, in, out(trace_node_exit)) is det.

:- inst trace_node_cond = bound(cond(ground, ground, ground)).

:- pred cond_node_from_id(S, R, trace_node(R)) <= annotated_trace(S, R).
:- mode cond_node_from_id(in, in, out(trace_node_cond)) is det.

:- inst trace_node_neg = bound(neg(ground, ground, ground)).

:- pred neg_node_from_id(S, R, trace_node(R)) <= annotated_trace(S, R).
:- mode neg_node_from_id(in, in, out(trace_node_neg)) is det.

:- inst trace_node_first_disj = bound(first_disj(ground, ground)).

:- pred first_disj_node_from_id(S, R, trace_node(R)) <= annotated_trace(S, R).
:- mode first_disj_node_from_id(in, in, out(trace_node_first_disj)) is det.

:- inst trace_node_disj = bound(first_disj(ground, ground);
				later_disj(ground, ground, ground)).

:- pred disj_node_from_id(S, R, trace_node(R)) <= annotated_trace(S, R).
:- mode disj_node_from_id(in, in, out(trace_node_disj)) is det.

	% Load an execution tree which was previously saved by
	% the back end.
	%
:- pred load_trace_node_map(io__input_stream, trace_node_map,
		trace_node_key, io__state, io__state).
:- mode load_trace_node_map(in, out, out, di, uo) is det.

	% Save an execution tree generated by the back end.  It is
	% first converted into a trace_node_map/trace_node_key pair.
	%
:- pred save_trace_node_store(io__output_stream, trace_node_store,
		trace_node_id, io__state, io__state).
:- mode save_trace_node_store(in, in, in, di, uo) is det.

%-----------------------------------------------------------------------------%

	% This instance is used when the declarative debugger is in
	% normal mode.  Values of this instance are produced by the
	% back end and passed directly to the front end.
	%
:- type trace_node_store.
:- type trace_node_id.
:- instance annotated_trace(trace_node_store, trace_node_id).

	% This instance is used when the declarative debugger is in
	% test mode.  Values of this instance are produced by copying
	% values of the previous instance.  Unlike the previous
	% instance, values of this one can be fed through a stream.
	% 
:- type trace_node_map.
:- type trace_node_key.
:- instance annotated_trace(trace_node_map, trace_node_key).

%-----------------------------------------------------------------------------%

:- implementation.
:- import_module map, require, store.

step_left_in_contour(Store, exit(_, Call, _, _, _)) = Prec :-
	call_node_from_id(Store, Call, call(Prec, _, _, _, _, _)).
step_left_in_contour(Store, excp(_, Call, _, _, _)) = Prec :-
	call_node_from_id(Store, Call, call(Prec, _, _, _, _, _)).
step_left_in_contour(_, switch(Prec, _)) = Prec.
step_left_in_contour(_, first_disj(Prec, _)) = Prec.
step_left_in_contour(Store, later_disj(_, _, FirstDisj)) = Prec :-
	first_disj_node_from_id(Store, FirstDisj, first_disj(Prec, _)).
step_left_in_contour(_, cond(Prec, _, Status)) = Node :-
	(
		Status = failed
	->
		error("step_left_in_contour: failed COND node")
	;
		Node = Prec
	).
step_left_in_contour(_, then(Prec, _)) = Prec.
step_left_in_contour(Store, else(_, Cond)) = Prec :-
	cond_node_from_id(Store, Cond, cond(Prec, _, _)).
step_left_in_contour(Store, neg_succ(_, Neg)) = Prec :-
	neg_node_from_id(Store, Neg, neg(Prec, _, _)).
	%
	% The following cases are possibly at the left end of a contour,
	% where we cannot step any further.
	%
step_left_in_contour(_, call(_, _, _, _, _, _)) = _ :-
	error("step_left_in_contour: unexpected CALL node").
step_left_in_contour(_, neg(Prec, _, Status)) = Next :-
	(
		Status = undecided
	->
			%
			% An exception must have been thrown inside the
			% negation, so we don't consider it a separate
			% context.
			%
		Next = Prec
	;
		error("step_left_in_contour: unexpected NEGE node")
	).
	%
	% In the remaining cases we have reached a dead end, so we
	% step to the previous contour instead.
	%
step_left_in_contour(Store, Node) = Prec :-
	Node = fail(_, _, _, _),
	find_prev_contour(Store, Node, Prec).
step_left_in_contour(Store, Node) = Prec :-
	Node = redo(_, _),
	find_prev_contour(Store, Node, Prec).
step_left_in_contour(Store, Node) = Prec :-
	Node = neg_fail(_, _),
	find_prev_contour(Store, Node, Prec).

	% Given any node which is not on a contour, find a node on
	% the previous contour in the same stratum.
	%
:- pred find_prev_contour(S, trace_node(R), R) <= annotated_trace(S, R).
:- mode find_prev_contour(in, in, out) is semidet.
:- mode find_prev_contour(in, in(trace_node_reverse), out) is det.

:- inst trace_node_reverse =
	bound(	fail(ground, ground, ground, ground)
	;	redo(ground, ground)
	;	neg_fail(ground, ground)).

find_prev_contour(Store, fail(_, Call, _, _), OnContour) :-
	call_node_from_id(Store, Call, call(OnContour, _, _, _, _, _)).
find_prev_contour(Store, redo(_, Exit), OnContour) :-
	exit_node_from_id(Store, Exit, exit(OnContour, _, _, _, _)).
find_prev_contour(Store, neg_fail(_, Neg), OnContour) :-
	neg_node_from_id(Store, Neg, neg(OnContour, _, _)).
	%
	% The following cases are at the left end of a contour,
	% so there are no previous contours in the same stratum.
	%
find_prev_contour(_, call(_, _, _, _, _, _), _) :-
	error("find_prev_contour: reached CALL node").
find_prev_contour(_, cond(_, _, _), _) :-
	error("find_prev_contour: reached COND node").
find_prev_contour(_, neg(_, _, _), _) :-
	error("find_prev_contour: reached NEGE node").

step_in_stratum(Store, exit(_, Call, MaybeRedo, _, _)) =
	step_over_redo_or_call(Store, Call, MaybeRedo).
step_in_stratum(Store, fail(_, Call, MaybeRedo, _)) =
	step_over_redo_or_call(Store, Call, MaybeRedo).
step_in_stratum(Store, excp(_, Call, MaybeRedo, _, _)) =
	step_over_redo_or_call(Store, Call, MaybeRedo).
step_in_stratum(Store, redo(_, Exit)) = Next :-
	exit_node_from_id(Store, Exit, exit(Next, _, _, _, _)).
step_in_stratum(_, switch(Next, _)) = Next.
step_in_stratum(_, first_disj(Next, _)) = Next.
step_in_stratum(_, later_disj(Next, _, _)) = Next.
step_in_stratum(_, cond(Prec, _, Status)) = Next :-
	(
		Status = failed
	->
		error("step_in_stratum: failed COND node")
	;
		Next = Prec
	).
step_in_stratum(_, then(Next, _)) = Next.
step_in_stratum(Store, else(_, Cond)) = Next :-
	cond_node_from_id(Store, Cond, cond(Next, _, _)).
step_in_stratum(Store, neg_succ(_, Neg)) = Next :-
	neg_node_from_id(Store, Neg, neg(Next, _, _)).
step_in_stratum(Store, neg_fail(_, Neg)) = Next :-
	neg_node_from_id(Store, Neg, neg(Next, _, _)).
	%
	% The following cases mark the boundary of the stratum,
	% so we cannot step any further.
	%
step_in_stratum(_, call(_, _, _, _, _, _)) = _ :-
	error("step_in_stratum: unexpected CALL node").
step_in_stratum(_, neg(_, _, _)) = _ :-
	error("step_in_stratum: unexpected NEGE node").

:- func step_over_redo_or_call(S, R, R) = R <= annotated_trace(S, R).

step_over_redo_or_call(Store, Call, MaybeRedo) = Next :-
	(
		maybe_redo_node_from_id(Store, MaybeRedo, Redo)
	->
		Redo = redo(Next, _)
	;
		call_node_from_id(Store, Call, call(Next, _, _, _, _, _))
	).

det_trace_node_from_id(Store, NodeId, Node) :-
	(
		trace_node_from_id(Store, NodeId, Node0)
	->
		Node = Node0
	;
		error("det_trace_node_from_id: NULL node id")
	).

call_node_from_id(Store, NodeId, Node) :-
	(
		trace_node_from_id(Store, NodeId, Node0),
		Node0 = call(_, _, _, _, _, _)
	->
		Node = Node0
	;
		error("call_node_from_id: not a CALL node")
	).

maybe_redo_node_from_id(Store, NodeId, Node) :-
	trace_node_from_id(Store, NodeId, Node0),
	(
		Node0 = redo(_, _)
	->
		Node = Node0
	;
		error("maybe_redo_node_from_id: not a REDO node or NULL")
	).

exit_node_from_id(Store, NodeId, Node) :-
	(
		trace_node_from_id(Store, NodeId, Node0),
		Node0 = exit(_, _, _, _, _)
	->
		Node = Node0
	;
		error("exit_node_from_id: not an EXIT node")
	).

cond_node_from_id(Store, NodeId, Node) :-
	(
		trace_node_from_id(Store, NodeId, Node0),
		Node0 = cond(_, _, _)
	->
		Node = Node0
	;
		error("cond_node_from_id: not a COND node")
	).

neg_node_from_id(Store, NodeId, Node) :-
	(
		trace_node_from_id(Store, NodeId, Node0),
		Node0 = neg(_, _, _)
	->
		Node = Node0
	;
		error("neg_node_from_id: not a NEG node")
	).

first_disj_node_from_id(Store, NodeId, Node) :-
	(
		trace_node_from_id(Store, NodeId, Node0),
		Node0 = first_disj(_, _)
	->
		Node = Node0
	;
		error("first_disj_node_from_id: not a first DISJ node")
	).

disj_node_from_id(Store, NodeId, Node) :-
	(
		trace_node_from_id(Store, NodeId, Node0),
		( Node0 = first_disj(_, _)
		; Node0 = later_disj(_, _, _)
		)
	->
		Node = Node0
	;
		error("disj_node_from_id: not a DISJ node")
	).

%-----------------------------------------------------------------------------%

:- instance annotated_trace(trace_node_store, trace_node_id) where [
	pred(trace_node_from_id/3) is search_trace_node_store
].

	% The "map" is actually just an integer representing the version
	% of the map.  The empty map should be given the value 0, and
	% each time the map is destructively modified (by C code), the
	% value should be incremented.
	%
:- type trace_node_store ---> store(int).

	% The implementation of the identifiers is the same as what
	% is identified.  This fact is hidden, however, to force the
	% abstract map to be explicitly used whenever a new node is
	% accessed.
	%
:- type trace_node_id ---> id(c_pointer).

:- pred search_trace_node_store(trace_node_store, trace_node_id,
		trace_node(trace_node_id)).
:- mode search_trace_node_store(in, in, out) is semidet.

:- pragma c_code(
	search_trace_node_store(_Store::in, Id::in, Node::out),
	[will_not_call_mercury, thread_safe],
	"
		Node = Id;
		SUCCESS_INDICATOR = (Id != (Word) NULL);
	"
).

	%
	% Following are some predicates that are useful for
	% manipulating the above instance in C code.
	%

:- func call_node_get_last_interface(trace_node(trace_node_id))
		= trace_node_id.
:- pragma export(call_node_get_last_interface(in) = out,
		"MR_DD_call_node_get_last_interface").

call_node_get_last_interface(Call) = Last :-
	(
		Call = call(_, Last0, _, _, _, _)
	->
		Last = Last0
	;
		error("call_node_get_last_interface: not a CALL node")
	).

:- func call_node_set_last_interface(trace_node(trace_node_id), trace_node_id)
		= trace_node(trace_node_id).
:- mode call_node_set_last_interface(di, di) = out is det.
:- pragma export(call_node_set_last_interface(di, di) = out,
		"MR_DD_call_node_set_last_interface").

call_node_set_last_interface(Call0, Last) = Call :-
	(
		Call0 = call(_, _, _, _, _, _)
	->
		Call1 = Call0
	;
		error("call_node_set_last_interface: not a CALL node")
	),
		% The last interface is the second field, so we pass 1
		% (since argument numbers start from 0).
		%
	set_trace_node_arg(Call1, 1, Last, Call).

:- func cond_node_set_status(trace_node(trace_node_id), goal_status)
		= trace_node(trace_node_id).
:- mode cond_node_set_status(di, di) = out is det.
:- pragma export(cond_node_set_status(di, di) = out,
		"MR_DD_cond_node_set_status").

cond_node_set_status(Cond0, Status) = Cond :-
	(
		Cond0 = cond(_, _, _)
	->
		Cond1 = Cond0
	;
		error("cond_node_set_status: not a COND node")
	),
		% The goal status is the third field, so we pass 2
		% (since argument numbers start from 0).
		%
	set_trace_node_arg(Cond1, 2, Status, Cond).

:- func neg_node_set_status(trace_node(trace_node_id), goal_status)
		= trace_node(trace_node_id).
:- mode neg_node_set_status(di, di) = out is det.
:- pragma export(neg_node_set_status(di, di) = out,
		"MR_DD_neg_node_set_status").

neg_node_set_status(Neg0, Status) = Neg :-
	(
		Neg0 = neg(_, _, _)
	->
		Neg1 = Neg0
	;
		error("neg_node_set_status: not a NEGE node")
	),
		% The goal status is the third field, so we pass 2
		% (since argument numbers start from 0).
		%
	set_trace_node_arg(Neg1, 2, Status, Neg).

:- pred set_trace_node_arg(trace_node(trace_node_id), int, T,
		trace_node(trace_node_id)).
:- mode set_trace_node_arg(di, in, di, out) is det.

set_trace_node_arg(Node0, FieldNum, Val, Node) :-
	store__new(S0),
	store__new_ref(Node0, Ref, S0, S1),
	store__arg_ref(Ref, FieldNum, ArgRef, S1, S2),
	store__set_ref_value(ArgRef, Val, S2, S),
	store__extract_ref_value(S, Ref, Node).

:- func trace_node_port(trace_node(trace_node_id)) = trace_port_type.
:- pragma export(trace_node_port(in) = out,
		"MR_DD_trace_node_port").

trace_node_port(call(_, _, _, _, _, _))	= call.
trace_node_port(exit(_, _, _, _, _))	= exit.
trace_node_port(redo(_, _))		= redo.
trace_node_port(fail(_, _, _, _))	= fail.
trace_node_port(excp(_, _, _, _, _))	= exception.
trace_node_port(switch(_, _))		= switch.
trace_node_port(first_disj(_, _))	= disj.
trace_node_port(later_disj(_, _, _))	= disj.
trace_node_port(cond(_, _, _))		= ite_cond.
trace_node_port(then(_, _))		= ite_then.
trace_node_port(else(_, _))		= ite_else.
trace_node_port(neg(_, _, _))		= neg_enter.
trace_node_port(neg_succ(_, _))		= neg_success.
trace_node_port(neg_fail(_, _))		= neg_failure.

:- func trace_node_path(trace_node_store, trace_node(trace_node_id))
		= goal_path_string.
:- pragma export(trace_node_path(in, in) = out,
		"MR_DD_trace_node_path").

trace_node_path(_, call(_, _, _, _, _, _)) = "".
trace_node_path(_, exit(_, _, _, _, _)) = "".
trace_node_path(_, redo(_, _)) = "".
trace_node_path(_, fail(_, _, _, _)) = "".
trace_node_path(_, excp(_, _, _, _, _)) = "".
trace_node_path(_, switch(_, P)) = P.
trace_node_path(_, first_disj(_, P)) = P.
trace_node_path(_, later_disj(_, P, _)) = P.
trace_node_path(_, cond(_, P, _)) = P.
trace_node_path(S, then(_, Cond)) = P :-
	cond_node_from_id(S, Cond, cond(_, P, _)).
trace_node_path(S, else(_, Cond)) = P :-
	cond_node_from_id(S, Cond, cond(_, P, _)).
trace_node_path(_, neg(_, P, _)) = P.
trace_node_path(S, neg_succ(_, Neg)) = P :-
	neg_node_from_id(S, Neg, neg(_, P, _)).
trace_node_path(S, neg_fail(_, Neg)) = P :-
	neg_node_from_id(S, Neg, neg(_, P, _)).

:- pred trace_node_seqno(trace_node_store, trace_node(trace_node_id),
		sequence_number).
:- mode trace_node_seqno(in, in, out) is semidet.

:- pragma export(trace_node_seqno(in, in, out), "MR_DD_trace_node_seqno").

trace_node_seqno(S, Node, SeqNo) :-
	(
		Node = call(_, _, _, SeqNo0, _, _)
	->
		SeqNo = SeqNo0
	;
		trace_node_call(S, Node, Call),
		call_node_from_id(S, Call, call(_, _, _, SeqNo, _, _))
	).

:- pred trace_node_call(trace_node_store, trace_node(trace_node_id),
		trace_node_id).
:- mode trace_node_call(in, in, out) is semidet.

:- pragma export(trace_node_call(in, in, out), "MR_DD_trace_node_call").

trace_node_call(_, exit(_, Call, _, _, _), Call).
trace_node_call(S, redo(_, Exit), Call) :-
	exit_node_from_id(S, Exit, exit(_, Call, _, _, _)).
trace_node_call(_, fail(_, Call, _, _), Call).
trace_node_call(_, excp(_, Call, _, _, _), Call).

:- pred trace_node_first_disj(trace_node(trace_node_id), trace_node_id).
:- mode trace_node_first_disj(in, out) is semidet.

:- pragma export(trace_node_first_disj(in, out),
		"MR_DD_trace_node_first_disj").

trace_node_first_disj(first_disj(_, _), NULL) :-
	null_trace_node_id(NULL).
trace_node_first_disj(later_disj(_, _, FirstDisj), FirstDisj).	

	% Export a version of this function to be called by C code
	% in trace/declarative_debugger.c.
	%
:- func step_left_in_contour_store(trace_node_store, trace_node(trace_node_id))
		= trace_node_id.
:- pragma export(step_left_in_contour_store(in, in) = out,
		"MR_DD_step_left_in_contour").

step_left_in_contour_store(Store, Node) = step_left_in_contour(Store, Node).

	% Export a version of this function to be called by C code
	% in trace/declarative_debugger.c.  If called with a node
	% that is already on a contour, this function returns the
	% same node.  This saves the C code from having to perform
	% that check itself.
	%
:- func find_prev_contour_store(trace_node_store, trace_node_id)
		= trace_node_id.
:- pragma export(find_prev_contour_store(in, in) = out,
		"MR_DD_find_prev_contour").

find_prev_contour_store(Store, Id) = Prev :-
	det_trace_node_from_id(Store, Id, Node),
	(
		find_prev_contour(Store, Node, Prev0)
	->
		Prev = Prev0
	;
		Prev = Id
	).

	% Print a text representation of a trace node, useful
	% for debugging purposes.
	%
:- pred print_trace_node(io__output_stream, trace_node(trace_node_id),
		io__state, io__state).
:- mode print_trace_node(in, in, di, uo) is det.
:- pragma export(print_trace_node(in, in, di, uo), "MR_DD_print_trace_node").

print_trace_node(OutStr, Node) -->
	{ convert_node(Node, CNode) },
	io__write(OutStr, CNode).

%-----------------------------------------------------------------------------%

	%
	% Each node type has a Mercury function which constructs
	% a node of that type.  The functions are exported to C so
	% that the back end can build an execution tree.
	%

:- func construct_call_node(trace_node_id, trace_atom, sequence_number,
		event_number, bool) = trace_node(trace_node_id).
:- pragma export(construct_call_node(in, in, in, in, in) = out,
		"MR_DD_construct_call_node").

construct_call_node(Preceding, Atom, SeqNo, EventNo, MaxDepth) = Call :-
	Call = call(Preceding, Answer, Atom, SeqNo, EventNo, MaxDepth),
	null_trace_node_id(Answer).


:- func construct_exit_node(trace_node_id, trace_node_id, trace_node_id,
		trace_atom, event_number) = trace_node(trace_node_id).
:- pragma export(construct_exit_node(in, in, in, in, in) = out,
		"MR_DD_construct_exit_node").

construct_exit_node(Preceding, Call, MaybeRedo, Atom, EventNo)
		= exit(Preceding, Call, MaybeRedo, Atom, EventNo).


:- func construct_redo_node(trace_node_id, trace_node_id)
		= trace_node(trace_node_id).
:- pragma export(construct_redo_node(in, in) = out,
		"MR_DD_construct_redo_node").

construct_redo_node(Preceding, Exit) = redo(Preceding, Exit).


:- func construct_fail_node(trace_node_id, trace_node_id, trace_node_id,
		event_number) = trace_node(trace_node_id).
:- pragma export(construct_fail_node(in, in, in, in) = out,
		"MR_DD_construct_fail_node").

construct_fail_node(Preceding, Call, Redo, EventNo) =
		fail(Preceding, Call, Redo, EventNo).


:- func construct_excp_node(trace_node_id, trace_node_id, trace_node_id,
		univ, event_number) = trace_node(trace_node_id).
:- pragma export(construct_excp_node(in, in, in, in, in) = out,
		"MR_DD_construct_excp_node").

construct_excp_node(Preceding, Call, MaybeRedo, Exception, EventNo) =
		excp(Preceding, Call, MaybeRedo, Exception, EventNo).


:- func construct_switch_node(trace_node_id, goal_path_string)
		= trace_node(trace_node_id).
:- pragma export(construct_switch_node(in, in) = out,
		"MR_DD_construct_switch_node").

construct_switch_node(Preceding, Path) =
		switch(Preceding, Path).

:- func construct_first_disj_node(trace_node_id, goal_path_string)
		= trace_node(trace_node_id).
:- pragma export(construct_first_disj_node(in, in) = out,
		"MR_DD_construct_first_disj_node").

construct_first_disj_node(Preceding, Path) =
		first_disj(Preceding, Path).


:- func construct_later_disj_node(trace_node_store, trace_node_id,
		goal_path_string, trace_node_id) = trace_node(trace_node_id).
:- pragma export(construct_later_disj_node(in, in, in, in) = out,
		"MR_DD_construct_later_disj_node").

construct_later_disj_node(Store, Preceding, Path, PrevDisj)
		= later_disj(Preceding, Path, FirstDisj) :-
	disj_node_from_id(Store, PrevDisj, PrevDisjNode),
	(
		PrevDisjNode = first_disj(_, _),
		FirstDisj = PrevDisj
	;
		PrevDisjNode = later_disj(_, _, FirstDisj)
	).


:- func construct_cond_node(trace_node_id, goal_path_string)
		= trace_node(trace_node_id).
:- pragma export(construct_cond_node(in, in) = out,
		"MR_DD_construct_cond_node").

construct_cond_node(Preceding, Path) = cond(Preceding, Path, undecided).


:- func construct_then_node(trace_node_id, trace_node_id)
		= trace_node(trace_node_id).
:- pragma export(construct_then_node(in, in) = out,
		"MR_DD_construct_then_node").

construct_then_node(Preceding, Cond) = then(Preceding, Cond).


:- func construct_else_node(trace_node_id, trace_node_id)
		= trace_node(trace_node_id).
:- pragma export(construct_else_node(in, in) = out,
		"MR_DD_construct_else_node").

construct_else_node(Preceding, Cond) = else(Preceding, Cond).


:- func construct_neg_node(trace_node_id, goal_path_string)
		= trace_node(trace_node_id).
:- pragma export(construct_neg_node(in, in) = out,
		"MR_DD_construct_neg_node").

construct_neg_node(Preceding, Path) = neg(Preceding, Path, undecided).


:- func construct_neg_succ_node(trace_node_id, trace_node_id)
		= trace_node(trace_node_id).
:- pragma export(construct_neg_succ_node(in, in) = out,
		"MR_DD_construct_neg_succ_node").

construct_neg_succ_node(Preceding, Neg) = neg_succ(Preceding, Neg).


:- func construct_neg_fail_node(trace_node_id, trace_node_id)
		= trace_node(trace_node_id).
:- pragma export(construct_neg_fail_node(in, in) = out,
		"MR_DD_construct_neg_fail_node").

construct_neg_fail_node(Preceding, Neg) = neg_fail(Preceding, Neg).


:- pred null_trace_node_id(trace_node_id).
:- mode null_trace_node_id(out) is det.

:- pragma c_code(
	null_trace_node_id(Id::out),
	[will_not_call_mercury, thread_safe],
	"Id = (Word) NULL;"
).


:- func construct_trace_atom(pred_or_func, string, int) = trace_atom.
:- pragma export(construct_trace_atom(in, in, in) = out,
		"MR_DD_construct_trace_atom").

construct_trace_atom(PredOrFunc, Functor, Arity) = Atom :-
	Atom = atom(PredOrFunc, Functor, Args),
	list__duplicate(Arity, no, Args).

:- func add_trace_atom_arg(trace_atom, int, univ) = trace_atom.
:- pragma export(add_trace_atom_arg(in, in, in) = out,
		"MR_DD_add_trace_atom_arg").

add_trace_atom_arg(atom(C, F, Args0), Num, Val) = atom(C, F, Args) :-
	list__replace_nth_det(Args0, Num, yes(Val), Args).

%-----------------------------------------------------------------------------%

	% The most important property of this instance is that it
	% can be written to or read in from a stream easily.  It
	% is not as efficient to use as the earlier instance, though.
	%
:- instance annotated_trace(trace_node_map, trace_node_key) where [
	pred(trace_node_from_id/3) is search_trace_node_map
].

:- type trace_node_map
	--->	map(map(trace_node_key, trace_node(trace_node_key))).

	% Values of this type are represented in the same way (in the
	% underlying C code) as corresponding values of the other
	% instance.
	%
:- type trace_node_key
	--->	key(int).

:- pred search_trace_node_map(trace_node_map, trace_node_key,
		trace_node(trace_node_key)).
:- mode search_trace_node_map(in, in, out) is semidet.

search_trace_node_map(map(Map), Key, Node) :-
	map__search(Map, Key, Node).

load_trace_node_map(Stream, Map, Key) -->
	io__read(Stream, ResKey),
	{
		ResKey = ok(Key)
	;
		ResKey = eof,
		error("load_trace_node_map: unexpected EOF")
	;
		ResKey = error(Msg, _),
		error(Msg)
	},
	io__read(Stream, ResMap),
	{
		ResMap = ok(Map)
	;
		ResMap = eof,
		error("load_trace_node_map: unexpected EOF")
	;
		ResMap = error(Msg, _),
		error(Msg)
	}.

:- pragma export(save_trace_node_store(in, in, in, di, uo),
		"MR_DD_save_trace").

save_trace_node_store(Stream, Store, NodeId) -->
	{ map__init(Map0) },
	{ node_id_to_key(NodeId, Key) },
	{ node_map(Store, NodeId, map(Map0), Map) },
	io__write(Stream, Key),
	io__write_string(Stream, ".\n"),
	io__write(Stream, Map),
	io__write_string(Stream, ".\n").

:- pred node_map(trace_node_store, trace_node_id, trace_node_map,
		trace_node_map).
:- mode node_map(in, in, in, out) is det.

node_map(Store, NodeId, map(Map0), Map) :-
	(
		search_trace_node_store(Store, NodeId, Node1)
	->
		node_id_to_key(NodeId, Key),
		convert_node(Node1, Node2),
		map__det_insert(Map0, Key, Node2, Map1),
		Next = preceding_node(Node1),
		node_map(Store, Next, map(Map1), Map)
	;
		Map = map(Map0)
	).

:- pred node_id_to_key(trace_node_id, trace_node_key).
:- mode node_id_to_key(in, out) is det.

:- pragma c_code(node_id_to_key(Id::in, Key::out),
		[will_not_call_mercury, thread_safe],
		"Key = (Integer) Id;").

:- pred convert_node(trace_node(trace_node_id), trace_node(trace_node_key)).
:- mode convert_node(in, out) is det.

:- pragma c_code(convert_node(N1::in, N2::out),
		[will_not_call_mercury, thread_safe],
		"N2 = N1;").

	% Given a node in an annotated trace, return a reference to
	% the preceding node in the trace, or a NULL reference if
	% it is the first.
	%
:- func preceding_node(trace_node(T)) = T.

preceding_node(call(P, _, _, _, _, _))	= P.
preceding_node(exit(P, _, _, _, _))	= P.
preceding_node(redo(P, _))		= P.
preceding_node(fail(P, _, _, _))	= P.
preceding_node(excp(P, _, _, _, _))	= P.
preceding_node(switch(P, _))		= P.
preceding_node(first_disj(P, _))	= P.
preceding_node(later_disj(P, _, _))	= P.
preceding_node(cond(P, _, _))		= P.
preceding_node(then(P, _))		= P.
preceding_node(else(P, _))		= P.
preceding_node(neg(P, _, _))		= P.
preceding_node(neg_succ(P, _))		= P.
preceding_node(neg_fail(P, _))		= P.

