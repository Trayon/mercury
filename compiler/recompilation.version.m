%-----------------------------------------------------------------------------%
% Copyright (C) 2001-2002 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% File: recompilation_version.m
% Main author: stayl
%
% Compute version numbers for program items in interface files.
%-----------------------------------------------------------------------------%
:- module recompilation__version.

:- interface.

:- import_module parse_tree__prog_data.
:- import_module parse_tree__prog_io_util, libs__timestamp.
:- import_module io, std_util, term.

	% recompilation__version__compute_version_numbers(SourceFileModTime,
	%	NewItems, MaybeOldItems, VersionNumbers).
:- pred recompilation__version__compute_version_numbers(timestamp::in,
	item_list::in, maybe(item_list)::in, version_numbers::out) is det.

:- pred recompilation__version__write_version_numbers(version_numbers::in,
	io__state::di, io__state::uo) is det.

:- pred recompilation__version__parse_version_numbers(term::in,
	maybe1(version_numbers)::out) is det.

	% The version number for the format of the version numbers
	% written to the interface files.
:- func version_numbers_version_number = int.

%-----------------------------------------------------------------------------%
:- implementation.

:- import_module parse_tree__mercury_to_mercury, check_hlds__mode_util.
:- import_module parse_tree__prog_io, parse_tree__prog_util.
:- import_module check_hlds__type_util.
:- import_module hlds__hlds_out, (parse_tree__inst).

:- import_module assoc_list, bool, list, map, require, string, varset.


recompilation__version__compute_version_numbers(SourceFileTime, Items,
		MaybeOldItems,
		version_numbers(ItemVersionNumbers, InstanceVersionNumbers)) :-
	recompilation__version__gather_items(Items,
		GatheredItems, InstanceItems),
	(
		MaybeOldItems = yes(OldItems0),
		OldItems0 = [VersionNumberItem | OldItems],
		VersionNumberItem = module_defn(_,
			version_numbers(_, OldVersionNumbers)) - _
	->
		OldVersionNumbers = version_numbers(OldItemVersionNumbers,
					OldInstanceVersionNumbers),
		recompilation__version__gather_items(OldItems, GatheredOldItems,
			OldInstanceItems)
	;
		% There were no old version numbers, so every item
		% gets the same timestamp as the source module.
		OldItemVersionNumbers = init_item_id_set(map__init),
		GatheredOldItems = init_item_id_set(map__init),
		map__init(OldInstanceItems),
		map__init(OldInstanceVersionNumbers)
	),
	
	recompilation__version__compute_item_version_numbers(SourceFileTime,
		GatheredItems, GatheredOldItems, OldItemVersionNumbers,
		ItemVersionNumbers),
		
	recompilation__version__compute_instance_version_numbers(SourceFileTime,
		InstanceItems, OldInstanceItems, OldInstanceVersionNumbers,
		InstanceVersionNumbers).

:- pred recompilation__version__compute_item_version_numbers(timestamp::in,
	gathered_items::in, gathered_items::in,
	item_version_numbers::in, item_version_numbers::out) is det.

recompilation__version__compute_item_version_numbers(SourceFileTime,
		GatheredItems, GatheredOldItems,
		OldVersionNumbers, VersionNumbers) :-
	VersionNumbers = map_ids(
	    (func(ItemType, Items0) =
		map__map_values(
		    (func(NameArity, Items) = VersionNumber :-
			OldIds = extract_ids(GatheredOldItems, ItemType),
			(
			    map__search(OldIds, NameArity, OldItems),
			    items_are_unchanged(OldItems, Items),
		    	    map__search(
			    	extract_ids(OldVersionNumbers, ItemType),
			    	NameArity, OldVersionNumber)
			->
			    VersionNumber = OldVersionNumber
			;
			    VersionNumber = SourceFileTime
			)
		    ),
		    Items0
		)
	    ),
	    GatheredItems,
	    map__init
	).

:- pred recompilation__version__compute_instance_version_numbers(timestamp::in,
	instance_item_map::in, instance_item_map::in, 
	instance_version_numbers::in, instance_version_numbers::out) is det.

recompilation__version__compute_instance_version_numbers(SourceFileTime,
		InstanceItems, OldInstanceItems,
		OldInstanceVersionNumbers, InstanceVersionNumbers) :-
	InstanceVersionNumbers =
	    map__map_values(
		(func(ClassId, Items) = VersionNumber :-
		    (
		    	map__search(OldInstanceItems, ClassId, OldItems),
			items_are_unchanged(OldItems, Items),
		    	map__search(OldInstanceVersionNumbers, ClassId,
				OldVersionNumber)
		    ->
			VersionNumber = OldVersionNumber
		    ;
			VersionNumber = SourceFileTime
		    )
		),
		InstanceItems
	    ).

:- pred recompilation__version__gather_items(item_list::in,
		gathered_items::out, instance_item_map::out) is det.

