%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: prog_io_pragma.m.
% Main authors: fjh, dgj.
%
% This module handles the parsing of pragma directives.

:- module prog_io_pragma.

:- interface.

:- import_module prog_data, prog_io_util.
:- import_module list, varset, term.

	% parse the pragma declaration. 
:- pred parse_pragma(module_name, varset, list(term), maybe1(item)).
:- mode parse_pragma(in, in, in, out) is semidet.

:- implementation.

:- import_module prog_io_goal, hlds_pred, term_util, term_errors.
:- import_module string, std_util, bool, require.

parse_pragma(ModuleName, VarSet, PragmaTerms, Result) :-
	(
		% new syntax: `:- pragma foo(...).'
		PragmaTerms = [SinglePragmaTerm],
		SinglePragmaTerm = term__functor(term__atom(PragmaType), 
					PragmaArgs, _),
		parse_pragma_type(ModuleName, PragmaType, PragmaArgs,
				SinglePragmaTerm, VarSet, Result0)
	->
		Result = Result0
	;
		% old syntax: `:- pragma(foo, ...).'
		% XXX we should issue a warning; this syntax is deprecated.
		PragmaTerms = [PragmaTypeTerm | PragmaArgs2],
		PragmaTypeTerm = term__functor(term__atom(PragmaType), [], _),
		parse_pragma_type(ModuleName, PragmaType, PragmaArgs2,
				PragmaTypeTerm, VarSet, Result1)
	->
		Result = Result1
	;
		fail
	).

:- pred parse_pragma_type(module_name, string, list(term), term,
						varset, maybe1(item)).
:- mode parse_pragma_type(in, in, in, in, in, out) is semidet.

parse_pragma_type(_, "source_file", PragmaTerms, ErrorTerm, _VarSet, Result) :-
	( PragmaTerms = [SourceFileTerm] ->
	    (
		SourceFileTerm = term__functor(term__string(SourceFile), [], _)
	    ->
		Result = ok(pragma(source_file(SourceFile)))
	    ;
		Result = error(
		"string expected in `pragma source_file' declaration",
				SourceFileTerm)
	    )
	;
	    Result = error(
		"wrong number of arguments in `pragma source_file' declaration",
			ErrorTerm)
	).

parse_pragma_type(_, "c_header_code", PragmaTerms,
			ErrorTerm, _VarSet, Result) :-
    	(
       	    PragmaTerms = [HeaderTerm]
        ->
	    (
    	        HeaderTerm = term__functor(term__string(HeaderCode), [], _)
	    ->
	        Result = ok(pragma(c_header_code(HeaderCode)))
	    ;
		Result = error("expected string for C header code", HeaderTerm)
	    )
	;
	    Result = error(
"wrong number of arguments in `pragma c_header_code(...) declaration", 
			    ErrorTerm)
        ).

