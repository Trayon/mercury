%-----------------------------------------------------------------------------%
% Copyright (C) 1994-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%

% File: std_util.m.
% Main author: fjh.
% Stability: medium to high.

% This file is intended for all the useful standard utilities
% that don't belong elsewhere, like <stdlib.h> in C.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module std_util.

:- interface.

:- import_module list, set.

%-----------------------------------------------------------------------------%

% The universal type `univ'.
% An object of type `univ' can hold the type and value of an object of any
% other type.
%
% Note that the current NU-Prolog/SICStus Prolog implementation of
% univ_to_type is buggy in that it always succeeds, even if the types didn't
% match, so until this gets implemented correctly, don't use
% univ_to_type unless you are sure that the types will definitely match,
% or you don't care about debugging with Prolog.

:- type univ.

	% type_to_univ(Object, Univ):
	% 	true iff the type stored in `Univ' is the same as the type
	%	of `Object', and the value stored in `Univ' is equal to the
	%	value of `Object'.
	%
	% Operational, the forwards mode converts an object to type `univ',
	% while the reverse mode converts the value stored in `Univ'
	% to the type of `Object', but fails if the type stored in `Univ'
	% does not match the type of `Object'.
	% 
:- pred type_to_univ(T, univ).
:- mode type_to_univ(di, uo) is det.
:- mode type_to_univ(in, out) is det.
:- mode type_to_univ(out, in) is semidet.

	% univ_to_type(Univ, Object) :- type_to_univ(Object, Univ).
	%
:- pred univ_to_type(univ, T).
:- mode univ_to_type(in, out) is semidet.
:- mode univ_to_type(out, in) is det.
:- mode univ_to_type(uo, di) is det.

	% The function univ/1 provides the same
	% functionality as type_to_univ/2.

	% univ(Object) = Univ :- type_to_univ(Object, Univ).
	%
:- func univ(T) = univ.
:- mode univ(in) = out is det.
:- mode univ(di) = uo is det.
:- mode univ(out) = in is semidet.

	% det_univ_to_type(Univ, Object):
	% 	the same as the forwards mode of univ_to_type, but
	% 	abort if univ_to_type fails.
	%
:- pred det_univ_to_type(univ, T).
:- mode det_univ_to_type(in, out) is det.

	% univ_type(Univ):
	%	returns the type_info for the type stored in `Univ'.
	%
:- func univ_type(univ) = type_info.


	% univ_value(Univ):
	%	returns the value of the object stored in Univ.
	%
	% Warning: support for existential types is still experimental.
	%
:- some [T] func univ_value(univ) = T.

%-----------------------------------------------------------------------------%

% The "maybe" type.

:- type maybe(T) ---> no ; yes(T).

%-----------------------------------------------------------------------------%

% The "unit" type - stores no information at all.

:- type unit		--->	unit.

%-----------------------------------------------------------------------------%

% The "pair" type.  Useful for many purposes.

:- type pair(T1, T2)	--->	(T1 - T2).
:- type pair(T)		==	pair(T,T).

%-----------------------------------------------------------------------------%

% solutions/2 collects all the solutions to a predicate and
% returns them as a list in sorted order, with duplicates removed.
% solutions_set/2 returns them as a set.
% unsorted_solutions/2 returns them as an unsorted list with possible
% duplicates; since there are an infinite number of such lists,
% this must be called from a context in which only a single solution
% is required.

:- pred solutions(pred(T), list(T)).
:- mode solutions(pred(out) is multi, out) is det.
:- mode solutions(pred(out) is nondet, out) is det.

:- pred solutions_set(pred(T), set(T)).
:- mode solutions_set(pred(out) is multi, out) is det.
:- mode solutions_set(pred(out) is nondet, out) is det.

:- pred unsorted_solutions(pred(T), list(T)).
:- mode unsorted_solutions(pred(out) is multi, out) is cc_multi.
:- mode unsorted_solutions(pred(out) is nondet, out) is cc_multi.

%-----------------------------------------------------------------------------%

	% aggregate/4 generates all the solutions to a predicate,
	% sorts them and removes duplicates, then applies an accumulator
	% predicate to each solution in turn:
	%
	% aggregate(Generator, Accumulator, Acc0, Acc) <=>
	%	solutions(Generator, Solutions),
	%	list__foldl(Accumulator, Solutions, Acc0, Acc).
	%

:- pred aggregate(pred(T), pred(T, U, U), U, U).
:- mode aggregate(pred(out) is multi, pred(in, in, out) is det,
		in, out) is det.
:- mode aggregate(pred(out) is multi, pred(in, di, uo) is det,
		di, uo) is det.
:- mode aggregate(pred(out) is nondet, pred(in, di, uo) is det,
		di, uo) is det.
:- mode aggregate(pred(out) is nondet, pred(in, in, out) is det,
		in, out) is det.

	% unsorted_aggregate/4 generates all the solutions to a predicate
	% and applies an accumulator predicate to each solution in turn.
	% Declaratively, the specification is as follows:
	%
	% unsorted_aggregate(Generator, Accumulator, Acc0, Acc) <=>
	%	unsorted_solutions(Generator, Solutions),
	%	list__foldl(Accumulator, Solutions, Acc0, Acc).
	%
	% Operationally, however, unsorted_aggregate/4 will call the
	% Accumulator for each solution as it is obtained, rather than
	% first building a list of all the solutions.

:- pred unsorted_aggregate(pred(T), pred(T, U, U), U, U).
:- mode unsorted_aggregate(pred(out) is multi, pred(in, in, out) is det,
		in, out) is cc_multi.
:- mode unsorted_aggregate(pred(out) is multi, pred(in, di, uo) is det,
		di, uo) is cc_multi.
:- mode unsorted_aggregate(pred(muo) is multi, pred(mdi, di, uo) is det,
		di, uo) is cc_multi.
:- mode unsorted_aggregate(pred(out) is nondet, pred(in, di, uo) is det,
		di, uo) is cc_multi.
:- mode unsorted_aggregate(pred(out) is nondet, pred(in, in, out) is det,
		in, out) is cc_multi.
:- mode unsorted_aggregate(pred(muo) is nondet, pred(mdi, di, uo) is det,
		di, uo) is cc_multi.

%-----------------------------------------------------------------------------%

	% maybe_pred(Pred, X, Y) takes a closure Pred which transforms an
	% input semideterministically. If calling the closure with the input
	% X succeeds, Y is bound to `yes(Z)' where Z is the output of the
	% call, or to `no' if the call fails.
	%
:- pred maybe_pred(pred(T1, T2), T1, maybe(T2)).
:- mode maybe_pred(pred(in, out) is semidet, in, out) is det.

%-----------------------------------------------------------------------------%

	% `semidet_succeed' is exactly the same as `true', except that
	% the compiler thinks that it is semi-deterministic.  You can
	% use calls to `semidet_succeed' to suppress warnings about
	% determinism declarations which could be stricter.
	% Similarly, `semidet_fail' is like `fail' except that its
	% determinism is semidet rather than failure, and
	% `cc_multi_equal(X,Y)' is the same as `X=Y' except that it
	% is cc_multi rather than det.

:- pred semidet_succeed is semidet.

:- pred semidet_fail is semidet.

:- pred cc_multi_equal(T, T).
:- mode cc_multi_equal(di, uo) is cc_multi.
:- mode cc_multi_equal(in, out) is cc_multi.

%-----------------------------------------------------------------------------%

	% The `type_info' and `type_ctor_info' types: these
	% provide access to type information.
	% A type_info represents a type, e.g. `list(int)'.
	% A type_ctor_info represents a type constructor, e.g. `list/1'.

:- type type_info.
:- type type_ctor_info.

	% (Note: it is not possible for the type of a variable to be an
	% unbound type variable; if there are no constraints on a type
	% variable, then the typechecker will use the type `void'.
	% `void' is a special (builtin) type that has no constructors.
	% There is no way of creating an object of type `void'.
	% `void' is not considered to be a discriminated union, so
	% get_functor/5 and construct/3 will fail if used upon a value
	% of this type.)

	% The function type_of/1 returns a representation of the type
	% of its argument.
	%
:- func type_of(T) = type_info.
:- mode type_of(unused) = out is det.

	% The predicate has_type/2 is basically an existentially typed
	% inverse to the function type_of/1.  It constrains the type
	% of the first argument to be the type represented by the
	% second argument.
	%
	% Warning: support for existential types is still experimental.
	%
:- some [T] pred has_type(T::unused, type_info::in) is det.

	% type_name(Type) returns the name of the specified type
	% (e.g. type_name(type_of([2,3])) = "list:list(int)").
	% Any equivalence types will be fully expanded.
	% Builtin types (those defined in builtin.m) will
	% not have a module qualifier.
	%
:- func type_name(type_info) = string.

	% type_ctor_and_args(Type, TypeCtor, TypeArgs):
	%	True iff `TypeCtor' is a representation of the top-level
	%	type constructor for `Type', and `TypeArgs' is a list
	%	of the corresponding type arguments to `TypeCtor',
	%	and `TypeCtor' is not an equivalence type.
	%
	% For example, type_ctor_and_args(type_of([2,3]), TypeCtor,
	% TypeArgs) will bind `TypeCtor' to a representation of the
	% type constructor list/1, and will bind `TypeArgs' to the list
	% `[Int]', where `Int' is a representation of the type `int'.
	%
	% Note that the requirement that `TypeCtor' not be an
	% equivalence type is fulfilled by fully expanding any
	% equivalence types.  For example, if you have a declaration
	% `:- type foo == bar.', then type_ctor_and_args/3 will always
	% return a representation of type constructor `bar/0', not `foo/0'. 
	% (If you don't want them expanded, you can use the reverse mode
	% of make_type/2 instead.)
	%
:- pred type_ctor_and_args(type_info, type_ctor_info, list(type_info)).
:- mode type_ctor_and_args(in, out, out) is det.

	% type_ctor(Type) = TypeCtor :-
	%	type_ctor_and_args(Type, TypeCtor, _).
	%
:- func type_ctor(type_info) = type_ctor_info.

	% type_args(Type) = TypeArgs :-
	%	type_ctor_and_args(Type, _, TypeArgs).
	%
:- func type_args(type_info) = list(type_info).

	% type_ctor_name(TypeCtor) returns the name of specified
	% type constructor.
	% (e.g. type_ctor_name(type_ctor(type_of([2,3]))) = "list").
	%
:- func type_ctor_name(type_ctor_info) = string.

	% type_ctor_module_name(TypeCtor) returns the module name of specified
	% type constructor.
	% (e.g. type_ctor_module_name(type_ctor(type_of(2))) = "builtin").
	%
:- func type_ctor_module_name(type_ctor_info) = string.

	% type_ctor_arity(TypeCtor) returns the arity of specified
	% type constructor.
	% (e.g. type_ctor_arity(type_ctor(type_of([2,3]))) = 1).
	%
:- func type_ctor_arity(type_ctor_info) = int.

	% type_ctor_name_and_arity(TypeCtor, ModuleName, TypeName, Arity) :-
	%	Name = type_ctor_name(TypeCtor),
	%	ModuleName = type_ctor_module_name(TypeCtor),
	%	Arity = type_ctor_arity(TypeCtor).
	%
:- pred type_ctor_name_and_arity(type_ctor_info, string, string, int).
:- mode type_ctor_name_and_arity(in, out, out, out) is det.

	% make_type(TypeCtor, TypeArgs) = Type:
	%	True iff `Type' is a type constructed by applying
	%	the type constructor `TypeCtor' to the type arguments
	%	`TypeArgs'.
	%
	% Operationally, the forwards mode returns the type formed by
	% applying the specified type constructor to the specified
	% argument types, or fails if the length of TypeArgs is not the
	% same as the arity of TypeCtor.  The reverse mode returns a
	% type constructor and its argument types, given a type_info;
	% the type constructor returned may be an equivalence type
	% (and hence this reverse mode of make_type/2 may be more useful
	% for some purposes than the type_ctor/1 function).
	% 
:- func make_type(type_ctor_info, list(type_info)) = type_info.
:- mode make_type(in, in) = out is semidet.
:- mode make_type(out, out) = in is cc_multi.

	% det_make_type(TypeCtor, TypeArgs):
	%
	% Returns the type formed by applying the specified type
	% constructor to the specified argument types.  Aborts if the
	% length of `TypeArgs' is not the same as the arity of `TypeCtor'.
	%
