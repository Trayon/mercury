%-----------------------------------------------------------------------------
%
% Copyright (C) 1997 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------
%
% term_util.m
% Main author: crs.
% 
% This file contains utilities that are used by termination analysis.
%
%-----------------------------------------------------------------------------

:- module term_util.

:- interface.

:- import_module list, bool, bag, int, hlds_module, hlds_pred, hlds_data.
:- import_module term_errors, io, hlds_goal, term, prog_data.

	% term(TermConstant, Terminates, UsedArgs, MaybeError)
	%   TermConstant	See description below
	%   Terminates		See description below
	%   UsedArgs		This list of bool, when set, has a 1:1 
	%   			  correspondance with the arguments of the
	%   			  proc. It stores whether the argument is
	%   			  used in producing the output arguments.  
	%   MaybeError		If the analysis fails to prove termination
	%   			  of a procedure, then this value indicates
	%   			  the reason that the analysis failed.
:- type termination 
	--->	 term(term_util__constant, terminates, maybe(list(bool)),
		maybe(term_errors__error)).

% term_util__constant defines the level by which a procedures arguments
% grow or shrink.  It is used to determine the termination properties of a 
% predicate.  The termination constant defines the relative sizes of input
% and output arguments in the following equation:
% | input arguments | + constant >= | output arguments |
% where | | represents a semilinear norm.
:- type term_util__constant
	--->	inf(term_errors__error)
				% could not find a limiting value
				% The error indicates why the analysis was
				% unable to set the termination constant.
	;	not_set		% Has not been set yet.  After 
				% term_pass1:proc_inequalities has been
				% run, the constant should be set for all
				% the procedures in the module.  Failure to
				% set the constant would indicate a
				% programming error.
	;	set(int).	% Termination constant has been set to int

:- type terminates 	
	---> 	dont_know	% cannot prove that the proc terminates
	;	not_set		% the initial value of terminates for each proc
				% the termination analysis uses the fact
				% that if a proc is called, whose
				% termination is not_set, then the call is
				% mutually recursive (If the call is not
				% mutually recursive, then the analysis
				% will have already processed the
				% procedure, and would have set the
				% constant). term_pass2:termination should
				% set the terminates value of all
				% procedures.  Failure to do so indicates a
				% software error.
	;	yes.		% YES  this procedure terminates for all 
				% possible inputs.

% the functor algorithm defines how a weight is assigned to each functor.
% XXX
% Currently this value is set manually in the code.  I plan to add an
% option to allow the functor_algorithm to be set from the command line.
:- type functor_algorithm
	--->	simple		% simple just assigns all functors a norm of 1
	;	total.		% all functors have a norm = arity of functor

:- type term_util__result(T) 
	--->	ok
	;	error(T).

:- type unify_info == functor_algorithm.

% This predicate is used to assign a norm (integer) to a functor, depending
% on its type.
:- pred functor_norm(functor_algorithm, cons_id, module_info,  int).
:- mode functor_norm(in, in, in, out) is det.

% This predicate should be called whenever a procedure needs its termination
% set to dont_know.  This predicate checks to see whether the termination
% is already set to dont_know, and if so it does nothing.  If the
% termination is set to yes, or not_set, it changes the termination to
% dont_know, and checks whether a 
% check_termination pragma has been defined for this predicate, and if so,
% this outputs a useful error message.
:- pred do_ppid_check_terminates(list(pred_proc_id), term_errors__error, 
	module_info, module_info, io__state, io__state).
:- mode do_ppid_check_terminates(in, in, in, out, di, uo) is det.

%  Used to create lists of boolean values, which are used for used_args.
%  make_bool_list(HeadVars, BoolIn, BoolOut) creates a bool list which is 
%  (length(HeadVars) - length(BoolIn)) no's followed by BoolIn.  This is
%  used to set the used args for compiler generated preds.  The no's at the
%  start are because the Type infos are not used. length(BoolIn) should
%  equal the arity of the predicate, and the difference in length between
%  the HeadVars of the procedure and the arity of the predicate are the
%  number of type infos. 
:- pred term_util__make_bool_list(list(_T), list(bool), list(bool)).
:- mode term_util__make_bool_list(in, in, out) is det.

% This predicate partitions the arguments of a call into a list of input
% variables and a list of output variables,
% XXX most (all) places that use this predicate immediatly use
% bag__from_list to change the output lists into bags.  Therefore this
% predicate should output bags directly.
:- pred partition_call_args(module_info, list(mode), list(var), list(var),
	list(var)).
:- mode partition_call_args(in, in, in, out, out) is det.

% Removes variables from the InVarBag that are not used in the call.
% remove_unused_args(InVarBag0, VarList, BoolList, InVarBag)
% VarList and BoolList are corresponding lists.  Any variable in VarList
% that has a 'no' in the corresponding place in the BoolList is removed
% from InVarBag.
:- pred remove_unused_args(bag(var), list(var), list(bool), bag(var)).
:- mode remove_unused_args(in, in, in, out) is det.