parse_pragma_type(ModuleName, "c_code", PragmaTerms,
			ErrorTerm, VarSet, Result) :-
	(
    	    PragmaTerms = [Just_C_Code_Term]
	->
	    (
		Just_C_Code_Term = term__functor(term__string(Just_C_Code), [],
			_)
	    ->
	        Result = ok(pragma(c_code(Just_C_Code)))
	    ;
		Result = error("expected string for C code", Just_C_Code_Term)
	    )
	;
    	    PragmaTerms = [PredAndVarsTerm, C_CodeTerm]
	->
	    % XXX we should issue a warning; this syntax is deprecated.
	    % Result = error("pragma c_code doesn't say whether it can call mercury", PredAndVarsTerm)
	    MayCallMercury = will_not_call_mercury,
	    parse_pragma_c_code(ModuleName, MayCallMercury, PredAndVarsTerm,
	    		no, C_CodeTerm, VarSet, Result)
	;
    	    PragmaTerms = [PredAndVarsTerm, MayCallMercuryTerm, C_CodeTerm]
	->
	    ( parse_may_call_mercury(MayCallMercuryTerm, MayCallMercury) ->
	        parse_pragma_c_code(ModuleName, MayCallMercury, PredAndVarsTerm,
			no, C_CodeTerm, VarSet, Result)
	    ; parse_may_call_mercury(PredAndVarsTerm, MayCallMercury) ->
		% XXX we should issue a warning; this syntax is deprecated
	        parse_pragma_c_code(ModuleName, MayCallMercury,
			MayCallMercuryTerm, no, C_CodeTerm, VarSet, Result)
	    ;
		Result = error("invalid second argument in `:- pragma c_code(..., ..., ...)' declaration -- expecting either `may_call_mercury' or `will_not_call_mercury'",
			MayCallMercuryTerm)
	    )
	;
    	    PragmaTerms = [PredAndVarsTerm, MayCallMercuryTerm,
		SavedVarsTerm, LabelNamesTerm, C_CodeTerm]
	->
	    ( parse_may_call_mercury(MayCallMercuryTerm, MayCallMercury) ->
	        ( parse_ident_list(SavedVarsTerm, SavedVars) ->
	            ( parse_ident_list(LabelNamesTerm, LabelNames) ->
	        	parse_pragma_c_code(ModuleName, MayCallMercury,
				PredAndVarsTerm, yes(SavedVars - LabelNames),
				C_CodeTerm, VarSet, Result)
		    ;
		        Result = error("invalid fourth argument in `:- pragma c_code/5' declaration -- expecting a list of C identifiers",
			   	MayCallMercuryTerm)
		    )
		;
		    Result = error("invalid third argument in `:- pragma c_code/5' declaration -- expecting a list of C identifiers",
			MayCallMercuryTerm)
		)
	    ;
		Result = error("invalid second argument in `:- pragma c_code/3' declaration -- expecting either `may_call_mercury' or `will_not_call_mercury'",
			MayCallMercuryTerm)
	    )
	;
	    Result = error(
	    "wrong number of arguments in `:- pragma c_code' declaration", 
		    ErrorTerm)
	).

parse_pragma_type(_ModuleName, "export", PragmaTerms,
			ErrorTerm, _VarSet, Result) :-
       (
	    PragmaTerms = [PredAndModesTerm, C_FunctionTerm]
       ->
	    (
                PredAndModesTerm = term__functor(_, _, _),
	        C_FunctionTerm = term__functor(term__string(C_Function), [], _)
	    ->
		(
		    PredAndModesTerm = term__functor(term__atom("="),
				[FuncAndArgModesTerm, RetModeTerm], _)
		->
		    parse_qualified_term(FuncAndArgModesTerm,
			"pragma export declaration", FuncAndArgModesResult),  
		    (
		        FuncAndArgModesResult = ok(FuncName, ArgModeTerms),
		        (
		    	    convert_mode_list(ArgModeTerms, ArgModes),
			    convert_mode(RetModeTerm, RetMode)
		        ->
			    list__append(ArgModes, [RetMode], Modes),
			    Result =
			    ok(pragma(export(FuncName, function,
				Modes, C_Function)))
		        ;
	   		    Result = error(
	"expected pragma export(FuncName(ModeList) = Mode, C_Function)",
				PredAndModesTerm)
		        )
		    ;
		        FuncAndArgModesResult = error(Msg, Term),
		        Result = error(Msg, Term)
		    )
		;
		    parse_qualified_term(PredAndModesTerm,
			"pragma export declaration", PredAndModesResult),  
		    (
		        PredAndModesResult = ok(PredName, ModeTerms),
		        (
		    	    convert_mode_list(ModeTerms, Modes)
		        ->
			    Result = 
			    ok(pragma(export(PredName, predicate, Modes,
				C_Function)))
		        ;
	   		    Result = error(
	"expected pragma export(PredName(ModeList), C_Function)",
				PredAndModesTerm)
		        )
		    ;
		        PredAndModesResult = error(Msg, Term),
		        Result = error(Msg, Term)
		    )
		)
	    ;
	    	Result = error(
		     "expected pragma export(PredName(ModeList), C_Function)",
		     PredAndModesTerm)
	    )
	;
	    Result = 
	    	error(
		"wrong number of arguments in `pragma export(...)' declaration",
		ErrorTerm)
       ).

