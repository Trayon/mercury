%-----------------------------------------------------------------------------%
% Copyright (C) 2000-2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% mlds_to_il - Convert MLDS to IL.
% Main author: trd.
%
% This module generates IL from MLDS.  Currently it's pretty tuned
% towards generating assembler -- to generate code using
% Reflection::Emit it is likely some changes will need to be made.
%
% Currently non-det environments are represented using a high-level data
% representation (classes with typed fields), while all other data structures 
% are represented using a low-level data representation (arrays of
% System.Object).  This is for historical reasons -- the MLDS high-level-data
% support wasn't available when it was needed.  Eventually we should
% move to a completely high-level data representation as the current
% representation is pretty inefficient.
%
% The IL backend TO-DO list:
%
% [ ] solutions
% [ ] floating point 
% [ ] Type classes
%	- You need to know what module the instance declaration is given in.
%	- This involves module qualifying instance declarations.
%	- This has semantic complications that we have to ignore for now
% [ ] RTTI (io__write -- about half the work required for this is done)
% [ ] High-level RTTI data
% [ ] Test unused mode (we seem to create a byref for it)
% [ ] Char (test unicode support)
% [ ] auto dependency generation for IL and assembler
% [ ] build environment improvements (support
% 	libraries/packages/namespaces better)
% [ ] verifiable code
% 	[ ] verifiable function pointers
% [ ] omit empty cctors
% [ ] Convert to "high-level data"
% [ ] Computed gotos need testing.
% [ ] :- extern doesn't work -- it needs to be treated like pragma c code.
% [ ] nested modules need testing
% [ ] We generate too many castclasses, it would be good to check if we
%     really to do it before generating it.  Same with isinst.
% [ ] Write line number information from contexts (in .il and .cpp files)
% [ ] Implement pragma export.
% [ ] Fix issues with abstract types so that we can implement C
%     pointers as MR_Box rather than MR_Word.
% [ ] When generating target_code, sometimes we output more calls than
%     we should (this can occur in nondet C code). 
% [ ] ml_gen_call_current_success_cont_indirectly should be merged with
% 	similar code for doing copy-in/copy-out.
% [ ] figure out whether we need maxstack and fix it
% [ ] Try to use the IL bool type for the true/false rvals.
% [ ] Add an option to do overflow checking.
% [ ] Should replace hard-coded of int32 with a more abstract name such
%     as `mercury_int_il_type'.
%
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module mlds_to_il.
:- interface.

:- import_module mlds, ilasm, ilds.
:- import_module io, list, bool, std_util.
:- import_module hlds_pred. % for `pred_proc_id'.

%-----------------------------------------------------------------------------%

	%
	% Generate IL assembly from MLDS.
	%
	% This is where all the action is for the IL backend.
	%
:- pred generate_il(mlds, list(ilasm:decl), bool, io__state, io__state).
:- mode generate_il(in, out, out, di, uo) is det.


%-----------------------------------------------------------------------------%

	%
	% The following predicates are exported so that we can get type
	% conversions and name mangling consistent between the managed
	% C++ output (currently in mlds_to_ilasm.m) and IL output (in
	% this file).
	%
	% XXX we should reduce the dependencies here to a bare minimum.
	%
:- pred params_to_il_signature(mlds_module_name, mlds__func_params,
		signature).
:- mode params_to_il_signature(in, in, out) is det.

	% Generate an IL identifier for a pred label.
:- pred predlabel_to_id(mlds__pred_label, proc_id,
	maybe(mlds__func_sequence_num), ilds__id).
:- mode predlabel_to_id(in, in, in, out) is det.

	% Generate an IL identifier for a MLDS var.
:- pred mangle_mlds_var(mlds__var, ilds__id).
:- mode mangle_mlds_var(in, out) is det.

	% Get the corresponding ILDS type for a MLDS 
:- func mlds_type_to_ilds_type(mlds__type) = ilds__type.

	% Turn a proc name into an IL class_name and a method name.
:- pred mangle_mlds_proc_label(mlds__qualified_proc_label, 
	maybe(mlds__func_sequence_num), ilds__class_name, ilds__id).
:- mode mangle_mlds_proc_label(in, in, out, out) is det.

	% Turn an MLDS module name into a class_name name.	
:- func mlds_module_name_to_class_name(mlds_module_name) =
		ilds__class_name.

	% Return the class_name for the generic class.
:- func il_generic_class_name = ilds__class_name.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module globals, options, passes_aux.
:- import_module builtin_ops, c_util, modules, tree.
:- import_module prog_data, prog_out, llds_out.
:- import_module rtti, type_util.

:- import_module ilasm, il_peephole.
:- import_module ml_util, ml_code_util, error_util.
:- import_module mlds_to_c. /* to output C code for .cpp files */
:- use_module llds. /* for user_c_code */

:- import_module bool, int, map, string, list, assoc_list, term.
:- import_module library, require, counter.

	% We build up lists of instructions using a tree to make
	% insertion easy.
:- type instr_tree == tree(list(instr)).

	% The state of the il code generator.
:- type il_info ---> il_info(
		% file-wide attributes (all static)
	module_name 	:: mlds_module_name,	% the module name
	imports 	:: mlds__imports,	% the imports
	file_c_code	:: bool,		% file contains c_code
		% class-wide attributes (all accumulate)
	alloc_instrs	:: instr_tree,		% .cctor allocation instructions
	init_instrs	:: instr_tree,		% .cctor init instructions
	classdecls	:: list(classdecl),	% class methods and fields 
	has_main	:: bool,		% class contains main
	class_c_code	:: bool,		% class contains c_code
		% method-wide attributes (accumulating)
	locals 		:: locals_map,		% The current locals
	instr_tree 	:: instr_tree,		% The instruction tree (unused)
	label_counter 	:: counter,		% the label counter
	block_counter 	:: counter,		% the block counter
	method_c_code	:: bool,		% method contains c_code
		% method-wide attributes (static)
	arguments 	:: arguments_map, 	% The arguments 
	method_name	:: member_name,		% current method name
	signature	:: signature		% current return type 
	).

:- type locals_map == map(ilds__id, mlds__type).
:- type arguments_map == assoc_list(ilds__id, mlds__type). 
:- type mlds_vartypes == map(ilds__id, mlds__type).

%-----------------------------------------------------------------------------%

generate_il(MLDS, ILAsm, ContainsCCode, IO, IO) :-
	MLDS = mlds(MercuryModuleName, _ForeignCode, Imports, Defns),
	ModuleName = mercury_module_name_to_mlds(MercuryModuleName),
	il_info_init(ModuleName, Imports, Info0),

		% Generate code for all the methods in this module.
	list__foldl(generate_method_defn, Defns, Info0, Info1),
	bool__or(Info1 ^ file_c_code, Info1 ^ method_c_code, ContainsCCode),
	Info = Info1 ^ file_c_code := ContainsCCode,
	ClassDecls = Info ^ classdecls,
	InitInstrs = list__condense(tree__flatten(Info ^ init_instrs)),
	AllocInstrs = list__condense(tree__flatten(Info ^ alloc_instrs)),

		% Generate definitions for all the other things
		% declared within this module.
		% XXX we should do them at the same time as the methods
	list__map(generate_other_decls(ModuleName), Defns, OtherDeclsList),
	list__condense(OtherDeclsList, OtherDecls),

	SymName = mlds_module_name_to_sym_name(ModuleName),
	ClassName = mlds_module_name_to_class_name(ModuleName),
	mlds_to_il__sym_name_to_string(SymName, MStr),

		% Make this module an assembly unless it is in the standard
		% library.  Standard library modules all go in the one
		% assembly in a separate step during the build (using
		% AL.EXE).  
	( 
		SymName = qualified(unqualified("mercury"), _)
	->
		ThisAssembly = [],
		AssemblerRefs = Imports
	;
		ThisAssembly = [assembly(MStr)],
			% If not in the library, but we have C code,
			% declare the __c_code module as an assembly we
			% reference
		( 
			Info1 ^ file_c_code = yes,
			mangle_dataname_module(no, ModuleName, CCodeModuleName),
			AssemblerRefs = [CCodeModuleName | Imports]
		;
			Info1 ^ file_c_code = no,
			AssemblerRefs = Imports
		)
	),

		% Turn the MLDS module names we import into a list of
		% assembly declarations.
	mlds_to_il__generate_extern_assembly(AssemblerRefs,
		ExternAssemblies),

		% Generate a field that records whether we have finished
		% RTTI initialization.
	generate_rtti_initialization_field(ClassName, 
		AllocDoneFieldRef, AllocDoneField),

		% Generate a class constructor.
	make_class_constructor_classdecl(AllocDoneFieldRef,
		Imports, AllocInstrs, InitInstrs, CCtor, Info1, _Info),

		% The declarations in this class.
	MethodDecls = [AllocDoneField, CCtor | ClassDecls],

		% The class that corresponds to this MLDS module.
	MainClass = [class([public], MStr, extends_nothing, implements([]),
		MethodDecls)],

		% A namespace to contain all the other declarations that
		% are created as a result of this MLDS code.
	MainNamespace = [namespace([MStr], OtherDecls)],
	ILAsm = list__condense(
		[ExternAssemblies, ThisAssembly, MainClass, MainNamespace]).

%-----------------------------------------------------------------------------

	% 
	% Code for generating method definitions.
	%

:- pred generate_method_defn(mlds__defn, il_info, il_info).
:- mode generate_method_defn(in, in, out) is det.

generate_method_defn(defn(type(_, _), _, _, _)) --> [].
	% XXX we don't handle export
generate_method_defn(defn(export(_), _, _, _)) --> [].
generate_method_defn(FunctionDefn) -->
	{ FunctionDefn = defn(function(PredLabel, ProcId, MaybeSeqNum, PredId), 
		Context, DeclsFlags, Entity) },
	( { Entity = mlds__function(_PredProcId, Params, MaybeStatement) } ->

		il_info_get_module_name(ModuleName),
			% Generate a term (we use it to emit the complete
			% method definition as a comment, which is nice
			% for debugging).
		{ term__type_to_term(defn(function(PredLabel, ProcId, 
			MaybeSeqNum, PredId), Context, DeclsFlags, Entity),
			MLDSDefnTerm) },

			% Generate the signature
		{ Params = mlds__func_params(Args, Returns) },
		{ list__map(mlds_arg_to_il_arg, Args, ILArgs) },
		{ params_to_il_signature(ModuleName, Params,
			ILSignature) },
			
			% Generate the name of the method.
		{ predlabel_to_id(PredLabel, ProcId, MaybeSeqNum,
			Id) },

			% Initialize the IL info with this method info.
		il_info_new_method(ILArgs, ILSignature, id(Id)),

			% Start a new block, which we will use to wrap
			% up the entire method.
		il_info_get_next_block_id(BlockId),

			% Generate the code of the statement.
		( { MaybeStatement = yes(Statement) } -> 
			statement_to_il(Statement, InstrsTree0)
		;
				% If there is no function body,
				% generate forwarding code instead.
				% This can happen with :- external
			atomic_statement_to_il(target_code(lang_C, []),
				InstrsTree0),
				% The code might reference locals...
			il_info_add_locals(["succeeded" - 
				mlds__native_bool_type])
		),

			% If this is main, add the entrypoint, set a
			% flag, and call the initialization instructions
			% in the cctor of this module.
		( { PredLabel = pred(predicate, no, "main", 2) },
		  { MaybeSeqNum = no }
		->
			{ EntryPoint = [entrypoint] },
			il_info_add_init_instructions(
				runtime_initialization_instrs),
			^ has_main := yes
		;
			{ EntryPoint = [] }
		),

			% Need to insert a ret for functions returning
			% void (MLDS doesn't).
		{ Returns = [] ->
			MaybeRet = instr_node(ret)
		;
			MaybeRet = empty
		},

			% Retrieve the locals, put them in the enclosing
			% scope.
		il_info_get_locals_list(Locals),
		{ InstrsTree = tree__list([
			instr_node(start_block(scope(Locals), BlockId)),
			InstrsTree0, 
			MaybeRet,
			instr_node(end_block(scope(Locals), BlockId))
			])
		},

			% Generate the entire method contents.
		{ MethodBody = make_method_defn(InstrsTree) },
		{ list__append(EntryPoint, MethodBody, MethodContents) },

			% Add this method and a comment to the class
			% declarations.
		{ ClassDecls = [
			comment_term(MLDSDefnTerm),
			ilasm__method(methodhead([static], id(Id), 
				ILSignature, []), MethodContents)
		] },
		il_info_add_classdecls(ClassDecls)
	;
		{ error("entity not a function") }
	).


generate_method_defn(DataDefn) --> 
	{ DataDefn = defn(data(DataName), _Context, _DeclsFlags, Entity) },
	il_info_get_module_name(ModuleName),
	{ ClassName = mlds_module_name_to_class_name(ModuleName) },

		% Generate a term (we use it to emit the complete
		% method definition as a comment, which is nice
		% for debugging).
	{ term__type_to_term(DataDefn, MLDSDefnTerm) },

		% Generate the field name for this data.
	{ mangle_dataname(DataName, FieldName) },
		
	( 
		{ Entity = mlds__data(_DataType, DataInitializer) }
	->
			% Generate instructions to initialize this data.
			% There are two sorts of instructions,
			% instructions to allocate the data structure,
			% and instructions to initialize it.
			% See the comments about class constructors to
			% find out why we do this.
		data_initializer_to_instrs(DataInitializer, AllocInstrsTree,
			InitInstrTree),

			% Make a field reference for the field
		{ FieldRef = make_fieldref(il_array_type,
			ClassName, FieldName) },

		{ AllocComment = comment_node(
			string__append("allocation for ", FieldName)) },
		{ InitComment = comment_node(
			string__append("initializer for ", FieldName)) },

			% If we had to allocate memory, the code
			% we generate looks like this:
			%
			%	// allocation for foo
			%	... allocation instructions ...
			%	stsfld thisclass::foo
			%
			%
			%	// initializer for foo
			%	ldsfld thisclass::foo
			%	... initialization code ...
			%	pop
			%
			% The final pop is necessary because the init
			% code will leave the field on the stack, but we
			% don't need it anymore (and we already set the
			% field when we allocated it).
			%
			% If no memory had to be allocated, the code is
			% a bit simpler.
			%
			%	// allocation for foo
			%	nothing here! 
			%	
			%	// initializer for foo
			%	... initialization code ...
			%	stsfld thisclass::foo
			%
			% Note that here we have to set the field.

		{ AllocInstrsTree = node([]) ->
			StoreAllocTree = node([]),
			StoreInitTree = node([stsfld(FieldRef)]),
			LoadTree = node([])
		;
			StoreAllocTree = node([stsfld(FieldRef)]),
			StoreInitTree = node([pop]),
			LoadTree = node([ldsfld(FieldRef)])
		},

			% Add a store after the alloc instrs (if necessary)
		{ AllocInstrs = list__condense(tree__flatten(
			tree(AllocComment,
			tree(AllocInstrsTree, StoreAllocTree)))) },
			% Add a load before the init instrs (if necessary)
		{ InitInstrs = list__condense(tree__flatten(
			tree(InitComment,
			tree(LoadTree, tree(InitInstrTree, StoreInitTree))))) },
		
			% Add these instructions to the lists of
			% allocation/initialization instructions.
			% They will be put into the class constructor
			% later.
		il_info_add_alloc_instructions(AllocInstrs),
		il_info_add_init_instructions(InitInstrs),

			% Make a public static field and add the field
			% and a comment term to the class decls.
		{ Field = field([public, static], il_array_type,
			FieldName, no, none) },
		{ ClassDecls = [comment_term(MLDSDefnTerm), Field] }
	;
		{ error("entity not data") }
	),
	il_info_add_classdecls(ClassDecls).
	
	% Generate top level declarations for "other" things (e.g.
	% anything that is not a method in the main class).
	% XXX Really, this should be integrated with the other pass
	% (generate_method_defn), and we can generate them all at once.
	% This would involve adding the top-level decls list to il_info too.