% given a list of pred_proc_ids, this predicate sets the termination
% constant of them all to the constant that is passed to it.
:- pred set_pred_proc_ids_const(list(pred_proc_id), term_util__constant,
	module_info, module_info).
:- mode set_pred_proc_ids_const(in, in, in, out) is det.

% given a list of pred_proc_ids, this predicate sets the error and
% terminates value of them all to the values that are passed to the
% predicate.
:- pred set_pred_proc_ids_terminates(list(pred_proc_id), terminates,
	maybe(term_errors__error), module_info, module_info).
:- mode set_pred_proc_ids_terminates(in, in, in, in, out) is det.

% Fails if one or more variables in the list are higher order
:- pred check_horder_args(list(var), map(var, type)).  
:- mode check_horder_args(in, in) is semidet.	

% given a list of variables from a unification, this predicate divides the
% list into a bag of input variables, and a bag of output variables.
:- pred split_unification_vars(list(var), list(uni_mode), module_info,
	bag(var), bag(var)).
:- mode split_unification_vars(in, in, in, out, out) is det.

:- implementation.

:- import_module map, std_util, require, mode_util, prog_out, type_util.

% given a list of variables from a unification, this predicate divides the
% list into a bag of input variables, and a bag of output variables.
split_unification_vars([], Modes, _ModuleInfo, Vars, Vars) :-
	bag__init(Vars),
	( Modes = [] ->
		true
	;
		error("term_util:split_unification_vars: Unmatched Variables")
	).
split_unification_vars([Arg | Args], Modes, ModuleInfo,
		InVars, OutVars):-
	( Modes = [UniMode | UniModes] ->
		split_unification_vars(Args, UniModes, ModuleInfo,
			InVars0, OutVars0),
		UniMode = ((_VarInit - ArgInit) -> (_VarFinal - ArgFinal)),
		( % if
			inst_is_bound(ModuleInfo, ArgInit) 
		->
			% Variable is an input variable
			bag__insert(InVars0, Arg, InVars),
			OutVars = OutVars0
		; % else if
			inst_is_free(ModuleInfo, ArgInit),
			inst_is_bound(ModuleInfo, ArgFinal) 
		->
			% Variable is an output variable
			InVars = InVars0,
			bag__insert(OutVars0, Arg, OutVars)
		; % else
			InVars = InVars0,
			OutVars = OutVars0
		)
	;
		error("term_util__split_unification_vars: Unmatched Variables")
	).

check_horder_args([], _).
check_horder_args([Arg | Args], VarType) :-
	map__lookup(VarType, Arg, Type),
	\+ type_is_higher_order(Type, _, _),
	check_horder_args(Args, VarType).

set_pred_proc_ids_const([], _Const, Module, Module).
set_pred_proc_ids_const([PPId | PPIds], Const, Module0, Module) :-
	PPId = proc(PredId, ProcId),
	module_info_preds(Module0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo0),
	pred_info_procedures(PredInfo0, ProcTable0),
	map__lookup(ProcTable0, ProcId, ProcInfo0),
	proc_info_termination(ProcInfo0, Termination0),

	Termination0 = term(_Const, Term, UsedArgs, MaybeError),
	Termination = term(Const, Term, UsedArgs, MaybeError),

	proc_info_set_termination(ProcInfo0, Termination, ProcInfo),
	map__det_update(ProcTable0, ProcId, ProcInfo, ProcTable),
	pred_info_set_procedures(PredInfo0, ProcTable, PredInfo),
	map__det_update(PredTable0, PredId, PredInfo, PredTable),
	module_info_set_preds(Module0, PredTable, Module1),
	set_pred_proc_ids_const(PPIds, Const, Module1, Module).

set_pred_proc_ids_terminates([], _Terminates, _, Module, Module).
set_pred_proc_ids_terminates([PPId | PPIds], Terminates, MaybeError, 
		Module0, Module) :-
	PPId = proc(PredId, ProcId),
	module_info_preds(Module0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo0),
	pred_info_procedures(PredInfo0, ProcTable0),
	map__lookup(ProcTable0, ProcId, ProcInfo0),
	proc_info_termination(ProcInfo0, Termination0),

	Termination0 = term(Const, _Terminates, UsedArgs, _),
	Termination = term(Const, Terminates, UsedArgs, MaybeError),

	proc_info_set_termination(ProcInfo0, Termination, ProcInfo),
	map__det_update(ProcTable0, ProcId, ProcInfo, ProcTable),
	pred_info_set_procedures(PredInfo0, ProcTable, PredInfo),
	map__det_update(PredTable0, PredId, PredInfo, PredTable),
	module_info_set_preds(Module0, PredTable, Module1),
	set_pred_proc_ids_terminates(PPIds, Terminates, MaybeError, 
		Module1, Module).