parse_pragma_type(ModuleName, "inline", PragmaTerms,
				ErrorTerm, _VarSet, Result) :-
	parse_simple_pragma(ModuleName, "inline",
		lambda([Name::in, Arity::in, Pragma::out] is det,
			Pragma = inline(Name, Arity)),
		PragmaTerms, ErrorTerm, Result).

parse_pragma_type(ModuleName, "no_inline", PragmaTerms,
				ErrorTerm, _VarSet, Result) :-
	parse_simple_pragma(ModuleName, "no_inline",
		lambda([Name::in, Arity::in, Pragma::out] is det,
			Pragma = no_inline(Name, Arity)),
		PragmaTerms, ErrorTerm, Result).

parse_pragma_type(ModuleName, "memo", PragmaTerms,
			ErrorTerm, _VarSet, Result) :-
	parse_simple_pragma(ModuleName, "memo",
		lambda([Name::in, Arity::in, Pragma::out] is det,
			Pragma = memo(Name, Arity)),
		PragmaTerms, ErrorTerm, Result).

parse_pragma_type(ModuleName, "obsolete", PragmaTerms,
		ErrorTerm, _VarSet, Result) :-
	parse_simple_pragma(ModuleName, "obsolete",
		lambda([Name::in, Arity::in, Pragma::out] is det,
			Pragma = obsolete(Name, Arity)),
		PragmaTerms, ErrorTerm, Result).

	% pragma unused_args should never appear in user programs,
	% only in .opt files.
parse_pragma_type(_ModuleName, "unused_args", PragmaTerms,
			ErrorTerm, _VarSet, Result) :-
	(
		PragmaTerms = [
			PredOrFuncTerm,
			PredNameTerm,
			term__functor(term__integer(Arity), [], _),
			term__functor(term__integer(ProcInt), [], _),
			UnusedArgsTerm
		],
		proc_id_to_int(ProcId, ProcInt),
		(
			PredOrFuncTerm = term__functor(
					term__atom("predicate"), [], _),
			PredOrFunc = predicate
		;
			PredOrFuncTerm = term__functor(
					term__atom("function"), [], _),
			PredOrFunc = function 
		),
		parse_qualified_term(PredNameTerm,
			"predicate name", PredNameResult),
		PredNameResult = ok(PredName, []),
		convert_int_list(UnusedArgsTerm, UnusedArgsResult),
		UnusedArgsResult = ok(UnusedArgs)
	->	
		Result = ok(pragma(unused_args(PredOrFunc, PredName,
				Arity, ProcId, UnusedArgs)))
	;
		Result = error("error in pragma unused_args", ErrorTerm)
	).

parse_pragma_type(ModuleName, "fact_table", PragmaTerms, 
		ErrorTerm, _VarSet, Result) :-
	(
	    PragmaTerms = [PredAndArityTerm, FileNameTerm]
	->
	    (
		PredAndArityTerm = term__functor(term__atom("/"), 
			[PredNameTerm, ArityTerm], _)
	    ->
	    	(
		    parse_qualified_term(ModuleName, PredNameTerm,
			    "pragma fact_table declaration", ok(PredName, [])),
		    ArityTerm = term__functor(term__integer(Arity), [], _)
		->
		    (
			FileNameTerm = 
				term__functor(term__string(FileName), [], _)
		    ->
			Result = ok(pragma(fact_table(PredName, Arity, 
				FileName)))
		    ;
			Result = error(
			    "expected string for fact table filename",
			    FileNameTerm)
		    )
		;
		    Result = error(
		    "expected predname/arity for `pragma fact_table(..., ...)'",
		    	PredAndArityTerm)
		)
	    ;
		Result = error(
		    "expected predname/arity for `pragma fact_table(..., ...)'",
		    PredAndArityTerm)
	    )
	;
	    Result = 
		error(
	"wrong number of arguments in pragma fact_table(..., ...) declaration",
		ErrorTerm)
	).



	% pragma opt_terminates should never appear in user programs,
	% only in .opt files.
