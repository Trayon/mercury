%-----------------------------------------------------------------------------%
% Copyright (C) 2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

:- module deep:startup.

:- interface.

:- pred startup(initial_deep::in, deep::out, io__state::di, io__state::uo)
	is det.

:- implementation.

:- import_module deep:util.

%-----------------------------------------------------------------------------%

startup(InitialDeep, Deep) -->
	stderr_stream(StdErr),

	{ InitialDeep = initial_deep(InitStats, Root,
		CallSiteDynamics0, ProcDynamics,
		CallSiteStatics0, ProcStatics) },

	format(StdErr,
		"  Mapping static call sites to containing procedures...\n",
		[]),
	{ array_foldl(record_css_containers, ProcStatics,
		u(CallSiteStatics0), CallSiteStatics) },
	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr,
		"  Mapping dynamic call sites to containing procedures...\n",
		[]),
	{ array_foldl(record_csd_containers, ProcDynamics,
		u(CallSiteDynamics0), CallSiteDynamics) },
	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr, "  Constructing graph...\n", []),
	make_graph(InitialDeep, Graph),
	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr, "  Constructing cliques...\n", []),
	{ atsort(Graph, CliqueList0) },

		% Turn each of the sets into a list.
		% (We use foldl here because the list may be very
		% long and map runs out of stack space, and we
		% want the final list in reverse order anyway.)
	{ list__foldl((pred(Set::in, L0::in, L::out) is det :-
		set__to_sorted_list(Set, List0),
		map((pred(PDI::in, PDPtr::out) is det :-
			PDPtr = proc_dynamic_ptr(PDI)
		), List0, List),
		L = [List | L0]
	), CliqueList0, [], CliqueList) },
		% It's actually more convenient to have the list in
		% reverse order so that foldl works from the bottom
		% of the tsort to the top, so that we can use it to
		% do the propagation simply.
	{ Cliques = array(CliqueList) },
	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr, "  Constructing clique indexes...\n", []),
	flush_output(StdErr),

	{ array__max(ProcDynamics, PDMax) },
	{ NPDs = PDMax + 1 },
	{ array__max(CallSiteDynamics, CSDMax) },
	{ NCSDs = CSDMax + 1 },
	{ array__max(ProcStatics, PSMax) },
	{ NPSs = PSMax + 1 },
	{ array__max(CallSiteStatics, CSSMax) },
	{ NCSSs = CSSMax + 1 },

	{ array__init(NPDs, clique_ptr(-1), CliqueIndex0) },

		% For each clique, add entries in an array
		% that maps from each clique member (ProcDynamic)
		% back to the clique to which it belongs.
	{ array_foldl((pred(CliqueN::in, CliqueMembers::in,
				I0::array_di, I::array_uo) is det :-
		array_list_foldl((pred(X::in, I1::array_di, I2::array_uo)
				is det :-
			X = proc_dynamic_ptr(Y),
			array__set(I1, Y, clique_ptr(CliqueN), I2)
		), CliqueMembers, I0, I)
	), Cliques, CliqueIndex0, CliqueIndex) },
	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr, "  Constructing clique parent map...\n", []),

		% For each CallSiteDynamic pointer, if it points to
		% a ProcDynamic which is in a different clique to
		% the one from which the CallSiteDynamic's parent
		% came, then this CallSiteDynamic is the entry to
		% the [lower] clique. We need to compute this information
		% so that we can print clique-based timing summaries in
		% the browser.
	{ array__max(Cliques, CliqueMax) },
	{ NCliques = CliqueMax + 1 },
	{ array__init(NCliques, call_site_dynamic_ptr(-1), CliqueParents0) },
	{ array__init(NCSDs, no, CliqueMaybeChildren0) },
	{ array_foldl2(construct_clique_parents(InitialDeep, CliqueIndex),
		CliqueIndex,
		CliqueParents0, CliqueParents,
		CliqueMaybeChildren0, CliqueMaybeChildren) },

	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr, "  Finding procedure callers...\n", []),
	{ array__init(NPSs, [], ProcCallers0) },
	{ array_foldl(construct_proc_callers(InitialDeep), CallSiteDynamics,
		ProcCallers0, ProcCallers) },
	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr, "  Constructing call site static map...\n", []),
	{ array__init(NCSDs, call_site_static_ptr(-1), CallSiteStaticMap0) },
	{ array_foldl(construct_call_site_caller(InitialDeep), ProcDynamics,
		CallSiteStaticMap0, CallSiteStaticMap) },
	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr, "  Finding call site calls...\n", []),
	{ array__init(NCSSs, map__init, CallSiteCalls0) },
	{ array_foldl(construct_call_site_calls(InitialDeep), ProcDynamics,
		CallSiteCalls0, CallSiteCalls) },
	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr, "  Propagating time up call graph...\n", []),

	{ array__init(NCSDs, zero_inherit_prof_info, CSDDesc0) },
	{ array__init(NPDs, zero_own_prof_info, PDOwn0) },
	{ array_foldl(sum_call_sites_in_proc_dynamic,
		CallSiteDynamics, PDOwn0, PDOwn) },
	{ array__init(NPDs, zero_inherit_prof_info, PDDesc0) },
	{ array__init(NPSs, zero_own_prof_info, PSOwn0) },
	{ array__init(NPSs, zero_inherit_prof_info, PSDesc0) },
	{ array__init(NCSSs, zero_own_prof_info, CSSOwn0) },
	{ array__init(NCSSs, zero_inherit_prof_info, CSSDesc0) },

	{ Deep0 = deep(InitStats, Root,
		CallSiteDynamics, ProcDynamics, CallSiteStatics, ProcStatics,
		CliqueIndex, Cliques, CliqueParents, CliqueMaybeChildren,
		ProcCallers, CallSiteStaticMap, CallSiteCalls,
		PDOwn, PDDesc0, CSDDesc0,
		PSOwn0, PSDesc0, CSSOwn0, CSSDesc0) },

	{ array_foldl(propagate_to_clique, Cliques, Deep0, Deep1) },
	format(StdErr, "  Done.\n", []),
	io__report_stats,

	format(StdErr, "  Summarizing information...\n", []),
	{ summarize_proc_dynamics(Deep1, Deep2) },
	{ summarize_call_site_dynamics(Deep2, Deep) },
	format(StdErr, "  Done.\n", []),
	io__report_stats.

