%---------------------------------------------------------------------------%
% Copyright (C) 1993-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: map.m.
% Main author: fjh, conway.
% Stability: high.
%
% This file provides the 'map' ADT.
% A map (also known as a dictionary or an associative array) is a collection
% of (Key,Data) pairs which allows you to look up any Data item given the
% Key.
%
% The implementation is using balanced binary trees, as provided by
% tree234.m.  Virtually all the predicates in this file just
% forward the work to the corresponding predicate in tree234.m.
%
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module map.
:- interface.
:- import_module set, list, assoc_list.

%-----------------------------------------------------------------------------%

:- type map(_K, _V).

%-----------------------------------------------------------------------------%

	% Initialize an empty map.
:- pred map__init(map(_,_)).
:- mode map__init(uo) is det.

	% Check whether a map is empty.
:- pred map__is_empty(map(_,_)).
:- mode map__is_empty(in) is semidet.

	% Check whether map contains key
:- pred map__contains(map(K,_V), K).
:- mode map__contains(in, in) is semidet.

:- pred map__member(map(K,V), K, V).
:- mode map__member(in, out, out) is nondet.

	% Search map for key.
:- pred map__search(map(K,V), K, V).
:- mode map__search(in, in, in) is semidet.	% implied
:- mode map__search(in, in, out) is semidet.

	% Search map for key, but abort if search fails.
:- pred map__lookup(map(K,V), K, V).
:- mode map__lookup(in, in, in) is semidet.	% implied
:- mode map__lookup(in, in, out) is det.

	% Search map for data.
:- pred map__inverse_search(map(K,V), V, K).
:- mode map__inverse_search(in, in, out) is nondet.

	% Insert a new key and corresponding value into a map.
	% Fail if the key already exists.
:- pred map__insert(map(K,V), K, V, map(K,V)).
:- mode map__insert(in, in, in, out) is semidet.

	% Insert a new key and corresponding value into a map.
	% Abort if the key already exists.
:- pred map__det_insert(map(K,V), K, V, map(K,V)).
:- mode map__det_insert(in, in, in, out) is det.

	% Apply map__det_insert to key - value pairs from corresponding lists.
:- pred map__det_insert_from_corresponding_lists(map(K,V), list(K),
						list(V), map(K,V)).
:- mode map__det_insert_from_corresponding_lists(in, in, in, out) is det.

	% Apply map__det_insert to key - value pairs from the assoc_lists.
:- pred map__det_insert_from_assoc_list(map(K,V), assoc_list(K, V),
						map(K,V)).
:- mode map__det_insert_from_assoc_list(in, in, out) is det.

	% Update the value corresponding to a given key
	% Fail if the key doesn't already exist.
:- pred map__update(map(K,V), K, V, map(K,V)).
:- mode map__update(in, in, in, out) is semidet.

	% Update the value corresponding to a given key
	% Abort if the key doesn't already exist.
:- pred map__det_update(map(K,V), K, V, map(K,V)).
:- mode map__det_update(in, in, in, out) is det.

	% Update value if the key is already present, otherwise
	% insert new key and value.
:- pred map__set(map(K,V), K, V, map(K,V)).
:- mode map__set(di, di, di, uo) is det.
:- mode map__set(in, in, in, out) is det.

	% Given a map, return a list of all the keys in the map.
:- pred map__keys(map(K, _V), list(K)).
:- mode map__keys(in, out) is det.

	% Given a map, return a list of all the keys in the map,
	% in sorted order.
:- pred map__sorted_keys(map(K, _V), list(K)).
:- mode map__sorted_keys(in, out) is det.

	% Given a map, return a list of all the data values in the map.
:- pred map__values(map(_K, V), list(V)).
:- mode map__values(in, out) is det.

	% Convert a map to an association list.
:- pred map__to_assoc_list(map(K,V), assoc_list(K,V)).
:- mode map__to_assoc_list(in, out) is det.

	% Convert a map to an association list which is sorted on the keys.
:- pred map__to_sorted_assoc_list(map(K,V), assoc_list(K,V)).
:- mode map__to_sorted_assoc_list(in, out) is det.

	% Convert an association list to a map.
:- pred map__from_assoc_list(assoc_list(K,V), map(K,V)).
:- mode map__from_assoc_list(in, out) is det.

	% Convert a sorted association list to a map.
