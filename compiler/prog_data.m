%-----------------------------------------------------------------------------%
% Copyright (C) 1996-2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: prog_data.m.
% Main author: fjh.
%
% This module defines a data structure for representing Mercury programs.
%
% This data structure specifies basically the same information as is
% contained in the source code, but in a parse tree rather than a flat file.
% Simplifications are done only by make_hlds.m, which transforms
% the parse tree which we built here into the HLDS.

:- module prog_data.

:- interface.

% This module should NOT import hlds*.m, either directly or indirectly.
% Any types which are needed in both the parse tree and in the HLDS
% should be defined here, rather than in hlds*.m.

:- import_module (inst).
:- import_module bool, list, assoc_list, map, varset, term, std_util.

%-----------------------------------------------------------------------------%

	% This is how programs (and parse errors) are represented.

:- type message_list	==	list(pair(string, term)).
				% the error/warning message, and the
				% term to which it relates

:- type compilation_unit		
	--->	module(
			module_name,
			item_list
		).

:- type item_list	==	list(item_and_context).

:- type item_and_context ==	pair(item, prog_context).

:- type item		
	--->	pred_clause(prog_varset, sym_name, list(prog_term), goal)
		%      VarNames, PredName, HeadArgs, ClauseBody

	;	func_clause(prog_varset, sym_name, list(prog_term),
			prog_term, goal)
		%      VarNames, PredName, HeadArgs, Result, ClauseBody

	; 	type_defn(tvarset, type_defn, condition)
	; 	inst_defn(inst_varset, inst_defn, condition)
	; 	mode_defn(inst_varset, mode_defn, condition)
	; 	module_defn(prog_varset, module_defn)

	; 	pred(tvarset, inst_varset, existq_tvars, sym_name,
			list(type_and_mode), maybe(determinism), condition,
			purity, class_constraints)
		%       TypeVarNames, InstVarNames,
		%	ExistentiallyQuantifiedTypeVars, PredName, ArgTypes,
		%	Deterministicness, Cond, Purity, TypeClassContext

	; 	func(tvarset, inst_varset, existq_tvars, sym_name,
			list(type_and_mode), type_and_mode, maybe(determinism),
			condition, purity, class_constraints)
		%       TypeVarNames, InstVarNames,
		%	ExistentiallyQuantifiedTypeVars, PredName, ArgTypes,
		%	ReturnType, Deterministicness, Cond, Purity,
		%	TypeClassContext

	; 	pred_mode(inst_varset, sym_name, list(mode), maybe(determinism),
			condition)
		%       VarNames, PredName, ArgModes, Deterministicness,
		%       Cond

	; 	func_mode(inst_varset, sym_name, list(mode), mode,
			maybe(determinism), condition)
		%       VarNames, PredName, ArgModes, ReturnValueMode,
		%       Deterministicness, Cond

	;	pragma(pragma_type)

	;	assertion(goal, prog_varset)

	;	typeclass(list(class_constraint), class_name, list(tvar),
			class_interface, tvarset)
		%	Constraints, ClassName, ClassParams, 
		%	ClassMethods, VarNames

	;	instance(list(class_constraint), class_name, list(type),
			instance_body, tvarset, module_name)
		%	DerivingClass, ClassName, Types, 
		%	MethodInstances, VarNames, ModuleContainingInstance

	;	nothing.
		% used for items that should be ignored (currently only
		% NU-Prolog `when' declarations, which are silently ignored
		% for backwards compatibility).

:- type type_and_mode	
	--->	type_only(type)
	;	type_and_mode(type, mode).

:- type foreign_language
	--->	c
% 	;	cplusplus
% 	;	csharp
 	;	managed_cplusplus
% 	;	java
% 	;	il
	.

:- type pred_or_func
	--->	predicate
	;	function.

	% Purity indicates whether a goal can have side effects or can
	% depend on global state.  See purity.m and the "Purity" section
	% of the Mercury language reference manual.
:- type purity		--->	pure
			;	(semipure)
			;	(impure).

	% The `determinism' type specifies how many solutions a given
	% procedure may have.  Procedures for manipulating this type
	% are defined in det_analysis.m and hlds_data.m.
:- type determinism	
	--->	det
	;	semidet
	;	nondet
	;	multidet
	;	cc_nondet
	;	cc_multidet
	;	erroneous
	;	failure.

%-----------------------------------------------------------------------------%
%
% Pragmas
%

:- type pragma_type 
			% a foreign language declaration, such as C
			% header code.
	--->	foreign_decl(foreign_language, string)

	;	foreign_code(foreign_language, string)

	;	foreign_proc(pragma_foreign_proc_attributes,
			sym_name, pred_or_func, list(pragma_var),
			prog_varset, pragma_foreign_code_impl)
			% Set of foreign proc attributes, eg.:
			%	what language this code is in
			%	whether or not the code may call Mercury,
			%	whether or not the code is thread-safe
			% PredName, Predicate or Function, Vars/Mode, 
			% VarNames, Foreign Code Implementation Info
	
	;	type_spec(sym_name, sym_name, arity, maybe(pred_or_func),
			maybe(list(mode)), type_subst, tvarset)
			% PredName, SpecializedPredName, Arity,
			% PredOrFunc, Modes if a specific procedure was
			% specified, type substitution (using the variable
			% names from the pred declaration), TVarSet

	;	inline(sym_name, arity)
			% Predname, Arity

	;	no_inline(sym_name, arity)
			% Predname, Arity

	;	obsolete(sym_name, arity)
			% Predname, Arity

	;	export(sym_name, pred_or_func, list(mode),
			string)
			% Predname, Predicate/function, Modes,
			% C function name.

	;	import(sym_name, pred_or_func, list(mode),
			pragma_foreign_proc_attributes, string)
			% Predname, Predicate/function, Modes,
			% Set of foreign proc attributes, eg.:
			%    whether or not the foreign code may call Mercury,
			%    whether or not the foreign code is thread-safe
			% foreign function name.

	;	source_file(string)
			% Source file name.

	;	unused_args(pred_or_func, sym_name, arity,
			mode_num, list(int))
			% PredName, Arity, Mode number, Optimized pred name,
			% 	Removed arguments.
			% Used for inter-module unused argument
			% removal, should only appear in .opt files.

	;	fact_table(sym_name, arity, string)
			% Predname, Arity, Fact file name.

	;	aditi(sym_name, arity)
			% Predname, Arity

	;	base_relation(sym_name, arity)
			% Predname, Arity
			%
			% Eventually, these should only occur in 
			% automatically generated database interface 
			% files, but for now there's no such thing, 
			% so they can occur in user programs.

	;	aditi_index(sym_name, arity, index_spec)
			% PredName, Arity, IndexType, Attributes
			%
			% Specify an index on a base relation.

	;	naive(sym_name, arity)
			% Predname, Arity
			% Use naive evaluation.

	;	psn(sym_name, arity)
			% Predname, Arity
			% Use predicate semi-naive evaluation.

	;	aditi_memo(sym_name, arity)
			% Predname, Arity

	;	aditi_no_memo(sym_name, arity)
			% Predname, Arity

	;	supp_magic(sym_name, arity)
			% Predname, Arity

	;	context(sym_name, arity)
			% Predname, Arity

	;	owner(sym_name, arity, string)
			% PredName, Arity, String.

	;	tabled(eval_method, sym_name, int, maybe(pred_or_func), 
				maybe(list(mode)))
			% Tabling type, Predname, Arity, PredOrFunc?, Mode?
	
	;	promise_pure(sym_name, arity)
			% Predname, Arity

	;	promise_semipure(sym_name, arity)
			% Predname, Arity

	;	termination_info(pred_or_func, sym_name, list(mode),
				maybe(pragma_arg_size_info),
				maybe(pragma_termination_info))
			% the list(mode) is the declared argmodes of the
			% procedure, unless there are no declared argmodes,
			% in which case the inferred argmodes are used.
			% This pragma is used to define information about a
			% predicates termination properties.  It is most
			% useful where the compiler has insufficient
			% information to be able to analyse the predicate.
			% This includes c_code, and imported predicates.
			% termination_info pragmas are used in opt and
			% trans_opt files.


	;	terminates(sym_name, arity)
			% Predname, Arity

	;	does_not_terminate(sym_name, arity)
			% Predname, Arity

	;	check_termination(sym_name, arity).
			% Predname, Arity

%
% Stuff for tabling pragmas
%

	% The evaluation method that should be used for a pred.
	% Ignored for Aditi procedures.
:- type eval_method
	--->	eval_normal		% normal mercury 
					% evaluation
	;	eval_loop_check		% loop check only
	;	eval_memo		% memoing + loop check 
	;	eval_table_io		% memoing I/O actions for debugging
	;	eval_minimal.		% minimal model 
					% evaluation 
%
% Stuff for the `aditi_index' pragma
%

	% For Aditi base relations, an index_spec specifies how the base
	% relation is indexed.
:- type index_spec
	---> index_spec(
		index_type,
		list(int)	% which attributes are being indexed on
				% (attribute numbers start at 1)
	).

	% Hash indexes?
:- type index_type
	--->	unique_B_tree
	;	non_unique_B_tree.

%
% Stuff for the `termination_info' pragma.
% See term_util.m.
%

:- type pragma_arg_size_info
	--->	finite(int, list(bool))
				% The termination constant is a finite integer.
				% The list of bool has a 1:1 correspondence
				% with the input arguments of the procedure.
				% It stores whether the argument contributes
				% to the size of the output arguments.
	;	infinite.
				% There is no finite integer for which the
				% above equation is true.

:- type pragma_termination_info
	---> 	cannot_loop	% This procedure definitely terminates for all
				% possible inputs.
	;	can_loop.	% This procedure might not terminate.


%
% Stuff for the `unused_args' pragma.
%

	% This `mode_num' type is only used for mode numbers written out in
	% automatically-generateed `pragma unused_args' pragmas in `.opt'
	% files. 
	% The mode_num gets converted to an HLDS proc_id by make_hlds.m.
	% We don't want to use the `proc_id' type here since the parse tree
	% (prog_data.m) should not depend on the HLDS.
:- type mode_num == int.

%
% Stuff for the `type_spec' pragma.
%

	% The type substitution for a `pragma type_spec' declaration.
	% Elsewhere in the compiler we generally use the `tsubst' type
	% which is a map rather than an assoc_list.
:- type type_subst == assoc_list(tvar, type).

%
% Stuff for `foreign_code' pragma.
%

	% This type holds information about the implementation details
	% of procedures defined via `pragma foreign_code'.
	%
	% All the strings in this type may be accompanied by the context
	% of their appearance in the source code. These contexts are
	% used to tell the foreign language compiler where the included
	% code comes from, to allow it to generate error messages that
	% refer to the original appearance of the code in the Mercury
	% program.
	% The context is missing if the foreign code was constructed by
	% the compiler.
	% Note that nondet pragma foreign definitions might not be
	% possible in all foreign languages.
:- type pragma_foreign_code_impl
	--->	ordinary(		% This is a foreign language
					% definition of a model_det
					% or model_semi procedure. (We
					% also allow model_non, until
					% everyone has had time to adapt
					% to the new way
					% of handling model_non pragmas.)
			string,		% The code of the procedure.
			maybe(prog_context)
		)
	;	nondet(			% This is a foreign language
					% definition of a model_non
					% procedure.
			string,
			maybe(prog_context),
					% The info saved for the time when
					% backtracking reenters this procedure
					% is stored in a data structure.
					% This arg contains the field
					% declarations.

			string,
			maybe(prog_context),
					% Gives the code to be executed when
					% the procedure is called for the first 
					% time. This code may access the input
					% variables.

			string,	
			maybe(prog_context),
					% Gives the code to be executed when
					% control backtracks into the procedure.
					% This code may not access the input
					% variables.

			pragma_shared_code_treatment,
					% How should the shared code be
					% treated during code generation.
			string,	
			maybe(prog_context)
					% Shared code that is executed after
					% both the previous code fragments.
					% May not access the input variables.
		)
	;	import(
			string,		% Pragma imported C func name
			string,		% Code to handle return value
			string,		% Comma seperated variables which
					% the import function is called
					% with.

			maybe(prog_context)
		).

	% The use of this type is explained in the comment at the top of
	% pragma_c_gen.m.
:- type pragma_shared_code_treatment
	--->	duplicate
	;	share
	;	automatic.

%-----------------------------------------------------------------------------%
%
% Stuff for type classes
%

	% A class constraint represents a constraint that a given
	% list of types is a member of the specified type class.
	% It is an invariant of this data structure that
	% the types in a class constraint do not contain any
	% information in their prog_context fields.
	% This invariant is needed to ensure that we can do
	% unifications, map__lookups, etc., and get the
	% expected semantics.
	% Any code that creates new class constraints must
	% ensure that this invariant is preserved,
	% probably by using strip_term_contexts/2 in type_util.m.
:- type class_constraint
	---> constraint(class_name, list(type)).

:- type class_constraints
	---> constraints(
		list(class_constraint),	% ordinary (universally quantified)
		list(class_constraint)	% existentially quantified constraints
	).

:- type class_name == sym_name.

:- type class_interface  == list(class_method).	

:- type class_method
	--->	pred(tvarset, inst_varset, existq_tvars, sym_name,
			list(type_and_mode), maybe(determinism), condition,
			purity, class_constraints, prog_context)
		%       TypeVarNames, InstVarNames,
		%	ExistentiallyQuantifiedTypeVars,
		%	PredName, ArgTypes, Determinism, Cond
		%	Purity, ClassContext, Context

	; 	func(tvarset, inst_varset, existq_tvars, sym_name,
			list(type_and_mode), type_and_mode,
			maybe(determinism), condition,
			purity, class_constraints, prog_context)
		%       TypeVarNames, InstVarNames,
		%	ExistentiallyQuantfiedTypeVars,
		%	PredName, ArgTypes, ReturnType,
		%	Determinism, Cond
		%	Purity, ClassContext, Context

	; 	pred_mode(inst_varset, sym_name, list(mode),
			maybe(determinism), condition,
			prog_context)
		%       InstVarNames, PredName, ArgModes,
		%	Determinism, Cond
		%	Context

	; 	func_mode(inst_varset, sym_name, list(mode), mode,
			maybe(determinism), condition,
			prog_context)
		%       InstVarNames, PredName, ArgModes,
		%	ReturnValueMode,
		%	Determinism, Cond
		%	Context
	.

:- type instance_method	
	--->	instance_method(pred_or_func, sym_name, instance_proc_def,
			arity, prog_context).
				% PredOrFunc, Method, Instance, Arity, 
				% Line number of declaration

:- type instance_proc_def
		% defined using the `pred(...) is <Name>' syntax
	--->	name(sym_name)	

		% defined using clauses
	;	clauses(
			list(item)	% the items must be either
					% pred_clause or func_clause items
		)
	.

:- type instance_body
	--->	abstract
	;	concrete(instance_methods).

:- type instance_methods ==	list(instance_method).

%-----------------------------------------------------------------------------%
%
% Some more stuff for `pragma c_code'.
%

		% an abstract type for representing a set of
		% `pragma_c_code_attribute's.
:- type pragma_foreign_proc_attributes.

:- pred default_attributes(foreign_language, pragma_foreign_proc_attributes).
:- mode default_attributes(in, out) is det.

:- pred may_call_mercury(pragma_foreign_proc_attributes, may_call_mercury).
:- mode may_call_mercury(in, out) is det.

:- pred set_may_call_mercury(pragma_foreign_proc_attributes, may_call_mercury,
		pragma_foreign_proc_attributes).
:- mode set_may_call_mercury(in, in, out) is det.

:- pred thread_safe(pragma_foreign_proc_attributes, thread_safe).
:- mode thread_safe(in, out) is det.

:- pred set_thread_safe(pragma_foreign_proc_attributes, thread_safe,
		pragma_foreign_proc_attributes).
:- mode set_thread_safe(in, in, out) is det.

:- pred foreign_language(pragma_foreign_proc_attributes, foreign_language).
:- mode foreign_language(in, out) is det.

:- pred set_foreign_language(pragma_foreign_proc_attributes, foreign_language,
		pragma_foreign_proc_attributes).
:- mode set_foreign_language(in, in, out) is det.

:- pred tabled_for_io(pragma_foreign_proc_attributes, tabled_for_io).
:- mode tabled_for_io(in, out) is det.

:- pred set_tabled_for_io(pragma_foreign_proc_attributes, tabled_for_io,
		pragma_foreign_proc_attributes).
:- mode set_tabled_for_io(in, in, out) is det.

	% For pragma c_code, there are two different calling conventions,
	% one for C code that may recursively call Mercury code, and another
	% more efficient one for the case when we know that the C code will
	% not recursively invoke Mercury code.
:- type may_call_mercury
	--->	may_call_mercury
	;	will_not_call_mercury.

	% If thread_safe execution is enabled, then we need to put a mutex
	% around the C code for each `pragma c_code' declaration, unless
	% it's declared to be thread_safe.
:- type thread_safe
	--->	not_thread_safe
	;	thread_safe.

:- type tabled_for_io
	--->	not_tabled_for_io
	;	tabled_for_io.

:- type pragma_var    
	--->	pragma_var(prog_var, string, mode).
	  	% variable, name, mode
		% we explicitly store the name because we need the real
		% name in code_gen

%-----------------------------------------------------------------------------%
%
% Goals
%

	% Here's how clauses and goals are represented.
	% a => b --> implies(a, b)
	% a <= b --> implies(b, a) [just flips the goals around!]
	% a <=> b --> equivalent(a, b)

% clause/4 defined above

:- type goal		==	pair(goal_expr, prog_context).

:- type goal_expr	
	% conjunctions
	--->	(goal , goal)	% (non-empty) conjunction
	;	true		% empty conjunction
	;	{goal & goal}	% parallel conjunction
				% (The curly braces just quote the '&'/2.)

	% disjunctions
	;	{goal ; goal}	% (non-empty) disjunction
				% (The curly braces just quote the ';'/2.)
	;	fail		% empty disjunction

	% quantifiers
	;	{ some(prog_vars, goal) }
				% existential quantification
				% (The curly braces just quote the 'some'/2.)
	;	all(prog_vars, goal)	% universal quantification

	% implications
	;	implies(goal, goal)	% A => B
	;	equivalent(goal, goal)	% A <=> B

	% negation and if-then-else
	;	not(goal)
	;	if_then(prog_vars, goal, goal)
	;	if_then_else(prog_vars, goal, goal, goal)

	% atomic goals
	;	call(sym_name, list(prog_term), purity)
	;	unify(prog_term, prog_term, purity).

:- type goals		==	list(goal).

	% These type equivalences are for the type of program variables
	% and associated structures.

:- type prog_var_type	--->	prog_var_type.
:- type prog_var	==	var(prog_var_type).
:- type prog_varset	==	varset(prog_var_type).
:- type prog_substitution ==	substitution(prog_var_type).
:- type prog_term	==	term(prog_var_type).
:- type prog_vars	==	list(prog_var).

	% A prog_context is just a term__context.

:- type prog_context	==	term__context.

	% Describe how a lambda expression is to be evaluated.
	%
	% `normal' is the top-down Mercury execution algorithm.
	%
	% `lambda_eval_method's other than `normal' are used for lambda
	% expressions constructed for arguments of the builtin Aditi
	% update constructs.
	%
	% `aditi_top_down' expressions are used by `aditi_delete'
	% goals (see hlds_goal.m) to determine whether a tuple
	% should be deleted.
	%
	% `aditi_bottom_up' expressions are used as database queries to
	% produce a set of tuples to be inserted or deleted.
:- type lambda_eval_method
	--->	normal
	;	(aditi_top_down)
	;	(aditi_bottom_up)
	.

%-----------------------------------------------------------------------------%
%
% Types
%

	% This is how types are represented.

			% one day we might allow types to take
			% value parameters as well as type parameters.

% type_defn/3 is defined above as a constructor for item/0

:- type type_defn	
	--->	du_type(sym_name, list(type_param), list(constructor),
			maybe(equality_pred)
		)
	;	uu_type(sym_name, list(type_param), list(type))
	;	eqv_type(sym_name, list(type_param), type)
	;	abstract_type(sym_name, list(type_param)).

:- type constructor	
	--->	ctor(
			existq_tvars,
			list(class_constraint),	% existential constraints
			sym_name,
			list(constructor_arg)
		).

:- type constructor_arg	==
		pair(
			maybe(ctor_field_name),
			type
		).

:- type ctor_field_name == sym_name.

	% An equality_pred specifies the name of a user-defined predicate
	% used for equality on a type.  See the chapter on them in the
	% Mercury Language Reference Manual.
:- type equality_pred	==	sym_name.

	% probably type parameters should be variables not terms.
:- type type_param	==	term(tvar_type).

	% Module qualified types are represented as ':'/2 terms.
	% Use type_util:type_to_type_id to convert a type to a qualified
	% type_id and a list of arguments.
	% type_util:construct_type to construct a type from a type_id 
	% and a list of arguments.
:- type (type)		==	term(tvar_type).
:- type type_term	==	term(tvar_type).

:- type tvar_type	--->	type_var.
:- type tvar		==	var(tvar_type).
					% used for type variables
:- type tvarset		==	varset(tvar_type).
					% used for sets of type variables
:- type tsubst		==	map(tvar, type). % used for type substitutions

	% existq_tvars is used to record the set of type variables which are
	% existentially quantified
:- type existq_tvars	==	list(tvar).

	% Types may have arbitrary assertions associated with them
	% (eg. you can define a type which represents sorted lists).
	% Similarly, pred declarations can have assertions attached.
	% The compiler will ignore these assertions - they are intended
	% to be used by other tools, such as the debugger.

:- type condition	
	--->	true
	;	where(term).

%-----------------------------------------------------------------------------%
%
% insts and modes
%

	% This is how instantiatednesses and modes are represented.
	% Note that while we use the normal term data structure to represent 
	% type terms (see above), we need a separate data structure for inst 
	% terms. 

	% The `inst' data type itself is defined in the module `inst.m'.

:- type inst_var_type	--->	inst_var_type.
:- type inst_var	==	var(inst_var_type).
:- type inst_term	==	term(inst_var_type).
:- type inst_varset	==	varset(inst_var_type).

% inst_defn/3 defined above

:- type inst_defn	
	--->	eqv_inst(sym_name, list(inst_var), inst)
	;	abstract_inst(sym_name, list(inst_var)).

	% An `inst_name' is used as a key for the inst_table.
	% It is either a user-defined inst `user_inst(Name, Args)',
	% or some sort of compiler-generated inst, whose name
	% is a representation of it's meaning.
	%
	% For example, `merge_inst(InstA, InstB)' is the name used for the
	% inst that results from merging InstA and InstB using `merge_inst'.
	% Similarly `unify_inst(IsLive, InstA, InstB, IsReal)' is
	% the name for the inst that results from a call to
	% `abstractly_unify_inst(IsLive, InstA, InstB, IsReal)'.
	% And `ground_inst' and `any_inst' are insts that result
	% from unifying an inst with `ground' or `any', respectively.
	% `typed_inst' is an inst with added type information.
	% `typed_ground(Uniq, Type)' a equivalent to
	% `typed_inst(ground(Uniq, no), Type)'.
	% Note that `typed_ground' is a special case of `typed_inst',
	% and `ground_inst' and `any_inst' are special cases of `unify_inst'.
	% The reason for having the special cases is efficiency.
	
:- type inst_name	
	--->	user_inst(sym_name, list(inst))
	;	merge_inst(inst, inst)
	;	unify_inst(is_live, inst, inst, unify_is_real)
	;	ground_inst(inst_name, is_live, uniqueness, unify_is_real)
	;	any_inst(inst_name, is_live, uniqueness, unify_is_real)
	;	shared_inst(inst_name)
	;	mostly_uniq_inst(inst_name)
	;	typed_ground(uniqueness, type)
	;	typed_inst(type, inst_name).

	% Note: `is_live' records liveness in the sense used by
	% mode analysis.  This is not the same thing as the notion of liveness
	% used by code generation.  See compiler/notes/glossary.html.
:- type is_live		--->	live ; dead.

	% Unifications of insts fall into two categories, "real" and "fake".
	% The "real" inst unifications correspond to real unifications,
	% and are not allowed to unify with `clobbered' insts (unless
	% the unification would be `det').
	% Any inst unification which is associated with some code that
	% will actually examine the contents of the variables in question
	% must be "real".  Inst unifications that are not associated with
	% some real code that examines the variables' values are "fake".
	% "Fake" inst unifications are used for procedure calls in implied
	% modes, where the final inst of the var must be computed by
	% unifying its initial inst with the procedure's final inst,
	% so that if you pass a ground var to a procedure whose mode
	% is `free -> list_skeleton', the result is ground, not list_skeleton.
	% But these fake unifications must be allowed to unify with `clobbered'
	% insts. Hence we pass down a flag to `abstractly_unify_inst' which
	% specifies whether or not to allow unifications with clobbered values.

:- type unify_is_real
	--->	real_unify
	;	fake_unify.

% mode_defn/3 defined above

:- type mode_defn	
	--->	eqv_mode(sym_name, list(inst_var), mode).

:- type (mode)		
	--->	((inst) -> (inst))
	;	user_defined_mode(sym_name, list(inst)).

% mode/4 defined above

%-----------------------------------------------------------------------------%
%
% Module system
%

	% This is how module-system declarations (such as imports
	% and exports) are represented.

:- type module_defn	
	--->	module(module_name)
	;	end_module(module_name)

	;	interface
	;	implementation

	;	private_interface
		% This is used internally by the compiler,
		% to identify items which originally
		% came from an implementation section
		% for a module that contains sub-modules;
		% such items need to be exported to the
		% sub-modules.

	;	imported(section)
		% This is used internally by the compiler,
		% to identify declarations which originally
		% came from some other module imported with 
		% a `:- import_module' declaration, and which
		% section the module was imported.
	;	used(section)
		% This is used internally by the compiler,
		% to identify declarations which originally
		% came from some other module and for which
		% all uses must be module qualified. This
		% applies to items from modules imported using
		% `:- use_module', and items from `.opt'
		% and `.int2' files. It also records from which
		% section the module was imported.
	;	opt_imported
		% This is used internally by the compiler,
		% to identify items which originally
		% came from a .opt file.

	;	external(sym_name_specifier)

	;	export(sym_list)
	;	import(sym_list)
	;	use(sym_list)

	;	include_module(list(module_name)).

:- type section
	--->	implementation
	;	interface.

:- type sym_list	
	--->	sym(list(sym_specifier))
	;	pred(list(pred_specifier))
	;	func(list(func_specifier))
	;	cons(list(cons_specifier))
	;	op(list(op_specifier))
	;	adt(list(adt_specifier))
	;	type(list(type_specifier))
	;	module(list(module_specifier)).

:- type sym_specifier	
	--->	sym(sym_name_specifier)
	;	typed_sym(typed_cons_specifier)
	;	pred(pred_specifier)
	;	func(func_specifier)
	;	cons(cons_specifier)
	;	op(op_specifier)
	;	adt(adt_specifier)
	;	type(type_specifier)
	;	module(module_specifier).
:- type pred_specifier	
	--->	sym(sym_name_specifier)
	;	name_args(sym_name, list(type)).
:- type func_specifier	==	cons_specifier.
:- type cons_specifier	
	--->	sym(sym_name_specifier)
	;	typed(typed_cons_specifier).
:- type typed_cons_specifier 
	--->	name_args(sym_name, list(type))
	;	name_res(sym_name_specifier, type)
	;	name_args_res(sym_name, list(type), type).
:- type adt_specifier	==	sym_name_specifier.
:- type type_specifier	==	sym_name_specifier.
:- type op_specifier	
	--->	sym(sym_name_specifier)
	% operator fixity specifiers not yet implemented
	;	fixity(sym_name_specifier, fixity).
:- type fixity		
	--->	infix 
	; 	prefix 
	; 	postfix 
	; 	binary_prefix 
	; 	binary_postfix.
:- type sym_name_specifier 
	--->	name(sym_name)
	;	name_arity(sym_name, arity).
:- type sym_name 	
	--->	unqualified(string)
	;	qualified(module_specifier, string).
:- type sym_name_and_arity
	--->	sym_name / arity.

:- type module_specifier ==	sym_name.
:- type module_name 	== 	sym_name.
:- type arity		==	int.

	% Describes whether an item can be used without an 
	% explicit module qualifier.
:- type need_qualifier
	--->	must_be_qualified
	;	may_be_unqualified.

	% Convert the foreign code attributes to their source code
	% representations suitable for placing in the attributes list of
	% the pragma (not all attributes have one).
	% In particular, the foreign language attribute needs to be
	% handled separately as it belongs at the start of the pragma.
:- pred attributes_to_strings(pragma_foreign_proc_attributes::in,
		list(string)::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- type pragma_foreign_proc_attributes
	--->	attributes(
			foreign_language 	:: foreign_language,
			may_call_mercury	:: may_call_mercury,
			thread_safe		:: thread_safe,
			tabled_for_io		:: tabled_for_io
		).

default_attributes(Language, 
	attributes(Language, may_call_mercury, not_thread_safe, 
		not_tabled_for_io)).

may_call_mercury(Attrs, Attrs ^ may_call_mercury).

thread_safe(Attrs, Attrs ^ thread_safe).

foreign_language(Attrs, Attrs ^ foreign_language).

tabled_for_io(Attrs, Attrs ^ tabled_for_io).

set_may_call_mercury(Attrs0, MayCallMercury, Attrs) :-
	Attrs = Attrs0 ^ may_call_mercury := MayCallMercury.

set_thread_safe(Attrs0, ThreadSafe, Attrs) :-
	Attrs = Attrs0 ^ thread_safe := ThreadSafe.

set_foreign_language(Attrs0, ForeignLanguage, Attrs) :-
	Attrs = Attrs0 ^ foreign_language := ForeignLanguage.

set_tabled_for_io(Attrs0, TabledForIo, Attrs) :-
	Attrs = Attrs0 ^ tabled_for_io := TabledForIo.

attributes_to_strings(Attrs, StringList) :-
	% We ignore Lang because it isn't an attribute that you can put
	% in the attribute list -- the foreign language specifier string
	% is at the start of the pragma.
	Attrs = attributes(_Lang, MayCallMercury, ThreadSafe, TabledForIO),
	(
		MayCallMercury = may_call_mercury,
		MayCallMercuryStr = "may_call_mercury"
	;
		MayCallMercury = will_not_call_mercury,
		MayCallMercuryStr = "will_not_call_mercury"
	),
	(
		ThreadSafe = not_thread_safe,
		ThreadSafeStr = "not_thread_safe"
	;
		ThreadSafe = thread_safe,
		ThreadSafeStr = "thread_safe"
	),
	(
		TabledForIO = tabled_for_io,
		TabledForIOStr = "tabled_for_io"
	;
		TabledForIO = not_tabled_for_io,
		TabledForIOStr = "not_tabled_for_io"
	),
	StringList = [MayCallMercuryStr, ThreadSafeStr, TabledForIOStr].

%-----------------------------------------------------------------------------%