recompilation__version__gather_items(Items, GatheredItems, Instances) :-
	list__reverse(Items, RevItems),
	Info0 = gathered_item_info(init_item_id_set(map__init),
			[], [], map__init),
	list__foldl(recompilation__version__gather_items_2, RevItems,
			Info0, Info1),

	%
	% Items which could appear in _OtherItems (those which aren't
	% gathered into the list for another type of item) can't appear
	% in the interface section. Those other items (e.g. assertions)
	% will need to be handled here when smart recompilation is made to
	% work with `--intermodule-optimization'.
	%
	Info1 = gathered_item_info(GatheredItems1, PragmaItems,
			_OtherItems, Instances),
	list__reverse(PragmaItems, RevPragmaItems),
	list__foldl(distribute_pragma_items, RevPragmaItems,
		GatheredItems1, GatheredItems).

:- pred distribute_pragma_items(
		pair(maybe_pred_or_func_id, item_and_context)::in,
		gathered_items::in, gathered_items::out) is det.

distribute_pragma_items(ItemId - ItemAndContext,
		GatheredItems0, GatheredItems) :-
	ItemId = MaybePredOrFunc - SymName / Arity,
	ItemAndContext = Item - ItemContext,

	% For predicates defined using `with_type` annotations
	% we don't know the actual arity, so always we need to add
	% entries for pragmas, even if the pragma doesn't match any
	% recorded predicate. For pragmas which don't include enough
	% information to work out whether they apply to a predicate
	% or a function this will result in an extra entry in the
	% version numbers. Pragmas in the interface aren't common
	% so this won't be too much of a problem.
	AddIfNotExisting = yes,
	(
		MaybePredOrFunc = yes(PredOrFunc),
		ItemType = pred_or_func_to_item_type(PredOrFunc),
		recompilation__version__add_gathered_item(Item,
			item_id(ItemType, SymName - Arity),
			ItemContext, AddIfNotExisting,
			GatheredItems0, GatheredItems2)
	;
		MaybePredOrFunc = no,
		recompilation__version__add_gathered_item(Item,
			item_id(predicate, SymName - Arity),
			ItemContext, AddIfNotExisting,
			GatheredItems0, GatheredItems1),
		recompilation__version__add_gathered_item(Item,
			item_id(function, SymName - Arity),
			ItemContext, AddIfNotExisting,
			GatheredItems1, GatheredItems2)
	),

	% Pragmas can apply to typeclass methods.
	map__map_values(
	    (pred(_::in, ClassItems0::in, ClassItems::out) is det :-
		( 
			% Does this pragma match any of the methods
			% of this class.
			list__member(ClassItem, ClassItems0),
			ClassItem = typeclass(_, _, _, Interface, _) - _,
			Interface = concrete(Methods),
			list__member(Method, Methods),
			Method = pred_or_func(_, _, _, MethodPredOrFunc,
				SymName, TypesAndModes, WithType, _,
				_, _, _, _, _),
			( MaybePredOrFunc = yes(MethodPredOrFunc)
			; MaybePredOrFunc = no
			),
			(
				WithType = no,
				adjust_func_arity(MethodPredOrFunc,
					Arity, list__length(TypesAndModes))
			;
				% We don't know the actual arity, so just
				% match on the name and pred_or_func.
				WithType = yes(_)
			)
		->
			% XXX O(N^2), but shouldn't happen too often.
			ClassItems = ClassItems0 ++ [ItemAndContext]
		;
			ClassItems = ClassItems0
		)
	    ), extract_ids(GatheredItems2, typeclass), GatheredTypeClasses),
	GatheredItems = update_ids(GatheredItems2, typeclass,
				GatheredTypeClasses).

:- type gathered_item_info
	--->	gathered_item_info(
			gathered_items :: gathered_items,
			pragma_items :: assoc_list(maybe_pred_or_func_id, 
						item_and_context),
			other_items :: item_list,
			instances :: instance_item_map
		).

:- type instance_item_map == map(item_name, item_list).

	% The constructors set should always be empty.
:- type gathered_items == item_id_set(gathered_item_map).
:- type gathered_item_map == map(pair(string, arity), item_list).

:- pred recompilation__version__gather_items_2(item_and_context::in,
		gathered_item_info::in, gathered_item_info::out) is det.

recompilation__version__gather_items_2(ItemAndContext) -->
	{ ItemAndContext = Item - ItemContext },
	(
		{ Item = type_defn(VarSet, Name, Args, Body, Cond) }
	->
		(
			{ Body = abstract_type },
			{ NameItem = Item },
			% The body of an abstract type can be recorded
			% as used when generating a call to the automatically
			% generated unification procedure.
			{ BodyItem = Item }
		;
			{ Body = du_type(_, _) },
			{ NameItem = type_defn(VarSet, Name, Args,
				abstract_type, Cond) },
			{ BodyItem = Item }	
		;
			{ Body = eqv_type(_) },
			% When we use an equivalence type we
			% always use the body.
			{ NameItem = Item },
			{ BodyItem = Item }
		),
		{ TypeCtor = Name - list__length(Args) },
		GatheredItems0 =^ gathered_items,
		{ recompilation__version__add_gathered_item(NameItem,
			item_id((type), TypeCtor), ItemContext,
			yes, GatheredItems0, GatheredItems1) },
		{ recompilation__version__add_gathered_item(BodyItem,
			item_id(type_body, TypeCtor), ItemContext,
			yes, GatheredItems1, GatheredItems) },
		^ gathered_items := GatheredItems
	;
		{ Item = instance(_, ClassName, ClassArgs, _, _, _) }
	->
		Instances0 =^ instances,
		{ ClassArity = list__length(ClassArgs) },
		(
			{ map__search(Instances0, ClassName - ClassArity,
				InstanceItems0) }
		->
			{ InstanceItems = InstanceItems0 }
		;
			{ InstanceItems = [] }
		),
		{ map__set(Instances0, ClassName - ClassArity,
			[Item - ItemContext | InstanceItems], Instances) },
		^ instances := Instances
	;
		% For predicates or functions defined using `with_inst`
		% annotations the pred_or_func and arity here won't be
		% correct, but equiv_type.m will record the dependency
		% on the version number with the `incorrect' pred_or_func
		% and arity, so this will work.
		{ Item = pred_or_func_mode(_, MaybePredOrFunc,
			SymName, Modes, WithInst, _, _) },
		{ MaybePredOrFunc = no },
		{ WithInst = yes(_) }
	->
		GatheredItems0 =^ gathered_items,
		{ ItemName = SymName - list__length(Modes) },
		{ recompilation__version__add_gathered_item(Item,
			item_id(predicate, ItemName), ItemContext,
			yes, GatheredItems0, GatheredItems1) },
		{ recompilation__version__add_gathered_item(Item,
			item_id(function, ItemName), ItemContext,
			yes, GatheredItems1, GatheredItems) },
		^ gathered_items := GatheredItems
	;

		{ item_to_item_id(Item, ItemId) }
	->
		GatheredItems0 =^ gathered_items,
		{ recompilation__version__add_gathered_item(Item, ItemId,
			ItemContext, yes, GatheredItems0, GatheredItems) },
		^ gathered_items := GatheredItems
	;
		{ Item = pragma(PragmaType) },
		{ is_pred_pragma(PragmaType, yes(PredOrFuncId)) }
	->
		PragmaItems =^ pragma_items,
		^ pragma_items := [PredOrFuncId - ItemAndContext | PragmaItems]
	;
		OtherItems =^ other_items,
		^ other_items := [ItemAndContext | OtherItems]
	).

