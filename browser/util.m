%---------------------------------------------------------------------------%
% Copyright (C) 1998-2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%

:- module mdb__util.

:- interface.

:- import_module list, string, io.

% The stuff defined below is similar to types goal_path and trace_port
% defined in modules compiler/hlds_goal.m and compiler/trace.m.
% This enumeration must be EXACTLY the same as the MR_trace_port enum in
% runtime/mercury_trace_base.h, and in the same order, since the code
% assumes the representation is the same.

:- type trace_port_type
	--->	call
	;	exit
	;	redo
	;	fail
	;	exception
	;	ite_cond
	;	ite_then
	;	ite_else
	;	neg_enter
	;	neg_success
	;	neg_failure
	;	disj
	;	switch
	;	nondet_pragma_first
	;	nondet_pragma_later
	.

% This enumeration must be EXACTLY the same as the MR_PredFunc enum in
% runtime/mercury_stack_layout.h, and in the same order, since the code
% assumes the representation is the same.

:- type pred_or_func
	--->	predicate
	;	function.

:- type goal_path_string == string.

	% Get user input via the same method used by the internal
	% debugger.
:- pred util__trace_getline(string, io__result(string), io__state,
		io__state).
:- mode util__trace_getline(in, out, di, uo) is det.

:- pred util__trace_getline(string, io__result(string), io__input_stream,
		io__output_stream, io__state, io__state).
:- mode util__trace_getline(in, out, in, in, di, uo) is det.

	% trace_get_command is similar to trace_getline except that it
	% breaks lines into semicolon separated commands, and replaces
	% EOF with the command 'quit'.
:- pred util__trace_get_command(string, string, io__state, io__state).
:- mode util__trace_get_command(in, out, di, uo) is det.

:- pred util__trace_get_command(string, string, io__input_stream,
		io__output_stream, io__state, io__state).
:- mode util__trace_get_command(in, out, in, in, di, uo) is det.

:- pred util__zip_with(pred(T1, T2, T3), list(T1), list(T2), list(T3)).
:- mode util__zip_with(pred(in, in, out) is det, in, in, out) is det.

	% Apply predicate to argument repeatedly until the result
	% remains the same.
:- pred util__limit(pred(list(T), list(T)), list(T), list(T)).
:- mode util__limit(pred(in,out) is det, in, out) is det.

%---------------------------------------------------------------------------%
:- implementation.

:- import_module int, require.

util__trace_getline(Prompt, Result) -->
	io__input_stream(MdbIn),
	io__output_stream(MdbOut),
	util__trace_getline(Prompt, Result, MdbIn, MdbOut).

:- pragma promise_pure(util__trace_getline/6).

util__trace_getline(Prompt, Result, MdbIn, MdbOut) -->
	{
		impure call_trace_getline(MdbIn, MdbOut, Prompt, Line)
	->
		Result = ok(Line)
	;
		Result = eof
	}.

:- impure pred call_trace_getline(input_stream, output_stream, string, string).
:-        mode call_trace_getline(in, in, in, out) is semidet.

:- pragma c_header_code("
	#include ""mercury_wrapper.h""
	#include ""mercury_string.h""
	#include ""mercury_trace_base.h""
	#include ""mercury_trace_internal.h""
	#include ""mercury_library_types.h""
").

:- pragma c_code(call_trace_getline(MdbIn::in, MdbOut::in, Prompt::in,
			Line::out),
	[will_not_call_mercury],
	"
		char		*line;
		MercuryFile	*mdb_in = (MercuryFile *) MdbIn;
		MercuryFile	*mdb_out = (MercuryFile *) MdbOut;

		if (MR_address_of_trace_getline != NULL) {
			line = (*MR_address_of_trace_getline)((char *) Prompt,
					MR_file(*mdb_in), MR_file(*mdb_out));
		} else {
			MR_tracing_not_enabled();
			/* not reached */
		}

		if (line == NULL) {
			SUCCESS_INDICATOR = FALSE;
		} else {
			MR_make_aligned_string_copy(Line, line);
			MR_free(line);
			SUCCESS_INDICATOR = TRUE;
		}
	"
).

util__trace_get_command(Prompt, Result) -->
	io__input_stream(MdbIn),
	io__output_stream(MdbOut),
	util__trace_get_command(Prompt, Result, MdbIn, MdbOut).

:- pragma c_code(util__trace_get_command(Prompt::in, Line::out, MdbIn::in,
			MdbOut::in, State0::di, State::uo),
	[will_not_call_mercury],
	"
		char		*line;
		MercuryFile	*mdb_in = (MercuryFile *) MdbIn;
		MercuryFile	*mdb_out = (MercuryFile *) MdbOut;

		if (MR_address_of_trace_getline != NULL) {
			line = (*MR_address_of_trace_get_command)(
					(char *) Prompt,
					MR_file(*mdb_in), MR_file(*mdb_out));
		} else {
			MR_tracing_not_enabled();
			/* not reached */
		}

		MR_make_aligned_string_copy(Line, line);
		MR_free(line);

		State = State0;
	"
).

util__zip_with(Pred, XXs, YYs, Zipped) :-
	( (XXs = [], YYs = []) ->
		Zipped = []
	; (XXs = [X|Xs], YYs = [Y|Ys]) ->
		Pred(X,Y,PXY),
		Zipped = [PXY|Rest],
		util__zip_with(Pred, Xs, Ys, Rest)
	;
		error("zip_with: list arguments are of unequal length")
	).

util__limit(Pred, Xs, Ys) :-
	Pred(Xs, Zs),
	( Xs = Zs ->
		Ys = Zs
	;
		util__limit(Pred, Zs, Ys)
	).

%---------------------------------------------------------------------------%
