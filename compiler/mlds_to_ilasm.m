%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% mlds_to_ilasm - Convert MLDS to IL assembler code.
% Main author: trd.
%
% This code converts the MLDS representation into IL assembler.
% This module takes care of creating the appropriate files and
% generating output, while mlds_to_il takes care of generated IL from
% MLDS.

:- module mlds_to_ilasm.
:- interface.

:- import_module mlds.
:- import_module io.

	% Convert the MLDS to IL and write it to a file.

:- pred mlds_to_ilasm__output_mlds(mlds, io__state, io__state).
:- mode mlds_to_ilasm__output_mlds(in, di, uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module globals, options, passes_aux.
:- import_module builtin_ops, c_util, modules, tree.
:- import_module hlds_pred. % for `pred_proc_id'.
:- import_module prog_data, prog_out, llds_out.
:- import_module rtti, type_util.

:- import_module ilds, ilasm, il_peephole.
:- import_module ml_util, ml_code_util.
:- import_module mlds_to_c. /* to output C code for .cpp files */
:- use_module llds. /* for user_c_code */

:- import_module bool, int, map, string, list, assoc_list, term, std_util.
:- import_module library, require, counter.

:- import_module mlds_to_il.

%-----------------------------------------------------------------------------%


%-----------------------------------------------------------------------------%

output_mlds(MLDS) -->
	{ ModuleName = mlds__get_module_name(MLDS) },
	module_name_to_file_name(ModuleName, ".il", no, ILAsmFile),
	output_to_file(ILAsmFile, output_assembler(MLDS), Result),

		% Put the pragma C code into a C++ file.
		% This is temporary, when we have pragma foreign
		% we should just put managed C++ foreign code into
		% this file.
	( { Result = yes } ->
		module_name_to_file_name(ModuleName, "__c_code.cpp", no, 
			CPPFile),
		output_to_file(CPPFile, output_c_code(MLDS),
			_Result)
	;
		[]
	).

:- pred output_to_file(string, pred(bool, io__state, io__state),
				bool, io__state, io__state).
:- mode output_to_file(in, pred(out, di, uo) is det, out, di, uo) is det.

output_to_file(FileName, Action, Result) -->
	globals__io_lookup_bool_option(verbose, Verbose),
	globals__io_lookup_bool_option(statistics, Stats),
	maybe_write_string(Verbose, "% Writing to file `"),
	maybe_write_string(Verbose, FileName),
	maybe_write_string(Verbose, "'...\n"),
	maybe_flush_output(Verbose),
	io__tell(FileName, Res),
	( { Res = ok } ->
		Action(Result),
		io__told,
		maybe_write_string(Verbose, "% done.\n"),
		maybe_report_stats(Stats)
	;
		maybe_write_string(Verbose, "\n"),
		{ string__append_list(["can't open file `",
			FileName, "' for output."], ErrorMessage) },
		report_error(ErrorMessage),
		{ Result = no }
	).

	%
	% Generate the `.il' file
	% Also, return whether there is any C code in this file so we
	% know whether to generate a <modulename>__c_code.cpp file.
	%
:- pred output_assembler(mlds, bool, io__state, io__state).
:- mode output_assembler(in, out, di, uo) is det.

output_assembler(MLDS, ContainsCCode) -->
	{ MLDS = mlds(ModuleName, _ForeignCode, _Imports, _Defns) },
	output_src_start(ModuleName), 
	io__nl,

	generate_il(MLDS, ILAsm0, ContainsCCode),

		% Perform peephole optimization if requested.
	globals__io_lookup_bool_option(optimize_peep, Peephole),
	{ Peephole = yes ->
		il_peephole__optimize(ILAsm0, ILAsm)
	;
		ILAsm0 = ILAsm
	},
		% Output the assembly.
	ilasm__output(ILAsm),

	output_src_end(ModuleName).

	%
	% Generate the `__c_code.cpp' file which contains the pragma C
	% code.
	%
:- pred output_c_code(mlds, bool, io__state, io__state).
:- mode output_c_code(in, out, di, uo) is det.

output_c_code(MLDS, yes) -->
	{ MLDS = mlds(ModuleName, _ForeignCode, _Imports, _Defns) },
	output_src_start(ModuleName), 
	io__nl,

	generate_c_code(MLDS),

	output_src_end(ModuleName).

:- pred output_src_start(mercury_module_name, io__state, io__state).
:- mode output_src_start(in, di, uo) is det.

output_src_start(ModuleName) -->
	{ library__version(Version) },
	{ prog_out__sym_name_to_string(ModuleName, ModuleNameStr) },
	io__write_strings(
		["//\n// Automatically generated from `", 
		ModuleNameStr,
		".m' by the\n",
		"// Mercury compiler, version ", 
		Version,
		".\n",
		"// Do not edit.\n",
		"\n\n"]).

:- pred output_src_end(mercury_module_name, io__state, io__state).
:- mode output_src_end(in, di, uo) is det.

output_src_end(ModuleName) -->
	io__write_string("// End of module: "),
	prog_out__write_sym_name(ModuleName),
	io__write_string(". \n").

%-----------------------------------------------------------------------------%

	% This section could very nearly be turned into a
	% mlds_to_managed_cpp module, which turns MLDS into managed C++.
	% Note that it relies on quite a few predicates in mlds_to_il.
	% XXX we should clean up the dependencies.
	% XXX we don't output contexts for any of this.
:- pred generate_c_code(mlds, io__state, io__state).
:- mode generate_c_code(in, di, uo) is det.
generate_c_code(MLDS) -->

	{ MLDS = mlds(ModuleName, ForeignCode, _Imports, Defns) },
	{ prog_out__sym_name_to_string(ModuleName, ModuleNameStr) },
	{ ClassName = mlds_module_name_to_class_name(
		mercury_module_name_to_mlds(ModuleName)) },

	io__nl,
	io__write_strings([
		"#using <mscorlib.dll>\n",
		"using namespace System;\n",
		"#include ""mercury_cpp.h""\n",
		"using namespace mercury;\n",
		"#using ""mercury_cpp.dll""\n",
		"#using """, ModuleNameStr, ".dll""\n",
		% XXX this supresses problems caused by references to 
		% float.  If you don't do this, you'll get link errors.
		% Revisit this when the .NET implementation has matured.
		"extern ""C"" int _fltused=0;\n",
		"\n"]),

		% XXX This is a bit of a hack.  We should probably handle the
		% class name much more elegantly than this.
	( { ClassName = ["mercury" | _] } ->
		io__write_string("namespace mercury {\n")
	;
		[]
	),

	generate_foreign_header_code(mercury_module_name_to_mlds(ModuleName),
		ForeignCode),

	io__write_strings([
		"__gc public class ", ModuleNameStr, "__c_code\n",
		"{\n",
		"public:\n"]),

		% Output the contents of
		% :- pragma foreign_code(Language, Code
		% declarations.
	generate_foreign_code(mercury_module_name_to_mlds(ModuleName),
		ForeignCode),

		% Output the contents of
		% :- pragma foreign_code(Language, Pred, Flags, Code)
		% declarations.  Put each one inside a method.
	list__foldl(generate_method_c_code(
		mercury_module_name_to_mlds(ModuleName)), Defns),

	io__write_string("};\n"),

	( { ClassName = ["mercury" | _] } ->
		io__write_string("}\n")
	;
		[]
	),

	io__nl.


	% XXX we don't handle export decls.
:- pred generate_foreign_code(mlds_module_name, mlds__foreign_code,
		io__state, io__state).
:- mode generate_foreign_code(in, in, di, uo) is det.
generate_foreign_code(_ModuleName, 
		mlds__foreign_code(_RevHeaderCode, RevBodyCode,
			_ExportDefns)) -->
	{ BodyCode = list__reverse(RevBodyCode) },
	io__write_list(BodyCode, "\n", 
		(pred(llds__user_foreign_code(c, Code, _Context)::in,
				di, uo) is det -->
			io__write_string(Code))
			).

	% XXX we don't handle export decls.
:- pred generate_foreign_header_code(mlds_module_name, mlds__foreign_code,
		io__state, io__state).
:- mode generate_foreign_header_code(in, in, di, uo) is det.
generate_foreign_header_code(_ModuleName, 
		mlds__foreign_code(RevHeaderCode, _RevBodyCode,
			_ExportDefns)) -->
	{ HeaderCode = list__reverse(RevHeaderCode) },
	io__write_list(HeaderCode, "\n", 
		(pred(Code - _Context::in, di, uo) is det -->
			io__write_string(Code))
			).


:- pred generate_method_c_code(mlds_module_name, mlds__defn,
		io__state, io__state).
:- mode generate_method_c_code(in, in, di, uo) is det.

	% XXX we don't handle export
generate_method_c_code(_, defn(export(_), _, _, _)) --> [].
generate_method_c_code(_, defn(data(_), _, _, _)) --> [].
generate_method_c_code(_, defn(type(_, _), _, _, _)) --> [].
generate_method_c_code(ModuleName, 
		defn(function(PredLabel, ProcId, MaybeSeqNum, _PredId), 
	_Context, _DeclFlags, Entity)) -->
	( 
		{ Entity = mlds__function(_, Params, yes(Statement)) },
		{ has_target_code_statement(Statement) }
	->
		{ params_to_il_signature(ModuleName, Params, ILSignature) },
		{ predlabel_to_id(PredLabel, ProcId, MaybeSeqNum, Id) },
		io__write_string("static "),
		{ ILSignature = signature(_CallConv, ReturnType, ILArgs) },
		write_il_ret_type_as_managed_cpp_type(ReturnType),

		io__write_string(" "),

		io__write_string(Id),
		io__write_string("("),
		io__write_list(ILArgs, ", ", write_il_arg_as_managed_cpp_type),
		io__write_string(")"),
		io__nl,

		io__write_string("{\n"),
		write_managed_cpp_statement(Statement),
		io__write_string("}\n")
	;
		[]
	).

	% In order to implement the C interface, you need to
	% implement:
	%	call/6 (for calling continuations)
	%	return/1 (for returning succeeded)
	% 	block/2 (because the code is wrapped in a block, and
	%		because local variables are declared for
	%		"succeeded")
	% 	target_code/2 (where the actual code is put)
	%	assign/2 (to assign to the environment)
	%	newobj/7 (to create an environment)
	%
	% Unfortunately currently some of the "raw_target_code" is
	% C specific and won't translate well into managed C++.
	% Probably the best solution to this is to introduce some new
	% code components.
	%
	% Note that for the managed C++ backend there is a problem.
	% #import doesn't import classes in namespaces properly (yet), so we
	% can't #import .dlls that define environments.  So even if we
	% implement newobj/7, we will get errors.  
	% The work-around for this is to make sure ml_elim_nested
	% doesn't introduce environments where they aren't needed,
	% so we don't generally have to allocate anything but the local
	% environment (which is defined locally).

:- pred write_managed_cpp_statement(mlds__statement, 
	io__state, io__state).
:- mode write_managed_cpp_statement(in, di, uo) is det.
write_managed_cpp_statement(Statement) -->
	( 
			% XXX this ignores the language target.
		{ Statement = statement(atomic(target_code(
			_Lang, CodeComponents)), _) } 
	->
		io__write_list(CodeComponents, "\n", 
			write_managed_cpp_code_component)
	;
		{ Statement = statement(block(Defns, Statements), _) }
	->
		io__write_list(Defns, "", write_managed_cpp_defn_decl),
		io__write_string("{\n"),
		io__write_list(Statements, "", write_managed_cpp_statement),
		io__write_string("}\n")
	;
		{ Statement = statement(
			call(_Sig, Function, _This, Args, Results, _IsTail), 
				_Context) }
	->
		% XXX this doesn't work for continuations because 
		% a) I don't know how to call a function pointer in
		%    managed C++.
		% b) Function pointers are represented as integers,
		%    and we don't do any casting for them.
		% The nondet interface might need to be reworked in
		% this case.
		% The workaround at the moment is to make sure we don't
		% actually generate calls to continuations in managed
		% C++, instead we generate a nested function that is
		% implemented in IL that does the continuation call, and
		% just call the nested function instead.  Sneaky, eh?
		( { Results = [] } ->
			[]
		; { Results = [Lval] } ->
			write_managed_cpp_lval(Lval),
			io__write_string(" = ")
		;
			{ sorry("multiple return values") }
		),
		write_managed_cpp_rval(Function),
		io__write_string("("),
		io__write_list(Args, ", ", write_managed_cpp_rval),
		io__write_string(");\n")
	;
		{ Statement = statement(return(Rvals), _) }
	->
		( { Rvals = [Rval] } ->
			io__write_string("return "),
			write_managed_cpp_rval(Rval),
			io__write_string(";\n")
		;
			{ sorry("multiple return values") }
		)
	;
		{ Statement = statement(atomic(assign(Lval, Rval)), _) }
	->
		write_managed_cpp_lval(Lval),
		io__write_string(" = "),
		write_managed_cpp_rval(Rval),
		io__write_string(";\n")
	;

			% XXX This is not fully implemented
		{ Statement = statement(atomic(
			new_object(Target, _MaybeTag, Type, _MaybeSize, 
				_MaybeCtorName, _Args, _ArgTypes)), _) },
		{ ILType = mlds_type_to_ilds_type(Type) },
		{ ILType = ilds__type([], class(ClassName)) }
	->
		write_managed_cpp_lval(Target),
		io__write_string(" = new "),
		write_managed_cpp_class_name(ClassName),
		io__write_string("();\n")
	;
		{ Statement = statement(atomic(Atomic), _) }
	->
		{ functor(Atomic, AtomicFunctor, Arity) },
		io__write_string("// unimplemented: atomic "), 
		io__write_string(AtomicFunctor), 
		io__write_string("/"), 
		io__write(Arity),
		io__nl

	;
		{ Statement = statement(S, _) },
		{ functor(S, SFunctor, Arity) },
		io__write_string("// unimplemented: "), 
		io__write_string(SFunctor), 
		io__write_string("/"), 
		io__write(Arity),
		io__nl
	).

	% XXX we ignore contexts