%-----------------------------------------------------------------------------%

:- pred make_graph(initial_deep::in, graph::out,
	io__state::di, io__state::uo) is det.

make_graph(InitialDeep, Graph) -->
	{ init(Graph0) },
	array_foldl2((pred(PDI::in, PD::in, G1::in, G2::out, di, uo) is det -->
		{ From = PDI },
	        { PD = proc_dynamic(_ProcStatic, CallSiteRefArray) },
	        { array__to_list(CallSiteRefArray, CallSiteRefList) },
	        list__foldl2((pred(CSR::in, G5::in, G6::out, di, uo) is det -->
		    (
			{ CSR = normal(call_site_dynamic_ptr(CSDI)) },
			( { CSDI > 0 } ->
				{ array__lookup(
					InitialDeep ^ init_call_site_dynamics,
					CSDI, CSD) },
				{ CSD = call_site_dynamic(_, CPDPtr, _) },
				{ CPDPtr = proc_dynamic_ptr(To) },
				{ add_arc(G5, From, To, G6) }
			;
				{ G6 = G5 }
			)
		    ;
			{ CSR = multi(CallSiteArray) },
			{ array__to_list(CallSiteArray, CallSites) },
			list__foldl2((pred(CSDPtr1::in, G7::in, G8::out,
					di, uo) is det -->
			    { CSDPtr1 = call_site_dynamic_ptr(CSDI) },
			    ( { CSDI > 0 } ->
			    	{ array__lookup(
					InitialDeep ^ init_call_site_dynamics,
					CSDI, CSD) },
			       	{ CSD = call_site_dynamic(_, CPDPtr, _) },
			    	{ CPDPtr = proc_dynamic_ptr(To) },
			    	{ add_arc(G7, From, To, G8) }
			    ;
			    	{ G8 = G7 }
			    )
			), CallSites, G5, G6)
		    )
	        ), CallSiteRefList, G1, G2)
	), InitialDeep ^ init_proc_dynamics, Graph0, Graph).

