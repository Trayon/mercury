%-----------------------------------------------------------------------------%
% Copyright (C) 2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

:- module deep.

:- interface.

:- import_module io.

:- pred main(io__state::di, io__state::uo) is cc_multi.

:- implementation.

:- import_module measurements.
:- import_module array, bool, char, getopt, int, list, assoc_list.
:- import_module map, require, set, std_util, string.

:- type profile_stats --->
	profile_stats(
		instrument_quanta	:: int,
		user_quanta		:: int,
		num_csds		:: int,
		num_pds			:: int,
		num_csss		:: int,
		num_pss			:: int
	).

:- type initial_deep --->
	initial_deep(
		init_profile_stats	:: profile_stats,

		init_root		:: proc_dynamic_ptr,
			% The main arrays, each indexed by own xxx_ptr int
		init_call_site_dynamics	:: call_site_dynamics,
		init_proc_dynamics	:: proc_dynamics,
		init_call_site_statics	:: call_site_statics,
		init_proc_statics	:: proc_statics
	).

:- type deep --->
	deep(
		profile_stats		:: profile_stats,
		server_name		:: string,
		data_file_name		:: string,

		root			:: proc_dynamic_ptr,
			% The main arrays, each indexed by own xxx_ptr int
		call_site_dynamics	:: call_site_dynamics,
		proc_dynamics		:: proc_dynamics,
		call_site_statics	:: call_site_statics,
		proc_statics		:: proc_statics,
			% Clique information
		clique_index		:: array(clique_ptr),
					   % index: proc_dynamic_ptr int
		clique_members		:: array(list(proc_dynamic_ptr)),
					   % index: clique_ptr int
		clique_parents		:: array(call_site_dynamic_ptr),
					   % index: clique_ptr int
		clique_maybe_child	:: array(maybe(clique_ptr)),
					   % index: call_site_dynamic_ptr int
			% Reverse links
		proc_callers		:: array(list(call_site_dynamic_ptr)),
					   % index: proc_static_ptr int
		call_site_static_map	:: call_site_static_map,
					   % index: call_site_dynamic_ptr int
		call_site_calls		:: array(map(proc_static_ptr,
						list(call_site_dynamic_ptr))),
					   % index: call_site_static_ptr int
			% Propagated timing info
		pd_own			:: array(own_prof_info),
		pd_desc			:: array(inherit_prof_info),
		csd_desc		:: array(inherit_prof_info),
		ps_own			:: array(own_prof_info),
		ps_desc			:: array(inherit_prof_info),
		css_own			:: array(own_prof_info),
		css_desc		:: array(inherit_prof_info)
	).

%-----------------------------------------------------------------------------%

:- type proc_dynamics == array(proc_dynamic).
:- type proc_statics == array(proc_static).
:- type call_site_dynamics == array(call_site_dynamic).
:- type call_site_statics == array(call_site_static).
:- type call_site_static_map == array(call_site_static_ptr).

:- type proc_dynamic_ptr
	--->	proc_dynamic_ptr(int).

:- type proc_static_ptr
	--->	proc_static_ptr(int).

:- type call_site_dynamic_ptr
	--->	call_site_dynamic_ptr(int).

:- type call_site_static_ptr
	--->	call_site_static_ptr(int).

:- type clique_ptr
	--->	clique_ptr(int).

%-----------------------------------------------------------------------------%

:- type proc_dynamic
	--->	proc_dynamic(
			pd_proc_static	:: proc_static_ptr,
			pd_sites	:: array(call_site_array_slot)
		).

:- type proc_static
	--->	proc_static(
			ps_id		:: proc_id,	% procedure ID
			ps_refined_id	:: string, 	% refined procedure id
			ps_raw_id	:: string, 	% raw procedure id
			ps_filename	:: string, 	% file name
			ps_sites	:: array(call_site_static_ptr)
		).

:- type call_site_dynamic
	--->	call_site_dynamic(
			csd_caller	:: proc_dynamic_ptr,
			csd_callee	:: proc_dynamic_ptr,
			csd_own_prof	:: own_prof_info
		).

:- type call_site_static
	--->	call_site_static(
			css_container	:: proc_static_ptr,
					   % the containing procedure
			css_slot_num	:: int,
					   % slot number in the
					   % containing procedure
			css_kind	:: call_site_kind_and_callee,
			css_line_num	:: int,
			css_goal_path	:: string
		).

%-----------------------------------------------------------------------------%

:- type pred_or_func
	--->	predicate
	;	function.

:- type proc_id
	--->	user_defined(
			user_pred_or_func	:: pred_or_func,
			user_decl_module	:: string,
			user_def_module		:: string,
			user_name		:: string,
			user_arity		:: int,
			user_mode		:: int
		)
	;	compiler_generated(
			comp_gen_type_name	:: string,
			comp_gen_type_module	:: string,
			comp_gen_def_module	:: string,
			comp_gen_pred_name	:: string,
			comp_gen_arity		:: int,
			comp_gen_mode		:: int
		).

:- type call_site_array_slot
	--->	normal(call_site_dynamic_ptr)
	;	multi(array(call_site_dynamic_ptr)).