:- pred map__from_sorted_assoc_list(assoc_list(K,V), map(K,V)).
:- mode map__from_sorted_assoc_list(in, out) is det.

	% Delete a key-value pair from a map.
	% If the key is not present, leave the map unchanged.
:- pred map__delete(map(K,V), K, map(K,V)).
:- mode map__delete(di, in, uo) is det.
:- mode map__delete(in, in, out) is det.

	% Apply map__delete/3 to a list of keys.
:- pred map__delete_list(map(K,V), list(K), map(K,V)).
:- mode map__delete_list(di, in, uo) is det.
:- mode map__delete_list(in, in, out) is det.

	% Delete a key-value pair from a map and return the value.
	% Fail if the key is not present.
:- pred map__remove(map(K,V), K, V, map(K,V)).
:- mode map__remove(in, in, out, out) is semidet.

	% Delete a key-value pair from a map and return the value.
	% Abort if the key is not present.
:- pred map__det_remove(map(K,V), K, V, map(K,V)).
:- mode map__det_remove(in, in, out, out) is det.

	% Count the number of elements in the map.
:- pred map__count(map(K, V), int).
:- mode map__count(in, out) is det.

	% Convert a pair of lists (which must be of the same length)
	% to a map.
:- pred map__from_corresponding_lists(list(K), list(V), map(K, V)).
:- mode map__from_corresponding_lists(in, in, out) is det.

	% For map__merge(MapA, MapB, Map), MapA and MapB must
	% not both contain the same key.
:- pred map__merge(map(K, V), map(K, V), map(K, V)).
:- mode map__merge(in, in, out) is det.

	% For map__overlay(MapA, MapB, Map), if MapA and MapB both
	% contain the same key, then Map will map that key to
	% the value from MapB.  In otherwords, MapB takes precedence
	% over MapA.
:- pred map__overlay(map(K,V), map(K,V), map(K,V)).
:- mode map__overlay(in, in, out) is det.

	% map__select takes a map and a set of keys and returns
	% a map containing the keys in the set and their corresponding
	% values.
:- pred map__select(map(K,V), set(K), map(K,V)).
:- mode map__select(in, in, out) is det.

	% Given a list of keys, produce a list of their corresponding
	% values in a specified map.
:- pred map__apply_to_list(list(K), map(K, V), list(V)).
:- mode map__apply_to_list(in, in, out) is det.

	% Declaratively, a NOP.
	% Operationally, a suggestion that the implemention
	% optimize the representation of the map in the expectation
	% of a number of lookups but few or no modifications.
:- pred map__optimize(map(K, V), map(K, V)).
:- mode map__optimize(in, out) is det.

	% Remove the smallest item from the map, fail if
	% the map is empty.
:- pred map__remove_smallest(map(K, V), K, V, map(K, V)).
:- mode map__remove_smallest(in, out, out, out) is semidet.

	% Perform an inorder tranversal of the map, applying
	% an accumulator predicate for each key-value pair.
:- pred map__foldl(pred(K, V, T, T), map(K, V), T, T).
:- mode map__foldl(pred(in, in, in, out) is det, in, in, out) is det.
:- mode map__foldl(pred(in, in, in, out) is semidet, in, in, out) is semidet.
:- mode map__foldl(pred(in, in, di, uo) is det, in, di, uo) is det.

	% Apply a transformation predicate to all the values
	% in a map.
:- pred map__map_values(pred(K, V, W), map(K, V), map(K, W)).
:- mode map__map_values(pred(in, in, out) is det, in, out) is det.
:- mode map__map_values(pred(in, in, out) is semidet, in, out) is semidet.

	% Given two maps M1 and M2, create a third map M3 that has only the
	% keys that occur in both M1 and M2. For keys that occur in both M1
	% and M2, compute the value in the final map by applying the supplied
	% predicate to the values associated with the key in M1 and M2.
	% Fail if and only if this predicate fails on the values associated
	% with some common key.
:- pred map__intersect(pred(V, V, V), map(K, V), map(K, V), map(K, V)).
:- mode map__intersect(pred(in, in, out) is semidet, in, in, out) is semidet.
:- mode map__intersect(pred(in, in, out) is det, in, in, out) is det.

	% Calls map__intersect. Aborts if map__intersect fails.