%-----------------------------------------------------------------------------%

:- pred record_css_containers(int::in, proc_static::in,
	array(call_site_static)::array_di,
	array(call_site_static)::array_uo) is det.

record_css_containers(PSI, PS, CallSiteStatics0, CallSiteStatics) :-
	PS = proc_static(_, _, _, _, CSSPtrs),
	PSPtr = proc_static_ptr(PSI),
	array__max(CSSPtrs, MaxCS),
	record_css_containers_2(MaxCS, PSPtr, CSSPtrs,
		CallSiteStatics0, CallSiteStatics).

:- pred record_css_containers_2(int::in, proc_static_ptr::in,
	array(call_site_static_ptr)::in,
	array(call_site_static)::array_di,
	array(call_site_static)::array_uo) is det.

record_css_containers_2(SlotNum, PSPtr, CSSPtrs,
		CallSiteStatics0, CallSiteStatics) :-
	( SlotNum >= 0 ->
		array__lookup(CSSPtrs, SlotNum, CSSPtr),
		lookup_call_site_statics(CallSiteStatics0, CSSPtr, CSS0),
		CSS0 = call_site_static(PSPtr0, SlotNum0,
			Kind, LineNumber, GoalPath),
		require(unify(PSPtr0, proc_static_ptr(-1)),
			"record_css_containers_2: real proc_static_ptr"),
		require(unify(SlotNum0, -1),
			"record_css_containers_2: real slot_num"),
		CSS = call_site_static(PSPtr, SlotNum,
			Kind, LineNumber, GoalPath),
		update_call_site_statics(CallSiteStatics0, CSSPtr, CSS,
			CallSiteStatics1),
		record_css_containers_2(SlotNum - 1,
			PSPtr, CSSPtrs, CallSiteStatics1, CallSiteStatics)
	;
		CallSiteStatics = CallSiteStatics0
	).

%-----------------------------------------------------------------------------%

:- pred record_csd_containers(int::in, proc_dynamic::in,
	array(call_site_dynamic)::array_di,
	array(call_site_dynamic)::array_uo) is det.

record_csd_containers(PDI, PD, CallSiteDynamics0, CallSiteDynamics) :-
	PD = proc_dynamic(_, CSDArray),
	PDPtr = proc_dynamic_ptr(PDI),
	flatten_call_sites(CSDArray, CSDPtrs),
	record_csd_containers_2(PDPtr, CSDPtrs,
		CallSiteDynamics0, CallSiteDynamics).

:- pred record_csd_containers_2(proc_dynamic_ptr::in,
	list(call_site_dynamic_ptr)::in,
	array(call_site_dynamic)::array_di,
	array(call_site_dynamic)::array_uo) is det.

record_csd_containers_2(_, [], CallSiteDynamics, CallSiteDynamics).
record_csd_containers_2(PDPtr, [CSDPtr | CSDPtrs],
		CallSiteDynamics0, CallSiteDynamics) :-
	lookup_call_site_dynamics(CallSiteDynamics0, CSDPtr, CSD0),
	CSD0 = call_site_dynamic(CallerPSPtr0, CalleePSPtr, Own),
	require(unify(CallerPSPtr0, proc_dynamic_ptr(-1)),
		"record_csd_containers_2: real proc_dynamic_ptr"),
	CSD = call_site_dynamic(PDPtr, CalleePSPtr, Own),
	update_call_site_dynamics(CallSiteDynamics0, CSDPtr, CSD,
		CallSiteDynamics1),
	record_csd_containers_2(PDPtr, CSDPtrs,
		CallSiteDynamics1, CallSiteDynamics).