:- pred write_managed_cpp_code_component(mlds__target_code_component, 
	io__state, io__state).
:- mode write_managed_cpp_code_component(in, di, uo) is det.
write_managed_cpp_code_component(user_target_code(Code, _MaybeContext)) -->
	io__write_string(Code).
write_managed_cpp_code_component(raw_target_code(Code)) -->
	io__write_string(Code).
		% XXX we don't handle name yet.
write_managed_cpp_code_component(name(_)) --> [].
write_managed_cpp_code_component(target_code_input(Rval)) -->
	write_managed_cpp_rval(Rval).
write_managed_cpp_code_component(target_code_output(Lval)) -->
	write_managed_cpp_lval(Lval).

:- pred write_managed_cpp_rval(mlds__rval, io__state, io__state).
:- mode write_managed_cpp_rval(in, di, uo) is det.
write_managed_cpp_rval(lval(Lval)) -->
	write_managed_cpp_lval(Lval).
write_managed_cpp_rval(mkword(_Tag, _Rval)) -->
	io__write_string(" /* mkword rval -- unimplemented */ ").
write_managed_cpp_rval(const(RvalConst)) -->
	write_managed_cpp_rval_const(RvalConst).
write_managed_cpp_rval(unop(Unop, Rval)) -->
	( 
		{ Unop = cast(Type) }
	->
		io__write_string("("),
		write_managed_cpp_type(Type),
		io__write_string(") "),
		write_managed_cpp_rval(Rval)
	;
		io__write_string(" /* unop rval -- unimplemented */ ")
	).
