%-----------------------------------------------------------------------------%
% Copyright (C) 2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% This module contains code to output the RTTI data structures
% defined in rtti.m as C code.
%
% This module is part of the LLDS back-end.  The decl_set data type
% that it uses, which is defined in llds_out.m, represents a set of LLDS
% declarations, and thus depends on the LLDS.  Also the code to output
% code_addrs depends on the LLDS.
%
% The MLDS back-end does not use this module; instead it converts the RTTI
% data structures to MLDS (and then to C or Java, etc.).
%
% Main author: zs.
%
%-----------------------------------------------------------------------------%

:- module rtti_out.

:- interface.

:- import_module prog_data, hlds_data.
:- import_module rtti, llds_out.
:- import_module bool, io.

	% output a C expression holding the address of the C name of
	% the specified rtti_data
:- pred output_addr_of_rtti_data(rtti_data::in, io__state::di, io__state::uo)
	is det.

	% Output a C declaration for the rtti_data.
:- pred output_rtti_data_decl(rtti_data::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

	% Output a C definition for the rtti_data.
:- pred output_rtti_data_defn(rtti_data::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

	% Output C code (e.g. a call to the MR_INIT_TYPE_CTOR_INFO() macro)
	% to initialize the rtti_data if necessary.
:- pred rtti_out__init_rtti_data_if_nec(rtti_data::in,
	io__state::di, io__state::uo) is det.

	% Output C code (e.g. a call to MR_register_type_ctor_info())
	% to register the rtti_data in the type tables, if it represents a data
	% structure that should be so registered. The bool should be the value
	% of the --split-c-files option; it governs whether the rtti_data is
	% declared in the generated code or not.
:- pred rtti_out__register_rtti_data_if_nec(rtti_data::in,
	bool::in, io__state::di, io__state::uo) is det.

	% Output the C name of the rtti_data specified by the given
	% rtti_type_id and rtti_name.
:- pred output_rtti_addr(rtti_type_id::in, rtti_name::in,
	io__state::di, io__state::uo) is det.

	% Output the C storage class, C type, and C name of the rtti_data 
	% specified by the given rtti_type_id and rtti_name,
	% for use in a declaration or definition.
	% The bool should be `yes' iff it is for a definition.
:- pred output_rtti_addr_storage_type_name(rtti_type_id::in, rtti_name::in,
	bool::in, io__state::di, io__state::uo) is det.

	% The same as output_rtti_addr_storage_type_name,
	% but for a base_typeclass_info.
:- pred output_base_typeclass_info_storage_type_name(module_name::in,
		class_id::in, string::in, bool::in,
		io__state::di, io__state::uo) is det.

        % Return true iff the given type of RTTI data structure includes
	% code addresses.
:- pred rtti_name_would_include_code_addr(rtti_name::in, bool::out) is det.

:- pred rtti_name_linkage(rtti_name::in, linkage::out) is det.

	% rtti_name_c_type(RttiName, Type, TypeSuffix):
	%	The type of the specified RttiName is given by Type
	%	and TypeSuffix, which are C code fragments suitable
	%	for use in a C declaration `<TypeName> foo <TypeSuffix>'.
	%	TypeSuffix will be "[]" if the given RttiName
	%	has an array type.
:- pred rtti_name_c_type(rtti_name::in, string::out, string::out) is det.

:- implementation.

:- import_module pseudo_type_info, code_util, llds, prog_out, c_util.
:- import_module options, globals.
:- import_module int, string, list, require, std_util.

%-----------------------------------------------------------------------------%

output_rtti_data_defn(exist_locns(RttiTypeId, Ordinal, Locns),
		DeclSet0, DeclSet) -->
	output_generic_rtti_data_defn_start(RttiTypeId, exist_locns(Ordinal),
		DeclSet0, DeclSet),
	(
			% ANSI/ISO C doesn't allow empty arrays, so
			% place a dummy value in the array if necessary.
		{ Locns = [] }
	->
		io__write_string("= { {0, 0} };\n")
	;
		io__write_string(" = {\n"),
		output_exist_locns(Locns),
		io__write_string("};\n")
	).
output_rtti_data_defn(exist_info(RttiTypeId, Ordinal, Plain, InTci, Tci,
		Locns), DeclSet0, DeclSet) -->
	output_rtti_addr_decls(RttiTypeId, Locns, "", "", 0, _,
		DeclSet0, DeclSet1),
	output_generic_rtti_data_defn_start(RttiTypeId, exist_info(Ordinal),
		DeclSet1, DeclSet),
	io__write_string(" = {\n\t"),
	io__write_int(Plain),
	io__write_string(",\n\t"),
	io__write_int(InTci),
	io__write_string(",\n\t"),
	io__write_int(Tci),
	io__write_string(",\n\t"),
	output_rtti_addr(RttiTypeId, Locns),
	io__write_string("\n};\n").
output_rtti_data_defn(field_names(RttiTypeId, Ordinal, MaybeNames),
		DeclSet0, DeclSet) -->
	output_generic_rtti_data_defn_start(RttiTypeId, field_names(Ordinal),
		DeclSet0, DeclSet),
	(
			% ANSI/ISO C doesn't allow empty arrays, so
			% place a dummy value in the array if necessary.
		{ MaybeNames = [] }
	->
		io__write_string("= { "" };\n")
	;
		io__write_string(" = {\n"),
		output_maybe_quoted_strings(MaybeNames),
		io__write_string("};\n")
	).
output_rtti_data_defn(field_types(RttiTypeId, Ordinal, Types),
		DeclSet0, DeclSet) -->
	output_rtti_datas_decls(Types, "", "", 0, _, DeclSet0, DeclSet1),
	output_generic_rtti_data_defn_start(RttiTypeId, field_types(Ordinal),
		DeclSet1, DeclSet),
	(
			% ANSI/ISO C doesn't allow empty arrays, so
			% place a dummy value in the array if necessary.
		{ Types = [] }
	->
		io__write_string("= { NULL };\n")
	;
		io__write_string(" = {\n"),
		output_addr_of_rtti_datas(Types),
		io__write_string("};\n")
	).
output_rtti_data_defn(enum_functor_desc(RttiTypeId, FunctorName, Ordinal),
		DeclSet0, DeclSet) -->
	output_generic_rtti_data_defn_start(RttiTypeId,
		enum_functor_desc(Ordinal), DeclSet0, DeclSet),
	io__write_string(" = {\n\t"""),
	c_util__output_quoted_string(FunctorName),
	io__write_string(""",\n\t"),
	io__write_int(Ordinal),
	io__write_string("\n};\n").
output_rtti_data_defn(notag_functor_desc(RttiTypeId, FunctorName, ArgType),
		DeclSet0, DeclSet) -->
	output_rtti_data_decls(ArgType, "", "", 0, _, DeclSet0, DeclSet1),
	output_generic_rtti_data_defn_start(RttiTypeId, notag_functor_desc,
		DeclSet1, DeclSet),
	io__write_string(" = {\n\t"""),
	c_util__output_quoted_string(FunctorName),
	io__write_string(""",\n\t "),
	output_addr_of_rtti_data(ArgType),
	io__write_string("\n};\n").
output_rtti_data_defn(du_functor_desc(RttiTypeId, FunctorName, Ptag, Stag,
		Locn, Ordinal, Arity, ContainsVarBitVector, ArgTypes,
		MaybeNames, MaybeExist),
		DeclSet0, DeclSet) -->
	output_rtti_addr_decls(RttiTypeId, ArgTypes, "", "", 0, _,
		DeclSet0, DeclSet1),
	(
		{ MaybeNames = yes(NamesInfo1) },
		output_rtti_addr_decls(RttiTypeId, NamesInfo1, "", "",
			0, _, DeclSet1, DeclSet2)
	;
		{ MaybeNames = no },
		{ DeclSet2 = DeclSet1 }
	),
	(
		{ MaybeExist = yes(ExistInfo1) },
		output_rtti_addr_decls(RttiTypeId, ExistInfo1, "", "",
			0, _, DeclSet2, DeclSet3)
	;
		{ MaybeExist = no },
		{ DeclSet3 = DeclSet2 }
	),
	output_generic_rtti_data_defn_start(RttiTypeId,
		du_functor_desc(Ordinal), DeclSet3, DeclSet),
	io__write_string(" = {\n\t"""),
	c_util__output_quoted_string(FunctorName),
	io__write_string(""",\n\t"),
	io__write_int(Arity),
	io__write_string(",\n\t"),
	io__write_int(ContainsVarBitVector),
	io__write_string(",\n\t"),
	{ rtti__sectag_locn_to_string(Locn, LocnStr) },
	io__write_string(LocnStr),
	io__write_string(",\n\t"),
	io__write_int(Ptag),
	io__write_string(",\n\t"),
	io__write_int(Stag),
	io__write_string(",\n\t"),
	io__write_int(Ordinal),
	io__write_string(",\n\t"),
	io__write_string("(MR_PseudoTypeInfo *) "), % cast away const
	output_addr_of_rtti_addr(RttiTypeId, ArgTypes),
	io__write_string(",\n\t"),
	(
		{ MaybeNames = yes(NamesInfo2) },
		output_rtti_addr(RttiTypeId, NamesInfo2)
	;
		{ MaybeNames = no },
		io__write_string("NULL")
	),
	io__write_string(",\n\t"),
	(
		{ MaybeExist = yes(ExistInfo2) },
		output_addr_of_rtti_addr(RttiTypeId, ExistInfo2)
	;
		{ MaybeExist = no },
		io__write_string("NULL")
	),
	io__write_string("\n};\n").
output_rtti_data_defn(enum_name_ordered_table(RttiTypeId, Functors),
		DeclSet0, DeclSet) -->
	output_rtti_addrs_decls(RttiTypeId, Functors, "", "", 0, _,
		DeclSet0, DeclSet1),
	output_generic_rtti_data_defn_start(RttiTypeId,
		enum_name_ordered_table, DeclSet1, DeclSet),
	io__write_string(" = {\n"),
	output_addr_of_rtti_addrs(RttiTypeId, Functors),
	io__write_string("};\n").
output_rtti_data_defn(enum_value_ordered_table(RttiTypeId, Functors),
		DeclSet0, DeclSet) -->
	output_rtti_addrs_decls(RttiTypeId, Functors, "", "", 0, _,
		DeclSet0, DeclSet1),
	output_generic_rtti_data_defn_start(RttiTypeId,
		enum_value_ordered_table, DeclSet1, DeclSet),
	io__write_string(" = {\n"),
	output_addr_of_rtti_addrs(RttiTypeId, Functors),
	io__write_string("};\n").
output_rtti_data_defn(du_name_ordered_table(RttiTypeId, Functors),
		DeclSet0, DeclSet) -->
	output_rtti_addrs_decls(RttiTypeId, Functors, "", "", 0, _,
		DeclSet0, DeclSet1),
	output_generic_rtti_data_defn_start(RttiTypeId,
		du_name_ordered_table, DeclSet1, DeclSet),
	io__write_string(" = {\n"),
	output_addr_of_rtti_addrs(RttiTypeId, Functors),
	io__write_string("};\n").
output_rtti_data_defn(du_stag_ordered_table(RttiTypeId, Ptag, Sharers),
		DeclSet0, DeclSet) -->
	output_rtti_addrs_decls(RttiTypeId, Sharers, "", "", 0, _,
		DeclSet0, DeclSet1),
	output_generic_rtti_data_defn_start(RttiTypeId,
		du_stag_ordered_table(Ptag), DeclSet1, DeclSet),
	io__write_string(" = {\n"),
	output_addr_of_rtti_addrs(RttiTypeId, Sharers),
	io__write_string("\n};\n").
output_rtti_data_defn(du_ptag_ordered_table(RttiTypeId, PtagLayouts),
		DeclSet0, DeclSet) -->
	output_ptag_layout_decls(PtagLayouts, RttiTypeId, DeclSet0, DeclSet1),
	output_generic_rtti_data_defn_start(RttiTypeId,
		du_ptag_ordered_table, DeclSet1, DeclSet),
	io__write_string(" = {\n"),
	output_ptag_layout_defns(PtagLayouts, RttiTypeId),
	io__write_string("\n};\n").
output_rtti_data_defn(type_ctor_info(RttiTypeId, Unify, Compare,
		CtorRep, Solver, Init, Version, NumPtags, NumFunctors,
		FunctorsInfo, LayoutInfo, _MaybeHashCons, _Prettyprinter),
		DeclSet0, DeclSet) -->
	{ UnifyCA   = make_maybe_code_addr(Unify) },
	{ CompareCA = make_maybe_code_addr(Compare) },
	{ SolverCA  = make_maybe_code_addr(Solver) },
	{ InitCA    = make_maybe_code_addr(Init) },
	{ MaybeCodeAddrs = [UnifyCA, CompareCA, SolverCA, InitCA] },
	{ CodeAddrs = list__filter_map(func(yes(CA)) = CA is semidet,
		MaybeCodeAddrs) },
	output_code_addrs_decls(CodeAddrs, "", "", 0, _, DeclSet0, DeclSet1),
	output_functors_info_decl(RttiTypeId, FunctorsInfo,
		DeclSet1, DeclSet2),
	output_layout_info_decl(RttiTypeId, LayoutInfo, DeclSet2, DeclSet3),
	output_generic_rtti_data_defn_start(RttiTypeId,
		type_ctor_info, DeclSet3, DeclSet),
	io__write_string(" = {\n\t"),
	{ RttiTypeId = rtti_type_id(Module, Type, TypeArity) },
	io__write_int(TypeArity),
	io__write_string(",\n\t"),
	output_maybe_static_code_addr(UnifyCA),
	io__write_string(",\n\t"),
	output_maybe_static_code_addr(UnifyCA),
	io__write_string(",\n\t"),
	output_maybe_static_code_addr(CompareCA),
	io__write_string(",\n\t"),
	{ rtti__type_ctor_rep_to_string(CtorRep, CtorRepStr) },
	io__write_string(CtorRepStr),
	io__write_string(",\n\t"),
	output_maybe_static_code_addr(SolverCA),
	io__write_string(",\n\t"),
	output_maybe_static_code_addr(InitCA),
	io__write_string(",\n\t"""),
	{ prog_out__sym_name_to_string(Module, ModuleName) },
	c_util__output_quoted_string(ModuleName),
	io__write_string(""",\n\t"""),
	c_util__output_quoted_string(Type),
	io__write_string(""",\n\t"),
	io__write_int(Version),
	io__write_string(",\n\t"),
	(
		{ FunctorsInfo = enum_functors(EnumFunctorsInfo) },
		io__write_string("{ (void *) "),
		output_rtti_addr(RttiTypeId, EnumFunctorsInfo),
		io__write_string(" }")
	;
		{ FunctorsInfo = notag_functors(NotagFunctorsInfo) },
		io__write_string("{ (void *) &"),
		output_rtti_addr(RttiTypeId, NotagFunctorsInfo),
		io__write_string(" }")
	;
		{ FunctorsInfo = du_functors(DuFunctorsInfo) },
		io__write_string("{ (void *) "),
		output_rtti_addr(RttiTypeId, DuFunctorsInfo),
		io__write_string(" }")
	;
		{ FunctorsInfo = no_functors },
		io__write_string("{ 0 }")
	),
	io__write_string(",\n\t"),
	(
		{ LayoutInfo = enum_layout(EnumLayoutInfo) },
		io__write_string("{ (void *) "),
		output_rtti_addr(RttiTypeId, EnumLayoutInfo),
		io__write_string(" }")
	;
		{ LayoutInfo = notag_layout(NotagLayoutInfo) },
		io__write_string("{ (void *) &"),
		output_rtti_addr(RttiTypeId, NotagLayoutInfo),
		io__write_string(" }")
	;
		{ LayoutInfo = du_layout(DuLayoutInfo) },
		io__write_string("{ (void *) "),
		output_rtti_addr(RttiTypeId, DuLayoutInfo),
		io__write_string(" }")
	;
		{ LayoutInfo = equiv_layout(EquivTypeInfo) },
		io__write_string("{ (void *) "),
		output_addr_of_rtti_data(EquivTypeInfo),
		io__write_string(" }")
	;
		{ LayoutInfo = no_layout },
		io__write_string("{ 0 }")
	),
	io__write_string(",\n\t"),
	io__write_int(NumFunctors),
	io__write_string(",\n\t"),
	io__write_int(NumPtags),
% This code is commented out while the corresponding fields of the
% MR_TypeCtorInfo_Struct type are commented out.
%
%	io__write_string(",\n\t"),
%	(
%		{ MaybeHashCons = yes(HashConsDataAddr) },
%		io__write_string("&"),
%		output_rtti_addr(RttiTypeId, HashConsDataAddr)
%	;
%		{ MaybeHashCons = no },
%		io__write_string("NULL")
%	),
%	io__write_string(",\n\t"),
%	output_maybe_static_code_addr(Prettyprinter),
	io__write_string("\n};\n").
output_rtti_data_defn(base_typeclass_info(InstanceModuleName, ClassId,
		InstanceString, BaseTypeClassInfo), DeclSet0, DeclSet) -->
	output_base_typeclass_info_defn(InstanceModuleName, ClassId,
		InstanceString, BaseTypeClassInfo, DeclSet0, DeclSet).
output_rtti_data_defn(pseudo_type_info(Pseudo), DeclSet0, DeclSet) -->
	output_pseudo_type_info_defn(Pseudo, DeclSet0, DeclSet).

:- pred output_base_typeclass_info_defn(module_name, class_id, string,
		base_typeclass_info, decl_set, decl_set, io__state, io__state).
:- mode output_base_typeclass_info_defn(in, in, in, in, in, out, di, uo) is det.

output_base_typeclass_info_defn(InstanceModuleName, ClassId, InstanceString,
		base_typeclass_info(N1, N2, N3, N4, N5, Methods),
		DeclSet0, DeclSet) -->
	{ CodeAddrs = list__map(make_code_addr, Methods) },
	output_code_addrs_decls(CodeAddrs, "", "", 0, _, DeclSet0, DeclSet1),
	io__write_string("\n"),
	output_base_typeclass_info_storage_type_name(InstanceModuleName,
		ClassId, InstanceString, yes),
	% XXX It would be nice to avoid generating redundant declarations
	% of base_typeclass_infos, but currently we don't.
	{ DeclSet1 = DeclSet },
	io__write_string(" = {\n\t(MR_Code *) "),
	io__write_list([N1, N2, N3, N4, N5],
		",\n\t(MR_Code *) ", io__write_int),
	io__write_string(",\n\t"),
	io__write_list(CodeAddrs, ",\n\t", output_static_code_addr),
	io__write_string("\n};\n").

:- func make_maybe_code_addr(maybe(rtti_proc_label)) = maybe(code_addr).
make_maybe_code_addr(no) = no.
make_maybe_code_addr(yes(ProcLabel)) = yes(make_code_addr(ProcLabel)).

:- func make_code_addr(rtti_proc_label) = code_addr.
make_code_addr(ProcLabel) = CodeAddr :-
	code_util__make_entry_label_from_rtti(ProcLabel, no, CodeAddr).

:- pred output_pseudo_type_info_defn(pseudo_type_info, decl_set, decl_set,
		io__state, io__state).
:- mode output_pseudo_type_info_defn(in, in, out, di, uo) is det.

output_pseudo_type_info_defn(type_var(_), DeclSet, DeclSet) --> [].
output_pseudo_type_info_defn(type_ctor_info(_), DeclSet, DeclSet) --> [].
output_pseudo_type_info_defn(TypeInfo, DeclSet0, DeclSet) -->
	{ TypeInfo = type_info(RttiTypeId, ArgTypes) },
	{ TypeCtorRttiData = pseudo_type_info(type_ctor_info(RttiTypeId)) },
	{ ArgRttiDatas = list__map(func(P) = pseudo_type_info(P), ArgTypes) },
	output_rtti_data_decls(TypeCtorRttiData, "", "", 0, _, DeclSet0, DeclSet1),
	output_rtti_datas_decls(ArgRttiDatas, "", "", 0, _, DeclSet1, DeclSet2),
	output_generic_rtti_data_defn_start(RttiTypeId,
		pseudo_type_info(TypeInfo), DeclSet2, DeclSet),
	io__write_string(" = {\n\t&"),
	output_rtti_addr(RttiTypeId, type_ctor_info),
	io__write_string(",\n{"),
	output_addr_of_rtti_datas(ArgRttiDatas),
	io__write_string("}};\n").
output_pseudo_type_info_defn(HO_TypeInfo, DeclSet0, DeclSet) -->
	{ HO_TypeInfo = higher_order_type_info(RttiTypeId, Arity, ArgTypes) },
	{ TypeCtorRttiData = pseudo_type_info(type_ctor_info(RttiTypeId)) },
	{ ArgRttiDatas = list__map(func(P) = pseudo_type_info(P), ArgTypes) },
	output_rtti_data_decls(TypeCtorRttiData, "", "", 0, _, DeclSet0, DeclSet1),
	output_rtti_datas_decls(ArgRttiDatas, "", "", 0, _, DeclSet1, DeclSet2),
	output_generic_rtti_data_defn_start(RttiTypeId,
		pseudo_type_info(HO_TypeInfo), DeclSet2, DeclSet),
	io__write_string(" = {\n\t&"),
	output_rtti_addr(RttiTypeId, type_ctor_info),
	io__write_string(",\n\t"),
	io__write_int(Arity),
	io__write_string(",\n{"),
	output_addr_of_rtti_datas(ArgRttiDatas),
	io__write_string("}};\n").

:- pred output_functors_info_decl(rtti_type_id::in,
	type_ctor_functors_info::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_functors_info_decl(RttiTypeId, enum_functors(EnumFunctorsInfo),
		DeclSet0, DeclSet) -->
	output_generic_rtti_data_decl(RttiTypeId, EnumFunctorsInfo,
		DeclSet0, DeclSet).
output_functors_info_decl(RttiTypeId, notag_functors(NotagFunctorsInfo),
		DeclSet0, DeclSet) -->
	output_generic_rtti_data_decl(RttiTypeId, NotagFunctorsInfo,
		DeclSet0, DeclSet).
output_functors_info_decl(RttiTypeId, du_functors(DuFunctorsInfo),
		DeclSet0, DeclSet) -->
	output_generic_rtti_data_decl(RttiTypeId, DuFunctorsInfo,
		DeclSet0, DeclSet).
output_functors_info_decl(_RttiTypeId, no_functors, DeclSet, DeclSet) --> [].

:- pred output_layout_info_decl(rtti_type_id::in, type_ctor_layout_info::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_layout_info_decl(RttiTypeId, enum_layout(EnumLayoutInfo),
		DeclSet0, DeclSet) -->
	output_generic_rtti_data_decl(RttiTypeId, EnumLayoutInfo,
		DeclSet0, DeclSet).
output_layout_info_decl(RttiTypeId, notag_layout(NotagLayoutInfo),
		DeclSet0, DeclSet) -->
	output_generic_rtti_data_decl(RttiTypeId, NotagLayoutInfo,
		DeclSet0, DeclSet).
output_layout_info_decl(RttiTypeId, du_layout(DuLayoutInfo),
		DeclSet0, DeclSet) -->
	output_generic_rtti_data_decl(RttiTypeId, DuLayoutInfo,
		DeclSet0, DeclSet).
output_layout_info_decl(_RttiTypeId, equiv_layout(EquivRttiData),
		DeclSet0, DeclSet) -->
	output_rtti_data_decl(EquivRttiData, DeclSet0, DeclSet).
output_layout_info_decl(_RttiTypeId, no_layout, DeclSet, DeclSet) --> [].

:- pred output_ptag_layout_decls(list(du_ptag_layout)::in, rtti_type_id::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_ptag_layout_decls([], _, DeclSet, DeclSet) --> [].
output_ptag_layout_decls([DuPtagLayout | DuPtagLayouts], RttiTypeId,
		DeclSet0, DeclSet) -->
	{ DuPtagLayout = du_ptag_layout(_, _, Descriptors) },
	output_rtti_addr_decls(RttiTypeId, Descriptors, "", "", 0, _,
		DeclSet0, DeclSet1),
	output_ptag_layout_decls(DuPtagLayouts, RttiTypeId, DeclSet1, DeclSet).

:- pred output_ptag_layout_defns(list(du_ptag_layout)::in, rtti_type_id::in,
	io__state::di, io__state::uo) is det.

output_ptag_layout_defns([], _) --> [].
output_ptag_layout_defns([DuPtagLayout | DuPtagLayouts], RttiTypeId) -->
	{ DuPtagLayout = du_ptag_layout(NumSharers, Locn, Descriptors) },
	io__write_string("\t{ "),
	io__write_int(NumSharers),
	io__write_string(", "),
	{ rtti__sectag_locn_to_string(Locn, LocnStr) },
	io__write_string(LocnStr),
	io__write_string(",\n\t"),
	output_rtti_addr(RttiTypeId, Descriptors),
	( { DuPtagLayouts = [] } ->
		io__write_string(" }\n")
	;
		io__write_string(" },\n")
	),
	output_ptag_layout_defns(DuPtagLayouts, RttiTypeId).

%-----------------------------------------------------------------------------%

output_rtti_data_decl(RttiData, DeclSet0, DeclSet) -->
	( { RttiData = pseudo_type_info(type_var(_)) } ->
		% These just get represented as integers,
		% so we don't need to declare them.
		% Also rtti_data_to_name/3 does not handle this case.
		{ DeclSet = DeclSet0 }
	;
		{ RttiData = base_typeclass_info(InstanceModuleName, ClassId,
			InstanceStr, _) }
	->
		% rtti_data_to_name/3 does not handle this case
		output_base_typeclass_info_decl(InstanceModuleName, ClassId,
			InstanceStr, no, DeclSet0, DeclSet)
	;
		{ rtti_data_to_name(RttiData, RttiTypeId, RttiName) },
		output_generic_rtti_data_decl(RttiTypeId, RttiName,
			DeclSet0, DeclSet)
	).

:- pred output_base_typeclass_info_decl(module_name::in, class_id::in,
		string::in, bool::in, decl_set::in, decl_set::out,
		io__state::di, io__state::uo) is det.

output_base_typeclass_info_decl(InstanceModuleName, ClassId, InstanceStr,
		BeingDefined, DeclSet0, DeclSet) -->
	output_base_typeclass_info_storage_type_name(InstanceModuleName,
			ClassId, InstanceStr, BeingDefined),
	io__write_string(";\n"),
	% XXX It would be nice to avoid generating redundant declarations
	% of base_typeclass_infos, but currently we don't.
	{ DeclSet = DeclSet0 }.

output_base_typeclass_info_storage_type_name(InstanceModuleName, ClassId,
		InstanceStr, BeingDefined) -->
	output_rtti_name_storage_type_name(
		output_base_typeclass_info_name(ClassId, InstanceStr),
		base_typeclass_info(InstanceModuleName, ClassId, InstanceStr),
			BeingDefined).

%-----------------------------------------------------------------------------%

:- pred output_generic_rtti_data_decl(rtti_type_id::in, rtti_name::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_generic_rtti_data_decl(RttiTypeId, RttiName, DeclSet0, DeclSet) -->
	output_rtti_addr_storage_type_name(RttiTypeId, RttiName, no),
	io__write_string(";\n"),
	{ DataAddr = rtti_addr(RttiTypeId, RttiName) },
	{ decl_set_insert(DeclSet0, data_addr(DataAddr), DeclSet) }.

:- pred output_generic_rtti_data_defn_start(rtti_type_id::in, rtti_name::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_generic_rtti_data_defn_start(RttiTypeId, RttiName, DeclSet0, DeclSet) -->
	io__write_string("\n"),
	output_rtti_addr_storage_type_name(RttiTypeId, RttiName, yes),
	{ DataAddr = rtti_addr(RttiTypeId, RttiName) },
	{ decl_set_insert(DeclSet0, data_addr(DataAddr), DeclSet) }.

output_rtti_addr_storage_type_name(RttiTypeId, RttiName, BeingDefined) -->
	output_rtti_name_storage_type_name(
		output_rtti_addr(RttiTypeId, RttiName),
		RttiName, BeingDefined).

:- pred output_rtti_name_storage_type_name(
	pred(io__state, io__state)::pred(di, uo) is det,
	rtti_name::in, bool::in, io__state::di, io__state::uo) is det.

output_rtti_name_storage_type_name(OutputName, RttiName, BeingDefined) -->
	output_rtti_type_decl(RttiName),
	{ rtti_name_linkage(RttiName, Linkage) },
	globals__io_get_globals(Globals),
	{ c_data_linkage_string(Globals, Linkage, BeingDefined, LinkageStr) },
	io__write_string(LinkageStr),

	{ rtti_name_would_include_code_addr(RttiName, InclCodeAddr) },
	{ c_data_const_string(Globals, InclCodeAddr, ConstStr) },
	io__write_string(ConstStr),

	{ rtti_name_c_type(RttiName, CType, Suffix) },
	c_util__output_quoted_string(CType),
	io__write_string(" "),
	OutputName,
	io__write_string(Suffix).

:- pred output_rtti_type_decl(rtti_name::in, io__state::di, io__state::uo)
	is det.
output_rtti_type_decl(RttiName) -->
	(
		%
		% Each pseudo-type-info may have a different type,
		% depending on what kind of pseudo-type-info it is,
		% and also on its arity.
		% We need to declare that type here.
		%
		{
		  RttiName = pseudo_type_info(type_info(_, ArgTypes)),
		  TypeNameBase = "MR_FO_PseudoTypeInfo_Struct",
		  DefineType = "MR_FIRST_ORDER_PSEUDOTYPEINFO_STRUCT"
		;
		  RttiName = pseudo_type_info(higher_order_type_info(_, _,
		  		ArgTypes)),
	 	  TypeNameBase = "MR_HO_PseudoTypeInfo_Struct",
		  DefineType = "MR_HIGHER_ORDER_PSEUDOTYPEINFO_STRUCT"
		}
	->
		{ NumArgTypes = list__length(ArgTypes) },
		{ Template = 
"#ifndef %s%d_GUARD
#define %s%d_GUARD
%s(%s%d, %d);
#endif
"		},
		io__format(Template, [
			s(TypeNameBase), i(NumArgTypes),
			s(TypeNameBase), i(NumArgTypes),
			s(DefineType), s(TypeNameBase),
			i(NumArgTypes), i(NumArgTypes)
		])
	;
		[]
	).

%-----------------------------------------------------------------------------%

rtti_out__init_rtti_data_if_nec(Data) -->
	(
		{ Data = type_ctor_info(RttiTypeId,
			_,_,_,_,_,_,_,_,_,_,_,_) }
	->
		io__write_string("\tMR_INIT_TYPE_CTOR_INFO(\n\t\t"),
		output_rtti_addr(RttiTypeId, type_ctor_info),
		io__write_string(",\n\t\t"),
		{ RttiTypeId = rtti_type_id(ModuleName, TypeName, Arity) },
		{ llds_out__sym_name_mangle(ModuleName, ModuleNameString) },
		{ string__append(ModuleNameString, "__", UnderscoresModule) },
		( 
			{ string__append(UnderscoresModule, _, TypeName) } 
		->
			[]
		;
			io__write_string(UnderscoresModule)
		),
		{ llds_out__name_mangle(TypeName, MangledTypeName) },
		io__write_string(MangledTypeName),
		io__write_string("_"),
		io__write_int(Arity),
		io__write_string("_0);\n")
	;
		{ Data = base_typeclass_info(_ModName, ClassName, ClassArity,
			base_typeclass_info(_N1, _N2, _N3, _N4, _N5,
				Methods)) }
	->
		io__write_string("#ifndef MR_STATIC_CODE_ADDRESSES\n"),
			% the field number for the first method is 5,
			% since the methods are stored after N1 .. N5,
			% and fields are numbered from 0.
		{ FirstFieldNum = 5 },
		{ CodeAddrs = list__map(make_code_addr, Methods) },
		output_init_method_pointers(FirstFieldNum, CodeAddrs,
			ClassName, ClassArity),
		io__write_string("#endif /* MR_STATIC_CODE_ADDRESSES */\n")
	;
		[]
	).

rtti_out__register_rtti_data_if_nec(Data, SplitFiles) -->
	(
		{ Data = type_ctor_info(RttiTypeId,
			_,_,_,_,_,_,_,_,_,_,_,_) }
	->
		(
			{ SplitFiles = yes },
			io__write_string("\t{\n\t"),
			output_rtti_addr_storage_type_name(RttiTypeId,
				type_ctor_info, no),
			io__write_string(
				";\n\tMR_register_type_ctor_info(\n\t\t&"),
			output_rtti_addr(RttiTypeId, type_ctor_info),
			io__write_string(");\n\t}\n")
		;
			{ SplitFiles = no },
			io__write_string(
				"\tMR_register_type_ctor_info(\n\t\t&"),
			output_rtti_addr(RttiTypeId, type_ctor_info),
			io__write_string(");\n")
		)
	;
		{ Data = base_typeclass_info(_InstanceModuleName, _ClassId,
			_InstanceString, _BaseTypeClassInfo) }
	->
		% XXX Registering base_typeclass_infos by themselves is not
		% enough. A base_typeclass_info doesn't say which types it
		% declares to be members of which typeclass, and for now
		% we don't even have any data structures in the runtime system
		% to describe such membership information.
		%
		% io__write_string("\tMR_register_base_typeclass_info(\n\t\t&"),
		% output_base_typeclass_info_storage_type_name(
		%	InstanceModuleName, ClassId, InstanceString, no),
		% io__write_string(");\n")
		[]
	;
		[]
	).

:- pred output_init_method_pointers(int, list(code_addr), class_id, string,
		io__state, io__state).
:- mode output_init_method_pointers(in, in, in, in, di, uo) is det.

output_init_method_pointers(_, [], _, _) --> [].
output_init_method_pointers(FieldNum, [Arg|Args], ClassId, InstanceStr) -->
	io__write_string("\t\t"),
	io__write_string("MR_field(MR_mktag(0), "),
	output_base_typeclass_info_name(ClassId, InstanceStr),
	io__format(", %d) =\n\t\t\t", [i(FieldNum)]),
	output_code_addr(Arg),
	io__write_string(";\n"),
	output_init_method_pointers(FieldNum + 1, Args, ClassId, InstanceStr).

%-----------------------------------------------------------------------------%

:- pred output_maybe_rtti_addrs_decls(rtti_type_id::in,
	list(maybe(rtti_name))::in, string::in, string::in, int::in, int::out,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_maybe_rtti_addrs_decls(_, [], _, _, N, N, DeclSet, DeclSet) --> [].
output_maybe_rtti_addrs_decls(RttiTypeId, [MaybeRttiName | RttiNames],
		FirstIndent, LaterIndent, N0, N, DeclSet0, DeclSet) -->
	(
		{ MaybeRttiName = yes(RttiName) },
		output_data_addr_decls(rtti_addr(RttiTypeId, RttiName),
			FirstIndent, LaterIndent, N0, N1, DeclSet0, DeclSet1)
	;
		{ MaybeRttiName = no },
		{ N1 = N0 },
		{ DeclSet1 = DeclSet0 }
	),
	output_maybe_rtti_addrs_decls(RttiTypeId, RttiNames,
		FirstIndent, LaterIndent, N1, N, DeclSet1, DeclSet).

:- pred output_rtti_datas_decls(list(rtti_data)::in,
	string::in, string::in, int::in, int::out, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_rtti_datas_decls([], _, _, N, N, DeclSet, DeclSet) --> [].
output_rtti_datas_decls([RttiData | RttiDatas],
		FirstIndent, LaterIndent, N0, N, DeclSet0, DeclSet) -->
	output_rtti_data_decls(RttiData,
		FirstIndent, LaterIndent, N0, N1, DeclSet0, DeclSet1),
	output_rtti_datas_decls(RttiDatas,
		FirstIndent, LaterIndent, N1, N, DeclSet1, DeclSet).

:- pred output_rtti_addrs_decls(rtti_type_id::in, list(rtti_name)::in,
	string::in, string::in, int::in, int::out, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_rtti_addrs_decls(_, [], _, _, N, N, DeclSet, DeclSet) --> [].
output_rtti_addrs_decls(RttiTypeId, [RttiName | RttiNames],
		FirstIndent, LaterIndent, N0, N, DeclSet0, DeclSet) -->
	output_data_addr_decls(rtti_addr(RttiTypeId, RttiName),
		FirstIndent, LaterIndent, N0, N1, DeclSet0, DeclSet1),
	output_rtti_addrs_decls(RttiTypeId, RttiNames,
		FirstIndent, LaterIndent, N1, N, DeclSet1, DeclSet).

:- pred output_rtti_data_decls(rtti_data::in,
	string::in, string::in, int::in, int::out, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_rtti_data_decls(RttiData, FirstIndent, LaterIndent,
		N0, N, DeclSet0, DeclSet) -->
	( { RttiData = pseudo_type_info(type_var(_)) } ->
		% These just get represented as integers,
		% so we don't need to declare them.
		% Also rtti_data_to_name/3 does not handle this case.
		{ DeclSet = DeclSet0 },
		{ N = N0 }
	;
		{ RttiData = base_typeclass_info(InstanceModuleName, ClassId,
			InstanceStr, _) }
	->
		% rtti_data_to_name/3 does not handle this case,
		% so we need to handle it here
		output_base_typeclass_info_decl(InstanceModuleName, ClassId,
			InstanceStr, no, DeclSet0, DeclSet),
		{ N = N0 }
	;
		{ rtti_data_to_name(RttiData, RttiTypeId, RttiName) },
		output_rtti_addr_decls(RttiTypeId, RttiName,
			FirstIndent, LaterIndent, N0, N, DeclSet0, DeclSet)
	).

:- pred output_rtti_addr_decls(rtti_type_id::in, rtti_name::in,
	string::in, string::in, int::in, int::out, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_rtti_addr_decls(RttiTypeId, RttiName, FirstIndent, LaterIndent,
		N0, N1, DeclSet0, DeclSet1) -->
	output_data_addr_decls(rtti_addr(RttiTypeId, RttiName),
		FirstIndent, LaterIndent, N0, N1, DeclSet0, DeclSet1).

:- pred output_addr_of_maybe_rtti_addr(rtti_type_id::in, maybe(rtti_name)::in,
	io__state::di, io__state::uo) is det.

output_addr_of_maybe_rtti_addr(RttiTypeId, MaybeRttiName) -->
	(
		{ MaybeRttiName = yes(RttiName) },
		output_addr_of_rtti_addr(RttiTypeId, RttiName)
	;
		{ MaybeRttiName = no },
		io__write_string("NULL")
	).

:- pred output_addr_of_maybe_rtti_addrs(rtti_type_id::in,
	list(maybe(rtti_name))::in, io__state::di, io__state::uo) is det.

output_addr_of_maybe_rtti_addrs(_, []) --> [].
output_addr_of_maybe_rtti_addrs(RttiTypeId,
		[MaybeRttiName | MaybeRttiNames]) -->
	io__write_string("\t"),
	io__write_list([MaybeRttiName | MaybeRttiNames], ",\n\t",
		output_addr_of_maybe_rtti_addr(RttiTypeId)),
	io__write_string("\n").

:- pred output_addr_of_rtti_addrs(rtti_type_id::in, list(rtti_name)::in,
	io__state::di, io__state::uo) is det.

output_addr_of_rtti_addrs(_, []) --> [].
output_addr_of_rtti_addrs(RttiTypeId, [RttiName | RttiNames]) -->
	io__write_string("\t"),
	io__write_list([RttiName | RttiNames], ",\n\t",
		output_addr_of_rtti_addr(RttiTypeId)),
	io__write_string("\n").

:- pred output_addr_of_rtti_datas(list(rtti_data)::in,
	io__state::di, io__state::uo) is det.

output_addr_of_rtti_datas([]) --> [].
output_addr_of_rtti_datas([RttiData | RttiDatas]) -->
	io__write_string("\t"),
	io__write_list([RttiData | RttiDatas], ",\n\t",
		output_addr_of_rtti_data),
	io__write_string("\n").

output_addr_of_rtti_data(RttiData) -->
	( { RttiData = pseudo_type_info(type_var(VarNum)) } ->
		% rtti_data_to_name/3 does not handle this case
		io__write_string("(MR_PseudoTypeInfo) "),
		io__write_int(VarNum)
	;
		{ RttiData = base_typeclass_info(_InstanceModuleName, ClassId,
			InstanceStr, _) }
	->
		% rtti_data_to_name/3 does not handle this case
		output_base_typeclass_info_name(ClassId,
			InstanceStr)
	;
		{ rtti_data_to_name(RttiData, RttiTypeId, RttiName) },
		output_addr_of_rtti_addr(RttiTypeId, RttiName)
	).

:- pred output_addr_of_rtti_addr(rtti_type_id::in, rtti_name::in,
	io__state::di, io__state::uo) is det.

output_addr_of_rtti_addr(RttiTypeId, RttiName) -->
	%
	% The various different kinds of pseudotypeinfos
	% each have different types, but really we treat
	% them like a union rather than as separate types,
	% so here we need to cast all such constants to
	% a single type MR_PseudoTypeInfo.
	%
	(
		{ RttiName = pseudo_type_info(_) }
	->
		io__write_string("(MR_PseudoTypeInfo) ")
	;
		[]
	),
	%
	% If the RttiName is not an array, then
	% we need to use `&' to take its address
	%
	(
		{ rtti_name_has_array_type(RttiName) = yes }
	->
		[]
	;
		io__write_string("&")
	),
	output_rtti_addr(RttiTypeId, RttiName).

output_rtti_addr(RttiTypeId, RttiName) -->
	io__write_string(mercury_data_prefix),
	{ rtti__addr_to_string(RttiTypeId, RttiName, Str) },
	io__write_string(Str).

%-----------------------------------------------------------------------------%

:- pred output_maybe_quoted_string(maybe(string)::in,
	io__state::di, io__state::uo) is det.

output_maybe_quoted_string(MaybeName) -->
	(
		{ MaybeName = yes(Name) },
		io__write_string(""""),
		c_util__output_quoted_string(Name),
		io__write_string("""")
	;
		{ MaybeName = no },
		io__write_string("NULL")
	).

:- pred output_maybe_quoted_strings(list(maybe(string))::in,
	io__state::di, io__state::uo) is det.

output_maybe_quoted_strings(MaybeNames) -->
	io__write_string("\t"),
	io__write_list(MaybeNames, ",\n\t", output_maybe_quoted_string),
	io__write_string("\n").

%-----------------------------------------------------------------------------%

:- pred output_exist_locn(exist_typeinfo_locn::in,
	io__state::di, io__state::uo) is det.

output_exist_locn(Locn) -->
	(
		{ Locn = plain_typeinfo(SlotInCell) },
		io__write_string("{ "),
		io__write_int(SlotInCell),
		io__write_string(", -1 }")
	;
		{ Locn = typeinfo_in_tci(SlotInCell, SlotInTci) },
		io__write_string("{ "),
		io__write_int(SlotInCell),
		io__write_string(", "),
		io__write_int(SlotInTci),
		io__write_string(" }")
	).

:- pred output_exist_locns(list(exist_typeinfo_locn)::in,
	io__state::di, io__state::uo) is det.

output_exist_locns(Locns) -->
	io__write_string("\t"),
	io__write_list(Locns, ",\n\t", output_exist_locn),
	io__write_string("\n").

:- pred output_maybe_static_code_addr(maybe(code_addr)::in,
	io__state::di, io__state::uo) is det.

output_maybe_static_code_addr(yes(CodeAddr)) -->
	output_static_code_addr(CodeAddr).
output_maybe_static_code_addr(no) -->
	io__write_string("NULL").

:- pred output_static_code_addr(code_addr::in, io__state::di, io__state::uo)
	is det.
output_static_code_addr(CodeAddr) -->
	io__write_string("MR_MAYBE_STATIC_CODE("),
	output_code_addr(CodeAddr),
	io__write_string(")").

%-----------------------------------------------------------------------------%

rtti_name_would_include_code_addr(exist_locns(_),            no).
rtti_name_would_include_code_addr(exist_info(_),             no).
rtti_name_would_include_code_addr(field_names(_),            no).
rtti_name_would_include_code_addr(field_types(_),            no).
rtti_name_would_include_code_addr(enum_functor_desc(_),      no).
rtti_name_would_include_code_addr(notag_functor_desc,        no).
rtti_name_would_include_code_addr(du_functor_desc(_),        no).
rtti_name_would_include_code_addr(enum_name_ordered_table,   no).
rtti_name_would_include_code_addr(enum_value_ordered_table,  no).
rtti_name_would_include_code_addr(du_name_ordered_table,     no).
rtti_name_would_include_code_addr(du_stag_ordered_table(_),  no).
rtti_name_would_include_code_addr(du_ptag_ordered_table,     no).
rtti_name_would_include_code_addr(type_ctor_info,            yes).
rtti_name_would_include_code_addr(base_typeclass_info(_, _, _), yes).
rtti_name_would_include_code_addr(pseudo_type_info(Pseudo),
		pseudo_type_info_would_incl_code_addr(Pseudo)).
rtti_name_would_include_code_addr(type_hashcons_pointer,     no).

:- func pseudo_type_info_would_incl_code_addr(pseudo_type_info) = bool.
pseudo_type_info_would_incl_code_addr(type_var(_))			= no.
pseudo_type_info_would_incl_code_addr(type_ctor_info(_))		= yes.
pseudo_type_info_would_incl_code_addr(type_info(_, _))			= no.
pseudo_type_info_would_incl_code_addr(higher_order_type_info(_, _, _))	= no.

rtti_name_linkage(RttiName, Linkage) :-
	(
			% ANSI/ISO C doesn't allow forward declarations
			% of static data with incomplete types (in this
			% case array types without an explicit array
			% size), so make the declarations extern.
		yes = rtti_name_has_array_type(RttiName)
	->
		Linkage = extern
	;
		Exported = rtti_name_is_exported(RttiName),
		( Exported = yes, Linkage = extern
		; Exported = no, Linkage = static
		)
        ).

rtti_name_c_type(exist_locns(_),           "MR_DuExistLocn", "[]").
rtti_name_c_type(exist_info(_),            "MR_DuExistInfo", "").
rtti_name_c_type(field_names(_),           "MR_ConstString", "[]").
rtti_name_c_type(field_types(_),           "MR_PseudoTypeInfo", "[]").
rtti_name_c_type(enum_functor_desc(_),     "MR_EnumFunctorDesc", "").
rtti_name_c_type(notag_functor_desc,       "MR_NotagFunctorDesc", "").
rtti_name_c_type(du_functor_desc(_),       "MR_DuFunctorDesc", "").
rtti_name_c_type(enum_name_ordered_table,  "MR_EnumFunctorDesc *", "[]").
rtti_name_c_type(enum_value_ordered_table, "MR_EnumFunctorDesc *", "[]").
rtti_name_c_type(du_name_ordered_table,    "MR_DuFunctorDesc *", "[]").
rtti_name_c_type(du_stag_ordered_table(_), "MR_DuFunctorDesc *", "[]").
rtti_name_c_type(du_ptag_ordered_table,    "MR_DuPtagLayout", "[]").
rtti_name_c_type(type_ctor_info,           "struct MR_TypeCtorInfo_Struct",
						"").
rtti_name_c_type(base_typeclass_info(_, _, _), "MR_Code *", "[]").
rtti_name_c_type(pseudo_type_info(Pseudo), TypePrefix, TypeSuffix) :-
	pseudo_type_info_name_c_type(Pseudo, TypePrefix, TypeSuffix).
rtti_name_c_type(type_hashcons_pointer,    "union MR_TableNode_Union **", "").

:- pred pseudo_type_info_name_c_type(pseudo_type_info, string, string).
:- mode pseudo_type_info_name_c_type(in, out, out) is det.

pseudo_type_info_name_c_type(type_var(_), _, _) :-
	% we use small integers to represent type_vars,
	% rather than pointers, so there is no pointed-to type
	error("rtti_name_c_type: type_var").
pseudo_type_info_name_c_type(type_ctor_info(_),
		"struct MR_TypeCtorInfo_Struct", "").
pseudo_type_info_name_c_type(type_info(_TypeId, ArgTypes),
		TypeInfoStruct, "") :-
	TypeInfoStruct = string__format("struct MR_FO_PseudoTypeInfo_Struct%d",
		[i(list__length(ArgTypes))]).
pseudo_type_info_name_c_type(higher_order_type_info(_TypeId, _Arity, ArgTypes),
		TypeInfoStruct, "") :-
	TypeInfoStruct = string__format("struct MR_HO_PseudoTypeInfo_Struct%d",
		[i(list__length(ArgTypes))]).

%-----------------------------------------------------------------------------%