%-----------------------------------------------------------------------------%

:- pred construct_clique_parents(initial_deep::in, array(clique_ptr)::in,
	int::in, clique_ptr::in,
	array(call_site_dynamic_ptr)::array_di,
	array(call_site_dynamic_ptr)::array_uo,
	array(maybe(clique_ptr))::array_di,
	array(maybe(clique_ptr))::array_uo) is det.

construct_clique_parents(InitialDeep, CliqueIndex, PDI, CliquePtr,
		CliqueParents0, CliqueParents,
		CliqueMaybeChildren0, CliqueMaybeChildren) :-
	( PDI > 0 ->
		flat_call_sites(InitialDeep ^ init_proc_dynamics,
			proc_dynamic_ptr(PDI), CSDPtrs),
		array_list_foldl2(
			construct_clique_parents_2(InitialDeep,
				CliqueIndex, CliquePtr),
			CSDPtrs, CliqueParents0, CliqueParents,
			CliqueMaybeChildren0, CliqueMaybeChildren)
	;
		error("emit nasal daemons")
	).

:- pred construct_clique_parents_2(initial_deep::in, array(clique_ptr)::in,
	clique_ptr::in, call_site_dynamic_ptr::in,
	array(call_site_dynamic_ptr)::array_di,
	array(call_site_dynamic_ptr)::array_uo,
	array(maybe(clique_ptr))::array_di,
	array(maybe(clique_ptr))::array_uo) is det.

construct_clique_parents_2(InitialDeep, CliqueIndex, ParentCliquePtr, CSDPtr,
		CliqueParents0, CliqueParents,
		CliqueMaybeChildren0, CliqueMaybeChildren) :-
	CSDPtr = call_site_dynamic_ptr(CSDI),
	( CSDI > 0 ->
		array__lookup(InitialDeep ^ init_call_site_dynamics, CSDI,
			CSD),
		CSD = call_site_dynamic(_, ChildPDPtr, _),
		ChildPDPtr = proc_dynamic_ptr(ChildPDI),
		( ChildPDI > 0 ->
			array__lookup(CliqueIndex, ChildPDI, ChildCliquePtr),
			( ChildCliquePtr \= ParentCliquePtr ->
				ChildCliquePtr = clique_ptr(ChildCliqueNum),
				array__set(CliqueParents0, ChildCliqueNum,
					CSDPtr, CliqueParents),
				array__set(CliqueMaybeChildren0, CSDI,
					yes(ChildCliquePtr),
					CliqueMaybeChildren)
			;
				CliqueParents = CliqueParents0,
				CliqueMaybeChildren = CliqueMaybeChildren0
			)
		;
			CliqueParents = CliqueParents0,
			CliqueMaybeChildren = CliqueMaybeChildren0
		)
	;
		CliqueParents = CliqueParents0,
		CliqueMaybeChildren = CliqueMaybeChildren0
	).

:- pred construct_proc_callers(initial_deep::in, int::in,
	call_site_dynamic::in,
	array(list(call_site_dynamic_ptr))::array_di,
	array(list(call_site_dynamic_ptr))::array_uo) is det.

construct_proc_callers(InitialDeep, CSDI, CSD, ProcCallers0, ProcCallers) :-
	CSD = call_site_dynamic(_, PDPtr, _),
	PDPtr = proc_dynamic_ptr(PDI),
	( PDI > 0, array__in_bounds(InitialDeep ^ init_proc_dynamics, PDI) ->
		array__lookup(InitialDeep ^ init_proc_dynamics, PDI, PD),
		PD = proc_dynamic(PSPtr, _),
		PSPtr = proc_static_ptr(PSI),
		array__lookup(ProcCallers0, PSI, Callers0),
		Callers = [call_site_dynamic_ptr(CSDI) | Callers0],
		array__set(ProcCallers0, PSI, Callers, ProcCallers)
	;
		ProcCallers = ProcCallers0
	).

