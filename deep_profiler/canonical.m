%-----------------------------------------------------------------------------%
% Copyright (C) 2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Authors: conway, zs.
%
% This module contains code for recursively merging sets of ProcDynamic and
% CallSiteDynamic nodes.

:- module canonical.

:- interface.

:- import_module profile.

:- pred canonicalize_cliques(initial_deep::in, initial_deep::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module measurements, callgraph, array_util.
:- import_module unsafe, io.
:- import_module std_util, bool, int, array, list, map, set, require.

:- type merge_info
	--->	merge_info(
			merge_clique_members :: array(list(proc_dynamic_ptr)),
			merge_clique_index   :: array(clique_ptr)
		).

:- type redirect
	--->	redirect(
			csd_redirect	:: array(call_site_dynamic_ptr),
						% index: call_site_dynamic_ptr
			pd_redirect	:: array(proc_dynamic_ptr)
						% index: proc_dynamic_ptr
		).

canonicalize_cliques(InitDeep0, InitDeep) :-
	MaxCSDs = array__max(InitDeep0 ^ init_call_site_dynamics),
	MaxPDs = array__max(InitDeep0 ^ init_proc_dynamics),
	NumCSDs = MaxCSDs + 1,
	NumPDs = MaxPDs + 1,

	find_cliques(InitDeep0, CliqueList),
	make_clique_indexes(NumPDs, CliqueList, Cliques, CliqueIndex),
	MergeInfo = merge_info(Cliques, CliqueIndex),

	CSDRedirect0 = array__init(NumCSDs, call_site_dynamic_ptr(0)),
	PDRedirect0 = array__init(NumPDs, proc_dynamic_ptr(0)),
	Redirect0 = redirect(CSDRedirect0, PDRedirect0),
	merge_cliques(CliqueList, MergeInfo, InitDeep0, Redirect0,
		InitDeep1, Redirect1),
	compact_dynamics(InitDeep1, Redirect1, NumCSDs, NumPDs, InitDeep).

:- pred merge_cliques(list(list(proc_dynamic_ptr))::in,
	merge_info::in, initial_deep::in, redirect::in,
	initial_deep::out, redirect::out) is det.

merge_cliques([], _, InitDeep, Redirect, InitDeep, Redirect).
merge_cliques([Clique | Cliques], MergeInfo, InitDeep0, Redirect0,
		InitDeep, Redirect) :-
	merge_clique(Clique, MergeInfo, InitDeep0, Redirect0,
		InitDeep1, Redirect1),
	merge_cliques(Cliques, MergeInfo, InitDeep1, Redirect1,
		InitDeep, Redirect).

:- pred merge_clique(list(proc_dynamic_ptr)::in,
	merge_info::in, initial_deep::in, redirect::in,
	initial_deep::out, redirect::out) is det.

merge_clique(CliquePDs0, MergeInfo, InitDeep0, Redirect0,
		InitDeep, Redirect) :-
	( CliquePDs0 = [_, _ | _] ->
		map__init(ProcMap0),
		list__foldl(cluster_pds_by_ps(InitDeep0), CliquePDs0,
			ProcMap0, ProcMap1),
		map__values(ProcMap1, PDsList1),
		list__filter(two_or_more, PDsList1, ToMergePDsList1),
		( ToMergePDsList1 = [_ | _] ->
			complete_clique(InitDeep0, Redirect0,
				ProcMap1, ProcMap, Clique),
			map__values(ProcMap, PDsList),
			list__filter(two_or_more, PDsList, ToMergePDsList),
			list__foldl2(merge_proc_dynamics_ignore_chosen(
				MergeInfo, Clique),
				ToMergePDsList, InitDeep0, InitDeep,
				Redirect0, Redirect)
		;
			InitDeep = InitDeep0,
			Redirect = Redirect0
		)
	;
		InitDeep = InitDeep0,
		Redirect = Redirect0
	).

:- pred insert_pds(list(T)::in, set(T)::in, set(T)::out) is det.

insert_pds(List, Set0, Set) :-
	set__insert_list(Set0, List, Set).

	% find set of proc_statics in the CliquePDs
	% for all (first order) calls in CliquePDs, if call is to a procedure
	%	that CliquePDs contains a call to, add its PD to the set

:- pred complete_clique(initial_deep::in, redirect::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::out,
	set(proc_dynamic_ptr)::out) is det.

complete_clique(InitDeep, Redirect, ProcMap0, ProcMap, Clique) :-
	map__values(ProcMap0, PDsList0),
	list__foldl(insert_pds, PDsList0, set__init, Clique0),
	complete_clique_pass(InitDeep, Redirect, Clique0, ProcMap0, ProcMap1,
		no, AddedPD),
	(
		AddedPD = yes,
		complete_clique(InitDeep, Redirect, ProcMap1, ProcMap, Clique)
	;
		AddedPD = no,
		ProcMap = ProcMap1,
		Clique = Clique0
	).

:- pred complete_clique_pass(initial_deep::in, redirect::in,
	set(proc_dynamic_ptr)::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::out,
	bool::in, bool::out) is det.

complete_clique_pass(InitDeep, _Redirect, Clique, ProcMap0, ProcMap,
		AddedPD0, AddedPD) :-
	map__to_assoc_list(ProcMap0, PSPDs0),
	list__foldl2(complete_clique_ps(InitDeep, Clique),
		PSPDs0, ProcMap0, ProcMap, AddedPD0, AddedPD).

:- pred complete_clique_ps(initial_deep::in,
	set(proc_dynamic_ptr)::in,
	pair(proc_static_ptr, list(proc_dynamic_ptr))::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::out,
	bool::in, bool::out) is det.

complete_clique_ps(InitDeep, Clique, PSPtr - PDPtrs, ProcMap0, ProcMap,
		AddedPD0, AddedPD) :-
	( PDPtrs = [_, _ | _] ->
		lookup_proc_statics(InitDeep ^ init_proc_statics, PSPtr, PS),
		list__map(lookup_pd_site(InitDeep), PDPtrs, PDSites),
		complete_clique_slots(array__max(PS ^ ps_sites), InitDeep,
			Clique, PS ^ ps_sites, PDSites, ProcMap0, ProcMap,
			AddedPD0, AddedPD)
	;
		ProcMap = ProcMap0,
		AddedPD = AddedPD0
	).

:- pred lookup_pd_site(initial_deep::in, proc_dynamic_ptr::in,
	array(call_site_array_slot)::out) is det.

lookup_pd_site(InitDeep, PDPtr, Sites) :-
	lookup_proc_dynamics(InitDeep ^ init_proc_dynamics, PDPtr, PD),
	Sites = PD ^ pd_sites.

:- pred complete_clique_slots(int::in, initial_deep::in,
	set(proc_dynamic_ptr)::in, array(call_site_static_ptr)::in,
	list(array(call_site_array_slot))::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::out,
	bool::in, bool::out) is det.

complete_clique_slots(SlotNum, InitDeep, Clique, PSSites, PDSites,
		ProcMap0, ProcMap, AddedPD0, AddedPD) :-
	( SlotNum >= 0 ->
		array__lookup(PSSites, SlotNum, CSSPtr),
		lookup_call_site_statics(InitDeep ^ init_call_site_statics,
			CSSPtr, CSS),
		( CSS ^ css_kind = normal_call(_, _) ->
			lookup_normal_sites(PDSites, SlotNum, CSDPtrs)
		;
			lookup_multi_sites(PDSites, SlotNum, CSDPtrLists),
			list__condense(CSDPtrLists, CSDPtrs)
		),
		list__filter(valid_call_site_dynamic_ptr_raw(
			InitDeep ^ init_call_site_dynamics), CSDPtrs,
			ValidCSDPtrs),
		list__map(extract_csdptr_callee(InitDeep), ValidCSDPtrs,
			CalleePDPtrs),
		CalleePDPtrSet = set__list_to_set(CalleePDPtrs),
		set__intersect(CalleePDPtrSet, Clique, Common),
		( set__empty(Common) ->
			ProcMap1 = ProcMap0,
			AddedPD1 = AddedPD0
		;
			set__difference(CalleePDPtrSet, Clique, NewMembers),
			( set__empty(NewMembers) ->
				ProcMap1 = ProcMap0,
				AddedPD1 = no
			;
				set__to_sorted_list(NewMembers, NewMemberList),
				list__foldl(cluster_pds_by_ps(InitDeep),
					NewMemberList, ProcMap0, ProcMap1),
				AddedPD1 = yes
			)
		),
		complete_clique_slots(SlotNum - 1, InitDeep, Clique,
			PSSites, PDSites, ProcMap1, ProcMap, AddedPD1, AddedPD)
	;
		ProcMap = ProcMap0,
		AddedPD = AddedPD0
	).

:- pred merge_proc_dynamics_ignore_chosen(merge_info::in,
	set(proc_dynamic_ptr)::in, list(proc_dynamic_ptr)::in,
	initial_deep::in, initial_deep::out, redirect::in, redirect::out)
	is det.

merge_proc_dynamics_ignore_chosen(MergeInfo, Clique, CandidatePDPtrs,
		InitDeep0, InitDeep, Redirect0, Redirect) :-
	merge_proc_dynamics(MergeInfo, Clique, CandidatePDPtrs, _ChosenPDPtr,
		InitDeep0, InitDeep, Redirect0, Redirect).

:- pred merge_proc_dynamics(merge_info::in, set(proc_dynamic_ptr)::in,
	list(proc_dynamic_ptr)::in, proc_dynamic_ptr::out,
	initial_deep::in, initial_deep::out, redirect::in, redirect::out)
	is det.

merge_proc_dynamics(MergeInfo, Clique, CandidatePDPtrs, ChosenPDPtr,
		InitDeep0, InitDeep, Redirect0, Redirect) :-
	ProcDynamics0 = InitDeep0 ^ init_proc_dynamics,
	list__filter(valid_proc_dynamic_ptr_raw(ProcDynamics0),
		CandidatePDPtrs, ValidPDPtrs, InvalidPDPtrs),
	require(unify(InvalidPDPtrs, []),
		"merge_proc_dynamics: invalid pdptrs"),
	( ValidPDPtrs = [PrimePDPtr | RestPDPtrs] ->
		record_pd_redirect(RestPDPtrs, PrimePDPtr,
			Redirect0, Redirect1),
		lookup_proc_dynamics(ProcDynamics0, PrimePDPtr, PrimePD0),
		list__map(lookup_proc_dynamics(ProcDynamics0),
			RestPDPtrs, RestPDs),
		list__map(extract_pd_sites, RestPDs, RestSites),
		PrimeSites0 = PrimePD0 ^ pd_sites,
		array__max(PrimeSites0, MaxSiteNum),
		merge_proc_dynamic_slots(MergeInfo, MaxSiteNum, Clique,
			PrimePDPtr, u(PrimeSites0), RestSites, PrimeSites,
			InitDeep0, InitDeep1, Redirect1, Redirect),
		PrimePD = PrimePD0 ^ pd_sites := PrimeSites,
		ProcDynamics1 = InitDeep1 ^ init_proc_dynamics,
		update_proc_dynamics(u(ProcDynamics1), PrimePDPtr, PrimePD,
			ProcDynamics),
		InitDeep = InitDeep1 ^ init_proc_dynamics := ProcDynamics,
		ChosenPDPtr = PrimePDPtr
	;
		% This could happen when merging the callees of CSDs
		% representing special calls, but only before we added callcode
		% to the unify/compare routines of builtin types.
		% ChosenPDPtr = proc_dynamic_ptr(0),
		% InitDeep = InitDeep0,
		% Redirect = Redirect0
		error("merge_proc_dynamics: no valid pdptrs")
	).

:- pred merge_proc_dynamic_slots(merge_info::in, int::in,
	set(proc_dynamic_ptr)::in, proc_dynamic_ptr::in,
	array(call_site_array_slot)::array_di,
	list(array(call_site_array_slot))::in,
	array(call_site_array_slot)::array_uo,
	initial_deep::in, initial_deep::out, redirect::in, redirect::out)
	is det.

merge_proc_dynamic_slots(MergeInfo, SlotNum, Clique, PrimePDPtr,
		PrimeSiteArray0, RestSiteArrays, PrimeSiteArray,
		InitDeep0, InitDeep, Redirect0, Redirect) :-
	( SlotNum >= 0 ->
		array__lookup(PrimeSiteArray0, SlotNum, PrimeSite0),
		(
			PrimeSite0 = normal(PrimeCSDPtr0),
			merge_proc_dynamic_normal_slot(MergeInfo, SlotNum,
				Clique, PrimePDPtr, PrimeCSDPtr0,
				RestSiteArrays, PrimeCSDPtr,
				InitDeep0, InitDeep1, Redirect0, Redirect1),
			array__set(PrimeSiteArray0, SlotNum,
				normal(PrimeCSDPtr), PrimeSiteArray1)
		;
			PrimeSite0 = multi(IsZeroed, PrimeCSDPtrArray0),
			array__to_list(PrimeCSDPtrArray0, PrimeCSDPtrList0),
			merge_proc_dynamic_multi_slot(MergeInfo, SlotNum,
				Clique, PrimePDPtr, PrimeCSDPtrList0,
				RestSiteArrays, PrimeCSDPtrList,
				InitDeep0, InitDeep1, Redirect0, Redirect1),
			PrimeCSDPtrArray = array(PrimeCSDPtrList),
			array__set(PrimeSiteArray0, SlotNum,
				multi(IsZeroed, PrimeCSDPtrArray),
				PrimeSiteArray1)
		),
		merge_proc_dynamic_slots(MergeInfo, SlotNum - 1, Clique,
			PrimePDPtr, PrimeSiteArray1, RestSiteArrays,
			PrimeSiteArray, InitDeep1, InitDeep,
			Redirect1, Redirect)
	;
		PrimeSiteArray = PrimeSiteArray0,
		InitDeep = InitDeep0,
		Redirect = Redirect0
	).

:- pred merge_proc_dynamic_normal_slot(merge_info::in, int::in,
	set(proc_dynamic_ptr)::in, proc_dynamic_ptr::in,
	call_site_dynamic_ptr::in, list(array(call_site_array_slot))::in,
	call_site_dynamic_ptr::out, initial_deep::in, initial_deep::out,
	redirect::in, redirect::out) is det.

merge_proc_dynamic_normal_slot(MergeInfo, SlotNum, Clique,
		PrimePDPtr, PrimeCSDPtr0, RestSiteArrays, PrimeCSDPtr,
		InitDeep0, InitDeep, Redirect0, Redirect) :-
	lookup_normal_sites(RestSiteArrays, SlotNum, RestCSDPtrs),
	merge_call_site_dynamics(MergeInfo, Clique, PrimePDPtr,
		[PrimeCSDPtr0 | RestCSDPtrs], PrimeCSDPtr,
		InitDeep0, InitDeep, Redirect0, Redirect).

:- pred accumulate_csd_owns(call_site_dynamic::in,
	own_prof_info::in, own_prof_info::out) is det.

accumulate_csd_owns(CSD, Own0, Own) :-
	Own = add_own_to_own(Own0, CSD ^ csd_own_prof).

:- pred callee_in_clique(initial_deep::in, set(proc_dynamic_ptr)::in,
	call_site_dynamic_ptr::in) is semidet.

callee_in_clique(InitDeep, Clique, CSDPtr) :-
	lookup_call_site_dynamics(InitDeep ^ init_call_site_dynamics,
		CSDPtr, CSD),
	CalleePDPtr = CSD ^ csd_callee,
	set__member(CalleePDPtr, Clique).

:- pred merge_proc_dynamic_multi_slot(merge_info::in, int::in,
	set(proc_dynamic_ptr)::in, proc_dynamic_ptr::in,
	list(call_site_dynamic_ptr)::in, list(array(call_site_array_slot))::in,
	list(call_site_dynamic_ptr)::out, initial_deep::in, initial_deep::out,
	redirect::in, redirect::out) is det.

merge_proc_dynamic_multi_slot(MergeInfo, SlotNum, Clique,
		ParentPDPtr, PrimeCSDPtrs0, RestSiteArrays, PrimeCSDPtrs,
		InitDeep0, InitDeep, Redirect0, Redirect) :-
	lookup_multi_sites(RestSiteArrays, SlotNum, RestCSDPtrLists),
	list__condense([PrimeCSDPtrs0 | RestCSDPtrLists], AllCSDPtrs),
	map__init(ProcMap0),
	list__foldl(cluster_csds_by_ps(InitDeep0), AllCSDPtrs,
		ProcMap0, ProcMap),
	map__values(ProcMap, CSDPtrsClusters),
	list__foldl3(merge_multi_slot_cluster(MergeInfo, ParentPDPtr, Clique),
		CSDPtrsClusters, [], PrimeCSDPtrs, InitDeep0, InitDeep,
		Redirect0, Redirect).

:- pred merge_multi_slot_cluster(merge_info::in, proc_dynamic_ptr::in,
	set(proc_dynamic_ptr)::in, list(call_site_dynamic_ptr)::in,
	list(call_site_dynamic_ptr)::in, list(call_site_dynamic_ptr)::out,
	initial_deep::in, initial_deep::out, redirect::in, redirect::out)
	is det.

merge_multi_slot_cluster(MergeInfo, ParentPDPtr, Clique, ClusterCSDPtrs,
		PrimeCSDPtrs0, PrimeCSDPtrs, InitDeep0, InitDeep,
		Redirect0, Redirect) :-
	merge_call_site_dynamics(MergeInfo, Clique,
		ParentPDPtr, ClusterCSDPtrs, PrimeCSDPtr,
		InitDeep0, InitDeep, Redirect0, Redirect),
	PrimeCSDPtrs = [PrimeCSDPtr | PrimeCSDPtrs0].

:- pred merge_call_site_dynamics(merge_info::in, set(proc_dynamic_ptr)::in,
	proc_dynamic_ptr::in, list(call_site_dynamic_ptr)::in,
	call_site_dynamic_ptr::out, initial_deep::in, initial_deep::out,
	redirect::in, redirect::out) is det.

merge_call_site_dynamics(MergeInfo, Clique, ParentPDPtr, CandidateCSDPtrs,
		ChosenCSDPtr, InitDeep0, InitDeep, Redirect0, Redirect) :-
	CallSiteDynamics0 = InitDeep0 ^ init_call_site_dynamics,
	list__filter(valid_call_site_dynamic_ptr_raw(CallSiteDynamics0),
		CandidateCSDPtrs, ValidCSDPtrs),
	(
		ValidCSDPtrs = [],
			% This signifies that there is no call here.
		ChosenCSDPtr = call_site_dynamic_ptr(0),
		InitDeep = InitDeep0,
		Redirect = Redirect0
	;
		ValidCSDPtrs = [FirstCSDPtr | LaterCSDPtrs],
		lookup_call_site_dynamics(CallSiteDynamics0, FirstCSDPtr,
			FirstCSD0),
		FirstCSD = FirstCSD0 ^ csd_caller := ParentPDPtr,
		update_call_site_dynamics(u(CallSiteDynamics0), FirstCSDPtr,
			FirstCSD, CallSiteDynamics),
		InitDeep1 = InitDeep0 ^ init_call_site_dynamics
			:= CallSiteDynamics,
		(
			LaterCSDPtrs = [],
			InitDeep = InitDeep1,
			Redirect = Redirect0
		;
			LaterCSDPtrs = [_ | _],
			merge_call_site_dynamics_2(MergeInfo, Clique,
				FirstCSDPtr, LaterCSDPtrs, InitDeep1, InitDeep,
				Redirect0, Redirect)
		),
		ChosenCSDPtr = FirstCSDPtr
	).

:- pred merge_call_site_dynamics_2(merge_info::in, set(proc_dynamic_ptr)::in,
	call_site_dynamic_ptr::in, list(call_site_dynamic_ptr)::in,
	initial_deep::in, initial_deep::out, redirect::in, redirect::out)
	is det.

merge_call_site_dynamics_2(MergeInfo, Clique, PrimeCSDPtr, RestCSDPtrs,
		InitDeep0, InitDeep, Redirect0, Redirect) :-
	% We must check whether PrimeCSDPtr and RestCSDPtrs are in Clique
	% *before* we update the proc_dynamics array in InitDeep0, which is
	% destructive updated to create InitDeep1.
	list__filter(callee_in_clique(InitDeep0, Clique), RestCSDPtrs,
		InClique, NotInClique),
	% XXX design error: should take union of cliques
	% i.e. if call is within clique in *any* caller, it should be within
	% clique in the final configuration
	( callee_in_clique(InitDeep0, Clique, PrimeCSDPtr) ->
		require(unify(NotInClique, []),
			"merge_proc_dynamic_normal_slot: prime in clique, others not in clique"),
		MergeChildren = no
	;
		require(unify(InClique, []),
			"merge_proc_dynamic_normal_slot: prime not in clique, others in clique"),
		MergeChildren = yes
	),
	record_csd_redirect(RestCSDPtrs, PrimeCSDPtr, Redirect0, Redirect1),
	CallSiteDynamics0 = InitDeep0 ^ init_call_site_dynamics,
	lookup_call_site_dynamics(CallSiteDynamics0, PrimeCSDPtr, PrimeCSD0),
	list__map(lookup_call_site_dynamics(CallSiteDynamics0),
		RestCSDPtrs, RestCSDs),
	PrimeOwn0 = PrimeCSD0 ^ csd_own_prof,
	list__foldl(accumulate_csd_owns, RestCSDs, PrimeOwn0, PrimeOwn1),
	PrimeCSD1 = PrimeCSD0 ^ csd_own_prof := PrimeOwn1,
	update_call_site_dynamics(u(CallSiteDynamics0), PrimeCSDPtr, PrimeCSD1,
		CallSiteDynamics1),
	InitDeep1 = InitDeep0 ^ init_call_site_dynamics := CallSiteDynamics1,
	(
		MergeChildren = no,
		InitDeep = InitDeep1,
		Redirect = Redirect1
	;
		MergeChildren = yes,
		merge_call_site_dynamics_descendants(MergeInfo,
			PrimeCSDPtr, RestCSDPtrs, ChosenPDPtr,
			InitDeep1, InitDeep2, Redirect1, Redirect),
		% We must ensure that PrimeCSDPtr ^ csd_callee
		% is updated to reflect the chosen merged ProcDynamic.
		CallSiteDynamics2 = InitDeep2 ^ init_call_site_dynamics,
		lookup_call_site_dynamics(CallSiteDynamics2, PrimeCSDPtr,
			PrimeCSD2),
		PrimeCSD = PrimeCSD2 ^ csd_callee := ChosenPDPtr,
		update_call_site_dynamics(u(CallSiteDynamics2),
			PrimeCSDPtr, PrimeCSD, CallSiteDynamics),
		InitDeep = InitDeep2 ^ init_call_site_dynamics
			:= CallSiteDynamics
	).

:- pred merge_call_site_dynamics_descendants(merge_info::in,
	call_site_dynamic_ptr::in, list(call_site_dynamic_ptr)::in,
	proc_dynamic_ptr::out, initial_deep::in, initial_deep::out,
	redirect::in, redirect::out) is det.

merge_call_site_dynamics_descendants(MergeInfo, PrimeCSDPtr, RestCSDPtrs,
		ChosenPDPtr, InitDeep0, InitDeep, Redirect0, Redirect) :-
	CallSiteDynamics = InitDeep0 ^ init_call_site_dynamics,
	lookup_call_site_dynamics(CallSiteDynamics, PrimeCSDPtr, PrimeCSD),
	extract_csd_callee(PrimeCSD, PrimeCSDCallee),
	list__map(lookup_call_site_dynamics(CallSiteDynamics), 
		RestCSDPtrs, RestCSDs),
	list__map(extract_csd_callee, RestCSDs, RestCSDCallees),
	PDPtrs = [PrimeCSDCallee | RestCSDCallees],
	list__foldl(union_cliques(MergeInfo), PDPtrs, set__init, CliqueUnion),
	merge_proc_dynamics(MergeInfo, CliqueUnion, PDPtrs, ChosenPDPtr,
		InitDeep0, InitDeep, Redirect0, Redirect).

:- pred union_cliques(merge_info::in, proc_dynamic_ptr::in,
	set(proc_dynamic_ptr)::in, set(proc_dynamic_ptr)::out) is det.

union_cliques(MergeInfo, PDPtr, CliqueUnion0, CliqueUnion) :-
	( PDPtr = proc_dynamic_ptr(0) ->
		% This can happen with calls to the unify/compare preds
		% of builtin types.
		CliqueUnion = CliqueUnion0
	;
		lookup_clique_index(MergeInfo ^ merge_clique_index, PDPtr,
			CliquePtr),
		lookup_clique_members(MergeInfo ^ merge_clique_members,
			CliquePtr, Members),
		set__insert_list(CliqueUnion0, Members, CliqueUnion)
	).

:- pred lookup_normal_sites(list(array(call_site_array_slot))::in, int::in,
	list(call_site_dynamic_ptr)::out) is det.

lookup_normal_sites([], _, []).
lookup_normal_sites([RestArray | RestArrays], SlotNum, [CSDPtr | CSDPtrs]) :-
	array__lookup(RestArray, SlotNum, Slot),
	(
		Slot = normal(CSDPtr)
	;
		Slot = multi(_, _),
		error("lookup_normal_sites: found multi")
	),
	lookup_normal_sites(RestArrays, SlotNum, CSDPtrs).

:- pred lookup_multi_sites(list(array(call_site_array_slot))::in, int::in,
	list(list(call_site_dynamic_ptr))::out) is det.

lookup_multi_sites([], _, []).
lookup_multi_sites([RestArray | RestArrays], SlotNum, [CSDList | CSDLists]) :-
	array__lookup(RestArray, SlotNum, Slot),
	(
		Slot = normal(_),
		error("lookup_multi_sites: found normal")
	;
		Slot = multi(_, CSDArray),
		array__to_list(CSDArray, CSDList)
	),
	lookup_multi_sites(RestArrays, SlotNum, CSDLists).

:- pragma promise_pure(record_pd_redirect/4).
:- pred record_pd_redirect(list(proc_dynamic_ptr)::in, proc_dynamic_ptr::in,
	redirect::in, redirect::out) is det.

record_pd_redirect(RestPDPtrs, PrimePDPtr, Redirect0, Redirect) :-
	impure unsafe_perform_io(io__write_string("pd redirect: ")),
	impure unsafe_perform_io(io__print(RestPDPtrs)),
	impure unsafe_perform_io(io__write_string(" -> ")),
	impure unsafe_perform_io(io__print(PrimePDPtr)),
	impure unsafe_perform_io(io__nl),
	lookup_pd_redirect(Redirect0 ^ pd_redirect, PrimePDPtr, OldRedirect),
	( OldRedirect = proc_dynamic_ptr(0) ->
		record_pd_redirect_2(RestPDPtrs, PrimePDPtr,
			Redirect0, Redirect)
	;
		error("record_pd_redirect: prime is redirected")
	).

:- pred record_pd_redirect_2(list(proc_dynamic_ptr)::in, proc_dynamic_ptr::in,
	redirect::in, redirect::out) is det.

record_pd_redirect_2([], _, Redirect, Redirect).
record_pd_redirect_2([RestPDPtr | RestPDPtrs], PrimePDPtr,
		Redirect0, Redirect) :-
	ProcRedirect0 = Redirect0 ^ pd_redirect,
	lookup_pd_redirect(ProcRedirect0, RestPDPtr, OldRedirect),
	( OldRedirect = proc_dynamic_ptr(0) ->
		set_pd_redirect(u(ProcRedirect0), RestPDPtr, PrimePDPtr,
			ProcRedirect)
	;
		error("record_pd_redirect_2: already redirected")
	),
	Redirect1 = Redirect0 ^ pd_redirect := ProcRedirect,
	record_pd_redirect_2(RestPDPtrs, PrimePDPtr, Redirect1, Redirect).

:- pragma promise_pure(record_csd_redirect/4).
:- pred record_csd_redirect(list(call_site_dynamic_ptr)::in,
	call_site_dynamic_ptr::in, redirect::in, redirect::out) is det.

record_csd_redirect(RestCSDPtrs, PrimeCSDPtr, Redirect0, Redirect) :-
	impure unsafe_perform_io(io__write_string("csd redirect: ")),
	impure unsafe_perform_io(io__print(RestCSDPtrs)),
	impure unsafe_perform_io(io__write_string(" -> ")),
	impure unsafe_perform_io(io__print(PrimeCSDPtr)),
	impure unsafe_perform_io(io__nl),
	lookup_csd_redirect(Redirect0 ^ csd_redirect, PrimeCSDPtr, OldRedirect),
	( OldRedirect = call_site_dynamic_ptr(0) ->
		record_csd_redirect_2(RestCSDPtrs, PrimeCSDPtr,
			Redirect0, Redirect)
	;
		error("record_pd_redirect: prime is redirected")
	).

:- pred record_csd_redirect_2(list(call_site_dynamic_ptr)::in,
	call_site_dynamic_ptr::in, redirect::in, redirect::out) is det.

record_csd_redirect_2([], _, Redirect, Redirect).
record_csd_redirect_2([RestCSDPtr | RestCSDPtrs], PrimeCSDPtr,
		Redirect0, Redirect) :-
	CallSiteRedirect0 = Redirect0 ^ csd_redirect,
	lookup_csd_redirect(CallSiteRedirect0, RestCSDPtr, OldRedirect),
	( OldRedirect = call_site_dynamic_ptr(0) ->
		set_csd_redirect(u(CallSiteRedirect0), RestCSDPtr, PrimeCSDPtr,
			CallSiteRedirect)
	;
		error("record_csd_redirect_2: already redirected")
	),
	Redirect1 = Redirect0 ^ csd_redirect := CallSiteRedirect,
	record_csd_redirect_2(RestCSDPtrs, PrimeCSDPtr, Redirect1, Redirect).

:- pred two_or_more(list(proc_dynamic_ptr)::in) is semidet.

two_or_more([_, _ | _]).

:- pred cluster_pds_by_ps(initial_deep::in, proc_dynamic_ptr::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::in,
	map(proc_static_ptr, list(proc_dynamic_ptr))::out) is det.

cluster_pds_by_ps(InitDeep, PDPtr, ProcMap0, ProcMap) :-
	ProcDynamics = InitDeep ^ init_proc_dynamics,
	( valid_proc_dynamic_ptr_raw(ProcDynamics, PDPtr) ->
		lookup_proc_dynamics(ProcDynamics, PDPtr, PD),
		PSPtr = PD ^ pd_proc_static,
		( map__search(ProcMap0, PSPtr, PDPtrs0) ->
			map__det_update(ProcMap0, PSPtr, [PDPtr | PDPtrs0],
				ProcMap)
		;
			map__det_insert(ProcMap0, PSPtr, [PDPtr], ProcMap)
		)
	;
		ProcMap = ProcMap0
	).

:- pred cluster_csds_by_ps(initial_deep::in, call_site_dynamic_ptr::in,
	map(proc_static_ptr, list(call_site_dynamic_ptr))::in,
	map(proc_static_ptr, list(call_site_dynamic_ptr))::out) is det.

cluster_csds_by_ps(InitDeep, CSDPtr, ProcMap0, ProcMap) :-
	CallSiteDynamics = InitDeep ^ init_call_site_dynamics,
	( valid_call_site_dynamic_ptr_raw(CallSiteDynamics, CSDPtr) ->
		lookup_call_site_dynamics(CallSiteDynamics, CSDPtr, CSD),
		PDPtr = CSD ^ csd_callee,
		ProcDynamics = InitDeep ^ init_proc_dynamics,
		( valid_proc_dynamic_ptr_raw(ProcDynamics, PDPtr) ->
			lookup_proc_dynamics(ProcDynamics, PDPtr, PD),
			PSPtr = PD ^ pd_proc_static
		;
			PSPtr = proc_static_ptr(0)
		),
		( map__search(ProcMap0, PSPtr, CSDPtrs0) ->
			map__det_update(ProcMap0, PSPtr, [CSDPtr | CSDPtrs0],
				ProcMap)
		;
			map__det_insert(ProcMap0, PSPtr, [CSDPtr], ProcMap)
		)
	;
		ProcMap = ProcMap0
	).

:- pred lookup_pd_redirect(array(proc_dynamic_ptr)::in,
	proc_dynamic_ptr::in, proc_dynamic_ptr::out) is det.

lookup_pd_redirect(ProcRedirect0, PDPtr, OldRedirect) :-
	PDPtr = proc_dynamic_ptr(PDI),
	array__lookup(ProcRedirect0, PDI, OldRedirect).

:- pred set_pd_redirect(array(proc_dynamic_ptr)::array_di,
	proc_dynamic_ptr::in, proc_dynamic_ptr::in,
	array(proc_dynamic_ptr)::array_uo) is det.

set_pd_redirect(ProcRedirect0, PDPtr, NewRedirect, ProcRedirect) :-
	PDPtr = proc_dynamic_ptr(PDI),
	array__set(ProcRedirect0, PDI, NewRedirect, ProcRedirect).

:- pred lookup_csd_redirect(array(call_site_dynamic_ptr)::in,
	call_site_dynamic_ptr::in, call_site_dynamic_ptr::out) is det.

lookup_csd_redirect(CallSiteRedirect0, CSDPtr, OldRedirect) :-
	CSDPtr = call_site_dynamic_ptr(CSDI),
	array__lookup(CallSiteRedirect0, CSDI, OldRedirect).

:- pred set_csd_redirect(array(call_site_dynamic_ptr)::array_di,
	call_site_dynamic_ptr::in, call_site_dynamic_ptr::in,
	array(call_site_dynamic_ptr)::array_uo) is det.

set_csd_redirect(CallSiteRedirect0, CSDPtr, NewRedirect, CallSiteRedirect) :-
	CSDPtr = call_site_dynamic_ptr(CSDI),
	array__set(CallSiteRedirect0, CSDI, NewRedirect, CallSiteRedirect).

%-----------------------------------------------------------------------------%

:- pred deref_call_site_dynamic(redirect::in, call_site_dynamic_ptr::in,
	call_site_dynamic_ptr::out) is det.

deref_call_site_dynamic(Redirect, CSDPtr0, CSDPtr) :-
	lookup_csd_redirect(Redirect ^ csd_redirect, CSDPtr0, RedirectCSDPtr),
	RedirectCSDPtr = call_site_dynamic_ptr(RedirectCSDI),
	( RedirectCSDI > 0 ->
		deref_call_site_dynamic(Redirect, RedirectCSDPtr, CSDPtr)
	;
		CSDPtr = CSDPtr0
	).

:- pred deref_proc_dynamic(redirect::in, proc_dynamic_ptr::in,
	proc_dynamic_ptr::out) is det.

deref_proc_dynamic(Redirect, PDPtr0, PDPtr) :-
	lookup_pd_redirect(Redirect ^ pd_redirect, PDPtr0, RedirectPDPtr),
	RedirectPDPtr = proc_dynamic_ptr(RedirectPDI),
	( RedirectPDI > 0 ->
		deref_proc_dynamic(Redirect, RedirectPDPtr, PDPtr)
	;
		PDPtr = PDPtr0
	).

%-----------------------------------------------------------------------------%

:- pred compact_dynamics(initial_deep::in, redirect::in, int::in, int::in,
	initial_deep::out) is det.

compact_dynamics(InitDeep0, Redirect0, MaxCSD0, MaxPD0, InitDeep) :-
	Redirect0 = redirect(CSDredirect0, PDredirect0),
	InitDeep0 = initial_deep(Stats, Root0, CSDs0, PDs0, CSSs, PSs),
	compact_csd_redirect(1, 1, MaxCSD0, NumCSD,
		u(CSDredirect0), CSDredirect),
	compact_pd_redirect(1, 1, MaxPD0, NumPD,
		u(PDredirect0), PDredirect),
	Redirect = redirect(CSDredirect, PDredirect),
	array_map_from_1(subst_in_call_site_dynamic(Redirect),
		u(CSDs0), CSDs1),
	array_map_from_1(subst_in_proc_dynamic(Redirect),
		u(PDs0), PDs1),
	array__shrink(CSDs1, NumCSD, CSDs),
	array__shrink(PDs1, NumPD, PDs),
	lookup_pd_redirect(PDredirect, Root0, Root),
	InitDeep = initial_deep(Stats, Root, CSDs, PDs, CSSs, PSs).

:- pred compact_csd_redirect(int::in, int::in, int::in, int::out,
	array(call_site_dynamic_ptr)::array_di,
	array(call_site_dynamic_ptr)::array_uo) is det.

compact_csd_redirect(CurOld, CurNew, MaxOld, NumNew,
		CSDredirect0, CSDredirect) :-
	( CurOld > MaxOld ->
		NumNew = CurNew,
		CSDredirect = CSDredirect0
	;
		array__lookup(CSDredirect0, CurOld, Redirect0),
		( Redirect0 = call_site_dynamic_ptr(0) ->
			array__set(CSDredirect0, CurOld,
				call_site_dynamic_ptr(CurNew), CSDredirect1),
			compact_csd_redirect(CurOld + 1, CurNew + 1,
				MaxOld, NumNew, CSDredirect1, CSDredirect)
		;
			% Since this CSD is being redirected, its slot is
			% available for another (non-redirected) CSD.
			compact_csd_redirect(CurOld + 1, CurNew,
				MaxOld, NumNew, CSDredirect0, CSDredirect)
		)
	).

:- pred compact_pd_redirect(int::in, int::in, int::in, int::out,
	array(proc_dynamic_ptr)::array_di,
	array(proc_dynamic_ptr)::array_uo) is det.

compact_pd_redirect(CurOld, CurNew, MaxOld, NumNew,
		PDredirect0, PDredirect) :-
	( CurOld > MaxOld ->
		NumNew = CurNew,
		PDredirect = PDredirect0
	;
		array__lookup(PDredirect0, CurOld, Redirect0),
		( Redirect0 = proc_dynamic_ptr(0) ->
			array__set(PDredirect0, CurOld,
				proc_dynamic_ptr(CurNew), PDredirect1),
			compact_pd_redirect(CurOld + 1, CurNew + 1,
				MaxOld, NumNew, PDredirect1, PDredirect)
		;
			% Since this PD is being redirected, its slot is
			% available for another (non-redirected) PD.
			compact_pd_redirect(CurOld + 1, CurNew,
				MaxOld, NumNew, PDredirect0, PDredirect)
		)
	).

:- pred subst_in_call_site_dynamic(redirect::in, call_site_dynamic::in,
	call_site_dynamic::out) is det.

subst_in_call_site_dynamic(Redirect, CSD0, CSD) :-
	CSD0 = call_site_dynamic(Caller0, Callee0, Own),
	lookup_pd_redirect(Redirect ^ pd_redirect, Caller0, Caller),
	lookup_pd_redirect(Redirect ^ pd_redirect, Callee0, Callee),
	CSD = call_site_dynamic(Caller, Callee, Own).

:- pred subst_in_proc_dynamic(redirect::in, proc_dynamic::in,
	proc_dynamic::out) is det.

subst_in_proc_dynamic(Redirect, PD0, PD) :-
	PD0 = proc_dynamic(PDPtr, Slots0),
	array__map(subst_in_slot(Redirect), u(Slots0), Slots),
	PD = proc_dynamic(PDPtr, Slots).

:- pred subst_in_slot(redirect::in, call_site_array_slot::in,
	call_site_array_slot::out) is det.

subst_in_slot(Redirect, normal(CSDPtr0), normal(CSDPtr)) :-
	lookup_csd_redirect(Redirect ^ csd_redirect, CSDPtr0, CSDPtr).
subst_in_slot(Redirect, multi(IsZeroed, CSDPtrs0), multi(IsZeroed, CSDPtrs)) :-
	array__map(lookup_csd_redirect(Redirect ^ csd_redirect),
		u(CSDPtrs0), CSDPtrs).

%-----------------------------------------------------------------------------%

:- pred merge_profiles(list(initial_deep)::in, maybe_error(initial_deep)::out)
	is det.

merge_profiles(InitDeeps, MaybeMergedInitDeep) :-
	( InitDeeps = [FirstInitDeep | LaterInitDeeps] ->
		( all_compatible(FirstInitDeep, LaterInitDeeps) ->
			do_merge_profiles(FirstInitDeep, LaterInitDeeps,
				MergedInitDeep),
			MaybeMergedInitDeep = ok(MergedInitDeep)
		;
			MaybeMergedInitDeep =
				error("profiles are not from the same executable")
		)
	;
		MaybeMergedInitDeep =
			error("merge_profiles: empty list of profiles")
	).

:- pred all_compatible(initial_deep::in, list(initial_deep)::in) is semidet.

all_compatible(BaseInitDeep, OtherInitDeeps) :-
	extract_max_css(BaseInitDeep, BaseMaxCSS),
	extract_max_ps(BaseInitDeep, BaseMaxPS),
	extract_ticks_per_sec(BaseInitDeep, BaseTicksPerSec),
	list__map(extract_max_css, OtherInitDeeps, OtherMaxCSSs),
	list__map(extract_max_ps, OtherInitDeeps, OtherMaxPSs),
	list__map(extract_ticks_per_sec, OtherInitDeeps, OtherTicksPerSec),
	all_true(unify(BaseMaxCSS), OtherMaxCSSs),
	all_true(unify(BaseMaxPS), OtherMaxPSs),
	all_true(unify(BaseTicksPerSec), OtherTicksPerSec),
	extract_init_call_site_statics(BaseInitDeep, BaseCallSiteStatics),
	extract_init_proc_statics(BaseInitDeep, BaseProcStatics),
	list__map(extract_init_call_site_statics, OtherInitDeeps,
		OtherCallSiteStatics),
	list__map(extract_init_proc_statics, OtherInitDeeps,
		OtherProcStatics),
	array_match_elements(1, BaseMaxCSS, BaseCallSiteStatics,
		OtherCallSiteStatics),
	array_match_elements(1, BaseMaxPS, BaseProcStatics,
		OtherProcStatics).

:- pred do_merge_profiles(initial_deep::in, list(initial_deep)::in,
	initial_deep::out) is det.

do_merge_profiles(BaseInitDeep, OtherInitDeeps, MergedInitDeep) :-
	extract_max_csd(BaseInitDeep, BaseMaxCSD),
	extract_max_pd(BaseInitDeep, BaseMaxPD),
	list__map(extract_max_csd, OtherInitDeeps, OtherMaxCSDs),
	list__map(extract_max_pd, OtherInitDeeps, OtherMaxPDs),
	list__foldl(int_add, OtherMaxCSDs, BaseMaxCSD, ConcatMaxCSD),
	list__foldl(int_add, OtherMaxPDs, BaseMaxPD, ConcatMaxPD),
	extract_init_call_site_dynamics(BaseInitDeep, BaseCallSiteDynamics),
	extract_init_proc_dynamics(BaseInitDeep, BaseProcDynamics),
	array__lookup(BaseCallSiteDynamics, 0, DummyCSD),
	array__lookup(BaseProcDynamics, 0, DummyPD),
	array__init(ConcatMaxCSD + 1, DummyCSD, ConcatCallSiteDynamics0),
	array__init(ConcatMaxPD + 1, DummyPD, ConcatProcDynamics0),
	AllInitDeeps = [BaseInitDeep | OtherInitDeeps],
	concatenate_profiles(AllInitDeeps, 0, 0,
		ConcatCallSiteDynamics0, ConcatCallSiteDynamics,
		ConcatProcDynamics0, ConcatProcDynamics),

	extract_max_css(BaseInitDeep, BaseMaxCSS),
	extract_max_ps(BaseInitDeep, BaseMaxPS),
	extract_ticks_per_sec(BaseInitDeep, BaseTicksPerSec),
	list__map(extract_instrument_quanta, AllInitDeeps, InstrumentQuantas),
	list__map(extract_user_quanta, AllInitDeeps, UserQuantas),
	list__foldl(int_add, InstrumentQuantas, 0, InstrumentQuanta),
	list__foldl(int_add, UserQuantas, 0, UserQuanta),
	WordSize = BaseInitDeep ^ init_profile_stats ^ word_size,
	ConcatProfileStats = profile_stats(
		ConcatMaxCSD, BaseMaxCSS, ConcatMaxPD, BaseMaxPS,
		BaseTicksPerSec, InstrumentQuanta, UserQuanta, WordSize, yes),
	% The root part is a temporary lie.
	MergedInitDeep = initial_deep(ConcatProfileStats,
		BaseInitDeep ^ init_root,
		ConcatCallSiteDynamics,
		ConcatProcDynamics,
		BaseInitDeep ^ init_call_site_statics,
		BaseInitDeep ^ init_proc_statics).
	% list__map(extract_init_root, AllInitDeeps, Roots),
	% merge clique of roots, replacing root with chosen pd

:- pred concatenate_profiles(list(initial_deep)::in, int::in, int::in,
	call_site_dynamics::array_di, call_site_dynamics::array_uo,
	proc_dynamics::array_di, proc_dynamics::array_uo) is det.

concatenate_profiles([], _PrevMaxCSD, _PrevMaxPD,
		ConcatCallSiteDynamics, ConcatCallSiteDynamics,
		ConcatProcDynamics, ConcatProcDynamics).
concatenate_profiles([InitDeep | InitDeeps], PrevMaxCSD, PrevMaxPD,
		ConcatCallSiteDynamics0, ConcatCallSiteDynamics,
		ConcatProcDynamics0, ConcatProcDynamics) :-
	concatenate_profile(InitDeep,
		PrevMaxCSD, PrevMaxPD, NextMaxCSD, NextMaxPD,
		ConcatCallSiteDynamics0, ConcatCallSiteDynamics1,
		ConcatProcDynamics0, ConcatProcDynamics1),
	concatenate_profiles(InitDeeps, NextMaxCSD, NextMaxPD,
		ConcatCallSiteDynamics1, ConcatCallSiteDynamics,
		ConcatProcDynamics1, ConcatProcDynamics).

:- pred concatenate_profile(initial_deep::in,
	int::in, int::in, int::out, int::out,
	call_site_dynamics::array_di, call_site_dynamics::array_uo,
	proc_dynamics::array_di, proc_dynamics::array_uo) is det.

concatenate_profile(InitDeep, PrevMaxCSD, PrevMaxPD, NextMaxCSD, NextMaxPD,
		ConcatCallSiteDynamics0, ConcatCallSiteDynamics,
		ConcatProcDynamics0, ConcatProcDynamics) :-
	extract_max_csd(InitDeep, MaxCSD),
	extract_max_pd(InitDeep, MaxPD),
	NextMaxCSD = PrevMaxCSD + MaxCSD,
	NextMaxPD = PrevMaxPD + MaxPD,
	concatenate_profile_csds(1, MaxCSD, PrevMaxCSD, PrevMaxPD,
		InitDeep ^ init_call_site_dynamics,
		ConcatCallSiteDynamics0, ConcatCallSiteDynamics),
	concatenate_profile_pds(1, MaxPD, PrevMaxCSD, PrevMaxPD,
		InitDeep ^ init_proc_dynamics,
		ConcatProcDynamics0, ConcatProcDynamics).

:- pred concatenate_profile_csds(int::in, int::in, int::in, int::in,
	call_site_dynamics::in,
	call_site_dynamics::array_di, call_site_dynamics::array_uo) is det.

concatenate_profile_csds(Cur, Max, PrevMaxCSD, PrevMaxPD, CallSiteDynamics,
		ConcatCallSiteDynamics0, ConcatCallSiteDynamics) :-
	( Cur =< Max ->
		array__lookup(CallSiteDynamics, Cur, CSD0),
		CSD0 = call_site_dynamic(CallerPDPtr0, CalleePDPtr0, Own),
		concat_proc_dynamic_ptr(PrevMaxPD, CallerPDPtr0, CallerPDPtr),
		concat_proc_dynamic_ptr(PrevMaxPD, CalleePDPtr0, CalleePDPtr),
		CSD = call_site_dynamic(CallerPDPtr, CalleePDPtr, Own),
		array__set(ConcatCallSiteDynamics0, PrevMaxCSD + Cur, CSD,
			ConcatCallSiteDynamics1),
		concatenate_profile_csds(Cur + 1, Max, PrevMaxCSD, PrevMaxPD,
			CallSiteDynamics,
			ConcatCallSiteDynamics1, ConcatCallSiteDynamics)
	;
		ConcatCallSiteDynamics = ConcatCallSiteDynamics0
	).

:- pred concatenate_profile_pds(int::in, int::in, int::in, int::in,
	proc_dynamics::in,
	proc_dynamics::array_di, proc_dynamics::array_uo) is det.

concatenate_profile_pds(Cur, Max, PrevMaxCSD, PrevMaxPD, ProcDynamics,
		ConcatProcDynamics0, ConcatProcDynamics) :-
	( Cur =< Max ->
		array__lookup(ProcDynamics, Cur, PD0),
		PD0 = proc_dynamic(PSPtr, Sites0),
		array__max(Sites0, MaxSite),
		concatenate_profile_slots(0, MaxSite, PrevMaxCSD, PrevMaxPD,
			u(Sites0), Sites),
		PD = proc_dynamic(PSPtr, Sites),
		array__set(ConcatProcDynamics0, PrevMaxPD + Cur, PD,
			ConcatProcDynamics1),
		concatenate_profile_pds(Cur + 1, Max, PrevMaxCSD, PrevMaxPD,
			ProcDynamics,
			ConcatProcDynamics1, ConcatProcDynamics)
	;
		ConcatProcDynamics = ConcatProcDynamics0
	).

:- pred concatenate_profile_slots(int::in, int::in, int::in, int::in,
	array(call_site_array_slot)::array_di,
	array(call_site_array_slot)::array_uo) is det.

concatenate_profile_slots(Cur, Max, PrevMaxCSD, PrevMaxPD, Sites0, Sites) :-
	( Cur =< Max ->
		array__lookup(Sites0, Cur, Slot0),
		(
			Slot0 = normal(CSDPtr0),
			concat_call_site_dynamic_ptr(PrevMaxCSD,
				CSDPtr0, CSDPtr),
			Slot = normal(CSDPtr)
		;
			Slot0 = multi(IsZeroed, CSDPtrs0),
			array_map_from_0(
				concat_call_site_dynamic_ptr(PrevMaxCSD),
				u(CSDPtrs0), CSDPtrs),
			Slot = multi(IsZeroed, CSDPtrs)
		),
		array__set(Sites0, Cur, Slot, Sites1),
		concatenate_profile_slots(Cur + 1, Max, PrevMaxCSD, PrevMaxPD,
			Sites1, Sites)
	;
		Sites = Sites0
	).

:- pred concat_call_site_dynamic_ptr(int::in, call_site_dynamic_ptr::in,
	call_site_dynamic_ptr::out) is det.

concat_call_site_dynamic_ptr(PrevMaxCSD, CSDPtr0, CSDPtr) :-
	CSDPtr0 = call_site_dynamic_ptr(CSDI0),
	( CSDI0 = 0 ->
		CSDPtr = CSDPtr0
	;
		CSDPtr = call_site_dynamic_ptr(CSDI0 + PrevMaxCSD)
	).

:- pred concat_proc_dynamic_ptr(int::in, proc_dynamic_ptr::in,
	proc_dynamic_ptr::out) is det.

concat_proc_dynamic_ptr(PrevMaxPD, PDPtr0, PDPtr) :-
	PDPtr0 = proc_dynamic_ptr(PDI0),
	( PDI0 = 0 ->
		PDPtr = PDPtr0
	;
		PDPtr = proc_dynamic_ptr(PDI0 + PrevMaxPD)
	).

%-----------------------------------------------------------------------------%

	% list__all_true(P, L) succeeds iff P is true for all elements of the
	% list L.
:- pred all_true(pred(X), list(X)).
:- mode all_true(pred(in) is semidet, in) is semidet.

all_true(_, []).
all_true(P, [H | T]) :-
	call(P, H),
	all_true(P, T).

	% array_match_elements(Min, Max, BaseArray, OtherArrays):
	% Succeeds iff all the elements of all the OtherArrays are equal to the
	% corresponding element of BaseArray.
:- pred array_match_elements(int::in, int::in, array(T)::in,
	list(array(T))::in) is semidet.

array_match_elements(N, Max, BaseArray, OtherArrays) :-
	( N =< Max ->
		array__lookup(BaseArray, N, BaseElement),
		match_element(BaseElement, N, OtherArrays),
		array_match_elements(N + 1, Max, BaseArray, OtherArrays)
	;
		true
	).

	% match_element(TestElement, Index, Arrays):
	% Succeeds iff the elements of all the Arrays at index Index
	% are equal to TestElement.
:- pred match_element(T::in, int::in, list(array(T))::in) is semidet.

match_element(_, _, []).
match_element(TestElement, Index, [Array | Arrays]) :-
	array__lookup(Array, Index, Element),
	Element = TestElement,
	match_element(Element, Index, Arrays).

:- pred int_add(int::in, int::in, int::out) is det.

int_add(A, B, C) :-
	C = A + B.