:- type call_site_kind
	--->	normal_call
	;	special_call
	;	higher_order_call
	;	method_call
	;	callback.

:- type call_site_kind_and_callee
	--->	normal_call(proc_static_ptr, string)
	;	special_call
	;	higher_order_call
	;	method_call
	;	callback.

:- type call_site_callees
	--->	call_site_callees(
			list(proc_dynamic_ptr)
		).

:- type call_site_caller
	--->	call_site_caller(
			call_site_static_ptr
		).

%-----------------------------------------------------------------------------%

:- type [A | B] == list(A).
:- type [] ---> [].
:- type (A -> B) == map(A, B).

%:- include_module deep:browse.
:- include_module deep:array.
:- include_module deep:cliques.
:- include_module deep:io.
:- include_module deep:server.
:- include_module deep:startup.
:- include_module deep:util.
:- include_module deep:globals.

%:- import_module deep:browse.
:- import_module deep:array.
:- import_module deep:cliques.
:- import_module deep:io.
:- import_module deep:server.
:- import_module deep:startup.
:- import_module deep:globals.

main -->
	stderr_stream(StdErr),
	io__report_stats,
	write_string(StdErr, "  Handling options...\n"),
	{ map__init(Globs0) },
	io__command_line_arguments(Args0),
	{ getopt__process_options(option_ops(short, long, defaults),
		Args0, _Args, MaybeOptions) },
	(
		{ MaybeOptions = ok(Options) },
		{ set_global(Globs0, options, options(Options)) = Globs1 },
		main2(Globs1)
	;
		{ MaybeOptions = error(Msg) },
		io__set_exit_status(1),
		format(StdErr, "error parsing options: %s\n", [s(Msg)])
	).

:- pred main2(globals::in, io__state::di, io__state::uo) is cc_multi.

main2(Globals) -->
	stderr_stream(StdErr),
	io__report_stats,
	write_string(StdErr, "  Reading graph data...\n"),
	{ get_global(Globals, options) = options(Options) },
	( { map__lookup(Options, data_file, maybe_string(yes(FileName0))) } ->
		{ FileName = FileName0 }
	;
		{ FileName = "Deep.data" }
	),
	read_call_graph(FileName, Res),
	write_string(StdErr, "  Done.\n"),
	io__report_stats,
	(
		{ Res = ok(InitialDeep) },
		( { map__search(Options, server, string(Machine)) } ->
			startup(Machine, FileName, InitialDeep, Deep),
			write_string(StdErr, "Done.\n"),
			{ array_foldl(sum_all_csd_quanta,
				Deep ^ call_site_dynamics, 0, Total) },
			format(StdErr, "Total quanta %d\n", [i(Total)]),
			main3(Globals, Deep)
		;
			io__set_exit_status(1),
			io__write_string(StdErr, "bad server name option\n")
		)
	;
		{ Res = error(Err) },
		io__set_exit_status(1),
		format(StdErr, "%s\n", [s(Err)])
	).

:- pred sum_all_csd_quanta(int::in, call_site_dynamic::in, int::in, int::out)
	is det.

sum_all_csd_quanta(_, call_site_dynamic(_, _, OwnPI), Sum0,
	Sum0 + quanta(OwnPI)).

:- pred main3(globals::in, deep::in, io__state::di, io__state::uo) is cc_multi.

main3(Globals, Deep) -->
	{ get_global(Globals, options) = options(Options) },
	( { map__search(Options, dump, bool(yes)) } ->
		dump_graph(Deep)
	;
		[]
	),
	%( { search(Options, dot, bool(yes)) } ->
	%	{ getopt__lookup_int_option(Options, depth, Depth) },
	%	deep2dot("Deep.dot", Depth, Deep)
	%;
	%	[]
	%),
	(
		{ map__search(Options, test, bool(Test)) },
		{ Test = yes },
		{ map__search(Options, test_dir, string(TestDir)) },
		{ map__search(Options, test_fields, string(TestFields)) }
	->
		test_server(TestDir, Deep, TestFields)
	;
		{ map__search(Options, timeout, int(TimeOut)) },
		{ map__search(Options, create_pipes, bool(CreatePipes)) },
		{ map__search(Options, debug, bool(Debug)) }
	->
		server(TimeOut, CreatePipes, Debug, Deep)
	;
		io__set_exit_status(1)
	).

%-----------------------------------------------------------------------------%

:- pred require_isnt(pred, string).
:- mode require_isnt((pred) is semidet, in) is det.

require_isnt(Goal, Message) :-
	( call(Goal) ->
		error(Message)
	;
		true
	).

:- pred is_member(T::in, list(T)::in) is semidet.

is_member(Elem, List) :-
	member(Elem, List).

:- pred mlookup(array(T), int, T, string).
:- mode mlookup(in, in, out, in) is det.
:- mode mlookup(array_ui, in, out, in) is det.

mlookup(A, I, T, S) :-
	array__max(A, M),
	( I >= 0, I =< M ->
		array__lookup(A, I, T)
	;
		format("!(0 <= %d <= %d): %s", [i(I), i(M), s(S)], Msg),
		error(Msg)
	).