:- pred construct_call_site_caller(initial_deep::in, int::in, proc_dynamic::in,
	array(call_site_static_ptr)::array_di,
	array(call_site_static_ptr)::array_uo) is det.

construct_call_site_caller(InitialDeep, _PDI, PD,
		CallSiteStaticMap0, CallSiteStaticMap) :-
	PD = proc_dynamic(PSPtr, CSDArraySlots),
	PSPtr = proc_static_ptr(PSI),
	array__lookup(InitialDeep ^ init_proc_statics, PSI, PS),
	PS = proc_static(_, _, _, _, CSSPtrs),
	array__max(CSDArraySlots, MaxCS),
	construct_call_site_caller_2(MaxCS,
		InitialDeep ^ init_call_site_dynamics, CSSPtrs, CSDArraySlots,
		CallSiteStaticMap0, CallSiteStaticMap).

:- pred construct_call_site_caller_2(int::in, call_site_dynamics::in,
	array(call_site_static_ptr)::in,
	array(call_site_array_slot)::in,
	array(call_site_static_ptr)::array_di,
	array(call_site_static_ptr)::array_uo) is det.

construct_call_site_caller_2(SlotNum, Deep, CSSPtrs, CSDArraySlots,
		CallSiteStaticMap0, CallSiteStaticMap) :-
	( SlotNum >= 0 ->
		array__lookup(CSDArraySlots, SlotNum, CSDArraySlot),
		array__lookup(CSSPtrs, SlotNum, CSSPtr),
		(
			CSDArraySlot = normal(CSDPtr),
			construct_call_site_caller_3(Deep, CSSPtr, -1, CSDPtr,
				CallSiteStaticMap0, CallSiteStaticMap1)

		;
			CSDArraySlot = multi(CSDPtrs),
			array_foldl0(
				construct_call_site_caller_3(Deep, CSSPtr),
				CSDPtrs,
				CallSiteStaticMap0, CallSiteStaticMap1)
		),
		construct_call_site_caller_2(SlotNum - 1, Deep, CSSPtrs,
			CSDArraySlots, CallSiteStaticMap1, CallSiteStaticMap)
	;
		CallSiteStaticMap = CallSiteStaticMap0
	).

:- pred construct_call_site_caller_3(call_site_dynamics::in,
	call_site_static_ptr::in, int::in, call_site_dynamic_ptr::in,
	array(call_site_static_ptr)::array_di,
	array(call_site_static_ptr)::array_uo) is det.

construct_call_site_caller_3(CallSiteDynamics, CSSPtr, _Dummy, CSDPtr,
		CallSiteStaticMap0, CallSiteStaticMap) :-
	( valid_call_site_dynamic_ptr_raw(CallSiteDynamics, CSDPtr) ->
		update_call_site_static_map(CallSiteStaticMap0,
			CSDPtr, CSSPtr, CallSiteStaticMap)
	;
		CallSiteStaticMap = CallSiteStaticMap0
	).

:- pred construct_call_site_calls(initial_deep::in, int::in, proc_dynamic::in,
	array(map(proc_static_ptr, list(call_site_dynamic_ptr)))::array_di,
	array(map(proc_static_ptr, list(call_site_dynamic_ptr)))::array_uo)
	is det.

construct_call_site_calls(InitialDeep, _PDI, PD,
		CallSiteCalls0, CallSiteCalls) :-
	PD = proc_dynamic(PSPtr, CSDArraySlots),
	array__max(CSDArraySlots, MaxCS),
	PSPtr = proc_static_ptr(PSI),
	array__lookup(InitialDeep ^ init_proc_statics, PSI, PS),
	PS = proc_static(_, _, _, _, CSSPtrs),
	CallSiteDynamics = InitialDeep ^ init_call_site_dynamics,
	ProcDynamics = InitialDeep ^ init_proc_dynamics,
	construct_call_site_calls_2(CallSiteDynamics, ProcDynamics, MaxCS,
		CSSPtrs, CSDArraySlots, CallSiteCalls0, CallSiteCalls).