parse_pragma_type(ModuleName, "opt_terminates", PragmaTerms, ErrorTerm,
	_VarSet, Result) :-
	
	(
		PragmaTerms = [
			PredOrFuncTerm,
			PredNameTerm,
			term__functor(term__integer(Arity), [], _),
			term__functor(term__integer(ProcInt), [], _),
			ConstTerm,
			TerminatesTerm,
			MaybeUsedArgsTerm
		],
		proc_id_to_int(ProcId, ProcInt),
		(
			PredOrFuncTerm = term__functor(
				term__atom("predicate"), [], _),
			PredOrFunc = predicate
		;
			PredOrFuncTerm = term__functor(
				term__atom("function"), [], _),
			PredOrFunc = function 
		),
		parse_qualified_term(ModuleName, PredNameTerm,
			"predicate name", PredNameResult),
		PredNameResult = ok(PredName, []),
		(	
			ConstTerm = term__functor(
				term__atom("not_set"), [], _),
			Const = not_set
		;
			ConstTerm = term__functor(
				term__atom("infinite"), [], ConstContext),
			Const = inf(ConstContext - imported_pred)
		;
			ConstTerm = term__functor(
				term__atom("set"), [IntTerm], _),
			IntTerm = term__functor(term__integer(Int), [], _),
			Const = set(Int)
		),
		(
			TerminatesTerm = term__functor(
				term__atom("not_set"), [], _),
			Terminates = not_set,
			MaybeError = no
		;
			TerminatesTerm = term__functor(
				term__atom("dont_know"), [], TermContext),
			Terminates = dont_know,
			MaybeError = yes(TermContext - imported_pred)
		;
			TerminatesTerm = term__functor(
				term__atom("yes"), [], _),
			Terminates = yes,
			MaybeError = no
		),
		(
			MaybeUsedArgsTerm = term__functor(
				term__atom("yes"), [BoolListTerm], _),
			convert_bool_list(BoolListTerm, BoolList),
			MaybeUsedArgs = yes(BoolList)
		;
			MaybeUsedArgsTerm = term__functor(
				term__atom("no"), [], _),
			MaybeUsedArgs = no
		),
		Termination = term(Const, Terminates, MaybeUsedArgs, 
			MaybeError)
		
	->
		Result = ok(pragma(opt_terminates(PredOrFunc, PredName, Arity,
			ProcId, Termination)))
	;
		Result = error("error in pragma opt_terminates", ErrorTerm)
	).
			
	
	

parse_pragma_type(ModuleName, "terminates", PragmaTerms,
				ErrorTerm, _VarSet, Result) :-
	parse_simple_pragma(ModuleName, "terminates",
		lambda([Name::in, Arity::in, Pragma::out] is det,
			Pragma = terminates(Name, Arity)),
		PragmaTerms, ErrorTerm, Result).

parse_pragma_type(ModuleName, "check_termination", PragmaTerms,
				ErrorTerm, _VarSet, Result) :-
	parse_simple_pragma(ModuleName, "check_termination",
		lambda([Name::in, Arity::in, Pragma::out] is det,
			Pragma = check_termination(Name, Arity)),
		PragmaTerms, ErrorTerm, Result).

:- pred parse_simple_pragma(module_name, string,
			pred(sym_name, int, pragma_type),
			list(term), term, maybe1(item)).
