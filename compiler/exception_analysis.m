%-----------------------------------------------------------------------------%
% Copyright (C) 2004 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% 
% File    : exception_analysis.m
% Author  : juliensf
%
% This module performs an exception tracing analysis.  The aim is to
% annotate the HLDS with information about whether each procedure
% might or will not throw an exception.
% 
% This information can be useful to the compiler when applying
% certain types of optimization.
%
% After running the analysis the exception behaviour of each procedure
% is one of:
%
%	(1) will_not_throw_exception
%	(2) may_throw_an_exception
%	(3) conditional
%
% (1) guarantees that, for all inputs, the procedure will not throw an
%     exception.
%
% (2) means that a call to that procedure might result in an exception
%     being thrown for at least some inputs. 
%	
%     We distinguish between two kinds of exception.  Those that
%     are ultimately a result of a call to exception.throw/1, which
%     we refer to as "user exceptions" and those that result from a 
%     unification or comparison where one of the types involved has 
%     a user-defined equality/comparison predicate that throws
%     an exception.  We refer to the latter kind, as "type exceptions".	
%
%     This means that for some polymorphic procedures we cannot
%     say what will happen until we know the values of the type variables.
%     And so we have ... 
%
% (3) means that the exception status of the procedure is dependent upon the
%     values of some higher-order variables, or the values of some type
%     variables or both.  This means that we cannot say anything definite
%     about the procedure but for calls to the procedure where have the
%     necessary information we can say what will happen. 
%
% In the event that we cannot determine the exception status we just assume
% the worst and mark the procedure as maybe throwing a user exception.
%
% For procedures that are defined using the FFI we currently assume that if a
% procedure will not make calls back to Mercury then it cannot throw
% a Mercury exception; if it does make calls to Mercury then it might
% throw an exception.
%
% NOTE: Some backends, e.g the Java backend, use exceptions in the target 
%       language for various things but we're not interested in that here.
%
% TODO:
%	- higher order stuff
%	- annotations for foreign_procs
% 	- use intermodule-analysis framework
%	- check what user-defined equality and comparison preds
%	  actually do rather than assuming that they always
%	  may throw exceptions.
%	- handle existential and solver types - currently we just
%	  assume that any call to unify or compare for these types
%	  might result in an exception being thrown. 
%
% XXX We need to be a bit careful with transformations like tabling that
% might add calls to exception.throw - at the moment this isn't a problem
% because exception analysis takes place after the tabling transformation.
%
%----------------------------------------------------------------------------%

:- module transform_hlds.exception_analysis.

:- interface.

:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.

:- import_module io.

	% Perform the exception analysis on a module.
	%
:- pred exception_analysis.process_module(module_info::in, module_info::out,
	io::di, io::uo) is det.

	% Write out the exception pragmas for this module.
	%
:- pred exception_analysis.write_pragma_exceptions(module_info::in,
	exception_info::in, pred_id::in, io::di, io::uo) is det.

%----------------------------------------------------------------------------%
%----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.mode_util.
:- import_module check_hlds.type_util.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_pred.
:- import_module hlds.make_hlds.
:- import_module hlds.passes_aux.
:- import_module hlds.special_pred.
:- import_module libs.globals.
:- import_module libs.options.
:- import_module parse_tree.error_util.
:- import_module parse_tree.mercury_to_mercury.
:- import_module parse_tree.modules.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_out.
:- import_module parse_tree.prog_util.
:- import_module transform_hlds.dependency_graph.

:- import_module bool, list, map, set, std_util, string, term, term_io, varset.

%----------------------------------------------------------------------------%
%
% Perform exception analysis on a module. 
%

exception_analysis.process_module(!Module, !IO) :-
	module_info_ensure_dependency_info(!Module),
	module_info_dependency_info(!.Module, DepInfo),
	hlds_dependency_info_get_dependency_ordering(DepInfo, SCCs),
	list.foldl(process_scc, SCCs, !Module),
	globals.io_lookup_bool_option(make_optimization_interface,
		MakeOptInt, !IO),
	( if	MakeOptInt = yes
	  then	exception_analysis.make_opt_int(!.Module, !IO)
	  else	true
	).	

%----------------------------------------------------------------------------%
% 
% Perform exception analysis on a SCC. 
%

:- type scc == list(pred_proc_id).