:- pred map__det_intersect(pred(V, V, V), map(K, V), map(K, V), map(K, V)).
:- mode map__det_intersect(pred(in, in, out) is semidet, in, in, out) is det.

	% Given two maps M1 and M2, create a third map M3 that all the keys
	% that occur in either M1 and M2. For keys that occur in both M1
	% and M2, compute the value in the final map by applying the supplied
	% predicate to the values associated with the key in M1 and M2.
	% Fail if and only if this predicate fails on the values associated
	% with some common key.
:- pred map__union(pred(V, V, V), map(K, V), map(K, V), map(K, V)).
:- mode map__union(pred(in, in, out) is semidet, in, in, out) is semidet.
:- mode map__union(pred(in, in, out) is det, in, in, out) is det.

	% Calls map__union. Aborts if map__union fails.
:- pred map__det_union(pred(V, V, V), map(K, V), map(K, V), map(K, V)).
:- mode map__det_union(pred(in, in, out) is semidet, in, in, out) is det.

%-----------------------------------------------------------------------------%

:- import_module tree234.

:- type map(K,V)	==	tree234(K,V).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.
:- import_module std_util, require, string.

%-----------------------------------------------------------------------------%

map__init(M) :-
	tree234__init(M).

map__is_empty(M) :-
	tree234__init(M).

map__contains(Map, K) :-
	map__search(Map, K, _).

map__member(Map, K, V) :-
	tree234__member(Map, K, V).

:- map__search(_Map, K, _V) when K.	% required by bimap.m

map__search(Map, K, V) :-
	tree234__search(Map, K, V).

:- map__lookup(_Map, K, _V) when K.	% required by bimap.m

map__lookup(Map, K, V) :-
	( tree234__search(Map, K, V1) ->
		V = V1
	;
		map__lookup_error("map__lookup: key_not_found", K, V)
	).

:- pred map__lookup_error(string, K, V).
:- mode map__lookup_error(in, in, unused) is erroneous.
map__lookup_error(Msg, K, V) :-
	KeyType = type_name(type_of(K)),
	ValueType = type_name(type_of(V)),
	functor(K, Functor, Arity),
	( Arity = 0 ->
		FunctorStr = Functor
	;
		string__int_to_string(Arity, ArityStr),
		string__append_list([Functor, "/", ArityStr],
			FunctorStr)
	),
	string__append_list(
		[Msg,
		"\n\tKey Type: ",
		KeyType,
		"\n\tKey Functor: ",
		FunctorStr,
		"\n\tValue Type: ",
		ValueType
		],
		ErrorString),
	error(ErrorString).

map__insert(Map0, K, V, Map) :-
	tree234__insert(Map0, K, V, Map).

map__det_insert(Map0, K, V, Map) :-
	( tree234__insert(Map0, K, V, Map1) ->
		Map = Map1
	;
		map__lookup_error("map__det_insert: key already present", K, V)
	).

map__det_insert_from_corresponding_lists(Map0, Ks, Vs, Map) :-
	( Ks = [Key | Keys], Vs = [Value | Values] ->
		map__det_insert(Map0, Key, Value, Map1),
		map__det_insert_from_corresponding_lists(Map1, Keys,
							Values, Map)
	;
		Ks = [], Vs = []
	->
		Map = Map0
	;
		error("map__det_insert_from_corresponding_lists - lists do not correspond")
	).

map__det_insert_from_assoc_list(Map, [], Map).
map__det_insert_from_assoc_list(Map0, [K - V | KVs], Map) :-
	map__det_insert(Map0, K, V, Map1),
	map__det_insert_from_assoc_list(Map1, KVs, Map).

map__update(Map0, K, V, Map) :-
	tree234__update(Map0, K, V, Map).

map__det_update(Map0, K, V, Map) :-
	( tree234__update(Map0, K, V, Map1) ->
		Map = Map1
	;
		map__lookup_error("map__det_update: key not found", K, V)
	).

map__set(Map0, K, V, Map) :-
	tree234__set(Map0, K, V, Map).

map__keys(Map, KeyList) :-
	tree234__keys(Map, KeyList).

map__sorted_keys(Map, KeyList) :-
	% Guaranteed to yield sorted lists.
	tree234__keys(Map, KeyList).

map__values(Map, KeyList) :-
	tree234__values(Map, KeyList).

