%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2001 The University of Melbourne.
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
:- import_module rtti, type_util, error_util.

:- import_module ilds, ilasm, il_peephole.
:- import_module ml_util, ml_code_util.
:- import_module mlds_to_csharp. /* to output C sharp code */
:- import_module mlds_to_mcpp. /* to output MC++ code */
:- use_module llds. /* for user_c_code */

:- import_module bool, int, map, string, set, list, assoc_list, term, std_util.
:- import_module library, require, counter.

:- import_module mlds_to_il.

%-----------------------------------------------------------------------------%


%-----------------------------------------------------------------------------%

output_mlds(MLDS) -->
	{ ModuleName = mlds__get_module_name(MLDS) },
	module_name_to_file_name(ModuleName, ".il", yes, ILAsmFile),
	output_to_file(ILAsmFile, output_assembler(MLDS), Result),

	( { Result = yes(ForeignLangs) } ->
		% Output any outline foreign_code to the appropriate foreign
		% language file.
		list__foldl(output_foreign_file(MLDS),
			set__to_sorted_list(ForeignLangs))
	;
		% An I/O error occurred; output_to_file has already reported
		% an error message, so we don't need to do anything here.
		[]
	).

:- pred output_foreign_file(mlds::in, foreign_language::in,
		io__state::di, io__state::uo) is det.

output_foreign_file(MLDS, ForeignLang) -->
	{ ModuleName = mlds__get_module_name(MLDS) },
	{ handle_foreign_lang(ForeignLang, Extension, CodeGenerator) },
	module_name_to_file_name(ModuleName, Extension, yes, File),
	output_to_file(File, (pred(di, uo) is det --> CodeGenerator(MLDS))).

:- pred handle_foreign_lang(foreign_language::in, string::out,
		pred(mlds, io__state, io__state)::out(pred(in, di, uo) is det))
		is det.

handle_foreign_lang(managed_cplusplus, "__cpp_code.cpp", output_mcpp_code).
handle_foreign_lang(csharp, "__csharp_code.cs", output_csharp_code).
handle_foreign_lang(c, _, _) :-
	sorry(this_file, "language C foreign code not supported").
handle_foreign_lang(il, _, _) :-
	sorry(this_file, "language IL foreign code not supported").

	%
	% Generate the `.il' file.
	% Returns the set of foreign language
	%
:- pred output_assembler(mlds, set(foreign_language), io__state, io__state).
:- mode output_assembler(in, out, di, uo) is det.

output_assembler(MLDS, ForeignLangs) -->
	{ MLDS = mlds(ModuleName, _ForeignCode, _Imports, _Defns) },
	output_src_start(ModuleName), 
	io__nl,

	generate_il(MLDS, ILAsm0, ForeignLangs),

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

:- func this_file = string.
this_file = "mlds_to_ilasm.m".

:- end_module mlds_to_ilasm.