:- type proc_results == list(proc_result).

:- type proc_result 
	---> proc_result(
			ppid   :: pred_proc_id,
 
			status :: exception_status,
					% Exception status of this procedure
					% not counting any input from
					% (mutually-)recursive inputs.	  
			rec_calls :: type_status
					% The collective type status of the 
					% types of the terms that are arguments
					% of (mutually-)recursive calls. 
	).

:- pred process_scc(scc::in, module_info::in, module_info::out) is det.

process_scc(SCC, !Module) :-
	ProcResults = check_procs_for_exceptions(SCC, !.Module),
	% 
	% The `Results' above are the results of analysing each
	% individual procedure in the SCC - we now have to combine
	% them in a meaningful way.   
	%
	Status = combine_individual_proc_results(ProcResults),
	%
	% Update the exception info. with information about this
	% SCC.
	%
	module_info_exception_info(!.Module, ExceptionInfo0),
	Update = (pred(PPId::in, Info0::in, Info::out) is det :-
		Info = Info0 ^ elem(PPId) := Status
	),
	list.foldl(Update, SCC, ExceptionInfo0, ExceptionInfo),
	module_info_set_exception_info(ExceptionInfo, !Module).	

	% Check each procedure in the SCC individually.
	%
:- func check_procs_for_exceptions(scc, module_info) = proc_results.

check_procs_for_exceptions(SCC, Module) = Result :-
	list.foldl(check_proc_for_exceptions(SCC, Module), SCC, [], Result).

	% Examine how the procedures interact with other procedures that
	% are mutually-recursive to them.
	%
:- func combine_individual_proc_results(proc_results) = exception_status.

combine_individual_proc_results([]) = _ :-
	unexpected(this_file, "Empty SCC during exception analysis.").
combine_individual_proc_results(ProcResults @ [_|_]) = SCC_Result :- 
	(
		% If none of the procedures may throw an exception or 
		% are conditional then the SCC cannot throw an exception
		% either.
		all [ProcResult] list.member(ProcResult, ProcResults) =>
			ProcResult ^ status = will_not_throw	
	->
		SCC_Result = will_not_throw	
	;
		% If none of the procedures may throw an exception but
		% at least one of them is conditional then somewhere in
		% the SCC there is a call to unify or compare that may
		% rely on the types of the polymorphically typed
		% arguments.  
		%
		% We need to check that any recursive calls
		% do not introduce types that might have user-defined
		% equality or comparison predicate that throw
		% exceptions. 
		all [EResult] list.member(EResult, ProcResults) =>
			EResult ^ status \= may_throw(_),
		some [CResult] (
			list.member(CResult, ProcResults),
			CResult ^ status = conditional
		)
	->
		SCC_Result = handle_mixed_conditional_scc(ProcResults)
	;
		% If none of the procedures can throw a user_exception
		% but one or more can throw a type_exception then mark
		% the SCC as maybe throwing a type_exception.
		all [EResult] list.member(EResult, ProcResults) =>
			EResult ^ status \= may_throw(user_exception),
		some [TResult] (
			list.member(TResult, ProcResults),
			TResult ^ status = may_throw(type_exception)
		)
	->
		SCC_Result = may_throw(type_exception)
	;
		SCC_Result = may_throw(user_exception)
	).

%----------------------------------------------------------------------------%
%
% Process individual procedures.
% 

:- pred check_proc_for_exceptions(scc::in, module_info::in,
	pred_proc_id::in, proc_results::in, proc_results::out) is det.

check_proc_for_exceptions(SCC, Module, PPId, !Results) :-
	module_info_pred_proc_info(Module, PPId, _, ProcInfo),
	proc_info_goal(ProcInfo, Body),
	proc_info_vartypes(ProcInfo, VarTypes),
	Result0 = proc_result(PPId, will_not_throw, type_will_not_throw),
	check_goal_for_exceptions(SCC, Module, VarTypes, Body, Result0, Result),
	list.cons(Result, !Results).

:- pred check_goal_for_exceptions(scc::in, module_info::in, vartypes::in,
	hlds_goal::in, proc_result::in, proc_result::out) is det.  

check_goal_for_exceptions(SCC, Module, VarTypes, Goal - GoalInfo,
		!Result) :-	
	( goal_info_get_determinism(GoalInfo, erroneous) ->
		!:Result = !.Result ^ status := may_throw(user_exception)
	;
		check_goal_for_exceptions_2(SCC, Module, VarTypes, Goal,
			!Result)
	).	

:- pred check_goal_for_exceptions_2(scc::in, module_info::in, vartypes::in,
	hlds_goal_expr::in, proc_result::in, proc_result::out) is det.

check_goal_for_exceptions_2(_, _, _, unify(_, _, _, Kind, _), !Result) :-
	( Kind = complicated_unify(_, _, _) ->
		unexpected(this_file,
			"complicated unify during exception analysis.")	
	;
		true
	).
check_goal_for_exceptions_2(SCC, Module, VarTypes, 
		call(CallPredId, CallProcId, CallArgs, _, _, _), !Result) :-
	CallPPId = proc(CallPredId, CallProcId),	
	module_info_pred_info(Module, CallPredId, CallPredInfo),
	(
		% Handle (mutually-)recursive calls.
		list.member(CallPPId, SCC) 
	->
		Types = list.map((func(Var) = VarTypes ^ det_elem(Var)),
			CallArgs),
		TypeStatus = check_types(Module, Types),
		combine_type_status(TypeStatus, !.Result ^ rec_calls,
			NewTypeStatus),
		!:Result = !.Result ^ rec_calls := NewTypeStatus 
	; 
		pred_info_is_builtin(CallPredInfo) 
	->
		% Builtins won't throw exceptions.
		true	
	;
		% Handle unify and compare.
		(
			ModuleName = pred_info_module(CallPredInfo),
			any_mercury_builtin_module(ModuleName),
			Name = pred_info_name(CallPredInfo),
			Arity = pred_info_arity(CallPredInfo),
			( SpecialPredId = compare
			; SpecialPredId = unify ),
			special_pred_name_arity(SpecialPredId, Name,
				Arity)
		;
			pred_info_get_maybe_special_pred(CallPredInfo,
				MaybeSpecial),
			MaybeSpecial = yes(SpecialPredId - _),
			( SpecialPredId = compare
			; SpecialPredId = unify )
		)	
	->
		% For unification/comparison the exception status depends
		% upon the the types of the arguments.  In particular
		% whether some component of that type has a user-defined
		% equality/comparison predicate that throws an exception.
		check_vars(Module, VarTypes, CallArgs, !Result) 
	;
		check_nonrecursive_call(Module, VarTypes, CallPPId, CallArgs,
			!Result)
	).
check_goal_for_exceptions_2(_, _, _, generic_call(_,_,_,_), !Result) :-
	!:Result = !.Result ^ status := may_throw(user_exception).
check_goal_for_exceptions_2(SCC, Module, VarTypes, not(Goal), !Result) :-
	check_goal_for_exceptions(SCC, Module, VarTypes, Goal, !Result).
check_goal_for_exceptions_2(SCC, Module, VarTypes, some(_, _, Goal),
		!Result) :-
	check_goal_for_exceptions(SCC, Module, VarTypes, Goal, !Result).

	% XXX We could provide  annotations for foreign procs here.
	% Currently we only consider foreign_procs that do not call Mercury
	% as not throwing exceptions.
check_goal_for_exceptions_2(_, _, _,
		foreign_proc(Attributes, _, _, _, _, _), !Result) :-
	( if 	may_call_mercury(Attributes) = may_call_mercury
	  then	!:Result = !.Result ^ status := may_throw(user_exception)
	  else	true
	).
check_goal_for_exceptions_2(_, _, _, shorthand(_), _, _) :-
	unexpected(this_file,
		"shorthand goal encountered during exception analysis.").
check_goal_for_exceptions_2(SCC, Module, VarTypes, switch(_, _, Cases),
		!Result) :-
	Goals = list.map((func(case(_, Goal)) = Goal), Cases),
	check_goals_for_exceptions(SCC, Module, VarTypes, Goals, !Result).
check_goal_for_exceptions_2(SCC, Module, VarTypes, 
		if_then_else(_, If, Then, Else), !Result) :-
	check_goals_for_exceptions(SCC, Module, VarTypes, [If, Then, Else],
		!Result). 	
check_goal_for_exceptions_2(SCC, Module, VarTypes, disj(Goals), !Result) :-
	check_goals_for_exceptions(SCC, Module, VarTypes, Goals, !Result).
check_goal_for_exceptions_2(SCC, Module, VarTypes, par_conj(Goals), !Result) :-
	check_goals_for_exceptions(SCC, Module, VarTypes, Goals, !Result).
check_goal_for_exceptions_2(SCC, Module, VarTypes, conj(Goals), !Result) :-
	check_goals_for_exceptions(SCC, Module, VarTypes, Goals, !Result).

:- pred check_goals_for_exceptions(scc::in, module_info::in, vartypes::in,
	hlds_goals::in, proc_result::in, proc_result::out) is det.

check_goals_for_exceptions(_, _, _, [], !Result).
check_goals_for_exceptions(SCC, Module, VarTypes, [ Goal | Goals ], !Result) :-
	check_goal_for_exceptions(SCC, Module, VarTypes, Goal, !Result),
	%
	% We can stop searching if we find a user exception.  However if we
	% find a type exception then we still need to check that there is 
	% not a user exception somewhere in the rest of the SCC.
	%
	( if	!.Result ^ status = may_throw(user_exception)
	  then	true
	  else	check_goals_for_exceptions(SCC, Module, VarTypes, Goals,
			!Result)
	).

%----------------------------------------------------------------------------%

:- pred update_proc_result(exception_status::in, proc_result::in,
	proc_result::out) is det.

update_proc_result(CurrentStatus, !Result) :-
	OldStatus = !.Result ^ status,
	NewStatus = combine_exception_status(CurrentStatus, OldStatus),
	!:Result  = !.Result ^ status := NewStatus.	

:- func combine_exception_status(exception_status, exception_status) 
	= exception_status.

combine_exception_status(will_not_throw, Y) = Y.
combine_exception_status(X @ may_throw(user_exception), _) = X.
combine_exception_status(X @ may_throw(type_exception), will_not_throw) = X.
combine_exception_status(X @ may_throw(type_exception), conditional) = X.
combine_exception_status(may_throw(type_exception), Y @ may_throw(_)) = Y.
combine_exception_status(conditional, conditional) = conditional.
combine_exception_status(conditional, will_not_throw) = conditional.
combine_exception_status(conditional, Y @ may_throw(_)) = Y.

%----------------------------------------------------------------------------%
% 
% Extra procedures for handling calls.
%

:- pred check_nonrecursive_call(module_info::in, vartypes::in,
	pred_proc_id::in, prog_vars::in, proc_result::in,
	proc_result::out) is det.

check_nonrecursive_call(Module, VarTypes, PPId, Args, !Result) :-
	module_info_exception_info(Module, ExceptionInfo),
	( map.search(ExceptionInfo, PPId, CalleeExceptionStatus) ->
		(
			CalleeExceptionStatus = will_not_throw
		;
			CalleeExceptionStatus = may_throw(ExceptionType),
			update_proc_result(may_throw(ExceptionType), !Result)
		;
			CalleeExceptionStatus = conditional,
			check_vars(Module, VarTypes, Args, !Result)	
		)
	;
		% If we do not have any information about the callee procedure
		% then assume that it might throw an exception. 
		update_proc_result(may_throw(user_exception), !Result)
	).

:- pred check_vars(module_info::in, vartypes::in, prog_vars::in, 
	proc_result::in, proc_result::out) is det.

check_vars(Module, VarTypes, Vars, !Result) :- 
	Types = list.map((func(Var) = VarTypes ^ det_elem(Var)), Vars),
	TypeStatus = check_types(Module, Types),
	(
		TypeStatus = type_will_not_throw
	;
		TypeStatus = type_may_throw,
		update_proc_result(may_throw(type_exception), !Result)
	;	
		TypeStatus = type_conditional,
		update_proc_result(conditional, !Result)
	).

%----------------------------------------------------------------------------%
%
% Predicates for checking mixed SCCs. 
%
% A "mixed SCC" is one where at least one of the procedures in the SCC is
% known not to throw an exception, at least one of them is conditional
% and none of them may throw an exception (of either sort).
%
% In order to determine the status of such a SCC we also need to take the
% affect of the recursive calls into account.  This is because calls to a
% conditional procedure from a procedure that is mutually recursive to it may 
% introduce types that could cause a type_exception to be thrown.  
%
% We currently assume that if these types are introduced
% somewhere in the SCC then they may be propagated around the entire
% SCC - hence if a part of the SCC is conditional we need to make
% sure other parts don't supply it with input whose types may have
% user-defined equality/comparison predicates. 
%
% NOTE: It is possible to write rather contrived programs that can 
% exhibit rather strange behaviour which is why all this is necessary. 
	
:- func handle_mixed_conditional_scc(proc_results) = exception_status. 

handle_mixed_conditional_scc(Results) = 
	(
		all [TypeStatus] list.member(Result, Results) =>
			Result ^ rec_calls \= type_may_throw
	->
		conditional
	;
		% Somewhere a type that causes an exception is being
		% passed around the SCC via one or more of the recursive
		% calls.
		may_throw(type_exception)
	).

%----------------------------------------------------------------------------%
% 
% Stuff for processing types.
%

% This is used in the analysis of calls to polymorphic procedures.
%
% By saying a `type can throw an exception' we mean that an exception
% might be thrown as a result of a unification or comparison involving
% the type because it has a user-defined equality/comparison predicate
% that may throw an exception. 
%
% XXX We don't actually need to examine all the types, just those
% that are potentially going to be involved in unification/comparisons.
% At the moment we don't keep track of that information so the current
% procedure is as follows:
%
% Examine the functor and then recursively examine the arguments.
% * If everything will not throw then the type will not throw
% * If at least one of the types may_throw then the type will throw
% * If at least one of the types is conditional  and none of them throw then
%   the type is conditional.