map__to_assoc_list(M, L) :-
	tree234__tree234_to_assoc_list(M, L).

map__to_sorted_assoc_list(M, L) :-
	% Guaranteed to yield sorted lists.
	tree234__tree234_to_assoc_list(M, L).

map__from_assoc_list(L, M) :-
	tree234__assoc_list_to_tree234(L, M).

map__from_sorted_assoc_list(L, M) :-
	tree234__assoc_list_to_tree234(L, M).

map__delete(Map0, Key, Map) :-
	tree234__delete(Map0, Key, Map).

map__delete_list(Map, [], Map).
map__delete_list(Map0, [Key | Keys], Map) :-
	map__delete(Map0, Key, Map1),
	map__delete_list(Map1, Keys, Map).

map__remove(Map0, Key, Value, Map) :-
	tree234__remove(Map0, Key, Value, Map).

map__det_remove(Map0, Key, Value, Map) :-
	( tree234__remove(Map0, Key, Value1, Map1) ->
		Value = Value1,
		Map = Map1
	;
		map__lookup_error("map__det_remove: key not found", Key, Value)
	).

map__count(Map, Count) :-
	tree234__count(Map, Count).

%-----------------------------------------------------------------------------%

	% XXX inefficient

map__inverse_search(Map, V, K) :-
	tree234__tree234_to_assoc_list(Map, AssocList),
	assoc_list_member(K, V, AssocList).

%-----------------------------------------------------------------------------%

	% The code here is deliberately written using very simple
	% modes.
	% The reason we don't just use member/2 is that we want to
	% bootstrap this thing ASAP.

:- pred assoc_list_member(K, V, list(pair(K,V))).
:- mode assoc_list_member(in, out, in) is nondet.
:- mode assoc_list_member(out, in, in) is nondet.
:- mode assoc_list_member(in, in, in) is semidet.
assoc_list_member(K, V, [K - V | _]).
assoc_list_member(K, V, [_ | Xs]) :-
	assoc_list_member(K, V, Xs).

%-----------------------------------------------------------------------------%

map__from_corresponding_lists(Keys, Values, Map) :-
	assoc_list__from_corresponding_lists(Keys, Values, AssocList),
	tree234__assoc_list_to_tree234(AssocList, Map).

%-----------------------------------------------------------------------------%

map__merge(M0, M1, M) :-
	map__to_assoc_list(M0, ML0),
	map__to_assoc_list(M1, ML1),
	list__merge(ML0, ML1, ML),
	map__from_sorted_assoc_list(ML, M).

%-----------------------------------------------------------------------------%

map__optimize(Map, Map).

%-----------------------------------------------------------------------------%

map__overlay(Map0, Map1, Map) :-
	map__to_assoc_list(Map1, AssocList),
	map__overlay_2(AssocList, Map0, Map).

:- pred map__overlay_2(assoc_list(K,V), map(K,V), map(K,V)).
:- mode map__overlay_2(in, in, out) is det.

map__overlay_2([], Map, Map).
map__overlay_2([K - V | AssocList], Map0, Map) :-
	map__set(Map0, K, V, Map1),
	map__overlay_2(AssocList, Map1, Map).

%-----------------------------------------------------------------------------%

map__select(Original, KeySet, NewMap) :-
	set__to_sorted_list(KeySet, KeyList),
	map__init(NewMap0),
	map__select_2(KeyList, Original, NewMap0, NewMap).

:- pred map__select_2(list(K), map(K,V), map(K,V), map(K,V)).
:- mode map__select_2(in, in, in, out) is det.

map__select_2([], _Original, New, New).
map__select_2([K|Ks], Original, New0, New) :-
	(
		map__search(Original, K, V)
	->
		map__set(New0, K, V, New1)
	;
		New1 = New0
	),
	map__select_2(Ks, Original, New1, New).

%-----------------------------------------------------------------------------%

map__apply_to_list([], _, []).
map__apply_to_list([K | Ks], Map, [V | Vs]) :-
	map__lookup(Map, K, V),
	map__apply_to_list(Ks, Map, Vs).

%-----------------------------------------------------------------------------%

map__remove_smallest(Map0, K, V, Map) :-
	tree234__remove_smallest(Map0, K, V, Map).

%-----------------------------------------------------------------------------%

map__foldl(Pred, Map, Acc0, Acc) :-
	tree234__foldl(Pred, Map, Acc0, Acc).