remove_unused_args(Vars, [], [], Vars).
remove_unused_args(Vars, [], [_X | _Xs], Vars) :-
	error("Unmatched Vars in term_util:remove_unused_args").
remove_unused_args(Vars, [_X | _Xs], [], Vars) :-
	error("Unmatched Vars in term_util__remove_unused_args").
remove_unused_args(Vars0, [ Arg | Args ], [ UsedVar | UsedVars ], Vars) :-
	( UsedVar = yes ->
		% the var is used, so leave it
		remove_unused_args(Vars0, Args, UsedVars, Vars)
	;
		% the var is not used in producing output vars, so dont 
		% include it as an input var
		% UsedVar=no for all output vars, and bag__remove would
		% fail on all output vars, as they wont be in InVarBag
		bag__delete(Vars0, Arg, Vars1),
		remove_unused_args(Vars1, Args, UsedVars, Vars)
	).

partition_call_args(_, [], [_ | _], _, _) :-
	error("Unmatched variables in term_util:partition_call_args").
partition_call_args(_, [_ | _], [], _, _) :-
	error("Unmatched variables in term_util__partition_call_args").
partition_call_args(_, [], [], [], []).
partition_call_args(ModuleInfo, [ArgMode | ArgModes], [Arg | Args],
		InputArgs, OutputArgs) :-
	partition_call_args(ModuleInfo, ArgModes, Args,
		InputArgs1, OutputArgs1),
	( mode_is_input(ModuleInfo, ArgMode) ->
		InputArgs = [Arg | InputArgs1],
		OutputArgs = OutputArgs1
	; mode_is_output(ModuleInfo, ArgMode) ->
		InputArgs = InputArgs1,
		OutputArgs = [Arg | OutputArgs1]
	;
		InputArgs = InputArgs1,
		OutputArgs = OutputArgs1
	).


term_util__make_bool_list(HeadVars0, Bools, Out) :-
	list__length(Bools, Arity),
	( list__drop(Arity, HeadVars0, HeadVars1) ->
		HeadVars = HeadVars1
	;
		error("Unmatched variables in term_util:make_bool_list")
	),
	term_util__make_bool_list_2(HeadVars, Bools, Out).

:- pred term_util__make_bool_list_2(list(_T), list(bool), list(bool)).
:- mode term_util__make_bool_list_2(in, in, out) is det.

term_util__make_bool_list_2([], Bools, Bools).
term_util__make_bool_list_2([ _ | Vars ], Bools, [no | Out]) :-
	term_util__make_bool_list_2(Vars, Bools, Out).
		
% Although the module info is not used in either of these norms, it could
% be needed for other norms, so it should not be removed.
functor_norm(simple, ConsId, _, Int) :-
	( 
		ConsId = cons(_, Arity),
		Arity \= 0
	->
		Int = 1
	;
		Int = 0
	).
functor_norm(total, ConsId, _Module, Int) :-
	( ConsId = cons(_, Arity) ->
		Int = Arity
	;
		Int = 1
	).

do_ppid_check_terminates([] , _Error, Module, Module) --> [].
do_ppid_check_terminates([ PPId | PPIds ], Error, Module0, Module) --> 
	% look up markers
	{ PPId = proc(PredId, ProcId) },

	{ module_info_preds(Module0, PredTable0) },
	{ map__lookup(PredTable0, PredId, PredInfo0) },
	{ pred_info_procedures(PredInfo0, ProcTable0) },
	{ map__lookup(ProcTable0, ProcId, ProcInfo0) },
	{ proc_info_termination(ProcInfo0, Termination0) },
	{ Termination0 = term(Const, Terminates, UsedArgs, _) },
	( { Terminates = dont_know } ->
		{ Module1 = Module0 }
	;
		{ Termination = term(Const, dont_know, UsedArgs, yes(Error)) },
		{ proc_info_set_termination(ProcInfo0, Termination, ProcInfo)},
		{ map__det_update(ProcTable0, ProcId, ProcInfo, ProcTable) },
		{ pred_info_set_procedures(PredInfo0, ProcTable, PredInfo) },
		{ map__det_update(PredTable0, PredId, PredInfo, PredTable) },
		{ module_info_set_preds(Module0, PredTable, Module1) },
		{ pred_info_get_marker_list(PredInfo, MarkerList) },
		% If a check_terminates pragma exists, print out an error
		% message.
		% Note that this allows the one error to be printed out
		% multiple times.  This is because one error can cause a
		% number of predicates to be non terminating, and if
		% check_terminates is defined on all of the predicates,
		% then the error is printed out for each of them.
		( { list__member(request(check_termination), MarkerList) } ->
			term_errors__output(PredId, ProcId, Module1,
				Success),
			% Success is only no if there was no error
			% defined for this predicate.  As we just set the
			% error, term_errors__output should succeed.
			{ require(unify(Success, yes), "term_util.m: Unexpected value in do_ppid_check_terminates") }
		;
			[]
		)
	),
	do_ppid_check_terminates(PPIds, Error, Module1, Module).