:- type type_status
	--->	type_will_not_throw
			% This type does not have user-defined equality 
			% or comparison predicates.
			% XXX (Or it has ones that are known not to throw
			%      exceptions).
			
	;	type_may_throw
			% This type has a user-defined equality or comparison
			% predicate that is known to throw an exception.
				
	;	type_conditional.
			% This type is polymorphic.  We cannot say anything about
			% it until we know the values of the type-variables.	

	% Return the collective type status of a list of types.
	%
:- func check_types(module_info, list((type))) = type_status.

check_types(Module, Types) = Status :-
	list.foldl(check_type(Module), Types, type_will_not_throw, Status).

:- pred check_type(module_info::in, (type)::in, type_status::in,
	type_status::out) is det.

check_type(Module, Type, !Status) :-
	combine_type_status(check_type(Module, Type), !Status).	

:- pred combine_type_status(type_status::in, type_status::in,
	type_status::out) is det.

combine_type_status(type_will_not_throw, type_will_not_throw,
		type_will_not_throw).
combine_type_status(type_will_not_throw, type_conditional, type_conditional).
combine_type_status(type_will_not_throw, type_may_throw, type_may_throw).
combine_type_status(type_conditional, type_will_not_throw, type_conditional).
combine_type_status(type_conditional, type_conditional, type_conditional).
combine_type_status(type_conditional, type_may_throw, type_may_throw).
combine_type_status(type_may_throw, _, type_may_throw).

	% Return the type status of an individual type.
	%