%-----------------------------------------------------------------------------%

map__map_values(Pred, Map0, Map) :-
	tree234__map_values(Pred, Map0, Map).

%-----------------------------------------------------------------------------%

map__intersect(CommonPred, Map1, Map2, Common) :-
	map__to_sorted_assoc_list(Map1, AssocList1),
	map__to_sorted_assoc_list(Map2, AssocList2),
	map__init(Common0),
	map__intersect_2(AssocList1, AssocList2, CommonPred, Common0, Common).

:- pred map__intersect_2(assoc_list(K, V), assoc_list(K, V), pred(V, V, V),
	map(K, V), map(K, V)).
:- mode map__intersect_2(in, in, pred(in, in, out) is semidet, in, out)
	is semidet.
:- mode map__intersect_2(in, in, pred(in, in, out) is det, in, out)
	is det.

map__intersect_2(AssocList1, AssocList2, CommonPred, Common0, Common) :-
	(
		AssocList1 = [],
		AssocList2 = [],
		Common = Common0
	;
		AssocList1 = [_ | _],
		AssocList2 = [],
		Common = Common0
	;
		AssocList1 = [],
		AssocList2 = [_ | _],
		Common = Common0
	;
		AssocList1 = [Key1 - Value1 | AssocTail1],
		AssocList2 = [Key2 - Value2 | AssocTail2],
		compare(R, Key1, Key2),
		(
			R = (=),
			call(CommonPred, Value1, Value2, Value),
			map__det_insert(Common0, Key1, Value, Common1),
			map__intersect_2(AssocTail1, AssocTail2, CommonPred,
				Common1, Common)
		;
			R = (<),
			map__intersect_2(AssocTail1, AssocList2, CommonPred,
				Common0, Common)
		;
			R = (>),
			map__intersect_2(AssocList1, AssocTail2, CommonPred,
				Common0, Common)
		)
	).

map__det_intersect(CommonPred, Map1, Map2, Common) :-
	( map__intersect(CommonPred, Map1, Map2, CommonPrime) ->
		Common = CommonPrime
	;
		error("map__det_intersect: map__intersect failed")
	).

%-----------------------------------------------------------------------------%

map__union(CommonPred, Map1, Map2, Common) :-
	map__to_sorted_assoc_list(Map1, AssocList1),
	map__to_sorted_assoc_list(Map2, AssocList2),
	map__init(Common0),
	map__union_2(AssocList1, AssocList2, CommonPred, Common0, Common).

:- pred map__union_2(assoc_list(K, V), assoc_list(K, V), pred(V, V, V),
	map(K, V), map(K, V)).
:- mode map__union_2(in, in, pred(in, in, out) is semidet, in, out)
	is semidet.
:- mode map__union_2(in, in, pred(in, in, out) is det, in, out)
	is det.

map__union_2(AssocList1, AssocList2, CommonPred, Common0, Common) :-
	(
		AssocList1 = [],
		AssocList2 = [],
		Common = Common0
	;
		AssocList1 = [_ | _],
		AssocList2 = [],
		map__det_insert_from_assoc_list(Common0, AssocList1, Common)
	;
		AssocList1 = [],
		AssocList2 = [_ | _],
		map__det_insert_from_assoc_list(Common0, AssocList2, Common)
	;
		AssocList1 = [Key1 - Value1 | AssocTail1],
		AssocList2 = [Key2 - Value2 | AssocTail2],
		compare(R, Key1, Key2),
		(
			R = (=),
			call(CommonPred, Value1, Value2, Value),
			map__det_insert(Common0, Key1, Value, Common1),
			map__union_2(AssocTail1, AssocTail2, CommonPred,
				Common1, Common)
		;
			R = (<),
			map__det_insert(Common0, Key1, Value1, Common1),
			map__union_2(AssocTail1, AssocList2, CommonPred,
				Common1, Common)
		;
			R = (>),
			map__det_insert(Common0, Key2, Value2, Common1),
			map__union_2(AssocList1, AssocTail2, CommonPred,
				Common1, Common)
		)
	).

map__det_union(CommonPred, Map1, Map2, Union) :-
	( map__union(CommonPred, Map1, Map2, UnionPrime) ->
		Union = UnionPrime
	;
		error("map__det_union: map__union failed")
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