:- pred recompilation__version__add_gathered_item(item::in, item_id::in,
		prog_context::in, bool::in, gathered_items::in,
		gathered_items::out) is det.

recompilation__version__add_gathered_item(Item, ItemId, ItemContext,
		AddIfNotExisting, GatheredItems0, GatheredItems) :-
	ItemId = item_id(ItemType, Id),
	Id = SymName - Arity,
	unqualify_name(SymName, Name),
	IdMap0 = extract_ids(GatheredItems0, ItemType),
	NameArity = Name - Arity,
	( map__search(IdMap0, NameArity, MatchingItems0) ->
		MatchingItems = MatchingItems0
	;
		MatchingItems = []
	),
	( MatchingItems = [], AddIfNotExisting = no ->
		GatheredItems = GatheredItems0
	;
		recompilation__version__add_gathered_item_2(Item, ItemType,
			NameArity, ItemContext, MatchingItems,
			GatheredItems0, GatheredItems)
	).

:- pred recompilation__version__add_gathered_item_2(item::in, item_type::in,
		pair(string, arity)::in, prog_context::in, item_list::in,
		gathered_items::in, gathered_items::out) is det.

recompilation__version__add_gathered_item_2(Item, ItemType, NameArity,
		ItemContext, MatchingItems0, GatheredItems0, GatheredItems) :-

	% mercury_to_mercury.m splits combined pred and mode
	% declarations. That needs to be done here as well
	% the item list read from the interface file will match
	% the item list generated here.
	(
		Item = pred_or_func(TVarSet, InstVarSet, ExistQVars,
			PredOrFunc, PredName, TypesAndModes, WithType,
			WithInst, Det, Cond, Purity, ClassContext),
		split_types_and_modes(TypesAndModes, Types, MaybeModes),
		MaybeModes = yes(Modes),
		( Modes \= []
		; WithInst = yes(_)
		)
	->
		TypesWithoutModes = list__map(
			(func(Type) = type_only(Type)), Types),
		varset__init(EmptyInstVarSet),
		PredOrFuncItem = pred_or_func(TVarSet, EmptyInstVarSet,
			ExistQVars, PredOrFunc, PredName, TypesWithoutModes,
			WithType, no, no, Cond, Purity, ClassContext),
		(
			WithInst = yes(_),
			% MaybePredOrFunc needs to be `no' here because when
			% the item is read from the interface file we won't
			% know whether it is a predicate or a function mode.
			MaybePredOrFunc = no
		;
			WithInst = no,
			MaybePredOrFunc = yes(PredOrFunc)
		),
		PredOrFuncModeItem = pred_or_func_mode(InstVarSet,
			MaybePredOrFunc, PredName, Modes, WithInst, Det, Cond),
		MatchingItems =
			[PredOrFuncItem - ItemContext,
			PredOrFuncModeItem - ItemContext
			| MatchingItems0]
	;
		Item = typeclass(Constraints, ClassName, ClassArgs,
			ClassInterface0, ClassTVarSet),
		ClassInterface0 = concrete(Methods0)
	->
		MethodsList = list__map(
			split_class_method_types_and_modes, Methods0),
		list__condense(MethodsList, Methods),
		TypeclassItem = typeclass(Constraints, ClassName, ClassArgs,
			concrete(Methods), ClassTVarSet),
		MatchingItems = [TypeclassItem - ItemContext | MatchingItems0]
	;
		MatchingItems = [Item - ItemContext| MatchingItems0]
	),

	IdMap0 = extract_ids(GatheredItems0, ItemType),
	map__set(IdMap0, NameArity, MatchingItems, IdMap),
	GatheredItems = update_ids(GatheredItems0, ItemType, IdMap).

:- func split_class_method_types_and_modes(class_method) = list(class_method).

split_class_method_types_and_modes(Method0) = Items :-
	% Always strip the context from the item -- this is needed
	% so the items can be easily tested for equality.
	Method0 = pred_or_func(TVarSet, InstVarSet, ExistQVars,
		PredOrFunc, SymName, TypesAndModes, WithType, WithInst,
		MaybeDet, Cond, Purity, ClassContext, _),
	(
		split_types_and_modes(TypesAndModes, Types, MaybeModes),
		MaybeModes = yes(Modes),
		( Modes \= []
		; WithInst = yes(_)
		)
	->
		TypesWithoutModes = list__map(
			(func(Type) = type_only(Type)), Types),
		(
			WithInst = yes(_),
			% MaybePredOrFunc needs to be `no' here because when
			% the item is read from the interface file we won't
			% know whether it is a predicate or a function mode.
			MaybePredOrFunc = no
		;
			WithInst = no,
			MaybePredOrFunc = yes(PredOrFunc)
		),
		PredOrFuncModeItem = pred_or_func_mode(InstVarSet,
			MaybePredOrFunc, SymName, Modes, WithInst,
			MaybeDet, Cond, term__context_init),
		PredOrFuncModeItems = [PredOrFuncModeItem]
	;
		TypesWithoutModes = TypesAndModes,
		PredOrFuncModeItems = []
	),
	varset__init(EmptyInstVarSet),
	PredOrFuncItem = pred_or_func(TVarSet, EmptyInstVarSet,
		ExistQVars, PredOrFunc, SymName,
		TypesWithoutModes, WithType, no, no, Cond, Purity,
		ClassContext, term__context_init),
	Items = [PredOrFuncItem | PredOrFuncModeItems].
