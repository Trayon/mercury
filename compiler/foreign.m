%-----------------------------------------------------------------------------%
% Copyright (C) 2000-2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% This module defines predicates for interfacing with foreign languages.
% In particular, this module supports interfacing with with languages
% other than the target of compilation.  

% Main authors: trd, dgj.
% Parts of this code were originally written by dgj, and have since been
% moved here.

%-----------------------------------------------------------------------------%

:- module foreign.

:- interface.

:- import_module prog_data.
:- import_module hlds_module, hlds_pred.
:- import_module llds.

:- import_module list.

	% Filter the decls for the given foreign language. 
	% The first return value is the list of matches, the second is
	% the list of mis-matches.
:- pred foreign__filter_decls(foreign_language, foreign_decl_info,
		foreign_decl_info, foreign_decl_info).
:- mode foreign__filter_decls(in, in, out, out) is det.

	% Filter the bodys for the given foreign language. 
	% The first return value is the list of matches, the second is
	% the list of mis-matches.
:- pred foreign__filter_bodys(foreign_language, foreign_body_info,
		foreign_body_info, foreign_body_info).
:- mode foreign__filter_bodys(in, in, out, out) is det.

	% Given some foreign code, generate some suitable proxy code for 
	% calling the code via the given language. 
	% This might mean, for example, generating a call to a
	% forwarding function in C.
	% The foreign language argument specifies which language is the
	% target language, the other inputs are the name, types, input
	% variables and so on for a piece of pragma foreign code. 
	% The outputs are the new attributes and implementation for this
	% code.
	% XXX This implementation is currently incomplete, so in future
	% this interface may change.
:- pred foreign__extrude_pragma_implementation(foreign_language,
		list(pragma_var), sym_name, pred_or_func, prog_context,
		module_info, pragma_foreign_proc_attributes,
		pragma_foreign_code_impl, 
		module_info, pragma_foreign_proc_attributes,
		pragma_foreign_code_impl).
:- mode foreign__extrude_pragma_implementation(in, in, in, in, in,
		in, in, in, out, out, out) is det.

	% make_pragma_import turns pragma imports into pragma foreign_code.
	% Given the pred and proc info for this predicate, the name
	% of the function to import, the context of the import pragma
	% and the module_info, create a pragma_foreign_code_impl
	% which imports the foreign function, and return the varset,
	% pragma_vars, argument types and other information about the
	% generated predicate body.
:- pred foreign__make_pragma_import(pred_info, proc_info, string, prog_context,
	module_info, pragma_foreign_code_impl, prog_varset, 
	list(pragma_var), list(type), arity, pred_or_func).
:- mode foreign__make_pragma_import(in, in, in, in, in,
	out, out, out, out, out, out) is det.

:- implementation.

:- import_module list, map, assoc_list, std_util, string, varset, int.
:- import_module require.

:- import_module hlds_pred, hlds_module, type_util, mode_util.
:- import_module code_model, globals.

foreign__filter_decls(WantedLang, Decls0, LangDecls, NotLangDecls) :-
	list__filter((pred(foreign_decl_code(Lang, _, _)::in) is semidet :-
			WantedLang = Lang),
		Decls0, LangDecls, NotLangDecls).

foreign__filter_bodys(WantedLang, Bodys0, LangBodys, NotLangBodys) :-
	list__filter((pred(foreign_body_code(Lang, _, _)::in) is semidet :-
			WantedLang = Lang),
		Bodys0, LangBodys, NotLangBodys).
	
