
%-----------------------------------------------------------------------------%
% Copyright (C) 1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
% File: debugger_interface.m
% Authors: fjh, jahier
% Purpose:
%	This module provide support routines needed by
%	runtime/mercury_trace_external.c for interfacing to an external
%	(in a different process) debugger, in particular an Opium-style
%	debugger.
%
% This module corresponds to what is called the "Query Handler" in Opium.

:- module debugger_interface.
:- interface. 

% This module exports the following C functions:
%	ML_DI_output_current
%	ML_DI_found_match
%	ML_DI_read_request_from_socket
% These are used by runtime/mercury_trace_external.c.

:- pred dummy_pred_to_avoid_warning_about_nothing_exported is det.

:- implementation.
:- import_module io, require.
:- import_module list, bool, std_util.

dummy_pred_to_avoid_warning_about_nothing_exported.

% The stuff defined below is also defined in modules prog_data, hlds_data.

:- type arity == int.

:- type determinism == int. 
	% encoded as specified in ../runtime/mercury_stack_layout.h
	% and ../compiler/stack_layout.m.

% The stuff defined below is similar to types goal_path and trace_port
% defined in modules compiler/hlds_goal.m and compiler/trace.m.
% This enumeration must be EXACTLY the same as the MR_trace_port enum in
% runtime/mercury_trace.h, and in the same order, since the code assumes
% the representation is the same.

:- type trace_port_type
	--->	call
	;	exit
	;	redo
	;	fail
	;	ite_then
	;	ite_else
	;	disj
	;	switch
	;	nondet_pragma_first
	;	nondet_pragma_later
	.

:- type goal_path_string == string.



% This is known as "debugger_query" in the Opium documentation.
% The debugger_request type is used for request sent
% from the debugger process to the Mercury program being debugged.
% This type would need to be extended to handle spypoints, etc.
:- type debugger_request
	--->	hello_reply		% yes, I'm here

		% A `forward_move' request instructs the debuggee
		% to step forward until we reach a trace event
		% which matches the specified attributes.
	;	forward_move(
			match(event_number),
			match(call_number),
			match(depth_number),
			match(trace_port_type),
			match(string),		% module name
			match(string),		% pred name
			match(arity),
			match(int),		% mode number
			match(determinism),
			match(list(univ)), 	% the arguments
				% XXX we could provide better ways of
				% matching on arguments
			match(goal_path_string)
		)

		% A `current_slots' request instructs the debuggee to
		% retrieve the attributes of the current trace
		% event (except for argument slot) and report them 
		% to the debugger via the socket.
	;	current_slots
		% A `current_vars' request instructs the debuggee to
		% retrieve the list of values and the list of internal
		% names of live variables of the current event and
		% report it to the debugger via the socket.
	;	current_vars    % 
 				% XXX should provide a way of getting
				% just part of the arguments
 				% (to reduce unnecessary socket traffic)
		% A `current_live_var_names' request instructs the debuggee to
		% retrieve the list of internal names of the currently 
		% live variables and a list of their corresponding types.
	;	current_live_var_names
		% A 'current_nth_var' request instructs the debuggee to 
		% retrieve the specified live variable.
	;	current_nth_var(int)
	;	abort_prog
			% just abort the program
	;	no_trace
			% stop tracing, and run the program to completion
	;	error(string)
			% something went wrong when trying to get the
			% next request
	.

:- type event_number == int.
:- type call_number == int.
:- type depth_number == int.