split_class_method_types_and_modes(Method0) = [Method] :-
	% Always strip the context from the item -- this is needed
	% so the items can be easily tested for equality.
	Method0 = pred_or_func_mode(A, B, C, D, E, F, G, _),
	Method = pred_or_func_mode(A, B, C, D, E, F, G, term__context_init).

:- pred item_to_item_id(item::in, item_id::out) is semidet.

item_to_item_id(Item, ItemId) :-
	item_to_item_id_2(Item, yes(ItemId)).

:- pred item_to_item_id_2(item::in, maybe(item_id)::out) is det.

item_to_item_id_2(clause(_, _, _, _, _), no).
item_to_item_id_2(type_defn(_, Name, Params, _, _),
		yes(item_id((type), Name - Arity))) :-
	list__length(Params, Arity).		
item_to_item_id_2(inst_defn(_, Name, Params, _, _),
		yes(item_id((inst), Name - Arity))) :-	
	list__length(Params, Arity).
item_to_item_id_2(mode_defn(_, Name, Params, _, _),
		yes(item_id((mode), Name - Arity))) :-	
	list__length(Params, Arity).
item_to_item_id_2(module_defn(_, _), no).
item_to_item_id_2(Item, yes(item_id(ItemType, SymName - Arity))) :-
	Item = pred_or_func(_, _, _, PredOrFunc, SymName,
			TypesAndModes, WithType, _, _, _, _, _),
	% For predicates or functions defined using `with_type` annotations
	% the arity here won't be correct, but equiv_type.m will record
	% the dependency on the version number with the `incorrect' arity,
	% so this will work.
	(
		WithType = no,
		adjust_func_arity(PredOrFunc, Arity,
			list__length(TypesAndModes))
	;
		WithType = yes(_),
		Arity = list__length(TypesAndModes)
	),
	ItemType = pred_or_func_to_item_type(PredOrFunc).

item_to_item_id_2(Item, ItemId) :-
	Item = pred_or_func_mode(_, MaybePredOrFunc, SymName, Modes,
			_, _, _),
	( MaybePredOrFunc = yes(PredOrFunc) ->
		adjust_func_arity(PredOrFunc, Arity, list__length(Modes)),
		ItemType = pred_or_func_to_item_type(PredOrFunc),
		ItemId = yes(item_id(ItemType, SymName - Arity))
	;
		% We need to handle these separately because a `:- mode'
		% declaration with a `with_inst` annotation could be
		% for a predicate or a funciton.
		ItemId = no
	).

	% We need to handle these separately because some pragmas
	% may affect a predicate and a function.
item_to_item_id_2(pragma(_), no).
item_to_item_id_2(promise(_, _, _, _), no).
item_to_item_id_2(Item, yes(item_id((typeclass), ClassName - ClassArity))) :-
	Item = typeclass(_, ClassName, ClassVars, _, _),
	list__length(ClassVars, ClassArity).	

	% Instances are handled separately (unlike other items, the module
	% qualifier on an instance declaration is the module containing
	% the class, not the module containing the instance).
item_to_item_id_2(instance(_, _, _, _, _, _), no).
item_to_item_id_2(nothing(_), no).

:- type maybe_pred_or_func_id ==
		pair(maybe(pred_or_func), sym_name_and_arity).

:- pred is_pred_pragma(pragma_type::in,
		maybe(maybe_pred_or_func_id)::out) is det.

is_pred_pragma(foreign_decl(_, _), no).
is_pred_pragma(foreign_import_module(_, _), no).
is_pred_pragma(foreign_code(_, _), no).
is_pred_pragma(foreign_proc(_, Name, PredOrFunc, Args, _, _),
		yes(yes(PredOrFunc) - Name / Arity)) :-
	adjust_func_arity(PredOrFunc, Arity, list__length(Args)).
is_pred_pragma(foreign_type(_, _, _, _), no).
is_pred_pragma(type_spec(Name, _, Arity, MaybePredOrFunc, _, _, _, _),
		yes(MaybePredOrFunc - Name / Arity)).