:- pred construct_call_site_calls_2(call_site_dynamics::in, proc_dynamics::in,
	int::in, array(call_site_static_ptr)::in,
	array(call_site_array_slot)::in,
	array(map(proc_static_ptr, list(call_site_dynamic_ptr)))::array_di,
	array(map(proc_static_ptr, list(call_site_dynamic_ptr)))::array_uo)
	is det.

construct_call_site_calls_2(CallSiteDynamics, ProcDynamics, SlotNum,
		CSSPtrs, CSDArraySlots, CallSiteCalls0, CallSiteCalls) :-
	( SlotNum >= 0 ->
		array__lookup(CSDArraySlots, SlotNum, CSDArraySlot),
		array__lookup(CSSPtrs, SlotNum, CSSPtr),
		(
			CSDArraySlot = normal(CSDPtr),
			construct_call_site_calls_3(CallSiteDynamics,
				ProcDynamics, CSSPtr, -1,
				CSDPtr, CallSiteCalls0, CallSiteCalls1)
		;
			CSDArraySlot = multi(CSDPtrs),
			array_foldl0(
				construct_call_site_calls_3(CallSiteDynamics,
					ProcDynamics, CSSPtr),
				CSDPtrs, CallSiteCalls0, CallSiteCalls1)
		),
		construct_call_site_calls_2(CallSiteDynamics, ProcDynamics,
			SlotNum - 1, CSSPtrs, CSDArraySlots,
			CallSiteCalls1, CallSiteCalls)
	;
		CallSiteCalls = CallSiteCalls0
	).

:- pred construct_call_site_calls_3(call_site_dynamics::in, proc_dynamics::in,
	call_site_static_ptr::in, int::in, call_site_dynamic_ptr::in,
	array(map(proc_static_ptr, list(call_site_dynamic_ptr)))::array_di,
	array(map(proc_static_ptr, list(call_site_dynamic_ptr)))::array_uo)
	is det.

construct_call_site_calls_3(CallSiteDynamics, ProcDynamics, CSSPtr,
		_Dummy, CSDPtr, CallSiteCalls0, CallSiteCalls) :-
	CSDPtr = call_site_dynamic_ptr(CSDI),
	( CSDI > 0 ->
		array__lookup(CallSiteDynamics, CSDI, CSD),
		CSD = call_site_dynamic(_, PDPtr, _),
		PDPtr = proc_dynamic_ptr(PDI),
		array__lookup(ProcDynamics, PDI, PD),
		PD = proc_dynamic(PSPtr, _),

		CSSPtr = call_site_static_ptr(CSSI),
		array__lookup(CallSiteCalls0, CSSI, CallMap0),
		( map__search(CallMap0, PSPtr, CallList0) ->
			CallList = [CSDPtr | CallList0],
			map__det_update(CallMap0, PSPtr, CallList, CallMap)
		;
			CallList = [CSDPtr],
			map__det_insert(CallMap0, PSPtr, CallList, CallMap)
		),
		array__set(CallSiteCalls0, CSSI, CallMap, CallSiteCalls)
	;
		CallSiteCalls = CallSiteCalls0
	).

:- pred sum_call_sites_in_proc_dynamic(int::in, call_site_dynamic::in,
	array(own_prof_info)::array_di, array(own_prof_info)::array_uo) is det.

sum_call_sites_in_proc_dynamic(_, CSD, PDO0, PDO) :-
	CSD = call_site_dynamic(_, PDPtr, PI),
	PDPtr = proc_dynamic_ptr(PDI),
	( PDI > 0 ->
		array__lookup(PDO0, PDI, OwnPI0),
		OwnPI = add_own_to_own(PI, OwnPI0),
		array__set(PDO0, PDI, OwnPI, PDO)
	;
		PDO = PDO0
	).

