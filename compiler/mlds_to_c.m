%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% mlds_to_c - Convert MLDS to C/C++ code.
% Main author: fjh.

% TODO:
%	- RTTI for debugging (module_layout, proc_layout, internal_layout)
%	- trail ops
%	- foreign language interfacing and inline target code
%	- packages, classes and inheritance
%	  (currently we just generate all classes as structs)

%-----------------------------------------------------------------------------%

:- module mlds_to_c.
:- interface.

:- import_module mlds.
:- import_module io.

:- pred mlds_to_c__output_mlds(mlds, io__state, io__state).
:- mode mlds_to_c__output_mlds(in, di, uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module ml_util.
:- import_module llds.		% XXX needed for C interface types
:- import_module llds_out.	% XXX needed for llds_out__name_mangle,
				% llds_out__sym_name_mangle,
				% llds_out__make_base_typeclass_info_name,
				% output_c_file_intro_and_grade.
:- import_module rtti.		% for rtti__addr_to_string.
:- import_module rtti_to_mlds.	% for mlds_rtti_type_name.
:- import_module hlds_pred.	% for pred_proc_id.
:- import_module ml_code_util.	% for ml_gen_mlds_var_decl, which is used by
				% the code that handles tail recursion.
:- import_module ml_type_gen.	% for ml_gen_type_name
:- import_module export.	% for export__type_to_type_string
:- import_module globals, options, passes_aux.
:- import_module builtin_ops, c_util, modules.
:- import_module prog_data, prog_out, type_util.

:- import_module bool, int, string, library, list.
:- import_module assoc_list, term, std_util, require.

%-----------------------------------------------------------------------------%

:- type output_type == pred(mlds__type, io__state, io__state).
:- inst output_type = (pred(in, di, uo) is det).

%-----------------------------------------------------------------------------%

mlds_to_c__output_mlds(MLDS) -->
	%
	% We need to use the MLDS package name to compute the header file
	% names, giving e.g. `mercury.io.h', `mercury.time.h' etc.,
	% rather than using just the Mercury module name, which would give
	% just `io.h', `time.h', etc.  The reason for this is that if we
	% don't, then we get name clashes with the standard C header files.
	% For example, `time.h' clashes with the standard <time.h> header.
	%
	% But to keep the Mmake auto-dependencies working, we still
	% want to name the `.c' file based on just the Mercury module
	% name, giving e.g. `time.c', not `mercury.time.c'.
	% Hence the different treatment of SourceFile and HeaderFile below.
	%
	% We write the header file out to <module>.h.tmp and then
	% call `update_interface' to move the <module>.h.tmp file to
	% <module>.h; this avoids updating the timestamp on the `.h'
	% file if it hasn't changed.
	% 
	% We output the source file before outputting the header,
	% since the Mmake dependencies say the header file depends
	% on the source file, and so if we wrote them out in the
	% other order this might lead to unnecessary recompilation
	% next time Mmake is run.
	%
	{ ModuleName = mlds__get_module_name(MLDS) },
	module_name_to_file_name(ModuleName, ".c", yes, SourceFile),
	{ MLDS_ModuleName = mercury_module_name_to_mlds(ModuleName) },
	{ ModuleSymName = mlds_module_name_to_sym_name(MLDS_ModuleName) },
	module_name_to_file_name(ModuleSymName, ".h.tmp", yes, TmpHeaderFile),
	module_name_to_file_name(ModuleSymName, ".h", yes, HeaderFile),
	{ Indent = 0 },
	mlds_output_to_file(SourceFile, mlds_output_src_file(Indent, MLDS)),
	mlds_output_to_file(TmpHeaderFile, mlds_output_hdr_file(Indent, MLDS)),
	update_interface(HeaderFile).
	%
	% XXX at some point we should also handle output of any non-C
	%     foreign code (Ada, Fortran, etc.) to appropriate files.

:- pred mlds_output_to_file(string, pred(io__state, io__state),
				io__state, io__state).
:- mode mlds_output_to_file(in, pred(di, uo) is det, di, uo) is det.

mlds_output_to_file(FileName, Action) -->
	globals__io_lookup_bool_option(verbose, Verbose),
	globals__io_lookup_bool_option(statistics, Stats),
	maybe_write_string(Verbose, "% Writing to file `"),
	maybe_write_string(Verbose, FileName),
	maybe_write_string(Verbose, "'...\n"),
	maybe_flush_output(Verbose),
	io__tell(FileName, Res),
	( { Res = ok } ->
		Action,
		io__told,
		maybe_write_string(Verbose, "% done.\n"),
		maybe_report_stats(Stats)
	;
		maybe_write_string(Verbose, "\n"),
		{ string__append_list(["can't open file `",
			FileName, "' for output."], ErrorMessage) },
		report_error(ErrorMessage)
	).

	%
	% Generate the header file
	%
:- pred mlds_output_hdr_file(indent, mlds, io__state, io__state).
:- mode mlds_output_hdr_file(in, in, di, uo) is det.

mlds_output_hdr_file(Indent, MLDS) -->
	{ MLDS = mlds(ModuleName, ForeignCode, Imports, Defns) },
	mlds_output_hdr_start(Indent, ModuleName), io__nl,
	mlds_output_hdr_imports(Indent, Imports), io__nl,
	mlds_output_c_hdr_decls(MLDS_ModuleName, Indent, ForeignCode), io__nl,
	%
	% The header file must contain _definitions_ of all public types,
	% but only _declarations_ of all public variables, constants,
	% and functions.
	%
	% Note that we don't forward-declare the types here; the
	% forward declarations that we need for types used in function
	% prototypes are generated by mlds_output_type_forward_decls.
	% See the comment in mlds_output_decl.
	% 
	{ list__filter(defn_is_public, Defns, PublicDefns) },
	{ list__filter(defn_is_type, PublicDefns, PublicTypeDefns,
		PublicNonTypeDefns) },
	{ MLDS_ModuleName = mercury_module_name_to_mlds(ModuleName) },
	mlds_output_defns(Indent, MLDS_ModuleName, PublicTypeDefns), io__nl,
	mlds_output_decls(Indent, MLDS_ModuleName, PublicNonTypeDefns), io__nl,
	mlds_output_init_fn_decls(MLDS_ModuleName), io__nl,
	mlds_output_hdr_end(Indent, ModuleName).

:- pred defn_is_public(mlds__defn).
:- mode defn_is_public(in) is semidet.

defn_is_public(Defn) :-
	Defn = mlds__defn(_Name, _Context, Flags, _Body),
	access(Flags) \= private.

:- pred defn_is_type(mlds__defn).
:- mode defn_is_type(in) is semidet.

defn_is_type(Defn) :-
	Defn = mlds__defn(Name, _Context, _Flags, _Body),
	Name = type(_, _).

:- pred defn_is_function(mlds__defn).
:- mode defn_is_function(in) is semidet.

defn_is_function(Defn) :-
	Defn = mlds__defn(Name, _Context, _Flags, _Body),
	Name = function(_, _, _, _).

:- pred defn_is_type_ctor_info(mlds__defn).
:- mode defn_is_type_ctor_info(in) is semidet.

defn_is_type_ctor_info(Defn) :-
	Defn = mlds__defn(_Name, _Context, _Flags, Body),
	Body = mlds__data(Type, _),
	Type = mlds__rtti_type(RttiName),
	RttiName = type_ctor_info.

:- pred defn_is_commit_type_var(mlds__defn).
:- mode defn_is_commit_type_var(in) is semidet.

defn_is_commit_type_var(Defn) :-
	Defn = mlds__defn(_Name, _Context, _Flags, Body),
	Body = mlds__data(Type, _),
	Type = mlds__commit_type.

:- pred mlds_output_hdr_imports(indent, mlds__imports, io__state, io__state).
:- mode mlds_output_hdr_imports(in, in, di, uo) is det.

% XXX currently we assume all imports are source imports,
% i.e. that the header file does not depend on any types
% defined in other header files.
mlds_output_hdr_imports(_Indent, _Imports) --> [].

:- pred mlds_output_src_imports(indent, mlds__imports, io__state, io__state).
:- mode mlds_output_src_imports(in, in, di, uo) is det.

mlds_output_src_imports(Indent, Imports) -->
	list__foldl(mlds_output_src_import(Indent), Imports).

:- pred mlds_output_src_import(indent, mlds__import, io__state, io__state).
:- mode mlds_output_src_import(in, in, di, uo) is det.

mlds_output_src_import(_Indent, Import) -->
	{ SymName = mlds_module_name_to_sym_name(Import) },
	module_name_to_file_name(SymName, ".h", no, HeaderFile),
	io__write_strings(["#include """, HeaderFile, """\n"]).


	%
	% Generate the `.c' file
	%
	% (Calling it the "source" file is a bit of a misnomer,
	% since in our case it is actually the target file,
	% but there's no obvious alternative term to use which
	% also has a clear and concise abbreviation, so never mind...)
	%
:- pred mlds_output_src_file(indent, mlds, io__state, io__state).
:- mode mlds_output_src_file(in, in, di, uo) is det.

mlds_output_src_file(Indent, MLDS) -->
	{ MLDS = mlds(ModuleName, ForeignCode, Imports, Defns) },
	{ library__version(Version) },
	module_name_to_file_name(ModuleName, ".m", no, OrigFileName),
	output_c_file_intro_and_grade(OrigFileName, Version),
	mlds_output_src_start(Indent, ModuleName), io__nl,
	mlds_output_src_imports(Indent, Imports), io__nl,
	mlds_output_c_decls(Indent, ForeignCode), io__nl,
	%
	% The public types have already been defined in the
	% header file, and the public vars, consts, and functions
	% have already been declared in the header file.
	% In the source file, we need to have
	%	#1. definitions of the private types,
	% 	#2. forward-declarations of the private non-types
	%	#3. definitions of all the non-types
	%	#4. initialization functions
	% in that order. 
	% #2 is needed to allow #3 to contain forward references,
	% which can arise for e.g. mutually recursive procedures.
	% #1 is needed since #2 may refer to the types.
	%
	% Note that we don't forward-declare the types here; the
	% forward declarations that we need for types used in function
	% prototypes are generated by mlds_output_type_forward_decls.
	% See the comment in mlds_output_decl.
	% 
	{ list__filter(defn_is_public, Defns, _PublicDefns, PrivateDefns) },
	{ list__filter(defn_is_type, PrivateDefns, PrivateTypeDefns,
		PrivateNonTypeDefns) },
	{ list__filter(defn_is_type, Defns, _TypeDefns, NonTypeDefns) },
	{ list__filter(defn_is_function, NonTypeDefns, FuncDefns) },
	{ list__filter(defn_is_type_ctor_info, NonTypeDefns,
		TypeCtorInfoDefns) },
	{ MLDS_ModuleName = mercury_module_name_to_mlds(ModuleName) },
	mlds_output_defns(Indent, MLDS_ModuleName, PrivateTypeDefns), io__nl,
	mlds_output_decls(Indent, MLDS_ModuleName, PrivateNonTypeDefns), io__nl,

	mlds_output_c_defns(MLDS_ModuleName, Indent, ForeignCode), io__nl,
	mlds_output_defns(Indent, MLDS_ModuleName, NonTypeDefns), io__nl,
	mlds_output_init_fn_defns(MLDS_ModuleName, FuncDefns,
		TypeCtorInfoDefns), io__nl,
	mlds_output_src_end(Indent, ModuleName).

:- pred mlds_output_hdr_start(indent, mercury_module_name,
		io__state, io__state).
:- mode mlds_output_hdr_start(in, in, di, uo) is det.

mlds_output_hdr_start(Indent, ModuleName) -->
	% XXX should spit out an "automatically generated by ..." comment
	mlds_indent(Indent),
	io__write_string("/* :- module "),
	prog_out__write_sym_name(ModuleName),
	io__write_string(". */\n"),
	mlds_indent(Indent),
	io__write_string("/* :- interface. */\n"),
	io__nl,
	mlds_indent(Indent),
	io__write_string("#ifndef MR_HEADER_GUARD_"),
	{ llds_out__sym_name_mangle(ModuleName, MangledModuleName) },
	io__write_string(MangledModuleName),
	io__nl,
	mlds_indent(Indent),
	io__write_string("#define MR_HEADER_GUARD_"),
	io__write_string(MangledModuleName),
	io__nl,
	io__nl,
	mlds_indent(Indent),
	io__write_string("#include ""mercury.h""\n").

:- pred mlds_output_src_start(indent, mercury_module_name,
		io__state, io__state).
:- mode mlds_output_src_start(in, in, di, uo) is det.

mlds_output_src_start(Indent, ModuleName) -->
	% XXX should spit out an "automatically generated by ..." comment
	mlds_indent(Indent),
	io__write_string("/* :- module "),
	prog_out__write_sym_name(ModuleName),
	io__write_string(". */\n"),
	mlds_indent(Indent),
	io__write_string("/* :- implementation. */\n"),
	mlds_output_src_bootstrap_defines, io__nl,
	mlds_output_src_import(Indent,
		mercury_module_name_to_mlds(ModuleName)),
	io__nl.

	%
	% Output any #defines which are required to bootstrap in the hlc
	% grade.
	%
:- pred mlds_output_src_bootstrap_defines(io__state::di, io__state::uo) is det.

mlds_output_src_bootstrap_defines -->
	[].

:- pred mlds_output_hdr_end(indent, mercury_module_name,
		io__state, io__state).
:- mode mlds_output_hdr_end(in, in, di, uo) is det.

mlds_output_hdr_end(Indent, ModuleName) -->
	mlds_indent(Indent),
	io__write_string("#endif /* MR_HEADER_GUARD_"),
	prog_out__write_sym_name(ModuleName),
	io__write_string(" */\n"),
	io__nl,
	mlds_indent(Indent),
	io__write_string("/* :- end_interface "),
	prog_out__write_sym_name(ModuleName),
	io__write_string(". */\n").

:- pred mlds_output_src_end(indent, mercury_module_name,
		io__state, io__state).
:- mode mlds_output_src_end(in, in, di, uo) is det.

mlds_output_src_end(Indent, ModuleName) -->
	mlds_indent(Indent),
	io__write_string("/* :- end_module "),
	prog_out__write_sym_name(ModuleName),
	io__write_string(". */\n").

%-----------------------------------------------------------------------------%

	%
	% Maybe output the function `mercury__<modulename>__init()'.
	% The body of the function consists of calls
	% MR_init_entry(<function>) for each function defined in the
	% module.
	%
:- pred mlds_output_init_fn_decls(mlds_module_name::in,
		io__state::di, io__state::uo) is det.

mlds_output_init_fn_decls(ModuleName) -->
	output_init_fn_name(ModuleName, ""),
	io__write_string(";\n"),
	output_init_fn_name(ModuleName, "_type_tables"),
	io__write_string(";\n"),
	output_init_fn_name(ModuleName, "_debugger"),
	io__write_string(";\n").

:- pred mlds_output_init_fn_defns(mlds_module_name::in, mlds__defns::in,
		mlds__defns::in, io__state::di, io__state::uo) is det.

mlds_output_init_fn_defns(ModuleName, FuncDefns, TypeCtorInfoDefns) -->
	output_init_fn_name(ModuleName, ""),
	io__write_string("\n{\n"),
	io_get_globals(Globals),
	(
		{ need_to_init_entries(Globals) },
		{ FuncDefns \= [] }
	->
		io__write_strings(["\tstatic bool initialised = FALSE;\n",
				"\tif (initialised) return;\n",
				"\tinitialised = TRUE;\n\n"]),
		mlds_output_calls_to_init_entry(ModuleName, FuncDefns)
	;
		[]
	),
	io__write_string("}\n\n"),

	output_init_fn_name(ModuleName, "_type_tables"),
	io__write_string("\n{\n"),
	(
		{ TypeCtorInfoDefns \= [] }
	->
		io__write_strings(["\tstatic bool initialised = FALSE;\n",
				"\tif (initialised) return;\n",
				"\tinitialised = TRUE;\n\n"]),
		mlds_output_calls_to_register_tci(ModuleName,
			TypeCtorInfoDefns)
	;
		[]
	),
	io__write_string("}\n\n"),

	output_init_fn_name(ModuleName, "_debugger"),
	io__write_string("\n{\n"),
	io__write_string(
	    "\tMR_fatal_error(""debugger initialization in MLDS grade"");\n"),
	io__write_string("}\n").

:- pred output_init_fn_name(mlds_module_name::in, string::in,
		io__state::di, io__state::uo) is det.

output_init_fn_name(ModuleName, Suffix) -->
		% Here we ensure that we only get one "mercury__" at the
		% start of the function name.
	{ prog_out__sym_name_to_string(
			mlds_module_name_to_sym_name(ModuleName), "__", 
			ModuleNameString0) },
	{
		string__prefix(ModuleNameString0, "mercury__")
	->
		ModuleNameString = ModuleNameString0
	;
		string__append("mercury__", ModuleNameString0,
				ModuleNameString)
	},
	io__write_string("void "),
	io__write_string(ModuleNameString),
	io__write_string("__init"),
	io__write_string(Suffix),
	io__write_string("(void)").

:- pred need_to_init_entries(globals::in) is semidet.
need_to_init_entries(Globals) :-
	% We only need to output calls to MR_init_entry() if profiling is
	% enabled.  (It would be OK to output the calls regardless, since
	% they will macro-expand to nothing if profiling is not enabled,
	% but for readability of the generated code we prefer not to.)
	( Option = profile_calls
	; Option = profile_time
	; Option = profile_memory
	),
	globals__lookup_bool_option(Globals, Option, yes).

	% Generate calls to MR_init_entry() for the specified functions.
	%
:- pred mlds_output_calls_to_init_entry(mlds_module_name::in, mlds__defns::in,
		io__state::di, io__state::uo) is det.

mlds_output_calls_to_init_entry(_ModuleName, []) --> [].
mlds_output_calls_to_init_entry(ModuleName, [FuncDefn | FuncDefns]) --> 
	{ FuncDefn = mlds__defn(EntityName, _, _, _) },
	io__write_string("\tMR_init_entry("),
	mlds_output_fully_qualified_name(qual(ModuleName, EntityName)),
	io__write_string(");\n"),
	mlds_output_calls_to_init_entry(ModuleName, FuncDefns).

	% Generate calls to MR_register_type_ctor_info() for the specified
	% type_ctor_infos.
	%
:- pred mlds_output_calls_to_register_tci(mlds_module_name::in, mlds__defns::in,
		io__state::di, io__state::uo) is det.

mlds_output_calls_to_register_tci(_ModuleName, []) --> [].
mlds_output_calls_to_register_tci(ModuleName,
		[TypeCtorInfoDefn | TypeCtorInfoDefns]) --> 
	{ TypeCtorInfoDefn = mlds__defn(EntityName, _, _, _) },
	io__write_string("\tMR_register_type_ctor_info(&"),
	mlds_output_fully_qualified_name(qual(ModuleName, EntityName)),
	io__write_string(");\n"),
	mlds_output_calls_to_register_tci(ModuleName, TypeCtorInfoDefns).

%-----------------------------------------------------------------------------%
%
% Foreign language interface stuff
%

:- pred mlds_output_c_hdr_decls(mlds_module_name, indent, mlds__foreign_code,
		io__state, io__state).
:- mode mlds_output_c_hdr_decls(in, in, in, di, uo) is det.

mlds_output_c_hdr_decls(ModuleName, Indent, ForeignCode) -->
	{ ForeignCode = mlds__foreign_code(RevHeaderCode, _RevBodyCode,
		ExportDefns) },
	{ HeaderCode = list__reverse(RevHeaderCode) },
	io__write_list(HeaderCode, "\n", mlds_output_c_hdr_decl(Indent)),
	io__write_string("\n"),
	io__write_list(ExportDefns, "\n",
			mlds_output_pragma_export_decl(ModuleName, Indent)).

:- pred mlds_output_c_hdr_decl(indent,
	foreign_header_code, io__state, io__state).
:- mode mlds_output_c_hdr_decl(in, in, di, uo) is det.

mlds_output_c_hdr_decl(_Indent, Code - Context) -->
	mlds_output_context(mlds__make_context(Context)),
	io__write_string(Code).

:- pred mlds_output_c_decls(indent, mlds__foreign_code,
	io__state, io__state).
:- mode mlds_output_c_decls(in, in, di, uo) is det.

% all of the declarations go in the header file or as c_code
mlds_output_c_decls(_, _) --> [].

:- pred mlds_output_c_defns(mlds_module_name, indent, mlds__foreign_code,
		io__state, io__state).
:- mode mlds_output_c_defns(in, in, in, di, uo) is det.

mlds_output_c_defns(ModuleName, Indent, ForeignCode) -->
	{ ForeignCode = mlds__foreign_code(_RevHeaderCode, RevBodyCode,
		ExportDefns) },
	{ BodyCode = list__reverse(RevBodyCode) },
	io__write_list(BodyCode, "\n", mlds_output_c_defn(Indent)),
	io__write_string("\n"),
	io__write_list(ExportDefns, "\n",
			mlds_output_pragma_export_defn(ModuleName, Indent)).

:- pred mlds_output_c_defn(indent, user_foreign_code,
	io__state, io__state).
:- mode mlds_output_c_defn(in, in, di, uo) is det.

mlds_output_c_defn(_Indent, user_foreign_code(c, Code, Context)) -->
	mlds_output_context(mlds__make_context(Context)),
	io__write_string(Code).

:- pred mlds_output_pragma_export_decl(mlds_module_name, indent,
		mlds__pragma_export, io__state, io__state).
:- mode mlds_output_pragma_export_decl(in, in, in, di, uo) is det.

mlds_output_pragma_export_decl(ModuleName, Indent, PragmaExport) -->
	mlds_output_pragma_export_func_name(ModuleName, Indent, PragmaExport),
	io__write_string(";").

:- pred mlds_output_pragma_export_defn(mlds_module_name, indent,
		mlds__pragma_export, io__state, io__state).
:- mode mlds_output_pragma_export_defn(in, in, in, di, uo) is det.

mlds_output_pragma_export_defn(ModuleName, Indent, PragmaExport) -->
	{ PragmaExport = ml_pragma_export(_C_name, MLDS_Name, MLDS_Signature,
			Context) },
	mlds_output_pragma_export_func_name(ModuleName, Indent, PragmaExport),
	io__write_string("\n"),
	mlds_indent(Context, Indent),
	io__write_string("{\n"),
	mlds_indent(Context, Indent),
	mlds_output_pragma_export_defn_body(ModuleName, MLDS_Name,
				MLDS_Signature),
	io__write_string("}\n").

:- pred mlds_output_pragma_export_func_name(mlds_module_name, indent,
		mlds__pragma_export, io__state, io__state).
:- mode mlds_output_pragma_export_func_name(in, in, in, di, uo) is det.

mlds_output_pragma_export_func_name(ModuleName, Indent,
		ml_pragma_export(C_name, _MLDS_Name, Signature, Context)) -->
	{ Name = qual(ModuleName, export(C_name)) },
	mlds_indent(Context, Indent),
	mlds_output_func_decl_ho(Indent, Name, Context, Signature,
			mlds_output_pragma_export_type(prefix),
			mlds_output_pragma_export_type(suffix)).

:- type locn ---> prefix ; suffix.
:- pred mlds_output_pragma_export_type(locn, mlds__type, io__state, io__state).
:- mode mlds_output_pragma_export_type(in, in, di, uo) is det.

mlds_output_pragma_export_type(suffix, _Type) --> [].
mlds_output_pragma_export_type(prefix, mercury_type(Type, _)) -->
	{ export__type_to_type_string(Type, String) },
	io__write_string(String).
mlds_output_pragma_export_type(prefix, mlds__cont_type(_)) -->
	io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds__commit_type) -->
	io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds__native_bool_type) -->
	io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds__native_int_type) -->
	io__write_string("MR_Integer").
mlds_output_pragma_export_type(prefix, mlds__native_float_type) -->
	io__write_string("MR_Float").
mlds_output_pragma_export_type(prefix, mlds__native_char_type) -->
	io__write_string("MR_Char").
mlds_output_pragma_export_type(prefix, mlds__class_type(_, _, _)) -->
	io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds__array_type(_)) -->
	io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds__ptr_type(Type)) -->
	mlds_output_pragma_export_type(prefix, Type),
	io__write_string(" *").
mlds_output_pragma_export_type(prefix, mlds__func_type(_)) -->
	io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds__generic_type) -->
	io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds__generic_env_ptr_type) -->
	io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds__pseudo_type_info_type) -->
	io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds__rtti_type(_)) -->
	io__write_string("MR_Word").
	

	%
	% Output the definition body for a pragma export
	%
:- pred mlds_output_pragma_export_defn_body(mlds_module_name,
		mlds__qualified_entity_name, func_params, io__state, io__state).
:- mode mlds_output_pragma_export_defn_body(in, in, in, di, uo) is det.

mlds_output_pragma_export_defn_body(ModuleName, FuncName, Signature) -->
	{ Signature = mlds__func_params(Parameters, RetTypes) },

	( { RetTypes = [] } ->
		io__write_string("\t")
	; { RetTypes = [RetType] } ->
		io__write_string("\treturn ("),
		mlds_output_pragma_export_type(prefix, RetType),
		mlds_output_pragma_export_type(suffix, RetType),
		io__write_string(") ")
	;
		{ error("mlds_output_pragma_export: multiple return types") }
	),

	mlds_output_fully_qualified_name(FuncName),
	io__write_string("("),
	io__write_list(Parameters, ", ",
			mlds_output_name_with_cast(ModuleName)),
	io__write_string(");\n").


	%
	% Write out the arguments to the MLDS function.  Note the last
	% in the list of the arguments is the return value, so it must
	% be "&arg"
	%
:- pred write_func_args(mlds_module_name::in, mlds__arguments::in,
		io__state::di, io__state::uo) is det.

write_func_args(_ModuleName, []) -->
	{ error("write_func_args: empty list") }.
write_func_args(_ModuleName, [_Arg]) -->
	io__write_string("&arg").
write_func_args(ModuleName, [Arg | Args]) -->
	{ Args = [_|_] },
	mlds_output_name_with_cast(ModuleName, Arg),
	io__write_string(", "),
	write_func_args(ModuleName, Args).

	%
	% Output a fully qualified name preceded by a cast.
	%
:- pred mlds_output_name_with_cast(mlds_module_name::in,
		pair(mlds__entity_name, mlds__type)::in,
		io__state::di, io__state::uo) is det.

mlds_output_name_with_cast(ModuleName, Name - Type) -->
	io__write_char('('),
	mlds_output_type(Type),
	io__write_string(") "),
	mlds_output_fully_qualified_name(qual(ModuleName, Name)).

	%
	% Generates the signature for det functions in the forward mode.
	%
:- func det_func_signature(mlds__func_params) = mlds__func_params.

det_func_signature(mlds__func_params(Args, _RetTypes)) = Params :-
	list__length(Args, NumArgs),
	NumFuncArgs is NumArgs - 1,
	( list__split_list(NumFuncArgs, Args, InputArgs0, [ReturnArg0]) ->
		InputArgs = InputArgs0,
		ReturnArg = ReturnArg0
	;
		error("det_func_signature: function missing return value?")
	),
	(
		ReturnArg = _ReturnArgName - mlds__ptr_type(ReturnArgType0)
	->
		ReturnArgType = ReturnArgType0
	;
		error("det_func_signature: function return type!")
	),
	Params = mlds__func_params(InputArgs, [ReturnArgType]).
	
%-----------------------------------------------------------------------------%
%
% Code to output declarations and definitions
%


:- pred mlds_output_decls(indent, mlds_module_name, mlds__defns,
		io__state, io__state).
:- mode mlds_output_decls(in, in, in, di, uo) is det.

mlds_output_decls(Indent, ModuleName, Defns) -->
	list__foldl(mlds_output_decl(Indent, ModuleName), Defns).

:- pred mlds_output_defns(indent, mlds_module_name, mlds__defns,
		io__state, io__state).
:- mode mlds_output_defns(in, in, in, di, uo) is det.

mlds_output_defns(Indent, ModuleName, Defns) -->
	{ OutputDefn = mlds_output_defn(Indent, ModuleName) },
	globals__io_lookup_bool_option(gcc_local_labels, GCC_LocalLabels),
	( { GCC_LocalLabels = yes } ->
		%
		% GNU C __label__ declarations must precede
		% ordinary variable declarations.
		%
		{ list__filter(defn_is_commit_type_var, Defns, LabelDecls,
			OtherDefns) },
		list__foldl(OutputDefn, LabelDecls),
		list__foldl(OutputDefn, OtherDefns)
	;
		list__foldl(OutputDefn, Defns)
	).


:- pred mlds_output_decl(indent, mlds_module_name, mlds__defn,
		io__state, io__state).
:- mode mlds_output_decl(in, in, in, di, uo) is det.

mlds_output_decl(Indent, ModuleName, Defn) -->
	{ Defn = mlds__defn(Name, Context, Flags, DefnBody) },
	(
		%
		% ANSI C does not permit forward declarations
		% of enumeration types.  So we just skip those.
		% Currently they're not needed since we don't
		% actually use the enum types.
		%
		{ DefnBody = mlds__class(ClassDefn) },
		{ ClassDefn^kind = mlds__enum }
	->
		[]
	;
		%
		% If we're using --high-level-data, then
		% for function declarations, we need to ensure
		% that we forward-declare any types used in
		% the function parameters.  This is because
		% otherwise, for any struct names whose first
		% occurence is in the function parameters,
		% the scope of such struct names is just that
		% function declaration, which is never right.
		%
		% We generate such forward declarations here,
		% rather than generating type declarations in a
		% header file and #including that header file,
		% because doing the latter would significantly
		% complicate the dependencies (to avoid cyclic
		% #includes, you'd need to generate the type
		% declarations in a different header file than
		% the function declarations).
		%
		globals__io_lookup_bool_option(highlevel_data, HighLevelData),
		(
			{ HighLevelData = yes },
			{ DefnBody = mlds__function(_, Signature, _) }
		->
			{ Signature = mlds__func_params(Parameters,
				_RetTypes) },
			{ assoc_list__values(Parameters, ParamTypes) },
			mlds_output_type_forward_decls(Indent, ParamTypes)
		;
			[]
		),
		%
		% Now output the declaration for this mlds__defn.
		%
		mlds_indent(Context, Indent),
		mlds_output_decl_flags(Flags, forward_decl, Name),
		mlds_output_decl_body(Indent, qual(ModuleName, Name), Context,
			DefnBody)
	).

:- pred mlds_output_type_forward_decls(indent, list(mlds__type),
		io__state, io__state).
:- mode mlds_output_type_forward_decls(in, in, di, uo) is det.

mlds_output_type_forward_decls(Indent, ParamTypes) -->
	%
	% Output forward declarations for all struct types
	% that are contained in the parameter types.
	%
	aggregate(mlds_type_list_contains_type(ParamTypes),
		mlds_output_type_forward_decl(Indent)).

	% mlds_type_list_contains_type(Types, SubType):
	%	True iff the type SubType occurs (directly or indirectly)
	%	in the specified list of Types.
	%
:- pred mlds_type_list_contains_type(list(mlds__type), mlds__type).
:- mode mlds_type_list_contains_type(in, out) is nondet.

mlds_type_list_contains_type(Types, SubType) :-
	list__member(Type, Types),
	mlds_type_contains_type(Type, SubType).

	% mlds_type_contains_type(Type, SubType):
	%	True iff the type Type contains the type SubType.
	%
:- pred mlds_type_contains_type(mlds__type, mlds__type).
:- mode mlds_type_contains_type(in, out) is multi.

mlds_type_contains_type(Type, Type).
mlds_type_contains_type(mlds__array_type(Type), Type).
mlds_type_contains_type(mlds__ptr_type(Type), Type).
mlds_type_contains_type(mlds__func_type(Parameters), Type) :-
	Parameters = mlds__func_params(Arguments, RetTypes),
	( list__member(_Name - Type, Arguments)
	; list__member(Type, RetTypes)
	).

:- pred mlds_output_type_forward_decl(indent, mlds__type,
		io__state, io__state).
:- mode mlds_output_type_forward_decl(in, in, di, uo) is det.

mlds_output_type_forward_decl(Indent, Type) -->
	(
		{
			Type = mlds__class_type(_Name, _Arity, Kind),
			Kind \= mlds__enum,
			ClassType = Type
		;
			Type = mercury_type(MercuryType, user_type),
			type_to_type_id(MercuryType, TypeId, _ArgsTypes),
			ml_gen_type_name(TypeId, ClassName, ClassArity),
			ClassType = mlds__class_type(ClassName, ClassArity,
				mlds__class)
		}
	->
		mlds_indent(Indent),
		mlds_output_type(ClassType),
		io__write_string(";\n")
	;
		[]
	).

:- pred mlds_output_defn(indent, mlds_module_name, mlds__defn,
		io__state, io__state).
:- mode mlds_output_defn(in, in, in, di, uo) is det.

mlds_output_defn(Indent, ModuleName, Defn) -->
	{ Defn = mlds__defn(Name, Context, Flags, DefnBody) },
	( { DefnBody \= mlds__data(_, _) } ->
		io__nl
	;
		[]
	),
	mlds_indent(Context, Indent),
	mlds_output_decl_flags(Flags, definition, Name),
	mlds_output_defn_body(Indent, qual(ModuleName, Name), Context,
			DefnBody).

:- pred mlds_output_decl_body(indent, mlds__qualified_entity_name,
		mlds__context, mlds__entity_defn, io__state, io__state).
:- mode mlds_output_decl_body(in, in, in, in, di, uo) is det.

mlds_output_decl_body(Indent, Name, Context, DefnBody) -->
	(
		{ DefnBody = mlds__data(Type, Initializer) },
		mlds_output_data_decl(Name, Type, initializer_array_size(Initializer))
	;
		{ DefnBody = mlds__function(MaybePredProcId, Signature,
			_MaybeBody) },
		mlds_output_maybe(MaybePredProcId, mlds_output_pred_proc_id),
		mlds_output_func_decl(Indent, Name, Context, Signature)
	;
		{ DefnBody = mlds__class(ClassDefn) },
		mlds_output_class_decl(Indent, Name, ClassDefn)
	),
	io__write_string(";\n").

:- pred mlds_output_defn_body(indent, mlds__qualified_entity_name,
		mlds__context, mlds__entity_defn, io__state, io__state).
:- mode mlds_output_defn_body(in, in, in, in, di, uo) is det.

mlds_output_defn_body(Indent, Name, Context, DefnBody) -->
	(
		{ DefnBody = mlds__data(Type, Initializer) },
		mlds_output_data_defn(Name, Type, Initializer)
	;
		{ DefnBody = mlds__function(MaybePredProcId, Signature,
			MaybeBody) },
		mlds_output_maybe(MaybePredProcId, mlds_output_pred_proc_id),
		mlds_output_func(Indent, Name, Context, Signature, MaybeBody)
	;
		{ DefnBody = mlds__class(ClassDefn) },
		mlds_output_class(Indent, Name, Context, ClassDefn)
	).


%-----------------------------------------------------------------------------%
%
% Code to output type declarations/definitions
%

:- pred mlds_output_class_decl(indent, mlds__qualified_entity_name,
		mlds__class_defn, io__state, io__state).
:- mode mlds_output_class_decl(in, in, in, di, uo) is det.

mlds_output_class_decl(_Indent, Name, ClassDefn) -->
	( { ClassDefn^kind = mlds__enum } ->
		io__write_string("enum "),
		mlds_output_fully_qualified_name(Name),
		io__write_string("_e")
	;
		io__write_string("struct "),
		mlds_output_fully_qualified_name(Name),
		io__write_string("_s")
	).

:- pred mlds_output_class(indent, mlds__qualified_entity_name, mlds__context,
		mlds__class_defn, io__state, io__state).
:- mode mlds_output_class(in, in, in, in, di, uo) is det.

mlds_output_class(Indent, Name, Context, ClassDefn) -->
	%
	% To avoid name clashes, we need to qualify the names of
	% the member constants with the class name.
	% (In particular, this is needed for enumeration constants
	% and for the nested classes that we generate for constructors
	% of discriminated union types.)
	% Here we compute the appropriate qualifier.
	%
	{ Name = qual(ModuleName, UnqualName) },
	{ UnqualName = type(ClassName, ClassArity) ->
		ClassModuleName = mlds__append_class_qualifier(ModuleName,
			ClassName, ClassArity)
	;
		error("mlds_output_enum_constants")
	},

	%
	% Hoist out static members, since plain old C doesn't support
	% static members in structs (except for enumeration constants).
	%
	% XXX this should be conditional: only when compiling to C,
	% not when compiling to C++
	%
	{ ClassDefn = class_defn(Kind, _Imports, BaseClasses, _Implements,
		AllMembers) },
	( { Kind = mlds__enum } ->
		{ StaticMembers = [] },
		{ StructMembers = AllMembers }
	;
		{ list__filter(is_static_member, AllMembers, StaticMembers,
			NonStaticMembers) },
		{ StructMembers = NonStaticMembers }
	),

	%
	% Convert the base classes into member variables,
	% since plain old C doesn't support base classes.
	%
	% XXX this should be conditional: only when compiling to C,
	% not when compiling to C++
	%
	{ list__map_foldl(mlds_make_base_class(Context),
		BaseClasses, BaseDefns, 1, _) },
	{ list__append(BaseDefns, StructMembers, BasesAndMembers) },

	%
	% Output the class declaration and the class members.
	% We treat enumerations specially.
	%
	mlds_output_class_decl(Indent, Name, ClassDefn),
	io__write_string(" {\n"),
	( { Kind = mlds__enum } ->
		mlds_output_enum_constants(Indent + 1, ClassModuleName,
			BasesAndMembers)
	;
		mlds_output_defns(Indent + 1, ClassModuleName,
			BasesAndMembers)
	),
	mlds_indent(Context, Indent),
	io__write_string("};\n"),
	mlds_output_defns(Indent, ClassModuleName, StaticMembers).

:- pred is_static_member(mlds__defn::in) is semidet.

is_static_member(Defn) :-
	Defn = mlds__defn(Name, _, Flags, _),
	(	Name = type(_, _)
	;	per_instance(Flags) = one_copy
	).

	% Convert a base class class_id into a member variable
	% that holds the value of the base class.
	%
:- pred mlds_make_base_class(mlds__context, mlds__class_id, mlds__defn,
		int, int).
:- mode mlds_make_base_class(in, in, out, in, out) is det.

mlds_make_base_class(Context, ClassId, MLDS_Defn, BaseNum0, BaseNum) :-
	BaseName = string__format("base_%d", [i(BaseNum0)]),
	Type = ClassId,
	MLDS_Defn = ml_gen_mlds_var_decl(var(BaseName), Type, Context),
	BaseNum = BaseNum0 + 1.

	% Output the definitions of the enumeration constants
	% for an enumeration type.
	%
:- pred mlds_output_enum_constants(indent, mlds_module_name,
		mlds__defns, io__state, io__state).
:- mode mlds_output_enum_constants(in, in, in, di, uo) is det.

mlds_output_enum_constants(Indent, EnumModuleName, Members) -->
	%
	% Select the enumeration constants from the list of members
	% for this enumeration type, and output them.
	%
	{ EnumConsts = list__filter(is_enum_const, Members) },
	io__write_list(EnumConsts, ",\n",
		mlds_output_enum_constant(Indent, EnumModuleName)),
	io__nl.

	% Test whether one of the members of an mlds__enum class
	% is an enumeration constant.
	%
:- pred is_enum_const(mlds__defn).
:- mode is_enum_const(in) is semidet.

is_enum_const(Defn) :-
	Defn = mlds__defn(_Name, _Context, Flags, _DefnBody),
	constness(Flags) = const.

	% Output the definition of a single enumeration constant.
	%
:- pred mlds_output_enum_constant(indent, mlds_module_name, mlds__defn,
		io__state, io__state).
:- mode mlds_output_enum_constant(in, in, in, di, uo) is det.

mlds_output_enum_constant(Indent, EnumModuleName, Defn) -->
	{ Defn = mlds__defn(Name, Context, _Flags, DefnBody) },
	(
		{ DefnBody = data(Type, Initializer) }
	->
		mlds_indent(Context, Indent),
		mlds_output_fully_qualified_name(qual(EnumModuleName, Name)),
		mlds_output_initializer(Type, Initializer)
	;
		{ error("mlds_output_enum_constant: constant is not data") }
	).

%-----------------------------------------------------------------------------%
%
% Code to output data declarations/definitions
%

:- pred mlds_output_data_decl(mlds__qualified_entity_name, mlds__type,
			initializer_array_size, io__state, io__state).
:- mode mlds_output_data_decl(in, in, in, di, uo) is det.

mlds_output_data_decl(Name, Type, InitializerSize) -->
	mlds_output_data_decl_ho(mlds_output_type_prefix,
			(pred(Tp::in, di, uo) is det -->
				mlds_output_type_suffix(Tp, InitializerSize)),
			Name, Type).

:- pred mlds_output_data_decl_ho(output_type, output_type,
		mlds__qualified_entity_name, mlds__type, io__state, io__state).
:- mode mlds_output_data_decl_ho(in(output_type), in(output_type),
		in, in, di, uo) is det.

mlds_output_data_decl_ho(OutputPrefix, OutputSuffix, Name, Type) -->
	OutputPrefix(Type),
	io__write_char(' '),
	mlds_output_fully_qualified_name(Name),
	OutputSuffix(Type).

:- pred mlds_output_data_defn(mlds__qualified_entity_name, mlds__type,
			mlds__initializer, io__state, io__state).
:- mode mlds_output_data_defn(in, in, in, di, uo) is det.

mlds_output_data_defn(Name, Type, Initializer) -->
	mlds_output_data_decl(Name, Type, initializer_array_size(Initializer)),
	mlds_output_initializer(Type, Initializer),
	io__write_string(";\n").

:- pred mlds_output_maybe(maybe(T), pred(T, io__state, io__state),
		io__state, io__state).
:- mode mlds_output_maybe(in, pred(in, di, uo) is det, di, uo) is det.

mlds_output_maybe(MaybeValue, OutputAction) -->
	( { MaybeValue = yes(Value) } ->
		OutputAction(Value)
	;
		[]
	).

:- pred mlds_output_initializer(mlds__type, mlds__initializer,
		io__state, io__state).
:- mode mlds_output_initializer(in, in, di, uo) is det.

mlds_output_initializer(_Type, Initializer) -->
	( { mlds_needs_initialization(Initializer) = yes } ->
		io__write_string(" = "),
		mlds_output_initializer_body(Initializer)
	;
		[]
	).

:- func mlds_needs_initialization(mlds__initializer) = bool.

mlds_needs_initialization(no_initializer) = no.
mlds_needs_initialization(init_obj(_)) = yes.
mlds_needs_initialization(init_struct([])) = no.
mlds_needs_initialization(init_struct([_|_])) = yes.
mlds_needs_initialization(init_array(_)) = yes.

	% XXX ANSI/ISO C does not allow empty arrays or empty structs;
	% what we do for them here is probably not quite right.
:- pred mlds_output_initializer_body(mlds__initializer, io__state, io__state).
:- mode mlds_output_initializer_body(in, di, uo) is det.

mlds_output_initializer_body(no_initializer) --> [].
mlds_output_initializer_body(init_obj(Rval)) -->
	mlds_output_rval(Rval).
mlds_output_initializer_body(init_struct(FieldInits)) -->
	io__write_string("{\n\t\t"),
	io__write_list(FieldInits, ",\n\t\t", mlds_output_initializer_body),
	io__write_string("}").
mlds_output_initializer_body(init_array(ElementInits)) -->
	io__write_string("{\n\t\t"),
	(
		{ ElementInits = [] }
	->
			% The MS VC++ compiler only generates a symbol, if
			% the array has a known size.
		io__write_string("0")
	;
		io__write_list(ElementInits,
				",\n\t\t", mlds_output_initializer_body)
	),
	io__write_string("}").

%-----------------------------------------------------------------------------%
%
% Code to output function declarations/definitions
%

:- pred mlds_output_pred_proc_id(pred_proc_id, io__state, io__state).
:- mode mlds_output_pred_proc_id(in, di, uo) is det.

mlds_output_pred_proc_id(proc(PredId, ProcId)) -->
	globals__io_lookup_bool_option(auto_comments, AddComments),
	( { AddComments = yes } ->
		io__write_string("/* pred_id: "),
		{ pred_id_to_int(PredId, PredIdNum) },
		io__write_int(PredIdNum),
		io__write_string(", proc_id: "),
		{ proc_id_to_int(ProcId, ProcIdNum) },
		io__write_int(ProcIdNum),
		io__write_string(" */\n")
	;
		[]
	).

:- pred mlds_output_func(indent, qualified_entity_name, mlds__context,
		func_params, maybe(statement), io__state, io__state).
:- mode mlds_output_func(in, in, in, in, in, di, uo) is det.

mlds_output_func(Indent, Name, Context, Signature, MaybeBody) -->
	mlds_output_func_decl(Indent, Name, Context, Signature),
	(
		{ MaybeBody = no },
		io__write_string(";\n")
	;
		{ MaybeBody = yes(Body) },
		io__write_string("\n"),

		mlds_indent(Context, Indent),
		io__write_string("{\n"),

		{ FuncInfo = func_info(Name, Signature) },
		mlds_maybe_output_time_profile_instr(Context, Indent + 1, Name),

		mlds_output_statement(Indent + 1, FuncInfo, Body),

		mlds_indent(Context, Indent),
		io__write_string("}\n")	% end the function
	).

:- pred mlds_output_func_decl(indent, qualified_entity_name, mlds__context,
		func_params, io__state, io__state).
:- mode mlds_output_func_decl(in, in, in, in, di, uo) is det.

mlds_output_func_decl(Indent, QualifiedName, Context, Signature) -->
	mlds_output_func_decl_ho(Indent, QualifiedName, Context, Signature,
			mlds_output_type_prefix, mlds_output_type_suffix).

:- pred mlds_output_func_decl_ho(indent, qualified_entity_name, mlds__context,
		func_params, output_type, output_type, io__state, io__state).
:- mode mlds_output_func_decl_ho(in, in, in, in, in(output_type),
		in(output_type), di, uo) is det.

mlds_output_func_decl_ho(Indent, QualifiedName, Context, Signature,
		OutputPrefix, OutputSuffix) -->
	{ Signature = mlds__func_params(Parameters, RetTypes) },
	( { RetTypes = [] } ->
		io__write_string("void")
	; { RetTypes = [RetType] } ->
		OutputPrefix(RetType)
	;
		io__write_string("\n#error multiple return types\n")
		% { error("mlds_output_func: multiple return types") }
	),
	io__write_char(' '),
	mlds_output_fully_qualified_name(QualifiedName),
	{ QualifiedName = qual(ModuleName, _) },
	mlds_output_params(OutputPrefix, OutputSuffix,
			Indent, ModuleName, Context, Parameters),
	( { RetTypes = [RetType2] } ->
		OutputSuffix(RetType2)
	;
		[]
	).

:- pred mlds_output_params(output_type, output_type,
		indent, mlds_module_name, mlds__context,
		mlds__arguments, io__state, io__state).
:- mode mlds_output_params(in(output_type), in(output_type),
		in, in, in, in, di, uo) is det.

mlds_output_params(OutputPrefix, OutputSuffix, Indent, ModuleName,
		Context, Parameters) -->
	io__write_char('('),
	( { Parameters = [] } ->
		io__write_string("void")
	;
		io__nl,
		io__write_list(Parameters, ",\n",
			mlds_output_param(OutputPrefix, OutputSuffix,
				Indent + 1, ModuleName, Context))
	),
	io__write_char(')').

:- pred mlds_output_param(output_type, output_type,
		indent, mlds_module_name, mlds__context,
		pair(mlds__entity_name, mlds__type), io__state, io__state).
:- mode mlds_output_param(in(output_type), in(output_type),
		in, in, in, in, di, uo) is det.


mlds_output_param(OutputPrefix, OutputSuffix, Indent,
		ModuleName, Context, Name - Type) -->
	mlds_indent(Context, Indent),
	mlds_output_data_decl_ho(OutputPrefix, OutputSuffix,
			qual(ModuleName, Name), Type).

:- pred mlds_output_func_type_prefix(func_params, io__state, io__state).
:- mode mlds_output_func_type_prefix(in, di, uo) is det.

mlds_output_func_type_prefix(Params) -->
	{ Params = mlds__func_params(_Parameters, RetTypes) },
	( { RetTypes = [] } ->
		io__write_string("void")
	; { RetTypes = [RetType] } ->
		mlds_output_type(RetType)
	;
		{ error("mlds_output_func_type_prefix: multiple return types") }
	),
	% Note that mlds__func_type actually corresponds to a
	% function _pointer_ type in C.  This is necessary because
	% function types in C are not first class.
	io__write_string(" (*").

:- pred mlds_output_func_type_suffix(func_params, io__state, io__state).
:- mode mlds_output_func_type_suffix(in, di, uo) is det.

mlds_output_func_type_suffix(Params) -->
	{ Params = mlds__func_params(Parameters, _RetTypes) },
	io__write_string(")"),
	mlds_output_param_types(Parameters).

:- pred mlds_output_param_types(mlds__arguments, io__state, io__state).
:- mode mlds_output_param_types(in, di, uo) is det.

mlds_output_param_types(Parameters) -->
	io__write_char('('),
	( { Parameters = [] } ->
		io__write_string("void")
	;
		io__write_list(Parameters, ", ", mlds_output_param_type)
	),
	io__write_char(')').

:- pred mlds_output_param_type(pair(mlds__entity_name, mlds__type),
		io__state, io__state).
:- mode mlds_output_param_type(in, di, uo) is det.

mlds_output_param_type(_Name - Type) -->
	mlds_output_type(Type).

%-----------------------------------------------------------------------------%
%
% Code to output names of various entities
%

:- pred mlds_output_fully_qualified_name(mlds__qualified_entity_name,
		io__state, io__state).
:- mode mlds_output_fully_qualified_name(in, di, uo) is det.

mlds_output_fully_qualified_name(QualifiedName) -->
	{ QualifiedName = qual(_ModuleName, Name) },
	(
		(
			%
			% don't module-qualify main/2
			%
			{ Name = function(PredLabel, _, _, _) },
			{ PredLabel = pred(predicate, no, "main", 2) }
		;
			%
			% don't module-qualify base_typeclass_infos
			%
			% We don't want to include the module name as part
			% of the name if it is a base_typeclass_info, since
			% we _want_ to cause a link error for overlapping
			% instance decls, even if they are in a different
			% module
			%
			{ Name = data(base_typeclass_info(_, _)) }
		;
			% We don't module qualify pragma export names.
			{ Name = export(_) }
		)
	->
		mlds_output_name(Name)
	;
		mlds_output_fully_qualified(QualifiedName, mlds_output_name)
	).

:- pred mlds_output_fully_qualified_proc_label(mlds__qualified_proc_label,
		io__state, io__state).
:- mode mlds_output_fully_qualified_proc_label(in, di, uo) is det.

mlds_output_fully_qualified_proc_label(QualifiedName) -->
	(
		%
		% don't module-qualify main/2
		%
		{ QualifiedName = qual(_ModuleName, Name) },
		{ Name = PredLabel - _ProcId },
		{ PredLabel = pred(predicate, no, "main", 2) }
	->
		mlds_output_proc_label(Name)
	;
		mlds_output_fully_qualified(QualifiedName,
			mlds_output_proc_label)
	).

:- pred mlds_output_fully_qualified(mlds__fully_qualified_name(T),
		pred(T, io__state, io__state), io__state, io__state).
:- mode mlds_output_fully_qualified(in, pred(in, di, uo) is det,
		di, uo) is det.

mlds_output_fully_qualified(qual(ModuleName, Name), OutputFunc) -->
	{ SymName = mlds_module_name_to_sym_name(ModuleName) },
	{ llds_out__sym_name_mangle(SymName, MangledModuleName) },
	io__write_string(MangledModuleName),
	io__write_string("__"),
	OutputFunc(Name).

:- pred mlds_output_module_name(mercury_module_name, io__state, io__state).
:- mode mlds_output_module_name(in, di, uo) is det.

mlds_output_module_name(ModuleName) -->
	{ llds_out__sym_name_mangle(ModuleName, MangledModuleName) },
	io__write_string(MangledModuleName).

:- pred mlds_output_name(mlds__entity_name, io__state, io__state).
:- mode mlds_output_name(in, di, uo) is det.

% XXX we should avoid appending the arity, modenum, and seqnum
%     if they are not needed.

mlds_output_name(type(Name, Arity)) -->
	{ llds_out__name_mangle(Name, MangledName) },
	io__format("%s_%d", [s(MangledName), i(Arity)]).
mlds_output_name(data(DataName)) -->
	mlds_output_data_name(DataName).
mlds_output_name(function(PredLabel, ProcId, MaybeSeqNum, _PredId)) -->
	mlds_output_pred_label(PredLabel),
	{ proc_id_to_int(ProcId, ModeNum) },
	io__format("_%d", [i(ModeNum)]),
	( { MaybeSeqNum = yes(SeqNum) } ->
		io__format("_%d", [i(SeqNum)])
	;
		[]
	).
mlds_output_name(export(Name)) -->
	io__write_string(Name).

:- pred mlds_output_pred_label(mlds__pred_label, io__state, io__state).
:- mode mlds_output_pred_label(in, di, uo) is det.

mlds_output_pred_label(pred(PredOrFunc, MaybeDefiningModule, Name, Arity)) -->
	( { PredOrFunc = predicate, Suffix = "p" }
	; { PredOrFunc = function, Suffix = "f" }
	),
	{ llds_out__name_mangle(Name, MangledName) },
	io__format("%s_%d_%s", [s(MangledName), i(Arity), s(Suffix)]),
	( { MaybeDefiningModule = yes(DefiningModule) } ->
		io__write_string("_in__"),
		mlds_output_module_name(DefiningModule)
	;
		[]
	).
mlds_output_pred_label(special_pred(PredName, MaybeTypeModule,
		TypeName, TypeArity)) -->
	{ llds_out__name_mangle(PredName, MangledPredName) },
	{ llds_out__name_mangle(TypeName, MangledTypeName) },
	io__write_string(MangledPredName),
	io__write_string("__"),
	( { MaybeTypeModule = yes(TypeModule) } ->
		mlds_output_module_name(TypeModule),
		io__write_string("__")
	;
		[]
	),
	io__write_string(MangledTypeName),
	io__write_string("_"),
	io__write_int(TypeArity).

:- pred mlds_output_data_name(mlds__data_name, io__state, io__state).
:- mode mlds_output_data_name(in, di, uo) is det.

mlds_output_data_name(var(Name)) -->
	mlds_output_mangled_name(Name).
mlds_output_data_name(common(Num)) -->
	io__write_string("common_"),
	io__write_int(Num).
mlds_output_data_name(rtti(RttiTypeId, RttiName)) -->
	{ rtti__addr_to_string(RttiTypeId, RttiName, RttiAddrName) },
	io__write_string(RttiAddrName).
mlds_output_data_name(base_typeclass_info(ClassId, InstanceStr)) -->
        { llds_out__make_base_typeclass_info_name(ClassId, InstanceStr,
		Name) },
	io__write_string(Name).
mlds_output_data_name(module_layout) -->
	{ error("mlds_to_c.m: NYI: module_layout") }.
mlds_output_data_name(proc_layout(_ProcLabel)) -->
	{ error("mlds_to_c.m: NYI: proc_layout") }.
mlds_output_data_name(internal_layout(_ProcLabel, _FuncSeqNum)) -->
	{ error("mlds_to_c.m: NYI: internal_layout") }.
mlds_output_data_name(tabling_pointer(ProcLabel)) -->
	io__write_string("table_for_"),
	mlds_output_proc_label(ProcLabel).

%-----------------------------------------------------------------------------%
%
% Code to output types
%

%
% Because of the joys of C syntax, the code for outputting
% types needs to be split into two parts; first the prefix,
% i.e. the part of the type name that goes before the variable
% name in a variable declaration, and then the suffix, i.e.
% the part which goes after the variable name, e.g. the "[]"
% for array types.
%

:- pred mlds_output_type(mlds__type, io__state, io__state).
:- mode mlds_output_type(in, di, uo) is det.

mlds_output_type(Type) -->
	mlds_output_type_prefix(Type),
	mlds_output_type_suffix(Type).

:- pred mlds_output_type_prefix(mlds__type, io__state, io__state).
:- mode mlds_output_type_prefix(in, di, uo) is det.

mlds_output_type_prefix(mercury_type(Type, TypeCategory)) -->
	mlds_output_mercury_type_prefix(Type, TypeCategory).
mlds_output_type_prefix(mlds__native_int_type)   --> io__write_string("int").
mlds_output_type_prefix(mlds__native_float_type) --> io__write_string("float").
mlds_output_type_prefix(mlds__native_bool_type)  --> io__write_string("bool").
mlds_output_type_prefix(mlds__native_char_type)  --> io__write_string("char").
mlds_output_type_prefix(mlds__class_type(Name, Arity, ClassKind)) -->
	( { ClassKind = mlds__enum } ->
		%
		% We can't just use the enumeration type,
		% since the enumeration type's definition
		% is not guaranteed to be in scope at this point.
		% (Fixing that would be somewhat complicated; it would
		% require writing enum definitions to a separate header file.)
		% Also the enumeration might not be word-sized,
		% which would cause problems for e.g. `std_util:arg/2'.
		% So we just use `MR_Integer', and output the
		% actual enumeration type as a comment.
		%
		io__write_string("MR_Integer /* actually `enum "),
		mlds_output_fully_qualified(Name, mlds_output_mangled_name),
		io__format("_%d_e", [i(Arity)]),
		io__write_string("' */")
	;
		% For struct types it's OK to output an incomplete type,
		% since don't use these types directly, we only
		% use pointers to them.
		io__write_string("struct "),
		mlds_output_fully_qualified(Name, mlds_output_mangled_name),
		io__format("_%d_s", [i(Arity)])
	).
mlds_output_type_prefix(mlds__ptr_type(Type)) -->
	mlds_output_type(Type),
	io__write_string(" *").
mlds_output_type_prefix(mlds__array_type(Type)) -->
	% Here we just output the element type.
	% The "[]" goes in the type suffix.
	mlds_output_type(Type).
mlds_output_type_prefix(mlds__func_type(FuncParams)) -->
	mlds_output_func_type_prefix(FuncParams).
mlds_output_type_prefix(mlds__generic_type) -->
	io__write_string("MR_Box").
mlds_output_type_prefix(mlds__generic_env_ptr_type) -->
	io__write_string("void *").
mlds_output_type_prefix(mlds__pseudo_type_info_type) -->
	io__write_string("MR_PseudoTypeInfo").
mlds_output_type_prefix(mlds__cont_type(ArgTypes)) -->
	( { ArgTypes = [] } ->
		globals__io_lookup_bool_option(gcc_nested_functions,
			GCC_NestedFuncs),
		( { GCC_NestedFuncs = yes } ->
			io__write_string("MR_NestedCont")
		;
			io__write_string("MR_Cont")
		)
	;
		% This case only happens for --nondet-copy-out
		io__write_string("void (*")
	).
mlds_output_type_prefix(mlds__commit_type) -->
	globals__io_lookup_bool_option(gcc_local_labels, GCC_LocalLabels),
	( { GCC_LocalLabels = yes } ->
		io__write_string("__label__")
	;
		io__write_string("jmp_buf")
	).
mlds_output_type_prefix(mlds__rtti_type(RttiName)) -->
	io__write_string("MR_"),
	io__write_string(mlds_rtti_type_name(RttiName)).

:- pred mlds_output_mercury_type_prefix(mercury_type, builtin_type,
		io__state, io__state).
:- mode mlds_output_mercury_type_prefix(in, in, di, uo) is det.

mlds_output_mercury_type_prefix(Type, TypeCategory) -->
	(
		{ TypeCategory = char_type },
		io__write_string("MR_Char")
	;
		{ TypeCategory = int_type },
		io__write_string("MR_Integer")
	;
		{ TypeCategory = str_type },
		io__write_string("MR_String")
	;
		{ TypeCategory = float_type },
		io__write_string("MR_Float")
	;
		{ TypeCategory = polymorphic_type },
		io__write_string("MR_Box")
	;
		{ TypeCategory = tuple_type },
		io__write_string("MR_Tuple")
	;
		{ TypeCategory = pred_type },
		globals__io_lookup_bool_option(highlevel_data, HighLevelData),
		( { HighLevelData = yes } ->
			io__write_string("MR_ClosurePtr")
		;
			io__write_string("MR_Word")
		)
	;
		{ TypeCategory = enum_type },
		mlds_output_mercury_user_type_prefix(Type, TypeCategory)
	;
		{ TypeCategory = user_type },
		mlds_output_mercury_user_type_prefix(Type, TypeCategory)
	).

:- pred mlds_output_mercury_user_type_prefix(mercury_type, builtin_type,
		io__state, io__state).
:- mode mlds_output_mercury_user_type_prefix(in, in, di, uo) is det.

mlds_output_mercury_user_type_prefix(Type, TypeCategory) -->
	globals__io_lookup_bool_option(highlevel_data, HighLevelData),
	( { HighLevelData = yes } ->
		( { type_to_type_id(Type, TypeId, _ArgsTypes) } ->
			{ ml_gen_type_name(TypeId, ClassName, ClassArity) },
			{ TypeCategory = enum_type ->
				MLDS_Type = mlds__class_type(ClassName,
					ClassArity, mlds__enum)
			;
				MLDS_Type = mlds__ptr_type(mlds__class_type(
					ClassName, ClassArity, mlds__class))
			},
			mlds_output_type_prefix(MLDS_Type)
		;
			{ error("mlds_output_mercury_user_type_prefix") }
		)
	;
		% for the --no-high-level-data case,
		% we just treat everything as `MR_Word'
		io__write_string("MR_Word")
	).

:- pred mlds_output_type_suffix(mlds__type, io__state, io__state).
:- mode mlds_output_type_suffix(in, di, uo) is det.

mlds_output_type_suffix(Type) -->
	mlds_output_type_suffix(Type, no_size).

:- type initializer_array_size
	--->	array_size(int)
	;	no_size.	% either the size is unknown,
				% or the data is not an array

:- func initializer_array_size(mlds__initializer) = initializer_array_size.
initializer_array_size(no_initializer) = no_size.
initializer_array_size(init_obj(_)) = no_size.
initializer_array_size(init_struct(_)) = no_size.
initializer_array_size(init_array(Elems)) = array_size(list__length(Elems)).

:- pred mlds_output_type_suffix(mlds__type, initializer_array_size,
		io__state, io__state).
:- mode mlds_output_type_suffix(in, in, di, uo) is det.


mlds_output_type_suffix(mercury_type(_, _), _) --> [].
mlds_output_type_suffix(mlds__native_int_type, _) --> [].
mlds_output_type_suffix(mlds__native_float_type, _) --> [].
mlds_output_type_suffix(mlds__native_bool_type, _) --> [].
mlds_output_type_suffix(mlds__native_char_type, _) --> [].
mlds_output_type_suffix(mlds__class_type(_, _, _), _) --> [].
mlds_output_type_suffix(mlds__ptr_type(_), _) --> [].
mlds_output_type_suffix(mlds__array_type(_), ArraySize) -->
	mlds_output_array_type_suffix(ArraySize).
mlds_output_type_suffix(mlds__func_type(FuncParams), _) -->
	mlds_output_func_type_suffix(FuncParams).
mlds_output_type_suffix(mlds__generic_type, _) --> [].
mlds_output_type_suffix(mlds__generic_env_ptr_type, _) --> [].
mlds_output_type_suffix(mlds__pseudo_type_info_type, _) --> [].
mlds_output_type_suffix(mlds__cont_type(ArgTypes), _) -->
	( { ArgTypes = [] } ->
		[]
	;
		% This case only happens for --nondet-copy-out
		io__write_string(")("),
		io__write_list(ArgTypes, ", ", mlds_output_type),
		% add the type for the environment parameter, if needed
		globals__io_lookup_bool_option(gcc_nested_functions,
			GCC_NestedFuncs),
		( { GCC_NestedFuncs = no } ->
			io__write_string(", void *")
		;
			[]
		),
		io__write_string(")")
	).
mlds_output_type_suffix(mlds__commit_type, _) --> [].
mlds_output_type_suffix(mlds__rtti_type(RttiName), ArraySize) -->
	( { rtti_name_has_array_type(RttiName) = yes } ->
		mlds_output_array_type_suffix(ArraySize)
	;
		[]
	).

:- pred mlds_output_array_type_suffix(initializer_array_size::in,
		io__state::di, io__state::uo) is det.
mlds_output_array_type_suffix(no_size) -->
	io__write_string("[]").
mlds_output_array_type_suffix(array_size(Size0)) -->
	%
	% ANSI/ISO C forbids arrays of size 0.
	%
	{ int__max(Size0, 1, Size) },
	io__format("[%d]", [i(Size)]).

%-----------------------------------------------------------------------------%
%
% Code to output declaration specifiers
%

:- type decl_or_defn
	--->	forward_decl
	;	definition.

:- pred mlds_output_decl_flags(mlds__decl_flags, decl_or_defn,
		mlds__entity_name, io__state, io__state).
:- mode mlds_output_decl_flags(in, in, in, di, uo) is det.

mlds_output_decl_flags(Flags, DeclOrDefn, Name) -->
	%
	% mlds_output_extern_or_static handles both the
	% `access' and the `per_instance' fields of the mlds__decl_flags.
	% We have to handle them together because C overloads `static'
	% to mean both `private' and `one_copy', rather than having
	% separate keywords for each.  To make it clear which MLDS
	% construct each `static' keyword means, we precede the `static'
	% without (optionally-enabled) comments saying whether it is
	% `private', `one_copy', or both.
	%
	mlds_output_access_comment(access(Flags)),
	mlds_output_per_instance_comment(per_instance(Flags)),
	mlds_output_extern_or_static(access(Flags), per_instance(Flags),
		DeclOrDefn, Name),
	mlds_output_virtuality(virtuality(Flags)),
	mlds_output_finality(finality(Flags)),
	mlds_output_constness(constness(Flags)),
	mlds_output_abstractness(abstractness(Flags)).

:- pred mlds_output_access_comment(access, io__state, io__state).
:- mode mlds_output_access_comment(in, di, uo) is det.

mlds_output_access_comment(Access) -->
	globals__io_lookup_bool_option(auto_comments, Comments),
	( { Comments = yes } ->
		mlds_output_access_comment_2(Access)
	;
		[]
	).

:- pred mlds_output_access_comment_2(access, io__state, io__state).
:- mode mlds_output_access_comment_2(in, di, uo) is det.

mlds_output_access_comment_2(public)    --> [].
mlds_output_access_comment_2(private)   --> io__write_string("/* private: */ ").
mlds_output_access_comment_2(protected) --> io__write_string("/* protected: */ ").
mlds_output_access_comment_2(default)   --> io__write_string("/* default access */ ").

:- pred mlds_output_per_instance_comment(per_instance, io__state, io__state).
:- mode mlds_output_per_instance_comment(in, di, uo) is det.

mlds_output_per_instance_comment(PerInstance) -->
	globals__io_lookup_bool_option(auto_comments, Comments),
	( { Comments = yes } ->
		mlds_output_per_instance_comment_2(PerInstance)
	;
		[]
	).

:- pred mlds_output_per_instance_comment_2(per_instance, io__state, io__state).
:- mode mlds_output_per_instance_comment_2(in, di, uo) is det.

mlds_output_per_instance_comment_2(per_instance) --> [].
mlds_output_per_instance_comment_2(one_copy)     --> io__write_string("/* one_copy */ ").

:- pred mlds_output_extern_or_static(access, per_instance, decl_or_defn,
		mlds__entity_name, io__state, io__state).
:- mode mlds_output_extern_or_static(in, in, in, in, di, uo) is det.

mlds_output_extern_or_static(Access, PerInstance, DeclOrDefn, Name) -->
	(
		{ Access = private ; PerInstance = one_copy },
		{ Name \= type(_, _) }
	->
		io__write_string("static ")
	;
		{ DeclOrDefn = forward_decl },
		{ Name = data(_) }
	->
		io__write_string("extern ")
	;
		[]
	).

:- pred mlds_output_virtuality(virtuality, io__state, io__state).
:- mode mlds_output_virtuality(in, di, uo) is det.

mlds_output_virtuality(virtual)     --> io__write_string("virtual ").
mlds_output_virtuality(non_virtual) --> [].

:- pred mlds_output_finality(finality, io__state, io__state).
:- mode mlds_output_finality(in, di, uo) is det.

mlds_output_finality(final)       --> io__write_string("/* final */ ").
mlds_output_finality(overridable) --> [].

:- pred mlds_output_constness(constness, io__state, io__state).
:- mode mlds_output_constness(in, di, uo) is det.

mlds_output_constness(const)      --> io__write_string("const ").
mlds_output_constness(modifiable) --> [].

:- pred mlds_output_abstractness(abstractness, io__state, io__state).
:- mode mlds_output_abstractness(in, di, uo) is det.

mlds_output_abstractness(abstract) --> io__write_string("/* abstract */ ").
mlds_output_abstractness(concrete) --> [].

%-----------------------------------------------------------------------------%
%
% Code to output statements
%

:- type func_info
	--->	func_info(mlds__qualified_entity_name, mlds__func_params).

:- pred mlds_output_statements(indent, func_info, list(mlds__statement),
		io__state, io__state).
:- mode mlds_output_statements(in, in, in, di, uo) is det.

mlds_output_statements(Indent, FuncInfo, Statements) -->
	list__foldl(mlds_output_statement(Indent, FuncInfo), Statements).

:- pred mlds_output_statement(indent, func_info, mlds__statement,
		io__state, io__state).
:- mode mlds_output_statement(in, in, in, di, uo) is det.

mlds_output_statement(Indent, FuncInfo, mlds__statement(Statement, Context)) -->
	mlds_output_context(Context),
	mlds_output_stmt(Indent, FuncInfo, Statement, Context).

:- pred mlds_output_stmt(indent, func_info, mlds__stmt, mlds__context,
		io__state, io__state).
:- mode mlds_output_stmt(in, in, in, in, di, uo) is det.

	%
	% sequence
	%
mlds_output_stmt(Indent, FuncInfo, block(Defns, Statements), Context) -->
	mlds_indent(Indent),
	io__write_string("{\n"),
	( { Defns \= [] } ->
		{ FuncInfo = func_info(FuncName, _) },
		{ FuncName = qual(ModuleName, _) },
		mlds_output_defns(Indent + 1, ModuleName, Defns),
		io__write_string("\n")
	;
		[]
	),
	mlds_output_statements(Indent + 1, FuncInfo, Statements),
	mlds_indent(Context, Indent),
	io__write_string("}\n").

	%
	% iteration
	%
mlds_output_stmt(Indent, FuncInfo, while(Cond, Statement, no), _) -->
	mlds_indent(Indent),
	io__write_string("while ("),
	mlds_output_rval(Cond),
	io__write_string(")\n"),
	mlds_output_statement(Indent + 1, FuncInfo, Statement).
mlds_output_stmt(Indent, FuncInfo, while(Cond, Statement, yes), Context) -->
	mlds_indent(Indent),
	io__write_string("do\n"),
	mlds_output_statement(Indent + 1, FuncInfo, Statement),
	mlds_indent(Context, Indent),
	io__write_string("while ("),
	mlds_output_rval(Cond),
	io__write_string(");\n").

	%
	% selection (see also computed_goto)
	%
mlds_output_stmt(Indent, FuncInfo, if_then_else(Cond, Then0, MaybeElse),
		Context) -->
	%
	% we need to take care to avoid problems caused by the
	% dangling else ambiguity
	%
	{
		%
		% For examples of the form
		%
		%	if (...)
		%		if (...)
		%			...
		%	else
		%		...
		%
		% we need braces around the inner `if', otherwise
		% they wouldn't parse they way we want them to:
		% C would match the `else' with the inner `if'
		% rather than the outer `if'.
		%
		MaybeElse = yes(_),
		Then0 = statement(if_then_else(_, _, no), ThenContext)
	->
		Then = statement(block([], [Then0]), ThenContext)
	;
		%
		% For examples of the form
		%
		%	if (...)
		%		if (...)
		%			...
		%		else
		%			...
		%
		% we don't _need_ braces around the inner `if',
		% since C will match the else with the inner `if',
		% but we add braces anyway, to avoid a warning from gcc.
		%
		MaybeElse = no,
		Then0 = statement(if_then_else(_, _, yes(_)), ThenContext)
	->
		Then = statement(block([], [Then0]), ThenContext)
	;
		Then = Then0
	},

	mlds_indent(Indent),
	io__write_string("if ("),
	mlds_output_rval(Cond),
	io__write_string(")\n"),
	mlds_output_statement(Indent + 1, FuncInfo, Then),
	( { MaybeElse = yes(Else) } ->
		mlds_indent(Context, Indent),
		io__write_string("else\n"),
		mlds_output_statement(Indent + 1, FuncInfo, Else)
	;
		[]
	).
mlds_output_stmt(Indent, FuncInfo, switch(_Type, Val, Cases, Default),
		Context) -->
	mlds_indent(Context, Indent),
	io__write_string("switch ("),
	mlds_output_rval(Val),
	io__write_string(") {\n"),
	list__foldl(mlds_output_switch_case(Indent + 1, FuncInfo, Context),
		Cases),
	mlds_output_switch_default(Indent + 1, FuncInfo, Context, Default),
	mlds_indent(Context, Indent),
	io__write_string("}\n").

	%
	% transfer of control
	%
mlds_output_stmt(Indent, _FuncInfo, label(LabelName), _) -->
	%
	% Note: MLDS allows labels at the end of blocks.
	% C doesn't.  Hence we need to insert a semi-colon after the colon
	% to ensure that there is a statement to attach the label to.
	%
	mlds_indent(Indent - 1),
	mlds_output_label_name(LabelName),
	io__write_string(":;\n").
mlds_output_stmt(Indent, _FuncInfo, goto(LabelName), _) -->
	mlds_indent(Indent),
	io__write_string("goto "),
	mlds_output_label_name(LabelName),
	io__write_string(";\n").
mlds_output_stmt(Indent, _FuncInfo, computed_goto(Expr, Labels), Context) -->
	% XXX for GNU C, we could output potentially more efficient code
	% by using an array of labels; this would tell the compiler that
	% it didn't need to do any range check.
	mlds_indent(Indent),
	io__write_string("switch ("),
	mlds_output_rval(Expr),
	io__write_string(") {\n"),
	{ OutputLabel =
	    (pred(Label::in, Count0::in, Count::out, di, uo) is det -->
		mlds_indent(Context, Indent + 1),
		io__write_string("case "),
		io__write_int(Count0),
		io__write_string(": goto "),
		mlds_output_label_name(Label),
		io__write_string(";\n"),
		{ Count = Count0 + 1 }
	) },
	list__foldl2(OutputLabel, Labels, 0, _FinalCount),
	mlds_indent(Context, Indent + 1),
	io__write_string("default: /*NOTREACHED*/ assert(0);\n"),
	mlds_indent(Context, Indent),
	io__write_string("}\n").

	%
	% function call/return
	%
mlds_output_stmt(Indent, CallerFuncInfo, Call, Context) -->
	{ Call = call(_Signature, FuncRval, MaybeObject, CallArgs,
		Results, IsTailCall) },
	{ CallerFuncInfo = func_info(Name, _Params) },
	%
	% Optimize general tail calls.
	% We can't really do much here except to insert `return'
	% as an extra hint to the C compiler.
	% XXX these optimizations should be disable-able
	%
	% If Results = [], i.e. the function has `void' return type,
	% then this would result in code that is not legal ANSI C
	% (although it _is_ legal in GNU C and in C++),
	% so for that case, we put the return statement after
	% the call -- see below.  We need to enclose it inside
	% an extra pair of curly braces in case this `call'
	% is e.g. inside an if-then-else.
	%
	mlds_indent(Indent),
	io__write_string("{\n"),

	mlds_maybe_output_call_profile_instr(Context,
			Indent + 1, FuncRval, Name),

	mlds_indent(Context, Indent + 1),

	( { IsTailCall = tail_call, Results \= [] } ->
		io__write_string("return ")
	;
		[]
	),
	( { MaybeObject = yes(Object) } ->
		mlds_output_bracketed_rval(Object),
		io__write_string(".") % XXX should this be "->"?
	;
		[]
	),
	( { Results = [] } ->
		[]
	; { Results = [Lval] } ->
		mlds_output_lval(Lval),
		io__write_string(" = ")
	;
		{ error("mld_output_stmt: multiple return values") }
	),
	mlds_output_bracketed_rval(FuncRval),
	io__write_string("("),
	io__write_list(CallArgs, ", ", mlds_output_rval),
	io__write_string(");\n"),

	( { IsTailCall = tail_call, Results = [] } ->
		mlds_indent(Context, Indent + 1),
		io__write_string("return;\n")
	;
		mlds_maybe_output_time_profile_instr(Context,
				Indent + 1, Name)
	),
	mlds_indent(Indent),
	io__write_string("}\n").

mlds_output_stmt(Indent, _FuncInfo, return(Results), _) -->
	mlds_indent(Indent),
	io__write_string("return"),
	( { Results = [] } ->
		[]
	; { Results = [Rval] } ->
		io__write_char(' '),
		mlds_output_rval(Rval)
	;
		{ error("mlds_output_stmt: multiple return values") }
	),
	io__write_string(";\n").
	
	%
	% commits
	%
mlds_output_stmt(Indent, _FuncInfo, do_commit(Ref), _) -->
	mlds_indent(Indent),
	globals__io_lookup_bool_option(gcc_local_labels, GCC_LocalLabels),
	( { GCC_LocalLabels = yes } ->
		% output "goto <Ref>"
		io__write_string("goto "),
		mlds_output_rval(Ref)
	;
		% output "longjmp(<Ref>, 1)"
		io__write_string("longjmp("),
		mlds_output_rval(Ref),
		io__write_string(", 1)")
	),
	io__write_string(";\n").
mlds_output_stmt(Indent, FuncInfo, try_commit(Ref, Stmt0, Handler), Context) -->
	globals__io_lookup_bool_option(gcc_local_labels, GCC_LocalLabels),
	(
		{ GCC_LocalLabels = yes },
	
		% Output the following:
		%
		%               <Stmt>
		%               goto <Ref>_done;
		%       <Ref>:
		%               <Handler>
		%       <Ref>_done:
		%               ;

		% Note that <Ref> should be just variable name,
		% not a complicated expression.  If not, the
		% C compiler will catch it.

		mlds_output_statement(Indent, FuncInfo, Stmt0),

		mlds_indent(Context, Indent),
		io__write_string("goto "),
		mlds_output_lval(Ref),
		io__write_string("_done;\n"),

		mlds_indent(Context, Indent - 1),
		mlds_output_lval(Ref),
		io__write_string(":\n"),

		mlds_output_statement(Indent, FuncInfo, Handler),

		mlds_indent(Context, Indent - 1),
		mlds_output_lval(Ref),
		io__write_string("_done:\t;\n")

	;
		{ GCC_LocalLabels = no },

		% Output the following:
		%
		%	if (setjmp(<Ref>) == 0)
		%               <Stmt>
		%       else
		%               <Handler>

		%
		% XXX we need to declare the local variables as volatile,
		% because of the setjmp()!
		%

		%
		% we need to take care to avoid problems caused by the
		% dangling else ambiguity
		%
		{
			Stmt0 = statement(if_then_else(_, _, no), Context)
		->
			Stmt = statement(block([], [Stmt0]), Context)
		;
			Stmt = Stmt0
		},

		mlds_indent(Indent),
		io__write_string("if (setjmp("),
		mlds_output_lval(Ref),
		io__write_string(") == 0)\n"),

		mlds_output_statement(Indent + 1, FuncInfo, Stmt),

		mlds_indent(Context, Indent),
		io__write_string("else\n"),

		mlds_output_statement(Indent + 1, FuncInfo, Handler)
	).

%-----------------------------------------------------------------------------%

%
% Extra code for outputting switch statements
%

:- pred mlds_output_switch_case(indent, func_info, mlds__context,
		mlds__switch_case, io__state, io__state).
:- mode mlds_output_switch_case(in, in, in, in, di, uo) is det.

mlds_output_switch_case(Indent, FuncInfo, Context, Case) -->
	{ Case = (Conds - Statement) },
	list__foldl(mlds_output_case_cond(Indent, Context), Conds),
	mlds_output_statement(Indent + 1, FuncInfo, Statement),
	mlds_indent(Context, Indent + 1),
	io__write_string("break;\n").

:- pred mlds_output_case_cond(indent, mlds__context,
		mlds__case_match_cond, io__state, io__state).
:- mode mlds_output_case_cond(in, in, in, di, uo) is det.

mlds_output_case_cond(Indent, Context, match_value(Val)) -->
	mlds_indent(Context, Indent),
	io__write_string("case "),
	mlds_output_rval(Val),
	io__write_string(":\n").
mlds_output_case_cond(Indent, Context, match_range(Low, High)) -->
	% This uses the GNU C extension `case <Low> ... <High>:'.
	mlds_indent(Context, Indent),
	io__write_string("case "),
	mlds_output_rval(Low),
	io__write_string(" ... "),
	mlds_output_rval(High),
	io__write_string(":\n").

:- pred mlds_output_switch_default(indent, func_info, mlds__context,
		mlds__switch_default, io__state, io__state).
:- mode mlds_output_switch_default(in, in, in, in, di, uo) is det.

mlds_output_switch_default(Indent, _FuncInfo, Context, default_is_unreachable) -->
	mlds_indent(Context, Indent),
	io__write_string("default: /*NOTREACHED*/ assert(0);\n").
mlds_output_switch_default(_Indent, _FuncInfo, _Context, default_do_nothing) --> [].
mlds_output_switch_default(Indent, FuncInfo, Context, default_case(Statement)) -->
	mlds_indent(Context, Indent),
	io__write_string("default:\n"),
	mlds_output_statement(Indent + 1, FuncInfo, Statement).

%-----------------------------------------------------------------------------%

	%
	% If memory profiling is turned on output an instruction to
	% record the heap allocation.
	%
:- pred mlds_maybe_output_heap_profile_instr(mlds__context::in,
		indent::in, list(mlds__rval)::in,
		mlds__qualified_entity_name::in, maybe(ctor_name)::in,
		io__state::di, io__state::uo) is det.

mlds_maybe_output_heap_profile_instr(Context, Indent, Args, FuncName,
		MaybeCtorName) -->
	globals__io_lookup_bool_option(profile_memory, ProfileMem),
	(
		{ ProfileMem = yes }
	->
		mlds_indent(Context, Indent),
		io__write_string("MR_record_allocation("),
		io__write_int(list__length(Args)),
		io__write_string(", "),
		mlds_output_fully_qualified_name(FuncName),
		io__write_string(", """),
		mlds_output_fully_qualified_name(FuncName),
		io__write_string(""", "),
		( { MaybeCtorName = yes(CtorName) } ->
			io__write_char('"'),
			c_util__output_quoted_string(CtorName),
			io__write_char('"')
		;
			io__write_string("NULL")
		),
		io__write_string(");\n")
	;
		[]
	).

	%
	% If call profiling is turned on output an instruction to record
	% an arc in the call profile between the callee and caller.
	%
:- pred mlds_maybe_output_call_profile_instr(mlds__context::in,
		indent::in, mlds__rval::in, mlds__qualified_entity_name::in,
		io__state::di, io__state::uo) is det.

mlds_maybe_output_call_profile_instr(Context, Indent,
		CalleeFuncRval, CallerName) -->
	globals__io_lookup_bool_option(profile_calls, ProfileCalls),
	(
		{
			ProfileCalls = yes,

				% Some functions don't have a
				% code_addr so we can't record the arc.
			\+ no_code_address(CalleeFuncRval)
		}
	->
		mlds_indent(Context, Indent),
		io__write_string("MR_prof_call_profile("),
		mlds_output_bracketed_rval(CalleeFuncRval),
		io__write_string(", "),
		mlds_output_fully_qualified_name(CallerName),
		io__write_string(");\n")
	;
		[]
	).

	%
	% If time profiling is turned on output an instruction which
	% informs the runtime which procedure we are currently located
	% in.
	%
:- pred mlds_maybe_output_time_profile_instr(mlds__context::in,
		indent::in, mlds__qualified_entity_name::in,
		io__state::di, io__state::uo) is det.

mlds_maybe_output_time_profile_instr(Context, Indent, Name) -->
	globals__io_lookup_bool_option(profile_time, ProfileTime),
	(
		{ ProfileTime = yes }
	->
		mlds_indent(Context, Indent),
		io__write_string("MR_set_prof_current_proc("),
		mlds_output_fully_qualified_name(Name),
		io__write_string(");\n")
	;
		[]
	).

	%
	% Does the rval represent a special procedure for which a
	% code address doesn't exist.
	%
:- pred no_code_address(mlds__rval::in) is semidet.

no_code_address(const(code_addr_const(proc(qual(Module, PredLabel - _), _)))) :-
	SymName = mlds_module_name_to_sym_name(Module),
	SymName = qualified(unqualified("mercury"), "private_builtin"),
	PredLabel = pred(predicate, _, "unsafe_type_cast", 2).

%-----------------------------------------------------------------------------%

	%
	% exception handling
	%

	/* XXX not yet implemented */


	%
	% atomic statements
	%
mlds_output_stmt(Indent, FuncInfo, atomic(AtomicStatement), Context) -->
	mlds_output_atomic_stmt(Indent, FuncInfo, AtomicStatement, Context).

:- pred mlds_output_label_name(mlds__label, io__state, io__state).
:- mode mlds_output_label_name(in, di, uo) is det.

mlds_output_label_name(LabelName) -->
	mlds_output_mangled_name(LabelName).

:- pred mlds_output_atomic_stmt(indent, func_info,
		mlds__atomic_statement, mlds__context, io__state, io__state).
:- mode mlds_output_atomic_stmt(in, in, in, in, di, uo) is det.

	%
	% comments
	%
mlds_output_atomic_stmt(Indent, _FuncInfo, comment(Comment), _) -->
	% XXX we should escape any "*/"'s in the Comment.
	%     we should also split the comment into lines and indent
	%     each line appropriately.
	mlds_indent(Indent),
	io__write_string("/* "),
	io__write_string(Comment),
	io__write_string(" */\n").

	%
	% assignment
	%
mlds_output_atomic_stmt(Indent, _FuncInfo, assign(Lval, Rval), _) -->
	mlds_indent(Indent),
	mlds_output_lval(Lval),
	io__write_string(" = "),
	mlds_output_rval(Rval),
	io__write_string(";\n").

	%
	% heap management
	%
mlds_output_atomic_stmt(_Indent, _FuncInfo, delete_object(_Lval), _) -->
	{ error("mlds_to_c.m: sorry, delete_object not implemented") }.

mlds_output_atomic_stmt(Indent, FuncInfo, NewObject, Context) -->
	{ NewObject = new_object(Target, MaybeTag, Type, MaybeSize,
		MaybeCtorName, Args, ArgTypes) },
	mlds_indent(Indent),
	io__write_string("{\n"),

	{ FuncInfo = func_info(FuncName, _) },
	mlds_maybe_output_heap_profile_instr(Context, Indent + 1, Args,
			FuncName, MaybeCtorName),

	mlds_indent(Context, Indent + 1),
	mlds_output_lval(Target),
	io__write_string(" = "),
	( { MaybeTag = yes(Tag0) } ->
		{ Tag = Tag0 },
		io__write_string("("),
		mlds_output_type(Type),
		io__write_string(") "),
		io__write_string("MR_mkword("),
		mlds_output_tag(Tag),
		io__write_string(", "),
		{ EndMkword = ")" }
	;
		{ Tag = 0 },
		%
		% XXX we shouldn't need the cast here,
		% but currently the type that we include
		% in the call to MR_new_object() is not
		% always correct.
		%
		io__write_string("("),
		mlds_output_type(Type),
		io__write_string(") "),
		{ EndMkword = "" }
	),
	io__write_string("MR_new_object("),
	mlds_output_type(Type),
	io__write_string(", "),
	( { MaybeSize = yes(Size) } ->
		mlds_output_rval(Size)
	;
		% XXX what should we do here?
		io__write_int(-1)
	),
	io__write_string(", "),
	( { MaybeCtorName = yes(CtorName) } ->
		io__write_char('"'),
		c_util__output_quoted_string(CtorName),
		io__write_char('"')
	;
		io__write_string("NULL")
	),
	io__write_string(")"),
	io__write_string(EndMkword),
	io__write_string(";\n"),
	mlds_output_init_args(Args, ArgTypes, Context, 0, Target, Tag,
		Indent + 1),
	mlds_indent(Context, Indent),
	io__write_string("}\n").

mlds_output_atomic_stmt(Indent, _FuncInfo, mark_hp(Lval), _) -->
	mlds_indent(Indent),
	io__write_string("MR_mark_hp("),
	mlds_output_lval(Lval),
	io__write_string(");\n").

mlds_output_atomic_stmt(Indent, _FuncInfo, restore_hp(Rval), _) -->
	mlds_indent(Indent),
	io__write_string("MR_mark_hp("),
	mlds_output_rval(Rval),
	io__write_string(");\n").

	%
	% trail management
	%
mlds_output_atomic_stmt(_Indent, _FuncInfo, trail_op(_TrailOp), _) -->
	{ error("mlds_to_c.m: sorry, trail_ops not implemented") }.

	%
	% foreign language interfacing
	%
mlds_output_atomic_stmt(_Indent, FuncInfo, target_code(TargetLang, Components),
		Context) -->
	( { TargetLang = lang_C } ->
		{ FuncInfo = func_info(qual(ModuleName, _), _FuncParams) },
		list__foldl(
			mlds_output_target_code_component(ModuleName, Context),
			Components)
	;
		{ error("mlds_to_c.m: sorry, target_code only works for lang_C") }
	).

:- pred mlds_output_target_code_component(mlds_module_name, mlds__context,
		target_code_component, io__state, io__state).
:- mode mlds_output_target_code_component(in, in, in, di, uo) is det.

mlds_output_target_code_component(_ModuleName, Context,
		user_target_code(CodeString, MaybeUserContext)) -->
	( { MaybeUserContext = yes(UserContext) } ->
		mlds_output_context(mlds__make_context(UserContext))
	;
		mlds_output_context(Context)
	),
	io__write_string(CodeString),
	io__write_string("\n").
mlds_output_target_code_component(_ModuleName, Context,
		raw_target_code(CodeString)) -->
	mlds_output_context(Context),
	io__write_string(CodeString).
mlds_output_target_code_component(_ModuleName, Context,
		target_code_input(Rval)) -->
	mlds_output_context(Context),
	mlds_output_rval(Rval),
	io__write_string("\n").
mlds_output_target_code_component(_ModuleName, Context,
		target_code_output(Lval)) -->
	mlds_output_context(Context),
	mlds_output_lval(Lval),
	io__write_string("\n").
mlds_output_target_code_component(ModuleName, _Context, name(Name)) -->
	% Note: `name(Name)' target_code_components are used to
	% generate the #define for `MR_PROC_LABEL'.
	% The fact that they're used in a #define means that we can't do
	% an mlds_output_context(Context) here, since #line directives
	% aren't allowed inside #defines.
	mlds_output_fully_qualified_name(qual(ModuleName, Name)),
	io__write_string("\n").

:- pred mlds_output_init_args(list(mlds__rval), list(mlds__type), mlds__context,
		int, mlds__lval, mlds__tag, indent, io__state, io__state).
:- mode mlds_output_init_args(in, in, in, in, in, in, in, di, uo) is det.

mlds_output_init_args([_|_], [], _, _, _, _, _) -->
	{ error("mlds_output_init_args: length mismatch") }.
mlds_output_init_args([], [_|_], _, _, _, _, _) -->
	{ error("mlds_output_init_args: length mismatch") }.
mlds_output_init_args([], [], _, _, _, _, _) --> [].
mlds_output_init_args([Arg|Args], [ArgType|ArgTypes], Context,
		ArgNum, Target, Tag, Indent) -->
	%
	% Currently all fields of new_object instructions are
	% represented as MR_Box, so we need to box them if necessary.
	%
	mlds_indent(Context, Indent),
	io__write_string("MR_field("),
	mlds_output_tag(Tag),
	io__write_string(", "),
	mlds_output_lval(Target),
	io__write_string(", "),
	io__write_int(ArgNum),
	io__write_string(") = (MR_Word) "),
	mlds_output_boxed_rval(ArgType, Arg),
	io__write_string(";\n"),
	mlds_output_init_args(Args, ArgTypes, Context,
		ArgNum + 1, Target, Tag, Indent).

%-----------------------------------------------------------------------------%
%
% Code to output expressions
%

:- pred mlds_output_lval(mlds__lval, io__state, io__state).
:- mode mlds_output_lval(in, di, uo) is det.

mlds_output_lval(field(MaybeTag, Rval, offset(OffsetRval),
		FieldType, _ClassType)) -->
	(
		{ FieldType = mlds__generic_type
		; FieldType = mlds__mercury_type(term__variable(_), _)
		}
	->
		% XXX this generated code is ugly;
		% it would be nicer to use a different macro
		% than MR_field(), one which had type `MR_Box'
		% rather than `MR_Word'.
		io__write_string("(* (MR_Box *) &")
	;
		% The field type for field(_, _, offset(_), _, _) lvals
		% must be something that maps to MR_Box.
		{ error("unexpected field type") }
	),
	( { MaybeTag = yes(Tag) } ->
		io__write_string("MR_field("),
		mlds_output_tag(Tag),
		io__write_string(", ")
	;
		io__write_string("MR_mask_field(")
	),
	io__write_string("(MR_Word) "),
	mlds_output_rval(Rval),
	io__write_string(", "),
	mlds_output_rval(OffsetRval),
	io__write_string("))").
mlds_output_lval(field(MaybeTag, PtrRval, named_field(FieldName, CtorType),
		_FieldType, _PtrType)) -->
	% XXX we shouldn't bother with this cast in the case where
	% PtrType == CtorType
	io__write_string("(("),
	mlds_output_type(CtorType),
	io__write_string(") "),
	( { MaybeTag = yes(0) } ->
		( { PtrRval = mem_addr(Lval) } ->
			mlds_output_lval(Lval),
			io__write_string(").")
		;
			mlds_output_bracketed_rval(PtrRval),
			io__write_string(")->")
		)
	;
		( { MaybeTag = yes(Tag) } ->
			io__write_string("MR_body("),
			mlds_output_rval(PtrRval),
			io__write_string(", "),
			mlds_output_tag(Tag)
		;
			io__write_string("MR_strip_tag("),
			mlds_output_rval(PtrRval)
		),
		io__write_string("))->")
	),
	mlds_output_fully_qualified(FieldName, mlds_output_mangled_name).
mlds_output_lval(mem_ref(Rval, _Type)) -->
	io__write_string("*"),
	mlds_output_bracketed_rval(Rval).
mlds_output_lval(var(VarName)) -->
	mlds_output_var(VarName).

:- pred mlds_output_var(mlds__var, io__state, io__state).
:- mode mlds_output_var(in, di, uo) is det.

mlds_output_var(VarName) -->
	mlds_output_fully_qualified(VarName, mlds_output_mangled_name).

:- pred mlds_output_mangled_name(string, io__state, io__state).
:- mode mlds_output_mangled_name(in, di, uo) is det.

mlds_output_mangled_name(Name) -->
	{ llds_out__name_mangle(Name, MangledName) },
	io__write_string(MangledName).

:- pred mlds_output_bracketed_lval(mlds__lval, io__state, io__state).
:- mode mlds_output_bracketed_lval(in, di, uo) is det.

mlds_output_bracketed_lval(Lval) -->
	(
		% if it's just a variable name, then we don't need parentheses
		{ Lval = var(_) }
	->
		mlds_output_lval(Lval)
	;
		io__write_char('('),
		mlds_output_lval(Lval),
		io__write_char(')')
	).

:- pred mlds_output_bracketed_rval(mlds__rval, io__state, io__state).
:- mode mlds_output_bracketed_rval(in, di, uo) is det.

mlds_output_bracketed_rval(Rval) -->
	(
		% if it's just a variable name, then we don't need parentheses
		{ Rval = lval(var(_))
		; Rval = const(code_addr_const(_))
		}
	->
		mlds_output_rval(Rval)
	;
		io__write_char('('),
		mlds_output_rval(Rval),
		io__write_char(')')
	).

:- pred mlds_output_rval(mlds__rval, io__state, io__state).
:- mode mlds_output_rval(in, di, uo) is det.

mlds_output_rval(lval(Lval)) -->
	mlds_output_lval(Lval).
/**** XXX do we need this?
mlds_output_rval(lval(Lval)) -->
	% if a field is used as an rval, then we need to use
	% the MR_const_field() macro, not the MR_field() macro,
	% to avoid warnings about discarding const,
	% and similarly for MR_mask_field.
	( { Lval = field(MaybeTag, Rval, FieldNum, _, _) } ->
		( { MaybeTag = yes(Tag) } ->
			io__write_string("MR_const_field("),
			mlds_output_tag(Tag),
			io__write_string(", ")
		;
			io__write_string("MR_const_mask_field(")
		),
		mlds_output_rval(Rval),
		io__write_string(", "),
		mlds_output_rval(FieldNum),
		io__write_string(")")
	;
		mlds_output_lval(Lval)
	).
****/

mlds_output_rval(mkword(Tag, Rval)) -->
	io__write_string("(MR_Word) MR_mkword("),
	mlds_output_tag(Tag),
	io__write_string(", "),
	mlds_output_rval(Rval),
	io__write_string(")").

mlds_output_rval(const(Const)) -->
	mlds_output_rval_const(Const).

mlds_output_rval(unop(Op, Rval)) -->
	mlds_output_unop(Op, Rval).

mlds_output_rval(binop(Op, Rval1, Rval2)) -->
	mlds_output_binop(Op, Rval1, Rval2).

mlds_output_rval(mem_addr(Lval)) -->
	% XXX are parentheses needed?
	io__write_string("&"),
	mlds_output_lval(Lval).

:- pred mlds_output_unop(mlds__unary_op, mlds__rval, io__state, io__state).
:- mode mlds_output_unop(in, in, di, uo) is det.
	
mlds_output_unop(cast(Type), Exprn) -->
	mlds_output_cast_rval(Type, Exprn).
mlds_output_unop(box(Type), Exprn) -->
	mlds_output_boxed_rval(Type, Exprn).
mlds_output_unop(unbox(Type), Exprn) -->
	mlds_output_unboxed_rval(Type, Exprn).
mlds_output_unop(std_unop(Unop), Exprn) -->
	mlds_output_std_unop(Unop, Exprn).

:- pred mlds_output_cast_rval(mlds__type, mlds__rval, io__state, io__state).
:- mode mlds_output_cast_rval(in, in, di, uo) is det.
	
mlds_output_cast_rval(Type, Exprn) -->
	io__write_string("("),
	mlds_output_type(Type),
	io__write_string(") "),
	mlds_output_rval(Exprn).

:- pred mlds_output_boxed_rval(mlds__type, mlds__rval, io__state, io__state).
:- mode mlds_output_boxed_rval(in, in, di, uo) is det.
	
mlds_output_boxed_rval(Type, Exprn) -->
	(
		{ Type = mlds__mercury_type(term__functor(term__atom("float"),
				[], _), _)
		; Type = mlds__native_float_type
		}
	->
		io__write_string("MR_box_float("),
		mlds_output_rval(Exprn),
		io__write_string(")")
	;
		% We cast first to MR_Word, and then to MR_Box.
		% This is done to avoid spurious warnings about "cast from
		% pointer to integer of different size" from gcc.
		% XXX The generated code would be more readable if we
		%     only did this for the cases where it was necessary.
		io__write_string("((MR_Box) (MR_Word) ("),
		mlds_output_rval(Exprn),
		io__write_string("))")
	).

:- pred mlds_output_unboxed_rval(mlds__type, mlds__rval, io__state, io__state).
:- mode mlds_output_unboxed_rval(in, in, di, uo) is det.
	
mlds_output_unboxed_rval(Type, Exprn) -->
	(
		{ Type = mlds__mercury_type(term__functor(term__atom("float"),
				[], _), _)
		; Type = mlds__native_float_type
		}
	->
		io__write_string("MR_unbox_float("),
		mlds_output_rval(Exprn),
		io__write_string(")")
	;
		% We cast first to MR_Word, and then to the desired type.
		% This is done to avoid spurious warnings about "cast from
		% pointer to integer of different size" from gcc.
		% XXX The generated code would be more readable if we
		%     only did this for the cases where it was necessary.
		io__write_string("(("),
		mlds_output_type(Type),
		io__write_string(") (MR_Word) "),
		mlds_output_rval(Exprn),
		io__write_string(")")
	).

:- pred mlds_output_std_unop(builtin_ops__unary_op, mlds__rval,
		io__state, io__state).
:- mode mlds_output_std_unop(in, in, di, uo) is det.
	
mlds_output_std_unop(UnaryOp, Exprn) -->
	{ c_util__unary_prefix_op(UnaryOp, UnaryOpString) },
	io__write_string(UnaryOpString),
	io__write_string("("),
	( { UnaryOp = tag } ->
		% The MR_tag macro requires its argument to be of type 
		% `MR_Word'.
		% XXX should we put this cast inside the definition of MR_tag?
		io__write_string("(MR_Word) ")
	;
		[]
	),
	mlds_output_rval(Exprn),
	io__write_string(")").

:- pred mlds_output_binop(binary_op, mlds__rval, mlds__rval,
			io__state, io__state).
:- mode mlds_output_binop(in, in, in, di, uo) is det.
	
mlds_output_binop(Op, X, Y) -->
	(
		{ Op = array_index }
	->
		mlds_output_bracketed_rval(X),
		io__write_string("["),
		mlds_output_rval(Y),
		io__write_string("]")
	;
		{ c_util__string_compare_op(Op, OpStr) }
	->
		io__write_string("(strcmp("),
		mlds_output_rval(X),
		io__write_string(", "),
		mlds_output_rval(Y),
		io__write_string(")"),
		io__write_string(" "),
		io__write_string(OpStr),
		io__write_string(" "),
		io__write_string("0)")
	;
		( { c_util__float_compare_op(Op, OpStr1) } ->
			{ OpStr = OpStr1 }
		; { c_util__float_op(Op, OpStr2) } ->
			{ OpStr = OpStr2 }
		;
			{ fail }
		)
	->
		io__write_string("("),
		mlds_output_bracketed_rval(X), % XXX as float
		io__write_string(" "),
		io__write_string(OpStr),
		io__write_string(" "),
		mlds_output_bracketed_rval(Y), % XXX as float
		io__write_string(")")
	;
/****
XXX broken for C == minint
(since `NewC is 0 - C' overflows)
		{ Op = (+) },
		{ Y = const(int_const(C)) },
		{ C < 0 }
	->
		{ NewOp = (-) },
		{ NewC is 0 - C },
		{ NewY = const(int_const(NewC)) },
		io__write_string("("),
		mlds_output_rval(X),
		io__write_string(" "),
		mlds_output_binary_op(NewOp),
		io__write_string(" "),
		mlds_output_rval(NewY),
		io__write_string(")")
	;
******/
		io__write_string("("),
		mlds_output_rval(X),
		io__write_string(" "),
		mlds_output_binary_op(Op),
		io__write_string(" "),
		mlds_output_rval(Y),
		io__write_string(")")
	).

:- pred mlds_output_binary_op(binary_op, io__state, io__state).
:- mode mlds_output_binary_op(in, di, uo) is det.

mlds_output_binary_op(Op) -->
	( { c_util__binary_infix_op(Op, OpStr) } ->
		io__write_string(OpStr)
	;
		{ error("mlds_output_binary_op: invalid binary operator") }
	).

:- pred mlds_output_rval_const(mlds__rval_const, io__state, io__state).
:- mode mlds_output_rval_const(in, di, uo) is det.

mlds_output_rval_const(true) -->
	io__write_string("TRUE").	% XXX should we use `MR_TRUE'?
mlds_output_rval_const(false) -->
	io__write_string("FALSE").	% XXX should we use `MR_FALSE'?
mlds_output_rval_const(int_const(N)) -->
	% we need to cast to (MR_Integer) to ensure
	% things like 1 << 32 work when `Integer' is 64 bits
	% but `int' is 32 bits.
	io__write_string("(MR_Integer) "),
	io__write_int(N).
mlds_output_rval_const(float_const(FloatVal)) -->
	% the cast to (MR_Float) here lets the C compiler
	% do arithmetic in `float' rather than `double'
	% if `MR_Float' is `float' not `double'.
	io__write_string("(MR_Float) "),
	io__write_float(FloatVal).
mlds_output_rval_const(string_const(String)) -->
	% the cast avoids the following gcc warning
	% "assignment discards qualifiers from pointer target type"
	io__write_string("(MR_String) "),
	io__write_string(""""),
	c_util__output_quoted_string(String),
	io__write_string("""").
mlds_output_rval_const(multi_string_const(Length, String)) -->
	io__write_string(""""),
	c_util__output_quoted_multi_string(Length, String),
	io__write_string("""").
mlds_output_rval_const(code_addr_const(CodeAddr)) -->
	mlds_output_code_addr(CodeAddr).
mlds_output_rval_const(data_addr_const(DataAddr)) -->
	mlds_output_data_addr(DataAddr).
mlds_output_rval_const(null(_)) -->
       io__write_string("NULL").

%-----------------------------------------------------------------------------%

:- pred mlds_output_tag(mlds__tag, io__state, io__state).
:- mode mlds_output_tag(in, di, uo) is det.

mlds_output_tag(Tag) -->
	io__write_string("MR_mktag("),
	io__write_int(Tag),
	io__write_string(")").

%-----------------------------------------------------------------------------%

:- pred mlds_output_code_addr(mlds__code_addr, io__state, io__state).
:- mode mlds_output_code_addr(in, di, uo) is det.

mlds_output_code_addr(proc(Label, _Sig)) -->
	mlds_output_fully_qualified_proc_label(Label).
mlds_output_code_addr(internal(Label, SeqNum, _Sig)) -->
	mlds_output_fully_qualified_proc_label(Label),
	io__write_string("_"),
	io__write_int(SeqNum).

:- pred mlds_output_proc_label(mlds__proc_label, io__state, io__state).
:- mode mlds_output_proc_label(in, di, uo) is det.

mlds_output_proc_label(PredLabel - ProcId) -->
	mlds_output_pred_label(PredLabel),
	{ proc_id_to_int(ProcId, ModeNum) },
	io__format("_%d", [i(ModeNum)]).

:- pred mlds_output_data_addr(mlds__data_addr, io__state, io__state).
:- mode mlds_output_data_addr(in, di, uo) is det.

mlds_output_data_addr(data_addr(ModuleName, DataName)) -->
	(
		% if its an array type, then we just use the name,
		% otherwise we must prefix the name with `&'.
		{ DataName = rtti(_, RttiName) },
		{ rtti_name_has_array_type(RttiName) = yes }
	->
		mlds_output_data_var_name(ModuleName, DataName)
	;
		io__write_string("(&"),
		mlds_output_data_var_name(ModuleName, DataName),
		io__write_string(")")
	).

:- pred mlds_output_data_var_name(mlds_module_name, mlds__data_name,
		io__state, io__state).
:- mode mlds_output_data_var_name(in, in, di, uo) is det.

mlds_output_data_var_name(ModuleName, DataName) -->
	(
		%
		% don't module-qualify base_typeclass_infos
		%
		% We don't want to include the module name as part
		% of the name if it is a base_typeclass_info, since
		% we _want_ to cause a link error for overlapping
		% instance decls, even if they are in a different
		% module
		%
		{ DataName = base_typeclass_info(_, _) }
	->
		[]
	;
		mlds_output_module_name(
			mlds_module_name_to_sym_name(ModuleName)),
		io__write_string("__")
	),
	mlds_output_data_name(DataName).

%-----------------------------------------------------------------------------%
%
% Miscellaneous stuff to handle indentation and generation of
% source context annotations (#line directives).
%

:- pred mlds_output_context(mlds__context, io__state, io__state).
:- mode mlds_output_context(in, di, uo) is det.

mlds_output_context(Context) -->
	{ ProgContext = mlds__get_prog_context(Context) },
	{ term__context_file(ProgContext, FileName) },
	{ term__context_line(ProgContext, LineNumber) },
	c_util__set_line_num(FileName, LineNumber).

:- pred mlds_indent(mlds__context, indent, io__state, io__state).
:- mode mlds_indent(in, in, di, uo) is det.

mlds_indent(Context, N) -->
	mlds_output_context(Context),
	mlds_indent(N).

% A value of type `indent' records the number of levels
% of indentation to indent the next piece of code.
% Currently we output two spaces for each level of indentation.
:- type indent == int.

:- pred mlds_indent(indent, io__state, io__state).
:- mode mlds_indent(in, di, uo) is det.

mlds_indent(N) -->
	( { N =< 0 } ->
		[]
	;
		io__write_string("  "),
		mlds_indent(N - 1)
	).

%-----------------------------------------------------------------------------%