:- pred generate_other_decls(mlds_module_name, mlds__defn, list(ilasm__decl)).
:- mode generate_other_decls(in, in, out) is det.
generate_other_decls(ModuleName, MLDSDefn, Decls) :-
	ClassName = mlds_module_name_to_class_name(ModuleName),
	MLDSDefn = mlds__defn(EntityName, _Context, _DeclFlags, Entity), 
	term__type_to_term(MLDSDefn, MLDSDefnTerm),
	( EntityName = type(TypeName, _Arity),
		list__append(ClassName, [TypeName],
			FullClassName),
		( 
			Entity = mlds__class(ClassDefn) 
		->
			ClassDefn = mlds__class_defn(ClassType, _Imports, 
				_Inherits, _Implements, Defns),
			( 
				ClassType = mlds__class
			->
				list__map(defn_to_class_decl, Defns, ILDefns),
				make_constructor(FullClassName, ClassDefn, 
					ConstructorILDefn),
				Decls = [comment_term(MLDSDefnTerm),
					class([public], TypeName,
					extends_nothing, implements([]),
					[ConstructorILDefn | ILDefns])]
			; 
				ClassType = mlds__struct
			->
				list__map(defn_to_class_decl, Defns, ILDefns),
				make_constructor(FullClassName, ClassDefn, 
					ConstructorILDefn),
				Decls = [comment_term(MLDSDefnTerm),
					class([public], TypeName, 
					extends(il_envptr_class_name), 
					implements([]), 
					[ConstructorILDefn | ILDefns])]
			;
				Decls = [comment_term(MLDSDefnTerm),
					comment("This type unimplemented.")]
			)
		;
			Decls = [comment_term(MLDSDefnTerm),
				comment("This type unimplemented.")]
		)
	; EntityName = function(_PredLabel, _ProcId, _MaybeFn, _PredId),
		Decls = []
	; EntityName = export(_),
			% XXX we don't handle export
		Decls = []
	; EntityName = data(_),
		Decls = []
	).

%-----------------------------------------------------------------------------

	%
	% Code for generating initializers.
	%

	% Generate initializer code from an MLDS defn.  We are only expecting
	% data defns at this point (local vars), not functions or classes.
:- pred generate_defn_initializer(mlds__defn, instr_tree, instr_tree, 
	il_info, il_info).
:- mode generate_defn_initializer(in, in, out, in, out) is det.
generate_defn_initializer(defn(Name, _Context, _DeclFlags, Entity),
		Tree0, Tree) --> 
	( 
		{ Name = data(DataName) },
		{ Entity = mlds__data(_MldsType, Initializer) }
	->
		( { Initializer = no_initializer } ->
			{ Tree = Tree0 }
		;
			( { DataName = var(VarName) } ->
				il_info_get_module_name(ModuleName),
				get_load_store_lval_instrs(
					var(qual(ModuleName, VarName)), 
					LoadMemRefInstrs, StoreLvalInstrs),
				{ NameString = VarName }
			;
				{ LoadMemRefInstrs = throw_unimplemented(
					"initializer_for_non_var_data_name") },
				{ StoreLvalInstrs = node([]) },
				{ NameString = "unknown" }
			),
			data_initializer_to_instrs(Initializer, AllocInstrs,
				InitInstrs),
			{ string__append("initializer for ", NameString, 
				Comment) },
			{ Tree = tree__list([
				Tree0,
				comment_node(Comment),
				LoadMemRefInstrs,
				AllocInstrs,
				InitInstrs,
				StoreLvalInstrs
				]) }
		)
	;
		{ unexpected(this_file, "defn not data(...) in block") }
	).

	% initialize this value, leave it on the stack.
	% XXX the code generator doesn't box these values
	% we need to look ahead at them and box them appropriately.
:- pred data_initializer_to_instrs(mlds__initializer::in,
	instr_tree::out, instr_tree::out, il_info::in, il_info::out) is det.
data_initializer_to_instrs(init_obj(Rval), node([]), InitInstrs) --> 
	load(Rval, InitInstrs).

	% Currently, structs are the same as arrays.
data_initializer_to_instrs(init_struct(InitList), AllocInstrs, InitInstrs) --> 
	data_initializer_to_instrs(init_array(InitList), AllocInstrs, 
		InitInstrs).

	% Put the array allocation in AllocInstrs.
	% For sub-initializations, we don't worry about keeping AllocInstrs
	% and InitInstrs apart, since we are only interested in top level
	% allocations.
data_initializer_to_instrs(init_array(InitList), AllocInstrs, InitInstrs) -->

		% To initialize an array, we generate the following
		% code:
		% 	ldc <length of array>
		% 	newarr System::Object
		%	
		% Then, for each element in the array:
		%	dup
		%	ldc <index of this element in the array>
		%	... allocation instructions ...
		%	... initialization instructions ...
		%	box the value (if necessary)
		%	stelem System::Object
		%
		% The initialization will leave the array on the stack.
		%	
	{ AllocInstrs = node([ldc(int32, i(list__length(InitList))), 
		newarr(il_generic_type)]) },
	{ AddInitializer = 
		(pred(Init0::in, X0 - Tree0::in, (X0 + 1) - Tree::out,
				in, out) is det -->
			maybe_box_initializer(Init0, Init),
			data_initializer_to_instrs(Init, ATree1, ITree1),
			{ Tree = tree(tree(Tree0, node(
					[dup, ldc(int32, i(X0))])), 
				tree(tree(ATree1, ITree1), 
					node([stelem(il_generic_simple_type)]
				))) }
		) },
	list__foldl2(AddInitializer, InitList, 0 - empty, _ - InitInstrs).
data_initializer_to_instrs(no_initializer, node([]), node([])) --> [].

	% If we are initializing an array or struct, we need to box
	% all the things inside it.
:- pred maybe_box_initializer(mlds__initializer, mlds__initializer, 
	il_info, il_info).
:- mode maybe_box_initializer(in, out, in, out) is det.

	% nothing to do
maybe_box_initializer(no_initializer, no_initializer) --> [].
	% array already boxed
maybe_box_initializer(init_array(X), init_array(X)) --> [].
	% struct already boxed
maybe_box_initializer(init_struct(X), init_struct(X)) --> [].
	% single items need to be boxed
maybe_box_initializer(init_obj(Rval), init_obj(NewRval)) -->
	rval_to_type(Rval, BoxType),
	{ NewRval = unop(box(BoxType), Rval) }.


%-----------------------------------------------------------------------------%
%
% Code to turn MLDS definitions into IL class declarations.
%

:- pred defn_to_class_decl(mlds__defn, ilasm__classdecl).
:- mode defn_to_class_decl(in, out) is det.

	% XXX shouldn't we re-use the code for creating fieldrefs here?
defn_to_class_decl(mlds__defn(Name, _Context, _DeclFlags, 
		mlds__data(Type, _Initializer)), ILClassDecl) :-
	ILType0 = mlds_type_to_ilds_type(Type),
		% IL doesn't allow byrefs in classes, so we don't use
		% them.
		% XXX really this should be a transformation done in
		% advance
	( ILType0 = ilds__type(_, '&'(ILType1)) ->
		ILType = ILType1
	;
		ILType = ILType0
	),
	( Name = data(DataName) ->
		mangle_dataname(DataName, MangledName),
		ILClassDecl = field([], ILType, MangledName, no, none) 
	;
		error("definintion name was not data/1")
	).

	% XXX this needs to be implemented
defn_to_class_decl(mlds__defn(_Name, _Context, _DeclFlags,
	mlds__function(_PredProcId, _Params, _MaybeStatements)), ILClassDecl) :-
		ILClassDecl = comment("unimplemented: functions in classes").

	% XXX this might not need to be implemented (nested classes)
	% since it will probably be flattened earlier.
defn_to_class_decl(mlds__defn(_Name, _Context, _DeclFlags,
		mlds__class(_)), _ILClassDecl) :-
	error("nested data definition not expected here").


%-----------------------------------------------------------------------------%
%
% Convert basic MLDS statements into IL.
%

:- pred statements_to_il(list(mlds__statement), instr_tree, il_info, il_info).
:- mode statements_to_il(in, out, in, out) is det.
statements_to_il([], empty) --> [].
statements_to_il([ S | Statements], tree(Instrs0, Instrs1)) -->
	statement_to_il(S, Instrs0),
	statements_to_il(Statements, Instrs1).


:- pred statement_to_il(mlds__statement, instr_tree, il_info, il_info).
:- mode statement_to_il(in, out, in, out) is det.

statement_to_il(statement(block(Defns, Statements), _Context), Instrs) -->
	il_info_get_module_name(ModuleName),
	il_info_get_next_block_id(BlockId),
	{ list__map(defn_to_local(ModuleName), Defns, Locals) },
	il_info_add_locals(Locals),
	list__foldl2(generate_defn_initializer, Defns, empty,
		InitInstrsTree),
	statements_to_il(Statements, BlockInstrs),
	{ list__map((pred((K - V)::in, (K - W)::out) is det :- 
		W = mlds_type_to_ilds_type(V)), Locals, ILLocals) },
	{ Instrs = tree__list([
			node([start_block(scope(ILLocals), BlockId)]),
			InitInstrsTree,
			comment_node("block body"),
			BlockInstrs,
			node([end_block(scope(ILLocals), BlockId)])
			]) },
	il_info_remove_locals(Locals).

statement_to_il(statement(atomic(Atomic), _Context), Instrs) -->
	atomic_statement_to_il(Atomic, Instrs).