:- func check_type(module_info, (type)) = type_status.

check_type(Module, Type) = Status :-
	( 
		( type_util.is_solver_type(Module, Type)
	  	; type_util.is_existq_type(Module, Type))
	 ->
		% XXX At the moment we just assume that existential
		% types and solver types result in a type exception
		% being thrown.
		Status = type_may_throw
	;	
		TypeCategory = type_util.classify_type(Module, Type),
		Status = check_type_2(Module, Type, TypeCategory)
	).

:- func check_type_2(module_info, (type), type_category) = type_status.

check_type_2(_, _, int_type) = type_will_not_throw.
check_type_2(_, _, char_type) = type_will_not_throw.
check_type_2(_, _, str_type) = type_will_not_throw.
check_type_2(_, _, float_type) = type_will_not_throw.
check_type_2(_, _, higher_order_type) = type_will_not_throw.
check_type_2(_, _, type_info_type) = type_will_not_throw.
check_type_2(_, _, type_ctor_info_type) = type_will_not_throw.
check_type_2(_, _, typeclass_info_type) = type_will_not_throw.
check_type_2(_, _, base_typeclass_info_type) = type_will_not_throw.
check_type_2(_, _, void_type) = type_will_not_throw.

check_type_2(_, _, variable_type) = type_conditional.