:- pred summarize_proc_dynamics(deep::in, deep::out) is det.

summarize_proc_dynamics(Deep0, Deep) :-
	PSOwn0 = Deep0 ^ ps_own,
	PSDesc0 = Deep0 ^ ps_desc,
	array_foldl2(summarize_proc_dynamic(Deep0 ^ pd_own, Deep0 ^ pd_desc),
		Deep0 ^ proc_dynamics,
		copy(PSOwn0), PSOwn, copy(PSDesc0), PSDesc),
	Deep = ((Deep0
		^ ps_own := PSOwn)
		^ ps_desc := PSDesc).

:- pred summarize_proc_dynamic(array(own_prof_info)::in,
	array(inherit_prof_info)::in, int::in, proc_dynamic::in,
	array(own_prof_info)::array_di, array(own_prof_info)::array_uo,
	array(inherit_prof_info)::array_di, array(inherit_prof_info)::array_uo)
	is det.

summarize_proc_dynamic(PDOwn, PDDesc, PDI, PD,
		PSOwn0, PSOwn, PSDesc0, PSDesc) :-
	PD = proc_dynamic(PSPtr, _),
	PSPtr = proc_static_ptr(PSI),
	( PSI > 0 ->
		array__lookup(PDOwn, PDI, PDOwnPI),
		array__lookup(PDDesc, PDI, PDDescPI),

		array__lookup(PSOwn0, PSI, PSOwnPI0),
		array__lookup(PSDesc0, PSI, PSDescPI0),

		add_own_to_own(PDOwnPI, PSOwnPI0) = PSOwnPI,
		add_inherit_to_inherit(PDDescPI, PSDescPI0) = PSDescPI,
		array__set(u(PSOwn0), PSI, PSOwnPI, PSOwn),
		array__set(u(PSDesc0), PSI, PSDescPI, PSDesc)
	;
		error("emit nasal devils")
	).

:- pred summarize_call_site_dynamics(deep::in, deep::out) is det.

summarize_call_site_dynamics(Deep0, Deep) :-
	CSSOwn0 = Deep0 ^ css_own,
	CSSDesc0 = Deep0 ^ css_desc,
	array_foldl2(summarize_call_site_dynamic(Deep0 ^ call_site_static_map,
		Deep0 ^ csd_desc),
		Deep0 ^ call_site_dynamics,
		copy(CSSOwn0), CSSOwn, copy(CSSDesc0), CSSDesc),
	Deep = ((Deep0
		^ css_own := CSSOwn)
		^ css_desc := CSSDesc).

:- pred summarize_call_site_dynamic(call_site_static_map::in,
	array(inherit_prof_info)::in, int::in, call_site_dynamic::in,
	array(own_prof_info)::array_di, array(own_prof_info)::array_uo,
	array(inherit_prof_info)::array_di, array(inherit_prof_info)::array_uo)
	is det.

summarize_call_site_dynamic(CallSiteStaticMap, CSDDescs, CSDI, CSD,
		CSSOwn0, CSSOwn, CSSDesc0, CSSDesc) :-
	CSDPtr = call_site_dynamic_ptr(CSDI),
	lookup_call_site_static_map(CallSiteStaticMap, CSDPtr, CSSPtr),
	CSSPtr = call_site_static_ptr(CSSI),
	( CSSI > 0 ->
		CSD = call_site_dynamic(_, _, CSDOwnPI),
		array__lookup(CSDDescs, CSDI, CSDDescPI),

		array__lookup(CSSOwn0, CSSI, CSSOwnPI0),
		array__lookup(CSSDesc0, CSSI, CSSDescPI0),

		add_own_to_own(CSDOwnPI, CSSOwnPI0)
			= CSSOwnPI,
		add_inherit_to_inherit(CSDDescPI, CSSDescPI0)
			= CSSDescPI,
		array__set(u(CSSOwn0), CSSI, CSSOwnPI, CSSOwn),
		array__set(u(CSSDesc0), CSSI, CSSDescPI, CSSDesc)
	;
		error("emit nasal gorgons")
	).