:- mode parse_simple_pragma(in, in, pred(in, in, out) is det,
			in, in, out) is det.

parse_simple_pragma(ModuleName, PragmaType, MakePragma,
				PragmaTerms, ErrorTerm, Result) :-
       (
            PragmaTerms = [PredAndArityTerm]
       ->
	    (
                PredAndArityTerm = term__functor(term__atom("/"), 
	    		[PredNameTerm, ArityTerm], _)
	    ->
		(
		    parse_qualified_term(ModuleName, PredNameTerm, "",
							ok(PredName, [])),
		    ArityTerm = term__functor(term__integer(Arity), [], _)
		->
		    call(MakePragma, PredName, Arity, Pragma),
		    Result = ok(pragma(Pragma))
		;
		    string__append_list(
			["expected predname/arity for `pragma ",
			 PragmaType, "(...)' declaration"], ErrorMsg),
	    	    Result = error(ErrorMsg, PredAndArityTerm)
		)
	    ;
	        string__append_list(["expected predname/arity for `pragma ",
			 PragmaType, "(...)' declaration"], ErrorMsg),
	        Result = error(ErrorMsg, PredAndArityTerm)
	    )
	;
	    string__append_list(["wrong number of arguments in `pragma ",
		 PragmaType, "(...)' declaration"], ErrorMsg),
	    Result = error(ErrorMsg, ErrorTerm)
       ).

%-----------------------------------------------------------------------------%

:- pred parse_may_call_mercury(term, may_call_mercury).
:- mode parse_may_call_mercury(in, out) is semidet.

parse_may_call_mercury(term__functor(term__atom("recursive"), [], _),
	may_call_mercury).
parse_may_call_mercury(term__functor(term__atom("non_recursive"), [], _),
	will_not_call_mercury).
parse_may_call_mercury(term__functor(term__atom("may_call_mercury"), [], _),
	may_call_mercury).
parse_may_call_mercury(term__functor(term__atom("will_not_call_mercury"), [], _),
	will_not_call_mercury).

:- pred parse_ident_list(term, list(string)).
:- mode parse_ident_list(in, out) is semidet.

parse_ident_list(term__functor(term__atom("[]"), [], _), []).
parse_ident_list(term__functor(term__atom("."), [Head, Tail], _),
		[SavedVar | SavedVars]) :-
	% XXX liberalize this
	Head = term__functor(term__atom(SavedVar), [], _),
	parse_ident_list(Tail, SavedVars).

% parse a pragma c_code declaration

:- pred parse_pragma_c_code(module_name, may_call_mercury, term,
	maybe(pair(list(string))), term, varset, maybe1(item)).
:- mode parse_pragma_c_code(in, in, in, in, in, in, out) is det.