check_type_2(Module, Type, tuple_type) = check_user_type(Module, Type).
check_type_2(Module, Type, enum_type)  = check_user_type(Module, Type). 
check_type_2(Module, Type, user_ctor_type) = check_user_type(Module, Type). 

:- func check_user_type(module_info, (type)) = type_status.

check_user_type(Module, Type) = Status :-
	( type_to_ctor_and_args(Type, _TypeCtor, Args) ->
		( 
			type_has_user_defined_equality_pred(Module, Type,
				_UnifyCompare)
		->
			% XXX We can do better than this by examining
			% what these preds actually do.  Something
			% similar needs to be sorted out for termination
			% analysis as well, so we'll wait until that is
			% done.
			Status = type_may_throw
		;
			Status = check_types(Module, Args)
		)
	
	;
		unexpected(this_file, "Unable to get ctor and args.")
	). 

%----------------------------------------------------------------------------%
%
% Stuff for intermodule optimization.
% 

:- pred exception_analysis.make_opt_int(module_info::in, io::di, io::uo) is det.

exception_analysis.make_opt_int(Module, !IO) :-
	module_info_name(Module, ModuleName),
	module_name_to_file_name(ModuleName, ".opt.tmp", no, OptFileName, !IO),
	globals.io_lookup_bool_option(verbose, Verbose, !IO),
	maybe_write_string(Verbose,
		"% Appending exceptions pragmas to `", !IO),
	maybe_write_string(Verbose, OptFileName, !IO),
	maybe_write_string(Verbose, "'...", !IO),
	maybe_flush_output(Verbose, !IO),
	io.open_append(OptFileName, OptFileRes, !IO),
	(
		OptFileRes = ok(OptFile),
		io.set_output_stream(OptFile, OldStream, !IO),
		module_info_exception_info(Module, ExceptionInfo), 
		module_info_predids(Module, PredIds),	
		list.foldl(write_pragma_exceptions(Module, ExceptionInfo),
			PredIds, !IO),
		io.set_output_stream(OldStream, _, !IO),
		io.close_output(OptFile, !IO),
		maybe_write_string(Verbose, " done.\n", !IO)
	;
		OptFileRes = error(IOError),
		maybe_write_string(Verbose, " failed!\n", !IO),
		io.error_message(IOError, IOErrorMessage),
		io.write_strings(["Error opening file `",
			OptFileName, "' for output: ", IOErrorMessage], !IO),
		io.set_exit_status(1, !IO)
	).	