:- func det_make_type(type_ctor_info, list(type_info)) = type_info.
:- mode det_make_type(in, in) = out is det.

%-----------------------------------------------------------------------------%

	% num_functors(TypeInfo) 
	% 
	% Returns the number of different functors for the top-level
	% type constructor of the type specified by TypeInfo, or -1
	% if the type is not a discriminated union type.
	%
:- func num_functors(type_info) = int.

	% get_functor(Type, N, Functor, Arity, ArgTypes)
	%
	% Binds Functor and Arity to the name and arity of the Nth
	% functor for the specified type (starting at zero), and binds
	% ArgTypes to the type_infos for the types of the arguments of
	% that functor.  Fails if the type is not a discriminated union
	% type, or if N is out of range.
	%
:- pred get_functor(type_info::in, int::in, string::out, int::out,
		list(type_info)::out) is semidet.

	% construct(TypeInfo, N, Args) = Term
	%
	% Returns a term of the type specified by TypeInfo whose functor
	% is the Nth functor of TypeInfo (starting at zero), and whose
	% arguments are given by Args.  Fails if the type is not a
	% discriminated union type, or if N is out of range, or if the
	% number of arguments doesn't match the arity of the Nth functor
	% of the type, or if the types of the arguments doesn't match
	% the expected argument types for that functor.
	%
:- func construct(type_info, int, list(univ)) = univ.
:- mode construct(in, in, in) = out is semidet.

%-----------------------------------------------------------------------------%

	% functor, argument and deconstruct take any type (including univ),
	% and return representation information for that type.
	%
	% The string representation of the functor that `functor' and 
	% `deconstruct' return is:
	% 	- for user defined types, the functor that is given
	% 	  in the type definition. For lists, this
	% 	  means the functors ./2 and []/0 are used, even if
	% 	  the list uses the [....] shorthand.
	%	- for integers, the string is a base 10 number,
	%	  positive integers have no sign.
	%	- for floats, the string is a floating point,
	%	  base 10 number, positive floating point numbers have
	%	  no sign. 
	%	- for strings, the string, inside double quotation marks
	%	- for characters, the character inside single 
	%	  quotation marks
	%	- for predicates and functions, the string
	%	  <<predicate>>

	% functor(Data, Functor, Arity)
	% 
	% Given a data item (Data), binds Functor to a string
	% representation of the functor and Arity to the arity of this
	% data item.  (Aborts if the type of Data is a type with a
	% non-canonical representation, i.e. one for which there is a
	% user-defined equality predicate.)
	%
:- pred functor(T::in, string::out, int::out) is det.

	% arg(Data, ArgumentIndex) = Argument
	% argument(Data, ArgumentIndex) = ArgumentUniv
	% 
	% Given a data item (Data) and an argument index
	% (ArgumentIndex), starting at 0 for the first argument, binds
	% Argument to that argument of the functor of the data item. If
	% the argument index is out of range -- that is, greater than or
	% equal to the arity of the functor or lower than 0 -- then
	% the call fails.  For argument/1 the argument returned has the
	% type univ, which can store any type.  For arg/1, if the
	% argument has the wrong type, then the call fails.
	% (Both abort if the type of Data is a type with a non-canonical
	% representation, i.e. one for which there is a user-defined
	% equality predicate.)
	%
:- func arg(T::in, int::in) = (ArgT::out) is semidet.
:- func argument(T::in, int::in) = (univ::out) is semidet.

	% det_arg(Data, ArgumentIndex) = Argument
	% det_argument(Data, ArgumentIndex) = ArgumentUniv
	% 
	% Same as arg/2 and argument/2 respectively, except that
	% for cases where arg/2 or argument/2 would fail,
	% det_arg/2 or det_argument/2 will abort.
	%
:- func det_arg(T::in, int::in) = (ArgT::out) is det.
:- func det_argument(T::in, int::in) = (univ::out) is det.

	% deconstruct(Data, Functor, Arity, Arguments) 
	% 
	% Given a data item (Data), binds Functor to a string
	% representation of the functor, Arity to the arity of this data
	% item, and Arguments to a list of arguments of the functor.
	% The arguments in the list are each of type univ.
	% (Aborts if the type of Data is a type with a non-canonical
	% representation, i.e. one for which there is a user-defined
	% equality predicate.)
	%