foreign__extrude_pragma_implementation(TargetLang, _PragmaVars,
		_PredName, _PredOrFunc, _Context,
		ModuleInfo0, Attributes, Impl0, 
		ModuleInfo, NewAttributes, Impl) :-
	foreign_language(Attributes, ForeignLanguage),
	set_foreign_language(Attributes, TargetLang, NewAttributes),
	( TargetLang = c ->
		( ForeignLanguage = managed_cplusplus,
			% This isn't finished yet, and we probably won't
			% implement it for C calling MC++.
			% For C calling normal C++ we would generate a proxy
			% function in C++ (implemented in a piece of C++
			% body code) with C linkage, and import that
			% function.
			% The backend would spit the C++ body code into
			% a separate file.
			% The code would look a little like this:
			/*
			NewName = make_pred_name(ForeignLanguage, PredName),
			( PredOrFunc = predicate ->
				ReturnCode = ""
			;
				ReturnCode = "ReturnVal = "
			),
			C_ExtraCode = "Some Extra Code To Run",
			create_pragma_import_c_code(PragmaVars, ModuleInfo0,
				"", VarString),
			module_add_foreign_body_code(cplusplus, 
				C_ExtraCode, Context, ModuleInfo0, ModuleInfo),
			Impl = import(NewName, ReturnCode, VarString, no)
			*/
			error("unimplemented: calling MC++ foreign code from C backend")

				
		; ForeignLanguage = csharp,
			error("unimplemented: calling C# foreign code from C backend")
		; ForeignLanguage = il,
			error("unimplemented: calling IL foreign code from C backend")
		; ForeignLanguage = c,
			Impl = Impl0,
			ModuleInfo = ModuleInfo0
		)
	; TargetLang = managed_cplusplus ->
			% Don't do anything - C and MC++ are embedded
			% inside MC++ without any changes.
		( ForeignLanguage = managed_cplusplus,
			Impl = Impl0,
			ModuleInfo = ModuleInfo0
		; ForeignLanguage = csharp,
			error("unimplemented: calling C# foreign code from MC++ backend")
		; ForeignLanguage = il,
			error("unimplemented: calling IL foreign code from MC++ backend")
		; ForeignLanguage = c,
			Impl = Impl0,
			ModuleInfo = ModuleInfo0
		)
	; TargetLang = csharp ->
		( ForeignLanguage = managed_cplusplus,
			error("unimplemented: calling MC++ foreign code from MC++ backend")
		; ForeignLanguage = csharp,
			Impl = Impl0,
			ModuleInfo = ModuleInfo0
		; ForeignLanguage = c,
			error("unimplemented: calling C foreign code from MC++ backend")
		; ForeignLanguage = il,
			error("unimplemented: calling IL foreign code from MC++ backend")
		)
	; TargetLang = il ->
		( ForeignLanguage = managed_cplusplus,
			error("unimplemented: calling MC++ foreign code from IL backend")
		; ForeignLanguage = csharp,
			error("unimplemented: calling C# foreign code from MC++ backend")
		; ForeignLanguage = c,
			error("unimplemented: calling C foreign code from MC++ backend")
		; ForeignLanguage = il,
			Impl = Impl0,
			ModuleInfo = ModuleInfo0
		)
	;
		error("extrude_pragma_implementation: unsupported foreign language")
	).

	% XXX we haven't implemented these functions yet.
	% What is here is only a guide
:- func make_pred_name(foreign_language, sym_name) = string.
make_pred_name(Lang, SymName) = 
	"mercury_" ++ simple_foreign_language_string(Lang) ++ "__" ++ 
		make_pred_name_rest(Lang, SymName).

:- func make_pred_name_rest(foreign_language, sym_name) = string.
make_pred_name_rest(c, _SymName) = "some_c_name".
make_pred_name_rest(managed_cplusplus, qualified(ModuleSpec, Name)) = 
	make_pred_name_rest(managed_cplusplus, ModuleSpec) ++ "__" ++ Name.
make_pred_name_rest(managed_cplusplus, unqualified(Name)) = Name.
make_pred_name_rest(csharp, _SymName) = "some_csharp_name".
make_pred_name_rest(il, _SymName) = "some_il_name".


make_pragma_import(PredInfo, ProcInfo, C_Function, Context,
		ModuleInfo, PragmaImpl, VarSet, PragmaVars, ArgTypes, 
		Arity, PredOrFunc) :-
	%
	% lookup some information we need from the pred_info and proc_info
	%
	pred_info_get_is_pred_or_func(PredInfo, PredOrFunc),
	pred_info_arg_types(PredInfo, ArgTypes),
	proc_info_argmodes(ProcInfo, Modes),
	proc_info_interface_code_model(ProcInfo, CodeModel),

	%
	% Build a list of argument variables, together with their
	% names, modes, and types.
	%
	varset__init(VarSet0),
	list__length(Modes, Arity),
	varset__new_vars(VarSet0, Arity, Vars, VarSet),
	create_pragma_vars(Vars, Modes, 0, PragmaVars),
	assoc_list__from_corresponding_lists(PragmaVars, ArgTypes,
			PragmaVarsAndTypes),

	%
	% Construct parts of the C_code string for calling a C_function.
	% This C code fragment invokes the specified C function
	% with the appropriate arguments from the list constructed
	% above, passed in the appropriate manner (by value, or by
	% passing the address to simulate pass-by-reference), and
	% assigns the return value (if any) to the appropriate place.
	% As this phase occurs before polymorphism, we don't know about
	% the type-infos yet.  polymorphism.m is responsible for adding
	% the type-info arguments to the list of variables.
	%
	handle_return_value(CodeModel, PredOrFunc, PragmaVarsAndTypes,
			ModuleInfo, ArgPragmaVarsAndTypes, Return),
	assoc_list__keys(ArgPragmaVarsAndTypes, ArgPragmaVars),
	create_pragma_import_c_code(ArgPragmaVars, ModuleInfo,
			"", Variables),

	%
	% Make an import implementation
	%
	PragmaImpl = import(C_Function, Return, Variables, yes(Context)).