:- pred propagate_to_clique(int::in, list(proc_dynamic_ptr)::in,
	deep::in, deep::out) is det.

propagate_to_clique(CliqueNumber, Members, Deep0, Deep) :-
	array__lookup(Deep0 ^ clique_parents, CliqueNumber, ParentCSDPtr),
	list__foldl(propagate_to_proc_dynamic(CliqueNumber, ParentCSDPtr),
		Members, Deep0, Deep1),
	(
		valid_call_site_dynamic_ptr_raw(Deep1 ^ call_site_dynamics,
			ParentCSDPtr)
	->
		lookup_call_site_dynamics(Deep1 ^ call_site_dynamics,
			ParentCSDPtr, ParentCSD),
		ParentCSD = call_site_dynamic(_, _, ParentOwnPI),
		deep_lookup_csd_desc(Deep1, ParentCSDPtr, ParentDesc0),
		subtract_own_from_inherit(ParentOwnPI, ParentDesc0) =
			ParentDesc,
		deep_update_csd_desc(Deep1, ParentCSDPtr, ParentDesc, Deep)
	;
		Deep = Deep1
	).

:- pred propagate_to_proc_dynamic(int::in, call_site_dynamic_ptr::in,
	proc_dynamic_ptr::in, deep::in, deep::out) is det.

propagate_to_proc_dynamic(CliqueNumber, ParentCSDPtr, PDPtr,
		Deep0, Deep) :-
	flat_call_sites(Deep0 ^ proc_dynamics, PDPtr, CSDPtrs),
	list__foldl(propagate_to_call_site(CliqueNumber, PDPtr),
		CSDPtrs, Deep0, Deep1),
	(
		valid_call_site_dynamic_ptr_raw(Deep1 ^ call_site_dynamics,
			ParentCSDPtr)
	->
		deep_lookup_csd_desc(Deep1, ParentCSDPtr, ParentDesc0),
		deep_lookup_pd_desc(Deep1, PDPtr, DescPI),
		deep_lookup_pd_own(Deep1, PDPtr, OwnPI),
		add_own_to_inherit(OwnPI, ParentDesc0) = ParentDesc1,
		add_inherit_to_inherit(DescPI, ParentDesc1) = ParentDesc,
		deep_update_csd_desc(Deep1, ParentCSDPtr, ParentDesc, Deep)
	;
		Deep = Deep1
	).

:- pred propagate_to_call_site(int::in, proc_dynamic_ptr::in,
	call_site_dynamic_ptr::in, deep::in, deep::out) is det.

propagate_to_call_site(CliqueNumber, PDPtr, CSDPtr, Deep0, Deep) :-
	CSDPtr = call_site_dynamic_ptr(CSDI),
	( CSDI > 0 ->
		array__lookup(Deep0 ^ call_site_dynamics, CSDI, CSD),
		CSD = call_site_dynamic(_, CPDPtr, CPI),
		CPDPtr = proc_dynamic_ptr(CPDI),
		( CPDI > 0 ->
			array__lookup(Deep0 ^ clique_index, CPDI,
				clique_ptr(ChildCliqueNumber)),
			( ChildCliqueNumber \= CliqueNumber ->
				PDPtr = proc_dynamic_ptr(PDI),
				array__lookup(Deep0 ^ pd_desc, PDI, PDTotal0),
				array__lookup(Deep0 ^ csd_desc, CSDI, CDesc),
				add_own_to_inherit(CPI, PDTotal0) = PDTotal1,
				add_inherit_to_inherit(CDesc, PDTotal1)
					= PDTotal,
				array__set(u(Deep0 ^ pd_desc), PDI, PDTotal,
					PDDesc),
				Deep = Deep0 ^ pd_desc := PDDesc
			;
				Deep = Deep0
			)
		;
			Deep = Deep0
		)
	;
		Deep = Deep0
	).

%-----------------------------------------------------------------------------%