:- pred child_call_sites(proc_dynamics::in, proc_statics::in,
	proc_dynamic_ptr::in,
	assoc_list(call_site_static_ptr, call_site_array_slot)::out) is det.

child_call_sites(ProcDynamics, ProcStatics, PDPtr, PairedSlots) :-
	PDPtr = proc_dynamic_ptr(PDI),
	% require(array__in_bounds(ProcDynamics, PDI),
	% 	"child_call_sites: PDI not in range"),
	array__lookup(ProcDynamics, PDI, PD),
	PD = proc_dynamic(PSPtr, CSDArray),
	PSPtr = proc_static_ptr(PSI),
	% require(array__in_bounds(ProcStatics, PSI),
	% 	"child_call_sites: PDI not in range"),
	array__lookup(ProcStatics, PSI, PS),
	CSSArray = PS ^ ps_sites,
	array__to_list(CSDArray, CSDSlots),
	array__to_list(CSSArray, CSSSlots),
	assoc_list__from_corresponding_lists(CSSSlots, CSDSlots, PairedSlots).

:- pred flat_call_sites(proc_dynamics::in, proc_dynamic_ptr::in,
	list(call_site_dynamic_ptr)::out) is det.

flat_call_sites(ProcDynamics, PDPtr, CSDPtrs) :-
	( PDPtr = proc_dynamic_ptr(PDI), PDI > 0 ->
		array__lookup(ProcDynamics, PDI, PD),
		PD = proc_dynamic(_PSPtr, CallSiteArray),
		flatten_call_sites(CallSiteArray, CSDPtrs)
	;
		CSDPtrs = []
	).

:- pred flatten_call_sites(array(call_site_array_slot)::in,
	list(call_site_dynamic_ptr)::out) is det.

flatten_call_sites(CallSiteArray, CSDPtrs) :-
	array__to_list(CallSiteArray, CallSites),
	list__foldl((pred(Slot::in, CSDPtrs0::in, CSDPtrs1::out)
		is det :-
	    (
		Slot = normal(CSDPtr),
		CSDPtr = call_site_dynamic_ptr(CSDI),
		( CSDI > 0 ->
			CSDPtrs1 = [[CSDPtr] | CSDPtrs0]
		;
			CSDPtrs1 = CSDPtrs0
		)
	    ;
		Slot = multi(PtrArray),
		array__to_list(PtrArray, PtrList0),
		filter((pred(CSDPtr::in) is semidet :-
			CSDPtr = call_site_dynamic_ptr(CSDI),
			CSDI > 0
		), PtrList0, PtrList1),
		CSDPtrs1 = [PtrList1 | CSDPtrs0]
	    )
	), CallSites, [], CSDPtrsList0),
	reverse(CSDPtrsList0, CSDPtrsList),
	condense(CSDPtrsList, CSDPtrs).

% :- pred kids(deep::in, array(clique_ptr)::in, proc_dynamic_ptr::in,	
% 	list(clique_ptr)::out) is det.
% 
% kids(Deep, Index, PDPtr, Kids) :-
% 	( PDPtr = proc_dynamic_ptr(PDI), PDI > 0 ->
% 		array__lookup(Deep ^ proc_dynamics, PDI, PD),
% 		PD = proc_dynamic(_PSPtr, Refs),
% 		solutions((pred(Kid::out) is nondet :-
% 		    array__to_list(Refs, RefList),
% 		    member(Ref, RefList),
% 		    (
% 		    	Ref = normal(CSDPtr),
% 		    	CSDPtr = call_site_dynamic_ptr(CSDI),
% 			CSDI > 0,
% 			array__lookup(Deep ^ call_site_dynamics, CSDI, CSD),
% 			CSD = call_site_dynamic(CPDPtr, _Prof),
% 			CPDPtr = proc_dynamic_ptr(CPDI),
% 			CPDI > 0,
% 		    	array__lookup(Index, CPDI, Kid)
% 		    ;
% 		    	Ref = multi(PtrArray),
% 		    	array__to_list(PtrArray, PtrList),
% 		    	member(CSDPtr, PtrList),
% 		    	CSDPtr = call_site_dynamic_ptr(CSDI),
% 			CSDI > 0,
% 			array__lookup(Deep ^ call_site_dynamics, CSDI, CSD),
% 			CSD = call_site_dynamic(CPDPtr, _Prof),
% 			CPDPtr = proc_dynamic_ptr(CPDI),
% 			CPDI > 0,
% 		    	array__lookup(Index, CPDI, Kid)
% 		    )
% 		), Kids)
% 	;
% 		Kids = []
% 	).

%-----------------------------------------------------------------------------%

:- func dummy_proc_id = proc_id.

dummy_proc_id = user_defined(predicate, "unknown", "unknown", "unknown",
	-1, -1).

:- func main_parent_proc_id = proc_id.

main_parent_proc_id = user_defined(predicate, "mercury_runtime",
	"mercury_runtime", "main_parent", 0, 0).

%-----------------------------------------------------------------------------%