write_pragma_exceptions(Module, ExceptionInfo, PredId, !IO) :-
	module_info_pred_info(Module, PredId, PredInfo),
	pred_info_import_status(PredInfo, ImportStatus),
	(	
		( ImportStatus = exported 
		; ImportStatus = opt_exported 
		),
		not is_unify_or_compare_pred(PredInfo),
		module_info_type_spec_info(Module, TypeSpecInfo),
		TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
		not set.member(PredId, TypeSpecForcePreds),
		%
		% XXX Writing out pragmas for the automatically
		% generated class instance methods causes the
		% compiler to abort when it reads them back in.
		%
		pred_info_get_markers(PredInfo, Markers),
		not check_marker(Markers, class_instance_method),
		not check_marker(Markers, named_class_instance_method)
	->
		ModuleName = pred_info_module(PredInfo),
		Name       = pred_info_name(PredInfo),
		Arity      = pred_info_arity(PredInfo),
		PredOrFunc = pred_info_is_pred_or_func(PredInfo),
		ProcIds    = pred_info_procids(PredInfo),
		%
		% XXX The termination analyser outputs pragmas even if
		% it doesn't have any information - should we be doing
		% this?
		%
		list.foldl((pred(ProcId::in, !.IO::di, !:IO::uo) is det :-
			proc_id_to_int(ProcId, ModeNum),
			( 
				map.search(ExceptionInfo, proc(PredId, ProcId),
					Status)
			->
				mercury_output_pragma_exceptions(PredOrFunc, 
					qualified(ModuleName, Name), Arity,
					ModeNum, Status, !IO)
			;
				true
			)), ProcIds, !IO)
	;
		true
	). 			

%----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "exception_analysis.m".

%----------------------------------------------------------------------------%
:- end_module exception_analysis.
%----------------------------------------------------------------------------%