is_pred_pragma(inline(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(no_inline(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(obsolete(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(export(Name, PredOrFunc, Modes, _), 
		yes(yes(PredOrFunc) - Name / Arity)) :-
	adjust_func_arity(PredOrFunc, Arity, list__length(Modes)).	
	% Pragma import declarations are never used
	% directly by Mercury code.
is_pred_pragma(import(_, _, _, _, _), no).
is_pred_pragma(source_file(_), no).
is_pred_pragma(unused_args(PredOrFunc, Name, Arity, _, _),
		yes(yes(PredOrFunc) - Name / Arity)).
is_pred_pragma(fact_table(Name, Arity, _), yes(no - Name / Arity)).
is_pred_pragma(aditi(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(base_relation(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(aditi_index(Name, Arity, _), yes(no - Name / Arity)).
is_pred_pragma(naive(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(psn(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(aditi_memo(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(aditi_no_memo(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(supp_magic(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(context(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(owner(Name, Arity, _), yes(no - Name / Arity)).
is_pred_pragma(tabled(_, Name, Arity, MaybePredOrFunc, _),
		yes(MaybePredOrFunc - Name / Arity)).
is_pred_pragma(promise_pure(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(promise_semipure(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(termination_info(PredOrFunc, Name, Modes, _, _),
		yes(yes(PredOrFunc) - Name / Arity)) :-
	adjust_func_arity(PredOrFunc, Arity, list__length(Modes)).	
is_pred_pragma(terminates(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(does_not_terminate(Name, Arity), yes(no - Name / Arity)).
is_pred_pragma(check_termination(Name, Arity), yes(no - Name / Arity)).

	% XXX This is a bit brittle (need to be careful with term__contexts).
	% For example, it won't work for clauses.
	% It will never succeed when it shouldn't, so it will never
	% cause a necessary recompilation to be missed.
:- pred items_are_unchanged(item_list::in, item_list::in) is semidet.

items_are_unchanged([], []).
items_are_unchanged([Item1 - _ | Items1], [Item2 - _ | Items2]) :-
	yes = item_is_unchanged(Item1, Item2),
	items_are_unchanged(Items1, Items2).

	% In most places here, we don't need to compare the varsets.
	% What matters is that the variable numbers in the arguments
	% and body are the same, the names are usually irrelevant.
	%
	% The only places where the names of variables affect the
	% compilation of the program are in explicit type qualifications
	% and `:- pragma type_spec' declarations. Explicit type
	% qualifications do not need to be considered here. This module
	% only deals with items in interface files (we don't yet write type
	% qualifications to `.opt' files). Variables in type qualifications
	% are only matched with the head type variables of the predicate
	% by make_hlds.m. For `:- pragma type_spec' declarations to work
	% we need to consider a predicate or function declaration to be
	% changed if the names of any of the type variables are changed.
	%
	% It's important not to compare the varsets for type and instance
	% declarations because the declarations we get here may be abstract
	% declarations produced from concrete declarations for use in an
	% interface file. The varsets may contain variables from the
	% discarded bodies which will not be present in the items read
	% in from the interface files for comparison. 
	%
	% This code assumes that the variables in the head of a
	% type or instance declaration are added to the varset before
	% those from the body, so that the variable numbers in the head of
	% the declaration match those from an abstract declaration read
	% from an interface file.
:- func item_is_unchanged(item, item) = bool.

item_is_unchanged(type_defn(_VarSet, Name, Args, Defn, Cond), Item2) =
		( Item2 = type_defn(_, Name, Args, Defn, Cond) -> yes ; no ).
item_is_unchanged(mode_defn(_VarSet, Name, Args, Defn, Cond), Item2) =
		( Item2 = mode_defn(_, Name, Args, Defn, Cond) -> yes ; no ).
item_is_unchanged(inst_defn(_VarSet, Name, Args, Defn, Cond), Item2) =
		( Item2 = inst_defn(_, Name, Args, Defn, Cond) -> yes ; no ).
item_is_unchanged(module_defn(_VarSet, Defn), Item2) =
		( Item2 = module_defn(_, Defn) -> yes ; no ).
item_is_unchanged(instance(Constraints, Name, Types, Body, _VarSet, Module),
		Item2) =
	( Item2 = instance(Constraints, Name, Types, Body, _, Module) ->
		yes
	;
		no
	).

	% XXX Need to compare the goals properly in clauses and assertions.
	% That's not necessary at the moment because smart recompilation
	% doesn't work with inter-module optimization yet.
item_is_unchanged(clause(_VarSet, PorF, SymName, Args, Goal), Item2) =
		( Item2 = clause(_, PorF, SymName, Args, Goal) -> yes ; no ).
item_is_unchanged(promise(PromiseType, Goal, _, UnivVars), Item2) =
		( Item2 = promise(PromiseType, Goal, _, UnivVars) -> yes ; no ).

	% We do need to compare the variable names in `:- pragma type_spec'
	% declarations because the names of the variables are used
	% to find the corresponding variables in the predicate or
	% function type declaration.
item_is_unchanged(pragma(PragmaType1), Item2) = Result :-
    ( Item2 = pragma(PragmaType2) ->
	(
	    PragmaType1 = type_spec(Name, SpecName, Arity, MaybePredOrFunc,
	    			MaybeModes, TypeSubst1, TVarSet1, _),
	    PragmaType2 = type_spec(Name, SpecName, Arity, MaybePredOrFunc,
	    			MaybeModes, TypeSubst2, TVarSet2, _)
	->
	    assoc_list__keys_and_values(TypeSubst1, TVars1, Types1),
	    var_list_to_term_list(TVars1, TVarTypes1),
	    assoc_list__keys_and_values(TypeSubst2, TVars2, Types2),
	    var_list_to_term_list(TVars2, TVarTypes2),
	    (
	    	type_list_is_unchanged(TVarSet1, TVarTypes1 ++ Types1,
			TVarSet2, TVarTypes2 ++ Types2, _, _, _)
	    ->
	    	Result = yes
	    ;
	    	Result = no
	    )
	;
	    Result = ( PragmaType1 = PragmaType2 -> yes ; no )
	)
    ;
	Result = no
    ).
item_is_unchanged(nothing(A), Item2) =
		( Item2 = nothing(A) -> yes ; no ).

item_is_unchanged(Item1, Item2) = Result :-
	Item1 = pred_or_func(TVarSet1, _, ExistQVars1, PredOrFunc,
		Name, TypesAndModes1, WithType1, _,
		Det1, Cond, Purity, Constraints1),
	(
		Item2 = pred_or_func(TVarSet2, _, ExistQVars2,
			PredOrFunc, Name, TypesAndModes2, WithType2,
			_, Det2, Cond, Purity,
			Constraints2),

		% For predicates, ignore the determinism -- the modes and
		% determinism should have been split into a separate
		% declaration. This case can only happen if this was
		% not a combined predicate and mode declaration
		% (XXX We should warn about this somewhere). 
		% For functions a determinism declaration but no modes
		% implies the default modes. The default modes are
		% added later by make_hlds.m, so they won't have been
		% split into a separate declaration here.
		(
			PredOrFunc = function,
			Det1 = Det2
		;
			PredOrFunc = predicate
		),

		pred_or_func_type_is_unchanged(TVarSet1, ExistQVars1,
			TypesAndModes1, WithType1, Constraints1, TVarSet2,
			ExistQVars2, TypesAndModes2, WithType2, Constraints2)
	->
		Result = yes
	;
		Result = no
	).

item_is_unchanged(Item1, Item2) = Result :-
	Item1 = pred_or_func_mode(InstVarSet1, PredOrFunc, Name, Modes1,
			WithInst1, Det, Cond),
	(
		Item2 = pred_or_func_mode(InstVarSet2, PredOrFunc,
			Name, Modes2, WithInst2, Det, Cond),
		pred_or_func_mode_is_unchanged(InstVarSet1, Modes1, WithInst1,
			InstVarSet2, Modes2, WithInst2)
	->
		Result = yes
	;
		Result = no
	).


item_is_unchanged(Item1, Item2) = Result :-
	Item1 = typeclass(Constraints, Name, Vars, Interface1, _VarSet),
	(
		Item2 = typeclass(Constraints, Name, Vars, Interface2, _),
		class_interface_is_unchanged(Interface1, Interface2)
	->
		Result = yes
	;
		Result = no
	).

	%
	% Apply a substitution to the existq_tvars, types_and_modes, and
	% class_constraints so that the type variables from both declarations
	% being checked are contained in the same tvarset, then check that
	% they are identical.
	%
	% We can't just assume that the varsets will be identical for
	% identical declarations because mercury_to_mercury.m splits
	% combined type and mode declarations into separate declarations.
	% When they are read back in the variable numbers will be different
	% because parser stores the type and inst variables for a combined
	% declaration in a single varset (it doesn't know which are which).
	%
:- pred pred_or_func_type_is_unchanged(tvarset::in, existq_tvars::in,
	list(type_and_mode)::in, maybe(type)::in, class_constraints::in,
	tvarset::in, existq_tvars::in, list(type_and_mode)::in,
	maybe(type)::in, class_constraints::in) is semidet. 

pred_or_func_type_is_unchanged(TVarSet1, ExistQVars1, TypesAndModes1,
		MaybeWithType1, Constraints1, TVarSet2, ExistQVars2,
		TypesAndModes2, MaybeWithType2, Constraints2) :-

	GetArgTypes =
		(func(TypeAndMode0) = Type :-
			(
				TypeAndMode0 = type_only(Type)
			;
				% This should have been split out into a
				% separate mode declaration by gather_items.
				TypeAndMode0 = type_and_mode(_, _),
				error(
			"pred_or_func_type_matches: type_and_mode")
			)
		),
	Types1 = list__map(GetArgTypes, TypesAndModes1),
	Types2 = list__map(GetArgTypes, TypesAndModes2),
	(
		MaybeWithType1 = yes(WithType1),
		MaybeWithType2 = yes(WithType2),
		AllTypes1 = [WithType1 | Types1],
		AllTypes2 = [WithType2 | Types2]
	;
		MaybeWithType1 = no,
		MaybeWithType2 = no,
		AllTypes1 = Types1,
		AllTypes2 = Types2
	),

	type_list_is_unchanged(TVarSet1, AllTypes1, TVarSet2, AllTypes2,
		_TVarSet, RenameSubst, Types2ToTypes1Subst),

	%
	% Check that the existentially quantified variables are equivalent.
	%
	SubstExistQVars2 =
		term_list_to_var_list(
			term__apply_rec_substitution_to_list(
				apply_substitution_to_list(
					var_list_to_term_list(ExistQVars2),
					RenameSubst),
				Types2ToTypes1Subst)),
	ExistQVars1 = SubstExistQVars2,

	%
	% Check that the class constraints are identical.
	%
	apply_subst_to_constraints(RenameSubst,
		Constraints2, RenamedConstraints2),
	apply_rec_subst_to_constraints(Types2ToTypes1Subst,
		RenamedConstraints2, SubstConstraints2),
	Constraints1 = SubstConstraints2.

:- pred type_list_is_unchanged(tvarset::in, list(type)::in,
		tvarset::in, list(type)::in, tvarset::out,
		tsubst::out, tsubst::out) is semidet.

type_list_is_unchanged(TVarSet1, Types1, TVarSet2, Types2,
		TVarSet, RenameSubst, Types2ToTypes1Subst) :-
	varset__merge_subst(TVarSet1, TVarSet2, TVarSet, RenameSubst),
	term__apply_substitution_to_list(Types2, RenameSubst, SubstTypes2),

	%
	% Check that the types are equivalent
	%
	type_list_subsumes(SubstTypes2, Types1, Types2ToTypes1Subst),
	type_list_subsumes(Types1, SubstTypes2, _),

	%
	% Check that the corresponding variables have the same names.
	% This is necessary because `:- pragma type_spec' declarations
	% depend on the names of the variables, so for example if two
	% variable names are swapped, the same `:- pragma type_spec'
	% declaration will cause a different specialized version to be
	% created.
	%
	( all [VarInItem1, VarInItem2]
	    (
		map__member(Types2ToTypes1Subst, VarInItem2, SubstTerm),
		(
			SubstTerm = term__variable(VarInItem1)
		;
			% The reverse subsumption test above should
			% ensure that the substitutions are all var->var.
			SubstTerm = term__functor(_, _, _),
			error("pred_or_func_type_matches: invalid subst")
		)
	    )
	=>
	    (
		varset__lookup_name(TVarSet, VarInItem1, VarName1),
		varset__lookup_name(TVarSet, VarInItem2, VarName2),
		(
			VarName1 = VarName2
	    	;
			%
			% Variables written to interface files are always
			% named, even if the variable in the source code
			% was not, so we can't just use varset__search_name
			% to check whether the variables are named.
			%
			VarIsNotNamed =
				(pred(VarName::in) is semidet :-
					string__append("V_", VarNum, VarName),
					string__to_int(VarNum, _)
				),
			VarIsNotNamed(VarName1),
			VarIsNotNamed(VarName2)
		)
	    )
	).

:- pred pred_or_func_mode_is_unchanged(inst_varset::in, list(mode)::in,
		maybe(inst)::in, inst_varset::in, list(mode)::in,
		maybe(inst)::in) is semidet.

pred_or_func_mode_is_unchanged(InstVarSet1, Modes1, MaybeWithInst1,
		InstVarSet2, Modes2, MaybeWithInst2) :-
	varset__coerce(InstVarSet1, VarSet1),
	varset__coerce(InstVarSet2, VarSet2),

	%
	% Apply the substitution to the modes so that the inst variables
	% from both declarations being checked are contained in the same
	% inst_varset, then check that they are identical.
	%
	varset__merge_subst(VarSet1, VarSet2, _, InstSubst),

	%
	% Treat modes as types here to use type_list_subsumes, which
	% does just what we want here. (XXX shouldn't type_list_subsumes
	% be in term.m and apply to generic terms anyway?).
	%
	ModeToTerm = (func(Mode) = term__coerce(mode_to_term(Mode))),
	ModeTerms1 = list__map(ModeToTerm, Modes1),
	ModeTerms2 = list__map(ModeToTerm, Modes2),
	(
		MaybeWithInst1 = yes(Inst1),
		MaybeWithInst2 = yes(Inst2),
		WithInstTerm1 = term__coerce(mode_to_term(free -> Inst1)),
		WithInstTerm2 = term__coerce(mode_to_term(free -> Inst2)),
		AllModeTerms1 = [WithInstTerm1 | ModeTerms1],
		AllModeTerms2 = [WithInstTerm2 | ModeTerms2]
	;
		MaybeWithInst1 = no,
		MaybeWithInst2 = no,
		AllModeTerms1 = ModeTerms1,
		AllModeTerms2 = ModeTerms2
	),	

	term__apply_substitution_to_list(AllModeTerms2,
		InstSubst, SubstAllModeTerms2),
	type_list_subsumes(AllModeTerms1, SubstAllModeTerms2, _),
	type_list_subsumes(SubstAllModeTerms2, AllModeTerms1, _).

	%
	% Combined typeclass method type and mode declarations are split
	% as for ordinary predicate declarations, so the varsets won't
	% necessarily match up if a typeclass declration is read back
	% from an interface file.
	%
:- pred class_interface_is_unchanged(class_interface::in,
		class_interface::in) is semidet.

class_interface_is_unchanged(abstract, abstract).
class_interface_is_unchanged(concrete(Methods1), concrete(Methods2)) :-
	class_methods_are_unchanged(Methods1, Methods2).

:- pred class_methods_are_unchanged(list(class_method)::in,
		list(class_method)::in) is semidet.

class_methods_are_unchanged([], []).
class_methods_are_unchanged([Method1 | Methods1], [Method2 | Methods2]) :-
	(
		Method1 = pred_or_func(TVarSet1, _, ExistQVars1, PredOrFunc,
			Name, TypesAndModes1, WithType1, _,
			Detism, Cond, Purity, Constraints1, _),
		Method2 = pred_or_func(TVarSet2, _, ExistQVars2, PredOrFunc,
			Name, TypesAndModes2, WithType2, _,
			Detism, Cond, Purity, Constraints2, _),
		pred_or_func_type_is_unchanged(TVarSet1, ExistQVars1,
			TypesAndModes1, WithType1, Constraints1,
			TVarSet2, ExistQVars2, TypesAndModes2, WithType2,
			Constraints2)
	;
		Method1 = pred_or_func_mode(InstVarSet1, PredOrFunc, Name,
			Modes1, WithInst1, Det, Cond, _),
		Method2 = pred_or_func_mode(InstVarSet2, PredOrFunc, Name,
			Modes2, WithInst2, Det, Cond, _),
		pred_or_func_mode_is_unchanged(InstVarSet1, Modes1, WithInst1,
			InstVarSet2, Modes2, WithInst2)
	),
	class_methods_are_unchanged(Methods1, Methods2).

%-----------------------------------------------------------------------------%

recompilation__version__write_version_numbers(
		version_numbers(VersionNumbers, InstanceVersionNumbers)) -->
	{ VersionNumbersList = list__filter_map(
		(func(ItemType) = (ItemType - ItemVersions) is semidet :-
			ItemVersions = extract_ids(VersionNumbers, ItemType),
			\+ map__is_empty(ItemVersions)
		),
		[(type), type_body, (mode), (inst),
			predicate, function, (typeclass)]) },
	io__write_string("{\n\t"),
	io__write_list(VersionNumbersList, ",\n\t",
	    (pred((ItemType - ItemVersions)::in, di, uo) is det -->
		{ string_to_item_type(ItemTypeStr, ItemType) },
		io__write_string(ItemTypeStr),
		io__write_string("(\n\t\t"),
		{ map__to_assoc_list(ItemVersions, ItemVersionsList) },
		io__write_list(ItemVersionsList, ",\n\t\t",
		    (pred((NameArity - VersionNumber)::in, di, uo) is det -->
			{ NameArity = Name - Arity },
			mercury_output_bracketed_sym_name(unqualified(Name),
				next_to_graphic_token),
			io__write_string("/"),
			io__write_int(Arity),
			io__write_string(" - "),
			write_version_number(VersionNumber)
		    )),
	    	io__write_string("\n\t)")
	    )),
	( { map__is_empty(InstanceVersionNumbers) } ->
		[]
	;
		( { VersionNumbersList = [] } ->
			[]
		;
			io__write_string(",\n\t")
		),
		io__write_string("instance("),
		{ map__to_assoc_list(InstanceVersionNumbers, InstanceAL) },
		io__write_list(InstanceAL, ",\n\n\t",
		    (pred((ClassNameArity - ClassVersionNumber)::in,
		    		di, uo) is det -->
			{ ClassNameArity = ClassName - ClassArity },
			mercury_output_bracketed_sym_name(ClassName,
				next_to_graphic_token),
			io__write_string("/"),
			io__write_int(ClassArity),
			io__write_string(" - "),
			write_version_number(ClassVersionNumber)
		    )),
		io__write_string(")\n\t")
	),
	io__write_string("\n}").

%-----------------------------------------------------------------------------%

version_numbers_version_number = 1.

%-----------------------------------------------------------------------------%

parse_version_numbers(VersionNumbersTerm, Result) :-
	(
		VersionNumbersTerm = term__functor(term__atom("{}"),
			VersionNumbersTermList0, _)
	->
		VersionNumbersTermList = VersionNumbersTermList0
	;
		VersionNumbersTermList = [VersionNumbersTerm]
	),	
	map_parser(parse_item_type_version_numbers,
		VersionNumbersTermList, Result0),
	(
		Result0 = ok(List),
		VersionNumbers0 = version_numbers(init_item_id_set(map__init),
						map__init),
		VersionNumbers = list__foldl(
		    (func(VNResult, version_numbers(VNs0, Instances0)) =
		    		version_numbers(VNs, Instances) :-
			( 
				VNResult = items(ItemType, ItemVNs),
				VNs = update_ids(VNs0, ItemType, ItemVNs),
				Instances = Instances0
			;
				VNResult = instances(Instances),
				VNs = VNs0
			)
		    ), List, VersionNumbers0),
		Result = ok(VersionNumbers)
	;
		Result0 = error(A, B),
		Result = error(A, B)
	).

:- type item_version_numbers_result
	--->	items(item_type, version_number_map)
	;	instances(instance_version_numbers)
	.

:- pred parse_item_type_version_numbers(term::in,
		maybe1(item_version_numbers_result)::out) is det.

parse_item_type_version_numbers(Term, Result) :-
	(
		Term = term__functor(term__atom(ItemTypeStr),
				ItemsVNsTerms, _),
		string_to_item_type(ItemTypeStr, ItemType)
	->
		ParseName =
		    (pred(NameTerm::in, Name::out) is semidet :-
			NameTerm = term__functor(term__atom(Name), [], _)
		    ),
		map_parser(parse_item_version_number(ParseName),
			ItemsVNsTerms, Result0),
		(
			Result0 = ok(VNsAL),
			map__from_assoc_list(VNsAL, VNsMap),
			Result = ok(items(ItemType, VNsMap))
		;
			Result0 = error(A, B),
			Result = error(A, B)
		)
	;
		Term = term__functor(term__atom("instance"),
				InstanceVNsTerms, _)
	->
		ParseName =
		    (pred(NameTerm::in, Name::out) is semidet :-
			sym_name_and_args(NameTerm, Name, [])
		    ),
		map_parser(parse_item_version_number(ParseName),
			InstanceVNsTerms, Result1),
		(
			Result1 = ok(VNsAL),
			map__from_assoc_list(VNsAL, VNsMap),
			Result = ok(instances(VNsMap))	
		;
			Result1 = error(A, B),
			Result = error(A, B)
		)	
	;
		Result = error("invalid item type version numbers",
				Term)
	).

:- pred parse_item_version_number(pred(term, T)::(pred(in, out) is semidet),
	term::in, maybe1(pair(pair(T, arity), version_number))::out) is det.

parse_item_version_number(ParseName, Term, Result) :-
	(
		Term = term__functor(term__atom("-"),
			[ItemNameArityTerm, VersionNumberTerm], _),
		ItemNameArityTerm = term__functor(term__atom("/"),
			[NameTerm, ArityTerm], _),
		ParseName(NameTerm, Name),
		ArityTerm = term__functor(term__integer(Arity), _, _),
		VersionNumber = term_to_version_number(VersionNumberTerm)
	->
		Result = ok((Name - Arity) - VersionNumber)
	;
		Result = error("error in item version number", Term)
	).

%-----------------------------------------------------------------------------%