%
% handle_return_value(CodeModel, PredOrFunc, Args0, M, Args, C_Code0):
%	Figures out what to do with the C function's return value,
%	based on Mercury procedure's code model, whether it is a predicate
%	or a function, and (if it is a function) the type and mode of the
%	function result.  Constructs a C code fragment `C_Code0' which
%	is a string of the form "<Something> =" that assigns the return
%	value to the appropriate place, if there is a return value,
%	or is an empty string, if there is no return value.
%	Returns in Args all of Args0 that must be passed as arguments
%	(i.e. all of them, or all of them except the return value).
%
:- pred handle_return_value(code_model, pred_or_func,
		assoc_list(pragma_var, type), module_info,
		assoc_list(pragma_var, type), string).
:- mode handle_return_value(in, in, in, in, out, out) is det.

handle_return_value(CodeModel, PredOrFunc, Args0, ModuleInfo, Args, C_Code0) :-
	( CodeModel = model_det,
		(
			PredOrFunc = function,
			pred_args_to_func_args(Args0, Args1, RetArg),
			RetArg = pragma_var(_, RetArgName, RetMode) - RetType,
			mode_to_arg_mode(ModuleInfo, RetMode, RetType,
				RetArgMode),
			RetArgMode = top_out,
			\+ type_util__is_dummy_argument_type(RetType)
		->
			string__append(RetArgName, " = ", C_Code0),
			Args2 = Args1
		;
			C_Code0 = "",
			Args2 = Args0
		)
	; CodeModel = model_semi,
		% we treat semidet functions the same as semidet predicates,
		% which means that for Mercury functions the Mercury return
		% value becomes the last argument, and the C return value
		% is a bool that is used to indicate success or failure.
		C_Code0 = "SUCCESS_INDICATOR = ",
		Args2 = Args0
	; CodeModel = model_non,
		% XXX we should report an error here, rather than generating
		% C code with `#error'...
		C_Code0 = "\n#error ""cannot import nondet procedure""\n",
		Args2 = Args0
	),
	list__filter(include_import_arg(ModuleInfo), Args2, Args).

%
% include_import_arg(M, Arg):
%	Succeeds iff Arg should be included in the arguments of the C
%	function.  Fails if `Arg' has a type such as `io__state' that
%	is just a dummy argument that should not be passed to C.
%
:- pred include_import_arg(module_info, pair(pragma_var, type)).
:- mode include_import_arg(in, in) is semidet.

include_import_arg(ModuleInfo, pragma_var(_Var, _Name, Mode) - Type) :-
	mode_to_arg_mode(ModuleInfo, Mode, Type, ArgMode),
	ArgMode \= top_unused,
	\+ type_util__is_dummy_argument_type(Type).

%
% create_pragma_vars(Vars, Modes, ArgNum0, PragmaVars):
%	given list of vars and modes, and an initial argument number,
%	allocate names to all the variables, and
%	construct a single list containing the variables, names, and modes.
%
:- pred create_pragma_vars(list(prog_var), list(mode), int, list(pragma_var)).
:- mode create_pragma_vars(in, in, in, out) is det.

create_pragma_vars([], [], _Num, []).

create_pragma_vars([Var|Vars], [Mode|Modes], ArgNum0,
		[PragmaVar | PragmaVars]) :-
	%
	% Figure out a name for the C variable which will hold this argument
	%
	ArgNum is ArgNum0 + 1,
	string__int_to_string(ArgNum, ArgNumString),
	string__append("Arg", ArgNumString, ArgName),

	PragmaVar = pragma_var(Var, ArgName, Mode),

	create_pragma_vars(Vars, Modes, ArgNum, PragmaVars).

create_pragma_vars([_|_], [], _, _) :-
	error("create_pragma_vars: length mis-match").
create_pragma_vars([], [_|_], _, _) :-
	error("create_pragma_vars: length mis-match").

%
% create_pragma_import_c_code(PragmaVars, M, C_Code0, C_Code):
%	This predicate creates the C code fragments for each argument
%	in PragmaVars, and appends them to C_Code0, returning C_Code.
%
:- pred create_pragma_import_c_code(list(pragma_var), module_info,
				string, string).
:- mode create_pragma_import_c_code(in, in, in, out) is det.

create_pragma_import_c_code([], _ModuleInfo, C_Code, C_Code).

create_pragma_import_c_code([PragmaVar | PragmaVars], ModuleInfo,
		C_Code0, C_Code) :-
	PragmaVar = pragma_var(_Var, ArgName, Mode),

	%
	% Construct the C code fragment for passing this argument,
	% and append it to C_Code0.
	% Note that C handles output arguments by passing the variable'
	% address, so if the mode is output, we need to put an `&' before
	% the variable name.
	%
	( mode_is_output(ModuleInfo, Mode) ->
		string__append(C_Code0, "&", C_Code1)
	;
		C_Code1 = C_Code0
	),
	string__append(C_Code1, ArgName, C_Code2),
	( PragmaVars \= [] ->
		string__append(C_Code2, ", ", C_Code3)
	;
		C_Code3 = C_Code2
	),

	create_pragma_import_c_code(PragmaVars, ModuleInfo, C_Code3, C_Code).