statement_to_il(statement(call(Sig, Function, _This, Args, Returns, IsTail), 
		_Context), Instrs) -->
	( { IsTail = tail_call } ->
		% For tail calls, to make the code verifiable, 
		% we need a `ret' instruction immediately after
		% the call.
		{ TailCallInstrs = [tailcall] },
		{ RetInstrs = [ret] },
		{ ReturnsStoredInstrs = empty },
		{ LoadMemRefInstrs = empty }
	;
		% For non-tail calls, we might have to load a memory
		% reference before the call so we can store the result
		% into the memory reference after the call.
		{ TailCallInstrs = [] },
		{ RetInstrs = [] },
		get_all_load_store_lval_instrs(Returns,
			LoadMemRefInstrs, ReturnsStoredInstrs)
	),
	list__map_foldl(load, Args, ArgsLoadInstrsTrees),
	{ ArgsLoadInstrs = tree__list(ArgsLoadInstrsTrees) },
	{ mlds_signature_to_ilds_type_params(Sig, TypeParams) },
	{ mlds_signature_to_il_return_param(Sig, ReturnParam) },
	( { Function = const(_) } ->
		{ FunctionLoadInstrs = empty },
		{ rval_to_function(Function, MemberName) },
		{ Instrs0 = [call(methoddef(call_conv(no, default),
			ReturnParam, MemberName, TypeParams))] }
	;
		load(Function, FunctionLoadInstrs),
		{ list__length(TypeParams, Length) },
		{ list__duplicate(Length, no, NoList) },
		{ assoc_list__from_corresponding_lists(
			TypeParams, NoList, ParamsList) },
		{ Instrs0 = [calli(signature(call_conv(no, default),
			ReturnParam, ParamsList))] }
	),		
	{ Instrs = tree__list([
			comment_node("call"), 
			LoadMemRefInstrs,
			ArgsLoadInstrs,
			FunctionLoadInstrs,
			node(TailCallInstrs),
			node(Instrs0), 
			node(RetInstrs),
			ReturnsStoredInstrs
			]) }.

statement_to_il(statement(if_then_else(Condition, ThenCase, ElseCase), 
		_Context), Instrs) -->
	generate_condition(Condition, ConditionInstrs, ElseLabel),
	il_info_make_next_label(DoneLabel),
	statement_to_il(ThenCase, ThenInstrs),
	maybe_map_fold(statement_to_il, ElseCase, empty, ElseInstrs),
	{ Instrs = tree__list([
		comment_node("if then else"),
		ConditionInstrs,
		comment_node("then case"),
		ThenInstrs,
		instr_node(br(label_target(DoneLabel))),
		instr_node(label(ElseLabel)),
		comment_node("else case"),
		ElseInstrs,
		comment_node("end if then else"),
		instr_node(label(DoneLabel))
		]) }.

statement_to_il(statement(switch(_Type, _Val, _Range, _Cases, _Default),
		_Context), _Instrs) -->
	% The IL back-end only supports computed_gotos and if-then-else chains;
	% the MLDS code generator should either avoid generating MLDS switches,
	% or should transform them into computed_gotos or if-then-else chains.
	{ error("mlds_to_il.m: `switch' not supported") }.

statement_to_il(statement(while(Condition, Body, AtLeastOnce), 
		_Context), Instrs) -->
	generate_condition(Condition, ConditionInstrs, EndLabel),
	il_info_make_next_label(StartLabel),
	statement_to_il(Body, BodyInstrs),
	{ AtLeastOnce = no,
		Instrs = tree__list([
			comment_node("while"),
			instr_node(label(StartLabel)),
			ConditionInstrs,
			BodyInstrs,
			instr_node(br(label_target(StartLabel))),
			instr_node(label(EndLabel))
		])
	; AtLeastOnce = yes, 
			% XXX this generates a branch over branch which
			% is suboptimal.
		Instrs = tree__list([
			comment_node("while (actually do ... while)"),
			instr_node(label(StartLabel)),
			BodyInstrs,
			ConditionInstrs,
			instr_node(br(label_target(StartLabel))),
			instr_node(label(EndLabel))
		])

	}.


statement_to_il(statement(return(Rvals), _Context), Instrs) -->
	( { Rvals = [Rval] } ->
		load(Rval, LoadInstrs),
		{ Instrs = tree__list([
			LoadInstrs,
			instr_node(ret)]) }
	;
		% MS IL doesn't support multiple return values
		{ sorry(this_file, "multiple return values") }
	).

statement_to_il(statement(label(Label), _Context), Instrs) -->
	{ string__format("label %s", [s(Label)], Comment) },
	{ Instrs = node([comment(Comment), label(Label)]) }.

statement_to_il(statement(goto(Label), _Context), Instrs) -->
	{ string__format("goto %s", [s(Label)], Comment) },
	{ Instrs = node([comment(Comment), br(label_target(Label))]) }.

statement_to_il(statement(do_commit(Ref), _Context), Instrs) -->

	% For commits, we use exception handling.
	%
	% We generate code of the following form:
	% 
	% 	<load exception rval -- should be of a special commit type>
	% 	throw
	%
	% 

	load(Ref, RefLoadInstrs),
	{ Instrs = tree__list([
		comment_node("do_commit/1"),
		RefLoadInstrs,
		instr_node(throw)
		]) }.

statement_to_il(statement(try_commit(Ref, GoalToTry, CommitHandlerGoal), 
		_Context), Instrs) -->

	% For commits, we use exception handling.
	%
	% We generate code of the following form:
	%
	% 	.try {	
	%		GoalToTry
	%		leave label1
	% 	} catch commit_type {
	%		pop	// discard the exception object
	% 		CommitHandlerGoal
	%		leave label1
	% 	}
	% 	label1:
	% 

	il_info_get_next_block_id(TryBlockId),
	statement_to_il(GoalToTry, GoalInstrsTree),
	il_info_get_next_block_id(CatchBlockId),
	statement_to_il(CommitHandlerGoal, HandlerInstrsTree),
	il_info_make_next_label(DoneLabel),

	rval_to_type(lval(Ref), MLDSRefType),
	{ RefType = mlds_type_to_ilds_type(MLDSRefType) },
	{ RefType = ilds__type(_, class(ClassName0)) ->
			ClassName = ClassName0
		;
			unexpected(this_file, "non-class for commit ref")
	},	
	{ Instrs = tree__list([
		comment_node("try_commit/3"),

		instr_node(start_block(try, TryBlockId)),
		GoalInstrsTree,
		instr_node(leave(label_target(DoneLabel))),
		instr_node(end_block(try, TryBlockId)),

		instr_node(start_block(catch(ClassName), CatchBlockId)),
		comment_node("discard the exception object"),
		instr_node(pop),
		HandlerInstrsTree,
		instr_node(leave(label_target(DoneLabel))),
		instr_node(end_block(catch(ClassName), CatchBlockId)),
		instr_node(label(DoneLabel))

		]) }.

statement_to_il(statement(computed_goto(Rval, MLDSLabels), _Context), 
		Instrs) -->
	load(Rval, RvalLoadInstrs),
	{ Targets = list__map(func(L) = label_target(L), MLDSLabels) },
	{ Instrs = tree__list([
		comment_node("computed goto"),
		RvalLoadInstrs,
		instr_node(switch(Targets))
		]) }.


	
:- pred atomic_statement_to_il(mlds__atomic_statement, instr_tree, 
	il_info, il_info).
:- mode atomic_statement_to_il(in, out, in, out) is det.

atomic_statement_to_il(mark_hp(_), node(Instrs)) --> 
	{ Instrs = [comment(
		"mark hp -- not relevant for this backend")] }.
atomic_statement_to_il(restore_hp(_), node(Instrs)) --> 
	{ Instrs = [comment(
		"restore hp -- not relevant for this backend")] }.

atomic_statement_to_il(target_code(_Lang, _Code), node(Instrs)) --> 
	il_info_get_module_name(ModuleName),
	( no =^ method_c_code  ->
		^ method_c_code := yes,
		{ mangle_dataname_module(no, ModuleName, NewModuleName) },
		{ ClassName = mlds_module_name_to_class_name(NewModuleName) },
		signature(_, RetType, Params) =^ signature, 
			% If there is a return value, put it in succeeded.
		{ RetType = void ->
			StoreReturnInstr = []
		;
			StoreReturnInstr = [stloc(name("succeeded"))]
		},
		MethodName =^ method_name,
		{ assoc_list__keys(Params, TypeParams) },
		{ list__map_foldl((pred(_::in, Instr::out,
			Num::in, Num + 1::out) is det :-
				Instr = ldarg(index(Num))),
			TypeParams, LoadInstrs, 0, _) },
		{ list__condense(
			[[comment("target code -- call handwritten version")],
			LoadInstrs,
			[call(get_static_methodref(ClassName, MethodName, 
				RetType, TypeParams))],
			StoreReturnInstr	
			], Instrs) }
	;
		{ Instrs = [comment("target code -- already called")] }
	).


atomic_statement_to_il(trail_op(_), node(Instrs)) --> 
	{ Instrs = [comment(
		"... some trail operation ... (unimplemented)")] }.

atomic_statement_to_il(assign(Lval, Rval), Instrs) -->
	% do assignments by loading the rval and storing
	% to the lval
	load(Rval, LoadRvalInstrs),
	get_load_store_lval_instrs(Lval, LoadMemRefInstrs, StoreLvalInstrs),
	{ Instrs = tree__list([
		comment_node("assign"),
		LoadMemRefInstrs,
		LoadRvalInstrs,
		StoreLvalInstrs
		]) }.
atomic_statement_to_il(comment(Comment), Instrs) -->
	{ Instrs = node([comment(Comment)]) }.

atomic_statement_to_il(delete_object(Target), Instrs) -->
		% XXX we assume the code generator knows what it is
		% doing and is only going to delete real objects (e.g.
		% reference types).  It would perhaps be prudent to
		% check the type of delete_object (if it had one) to
		% make sure.
	
		% We implement delete_object by storing null in the
		% lval, which hopefully gives the garbage collector a good
		% solid hint that this storage is no longer required.
	get_load_store_lval_instrs(Target, LoadInstrs, StoreInstrs),
	{ Instrs = tree__list([LoadInstrs, instr_node(ldnull), StoreInstrs]) }.

atomic_statement_to_il(new_object(Target, _MaybeTag, Type, Size, _CtorName,
		Args, ArgTypes), Instrs) -->
	( 
		{ Type = mlds__generic_env_ptr_type 
		; Type = mlds__class_type(_, _, _) }
	->
			% If this is an env_ptr we should call the
			% constructor.  
			% (This is also how we will handle high-level data).
			% We generate code of the form:
			%
			% 	... load memory reference ...
			%	// new object (call constructor)
			%	... load each argument ...
			%	call ClassName::.ctor
			%	... store to memory reference ...
			%
		{ ILType = mlds_type_to_ilds_type(Type) },
		{ 
			ILType = ilds__type(_, class(ClassName0))
		->
			ClassName = ClassName0
		;
			unexpected(this_file, "non-class for new_object")
		},	
		list__map_foldl(load, Args, ArgsLoadInstrsTrees),
		{ ArgsLoadInstrs = tree__list(ArgsLoadInstrsTrees) },
		get_load_store_lval_instrs(Target, LoadMemRefInstrs,
			StoreLvalInstrs),
		{ CallCtor = newobj_constructor(ClassName) },
		{ Instrs = tree__list([
			LoadMemRefInstrs, 
			comment_node("new object (call constructor)"),
			ArgsLoadInstrs,
			instr_node(CallCtor),
			StoreLvalInstrs
			]) }
	    ;
			% Otherwise this is a generic mercury object -- we 
			% use an array of System::Object to represent
			% it.
			%
			% 	... load memory reference ...
			%	// new object 
			%	ldc <size of array>
			%	newarr
			%
			% And then for each array element:
			%
			%	dup
			%	ldc <array index>
			%	... load and box rval ...
			%	stelem System::Object
			%
			% Finally, after all the array elements have
			% been set:
			%
			%	... store to memory reference ...
			
			% We need to do the boxing ourselves because
			% MLDS hasn't done it.  We add boxing unops to
			% the rvals.
		{ Box = (pred(A - T::in, B::out) is det :- 
			B = unop(box(T), A)   
		) },
		{ assoc_list__from_corresponding_lists(Args, ArgTypes,
			ArgsAndTypes) },
		{ list__map(Box, ArgsAndTypes, BoxedArgs) },
	
			% Load each rval 
			% (XXX we do almost exactly the same code when
			% initializing array data structures -- we
			% should reuse that code.
		{ LoadInArray = (pred(Rval::in, I::out, Arg0::in, 
				Arg::out) is det :- 
			Arg0 = Index - S0,
			I0 = instr_node(dup),
			load(const(int_const(Index)), I1, S0, S1),
			load(Rval, I2, S1, S), 
			I3 = instr_node(stelem(il_generic_simple_type)),
			I = tree__list([I0, I1, I2, I3]),
			Arg = (Index + 1) - S
		) },
		=(State0),
		{ list__map_foldl(LoadInArray, BoxedArgs, ArgsLoadInstrsTrees,
			0 - State0, _ - State) },
		{ ArgsLoadInstrs = tree__list(ArgsLoadInstrsTrees) },
		dcg_set(State),

			% Get the instructions to load and store the
			% target.
		get_load_store_lval_instrs(Target, LoadMemRefInstrs,
			StoreLvalInstrs),

			% XXX some hackery here to get around the MLDS memory
			% allocation that tries to allocate in bytes.
		{ Size = yes(binop((*), SizeInWordsRval0, _)) ->
			SizeInWordsRval = SizeInWordsRval0
		; Size = yes(SizeInWordsRval0) ->
			SizeInWordsRval = SizeInWordsRval0
		;
			% XXX something else
			error("unknown size in MLDS new_object")
		},
		load(SizeInWordsRval, LoadSizeInstrs),

		{ Instrs = tree__list([
			LoadMemRefInstrs,
			comment_node("new object"),
			LoadSizeInstrs,
			instr_node(newarr(il_generic_type)),
			ArgsLoadInstrs,
			StoreLvalInstrs
			]) }
		).

:- pred get_all_load_store_lval_instrs(list(lval), instr_tree, instr_tree,
		il_info, il_info).
:- mode get_all_load_store_lval_instrs(in, out, out, in, out) is det.
get_all_load_store_lval_instrs([], empty, empty) --> [].
get_all_load_store_lval_instrs([Lval | Lvals], 
		tree(LoadMemRefNode, LoadMemRefTree),
		tree(StoreLvalNode, StoreLvalTree)) -->
	get_load_store_lval_instrs(Lval, LoadMemRefNode, StoreLvalNode),
	get_all_load_store_lval_instrs(Lvals, LoadMemRefTree, StoreLvalTree).

	% Some lvals need to be loaded before you load the rval.
	% XXX It would be much better if this took the lval and the rval and
	% just gave you a single tree.  Instead it gives you the
	% "before" tree and the "after" tree and asks you to sandwich
	% the rval in between.
	% The predicate `store' should probably take the lval and the
	% rval and do all of this at once.
:- pred get_load_store_lval_instrs(lval, instr_tree, instr_tree, il_info,
		il_info).
:- mode get_load_store_lval_instrs(in, out, out, in, out) is det.
get_load_store_lval_instrs(Lval, LoadMemRefInstrs,
		StoreLvalInstrs) -->
	( { Lval = mem_ref(Rval0, MLDS_Type) } ->
		load(Rval0, LoadMemRefInstrs),
		{ ILType = mlds_type_to_ilds_type(MLDS_Type) },
		{ ILType = ilds__type(_, SimpleType) },
		{ StoreLvalInstrs = instr_node(stind(SimpleType)) } 
	; { Lval = field(_MaybeTag, FieldRval, FieldNum, FieldType, 
			ClassType) } -> 
		{ get_fieldref(FieldNum, FieldType, ClassType, 
			FieldRef) },
		load(FieldRval, LoadMemRefInstrs),
		{ StoreLvalInstrs = instr_node(stfld(FieldRef)) } 
	;
		{ LoadMemRefInstrs = empty },
		store(Lval, StoreLvalInstrs)
	).

%-----------------------------------------------------------------------------%
%
% Load and store.
%
% NOTE: Be very careful calling store directly.  You probably want to
% call get_load_store_lval_instrs to generate the prelude part (which
% will load any memory reference that need to be loaded) and the store
% part (while will store the rval into the pre-loaded lval), and then
% sandwich the calculation of the rval in between the two.
%

:- pred load(mlds__rval, instr_tree, il_info, il_info) is det.
:- mode load(in, out, in, out) is det.

load(lval(Lval), Instrs, Info0, Info) :- 
	( Lval = var(Var),
		mangle_mlds_var(Var, MangledVarStr),
		( is_local(MangledVarStr, Info0) ->
			Instrs = instr_node(ldloc(name(MangledVarStr)))
		; is_argument(Var, Info0) ->
			Instrs = instr_node(ldarg(name(MangledVarStr)))
		;
			% XXX RTTI generates vars which are references
			% to other modules!
			Var = qual(ModuleName, _),
			mangle_dataname_module(no, ModuleName,
				NewModuleName),
			ClassName = mlds_module_name_to_class_name(
				NewModuleName),
			GlobalType = mlds_type_to_ilds_type(
				mlds_type_for_rtti_global),
			FieldRef = make_fieldref(GlobalType, ClassName, 
				MangledVarStr),
			Instrs = instr_node(ldsfld(FieldRef))
		),
		Info0 = Info
	; Lval = field(_MaybeTag, Rval, FieldNum, FieldType, ClassType),
		load(Rval, RvalLoadInstrs, Info0, Info1),
		( FieldNum = offset(OffSet) ->
			ILFieldType = mlds_type_to_ilds_type(FieldType),
			ILFieldType = ilds__type(_, SimpleFieldType),
			load(OffSet, OffSetLoadInstrs, Info1, Info),
			LoadInstruction = ldelem(SimpleFieldType)
		;
			get_fieldref(FieldNum, FieldType, ClassType, FieldRef),
			LoadInstruction = ldfld(FieldRef),
			OffSetLoadInstrs = empty,
			Info = Info1
		),
		Instrs = tree__list([
				RvalLoadInstrs, 
				OffSetLoadInstrs, 
				instr_node(LoadInstruction)
				])
	; Lval = mem_ref(Rval, MLDS_Type),
		ILType = mlds_type_to_ilds_type(MLDS_Type),
		ILType = ilds__type(_, SimpleType),
		load(Rval, RvalLoadInstrs, Info0, Info),
		Instrs = tree__list([
			RvalLoadInstrs,
			instr_node(ldind(SimpleType))
			])
	).

load(mkword(_Tag, _Rval), Instrs, Info, Info) :- 
	Instrs = comment_node("unimplemented load rval mkword").

	% XXX check these, what should we do about multi strings, 
	% characters, etc.
load(const(Const), Instrs, Info, Info) :- 
		% XXX is there a better way to handle true and false
		% using IL's bool type?
	( Const = true,
		Instrs = instr_node(ldc(int32, i(1)))
	; Const = false,
		Instrs = instr_node(ldc(int32, i(0)))
	; Const = string_const(Str),
		Instrs = instr_node(ldstr(Str))
	; Const = int_const(Int),
		Instrs = instr_node(ldc(int32, i(Int)))
	; Const = float_const(Float),
		Instrs = instr_node(ldc(float64, f(Float)))
	; Const = multi_string_const(_Length, _MultiString),
		Instrs = throw_unimplemented("load multi_string_const")
	; Const = code_addr_const(CodeAddr),
		code_addr_constant_to_methodref(CodeAddr, MethodRef),
		Instrs = instr_node(ldftn(MethodRef))
	; Const = data_addr_const(DataAddr),
		data_addr_constant_to_fieldref(DataAddr, FieldRef),
		Instrs = instr_node(ldsfld(FieldRef))
	; Const = null(_MLDSType),
			% We might consider loading an integer for 
			% null function types.
		Instrs = instr_node(ldnull)
	).

load(unop(Unop, Rval), Instrs) -->
	load(Rval, RvalLoadInstrs),
	unaryop_to_il(Unop, Rval, UnOpInstrs),
	{ Instrs = tree__list([RvalLoadInstrs, UnOpInstrs]) }.

load(binop(BinOp, R1, R2), Instrs) -->
	load(R1, R1LoadInstrs),
	load(R2, R2LoadInstrs),
	binaryop_to_il(BinOp, BinaryOpInstrs),
	{ Instrs = tree__list([R1LoadInstrs, R2LoadInstrs, BinaryOpInstrs]) }.

load(mem_addr(Lval), Instrs, Info0, Info) :- 
	( Lval = var(Var),
		mangle_mlds_var(Var, MangledVarStr),
		Info0 = Info,
		( is_local(MangledVarStr, Info) ->
			Instrs = instr_node(ldloca(name(MangledVarStr)))
		;
			Instrs = instr_node(ldarga(name(MangledVarStr)))
		)
	; Lval = field(_MaybeTag, Rval, FieldNum, FieldType, ClassType),
		get_fieldref(FieldNum, FieldType, ClassType, FieldRef),
		load(Rval, RvalLoadInstrs, Info0, Info),
		Instrs = tree__list([
			RvalLoadInstrs, 
			instr_node(ldflda(FieldRef))
			])
	; Lval = mem_ref(_, _),
		Info0 = Info,
			% XXX implement this
		Instrs = throw_unimplemented("load mem_addr lval mem_ref")
	).

:- pred store(mlds__lval, instr_tree, il_info, il_info) is det.
:- mode store(in, out, in, out) is det.

store(field(_MaybeTag, Rval, FieldNum, FieldType, ClassType), Instrs, 
		Info0, Info) :- 
	get_fieldref(FieldNum, FieldType, ClassType, FieldRef),
	load(Rval, RvalLoadInstrs, Info0, Info),
	Instrs = tree__list([RvalLoadInstrs, instr_node(stfld(FieldRef))]).

store(mem_ref(_Rval, _Type), _Instrs, Info, Info) :- 
		% you always need load the reference first, then
		% the value, then stind it.  There's no swap
		% instruction.  Annoying, eh?
	unexpected(this_file, "store into mem_ref").

store(var(Var), Instrs, Info, Info) :- 
	mangle_mlds_var(Var, MangledVarStr),
	( is_local(MangledVarStr, Info) ->
		Instrs = instr_node(stloc(name(MangledVarStr)))
	;
		Instrs = instr_node(starg(name(MangledVarStr)))
	).

%-----------------------------------------------------------------------------%
%
% Convert binary and unary operations to IL
%


:- pred unaryop_to_il(mlds__unary_op, mlds__rval, instr_tree, il_info,
	il_info) is det.
:- mode unaryop_to_il(in, in, out, in, out) is det.

	% Once upon a time the code generator generated primary tag tests
	% (but we don't use primary tags).
	% If we make mktag return its operand (since it will always be
	% called with 0 as its operand), and we make tag return 0, it will
	% always succeed in the tag test (which is good, with tagbits = 0
	% we want to always succeed all primary tag tests).

unaryop_to_il(std_unop(mktag), _, comment_node("mktag (a no-op)")) --> [].
unaryop_to_il(std_unop(tag), _, Instrs) --> 
	load(const(int_const(0)), Instrs).
unaryop_to_il(std_unop(unmktag), _, comment_node("unmktag (a no-op)")) --> [].
unaryop_to_il(std_unop(mkbody),	_, comment_node("mkbody (a no-op)")) --> [].
unaryop_to_il(std_unop(unmkbody), _, comment_node("unmkbody (a no-op)")) --> [].

		% XXX implement this using string__hash
unaryop_to_il(std_unop(hash_string), _,
	throw_unimplemented("unimplemented hash_string unop")) --> [].
unaryop_to_il(std_unop(bitwise_complement), _, node([not])) --> [].

		% might want to revisit this and define not to be only
		% valid on 1 or 0, then we can use ldc.i4.1 and xor,
		% which might be more efficient.
unaryop_to_il(std_unop((not)), _,
	node([ldc(int32, i(1)), clt(unsigned)])) --> [].

		% if we are casting from an unboxed type, we should box
		% it first.
		% XXX should also test the cast-to type, to handle the
		% cases where it is unboxed.
unaryop_to_il(cast(Type), Rval, Instrs) -->
	{ ILType = mlds_type_to_ilds_type(Type) },
	{ 
		Rval = const(Const),
		RvalType = rval_const_to_type(Const),
		RvalILType = mlds_type_to_ilds_type(RvalType),
		not already_boxed(RvalILType)
	->
		Instrs = node([call(convert_to_object(RvalILType)),
			castclass(ILType)])
	;
		Instrs = node([castclass(ILType)])
	}.


	% XXX boxing and unboxing should be fixed.
	% currently for boxing and unboxing we call some conversion
	% methods that written by hand. 
	% We should do a small MLDS->MLDS transformation to introduce
	% locals so we can box the address of the locals.
	% then unboxing should just be castclass(System.Int32 or whatever),
	% then unbox.
unaryop_to_il(box(Type), _, Instrs) -->
	{ ILType = mlds_type_to_ilds_type(Type) },
	{ already_boxed(ILType) ->
		Instrs = node([isinst(il_generic_type)])
	;
		Instrs = node([call(convert_to_object(ILType))])
		% XXX can't just use box, because it requires a pointer to
		% the object, so it's useless for anything that isn't
		% addressable
		% Instrs = [box(ILType)]  
	}.

unaryop_to_il(unbox(Type), _, Instrs) -->
	{ ILType = mlds_type_to_ilds_type(Type) },
	{ ILType = ilds__type(_, class(_)) ->
		Instrs = node([castclass(ILType)])
	;
		Instrs = node([call(convert_from_object(ILType))])
		% since we can't use box, we can't use unbox
		% Instrs = [unbox(ILType)]
	}.

:- pred already_boxed(ilds__type::in) is semidet.
already_boxed(ilds__type(_, class(_))).
already_boxed(ilds__type(_, '[]'(_, _))).

:- pred binaryop_to_il(binary_op, instr_tree, il_info,
	il_info) is det.
:- mode binaryop_to_il(in, out, in, out) is det.

binaryop_to_il((+), instr_node(I)) -->
	{ I = add(nocheckoverflow, signed) }.

binaryop_to_il((-), instr_node(I)) -->
	{ I = sub(nocheckoverflow, signed) }.

binaryop_to_il((*), instr_node(I)) -->
	{ I = mul(nocheckoverflow, signed) }.

binaryop_to_il((/), instr_node(I)) -->
	{ I = div(signed) }.

binaryop_to_il((mod), instr_node(I)) -->
	{ I = rem(signed) }.

binaryop_to_il((<<), instr_node(I)) -->
	{ I = shl }.

binaryop_to_il((>>), instr_node(I)) -->
	{ I = shr(signed) }.

binaryop_to_il((&), instr_node(I)) -->
	{ I = (and) }.

binaryop_to_il(('|'), instr_node(I)) -->
	{ I = (or) }.

binaryop_to_il(('^'), instr_node(I)) -->
	{ I = (xor) }.

binaryop_to_il((and), instr_node(I)) --> % This is logical and
	{ I = (and) }.

binaryop_to_il((or), instr_node(I)) --> % This is logical or
	{ I = (or) }.

binaryop_to_il(eq, instr_node(I)) -->
	{ I = ceq }.

binaryop_to_il(ne, node(Instrs)) --> 
	{ Instrs = [
		ceq, 
		ldc(int32, i(0)),
		ceq
	] }.

binaryop_to_il(body, _) -->
	{ unexpected(this_file, "binop: body") }.


	% XXX we need to know what kind of thing is being indexed
	% from the array in general. 
binaryop_to_il(array_index, throw_unimplemented("array index unimplemented")) 
		--> [].

	% String operations.
binaryop_to_il(str_eq, node([
		call(il_string_equals)
		])) --> [].
binaryop_to_il(str_ne, node([
		call(il_string_equals),
		ldc(int32, i(0)),
		ceq
		])) --> [].
binaryop_to_il(str_lt, node([
		call(il_string_compare),
		ldc(int32, i(0)),
		clt(signed)
		])) --> [].
binaryop_to_il(str_gt, node([
		call(il_string_compare),
		ldc(int32, i(0)),
		cgt(signed)
		])) --> [].
binaryop_to_il(str_le, node([
		call(il_string_compare),
		ldc(int32, i(1)), clt(signed)
		])) --> [].
binaryop_to_il(str_ge, node([
		call(il_string_compare),
		ldc(int32, i(-1)),
		cgt(signed)
		])) --> [].

	% Integer comparison
binaryop_to_il((<), node([clt(signed)])) --> [].
binaryop_to_il((>), node([cgt(signed)])) --> [].
binaryop_to_il((<=), node([cgt(signed), ldc(int32, i(0)), ceq])) --> [].
binaryop_to_il((>=), node([clt(signed), ldc(int32, i(0)), ceq])) --> [].
binaryop_to_il(unsigned_le, node([cgt(unsigned), ldc(int32, i(0)), ceq])) -->
	[].

	% Floating pointer operations.
binaryop_to_il(float_plus, instr_node(I)) -->
	{ I = add(nocheckoverflow, signed) }.
binaryop_to_il(float_minus, instr_node(I)) -->
	{ I = sub(nocheckoverflow, signed) }.
binaryop_to_il(float_times, instr_node(I)) -->
	{ I = mul(nocheckoverflow, signed) }.
binaryop_to_il(float_divide, instr_node(I)) -->
	{ I = div(signed) }.
binaryop_to_il(float_eq, instr_node(I)) -->
	{ I = ceq }.
binaryop_to_il(float_ne, node(Instrs)) --> 
	{ Instrs = [
		ceq, 
		ldc(int32, i(0)),
		ceq
	] }.
binaryop_to_il(float_lt, node([clt(signed)])) --> [].
binaryop_to_il(float_gt, node([cgt(signed)])) --> [].
binaryop_to_il(float_le, node([cgt(signed), ldc(int32, i(0)), ceq])) --> [].
binaryop_to_il(float_ge, node([clt(signed), ldc(int32, i(0)), ceq])) --> [].

%-----------------------------------------------------------------------------%
%
% Generate code for conditional statements
%
% For most conditionals, we simply load the rval and branch to the else
% case if it is false.
%
%	load rval
%	brfalse elselabel
%
% For eq and ne binops, this will generate something a bit wasteful, e.g.
%
%	load operand1
%	load operand2
%	ceq
%	brfalse elselabel
%
% We try to avoid generating a comparison result on the stack and then
% comparing it to false.  Instead we load the operands and
% branch/compare all at once.  E.g.
%
%	load operand1
%	load operand2
%	bne.unsigned elselabel
%
% Perhaps it would be better to just generate the default code and let
% the peephole optimizer pick this one up.  Since it's pretty easy
% to detect I've left it here for now.

:- pred generate_condition(rval, instr_tree, string, 
		il_info, il_info).
:- mode generate_condition(in, out, out, in, out) is det.

generate_condition(Rval, Instrs, ElseLabel) -->
	il_info_make_next_label(ElseLabel),
	( 
		{ Rval = binop(eq, Operand1, Operand2) }
	->
		load(Operand1, Op1Instr),
		load(Operand2, Op2Instr),
		{ OpInstr = instr_node(
			bne(unsigned, label_target(ElseLabel))) },
		{ Instrs = tree__list([Op1Instr, Op2Instr, OpInstr]) }
	; 
		{ Rval = binop(ne, Operand1, Operand2) }
	->
		load(Operand1, Op1Instr),
		load(Operand2, Op2Instr),
		{ OpInstr = instr_node(beq(label_target(ElseLabel))) },
		{ Instrs = tree__list([Op1Instr, Op2Instr, OpInstr]) }
	;
		load(Rval, RvalLoadInstrs),
		{ ExtraInstrs = instr_node(brfalse(label_target(ElseLabel))) },
		{ Instrs = tree__list([RvalLoadInstrs, ExtraInstrs]) }
	).

%-----------------------------------------------------------------------------%
%
% Get a function name for a code_addr_const rval.
%
% XXX This predicate should be narrowed down to the cases that actually
% make sense.


	% Convert an rval into a function we can call.
:- pred rval_to_function(rval, class_member_name).
:- mode rval_to_function(in, out) is det.
rval_to_function(Rval, MemberName) :-
	( Rval = const(Const),
		( Const = code_addr_const(CodeConst) ->
			( CodeConst = proc(ProcLabel, _Sig),
				mangle_mlds_proc_label(ProcLabel, no, 
					ClassName, ProcLabelStr),
				MemberName = class_member_name(ClassName, 
					id(ProcLabelStr))
			; CodeConst = internal(ProcLabel, SeqNum, _Sig),
				mangle_mlds_proc_label(ProcLabel, yes(SeqNum),
					ClassName, ProcLabelStr),
				MemberName = class_member_name(ClassName, 
					id(ProcLabelStr))
			)
		;
			unexpected(this_file,
				"rval_to_function: const is not a code address")
		)
	; Rval = mkword(_, _),
		unexpected(this_file, "mkword_function_name")
	; Rval = lval(_),
		unexpected(this_file, "lval_function_name")
	; Rval = unop(_, _),
		unexpected(this_file, "unop_function_name")
	; Rval = binop(_, _, _),
		unexpected(this_file, "binop_function_name")
	; Rval = mem_addr(_),
		unexpected(this_file, "mem_addr_function_name")
	).

%-----------------------------------------------------------------------------
%
% Class constructors (.cctors) are used to fill in the RTTI information
% needed for any types defined in the module.  The RTTI is stored in
% static fields of the class.

	% .cctors can be called at practically any time by the runtime
	% system, but must be called before a static field is loaded
	% (the runtime will ensure this happens).
	% Since all the static fields in RTTI reference other RTTI static
	% fields, we could run into problems if we load a field from another
	% class before we initialize it.  Often the RTTI in one module will
	% refer to another, creating exactly this cross-referencing problem.
	% To avoid problems, we initialize them in 3 passes.
	%
	% 1. We allocate all the RTTI data structures but leave them blank.
	% When this is complete we set a flag to say we have completed this
	% pass.  After this pass is complete, it is safe for any other module
	% to reference our data structures.
	%
	% 2. We call all the .cctors for RTTI data structures that we
	% import.  We do this because we can't load fields from them until we
	% know they have been allocated.
	%
	% 3. We fill in the RTTI info in the already allocated structures.
	%
	% To ensure that pass 2 doesn't cause looping, the first thing done
	% in all .cctors is a check to see if the flag is set.  If it is, we
	% return immediately (we have already been called and our
	% initialization is either complete or at pass 2).
	%
	% 	// if (rtti_initialized) return;
	% 	ldsfld rtti_initialized
	%       brfalse done_label
	% 	ret
	% 	done_label:
	% 
	% 	// rtti_initialized = true
	% 	ldc.i4.1
	% 	stsfld rtti_initialized
	% 
	% 	// allocate RTTI data structures.
	% 	<allocation instructions generated by field initializers>
	% 
	% 	// call .cctors
	% 	call	someclass::.cctor
	% 	call	someotherclass::.cctor
	% 	... etc ...
	% 
	% 	// fill in fields of RTTI data structures
	% 	<initialization instructions generated by field initializers>
	%

:- pred make_class_constructor_classdecl(fieldref, mlds__imports,
	list(instr), list(instr), classdecl, il_info, il_info).
:- mode make_class_constructor_classdecl(in, in, in, in, out, in, out) is det.
make_class_constructor_classdecl(DoneFieldRef, Imports, AllocInstrs, 
		InitInstrs, Method) -->
	{ Method = method(methodhead([static], cctor, 
		signature(call_conv(no, default), void, []), []),
		MethodDecls) },
	test_rtti_initialization_field(DoneFieldRef, TestInstrs),
	set_rtti_initialization_field(DoneFieldRef, SetInstrs),
	{ CCtorCalls = list__map((func(X) = call_class_constructor(
		mlds_module_name_to_class_name(X))), Imports) },
	{ AllInstrs = list__condense([TestInstrs, AllocInstrs, SetInstrs,
		CCtorCalls, InitInstrs, [ret]]) },
	{ MethodDecls = [instrs(AllInstrs)] }.

:- pred test_rtti_initialization_field(fieldref, list(instr),
		il_info, il_info).
:- mode test_rtti_initialization_field(in, out, in, out) is det.
test_rtti_initialization_field(FieldRef, Instrs) -->
	il_info_make_next_label(DoneLabel),
	{ Instrs = [ldsfld(FieldRef), brfalse(label_target(DoneLabel)),
		ret, label(DoneLabel)] }.

:- pred set_rtti_initialization_field(fieldref, list(instr),
		il_info, il_info).
:- mode set_rtti_initialization_field(in, out, in, out) is det.
set_rtti_initialization_field(FieldRef, Instrs) -->
	{ Instrs = [ldc(int32, i(1)), stsfld(FieldRef)] }.


:- pred generate_rtti_initialization_field(ilds__class_name, 
		fieldref, classdecl).
:- mode generate_rtti_initialization_field(in, out, out) is det.
generate_rtti_initialization_field(ClassName, AllocDoneFieldRef,
		AllocDoneField) :-
	AllocDoneFieldName = "rtti_initialized",
	AllocDoneField = field([public, static], ilds__type([], bool),
				AllocDoneFieldName, no, none),
	AllocDoneFieldRef = make_fieldref(ilds__type([], bool),
		ClassName, AllocDoneFieldName).



%-----------------------------------------------------------------------------
%
% Conversion of MLDS types to IL types.

:- pred mlds_signature_to_ilds_type_params(mlds__func_signature, list(ilds__type)).
:- mode mlds_signature_to_ilds_type_params(in, out) is det.
mlds_signature_to_ilds_type_params(func_signature(Args, _Returns), Params) :-
	Params = list__map(mlds_type_to_ilds_type, Args).

:- pred mlds_arg_to_il_arg(pair(mlds__entity_name, mlds__type), 
		pair(ilds__id, mlds__type)).
:- mode mlds_arg_to_il_arg(in, out) is det.
mlds_arg_to_il_arg(EntityName - Type, Id - Type) :-
	mangle_entity_name(EntityName, Id).

:- pred mlds_signature_to_il_return_param(mlds__func_signature, ret_type).
:- mode mlds_signature_to_il_return_param(in, out) is det.
mlds_signature_to_il_return_param(func_signature(_, Returns), Param) :-
	( Returns = [] ->
		Param = void
	; Returns = [ReturnType] ->
		ReturnParam = mlds_type_to_ilds_type(ReturnType),
		ReturnParam = ilds__type(_, SimpleType),
		Param = simple_type(SimpleType)
	;
		% IL doesn't support multiple return values
		sorry(this_file, "multiple return values")
	).

params_to_il_signature(ModuleName, mlds__func_params(Inputs, Outputs),
		 ILSignature) :-
	ILInputTypes = list__map(input_param_to_ilds_type(ModuleName), Inputs),
	( Outputs = [] ->
		Param = void
	; Outputs = [ReturnType] ->
		ReturnParam = mlds_type_to_ilds_type(ReturnType),
		ReturnParam = ilds__type(_, SimpleType),
		Param = simple_type(SimpleType)
	;
		% IL doesn't support multiple return values
		sorry(this_file, "multiple return values")
	),
	ILSignature = signature(call_conv(no, default), Param, ILInputTypes).

:- func input_param_to_ilds_type(mlds_module_name, 
		pair(entity_name, mlds__type)) = ilds__param.
input_param_to_ilds_type(ModuleName, EntityName - MldsType) 
		= ILType - yes(Id) :-
	mangle_entity_name(EntityName, VarName),
	mangle_mlds_var(qual(ModuleName, VarName), Id),
	ILType = mlds_type_to_ilds_type(MldsType).
	

	% XXX make sure all the types are converted correctly

mlds_type_to_ilds_type(mlds__rtti_type(_RttiName)) = il_array_type.

mlds_type_to_ilds_type(mlds__array_type(ElementType)) = 
	ilds__type([], '[]'(mlds_type_to_ilds_type(ElementType), [])).

	% This is tricky.  It could be an integer, or it could be
	% a System.Array.
mlds_type_to_ilds_type(mlds__pseudo_type_info_type) = il_generic_type.

	% IL has a pretty fuzzy idea about function types.
	% We treat them as integers for now
	% XXX This means the code is not verifiable.
mlds_type_to_ilds_type(mlds__func_type(_)) = ilds__type([], int32).

mlds_type_to_ilds_type(mlds__generic_type) = il_generic_type.

	% XXX Using int32 here means the code is not verifiable
	% see comments about function types above.
mlds_type_to_ilds_type(mlds__cont_type(_ArgTypes)) = ilds__type([], int32).

mlds_type_to_ilds_type(mlds__class_type(Class, _Arity, _Kind)) = ILType :-
	Class = qual(MldsModuleName, MldsClassName),
	ClassName = mlds_module_name_to_class_name(MldsModuleName),
	list__append(ClassName, [MldsClassName], FullClassName),
	ILType = ilds__type([], class(FullClassName)).

mlds_type_to_ilds_type(mlds__commit_type) =
	ilds__type([], class(["mercury", "runtime", "Commit"])).

mlds_type_to_ilds_type(mlds__generic_env_ptr_type) = il_envptr_type.

	% XXX we ought to use the IL bool type
mlds_type_to_ilds_type(mlds__native_bool_type) = ilds__type([], int32).


mlds_type_to_ilds_type(mlds__native_char_type) = ilds__type([], char).

	% These two following choices are arbitrary -- IL has native
	% integer and float types too.  It's not clear whether there is
	% any benefit in mapping to them instead -- it all depends what
	% the indended use of mlds__native_int_type and
	% mlds__native_float_type is.
	% Any mapping other than int32 would have to be examined to see
	% whether it is going to be compatible with int32.
mlds_type_to_ilds_type(mlds__native_int_type) = ilds__type([], int32).

mlds_type_to_ilds_type(mlds__native_float_type) = ilds__type([], float64).

mlds_type_to_ilds_type(mlds__ptr_type(MLDSType)) =
	ilds__type([], '&'(mlds_type_to_ilds_type(MLDSType))).

	% XXX should use the classification now that it is available.
mlds_type_to_ilds_type(mercury_type(Type, _Classification)) = ILType :-
	( 
		Type = term__functor(term__atom(Atom), [], _),
		( Atom = "string", 	SimpleType = il_string_simple_type
		; Atom = "int", 	SimpleType = int32
		; Atom = "character",	SimpleType = char
		; Atom = "float",	SimpleType = float64
		) 
	->
		ILType = ilds__type([], SimpleType)
	;
		Type = term__variable(_)
	->
		ILType = il_generic_type
		% XXX we can't use MR_Box (il_generic_type) for C
		% pointers just yest, because abstract data types are
		% assumed to be MR_Word (and MR_Box is not compatible
		% with MR_Word in the IL backend).
%	;
%		type_to_type_id(Type, 
%			qualified(unqualified("builtin"), "c_pointer") - 0, [])
%	->
%		ILType = il_generic_type
	;
		ILType = il_array_type
	).


%-----------------------------------------------------------------------------
%
% Name mangling.


	% XXX we should check into the name mangling done here to make
	% sure it is all necessary.
	% We may need to do different name mangling for CLS compliance
	% than we would otherwise need.
predlabel_to_id(pred(PredOrFunc, MaybeModuleName, Name, Arity), ProcId, 
			MaybeSeqNum, Id) :-
		( PredOrFunc = predicate, PredOrFuncStr = "p" 
		; PredOrFunc = function, PredOrFuncStr = "f" 
		),
		proc_id_to_int(ProcId, ProcIdInt),
		( MaybeModuleName = yes(ModuleName) ->
			mlds_to_il__sym_name_to_string(ModuleName, MStr),
			string__format("%s_", [s(MStr)], MaybeModuleStr)
		;
			MaybeModuleStr = ""
		),
		( MaybeSeqNum = yes(SeqNum) ->
			string__format("_%d", [i(SeqNum)], MaybeSeqNumStr)
		;
			MaybeSeqNumStr = ""
		),
		string__format("%s%s_%d_%s_%d%s", [s(MaybeModuleStr), s(Name),
			 i(Arity), s(PredOrFuncStr), i(ProcIdInt),
			 s(MaybeSeqNumStr)], UnMangledId),
		llds_out__name_mangle(UnMangledId, Id).

predlabel_to_id(special_pred(PredName, MaybeModuleName, TypeName, Arity),
			ProcId, MaybeSeqNum, Id) :-
		proc_id_to_int(ProcId, ProcIdInt),
		( MaybeModuleName = yes(ModuleName) ->
			mlds_to_il__sym_name_to_string(ModuleName, MStr),
			string__format("%s_", [s(MStr)], MaybeModuleStr)
		;
			MaybeModuleStr = ""
		),
		( MaybeSeqNum = yes(SeqNum) ->
			string__format("_%d", [i(SeqNum)], MaybeSeqNumStr)
		;
			MaybeSeqNumStr = ""
		),
		string__format("special_%s%s_%s_%d_%d%s", 
			[s(MaybeModuleStr), s(PredName), s(TypeName), i(Arity),
				i(ProcIdInt), s(MaybeSeqNumStr)], UnMangledId),
		llds_out__name_mangle(UnMangledId, Id).

	% When generating references to RTTI, we need to mangle the
	% module name if the RTTI is defined in C code by hand.
	% If no data_name is provided, always do the mangling.
:- pred mangle_dataname_module(maybe(mlds__data_name), mlds_module_name,
	mlds_module_name).
:- mode mangle_dataname_module(in, in, out) is det.

mangle_dataname_module(no, ModuleName0, ModuleName) :-
	SymName0 = mlds_module_name_to_sym_name(ModuleName0),
	( 
		SymName0 = qualified(Q, M0),
		string__append(M0, "__c_code", M),
		SymName = qualified(Q, M)
	; 
		SymName0 = unqualified(M0),
		string__append(M0, "__c_code", M),
		SymName = unqualified(M)
	),
	ModuleName = mercury_module_name_to_mlds(SymName).

mangle_dataname_module(yes(DataName), ModuleName0, ModuleName) :-
	( 
		SymName = mlds_module_name_to_sym_name(ModuleName0),
		SymName = qualified(unqualified("mercury"),
			LibModuleName0),
		DataName = rtti(rtti_type_id(_, Name, Arity),
			_RttiName),
		( LibModuleName0 = "builtin",
			( 
			  Name = "int", Arity = 0 
			; Name = "string", Arity = 0
			; Name = "float", Arity = 0
			; Name = "character", Arity = 0
			; Name = "void", Arity = 0
			; Name = "c_pointer", Arity = 0
			; Name = "pred", Arity = 0
			; Name = "func", Arity = 0
			)
		; LibModuleName0 = "array", 
			(
			  Name = "array", Arity = 1
			)
		; LibModuleName0 = "std_util",
			( 
			  Name = "type_desc", Arity = 0
			)
		; LibModuleName0 = "private_builtin",
			( 
			  Name = "type_ctor_info", Arity = 1
			; Name = "type_info", Arity = 1
			; Name = "base_typeclass_info", Arity = 1
			; Name = "typeclass_info", Arity = 1
			)
		)		  
	->
		string__append(LibModuleName0, "__c_code",
			LibModuleName),
		ModuleName = mercury_module_name_to_mlds(
			qualified(unqualified("mercury"), LibModuleName))
	;
		ModuleName = ModuleName0
	).



:- pred mangle_dataname(mlds__data_name, string).
:- mode mangle_dataname(in, out) is det.

mangle_dataname(var(Name), Name).
mangle_dataname(common(Int), MangledName) :-
	string__format("common_%s", [i(Int)], MangledName).
mangle_dataname(rtti(RttiTypeId, RttiName), MangledName) :-
	rtti__addr_to_string(RttiTypeId, RttiName, MangledName).
mangle_dataname(base_typeclass_info(ClassId, InstanceStr), MangledName) :-
        llds_out__make_base_typeclass_info_name(ClassId, InstanceStr,
		MangledName).
mangle_dataname(module_layout, _MangledName) :-
	error("unimplemented: mangling module_layout").
mangle_dataname(proc_layout(_), _MangledName) :-
	error("unimplemented: mangling proc_layout").
mangle_dataname(internal_layout(_, _), _MangledName) :-
	error("unimplemented: mangling internal_layout").
mangle_dataname(tabling_pointer(_), _MangledName) :-
	error("unimplemented: mangling tabling_pointer").

	% We turn procedures into methods of classes.
mangle_mlds_proc_label(qual(ModuleName, PredLabel - ProcId), MaybeSeqNum,
		ClassName, PredStr) :-
	ClassName = mlds_module_name_to_class_name(ModuleName),
	predlabel_to_id(PredLabel, ProcId, MaybeSeqNum, PredStr).

:- pred mangle_entity_name(mlds__entity_name, string).
:- mode mangle_entity_name(in, out) is det.
mangle_entity_name(type(_TypeName, _), _MangledName) :-
	error("can't mangle type names").
mangle_entity_name(data(DataName), MangledName) :-
	mangle_dataname(DataName, MangledName).
mangle_entity_name(function(_, _, _, _), _MangledName) :-
	error("can't mangle function names").
mangle_entity_name(export(_), _MangledName) :-
	error("can't mangle export names").

	% Any valid Mercury identifier will be fine here too.
	% We quote all identifiers before we output them, so
	% even funny characters should be fine.
mangle_mlds_var(qual(_ModuleName, VarName), Str) :-
	Str = VarName.

:- pred mlds_to_il__sym_name_to_string(sym_name, string).
:- mode mlds_to_il__sym_name_to_string(in, out) is det.
mlds_to_il__sym_name_to_string(SymName, String) :-
        mlds_to_il__sym_name_to_string(SymName, ".", String).

:- pred mlds_to_il__sym_name_to_string(sym_name, string, string).
:- mode mlds_to_il__sym_name_to_string(in, in, out) is det.
mlds_to_il__sym_name_to_string(SymName, Separator, String) :-
        mlds_to_il__sym_name_to_string_2(SymName, Separator, Parts, []),
        string__append_list(Parts, String).

:- pred mlds_to_il__sym_name_to_string_2(sym_name, string, list(string),
	 list(string)).
:- mode mlds_to_il__sym_name_to_string_2(in, in, out, in) is det.

mlds_to_il__sym_name_to_string_2(qualified(ModuleSpec,Name), Separator) -->
        mlds_to_il__sym_name_to_string_2(ModuleSpec, Separator),
        [Separator, Name].
mlds_to_il__sym_name_to_string_2(unqualified(Name), _) -->
        [Name].

mlds_module_name_to_class_name(MldsModuleName) = ClassName :-
	SymName = mlds_module_name_to_sym_name(MldsModuleName),
	sym_name_to_class_name(SymName, ClassName).

:- pred sym_name_to_class_name(sym_name, list(ilds__id)).
:- mode sym_name_to_class_name(in, out) is det.
sym_name_to_class_name(SymName, Ids) :-
	sym_name_to_class_name_2(SymName, Ids0),
	list__reverse(Ids0, Ids).

:- pred sym_name_to_class_name_2(sym_name, list(ilds__id)).
:- mode sym_name_to_class_name_2(in, out) is det.
sym_name_to_class_name_2(qualified(ModuleSpec, Name), [Name | Modules]) :-
	sym_name_to_class_name_2(ModuleSpec, Modules).
sym_name_to_class_name_2(unqualified(Name), [Name]).



%-----------------------------------------------------------------------------%
%
% Predicates for checking various attributes of variables.
%


:- pred is_argument(mlds__var, il_info).
:- mode is_argument(in, in) is semidet.
is_argument(qual(_, VarName), Info) :-
	list__member(VarName - _, Info ^ arguments).

:- pred is_local(string, il_info).
:- mode is_local(in, in) is semidet.
is_local(VarName, Info) :-
	map__contains(Info ^ locals, VarName).

%-----------------------------------------------------------------------------%
%
% Preds and funcs to find the types of rvals.
%

	% This gives us the type of an rval. 
	% This type is an MLDS type, but is with respect to the IL
	% representation (that is, we map code address and data address
	% constants to the MLDS version of their IL representation).
	% This is so you can generate appropriate box rvals for
	% rval_consts.

:- pred rval_to_type(mlds__rval::in, mlds__type::out,
		il_info::in, il_info::out) is det.

rval_to_type(lval(Lval), Type, Info0, Info) :- 
	( Lval = var(Var),
		mangle_mlds_var(Var, MangledVarStr),
		il_info_get_mlds_type(MangledVarStr, Type, Info0, Info)
	; Lval = field(_, _, _, Type, _),
		Info = Info0
	; Lval = mem_ref(_Rval, Type),
		Info = Info0
	).

	% The following four conversions should never occur or be boxed
	% anyway, but just in case they are we make them reference
	% mercury.invalid which is a non-exisitant class.   If we try to
	% run this code, we'll get a runtime error.
	% XXX can we just call error?
rval_to_type(mkword(_Tag, _Rval), Type, I, I) :- 
	ModuleName = mercury_module_name_to_mlds(unqualified("mercury")),
	Type = mlds__class_type(qual(ModuleName, "invalid"),
		0, mlds__class).
rval_to_type(unop(_, _), Type, I, I) :- 
	ModuleName = mercury_module_name_to_mlds(unqualified("mercury")),
	Type = mlds__class_type(qual(ModuleName, "invalid"),
		0, mlds__class).
rval_to_type(binop(_, _, _), Type, I, I) :- 
	ModuleName = mercury_module_name_to_mlds(unqualified("mercury")),
	Type = mlds__class_type(qual(ModuleName, "invalid"),
		0, mlds__class).
rval_to_type(mem_addr(_), Type, I, I) :-
	ModuleName = mercury_module_name_to_mlds(unqualified("mercury")),
	Type = mlds__class_type(qual(ModuleName, "invalid"),
		0, mlds__class).
rval_to_type(const(Const), Type, I, I) :- 
	Type = rval_const_to_type(Const).

:- func rval_const_to_type(mlds__rval_const) = mlds__type.
rval_const_to_type(data_addr_const(_)) =
	mlds__array_type(mlds__generic_type).
rval_const_to_type(code_addr_const(_)) = mlds__func_type(
		mlds__func_params([], [])).
rval_const_to_type(int_const(_)) = mercury_type(
	term__functor(term__atom("int"), [], context("", 0)), int_type).
rval_const_to_type(float_const(_)) = mercury_type(
	term__functor(term__atom("float"), [], context("", 0)), float_type).
rval_const_to_type(false) = mlds__native_bool_type.
rval_const_to_type(true) = mlds__native_bool_type.
rval_const_to_type(string_const(_)) = mercury_type(
	term__functor(term__atom("string"), [], context("", 0)), str_type).
rval_const_to_type(multi_string_const(_, _)) = mercury_type(
	term__functor(term__atom("string"), [], context("", 0)), str_type).
rval_const_to_type(null(MldsType)) = MldsType.

%-----------------------------------------------------------------------------%

:- pred code_addr_constant_to_methodref(mlds__code_addr, methodref).
:- mode code_addr_constant_to_methodref(in, out) is det.

code_addr_constant_to_methodref(proc(ProcLabel, Sig), MethodRef) :-
	mangle_mlds_proc_label(ProcLabel, no, ClassName, ProcLabelStr),
	mlds_signature_to_ilds_type_params(Sig, TypeParams),
	mlds_signature_to_il_return_param(Sig, ReturnParam),
	MemberName = class_member_name(ClassName, id(ProcLabelStr)),
	MethodRef = methoddef(call_conv(no, default), ReturnParam, 
		MemberName, TypeParams).

code_addr_constant_to_methodref(internal(ProcLabel, SeqNum, Sig), MethodRef) :-
	mangle_mlds_proc_label(ProcLabel, yes(SeqNum), ClassName, 
		ProcLabelStr),
	mlds_signature_to_ilds_type_params(Sig, TypeParams),
	mlds_signature_to_il_return_param(Sig, ReturnParam),
	MemberName = class_member_name(ClassName, id(ProcLabelStr)),
	MethodRef = methoddef(call_conv(no, default), ReturnParam, 
		MemberName, TypeParams).


	% Assumed to be a field of a class
:- pred data_addr_constant_to_fieldref(mlds__data_addr, fieldref).
:- mode data_addr_constant_to_fieldref(in, out) is det.

data_addr_constant_to_fieldref(data_addr(ModuleName, DataName), FieldRef) :-
	mangle_dataname(DataName, FieldName),
	mangle_dataname_module(yes(DataName), ModuleName, NewModuleName),
	ClassName = mlds_module_name_to_class_name(NewModuleName),
	FieldRef = make_fieldref(il_array_type, ClassName, FieldName).


%-----------------------------------------------------------------------------%

	% when we generate mercury terms using classes, we should use
	% this to reference the fields of the class.
	% note this pred will handle named or offsets.  It assumes that
	% an offset is transformed into "f<num>".
	% XXX should move towards using this code for *all* field name
	% creation and referencing
	% XXX we remove byrefs from fields here.  Perhaps we ought to do
	% this in a separate pass.   See defn_to_class_decl which does
	% the same thing when creating the fields.
:- pred get_fieldref(field_id, mlds__type, mlds__type, fieldref).
:- mode get_fieldref(in, in, in, out) is det.
get_fieldref(FieldNum, FieldType, ClassType, FieldRef) :-
		FieldILType0 = mlds_type_to_ilds_type(FieldType),
		ClassILType = mlds_type_to_ilds_type(ClassType),
		( FieldILType0 = ilds__type(_, '&'(FieldILType1)) ->
			FieldILType = FieldILType1
		;
			FieldILType = FieldILType0
		),
		( ClassILType = ilds__type(_, 
			class(ClassTypeName0))
		->
			ClassName = ClassTypeName0
		;
			ClassName = ["invalid_field_access_class"]
			% unexpected(this_file, "not a class for field access")
		),
		( 
			FieldNum = offset(OffsetRval),
			( OffsetRval = const(int_const(Num)) ->
				string__format("f%d", [i(Num)], FieldId)
			;
				sorry(this_file, 
					"offsets for non-int_const rvals")
			)
		; 
			FieldNum = named_field(qual(_ModuleName, FieldId),
				_Type)
		),
		FieldRef = make_fieldref(FieldILType, ClassName, FieldId).


%-----------------------------------------------------------------------------%

:- pred defn_to_local(mlds_module_name, mlds__defn, 
	pair(ilds__id, mlds__type)).
:- mode defn_to_local(in, in, out) is det.

defn_to_local(ModuleName, 
	mlds__defn(Name, _Context, _DeclFlags, Entity), Id - MLDSType) :-
	( Name = data(DataName),
	  Entity = mlds__data(MLDSType0, _Initializer) ->
		mangle_dataname(DataName, MangledDataName),
		mangle_mlds_var(qual(ModuleName, MangledDataName), Id),
		MLDSType0 = MLDSType
	;
		error("definition name was not data/1")
	).

%-----------------------------------------------------------------------------%
%
% These functions are for converting to/from generic objects.
%

:- func convert_to_object(ilds__type) = methodref.

convert_to_object(Type) = methoddef(call_conv(no, default), 
		simple_type(il_generic_simple_type),
		class_member_name(il_conversion_class_name, id("ToObject")),
		[Type]).

:- func convert_from_object(ilds__type) = methodref.

convert_from_object(Type) = 
	methoddef(call_conv(no, default), simple_type(SimpleType),
		class_member_name(il_conversion_class_name, id(Id)),
			[il_generic_type]) :-
	Type = ilds__type(_, SimpleType),
	ValueClassName = simple_type_to_value_class_name(SimpleType),
	string__append("To", ValueClassName, Id).


	% XXX String and Array should be converted to/from Object using a
	% cast, not a call to runtime convert.  When that is done they can be
	% removed from this list
:- func simple_type_to_value_class_name(simple_type) = string.
simple_type_to_value_class_name(int8) = "Int8".
simple_type_to_value_class_name(int16) = "Int16".
simple_type_to_value_class_name(int32) = "Int32".
simple_type_to_value_class_name(int64) = "Int64".
simple_type_to_value_class_name(uint8) = "Int8".
simple_type_to_value_class_name(uint16) = "UInt16".
simple_type_to_value_class_name(uint32) = "UInt32".
simple_type_to_value_class_name(uint64) = "UInt64".
simple_type_to_value_class_name(float32) = "Single".
simple_type_to_value_class_name(float64) = "Double".
simple_type_to_value_class_name(bool) = "Bool".
simple_type_to_value_class_name(char) = "Char".
simple_type_to_value_class_name(refany) = _ :-
	error("no value class name for refany").
simple_type_to_value_class_name(class(Name)) = VCName :-
	( Name = il_string_class_name ->
		VCName = "String"
	;
		error("unknown class name")
	).
simple_type_to_value_class_name(value_class(_)) = _ :-
	error("no value class name for value_class").
simple_type_to_value_class_name(interface(_)) = _ :-
	error("no value class name for interface").
simple_type_to_value_class_name('[]'(_, _)) = "Array".
simple_type_to_value_class_name('&'( _)) = _ :-
	error("no value class name for '&'").
simple_type_to_value_class_name('*'(_)) = _ :-
	error("no value class name for '*'").
simple_type_to_value_class_name(native_float) = _ :-
	error("no value class name for native float").
simple_type_to_value_class_name(native_int) = _ :-
	error("no value class name for native int").
simple_type_to_value_class_name(native_uint) = _ :-
	error("no value class name for native uint").

%-----------------------------------------------------------------------------%
%
% The mapping to the string type.
%

:- func il_string_equals = methodref.
il_string_equals = get_static_methodref(il_string_class_name, id("Equals"), 
	simple_type(bool), [il_string_type, il_string_type]).

:- func il_string_compare = methodref.
il_string_compare = get_static_methodref(il_string_class_name, id("Compare"), 
	simple_type(int32), [il_string_type, il_string_type]).

:- func il_string_class_name = ilds__class_name.
il_string_class_name = il_system_name(["String"]).

:- func il_string_simple_type = simple_type.
il_string_simple_type = class(il_string_class_name).

:- func il_string_type = ilds__type.
il_string_type = ilds__type([], il_string_simple_type).

%-----------------------------------------------------------------------------%
%
% The mapping to the generic type (used like MR_Box).
%

:- func il_generic_type = ilds__type.
il_generic_type = ilds__type([], il_generic_simple_type).

:- func il_generic_simple_type = simple_type.
il_generic_simple_type = class(il_generic_class_name).

il_generic_class_name = il_system_name(["Object"]).

%-----------------------------------------------------------------------------%
%
% The mapping to the array type (used like MR_Word).
%

	% il_array_type means array of System.Object.
:- func il_array_type = ilds__type.
il_array_type = ilds__type([], '[]'(il_generic_type, [])).

%-----------------------------------------------------------------------------%
%
% The class that performs conversion operations
%

:- func il_conversion_class_name = ilds__class_name.
il_conversion_class_name = ["mercury", "runtime", "Convert"].

%-----------------------------------------------------------------------------%
%
% The mapping to the exception type.
%

:- func il_exception_type = ilds__type.
il_exception_type = ilds__type([], il_exception_simple_type).

:- func il_exception_simple_type = simple_type.
il_exception_simple_type = class(il_exception_class_name).

:- func il_exception_class_name = ilds__class_name.
il_exception_class_name = ["mercury", "runtime", "Exception"].

%-----------------------------------------------------------------------------%
%
% The mapping to the environment type.
%

:- func il_envptr_type = ilds__type.
il_envptr_type = ilds__type([], il_envptr_simple_type).

:- func il_envptr_simple_type = simple_type.
il_envptr_simple_type = class(il_envptr_class_name).

:- func il_envptr_class_name = ilds__class_name.
il_envptr_class_name = ["mercury", "runtime", "Environment"].


%-----------------------------------------------------------------------------%
%
% The mapping to the commit type.
%

:- func il_commit_type = ilds__type.
il_commit_type = ilds__type([], il_commit_simple_type).

:- func il_commit_simple_type = simple_type.
il_commit_simple_type = class(il_commit_class_name).

:- func il_commit_class_name = ilds__class_name.
il_commit_class_name = ["mercury", "runtime", "Commit"].

%-----------------------------------------------------------------------------

	% qualifiy a name with "[mscorlib]System."
:- func il_system_name(ilds__class_name) = ilds__class_name.
il_system_name(Name) = 
	[il_system_assembly_name, il_system_namespace_name | Name].

:- func il_system_assembly_name = string.
il_system_assembly_name = "mscorlib".

:- func il_system_namespace_name = string.
il_system_namespace_name = "System".

%-----------------------------------------------------------------------------

	% Generate extern decls for any assembly we reference.
:- pred mlds_to_il__generate_extern_assembly(mlds__imports, list(decl)).
:- mode mlds_to_il__generate_extern_assembly(in, out) is det.

mlds_to_il__generate_extern_assembly(Imports, Decls) :-
	Gen = (pred(Import::in, Decl::out) is semidet :-
		ClassName = mlds_module_name_to_class_name(Import),
		ClassName = [TopLevel | _],
		Decl = extern_assembly(TopLevel)
	),
	list__filter_map(Gen, Imports, Decls0),
	list__sort_and_remove_dups(Decls0, Decls).

%-----------------------------------------------------------------------------

:- func make_method_defn(instr_tree) = method_defn.
make_method_defn(InstrTree) = MethodDecls :-
	Instrs = list__condense(tree__flatten(InstrTree)),
	MethodDecls = [
			% XXX should avoid hard-coding "100" for
			% the maximum static size -- not sure if we even
			% need this anymore.
		maxstack(int32(100)),
			% note that we only need .zeroinit to ensure
			% verifiability; for nonverifiable code,
			% we could omit that (it ensures that all
			% variables are initialized to zero).
		zeroinit,
		instrs(Instrs)
		].

	% This is used to initialize nondet environments.
	% When we move to high-level data it will need to be generalized
	% to intialize any class.

:- pred make_constructor(list(ilds__id), mlds__class_defn,
	ilasm__classdecl).
:- mode make_constructor(in, in, out) is det.
make_constructor(ClassName, mlds__class_defn(_,  _Imports, Inherits, 
		_Implements, Defns), ILDecl) :-
	( Inherits = [] ->
		CtorMemberName = il_generic_class_name
	;
		% XXX this needs to be calculated correctly
		% (i.e. according to the value of inherits)
		CtorMemberName = il_envptr_class_name
	),
	list__map(call_field_constructor(ClassName), Defns, 
		FieldConstrInstrsLists),
	list__condense(FieldConstrInstrsLists, FieldConstrInstrs),
	Instrs = [load_this, call_constructor(CtorMemberName)],
	MethodDecls = make_method_defn(tree__list(
		[node(Instrs),
		 node(FieldConstrInstrs),
		 instr_node(ret)
		 ])),
	ILDecl = make_constructor_classdecl(MethodDecls).


	% XXX This should really be generated at a higher level	
	% XXX For now we only call the constructor if it is an env_ptr
	%     or commit type.
:- pred call_field_constructor(list(ilds__id), mlds__defn, list(instr)).
:- mode call_field_constructor(in, in, out) is det.
call_field_constructor(ObjClassName, MLDSDefn, Instrs) :-
	MLDSDefn = mlds__defn(EntityName, _Context, _DeclFlags, Entity), 
	( 
		Entity = mlds__data(Type, _Initializer),
		EntityName = data(DataName)
	->
		ILType = mlds_type_to_ilds_type(Type),
		mangle_dataname(DataName, MangledName),
		FieldRef = make_fieldref(ILType, ObjClassName,
			MangledName),
		( 
			ILType = il_envptr_type
		->
			ClassName = il_envptr_class_name,
			Instrs = [ldarg(index(0)),
				newobj_constructor(ClassName),
				stfld(FieldRef)]
		;
			ILType = il_commit_type
		->
			ClassName = il_commit_class_name,
			Instrs = [ldarg(index(0)),
				newobj_constructor(ClassName),
				stfld(FieldRef)]
		;
			Instrs = []
		)
	; 
		Instrs = []
	).

%-----------------------------------------------------------------------------
% Some useful functions for generating IL fragments.
		
:- func load_this = instr.
load_this = ldarg(index(0)).

:- func call_class_constructor(ilds__class_name) = instr.
call_class_constructor(CtorMemberName) = 
	call(get_static_methodref(CtorMemberName, cctor, void, [])).

:- func call_constructor(ilds__class_name) = instr.
call_constructor(CtorMemberName) = 
	call(get_constructor_methoddef(CtorMemberName)).

:- func throw_unimplemented(string) = instr_tree.
throw_unimplemented(String) = 
	node([
		ldstr(String),
		newobj(get_instance_methodref(il_exception_class_name,
			ctor, void, [il_string_type])),
		throw]
	).

:- func newobj_constructor(ilds__class_name) = instr.
newobj_constructor(CtorMemberName) = 
	newobj(get_constructor_methoddef(CtorMemberName)).

:- func get_constructor_methoddef(ilds__class_name) = methodref.
get_constructor_methoddef(CtorMemberName) = 
	get_instance_methodref(CtorMemberName, ctor, void, []).

:- func get_instance_methodref(ilds__class_name, member_name, ret_type,
		list(ilds__type)) = methodref.
get_instance_methodref(ClassName, MethodName, RetType, TypeParams) = 
	methoddef(call_conv(yes, default), RetType,
		class_member_name(ClassName, MethodName), TypeParams).

:- func get_static_methodref(ilds__class_name, member_name, ret_type,
		list(ilds__type)) = methodref.
get_static_methodref(ClassName, MethodName, RetType, TypeParams) = 
	methoddef(call_conv(no, default), RetType,
		class_member_name(ClassName, MethodName), TypeParams).

:- func make_constructor_classdecl(method_defn) = classdecl.
make_constructor_classdecl(MethodDecls) = method(
	methodhead([], ctor, signature(call_conv(no, default), 
		void, []), []), MethodDecls).

:- func make_fieldref(ilds__type, ilds__class_name, ilds__id) = fieldref.
make_fieldref(ILType, ClassName, Id) = 
	fieldref(ILType, class_member_name(ClassName, id(Id))).



:- func runtime_initialization_instrs = list(instr).
runtime_initialization_instrs = [
	call(get_static_methodref(runtime_init_module_name, 
			runtime_init_method_name, void, []))
	].

:- func runtime_init_module_name = ilds__class_name.
runtime_init_module_name = ["mercury", "private_builtin__c_code"].

:- func runtime_init_method_name = ilds__member_name.
runtime_init_method_name = id("init_runtime").

%-----------------------------------------------------------------------------%
%
% Predicates for manipulating il_info.
%

:- pred il_info_init(mlds_module_name, mlds__imports, il_info).
:- mode il_info_init(in, in, out) is det.

il_info_init(ModuleName, Imports,
	il_info(ModuleName, Imports, no,
		empty, empty, [], no, no,
		map__init, empty, counter__init(1), counter__init(1), no,
		Args, MethodName, DefaultSignature)) :-
	Args = [],
	DefaultSignature = signature(call_conv(no, default), void, []),
	MethodName = id("").

	% reset the il_info for processing a new method
:- pred il_info_new_method(arguments_map, signature, member_name, 
	il_info, il_info).
:- mode il_info_new_method(in, in, in, in, out) is det.

il_info_new_method(ILArgs, ILSignature, MethodName,
	il_info(ModuleName, Imports, FileCCode,
		AllocInstrs, InitInstrs, ClassDecls, HasMain, ClassCCode,
		__Locals, _InstrTree, _LabelCounter, _BlockCounter, MethodCCode,
		_Args, _Name, _Signature),
	il_info(ModuleName, Imports, NewFileCCode,
		AllocInstrs, InitInstrs, ClassDecls, HasMain, NewClassCCode,
		map__init, empty, counter__init(1), counter__init(1), no,
		ILArgs, MethodName, ILSignature)) :-
	bool__or(ClassCCode, MethodCCode, NewClassCCode),
	bool__or(FileCCode, MethodCCode, NewFileCCode).

:- pred il_info_set_arguments(assoc_list(ilds__id, mlds__type), 
	il_info, il_info).
:- mode il_info_set_arguments(in, in, out) is det.
il_info_set_arguments(Arguments, Info0, Info) :- 
	Info = Info0 ^ arguments := Arguments.

:- pred il_info_get_arguments(arguments_map, il_info, il_info).
:- mode il_info_get_arguments(out, in, out) is det.
il_info_get_arguments(Arguments, Info0, Info0) :- 
	Arguments = Info0 ^ arguments.

:- pred il_info_get_mlds_type(ilds__id, mlds__type, il_info, il_info).
:- mode il_info_get_mlds_type(in, out, in, out) is det.
il_info_get_mlds_type(Id, Type, Info0, Info0) :- 
	( 
		map__search(Info0 ^ locals, Id, Type0)
	->
		Type = Type0
	;
		assoc_list__search(Info0 ^ arguments, Id, Type0)
	->
		Type = Type0
	;
		% XXX If it isn't a local or an argument, it can only be a
		% "global variable" -- used by RTTI.  
		Type = mlds_type_for_rtti_global
	).

	% RTTI creates global variables -- these all happen to be of
	% type mlds__native_int_type.
:- func mlds_type_for_rtti_global = mlds__type.
mlds_type_for_rtti_global = native_int_type.
		
:- pred il_info_set_modulename(mlds_module_name, il_info, il_info).
:- mode il_info_set_modulename(in, in, out) is det.
il_info_set_modulename(ModuleName, Info0, Info) :- 
	Info = Info0 ^ module_name := ModuleName.

:- pred il_info_add_locals(assoc_list(ilds__id, mlds__type), il_info, il_info).
:- mode il_info_add_locals(in, in, out) is det.
il_info_add_locals(NewLocals, Info0, Info) :- 
	Info = Info0 ^ locals := 
		map__det_insert_from_assoc_list(Info0 ^ locals, NewLocals).

:- pred il_info_remove_locals(assoc_list(ilds__id, mlds__type), 
	il_info, il_info).
:- mode il_info_remove_locals(in, in, out) is det.
il_info_remove_locals(RemoveLocals, Info0, Info) :- 
	assoc_list__keys(RemoveLocals, Keys),
	map__delete_list(Info0 ^ locals, Keys, NewLocals),
	Info = Info0 ^ locals := NewLocals.

:- pred il_info_add_classdecls(list(classdecl), il_info, il_info).
:- mode il_info_add_classdecls(in, in, out) is det.
il_info_add_classdecls(ClassDecls, Info0, Info) :- 
	Info = Info0 ^ classdecls := 
		list__append(ClassDecls, Info0 ^ classdecls).

:- pred il_info_add_instructions(list(instr), il_info, il_info).
:- mode il_info_add_instructions(in, in, out) is det.
il_info_add_instructions(NewInstrs, Info0, Info) :- 
	Info = Info0 ^ instr_tree := tree(Info0 ^ instr_tree, node(NewInstrs)).

:- pred il_info_add_init_instructions(list(instr), il_info, il_info).
:- mode il_info_add_init_instructions(in, in, out) is det.
il_info_add_init_instructions(NewInstrs, Info0, Info) :- 
	Info = Info0 ^ init_instrs := tree(Info0 ^ init_instrs,
		node(NewInstrs)).

:- pred il_info_add_alloc_instructions(list(instr), il_info, il_info).
:- mode il_info_add_alloc_instructions(in, in, out) is det.
il_info_add_alloc_instructions(NewInstrs, Info0, Info) :- 
	Info = Info0 ^ alloc_instrs := tree(Info0 ^ alloc_instrs,
		node(NewInstrs)).

:- pred il_info_get_instructions(tree(list(instr)), il_info, il_info).
:- mode il_info_get_instructions(out, in, out) is det.
il_info_get_instructions(Instrs, Info, Info) :- 
	Instrs = Info ^ instr_tree.

:- pred il_info_get_locals_list(assoc_list(ilds__id, ilds__type), 
	il_info, il_info).
:- mode il_info_get_locals_list(out, in, out) is det.
il_info_get_locals_list(Locals, Info, Info) :- 
	map__map_values((pred(_K::in, V::in, W::out) is det :- 
		W = mlds_type_to_ilds_type(V)), Info ^ locals, LocalsMap),
	map__to_assoc_list(LocalsMap, Locals).

:- pred il_info_get_module_name(mlds_module_name, il_info, il_info).
:- mode il_info_get_module_name(out, in, out) is det.
il_info_get_module_name(ModuleName, Info, Info) :- 
	ModuleName = Info ^ module_name.

:- pred il_info_get_next_block_id(blockid, il_info, il_info).
:- mode il_info_get_next_block_id(out, in, out) is det.
il_info_get_next_block_id(N, Info0, Info) :- 
	counter__allocate(N, Info0 ^ block_counter, NewCounter),
	Info = Info0 ^ block_counter := NewCounter.

:- pred il_info_get_next_label_num(int, il_info, il_info).
:- mode il_info_get_next_label_num(out, in, out) is det.
il_info_get_next_label_num(N, Info0, Info) :- 
	counter__allocate(N, Info0 ^ label_counter, NewCounter),
	Info = Info0 ^ label_counter := NewCounter.

:- pred il_info_make_next_label(ilds__label, il_info, il_info).
:- mode il_info_make_next_label(out, in, out) is det.
il_info_make_next_label(Label, Info0, Info) :- 
	il_info_get_next_label_num(LabelNnum, Info0, Info),
	string__format("l%d", [i(LabelNnum)], Label).

%-----------------------------------------------------------------------------%
%
% General utility predicates.
%

:- pred dcg_set(T::in, T::unused, T::out) is det.
dcg_set(T, _, T).

%-----------------------------------------------------------------------------%

	% Use this to make comments into trees easily.
:- func comment_node(string) = instr_tree.
comment_node(S) = node([comment(S)]).

	% Use this to make instructions into trees easily.
:- func instr_node(instr) = instr_tree.
instr_node(I) = node([I]).

	% Maybe fold T into U, and map it to V.  
	% U remains untouched if T is `no'.
:- pred maybe_map_fold(pred(T, V, U, U), maybe(T), V, V, U, U).
:- mode maybe_map_fold(pred(in, out, in, out) is det, in, in, out, in, out)
		 is det.

maybe_map_fold(_, no, V, V, U, U).
maybe_map_fold(P, yes(T), _, V, U0, U) :-
	P(T, V, U0, U).

%-----------------------------------------------------------------------------%

:- func this_file = string.
this_file = "mlds_to_il.m".

:- end_module mlds_to_il.