write_managed_cpp_rval(binop(_, _, _)) -->
	io__write_string(" /* binop rval -- unimplemented */ ").
write_managed_cpp_rval(mem_addr(_)) -->
	io__write_string(" /* mem_addr rval -- unimplemented */ ").
	
:- pred write_managed_cpp_rval_const(mlds__rval_const, io__state, io__state).
:- mode write_managed_cpp_rval_const(in, di, uo) is det.
write_managed_cpp_rval_const(true) --> io__write_string("1").
write_managed_cpp_rval_const(false) --> io__write_string("0").
write_managed_cpp_rval_const(int_const(I)) --> io__write_int(I).
write_managed_cpp_rval_const(float_const(F)) --> io__write_float(F).
	% XXX We don't quote this correctly.
write_managed_cpp_rval_const(string_const(S)) --> 
	io__write_string(""""),
	io__write_string(S),
	io__write_string("""").
write_managed_cpp_rval_const(multi_string_const(_L, _S)) --> 
	io__write_string(" /* multi_string_const rval -- unimplemented */ ").
write_managed_cpp_rval_const(code_addr_const(CodeAddrConst)) --> 
	(
		{ CodeAddrConst = proc(ProcLabel, _FuncSignature) },
		{ mangle_mlds_proc_label(ProcLabel, no, ClassName,
			MangledName) },
		write_managed_cpp_class_name(ClassName),
		io__write_string("::"),
		io__write_string(MangledName)
	;
		{ CodeAddrConst = internal(ProcLabel, SeqNum,
			_FuncSignature) },
		{ mangle_mlds_proc_label(ProcLabel, yes(SeqNum), ClassName,
			MangledName) },
		write_managed_cpp_class_name(ClassName),
		io__write_string("::"),
		io__write_string(MangledName)
	).



write_managed_cpp_rval_const(data_addr_const(_)) --> 
	io__write_string(" /* data_addr_const rval -- unimplemented */ ").
write_managed_cpp_rval_const(null(_)) --> 
	io__write_string("0").

:- pred write_managed_cpp_lval(mlds__lval, io__state, io__state).
:- mode write_managed_cpp_lval(in, di, uo) is det.
write_managed_cpp_lval(field(_, Rval, named_field(FieldId, _Type), _, _)) -->
	io__write_string("("),
	write_managed_cpp_rval(Rval),
	io__write_string(")"),
	io__write_string("->"),
	{ FieldId = qual(_, FieldName) },
	io__write_string(FieldName).

write_managed_cpp_lval(field(_, _, offset(_), _, _)) -->
	io__write_string(" /* offset field lval -- unimplemented */ ").
write_managed_cpp_lval(mem_ref(Rval, _)) -->
	io__write_string("*"),
	write_managed_cpp_rval(Rval).
write_managed_cpp_lval(var(Var)) -->
	{ mangle_mlds_var(Var, Id) },
	io__write_string(Id).

:- pred write_managed_cpp_defn_decl(mlds__defn, io__state, io__state).
:- mode write_managed_cpp_defn_decl(in, di, uo) is det.
write_managed_cpp_defn_decl(Defn) -->
	{ Defn = mlds__defn(Name, _Context, _Flags, DefnBody) },
	( { DefnBody = data(Type, _Initializer) },
  	  { Name = data(var(VarName)) }
	->
		write_managed_cpp_type(Type),
		io__write_string(" "),
		io__write_string(VarName),
		io__write_string(";\n")
	;
		io__write_string("// unimplemented defn decl\n")
	).

:- pred write_managed_cpp_type(mlds__type, io__state, io__state).
:- mode write_managed_cpp_type(in, di, uo) is det.
write_managed_cpp_type(Type) -->
	{ ILType = mlds_type_to_ilds_type(Type) },
	write_il_type_as_managed_cpp_type(ILType).

	% XXX this could be more efficient
:- pred has_target_code_statement(mlds__statement).
:- mode has_target_code_statement(in) is semidet.
has_target_code_statement(Statement) :-
	GetTargetCode = (pred(SubStatement::out) is nondet :-
		statement_contains_statement(Statement, SubStatement),
		SubStatement = statement(atomic(target_code(_, _)), _) 
		),
	solutions(GetTargetCode, [_|_]).



:- pred write_il_ret_type_as_managed_cpp_type(ret_type::in,
	io__state::di, io__state::uo) is det.
write_il_ret_type_as_managed_cpp_type(void) --> io__write_string("void").
write_il_ret_type_as_managed_cpp_type(simple_type(T)) --> 
	write_il_simple_type_as_managed_cpp_type(T).

	% XXX need to revisit this and choose types appropriately
:- pred write_il_simple_type_as_managed_cpp_type(simple_type::in,
	io__state::di, io__state::uo) is det.
write_il_simple_type_as_managed_cpp_type(int8) --> 
	io__write_string("MR_Integer8").
write_il_simple_type_as_managed_cpp_type(int16) --> 
	io__write_string("MR_Integer16").
write_il_simple_type_as_managed_cpp_type(int32) --> 
	io__write_string("MR_Integer").
write_il_simple_type_as_managed_cpp_type(int64) --> 
	io__write_string("MR_Integer64").
write_il_simple_type_as_managed_cpp_type(uint8) --> 
	io__write_string("unsigned int").
write_il_simple_type_as_managed_cpp_type(uint16) --> 
	io__write_string("unsigned int").
write_il_simple_type_as_managed_cpp_type(uint32) --> 
	io__write_string("unsigned int").
write_il_simple_type_as_managed_cpp_type(uint64) --> 
	io__write_string("unsigned int").
write_il_simple_type_as_managed_cpp_type(native_int) --> 
	io__write_string("MR_Integer").
write_il_simple_type_as_managed_cpp_type(native_uint) --> 
	io__write_string("unsigned int").
write_il_simple_type_as_managed_cpp_type(float32) --> 
	io__write_string("float").
write_il_simple_type_as_managed_cpp_type(float64) --> 
	io__write_string("MR_Float").
write_il_simple_type_as_managed_cpp_type(native_float) --> 
	io__write_string("MR_Float").
write_il_simple_type_as_managed_cpp_type(bool) --> 
	io__write_string("MR_Integer").
write_il_simple_type_as_managed_cpp_type(char) --> 
	io__write_string("MR_Char").
write_il_simple_type_as_managed_cpp_type(refany) --> 
	io__write_string("MR_RefAny").
write_il_simple_type_as_managed_cpp_type(class(ClassName)) --> 
	( { ClassName = il_generic_class_name } ->
		io__write_string("MR_Box")
	;
		io__write_string("class "),
		write_managed_cpp_class_name(ClassName),
		io__write_string(" *")
	).
		% XXX this is not the right syntax
write_il_simple_type_as_managed_cpp_type(value_class(ClassName)) --> 
	io__write_string("value class "),
	write_managed_cpp_class_name(ClassName),
	io__write_string(" *").
		% XXX this is not the right syntax
write_il_simple_type_as_managed_cpp_type(interface(ClassName)) --> 
	io__write_string("interface "),
	write_managed_cpp_class_name(ClassName),
	io__write_string(" *").
		% XXX this needs more work
write_il_simple_type_as_managed_cpp_type('[]'(_Type, _Bounds)) --> 
	io__write_string("MR_Word").
write_il_simple_type_as_managed_cpp_type('&'(Type)) --> 
	io__write_string("MR_Ref("),
	write_il_type_as_managed_cpp_type(Type),
	io__write_string(")").
write_il_simple_type_as_managed_cpp_type('*'(Type)) --> 
	write_il_type_as_managed_cpp_type(Type),
	io__write_string(" *").

:- pred write_managed_cpp_class_name(structured_name::in, io__state::di,
	io__state::uo) is det.
write_managed_cpp_class_name(ClassName0) -->
	{ ClassName = drop_assemblies_from_class_name(ClassName0) },
	io__write_list(ClassName, "::", io__write_string).

:- pred write_il_type_as_managed_cpp_type(ilds__type::in,
	io__state::di, io__state::uo) is det.
write_il_type_as_managed_cpp_type(ilds__type(Modifiers, SimpleType)) -->
	io__write_list(Modifiers, " ", 
		write_il_type_modifier_as_managed_cpp_type),
	write_il_simple_type_as_managed_cpp_type(SimpleType).

:- pred write_il_type_modifier_as_managed_cpp_type(ilds__type_modifier::in,
	io__state::di, io__state::uo) is det.
write_il_type_modifier_as_managed_cpp_type(const) --> 
	io__write_string("const").
write_il_type_modifier_as_managed_cpp_type(readonly) --> 
	io__write_string("readonly").
write_il_type_modifier_as_managed_cpp_type(volatile) --> 
	io__write_string("volatile").

:- pred write_il_arg_as_managed_cpp_type(pair(ilds__type,
	maybe(ilds__id))::in, io__state::di, io__state::uo) is det.
write_il_arg_as_managed_cpp_type(Type - MaybeId) --> 
	write_il_type_as_managed_cpp_type(Type),
	( { MaybeId = yes(Id) } ->
		io__write_string(" "),
		io__write_string(Id)
	;
		% XXX should make up a name!
		{ unexpected("unnamed argument in method parameters") }
	).


:- func drop_assemblies_from_class_name(structured_name) = 
	structured_name.

drop_assemblies_from_class_name([]) = [].
drop_assemblies_from_class_name([A | Rest]) = 
	( ( A = "mscorlib" ; A = "mercury" ) -> Rest ; [A | Rest] ).