% `match' is called "get status" in the Opium documentation.
% This type defines a unary predicate which determines whether
% or not a particular value will be selected.
:- type match(T)
	--->	nop		% nop: value = -
	;	exact(T)	% exact(X): value = X
	;	neg(T)		% neg(X): value \= X
	;	list(list(T))	% list(L): list__member(value, L)
	;	interval(T,T)	% interval(Low, High): Low =< X, X =< High
	.


% The debugger_response type is used for response sent
% to the debugger process from the Mercury program being debugged.
% This type would need to be extended.
:- type debugger_response
	% sending hello
	--->	hello	% are you there?
	% start the synchronous communication with the debugger
	;	start
	% responses to forward_move
	;	forward_move_match_found
	;	forward_move_match_not_found
	% responses to current 
	% responses to current_slots 
	;	current_slots(
			event_number,
			call_number,
			depth_number,
			trace_port_type,
			string,		% module name
			string,		% pred name
			arity,
			int,		% mode number
			determinism,
			goal_path_string
 		)
	% responses to current_vars
	;	current_vars(list(univ), list(string))
	% reponse to current_nth_var
	;	current_nth_var(univ)
	% responses to current_live_var_names
	;	current_live_var_names(list(string), list(string))
	% response sent when the last event is reached
	;	last_event
	% responses to abort_prog or no_trace
	;	ok
	% responses to anything
	;	error(string)
	.

%-----------------------------------------------------------------------------%
%	send to the debugger (e.g. Opium) the wanted features.

% output_current_slots "ML_DI_output_current_slots":
%	send to the debugger (e.g. Opium) the attributes of the current event
%	except the list of arguments.

:- pragma export(output_current_slots(in, in, in, in, in, in, in, in, in,
		in, in, di, uo), "ML_DI_output_current_slots").
			
:- pred output_current_slots(event_number, call_number, depth_number, 
	trace_port_type, /* module name */ string, /* pred name */ string, 
	arity, /* mode num */ int, determinism, goal_path_string, 
	io__output_stream, io__state, io__state).
:- mode output_current_slots(in, in, in, in, in, in, in, in, in, in, in,
 	di, uo) is det.


output_current_slots(EventNumber, CallNumber, DepthNumber, Port,
	ModuleName, PredName, Arity, ModeNum, Determinism,
	Path, OutputStream) -->
	
	{ CurrentTraceInfo = current_slots(EventNumber, CallNumber, 
		DepthNumber, Port, ModuleName, PredName, Arity,
		ModeNum, Determinism, Path) },
	io__write(OutputStream, CurrentTraceInfo),
	io__print(OutputStream, ".\n"),
	io__flush_output(OutputStream).

% output_current_vars "ML_DI_output_current_vars":
%	send to the debugger the list of the live variables of the current event.

:- pragma export(output_current_vars(in, in, in, di, uo), "ML_DI_output_current_vars").
			
:- pred output_current_vars(list(univ), list(string), 
	io__output_stream, io__state, io__state).
:- mode output_current_vars(in, in, in, di, uo) is det.


output_current_vars(VarList, StringList, OutputStream) -->
		
	{ CurrentTraceInfo = current_vars(VarList, StringList) },
	io__write(OutputStream, CurrentTraceInfo),
	io__print(OutputStream, ".\n"),
	io__flush_output(OutputStream).

% output_current_nth_var "ML_DI_output_current_nth_var":
%	send to the debugger the requested live variable of the current event.

:- pragma export(output_current_nth_var(in, in, di, uo), "ML_DI_output_current_nth_var").
			
:- pred output_current_nth_var(univ, io__output_stream, io__state, io__state).
:- mode output_current_nth_var(in, in, di, uo) is det.


output_current_nth_var(Var, OutputStream) -->
		
	{ CurrentTraceInfo = current_nth_var(Var) },
	io__write(OutputStream, CurrentTraceInfo),
	io__print(OutputStream, ".\n"),
	io__flush_output(OutputStream).


:- pragma export(output_current_live_var_names(in, in, in, di, uo), 
	"ML_DI_output_current_live_var_names").
			
:- pred output_current_live_var_names(list(string), list(string),
	io__output_stream, io__state, io__state).
:- mode output_current_live_var_names(in, in, in, di, uo) is det.


output_current_live_var_names(LiveVarNameList, LiveVarTypeList, 
	OutputStream) -->
		
	{ CurrentTraceInfo = current_live_var_names(
				LiveVarNameList, LiveVarTypeList) },
	io__write(OutputStream, CurrentTraceInfo),
	io__print(OutputStream, ".\n"),
	io__flush_output(OutputStream).

%-----------------------------------------------------------------------------%

:- pragma export(get_var_number(in) = out, "ML_DI_get_var_number").
			
:- func get_var_number(debugger_request) = int.
:- mode get_var_number(in) = out is det.
	% This function is intended to retrieve the integer in 
	% "current_nth_var(int)" requests. 

get_var_number(DebuggerRequest) = VarNumber :-
	(
		DebuggerRequest = current_nth_var(Var)
	->
		Var = VarNumber
	;
		error("get_var_number: not a current_nth_var request")
	).

%-----------------------------------------------------------------------------%

:- pragma export(found_match(in, in, in, in, in, in, in, in, in, in,
			in, in), "ML_DI_found_match").
			
:- pred found_match(event_number, call_number, depth_number, trace_port_type,
	/* module name */ string, /* pred name */ string, arity,
	/* mode num */ int, determinism, /* the arguments */ list(univ),
				% XXX we could provide better ways of
				% matching on arguments
	goal_path_string, debugger_request).
:- mode found_match(in, in, in, in, in, in, in, in, in, in, in, in)
	is semidet.

found_match(EventNumber, CallNumber, DepthNumber, Port, ModuleName, 
		PredName, Arity, ModeNum, Determinism, Args, Path, 
		DebuggerRequest) :-
	(
		DebuggerRequest = forward_move(MatchEventNumber,
			MatchCallNumber, MatchDepthNumber, MatchPort,
			MatchModuleName, MatchPredName, MatchArity,
			MatchModeNum, MatchDeterminism, MatchArgs, MatchPath)
	->
		match(MatchEventNumber, EventNumber),
		match(MatchCallNumber, CallNumber),
		match(MatchDepthNumber, DepthNumber),
		match(MatchPort, Port),
		match(MatchModuleName, ModuleName),
		match(MatchPredName, PredName),
		match(MatchArity, Arity),
		match(MatchModeNum, ModeNum),
		match(MatchDeterminism, Determinism),
		match(MatchArgs, Args),
		match(MatchPath, Path)
	;
		error("found_match: forward_move expected")
	).


% match(MatchPattern, Value) is true iff Value matches the specified pattern.
:- pred match(match(T), T).
:- mode match(in, in) is semidet.

match(nop, _).
match(exact(X), X).
match(neg(X), Y) :- X \= Y.
match(list(L), X) :- list__member(X, L).
match(interval(Low, High), X) :-
	% X >= Low, X =< High
	compare(LE, X, High), 
	(LE = (<) ; LE = (=)),
	compare(GE, X, Low), 
	(GE = (>) ; GE = (=)).


%-----------------------------------------------------------------------------%

:- pred read_request_from_socket(io__input_stream, debugger_request, int,
		io__state, io__state).
			
:- mode read_request_from_socket(in, out, out, di, uo) is det.

:- pragma export(read_request_from_socket(in, out, out, di, uo),
		"ML_DI_read_request_from_socket").

read_request_from_socket(SocketStream, Request, RequestType) -->
	io__read(SocketStream, MaybeRequest),
	( { MaybeRequest = ok(Request0) },
		{ Request = Request0 }
	; { MaybeRequest = error(ErrorMsg, _LineNum) },
		{ Request = error(ErrorMsg) }
	; { MaybeRequest = eof },
		{ Request = error("end of file") }
	),
	{ classify_request(Request, RequestType) }.

	/***********
	% debugging stuff.
	io__stderr_stream(StdErr),
	io__print(StdErr, "debugger_interface: Receive the Request:+"),
	io__print(StdErr, Request),
	io__print(StdErr, "+ from opium\ndebugger_interface: RequestType = "),
	io__print(StdErr, RequestType),
	io__print(StdErr, ".\n").
	***********/



:- pred classify_request(debugger_request, int).
:- mode classify_request(in, out) is det.

% the numbers here should match the definition of
% MR_debugger_request_type in runtime/mercury_trace_external.c.

classify_request(hello_reply, 0).
classify_request(forward_move(_, _, _, _, _, _, _, _, _, _, _), 1).
classify_request(current_vars, 2).
classify_request(current_slots, 3).
classify_request(no_trace, 4).
classify_request(abort_prog, 5).
classify_request(error(_), 6).
classify_request(current_live_var_names, 7).
classify_request(current_nth_var(_), 8).


%-----------------------------------------------------------------------------%