parse_pragma_c_code(ModuleName, MayCallMercury, PredAndVarsTerm0, ExtraInfo,
	C_CodeTerm, VarSet, Result) :-
    (
	PredAndVarsTerm0 = term__functor(Const, Terms0, _)
    ->
    	(
	    % is this a function or a predicate?
	    Const = term__atom("="),
	    Terms0 = [FuncAndVarsTerm, FuncResultTerm0]
	->
	    % function
	    PredOrFunc = function,
	    PredAndVarsTerm = FuncAndVarsTerm,
	    FuncResultTerms = [ FuncResultTerm0 ]
	;
	    % predicate
	    PredOrFunc = predicate,
	    PredAndVarsTerm = PredAndVarsTerm0,
	    FuncResultTerms = []
	),
	parse_qualified_term(ModuleName, PredAndVarsTerm,
			"pragma c_code declaration", PredNameResult),
	(
	    PredNameResult = ok(PredName, VarList0),
	    (
	    	PredOrFunc = predicate,
	    	VarList = VarList0
	    ;
	    	PredOrFunc = function,
	    	list__append(VarList0, FuncResultTerms, VarList)
	    ),
	    (
		C_CodeTerm = term__functor(term__string(C_Code), [], _)
	    ->
		parse_pragma_c_code_varlist(VarSet, 
				VarList, PragmaVars, Error),
	        (
		    Error = no,
		    (
			ExtraInfo = no,
		        Result = ok(pragma(c_code(MayCallMercury, PredName,
				PredOrFunc, PragmaVars, VarSet, C_Code)))
		    ;
			ExtraInfo = yes(SavedVars - LabelNames),
		        Result = ok(pragma(c_code(MayCallMercury, PredName,
				PredOrFunc, PragmaVars, SavedVars, LabelNames,
				VarSet, C_Code)))
		    )
	    	;
		    Error = yes(ErrorMessage),
		    Result = error(ErrorMessage, PredAndVarsTerm)
	        )
	    ;
		Result = error("expected string for C code", C_CodeTerm)
	    )
        ;
	    PredNameResult = error(Msg, Term),
	    Result = error(Msg, Term)
	)
    ;
	Result = error("unexpected variable in pragma(c_code, ...)",
						PredAndVarsTerm0)
    ).

	% parse the variable list in the pragma c code declaration.
	% The final argument is 'no' for no error, or 'yes(ErrorMessage)'.
:- pred parse_pragma_c_code_varlist(varset, list(term), list(pragma_var), 
	maybe(string)).
:- mode parse_pragma_c_code_varlist(in, in, out, out) is det.

parse_pragma_c_code_varlist(_, [], [], no).
parse_pragma_c_code_varlist(VarSet, [V|Vars], PragmaVars, Error):-
	(
		V = term__functor(term__atom("::"), [VarTerm, ModeTerm], _),
		VarTerm = term__variable(Var)
	->
		(
			varset__search_name(VarSet, Var, VarName)
		->
			(
				convert_mode(ModeTerm, Mode)
			->
				P = (pragma_var(Var, VarName, Mode)),
				parse_pragma_c_code_varlist(VarSet, 
					Vars, PragmaVars0, Error),
				PragmaVars = [P|PragmaVars0]
			;
				PragmaVars = [],
				Error = yes("unknown mode in pragma c_code")
			)
		;
			% if the variable wasn't in the varset it must be an
			% underscore variable.
			PragmaVars = [],	% return any old junk for that.
			Error = yes(
"sorry, not implemented: anonymous `_' variable in pragma c_code")
		)
	;
		PragmaVars = [],	% return any old junk in PragmaVars
		Error = yes("arguments not in form 'Var :: mode'")
	).

:- pred convert_int_list(term::in, maybe1(list(int))::out) is det.

convert_int_list(term__variable(V),
			error("variable in int list", term__variable(V))).
convert_int_list(term__functor(Functor, Args, Context), Result) :-
	( 
		Functor = term__atom("."),
		Args = [term__functor(term__integer(Int), [], _), RestTerm]
	->	
		convert_int_list(RestTerm, RestResult),
		(
			RestResult = ok(List0),
			Result = ok([Int | List0])
		;
			RestResult = error(_, _),
			Result = RestResult
		)
	;
		Functor = term__atom("[]"),
		Args = []
	->
		Result = ok([])
	;
		Result = error("error in int list",
				term__functor(Functor, Args, Context))
	).

:- pred convert_bool_list(term::in, list(bool)::out) is semidet.

convert_bool_list(term__functor(Functor, Args, _), Bools) :-
	(
		Functor = term__atom("."),
		Args = [term__functor(AtomTerm, [], _), RestTerm],
		( 
			AtomTerm = term__atom("yes"),
			Bool = yes
		;
			AtomTerm = term__atom("no"),
			Bool = no
		),
		convert_bool_list(RestTerm, RestList),
		Bools = [ Bool | RestList ]
	;
		Functor = term__atom("[]"),
		Args = [],
		Bools = []
	).