:- pred deconstruct(T::in, string::out, int::out, list(univ)::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module require, set, int, string, bool.

%-----------------------------------------------------------------------------%

/****
	Is this really useful?
% for use in lambda expressions where the type of functor '-' is ambiguous
:- pred pair(X, Y, pair(X, Y)).
:- mode pair(in, in, out) is det.
:- mode pair(out, out, in) is det.

pair(X, Y, X-Y).
****/

maybe_pred(Pred, X, Y) :-
	(
		call(Pred, X, Z)
	->
		Y = yes(Z)
	;
		Y = no
	).

%-----------------------------------------------------------------------------%

:- pred builtin_aggregate(pred(T), pred(T, U, U), U, U).
:- mode builtin_aggregate(pred(out) is multi, pred(in, in, out) is det,
		in, out) is det. /* really cc_multi */
:- mode builtin_aggregate(pred(out) is multi, pred(in, di, uo) is det,
		di, uo) is det. /* really cc_multi */
:- mode builtin_aggregate(pred(muo) is multi, pred(mdi, di, uo) is det,
		di, uo) is det. /* really cc_multi */
:- mode builtin_aggregate(pred(out) is nondet, pred(in, di, uo) is det,
		di, uo) is det. /* really cc_multi */
:- mode builtin_aggregate(pred(out) is nondet, pred(in, in, out) is det,
		in, out) is det. /* really cc_multi */
:- mode builtin_aggregate(pred(muo) is nondet, pred(mdi, di, uo) is det,
		di, uo) is det. /* really cc_multi */

:- external(builtin_aggregate/4).
	% builtin_aggregate is implemented in c_code.

:- pragma c_code("
 
/*
** This module defines builtin_aggregate/4 which takes a closure of type
** pred(T) in which the remaining argument is output, and backtracks over
** solutions for this, using the second argument to aggregate them however the
** user wishes.  This is basically a generalization of solutions/2.
*/
 
#include ""mercury_imp.h""
#include ""mercury_deep_copy.h""

Declare_entry(do_call_nondet_closure);
Declare_entry(do_call_det_closure);

Define_extern_entry(mercury__std_util__builtin_aggregate_4_0);
Define_extern_entry(mercury__std_util__builtin_aggregate_4_1);
Define_extern_entry(mercury__std_util__builtin_aggregate_4_2);
Define_extern_entry(mercury__std_util__builtin_aggregate_4_3);
Define_extern_entry(mercury__std_util__builtin_aggregate_4_4);
Define_extern_entry(mercury__std_util__builtin_aggregate_4_5);
Declare_label(mercury__std_util__builtin_aggregate_4_0_i1);
Declare_label(mercury__std_util__builtin_aggregate_4_0_i2);
Declare_label(mercury__std_util__builtin_aggregate_4_0_i3);

MR_MAKE_PROC_LAYOUT(mercury__std_util__builtin_aggregate_4_0,
	MR_DETISM_MULTI, MR_ENTRY_NO_SLOT_COUNT, MR_LVAL_TYPE_UNKNOWN,
	MR_PREDICATE, ""std_util"", ""builtin_aggregate"", 4, 0);

MR_MAKE_INTERNAL_LAYOUT(mercury__std_util__builtin_aggregate_4_0, 1);
MR_MAKE_INTERNAL_LAYOUT(mercury__std_util__builtin_aggregate_4_0, 2);
MR_MAKE_INTERNAL_LAYOUT(mercury__std_util__builtin_aggregate_4_0, 3);

BEGIN_MODULE(builtin_aggregate_module)
	init_entry_sl(mercury__std_util__builtin_aggregate_4_0);
	MR_INIT_PROC_LAYOUT_ADDR(mercury__std_util__builtin_aggregate_4_0);
	init_entry(mercury__std_util__builtin_aggregate_4_1);
	init_entry(mercury__std_util__builtin_aggregate_4_2);
	init_entry(mercury__std_util__builtin_aggregate_4_3);
	init_entry(mercury__std_util__builtin_aggregate_4_4);
	init_entry(mercury__std_util__builtin_aggregate_4_5);
	init_label_sl(mercury__std_util__builtin_aggregate_4_0_i1);
	init_label_sl(mercury__std_util__builtin_aggregate_4_0_i2);
	init_label_sl(mercury__std_util__builtin_aggregate_4_0_i3);
BEGIN_CODE

/*
** :- pred builtin_aggregate(pred(T), pred(T,T2,T2), T2, T2).
** :- mode builtin_aggregate(pred([out/muo]) is [multi/nondet],
**		pred([in/mdi],[in/di],[out/uo]) is det, in, out) is cc_multi.
**
** Polymorphism will add two extra input parameters, type_infos for T and T2,
** which we don't use at the moment (later they could be used to find
** the address of the respective deep copy routines).
**
** The type_info structures will be in r1 and r2, the closures will be in
** r3 and r4, and the 'initial value' will be in r5, with both calling
** conventions. The output should go either in r6 (for the normal parameter
** convention) or r1 (for the compact parameter convention).
*/
 
#ifdef	COMPACT_ARGS
  #define builtin_aggregate_output	r1
#else
  #define builtin_aggregate_output	r6
#endif

#ifdef PROFILE_CALLS
  #define fallthru(target, caller) { tailcall((target), (caller)); }
#else
  #define fallthru(target, caller)
#endif

Define_entry(mercury__std_util__builtin_aggregate_4_1);
fallthru(ENTRY(mercury__std_util__builtin_aggregate_4_0),
			LABEL(mercury__std_util__builtin_aggregate_4_1))
Define_entry(mercury__std_util__builtin_aggregate_4_2);
fallthru(ENTRY(mercury__std_util__builtin_aggregate_4_0),
			LABEL(mercury__std_util__builtin_aggregate_4_2))
Define_entry(mercury__std_util__builtin_aggregate_4_3);
fallthru(ENTRY(mercury__std_util__builtin_aggregate_4_0),
			LABEL(mercury__std_util__builtin_aggregate_4_3))
Define_entry(mercury__std_util__builtin_aggregate_4_4);
fallthru(ENTRY(mercury__std_util__builtin_aggregate_4_0),
			LABEL(mercury__std_util__builtin_aggregate_4_4))
Define_entry(mercury__std_util__builtin_aggregate_4_5);
fallthru(ENTRY(mercury__std_util__builtin_aggregate_4_0),
			LABEL(mercury__std_util__builtin_aggregate_4_5))
Define_entry(mercury__std_util__builtin_aggregate_4_0);

#ifndef CONSERVATIVE_GC

#ifndef USE_TYPE_LAYOUT
	fatal_error(""builtin_aggregate/4 not supported with this grade ""
		    ""on this system.\\n""
		""Try using a `.gc' (conservative gc) grade.\\n"");
#endif

/*
** In order to implement any sort of code that requires terms to survive
** backtracking, we need to (deeply) copy them out of the heap and into some
** other area before backtracking.  The obvious thing to do then is just call
** the generator predicate, let it run to completion, and copy its result into
** another memory area (call it the solutions heap) before forcing
** backtracking.  When we get the next solution, we do the same, this time
** passing the previous collection (which is still on the solutions heap) to
** the collector predicate.  If the result of this operation contains the old
** collection as a part, then the deep copy operation is smart enough
** not to copy again.  So this could be pretty efficient.
**
** But what if the collector predicate does something that copies the previous
** collection?  Then on each solution, we'll copy the previous collection to
** the heap, and then deep copy it back to the solution heap.  This means
** copying solutions order N**2 times, where N is the number of solutions.  So
** this isn't as efficient as we hoped.
**
** So we use a slightly different approach.  When we find a solution, we deep
** copy it to the solution heap.  Then, before calling the collector code, we
** sneakily swap the runtime system's notion of which is the heap and which is
** the solutions heap.  This ensures that any terms are constructed on the
** solutions heap.  When this is complete, we swap them back, and force the
** engine to backtrack to get the next solution.  And so on.  After we've
** gotten the last solution, we do another deep copy to move the solution back
** to the 'real' heap, and reset the solutions heap pointer (which of course
** reclaims all the garbage of the collection process).
**
** Note that this will work with recursive calls to builtin_aggregate as
** well.  If the recursive invocation occurs in the generator pred, there can
** be no problem because by the time the generator succeeds, the inner
** do_ call will have completed, copied its result from the solutions heap,
** and reset the solutions heap pointer.  If the recursive invocation happens
** in the collector pred, then it will happen when the heap and solutions heap
** are 'swapped.'  This will work out fine, because the real heap isn't needed
** while the collector pred is executing, and by the time the nested do_ is
** completed, the 'real' heap pointer will have been reset.
*/

/* Define a macro to swap the heap and solutions heap */
#define swap_heap_and_solutions_heap()				\
    do {							\
	Word temp;						\
	temp = (Word) MR_ENGINE(heap_zone);			\
	MR_ENGINE(heap_zone) = MR_ENGINE(solutions_heap_zone);	\
	LVALUE_CAST(Word, MR_ENGINE(solutions_heap_zone)) = temp;	\
	temp = (Word) MR_hp;					\
	MR_hp = MR_sol_hp;				\
	LVALUE_CAST(Word, MR_sol_hp) = temp;		\
    } while (0)
 
/*
** Define some framevars we will be using - we need to keep the
** value of hp and the solutions hp (solhp) before we entered 
** solutions, so we can reset the hp after each solution, and
** reset the solhp after all solutions have been found.
** To do a deep copy, we need the type_info of the type of a solution,
** so we save the type_info in type_info_fv.
** Finally, we store the collection of solutions so far in sofar_fv.
*/

#ifdef MR_USE_TRAIL
  #define num_framevars		7
#else
  #define num_framevars		6
#endif

#define saved_hp_fv		(MR_framevar(1))
#define saved_solhp_fv		(MR_framevar(2))
#define collector_pred_fv	(MR_framevar(3))
#define sofar_fv		(MR_framevar(4))
#define element_type_info_fv	(MR_framevar(5))
#define collection_type_info_fv	(MR_framevar(6))
#ifdef MR_USE_TRAIL
  #define saved_trail_ticket_fv	(MR_framevar(7))
#endif

	/*
	** Create a nondet frame and set the failure continuation.
	** The frame slots are used to hold heap and trail states and the
	** collector pred and the collection, and type infos for copying
	** each solution, and for copying the collection back to the heap
	** when we're done.
	*/
	mkframe(""builtin_aggregate"", num_framevars,
		LABEL(mercury__std_util__builtin_aggregate_4_0_i3));
 
	/* save heap states */
 	saved_solhp_fv = (Word) MR_sol_hp; 
 	mark_hp(saved_hp_fv);

#ifdef MR_USE_TRAIL
	/* save trail state */
	MR_store_ticket(saved_trail_ticket_fv);
#endif

	/* save arguments into framevars */
	collector_pred_fv = r4;
	sofar_fv = r5;
	element_type_info_fv = r1;
	collection_type_info_fv = r2;

	/* we do not (yet) need the type_info we are passed in r1 */
	/* call the higher-order pred closure that we were passed in r3 */
	r1 = r3;
	r2 = (Word) 0;	/* the higher-order call has 0 extra input arguments */
	r3 = (Word) 1;	/* the higher-order call has 1 extra output argument */

	call(ENTRY(do_call_nondet_closure),
		LABEL(mercury__std_util__builtin_aggregate_4_0_i1),
		LABEL(mercury__std_util__builtin_aggregate_4_0));

Define_label(mercury__std_util__builtin_aggregate_4_0_i1);
	update_prof_current_proc(
		LABEL(mercury__std_util__builtin_aggregate_4_0));
{
	Word copied_solution, solution;

	/* we found a solution (in r1) */
	solution = r1;

#ifdef MR_USE_TRAIL
	/* check for outstanding delayed goals (``floundering'') */
	MR_reset_ticket(saved_trail_ticket_fv, MR_solve);
#endif

	/* swap heaps so we build on solution heap */
	swap_heap_and_solutions_heap();
 
	/*
	** deep copy solution to the solutions heap, up to the saved_hp.
	** Note that we need to save/restore the hp register, if it
	** is transient, before/after calling deep_copy().
	*/
	save_transient_registers();
	copied_solution = deep_copy(&solution, (Word *) element_type_info_fv,
			(Word *) saved_hp_fv,
			MR_ENGINE(solutions_heap_zone)->top);
	restore_transient_registers();

	/* call the collector closure */
	r1 = collector_pred_fv;
	r2 = (Word) 2;	/* higher-order call has 2 extra input args */
	r3 = (Word) 1;	/* higher-order call has 1 extra output arg */
	r4 = copied_solution;
	r5 = sofar_fv;
	call(ENTRY(do_call_det_closure),
		LABEL(mercury__std_util__builtin_aggregate_4_0_i2),
		LABEL(mercury__std_util__builtin_aggregate_4_0));
}
Define_label(mercury__std_util__builtin_aggregate_4_0_i2);
	update_prof_current_proc(
		LABEL(mercury__std_util__builtin_aggregate_4_0));

	sofar_fv = r1;
 
	/* swap heaps back the way they were */
	swap_heap_and_solutions_heap();
 
	/* look for the next solution */
	redo();
	
Define_label(mercury__std_util__builtin_aggregate_4_0_i3);
	update_prof_current_proc(
		LABEL(mercury__std_util__builtin_aggregate_4_0));
{
	Word copied_collection;

	/* there were no more solutions */

	/* reset heap */
	restore_hp(saved_hp_fv);

#ifdef MR_USE_TRAIL
	/*
	** Reset the trail.  This is necessary to undo any updates performed
	** by the called goal before it failed, and to avoid leaking memory
	** on the trail.
	*/
	MR_reset_ticket(saved_trail_ticket_fv, MR_undo);
#endif

	/*
	** deep_copy() the result to the mercury heap, copying
	** everything between where we started on the solutions
	** heap, and the top of the solutions heap.
	** Note that we need to save/restore the hp register, if it
	** is transient, before/after calling deep_copy().
	**/
	save_transient_registers();
	copied_collection = deep_copy(&sofar_fv,
		    (Word *) collection_type_info_fv,
		    (Word *) saved_solhp_fv,
		    MR_ENGINE(solutions_heap_zone)->top);
	restore_transient_registers();

	builtin_aggregate_output = copied_collection;

 	/* reset solutions heap to where it was before call to solutions  */
 	MR_sol_hp = (Word *) saved_solhp_fv;
 	
	/* discard the frame we made */
	succeed_discard();
}

#undef num_framevars
#undef saved_hp_fv
#undef saved_solhp_fv
#undef collector_pred_fv
#undef sofar_fv
#undef element_type_info_fv
#undef collection_type_info_fv
#undef saved_trail_ticket_fv

#else

/*
** The following algorithm is very straight-forward implementation
** but only works with `--gc conservative'.
** Since with conservative gc, we don't reclaim any memory on failure,
** but instead leave it to the garbage collector, there is no need to
** make deep copies of the solutions.  This is a `copy-zero' implementation ;-)
*/

#ifdef MR_USE_TRAIL
  #define num_framevars		3
#else
  #define num_framevars		2
#endif

#define collector_pred_fv	(MR_framevar(1))
#define sofar_fv		(MR_framevar(2))
#ifdef MR_USE_TRAIL
  #define saved_trail_ticket_fv	(MR_framevar(3))
#endif

	/* create a nondet stack frame with two slots, to hold the collector
	   pred and the collection, and set the failure continuation */
	mkframe(""builtin_aggregate"", num_framevars,
		LABEL(mercury__std_util__builtin_aggregate_4_0_i3));

#ifdef MR_USE_TRAIL
	/* save trail state */
	MR_store_ticket(saved_trail_ticket_fv);
#endif

	/* save our arguments in framevars */
	collector_pred_fv = r4;
	sofar_fv = r5;
 
	/* we do not (yet) need the type_info we are passed in r1 */
	/* call the higher-order pred closure that we were passed in r3 */
	r1 = r3;
	r2 = (Word) 0;	/* the higher-order call has 0 extra input arguments */
	r3 = (Word) 1;	/* the higher-order call has 1 extra output argument */
	call(ENTRY(do_call_nondet_closure),
		LABEL(mercury__std_util__builtin_aggregate_4_0_i1),
		LABEL(mercury__std_util__builtin_aggregate_4_0));

Define_label(mercury__std_util__builtin_aggregate_4_0_i1);
	update_prof_current_proc(
		LABEL(mercury__std_util__builtin_aggregate_4_0));

	/* we found a solution (in r1) */

#ifdef MR_USE_TRAIL
	/* check for outstanding delayed goals (``floundering'') */
	MR_reset_ticket(saved_trail_ticket_fv, MR_solve);
#endif

	/* setup for calling the collector closure */
	r4 = r1;	/* put solution to be collected where we need it */
	r1 = collector_pred_fv;
	r2 = (Word) 2;	/* the higher-order call has 2 extra input arguments */
	r3 = (Word) 1;	/* the higher-order call has 1 extra output argument */
	r5 = sofar_fv;

	call(ENTRY(do_call_det_closure),
		LABEL(mercury__std_util__builtin_aggregate_4_0_i2),
		LABEL(mercury__std_util__builtin_aggregate_4_0));

Define_label(mercury__std_util__builtin_aggregate_4_0_i2);
	update_prof_current_proc(
		LABEL(mercury__std_util__builtin_aggregate_4_0));

	/*
	** we inserted the solution into the collection,
	** and we've now got a new collection (in r1)
	*/
	sofar_fv = r1;

	/* look for the next solution */
 	redo();
 
Define_label(mercury__std_util__builtin_aggregate_4_0_i3);
	update_prof_current_proc(
		LABEL(mercury__std_util__builtin_aggregate_4_0));

	/* no more solutions */

#ifdef MR_USE_TRAIL
	/*
	** Reset the trail.  This is necessary to undo any updates performed
	** by the called goal before it failed, and to avoid leaking memory
	** on the trail.
	*/
	MR_reset_ticket(saved_trail_ticket_fv, MR_undo);
#endif

	/* return the collection and discard the frame we made */
	builtin_aggregate_output = sofar_fv;
 	succeed_discard();
 
#undef num_framevars
#undef collector_pred_fv
#undef sofar_fv
#undef saved_trail_ticket_fv

#endif

END_MODULE

#undef builtin_aggregate_output
#undef swap_heap_and_solutions_heap

/* Ensure that the initialization code for the above module gets run. */
/*
INIT sys_init_builtin_aggregate_module
*/
extern ModuleFunc builtin_aggregate_module;
/* the extra declaration is to suppress a gcc -Wmissing-decl warning */
void sys_init_builtin_aggregate_module(void);
void sys_init_builtin_aggregate_module(void) {
	builtin_aggregate_module();
}

").

solutions(Pred, List) :-
	builtin_solutions(Pred, UnsortedList),
	list__sort_and_remove_dups(UnsortedList, List).

solutions_set(Pred, Set) :-
	builtin_solutions(Pred, List),
	set__list_to_set(List, Set).

unsorted_solutions(Pred, List) :-
	builtin_solutions(Pred, UnsortedList),
	cc_multi_equal(UnsortedList, List).

:- pred builtin_solutions(pred(T), list(T)).
:- mode builtin_solutions(pred(out) is multi, out)
	is det. /* really cc_multi */
:- mode builtin_solutions(pred(out) is nondet, out)
	is det. /* really cc_multi */

builtin_solutions(Generator, UnsortedList) :-
	builtin_aggregate(Generator, cons, [], UnsortedList).

:- pred cons(T::in, list(T)::in, list(T)::out) is det.
cons(H, T, [H|T]).

%-----------------------------------------------------------------------------%

aggregate(Generator, Accumulator, Acc0, Acc) :-
	solutions(Generator, Solutions),
	list__foldl(Accumulator, Solutions, Acc0, Acc).

unsorted_aggregate(Generator, Accumulator, Acc0, Acc) :-
	builtin_aggregate(Generator, Accumulator, Acc0, Acc1),
	cc_multi_equal(Acc1, Acc).

%-----------------------------------------------------------------------------%

% semidet_succeed and semidet_fail, implemented using the C interface
% to make sure that the compiler doesn't issue any determinism warnings
% for them.

:- pragma c_code(semidet_succeed, will_not_call_mercury,
		"SUCCESS_INDICATOR = TRUE;").
:- pragma c_code(semidet_fail, will_not_call_mercury,
		"SUCCESS_INDICATOR = FALSE;").
:- pragma c_code(cc_multi_equal(X::in, Y::out), will_not_call_mercury,
		"Y = X;").
:- pragma c_code(cc_multi_equal(X::di, Y::uo), will_not_call_mercury,
		"Y = X;").
%-----------------------------------------------------------------------------%

	% The type `std_util:type_info/0' happens to use much the same
	% representation as `private_builtin:type_info/1'.
	
univ_to_type(Univ, X) :- type_to_univ(X, Univ).

univ(X) = Univ :- type_to_univ(X, Univ).

det_univ_to_type(Univ, X) :-
	( type_to_univ(X0, Univ) ->
		X = X0
	;
		UnivTypeName = type_name(univ_type(Univ)),
		ObjectTypeName = type_name(type_of(X)),
		string__append_list(["det_univ_to_type: conversion failed\\n",
			"\tUniv Type: ", UnivTypeName,
			"\\n\tObject Type: ", ObjectTypeName], ErrorString),
		error(ErrorString)
	).

:- pragma c_code(univ_value(Univ::in) = (Value::out), will_not_call_mercury, "
	TypeInfo_for_T = field(mktag(0), Univ, UNIV_OFFSET_FOR_TYPEINFO);
	Value = field(mktag(0), Univ, UNIV_OFFSET_FOR_DATA);
").

:- pragma c_header_code("
/*
**	`univ' is represented as a two word structure.
**	One word contains the address of a type_info for the type.
**	The other word contains the data.
**	The offsets UNIV_OFFSET_FOR_TYPEINFO and UNIV_OFFSET_FOR_DATA 
**	are defined in runtime/type_info.h.
*/

#include ""mercury_type_info.h""


").

% :- pred type_to_univ(T, univ).
% :- mode type_to_univ(di, uo) is det.
% :- mode type_to_univ(in, out) is det.
% :- mode type_to_univ(out, in) is semidet.

	% Forward mode - convert from type to univ.
	% Allocate heap space, set the first field to contain the address
	% of the type_info for this type, and then store the input argument
	% in the second field.
:- pragma c_code(type_to_univ(Type::di, Univ::uo), will_not_call_mercury, "
	incr_hp(Univ, 2);
	field(mktag(0), Univ, UNIV_OFFSET_FOR_TYPEINFO) = (Word) TypeInfo_for_T;
	field(mktag(0), Univ, UNIV_OFFSET_FOR_DATA) = (Word) Type;
").
:- pragma c_code(type_to_univ(Type::in, Univ::out), will_not_call_mercury, "
	incr_hp(Univ, 2);
	field(mktag(0), Univ, UNIV_OFFSET_FOR_TYPEINFO) = (Word) TypeInfo_for_T;
	field(mktag(0), Univ, UNIV_OFFSET_FOR_DATA) = (Word) Type;
").

	% Backward mode - convert from univ to type.
	% We check that type_infos compare equal.
	% The variable `TypeInfo_for_T' used in the C code
	% is the compiler-introduced type-info variable.
:- pragma c_code(type_to_univ(Type::out, Univ::in), will_not_call_mercury, "{
	Word univ_type_info = field(mktag(0), Univ, UNIV_OFFSET_FOR_TYPEINFO);
	int comp;
	save_transient_registers();
	comp = MR_compare_type_info(univ_type_info, TypeInfo_for_T);
	restore_transient_registers();
	if (comp == COMPARE_EQUAL) {
		Type = field(mktag(0), Univ, UNIV_OFFSET_FOR_DATA);
		SUCCESS_INDICATOR = TRUE;
	} else {
		SUCCESS_INDICATOR = FALSE;
	}
}").

:- pragma c_code(univ_type(Univ::in) = (TypeInfo::out), will_not_call_mercury, "
	TypeInfo = field(mktag(0), Univ, UNIV_OFFSET_FOR_TYPEINFO);
").

:- pragma c_code("

/*
 * Univ has a special value reserved for its layout, since it needs to
 * be handled as a special case. See above for information on 
 * the representation of data of type `univ'.
 */

#ifdef  USE_TYPE_LAYOUT

MR_MODULE_STATIC_OR_EXTERN
const struct mercury_data_std_util__base_type_layout_univ_0_struct {
	TYPE_LAYOUT_FIELDS
} mercury_data_std_util__base_type_layout_univ_0 = {
	make_typelayout_for_all_tags(TYPELAYOUT_CONST_TAG, 
		mkbody(TYPELAYOUT_UNIV_VALUE))
};

MR_MODULE_STATIC_OR_EXTERN
const struct mercury_data_std_util__base_type_functors_univ_0_struct {
	Integer f1;
} mercury_data_std_util__base_type_functors_univ_0 = {
	MR_TYPEFUNCTORS_UNIV
};

MR_MODULE_STATIC_OR_EXTERN
const struct mercury_data_std_util__base_type_layout_type_info_0_struct
{
	TYPE_LAYOUT_FIELDS
} mercury_data_std_util__base_type_layout_type_info_0 = {
	make_typelayout_for_all_tags(TYPELAYOUT_CONST_TAG, 
		mkbody(TYPELAYOUT_TYPEINFO_VALUE))
};

MR_MODULE_STATIC_OR_EXTERN
const struct
mercury_data_std_util__base_type_functors_type_info_0_struct {
	Integer f1;
} mercury_data_std_util__base_type_functors_type_info_0 = {
	MR_TYPEFUNCTORS_SPECIAL
};

#endif

Define_extern_entry(mercury____Unify___std_util__univ_0_0);
Define_extern_entry(mercury____Index___std_util__univ_0_0);
Define_extern_entry(mercury____Compare___std_util__univ_0_0);

#ifndef	COMPACT_ARGS

Declare_label(mercury____Compare___std_util__univ_0_0_i1);

MR_MAKE_PROC_LAYOUT(mercury____Compare___std_util__univ_0_0,
	MR_DETISM_DET, 1, MR_LIVE_LVAL_STACKVAR(1),
	MR_PREDICATE, ""std_util"", ""compare_univ"", 3, 0);
MR_MAKE_INTERNAL_LAYOUT(mercury____Compare___std_util__univ_0_0, 1);

#endif

Define_extern_entry(mercury____Unify___std_util__type_info_0_0);
Define_extern_entry(mercury____Index___std_util__type_info_0_0);
Define_extern_entry(mercury____Compare___std_util__type_info_0_0);

BEGIN_MODULE(unify_univ_module)
	init_entry(mercury____Unify___std_util__univ_0_0);
	init_entry(mercury____Index___std_util__univ_0_0);
#ifdef	COMPACT_ARGS
	init_entry(mercury____Compare___std_util__univ_0_0);
#else
	init_entry_sl(mercury____Compare___std_util__univ_0_0);
	MR_INIT_PROC_LAYOUT_ADDR(mercury____Compare___std_util__univ_0_0);
	init_label_sl(mercury____Compare___std_util__univ_0_0_i1);
#endif

	init_entry(mercury____Unify___std_util__type_info_0_0);
	init_entry(mercury____Index___std_util__type_info_0_0);
	init_entry(mercury____Compare___std_util__type_info_0_0);

BEGIN_CODE
Define_entry(mercury____Unify___std_util__univ_0_0);
{
	/*
	** Unification for univ.
	**
	** The two inputs are in the registers named by unify_input[12].
	** The success/failure indication should go in unify_output.
	*/

	Word univ1, univ2;
	Word typeinfo1, typeinfo2;
	int comp;

	univ1 = unify_input1;
	univ2 = unify_input2;

	/* First check the type_infos compare equal */
	typeinfo1 = field(mktag(0), univ1, UNIV_OFFSET_FOR_TYPEINFO);
	typeinfo2 = field(mktag(0), univ2, UNIV_OFFSET_FOR_TYPEINFO);
	save_transient_registers();
	comp = MR_compare_type_info(typeinfo1, typeinfo2);
	restore_transient_registers();
	if (comp != COMPARE_EQUAL) {
		unify_output = FALSE;
		proceed();
	}

	/*
	** Then invoke the generic unification predicate on the
	** unwrapped args
	*/
	mercury__unify__x = field(mktag(0), univ1, UNIV_OFFSET_FOR_DATA);
	mercury__unify__y = field(mktag(0), univ2, UNIV_OFFSET_FOR_DATA);
	mercury__unify__typeinfo = typeinfo1;
	{
		Declare_entry(mercury__unify_2_0);
		tailcall(ENTRY(mercury__unify_2_0),
			LABEL(mercury____Unify___std_util__univ_0_0));
	}
}

Define_entry(mercury____Index___std_util__univ_0_0);
	index_output = -1;
	proceed();

Define_entry(mercury____Compare___std_util__univ_0_0);
{
	/*
	** Comparison for univ:
	**
	** The two inputs are in the registers named by compare_input[12].
	** The result should go in compare_output.
	*/

	Word univ1, univ2;
	Word typeinfo1, typeinfo2;
	int comp;

	univ1 = compare_input1;
	univ2 = compare_input2;

	/* First compare the type_infos */
	typeinfo1 = field(mktag(0), univ1, UNIV_OFFSET_FOR_TYPEINFO);
	typeinfo2 = field(mktag(0), univ2, UNIV_OFFSET_FOR_TYPEINFO);
	save_transient_registers();
	comp = MR_compare_type_info(typeinfo1, typeinfo2);
	restore_transient_registers();
	if (comp != COMPARE_EQUAL) {
		compare_output = comp;
		proceed();
	}

	/*
	** If the types are the same, then invoke the generic compare/3
	** predicate on the unwrapped args.
	*/

#ifdef	COMPACT_ARGS
	r1 = typeinfo1;
	r3 = field(mktag(0), univ2, UNIV_OFFSET_FOR_DATA);
	r2 = field(mktag(0), univ1, UNIV_OFFSET_FOR_DATA);
	{
		Declare_entry(mercury__compare_3_0);
		tailcall(ENTRY(mercury__compare_3_0),
			LABEL(mercury____Compare___std_util__univ_0_0));
	}
#else
	r1 = typeinfo1;
	r4 = field(mktag(0), univ2, UNIV_OFFSET_FOR_DATA);
	r3 = field(mktag(0), univ1, UNIV_OFFSET_FOR_DATA);
	incr_sp_push_msg(1, ""mercury____Compare___std_util__univ_0_0"");
	MR_stackvar(1) = MR_succip;
	{
		Declare_entry(mercury__compare_3_0);
		call(ENTRY(mercury__compare_3_0),
			LABEL(mercury____Compare___std_util__univ_0_0_i1),
			LABEL(mercury____Compare___std_util__univ_0_0));
	}
}
Define_label(mercury____Compare___std_util__univ_0_0_i1);
{
	update_prof_current_proc(
		LABEL(mercury____Compare___std_util__univ_0_0));

	/* shuffle the return value into the right register */
	r1 = r2;
	MR_succip = MR_stackvar(1);
	proceed();
#endif
}

Define_entry(mercury____Unify___std_util__type_info_0_0);
{
	/*
	** Unification for type_info.
	**
	** The two inputs are in the registers named by unify_input[12].
	** The success/failure indication should go in unify_output.
	*/
	int comp;
	save_transient_registers();
	comp = MR_compare_type_info(unify_input1, unify_input2);
	restore_transient_registers();
	unify_output = (comp == COMPARE_EQUAL);
	proceed();
}

Define_entry(mercury____Index___std_util__type_info_0_0);
	index_output = -1;
	proceed();

Define_entry(mercury____Compare___std_util__type_info_0_0);
{
	/*
	** Comparison for type_info:
	**
	** The two inputs are in the registers named by compare_input[12].
	** The result should go in compare_output.
	*/
	int comp;
	save_transient_registers();
	comp = MR_compare_type_info(unify_input1, unify_input2);
	restore_transient_registers();
	compare_output = comp;
	proceed();
}

END_MODULE

/* Ensure that the initialization code for the above module gets run. */
/*
INIT sys_init_unify_univ_module
*/
extern ModuleFunc unify_univ_module;
void sys_init_unify_univ_module(void); /* suppress gcc -Wmissing-decl warning */
void sys_init_unify_univ_module(void) {
	unify_univ_module();
}

").

%-----------------------------------------------------------------------------%

	% Code for type manipulation.


	% Prototypes and type definitions.

:- pragma c_header_code("

typedef struct ML_Construct_Info_Struct {
	int vector_type;
	int arity;
	Word *functors_vector;
	Word *argument_vector;
	Word primary_tag;
	Word secondary_tag;
	ConstString functor_name;
} ML_Construct_Info;

int	ML_get_num_functors(Word type_info); 
Word 	ML_copy_argument_typeinfos(int arity, Word type_info,
				Word *arg_vector);
bool 	ML_get_functors_check_range(int functor_number, Word type_info, 
				ML_Construct_Info *info);
void	ML_copy_arguments_from_list_to_vector(int arity, Word arg_list, 
				Word term_vector);
bool	ML_typecheck_arguments(Word type_info, int arity, 
				Word arg_list, Word* arg_vector);
Word 	ML_make_type(int arity, Word *base_type_info, Word arg_type_list);

").


	% A type_ctor_info is represented as a pointer to a base_type_info,
	% except for higher-order types, which are represented using
	% small integers.  See runtime/type_info.h.
:- type type_ctor_info == c_pointer.  

:- pragma c_code(type_of(_Value::unused) = (TypeInfo::out),
	will_not_call_mercury, " 
{
	TypeInfo = TypeInfo_for_T;

	/*
	** We used to collapse equivalences for efficiency here,
	** but that's not always desirable, due to the reverse
	** mode of make_type/2, and efficiency of type_infos
	** probably isn't very important anyway.
	*/
#if 0
	save_transient_registers();
	TypeInfo = MR_collapse_equivalences(TypeInfo_for_T);
	restore_transient_registers();
#endif

}
").

:- pragma c_code(has_type(_Arg::unused, TypeInfo::in), will_not_call_mercury, "
	TypeInfo_for_T = TypeInfo;
").

% Export this function in order to use it in runtime/mercury_trace_external.c
:- pragma export(type_name(in) = out, "ML_type_name").

type_name(Type) = TypeName :-
	type_ctor_and_args(Type, TypeCtor, ArgTypes),
	type_ctor_name_and_arity(TypeCtor, ModuleName, Name, Arity),
	( Arity = 0 ->
		UnqualifiedTypeName = Name
	;
		% XXX the test for mercury_builtin is for bootstrapping
		% only; it should eventually be deleted.
		( ModuleName = "mercury_builtin", Name = "func" -> 
			IsFunc = yes 
		; ModuleName = "builtin", Name = "func" -> 
			IsFunc = yes 
		;
		 	IsFunc = no 
		),
		(
			IsFunc = yes,
			ArgTypes = [FuncRetType]
		->
			FuncRetTypeName = type_name(FuncRetType),
			string__append_list(
				["((func) = ", FuncRetTypeName, ")"],
				UnqualifiedTypeName)
		;
			type_arg_names(ArgTypes, IsFunc, ArgTypeNames),
			string__append_list([Name, "(" | ArgTypeNames], 
				UnqualifiedTypeName)
		)
	),
		% XXX the test for mercury_builtin is for bootstrapping
		% only; it should eventually be deleted.
	( (ModuleName = "mercury_builtin" ; ModuleName = "builtin") ->
		TypeName = UnqualifiedTypeName
	;
		string__append_list([ModuleName, ":", 
			UnqualifiedTypeName], TypeName)
	).

:- pred type_arg_names(list(type_info), bool, list(string)).
:- mode type_arg_names(in, in, out) is det.

type_arg_names([], _, []).
type_arg_names([Type|Types], IsFunc, ArgNames) :-
	Name = type_name(Type),
	( Types = [] ->
		ArgNames = [Name, ")"]
	; IsFunc = yes, Types = [FuncReturnType] ->
		FuncReturnName = type_name(FuncReturnType),
		ArgNames = [Name, ") = ", FuncReturnName]
	;
		type_arg_names(Types, IsFunc, Names),
		ArgNames = [Name, ", " | Names]
	).

type_args(Type) = ArgTypes :-
	type_ctor_and_args(Type, _TypeCtor, ArgTypes).

type_ctor_name(TypeCtor) = Name :-
	type_ctor_name_and_arity(TypeCtor, _ModuleName, Name, _Arity).

type_ctor_module_name(TypeCtor) = ModuleName :-
	type_ctor_name_and_arity(TypeCtor, ModuleName, _Name, _Arity).

type_ctor_arity(TypeCtor) = Arity :-
	type_ctor_name_and_arity(TypeCtor, _ModuleName, _Name, Arity).

det_make_type(TypeCtor, ArgTypes) = Type :-
	( make_type(TypeCtor, ArgTypes) = NewType ->
		Type = NewType
	;
		error("det_make_type/2: make_type/2 failed (wrong arity)")
	).

:- pragma c_code(type_ctor(TypeInfo::in) = (TypeCtor::out), 
	will_not_call_mercury, "
{
	Word *type_info, *base_type_info;

	save_transient_registers();
	type_info = (Word *) MR_collapse_equivalences(TypeInfo);
	restore_transient_registers();

	base_type_info = (Word *) MR_TYPEINFO_GET_BASE_TYPEINFO(type_info);

	TypeCtor = ML_make_ctor_info(type_info, base_type_info);
}
").

:- pragma c_header_code("

Word ML_make_ctor_info(Word *type_info, Word *base_type_info);

	/*
	** Several predicates use these (the MR_BASE_TYPEINFO_IS_HO_*
	** macros need access to these addresses).
	*/
MR_DECLARE_STRUCT(mercury_data___base_type_info_pred_0);
MR_DECLARE_STRUCT(mercury_data___base_type_info_func_0);


").

:- pragma c_code("


Word ML_make_ctor_info(Word *type_info, Word *base_type_info)
{
	Word ctor_info = (Word) base_type_info;

	if (MR_BASE_TYPEINFO_IS_HO_PRED(base_type_info)) {
		ctor_info = MR_TYPECTOR_MAKE_PRED(
			MR_TYPEINFO_GET_HIGHER_ARITY(type_info));
		if (!MR_TYPECTOR_IS_HIGHER_ORDER(ctor_info)) {
			fatal_error(""std_util:ML_make_ctor_info""
				""- arity out of range."");
		}
	} else if (MR_BASE_TYPEINFO_IS_HO_FUNC(base_type_info)) {
		ctor_info = MR_TYPECTOR_MAKE_FUNC(
			MR_TYPEINFO_GET_HIGHER_ARITY(type_info));
		if (!MR_TYPECTOR_IS_HIGHER_ORDER(ctor_info)) {
			fatal_error(""std_util:ML_make_ctor_info""
				""- arity out of range."");
		}
	}
	return ctor_info;
}

").


:- pragma c_code(type_ctor_and_args(TypeInfo::in,
		TypeCtor::out, TypeArgs::out), will_not_call_mercury, "
{
	Word *type_info, *base_type_info;
	Integer arity;

	save_transient_registers();
	type_info = (Word *) MR_collapse_equivalences(TypeInfo);
	base_type_info = MR_TYPEINFO_GET_BASE_TYPEINFO(type_info);
	TypeCtor = ML_make_ctor_info(type_info, base_type_info);

	if (MR_TYPECTOR_IS_HIGHER_ORDER(TypeCtor)) {
		arity = MR_TYPECTOR_GET_HOT_ARITY(TypeCtor);
		TypeArgs = ML_copy_argument_typeinfos(arity, 0,
			type_info + TYPEINFO_OFFSET_FOR_PRED_ARGS);
	} else {
		arity = MR_BASE_TYPEINFO_GET_TYPE_ARITY(base_type_info);
		TypeArgs = ML_copy_argument_typeinfos(arity, 0,
			type_info + OFFSET_FOR_ARG_TYPE_INFOS);
	}
	restore_transient_registers();

}
").

	/*
	** This is the forwards mode of make_type/2:
	** given a type constructor and a list of argument
	** types, check that the length of the argument
	** types matches the arity of the type constructor,
	** and if so, use the type constructor to construct
	** a new type with the specified arguments.
	*/

:- pragma c_code(make_type(TypeCtor::in, ArgTypes::in) = (Type::out),
		will_not_call_mercury, "
{
	int list_length, arity;
	Word arg_type;
	Word *base_type_info;
	
	base_type_info = (Word *) TypeCtor;

	if (MR_TYPECTOR_IS_HIGHER_ORDER(base_type_info)) {
		arity = MR_TYPECTOR_GET_HOT_ARITY(base_type_info);
	} else {
		arity = MR_BASE_TYPEINFO_GET_TYPE_ARITY(base_type_info);
	}

	arg_type = ArgTypes; 
	for (list_length = 0; !list_is_empty(arg_type); list_length++) {
		arg_type = list_tail(arg_type);
	}

	if (list_length != arity) {
		SUCCESS_INDICATOR = FALSE;
	} else {
		save_transient_registers();
		Type = ML_make_type(arity, base_type_info, ArgTypes);
		restore_transient_registers();
		SUCCESS_INDICATOR = TRUE;
	}
}
").

	/*
	** This is the reverse mode of make_type: given a type,
	** split it up into a type constructor and a list of
	** arguments.
	*/

:- pragma c_code(make_type(TypeCtor::out, ArgTypes::out) = (TypeInfo::in),
		will_not_call_mercury, "
{
	Word *type_info = (Word *) TypeInfo;
	Word *base_type_info = MR_TYPEINFO_GET_BASE_TYPEINFO(type_info);
	Integer arity;

	TypeCtor = ML_make_ctor_info(type_info, base_type_info);
	if (MR_TYPECTOR_IS_HIGHER_ORDER(TypeCtor)) {
		arity = MR_TYPECTOR_GET_HOT_ARITY(base_type_info);
		save_transient_registers();
		ArgTypes = ML_copy_argument_typeinfos(arity, 0,
			type_info + TYPEINFO_OFFSET_FOR_PRED_ARGS);
		restore_transient_registers();
	} else {
		arity = MR_BASE_TYPEINFO_GET_TYPE_ARITY(base_type_info);
		save_transient_registers();
		ArgTypes = ML_copy_argument_typeinfos(arity, 0,
			type_info + OFFSET_FOR_ARG_TYPE_INFOS);
		restore_transient_registers();
	}
}
").

:- pragma c_code(type_ctor_name_and_arity(TypeCtor::in, 
		TypeCtorModuleName::out, TypeCtorName::out, 
		TypeCtorArity::out), will_not_call_mercury, "
{
	Word *type_ctor = (Word *) TypeCtor;

	if (MR_TYPECTOR_IS_HIGHER_ORDER(type_ctor)) {
		TypeCtorName = (String) (Word) 
			MR_TYPECTOR_GET_HOT_NAME(type_ctor);
		TypeCtorModuleName = (String) (Word) 
			MR_TYPECTOR_GET_HOT_MODULE_NAME(type_ctor);
		TypeCtorArity = MR_TYPECTOR_GET_HOT_ARITY(type_ctor);
	} else {
		TypeCtorName = MR_BASE_TYPEINFO_GET_TYPE_NAME(type_ctor);
		TypeCtorArity = MR_BASE_TYPEINFO_GET_TYPE_ARITY(type_ctor);
		TypeCtorModuleName = 
			MR_BASE_TYPEINFO_GET_TYPE_MODULE_NAME(type_ctor);
	}
}
").

:- pragma c_code(num_functors(TypeInfo::in) = (Functors::out), 
	will_not_call_mercury, "
{
	save_transient_registers();
	Functors = ML_get_num_functors(TypeInfo); 
	restore_transient_registers(); 
}
").

:- pragma c_code(get_functor(TypeInfo::in, FunctorNumber::in,
		FunctorName::out, Arity::out, TypeInfoList::out), 
	will_not_call_mercury, "
{
	ML_Construct_Info info;
	bool success;

		/* 
		** Get information for this functor number and
		** store in info. If this is a discriminated union
		** type and if the functor number is in range, we
		** succeed.
		*/
	save_transient_registers();
	success = ML_get_functors_check_range(FunctorNumber,
				TypeInfo, &info);
	restore_transient_registers();

		/* 
		** Get the functor name and arity, construct the list
		** of type_infos for arguments.
		*/

	if (success) {
		make_aligned_string(FunctorName, (String) (Word) 
				info.functor_name);
		Arity = info.arity;
		save_transient_registers();
		TypeInfoList = ML_copy_argument_typeinfos((int) Arity,
				TypeInfo, info.argument_vector);
		restore_transient_registers();
	}
	SUCCESS_INDICATOR = success;
}
").

:- pragma c_code(construct(TypeInfo::in, FunctorNumber::in, ArgList::in) =
	(Term::out), will_not_call_mercury, "
{
	Word 	layout_entry, new_data, term_vector;
	ML_Construct_Info info;
	bool success;

		/* 
		** Check range of FunctorNum, get info for this
		** functor.
		*/
	save_transient_registers();
	success = 
		ML_get_functors_check_range(FunctorNumber, TypeInfo, &info) &&
		ML_typecheck_arguments(TypeInfo, info.arity, ArgList, 
				info.argument_vector);
	restore_transient_registers();

		/*
		** Build the new term. 
		** 
		** It will be stored in `new_data', and `term_vector' is a
		** the argument vector.
		** 
		*/
	if (success) {

		layout_entry = MR_BASE_TYPEINFO_GET_TYPELAYOUT_ENTRY(
			MR_TYPEINFO_GET_BASE_TYPEINFO((Word *) TypeInfo), 
				info.primary_tag);

		if (info.vector_type == MR_TYPEFUNCTORS_ENUM) {
			/*
			** Enumeratiors don't have tags or arguments,
			** just the enumeration value.
			*/
			new_data = (Word) info.secondary_tag;
		} else {
			/* 
			** It must be some sort of tagged functor.
			*/

			if (info.vector_type == MR_TYPEFUNCTORS_NO_TAG) {

				/*
				** We set term_vector to point to
				** new_data so that the argument filling
				** loop will fill the argument in.
				*/

				term_vector = (Word) &new_data;

			} else if (tag(layout_entry) == 
					TYPELAYOUT_COMPLICATED_TAG) {

				/*
				** Create arity + 1 words, fill in the
				** secondary tag, and the term_vector will
				** be the rest of the words.
				*/
				incr_hp(new_data, info.arity + 1);
				field(0, new_data, 0) = info.secondary_tag;
				term_vector = (Word) (new_data + sizeof(Word));

			} else if (tag(layout_entry) == TYPELAYOUT_CONST_TAG) {

				/* 
				** If it's a du, and this tag is
				** constant, it must be a complicated
				** constant tag. 
				*/

				new_data = mkbody(info.secondary_tag);
				term_vector = (Word) NULL;

			} else {

				/*
				** A simple tagged word, just need to
				** create arguments.
				*/

				incr_hp(new_data, info.arity);
				term_vector = (Word) new_data; 
			}

				/* 
				** Copy arguments.
				*/

			ML_copy_arguments_from_list_to_vector(info.arity,
					ArgList, term_vector);

				/* 
				** Add tag to new_data.
				*/
			new_data = (Word) mkword(mktag(info.primary_tag), 
				new_data);
		}

		/* 
		** Create a univ.
		*/

		incr_hp(Term, 2);
		field(mktag(0), Term, UNIV_OFFSET_FOR_TYPEINFO) = 
			(Word) TypeInfo;
		field(mktag(0), Term, UNIV_OFFSET_FOR_DATA) = (Word) new_data;
	}

	SUCCESS_INDICATOR = success;
}
"). 

:- pragma c_code("

	/* 
	** Prototypes
	*/

static int 	ML_get_functor_info(Word type_info, int functor_number, 
				ML_Construct_Info *info);

	/*
	** ML_get_functor_info:
	**
	** Extract the information for functor number `functor_number',
	** for the type represented by type_info.
	** We succeed if the type is some sort of discriminated union.
	**
	** You need to save and restore transient registers around
	** calls to this function.
	*/

int 
ML_get_functor_info(Word type_info, int functor_number, ML_Construct_Info *info)
{
	Word *base_type_functors;

	base_type_functors = MR_BASE_TYPEINFO_GET_TYPEFUNCTORS(
		MR_TYPEINFO_GET_BASE_TYPEINFO((Word *) type_info));

	info->vector_type = MR_TYPEFUNCTORS_INDICATOR(base_type_functors);

	switch (info->vector_type) {

	case MR_TYPEFUNCTORS_ENUM:
		info->functors_vector = MR_TYPEFUNCTORS_ENUM_FUNCTORS(
				base_type_functors);
		info->arity = 0;
		info->argument_vector = NULL;
		info->primary_tag = 0;
		info->secondary_tag = functor_number;
		info->functor_name = MR_TYPELAYOUT_ENUM_VECTOR_FUNCTOR_NAME(
				info->functors_vector, functor_number);
		break; 

	case MR_TYPEFUNCTORS_DU:
		info->functors_vector = MR_TYPEFUNCTORS_DU_FUNCTOR_N(
				base_type_functors, functor_number);
		info->arity = MR_TYPELAYOUT_SIMPLE_VECTOR_ARITY(
			info->functors_vector);
		info->argument_vector = MR_TYPELAYOUT_SIMPLE_VECTOR_ARGS(
				info->functors_vector);
		info->primary_tag = tag(MR_TYPELAYOUT_SIMPLE_VECTOR_TAG(
			info->functors_vector));
		info->secondary_tag = unmkbody(
			body(MR_TYPELAYOUT_SIMPLE_VECTOR_TAG(
				info->functors_vector), info->primary_tag));
		info->functor_name = MR_TYPELAYOUT_SIMPLE_VECTOR_FUNCTOR_NAME(
				info->functors_vector);
		break; 

	case MR_TYPEFUNCTORS_NO_TAG:
		info->functors_vector = MR_TYPEFUNCTORS_NO_TAG_FUNCTOR(
				base_type_functors);
		info->arity = 1;
		info->argument_vector = MR_TYPELAYOUT_NO_TAG_VECTOR_ARGS(
				info->functors_vector);
		info->primary_tag = 0;
		info->secondary_tag = 0;
		info->functor_name = MR_TYPELAYOUT_NO_TAG_VECTOR_FUNCTOR_NAME(
				info->functors_vector);
		break; 

	case MR_TYPEFUNCTORS_EQUIV: {
		Word *equiv_type;
		equiv_type = (Word *) MR_TYPEFUNCTORS_EQUIV_TYPE(
				base_type_functors);
		return ML_get_functor_info((Word)
				MR_create_type_info((Word *) type_info, 
						equiv_type),
				functor_number, info);
	}
	case MR_TYPEFUNCTORS_SPECIAL:
		return FALSE;
	case MR_TYPEFUNCTORS_UNIV:
		return FALSE;
	default:
		fatal_error(""std_util:construct - unexpected type."");
	}

	return TRUE;
}

	/*
	** ML_typecheck_arguments:
	**
	** Given a list of univs (`arg_list'), and an vector of
	** type_infos (`arg_vector'), checks that they are all of the
	** same type; if so, returns TRUE, otherwise returns FALSE;
	** `arg_vector' may contain type variables, these
	** will be filled in by the type arguments of `type_info'.
	**
	** Assumes the length of the list has already been checked.
	**
	** You need to save and restore transient registers around
	** calls to this function.
	*/

bool
ML_typecheck_arguments(Word type_info, int arity, Word arg_list,
		Word* arg_vector) 
{
	int i, comp;
	Word arg_type_info, list_arg_type_info;

		/* Type check list of arguments */

	for (i = 0; i < arity; i++) {
		if (list_is_empty(arg_list)) {
			return FALSE;
		}
		list_arg_type_info = field(0, list_head(arg_list), 
			UNIV_OFFSET_FOR_TYPEINFO);

		arg_type_info = (Word) MR_create_type_info(
			(Word *) type_info, (Word *) arg_vector[i]);

		comp = MR_compare_type_info(list_arg_type_info, arg_type_info);
		if (comp != COMPARE_EQUAL) {
			return FALSE;
		}
		arg_list = list_tail(arg_list);
	}

		/* List should now be empty */
	return list_is_empty(arg_list);
}

	/*
	** ML_copy_arguments_from_list_to_vector:
	**
	** Copy the arguments from a list of univs (`arg_list'), 
	** into the vector (`term_vector').
	**
	** Assumes the length of the list has already been checked.
	*/

void
ML_copy_arguments_from_list_to_vector(int arity, Word arg_list,
		Word term_vector) 
{
	int i;

	for (i = 0; i < arity; i++) {
		field(mktag(0), term_vector, i) = 
			field(mktag(0), list_head(arg_list), 
				UNIV_OFFSET_FOR_DATA);
		arg_list = list_tail(arg_list);
	}
}


	/*
	** ML_make_type(arity, base_type_info, arg_types_list):
	**
	** Construct and return a type_info for a type using the
	** specified type_ctor for the type constructor,
	** and using the arguments specified in arg_types_list
	** for the type arguments (if any).
	**
	** Assumes that the arity of the type constructor represented
	** by base_type_info and the length of the arg_types_list 
	** are both equal to `arity'.
	**
	** You need to save and restore transient registers around
	** calls to this function.
	*/

Word
ML_make_type(int arity, Word *type_ctor, Word arg_types_list) 
{
	int i, extra_args;
	Word base_type_info;

	/*
	** We need to treat higher-order predicates as a special case here.
	*/
	if (MR_TYPECTOR_IS_HIGHER_ORDER(type_ctor)) {
		base_type_info = MR_TYPECTOR_GET_HOT_BASE_TYPE_INFO(type_ctor);
		extra_args = 2;
	} else {
		base_type_info = (Word) type_ctor;
		extra_args = 1;
	}

	if (arity == 0) {
		return base_type_info;
	} else {
		Word *type_info;

		restore_transient_registers();
		incr_hp(LVALUE_CAST(Word, type_info), arity + extra_args);
		save_transient_registers();
		
		field(mktag(0), type_info, 0) = base_type_info;
		if (MR_TYPECTOR_IS_HIGHER_ORDER(type_ctor)) {
			field(mktag(0), type_info, 1) = (Word) arity;
		}
		for (i = 0; i < arity; i++) {
			field(mktag(0), type_info, i + extra_args) = 
				list_head(arg_types_list);
			arg_types_list = list_tail(arg_types_list);
		}

		return (Word) type_info;
	}
}


	/*
	** ML_get_functors_check_range:
	**
	** Check that functor_number is in range, and get the functor
	** info if it is. Return FALSE if it is out of range, or
	** if ML_get_functor_info returns FALSE, otherwise return TRUE.
	**
	** You need to save and restore transient registers around
	** calls to this function.
	*/

bool
ML_get_functors_check_range(int functor_number, Word type_info, 
	ML_Construct_Info *info)
{
		/* 
		** Check range of functor_number, get functors
		** vector
		*/
	return  functor_number < ML_get_num_functors(type_info) &&
		functor_number >= 0 &&
		ML_get_functor_info(type_info, functor_number, info);
}


	/* 
	** ML_copy_argument_typeinfos:
	**
	** Copy `arity' type_infos from `arg_vector' onto the heap
	** in a list. 
	** 
	** You need to save and restore transient registers around
	** calls to this function.
	*/

Word 
ML_copy_argument_typeinfos(int arity, Word type_info, Word *arg_vector)
{
	Word type_info_list, *functors;

	restore_transient_registers();
	type_info_list = list_empty(); 

	while (--arity >= 0) {
		Word argument;

			/* Get the argument type_info */
		argument = arg_vector[arity];

			/* Fill in any polymorphic type_infos */
		save_transient_registers();
		argument = (Word) MR_create_type_info(
			(Word *) type_info, (Word *) argument);
		restore_transient_registers();

			/* Look past any equivalences */
		save_transient_registers();
		argument = MR_collapse_equivalences(argument);
		restore_transient_registers();

			/* Join the argument to the front of the list */
		type_info_list = list_cons(argument, type_info_list);
	}
	save_transient_registers();

	return type_info_list;
}


	/* 
	** ML_get_num_functors:
	**
	** Get the number of functors for a type. If it isn't a
	** discriminated union, return -1.
	**
	** You need to save and restore transient registers around
	** calls to this function.
	*/

int 
ML_get_num_functors(Word type_info)
{
	Word *base_type_functors;
	int Functors;

	base_type_functors = MR_BASE_TYPEINFO_GET_TYPEFUNCTORS(
		MR_TYPEINFO_GET_BASE_TYPEINFO((Word *) type_info));

	switch ((int) MR_TYPEFUNCTORS_INDICATOR(base_type_functors)) {

		case MR_TYPEFUNCTORS_DU:
			Functors = MR_TYPEFUNCTORS_DU_NUM_FUNCTORS(
					base_type_functors);
			break;

		case MR_TYPEFUNCTORS_ENUM:
			Functors = MR_TYPEFUNCTORS_ENUM_NUM_FUNCTORS(
					base_type_functors);
			break;

		case MR_TYPEFUNCTORS_EQUIV: {
			Word *equiv_type;
			equiv_type = (Word *) 
				MR_TYPEFUNCTORS_EQUIV_TYPE(
					base_type_functors);
			Functors = ML_get_num_functors((Word)
					MR_create_type_info((Word *) 
						type_info, equiv_type));
			break;
		}

		case MR_TYPEFUNCTORS_SPECIAL:
			Functors = -1;
			break;

		case MR_TYPEFUNCTORS_NO_TAG:
			Functors = 1;
			break;

		case MR_TYPEFUNCTORS_UNIV:
			Functors = -1;
			break;

		default:
			fatal_error(""std_util:ML_get_num_functors :""
				"" unknown indicator"");
	}
	return Functors;
}

").

%-----------------------------------------------------------------------------%


:- pragma c_header_code("

	#include <stdio.h>

	/* 
	 * Code for functor, arg and deconstruct
	 * 
	 * This relies on some C primitives that take a type_info
	 * and a data_word, and get a functor, arity, argument vector,
	 * and argument type_info vector.
	 */

	/* Type definitions */

	/* 
	 * The last two fields, need_functor, and need_args, must
	 * be set by the caller, to indicate whether ML_expand
	 * should copy the functor (if need_functor is non-zero) or
	 * the argument vector and type_info_vector (if need_args is
	 * non-zero). The arity will always be set.
	 *
	 * ML_expand will fill in the other fields (functor, arity,
	 * argument_vector, type_info_vector, and non_canonical_type)
	 * accordingly, but
	 * the values of fields not asked for should be assumed to
	 * contain random data when ML_expand returns.
	 * (that is, they should not be relied on to remain unchanged).
	 */


typedef struct ML_Expand_Info_Struct {
	ConstString functor;
	int arity;
	Word *argument_vector;
	Word *type_info_vector;
	bool non_canonical_type;
	bool need_functor;
	bool need_args;
} ML_Expand_Info;


	/* Prototypes */

void ML_expand(Word* type_info, Word *data_word_ptr, ML_Expand_Info *info);

	/* NB. ML_arg() is also used by store__arg_ref in store.m */
bool ML_arg(Word term_type_info, Word *term, Word argument_index,
		Word *arg_type_info, Word **argument_ptr);

").

:- pragma c_code("

Declare_entry(mercury__builtin_compare_pred_3_0);
Declare_entry(mercury__builtin_compare_non_canonical_type_3_0);

/*
** Expand the given data using its type_info, find its
** functor, arity, argument vector and type_info vector.
** 
** The info.type_info_vector is allocated using malloc 
** It is the responsibility of the  caller to free this
** memory, and to copy any fields of this vector to
** the Mercury heap. The type_infos that the elements of
** this vector point to are either
** 	- already allocated on the heap.
** 	- constants (eg base_type_infos)
**
** Please note: 
**	ML_expand increments the heap pointer, however, on
**	some platforms the register windows mean that transient
**	Mercury registers may be lost. Before calling ML_expand,
**	call save_transient_registers(), and afterwards, call
**	restore_transient_registers().
**
** 	If writing a C function that calls deep_copy, make sure you
** 	document that around your function, save_transient_registers()
** 	restore_transient_registers() need to be used.
**
** 	If you change this code you will also have reflect any changes in 
**	runtime/mercury_deep_copy.c and runtime/mercury_table_any.c
**
**	We use 4 space tabs here because of the level of indenting.
*/

void 
ML_expand(Word* type_info, Word *data_word_ptr, ML_Expand_Info *info)
{
    Code *compare_pred;
    Word *base_type_info, *base_type_functors;
    Word data_value, entry_value, base_type_layout_entry, functors_indicator;
    int data_tag, entry_tag; 
    Word data_word;
    enum MR_DataRepresentation data_rep;

    base_type_info = MR_TYPEINFO_GET_BASE_TYPEINFO(type_info);

    compare_pred = (Code *) base_type_info[OFFSET_FOR_COMPARE_PRED];
    info->non_canonical_type = ( compare_pred ==
        ENTRY(mercury__builtin_compare_non_canonical_type_3_0) );

    data_word = *data_word_ptr;
    data_tag = tag(data_word);
    data_value = body(data_word, data_tag);
	
    base_type_layout_entry = MR_BASE_TYPEINFO_GET_TYPELAYOUT_ENTRY(
        base_type_info, data_tag);
    base_type_functors = MR_BASE_TYPEINFO_GET_TYPEFUNCTORS(base_type_info);
    functors_indicator = MR_TYPEFUNCTORS_INDICATOR(base_type_functors);


    data_rep = MR_categorize_data(functors_indicator, base_type_layout_entry);

    entry_value = strip_tag(base_type_layout_entry);

    switch(data_rep) {

        case MR_DATAREP_ENUM:
            info->functor = MR_TYPELAYOUT_ENUM_VECTOR_FUNCTOR_NAME(
                entry_value, data_word);
            info->arity = 0;
            info->argument_vector = NULL;
            info->type_info_vector = NULL;	
            break;

        case MR_DATAREP_COMPLICATED_CONST:
            data_value = unmkbody(data_value);
            info->functor = MR_TYPELAYOUT_ENUM_VECTOR_FUNCTOR_NAME(
                entry_value, data_value);
            info->arity = 0;
            info->argument_vector = NULL;
            info->type_info_vector = NULL;	
            break;

        case MR_DATAREP_COMPLICATED: {
            Word secondary_tag;

            secondary_tag = ((Word *) data_value)[0];
             
                /* 
                 * Look past the secondary tag, and get the simple vector,
                 * then we can just use the code for simple tags.
                 */
            data_value = (Word) ((Word *) data_value + 1);
            entry_value = (Word)
	    	MR_TYPELAYOUT_COMPLICATED_VECTOR_GET_SIMPLE_VECTOR(
		    entry_value, secondary_tag);
            entry_value = strip_tag(entry_value);
        }   /* fallthru */

        case MR_DATAREP_SIMPLE: /* fallthru */
        {
            int i;
	    Word * simple_vector = (Word *) entry_value;

            info->arity =
	    MR_TYPELAYOUT_SIMPLE_VECTOR_ARITY(simple_vector);
	
            if (info->need_functor) {
                make_aligned_string(info->functor, 
                    MR_TYPELAYOUT_SIMPLE_VECTOR_FUNCTOR_NAME(
                    simple_vector));
            }

            if (info->need_args) {
                info->argument_vector = (Word *) data_value;

                info->type_info_vector = checked_malloc(
                    info->arity * sizeof(Word));

                for (i = 0; i < info->arity ; i++) {
                    Word *arg_pseudo_type_info;

                    arg_pseudo_type_info = (Word *)
                        MR_TYPELAYOUT_SIMPLE_VECTOR_ARGS(simple_vector)[i];
                    info->type_info_vector[i] = (Word) MR_create_type_info(
                        type_info, arg_pseudo_type_info);
                }
            }
            break;
        }

        case MR_DATAREP_NOTAG:
        {
            int i;
	    Word * simple_vector = (Word *) entry_value;

            data_value = (Word) data_word_ptr;

            info->arity = MR_TYPELAYOUT_SIMPLE_VECTOR_ARITY(simple_vector);
	
            if (info->need_functor) {
                make_aligned_string(info->functor, 
                    MR_TYPELAYOUT_SIMPLE_VECTOR_FUNCTOR_NAME(
                    simple_vector));
            }

            if (info->need_args) {
                    /* 
                     * A NO_TAG is much like SIMPLE, but we use the
                     * data_word_ptr here to simulate an argument
                     * vector.
                     */
                info->argument_vector = (Word *) data_word_ptr;

                info->type_info_vector = checked_malloc(
                    info->arity * sizeof(Word));

                for (i = 0; i < info->arity ; i++) {
                    Word *arg_pseudo_type_info;

                    arg_pseudo_type_info = (Word *)
                        MR_TYPELAYOUT_SIMPLE_VECTOR_ARGS(simple_vector)[i];
                    info->type_info_vector[i] = (Word) MR_create_type_info(
                        type_info, arg_pseudo_type_info);
                }
            }
            break;
        }
        case MR_DATAREP_EQUIV: {
            Word *equiv_type_info;

			equiv_type_info = MR_create_type_info(type_info, 
				(Word *) MR_TYPELAYOUT_EQUIV_TYPE(
					entry_value));
			ML_expand(equiv_type_info, data_word_ptr, info);
            break;
        }
        case MR_DATAREP_EQUIV_VAR: {
            Word *equiv_type_info;

			equiv_type_info = MR_create_type_info(type_info, 
				(Word *) entry_value);
			ML_expand(equiv_type_info, data_word_ptr, info);
            break;
        }
        case MR_DATAREP_INT:
            if (info->need_functor) {
                char buf[500];
                char *str;

                sprintf(buf, ""%ld"", (long) data_word);
                incr_saved_hp_atomic(LVALUE_CAST(Word, str), 
                    (strlen(buf) + sizeof(Word)) / sizeof(Word));
                strcpy(str, buf);
                info->functor = str;
            }

            info->argument_vector = NULL;
            info->type_info_vector = NULL;
            info->arity = 0;
            break;

        case MR_DATAREP_CHAR:
                /* XXX should escape characters correctly */
            if (info->need_functor) {
                char *str;

                incr_saved_hp_atomic(LVALUE_CAST(Word, str), 
                    (3 + sizeof(Word)) / sizeof(Word));
                    sprintf(str, ""\'%c\'"", (char) data_word);
                info->functor = str;
            }
            info->argument_vector = NULL;
            info->type_info_vector = NULL;
            info->arity = 0;
            break;

        case MR_DATAREP_FLOAT:
            if (info->need_functor) {
                char buf[500];
                Float f;
                char *str;

                f = word_to_float(data_word);
                sprintf(buf, ""%#.15g"", f);
                incr_saved_hp_atomic(LVALUE_CAST(Word, str), 
                    (strlen(buf) + sizeof(Word)) / sizeof(Word));
                strcpy(str, buf);
                info->functor = str;
            }
            info->argument_vector = NULL;
            info->type_info_vector = NULL;
            info->arity = 0;
            break;

        case MR_DATAREP_STRING:
                /* XXX should escape characters correctly */
            if (info->need_functor) {
                char *str;
    
                incr_saved_hp_atomic(LVALUE_CAST(Word, str),
                    (strlen((String) data_word) + 2 + sizeof(Word))
                    / sizeof(Word));
                sprintf(str, ""%c%s%c"", '""', (String) data_word, '""');
                info->functor = str;
            }
            info->argument_vector = NULL;
            info->type_info_vector = NULL;
            info->arity = 0;
            break;

        case MR_DATAREP_PRED:
            if (info->need_functor) {
                make_aligned_string(info->functor, ""<<predicate>>"");
            }
            info->argument_vector = NULL;
            info->type_info_vector = NULL;
            info->arity = 0;
            break;

        case MR_DATAREP_UNIV:
                /* 
                 * Univ is a two word structure, containing
                 * type_info and data.
                 */
            ML_expand((Word *)
                ((Word *) data_word)[UNIV_OFFSET_FOR_TYPEINFO], 
                &((Word *) data_word)[UNIV_OFFSET_FOR_DATA], info);
            break;

        case MR_DATAREP_VOID:
	    /*
	    ** There's no way to create values of type `void',
	    ** so this should never happen.
	    */
	    fatal_error(""ML_expand: cannot expand void types"");

        case MR_DATAREP_ARRAY:
            if (info->need_functor) {
                make_aligned_string(info->functor, ""<<array>>"");
            }
	    /* XXX should we return the arguments here? */
            info->argument_vector = NULL;
            info->type_info_vector = NULL;
            info->arity = 0;
            break;

        case MR_DATAREP_TYPEINFO:
            if (info->need_functor) {
                make_aligned_string(info->functor, ""<<typeinfo>>"");
            }
	    /* XXX should we return the arguments here? */
            info->argument_vector = NULL;
            info->type_info_vector = NULL;
            info->arity = 0;
            break;

        case MR_DATAREP_C_POINTER:
            if (info->need_functor) {
                make_aligned_string(info->functor, ""<<c_pointer>>"");
            }
            info->argument_vector = NULL;
            info->type_info_vector = NULL;
            info->arity = 0;
            break;

        case MR_DATAREP_UNKNOWN:    /* fallthru */
        default:
            fatal_error(""ML_expand: cannot expand -- unknown data type"");
            break;
    }
}

/*
** ML_arg() is a subroutine used to implement arg/2, argument/2,
** and also store__arg_ref/5 in store.m.
** It takes a term (& its type), and an argument index,
** and returns a
*/
bool
ML_arg(Word term_type_info, Word *term_ptr, Word argument_index,
	Word *arg_type_info, Word **argument_ptr)
{
	ML_Expand_Info info;
	Word arg_pseudo_type_info;
	bool success;

	info.need_functor = FALSE;
	info.need_args = TRUE;

	ML_expand((Word *) term_type_info, term_ptr, &info);

		/*
		** Check for attempts to deconstruct a non-canonical type:
		** such deconstructions must be cc_multi, and since
		** arg/2 is det, we must treat violations of this
		** as runtime errors.
		** (There ought to be a cc_multi version of arg/2
		** that allows this.)
		*/
	if (info.non_canonical_type) {
		fatal_error(""called argument/2 for a type with a ""
			""user-defined equality predicate"");
	}

		/* Check range */
	success = (argument_index >= 0 && argument_index < info.arity);
	if (success) {
			/* figure out the type of the argument */
		arg_pseudo_type_info = info.type_info_vector[argument_index];
		if (TYPEINFO_IS_VARIABLE(arg_pseudo_type_info)) {
			*arg_type_info =
				((Word *) term_type_info)[arg_pseudo_type_info];
		} else {
			*arg_type_info = arg_pseudo_type_info;
		}

		*argument_ptr = &info.argument_vector[argument_index];
	}

	/*
	** Free the allocated type_info_vector, since we just copied
	** the stuff we want out of it.
	*/
	free(info.type_info_vector);

	return success;
}

").

%-----------------------------------------------------------------------------%

	% Code for functor, arg and deconstruct.

:- pragma c_code(functor(Term::in, Functor::out, Arity::out),
		will_not_call_mercury, " 
{
	ML_Expand_Info info;

	info.need_functor = TRUE;
	info.need_args = FALSE;

	save_transient_registers();

	ML_expand((Word *) TypeInfo_for_T, &Term, &info);

	restore_transient_registers();

		/*
		** Check for attempts to deconstruct a non-canonical type:
		** such deconstructions must be cc_multi, and since
		** functor/2 is det, we must treat violations of this
		** as runtime errors.
		** (There ought to be a cc_multi version of functor/2
		** that allows this.)
		*/
	if (info.non_canonical_type) {
		fatal_error(""called functor/2 for a type with a ""
			""user-defined equality predicate"");
	}

		/* Copy functor onto the heap */
	make_aligned_string(LVALUE_CAST(ConstString, Functor), info.functor);

	Arity = info.arity;
}").

/*
** N.B. any modifications to arg/2 might also require similar
** changes to store__arg_ref in store.m.
*/

:- pragma c_code(arg(Term::in, ArgumentIndex::in) = (Argument::out),
		will_not_call_mercury, " 
{
	Word arg_type_info;
	Word *argument_ptr;
	bool success;
	int comparison_result;

	save_transient_registers();

	success = ML_arg(TypeInfo_for_T, &Term, ArgumentIndex, &arg_type_info,
			&argument_ptr);

	if (success) {
		/* compare the actual type with the expected type */
		comparison_result =
			MR_compare_type_info(arg_type_info, TypeInfo_for_ArgT);
		success = (comparison_result == COMPARE_EQUAL);

		if (success) {
			Argument = *argument_ptr;
		}
	}

	restore_transient_registers();

	SUCCESS_INDICATOR = success;
}").

:- pragma c_code(argument(Term::in, ArgumentIndex::in) = (ArgumentUniv::out),
		will_not_call_mercury, " 
{
	Word arg_type_info;
	Word *argument_ptr;
	bool success;

	save_transient_registers();

	success = ML_arg(TypeInfo_for_T, &Term, ArgumentIndex, &arg_type_info,
			&argument_ptr);

	restore_transient_registers();

	if (success) {
		/* Allocate enough room for a univ */
		incr_hp(ArgumentUniv, 2);
		field(0, ArgumentUniv, UNIV_OFFSET_FOR_TYPEINFO) =
			arg_type_info;
		field(0, ArgumentUniv, UNIV_OFFSET_FOR_DATA) = *argument_ptr;
	}

	SUCCESS_INDICATOR = success;

}").

det_arg(Type, ArgumentIndex) = Argument :-
	(
		arg(Type, ArgumentIndex) = Argument0
	->
		Argument = Argument0
	;
		( argument(Type, ArgumentIndex) = _ArgumentUniv ->
			error("det_arg: argument number out of range")
		;
			error("det_arg: argument had wrong type")
		)
	).

det_argument(Type, ArgumentIndex) = Argument :-
	(
		argument(Type, ArgumentIndex) = Argument0
	->
		Argument = Argument0
	;
		error("det_argument: argument out of range")
	).

:- pragma c_code(deconstruct(Term::in, Functor::out, Arity::out, 
		Arguments::out), will_not_call_mercury, " 
{
	ML_Expand_Info info;
	Word arg_pseudo_type_info;
	Word Argument, tmp;
	int i;

	info.need_functor = TRUE;
	info.need_args = TRUE;

	save_transient_registers();

	ML_expand((Word *) TypeInfo_for_T, &Term, &info);
	
	restore_transient_registers();

		/*
		** Check for attempts to deconstruct a non-canonical type:
		** such deconstructions must be cc_multi, and since
		** deconstruct/4 is det, we must treat violations of this
		** as runtime errors.
		** (There ought to be a cc_multi version of deconstruct/4
		** that allows this.)
		*/
	if (info.non_canonical_type) {
		fatal_error(""called deconstruct/4 for a type with a ""
			""user-defined equality predicate"");
	}

		/* Get functor */
	make_aligned_string(LVALUE_CAST(ConstString, Functor), info.functor);

		/* Get arity */
	Arity = info.arity;

		/* Build argument list */
	Arguments = list_empty();
	i = info.arity;

	while (--i >= 0) {

			/* Create an argument on the heap */
		incr_hp(Argument, 2);

			/* Join the argument to the front of the list */
		Arguments = list_cons(Argument, Arguments);

			/* Fill in the arguments */
		arg_pseudo_type_info = info.type_info_vector[i];

		if (TYPEINFO_IS_VARIABLE(arg_pseudo_type_info)) {

				/* It's a type variable, get its value */
			field(0, Argument, UNIV_OFFSET_FOR_TYPEINFO) = 
				((Word *) TypeInfo_for_T)[arg_pseudo_type_info];
		}
		else {
				/* It's already a type_info */
			field(0, Argument, UNIV_OFFSET_FOR_TYPEINFO) = 
				arg_pseudo_type_info;
		}
			/* Fill in the data */
		field(0, Argument, UNIV_OFFSET_FOR_DATA) = 
			info.argument_vector[i];
	}

	/* Free the allocated type_info_vector, since we just copied
	 * all its arguments onto the heap. 
	 */

	free(info.type_info_vector);

}").

%-----------------------------------------------------------------------------%

	% This predicate returns the type_info for the type std_util:type_info.
	% It is intended for use from C code, since Mercury code can access
	% this type_info easily enough even without this predicate.
:- pred get_type_info_for_type_info(type_info).
:- mode get_type_info_for_type_info(out) is det.

:- pragma export(get_type_info_for_type_info(out),
	"ML_get_type_info_for_type_info").

get_type_info_for_type_info(TypeInfo) :-
	Type = type_of(1),
	TypeInfo = type_of(Type).

%-----------------------------------------------------------------------------%

% This is a generalization of unsorted_aggregate which allows the
% iteration to stop before all solutions have been found.
% NOT YET IMPLEMENTED
%  
% :- pred do_while(pred(T), pred(T,T2,T2,bool), T2, T2).
% :- mode do_while(pred(out) is multi, pred(in,in,out,out) is det, in, out) is
% 	cc_multi.
% :- mode do_while(pred(out) is nondet, pred(in,in,out,out) is det, in, out) is
% 	cc_multi.

%-----------------------------------------------------------------------------%
