%-----------------------------------------------------------------------------%
% Copyright (C) 2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Authors: conway, zs.
%
% This module contains the code for finding the cliques in the call graph
% described by an initial_deep structure. They are returned as a list of
% cliques, in bottom-up order.

:- module callgraph.

:- interface.

:- import_module profile.
:- import_module array, list.

:- pred find_cliques(initial_deep::in, list(list(proc_dynamic_ptr))::out)
	is det.

:- pred make_clique_indexes(int::in, list(list(proc_dynamic_ptr))::in,
	array(list(proc_dynamic_ptr))::array_uo, array(clique_ptr)::array_uo)
	is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module profile, cliques, array_util.
:- import_module int, set.

find_cliques(InitDeep, BottomUpPDPtrCliqueList) :-
	make_graph(InitDeep, Graph),
	topological_sort(Graph, TopDownPDICliqueList),
		% Turn each of the sets of PDIs into a list of PDPtrs.
		% We use foldl here because the list may be very long
		% and map runs out of stack space, and we want the final list
		% in reverse order anyway because the propagation algorithm
		% works bottom up.
	list__foldl(accumulate_pdptr_lists, TopDownPDICliqueList,
		[], BottomUpPDPtrCliqueList).

:- pred accumulate_pdptr_lists(set(int)::in, list(list(proc_dynamic_ptr))::in,
	list(list(proc_dynamic_ptr))::out) is det.

accumulate_pdptr_lists(PDISet, PDPtrLists0, PDPtrLists) :-
	pdi_set_to_pdptr_list(PDISet, PDPtrList),
	PDPtrLists = [PDPtrList | PDPtrLists0].

:- pred pdi_set_to_pdptr_list(set(int)::in, list(proc_dynamic_ptr)::out)
	is det.

pdi_set_to_pdptr_list(PDISet, PDPtrList) :-
	set__to_sorted_list(PDISet, PDIList),
	list__map(pdi_to_pdptr, PDIList, PDPtrList).

:- pred pdi_to_pdptr(int::in, proc_dynamic_ptr::out) is det.

pdi_to_pdptr(PDI, proc_dynamic_ptr(PDI)).

%-----------------------------------------------------------------------------%

:- pred make_graph(initial_deep::in, graph::out) is det.

make_graph(InitDeep, Graph) :-
	init(Graph0),
	array_foldl_from_1(add_pd_arcs(InitDeep), 
		InitDeep ^ init_proc_dynamics, Graph0, Graph).

:- pred add_pd_arcs(initial_deep::in, int::in, proc_dynamic::in,
	graph::in, graph::out) is det.

add_pd_arcs(InitDeep, PDI, PD, Graph0, Graph) :-
	CallSiteRefArray = PD ^ pd_sites,
	array__to_list(CallSiteRefArray, CallSiteRefList),
	list__foldl(add_call_site_arcs(InitDeep, PDI), 
		CallSiteRefList, Graph0, Graph).

:- pred add_call_site_arcs(initial_deep::in, int::in, call_site_array_slot::in,
	graph::in, graph::out) is det.

add_call_site_arcs(InitDeep, FromPDI, CallSiteSlot, Graph0, Graph) :-
	(
		CallSiteSlot = normal(CSDPtr),
		add_csd_arcs(InitDeep, FromPDI, CSDPtr, Graph0, Graph)
	;
		CallSiteSlot = multi(_, CSDPtrArray),
		array__to_list(CSDPtrArray, CSDPtrs),
		list__foldl(add_csd_arcs(InitDeep, FromPDI), CSDPtrs,
			Graph0, Graph)
	).

:- pred add_csd_arcs(initial_deep::in, int::in, call_site_dynamic_ptr::in,
	graph::in, graph::out) is det.

add_csd_arcs(InitDeep, FromPDI, CSDPtr, Graph0, Graph) :-
	CSDPtr = call_site_dynamic_ptr(CSDI),
	( CSDI > 0 ->
		array__lookup(InitDeep ^ init_call_site_dynamics, CSDI, CSD),
		ToPDPtr = CSD ^ csd_callee,
		ToPDPtr = proc_dynamic_ptr(ToPDI),
		add_arc(Graph0, FromPDI, ToPDI, Graph)
	;
		Graph = Graph0
	).

%-----------------------------------------------------------------------------%

make_clique_indexes(NPDs, CliqueList, Cliques, CliqueIndex) :-
	Cliques = array(CliqueList),
	array__init(NPDs, clique_ptr(-1), CliqueIndex0),
		% For each clique, add entries to the CliqueIndex array,
		% which maps every proc_dynamic_ptr back to the clique
		% to which it belongs.
	array_foldl_from_1(index_clique, Cliques, CliqueIndex0, CliqueIndex).

:- pred index_clique(int::in, list(proc_dynamic_ptr)::in,
	array(clique_ptr)::array_di, array(clique_ptr)::array_uo) is det.

index_clique(CliqueNum, CliqueMembers, CliqueIndex0, CliqueIndex) :-
	array_list_foldl(index_clique_member(CliqueNum),
		CliqueMembers, CliqueIndex0, CliqueIndex).

:- pred index_clique_member(int::in, proc_dynamic_ptr::in,
	array(clique_ptr)::array_di, array(clique_ptr)::array_uo) is det.

index_clique_member(CliqueNum, PDPtr, CliqueIndex0, CliqueIndex) :-
	PDPtr = proc_dynamic_ptr(PDI),
	array__set(CliqueIndex0, PDI, clique_ptr(CliqueNum), CliqueIndex).
