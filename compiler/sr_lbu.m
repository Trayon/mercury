%-----------------------------------------------------------------------------%
% Copyright (C) 2000-2002,2004 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% module sr_lbu: implements the process of annotating each program point
% 		 with Local Backward Use (LBU) information. 
%	 	 (based on resume-points and forward use information)
% main author: nancy
%
% We annotate each program point within a procedure definition with a set of
% variables which are in so-called Local Backward Use (LBU). A variable is said
% to be in LBU if it may be accessed upon backtracking. 
% This information is computed based on the backtrack-vars,
% and forward use information. 
% The goals requiring special attention are: 
% 	- procedure calls: if the call is nondet, then all the arguments
% 	  of the call are in LBU, as well as all the variables which 
% 	  are instantiated at that program point, and are still used in 
%	  forward execution. (Intuition: if backtracking up to this
% 	  procedure call is needed, then all the values of these forward
%	  use variables must remain the same, as they will be needed after
%	  backtracking. 
% 	- disjunctions, not, switch.  Introduce new local backward
%	  uses. 
% All the other goals simply propagate LBU. 

:- module structure_reuse__sr_lbu.

:- interface.

:- import_module hlds__hlds_module.
:- import_module hlds__hlds_pred. 

	% Precondition: the code must already be annotated with
	% LFU-information. 
:- pred sr_lbu__process_proc(module_info::in,
		proc_info::in, proc_info::out) is det.

%-------------------------------------------------------------------%
%-------------------------------------------------------------------%

:- implementation. 


:- import_module hlds__hlds_goal.
:- import_module hlds__hlds_llds.
:- import_module hlds__instmap. 
:- import_module hlds__passes_aux.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module parse_tree__prog_data.
:- import_module structure_reuse__sr_live.

:- import_module list,map, bool, set, varset.
:- import_module string.
:- import_module std_util, require.

sr_lbu__process_proc(HLDS, ProcInfo0, ProcInfo) :-
	proc_info_goal(ProcInfo0, Goal0),

	% extra info to be caried around for each program point: 
	% 	LBU at previous point
	%	Aliases at previous point 
	% output after each specific goal:
	%	new LBU set, 
	% 	new Alias set

	set__init(Lbu0), 
	annotate_lbu_in_goal(HLDS, ProcInfo0, 
				Lbu0, _Lbu, Goal0, Goal), 

	proc_info_set_goal(ProcInfo0, Goal, ProcInfo).

:- pred annotate_lbu_in_goal(module_info, proc_info, 
			set(prog_var), set(prog_var), 
			hlds_goal, hlds_goal).
:- mode annotate_lbu_in_goal(in, in, in, out, in, out) is det.


annotate_lbu_in_goal(HLDS, ProcInfo, 
		Lbu0, Lbu, TopGoal0, TopGoal):-

	% incorporate the fresh resume_vars into the Lbu-set
	TopGoal0 = Expr0 - Info0,
	info_get_backtrack_vars(Info0, RESUME_VARS), 
	set__union(Lbu0, RESUME_VARS, Lbu_01),
	(
		%%%%%%%%%%%%%%%%%%%
		% (1) conjunction %
		%%%%%%%%%%%%%%%%%%%
		Expr0 = conj(Goals0)
	->
		annotate_lbu_in_conj(HLDS, ProcInfo, Lbu_01,  
				Lbu, 
				Goals0, Goals), 
		LbuGoal = Lbu, 
		Expr = conj(Goals) ,
		Info = Info0
	;
		%%%%%%%%%%%%
		% (2) call %
		%%%%%%%%%%%%
		Expr0 = call(_,_, CallVars, _, _, _)
	-> 
		% and now for the LBU
		goal_info_get_determinism(Info0, Det),
		(
			determinism_is_nondet(Det)
		->
			goal_info_get_instmap_delta(Info0, InstMapDelta),
			list__filter(
				pred(V::in) is semidet :- 
				  ( 
				     ( instmap_delta_search_var(InstMapDelta,
						V, _InstV)
				     -> fail % var changes its instantiation 
				             % over this call, thus is 
					     % certainly not pure INPUT
				     ; true ) ),
				   CallVars, 
				   InputCallVars),
			set__list_to_set(CallVars, CallVars_set),
			set__list_to_set(InputCallVars,InCallVars_set),	
			goal_info_get_lfu(Info0, LFU), 

			%% 
			%% 
		%	lbu_setting_1(Lbu_01, LFU, CallVars_set,
		%		InCallVars_set, LbuGoal, Lbu)
		% 	lbu_setting_2(Lbu_01, LFU, CallVars_set,
		%		 InCallVars_set, LbuGoal, Lbu)
		 	lbu_setting_4(Lbu_01, LFU, CallVars_set,
				 InCallVars_set, LbuGoal, Lbu)
		;
			Lbu = Lbu_01,
			LbuGoal = Lbu 
		),
		Expr = Expr0,
		Info = Info0
	;
		% (3) switch
		Expr0 = switch(A, B, Cases0)
	->
		annotate_lbu_in_switch(HLDS, ProcInfo, 
				Lbu_01, Lbu,  
				Cases0, Cases), 
		LbuGoal = Lbu, 
		Expr = switch(A, B, Cases),
		Info = Info0
	;
		%%%%%%%%%%%%%
		% (4) unify %
		%%%%%%%%%%%%%
		Expr0 = unify(_, _, _, _, _)
	->
		% Lbu
		Lbu = Lbu_01, 
		LbuGoal = Lbu, 
		Expr = Expr0,
		Info = Info0
	;
		%%%%%%%%%%%%
		% (5) disj %
		%%%%%%%%%%%%
		Expr0 = disj(Goals0)
	->
		annotate_lbu_in_disj(HLDS, ProcInfo, Lbu_01,  
				Lbu, Goals0, Goals),
		LbuGoal = Lbu, 
		Expr = disj(Goals),
		Info = Info0
	;
		%%%%%%%%%%%%%%%%%%%%
		% (6) if_then_else %
		%%%%%%%%%%%%%%%%%%%%
		Expr0 = if_then_else(Vars, Cond0, Then0, Else0)
	->
			% annotating the condition
			% starting from Lbu_01 (where resume_vars are
			% taken into account)
		annotate_lbu_in_goal(HLDS, ProcInfo, Lbu_01, 
				_LbuCond, Cond0, Cond),
			% when annotating the then-part, 
			% the lbu used for it may not contain the
			% resume-vars due to the else part. 	
			% trick: to calculate the Lbu0Then, we set
			% resume-point of the condition to no_resume_point.
		Cond0 = CondGoal0 - CondInfo0,
		goal_info_set_resume_point(CondInfo0, no_resume_point, 
				InfoTmp),
		CondTmp = CondGoal0 - InfoTmp, 
		annotate_lbu_in_goal(HLDS, ProcInfo, Lbu_01,  
				Lbu0Then, CondTmp, _),
		annotate_lbu_in_goal(HLDS, ProcInfo, Lbu0Then,  
				LbuThen, Then0, Then),
		annotate_lbu_in_goal(HLDS, ProcInfo, Lbu_01, 
				LbuElse, Else0, Else),
		set__union(LbuThen, LbuElse, Lbu),
		LbuGoal = Lbu, 
		Expr = if_then_else(Vars, Cond, Then, Else),
		Info = Info0
	;
		%%%%%%%%%%%
		% (7) not %
		%%%%%%%%%%%
		Expr0 = not(Goal0)
		% handled as if(Goal0) then fail else true
	->
		annotate_lbu_in_goal(HLDS, ProcInfo, Lbu_01, 
				_Lbu, Goal0, Goal),
		% A not does not introduce any choice-points! Hence the
		% not itself is deterministic, and no new variables in LBU
		% are introduced. 
		Lbu = Lbu_01,
		LbuGoal = Lbu,
		Expr = not(Goal),
		Info = Info0
	;
		%%%%%%%%%%%%
		% (8) some %
		%%%%%%%%%%%%
		Expr0 = some(Vars, CR, Goal0)
	->
		annotate_lbu_in_goal(HLDS, ProcInfo, Lbu_01,  
				Lbu, Goal0, Goal),
		LbuGoal = Lbu,
		Expr = some(Vars, CR, Goal),
		Info = Info0
	;
		%%%%%%%%%%%%%%%%%%%%%%%
		% (9)  generic_call   %
		% (10) pragma_c_code  %
		% (11) par_conj       %
		% (12) bi_implication %
		%%%%%%%%%%%%%%%%%%%%%%%
		Lbu = Lbu0, 
		LbuGoal = Lbu, 
		Expr = Expr0,
		Info = Info0
	),
	goal_info_set_lbu(LbuGoal, Info, Info_new), 
	TopGoal = Expr - Info_new. 	

% LBU setting 1: 
	% if the call is nondeterministic, all actual
	% vars are taken to be in Local Backward Use.
	% LBU_i = LBU_{i-1} + LFU + vars(call)
	% LBU_goal = LBU_i
:- pred lbu_setting_1(set(prog_var), set(prog_var), set(prog_var),
		set(prog_var), set(prog_var), set(prog_var)).
:- mode lbu_setting_1(in, in, in, in, out, out) is det.

lbu_setting_1(Lbu_01, LFU, CallVars, _InputCallVars, LbuGoal, Lbu):- 
	Lbu = set__union_list([Lbu_01, LFU, CallVars]),
	LbuGoal = Lbu.

% LBU setting 2: 
	% for nondet calls, only add the LFU vars to 
	% the lbu-set. 
	% LBU_i = LBU_{i-1} + LFU
	% LBU_goal = LBU_i
:- pred lbu_setting_2(set(prog_var), set(prog_var), set(prog_var),
		set(prog_var), set(prog_var), set(prog_var)).
:- mode lbu_setting_2(in, in, in, in, out, out) is det.

lbu_setting_2(Lbu_01, LFU, _CallVars, _InputCallVars, LbuGoal, Lbu):- 
	Lbu = set__union_list([Lbu_01, LFU]),
	LbuGoal = Lbu.

% LBU setting 3: 
	% LBU_goal = LBU_{i-1} + (LFU_i - vars(call)) % does'nt matter... 
	% LBU_i = LBU_goal + IN
:- pred lbu_setting_3(set(prog_var), set(prog_var), set(prog_var),
		set(prog_var), set(prog_var), set(prog_var)).
:- mode lbu_setting_3(in, in, in, in, out, out) is det.

lbu_setting_3(Lbu_01, LFU, CallVars, InputCallVars, LbuGoal, Lbu):- 
	PartLFU = set__difference(LFU, CallVars),
	LbuGoal = set__union_list([Lbu_01,PartLFU]),
	Lbu = set__union_list([LbuGoal, InputCallVars]).

% LBU setting 4: 
	% LBU_goal = LBU_{i-1} + (LFU_i - vars(call)) % does'nt matter... 
	% LBU_i = LBU_goal + LFU + IN
:- pred lbu_setting_4(set(prog_var), set(prog_var), set(prog_var),
		set(prog_var), set(prog_var), set(prog_var)).
:- mode lbu_setting_4(in, in, in, in, out, out) is det.

lbu_setting_4(Lbu_01, LFU, CallVars, InputCallVars, LbuGoal, Lbu):- 
	PartLFU = set__difference(LFU, CallVars),
	LbuGoal = set__union_list([Lbu_01,PartLFU]),
	Lbu = set__union_list([LbuGoal, LFU, InputCallVars]).

:- pred annotate_lbu_in_conj(module_info, proc_info, set(prog_var),  
			set(prog_var), 
			list(hlds_goal), list(hlds_goal)). 
:- mode annotate_lbu_in_conj(in, in, in, out, in, out) is det.

annotate_lbu_in_conj(HLDS, ProcInfo, Lbu0,  
				Lbu, Goals0, Goals) :- 
	list__map_foldl(
		pred(Goal0::in, Goal::out, 
		      L0::in, L::out) is det :-
			(annotate_lbu_in_goal(HLDS, ProcInfo, L0,  
					L, Goal0, Goal)),
		Goals0, Goals, 
		Lbu0, Lbu).

:- pred annotate_lbu_in_switch(module_info, proc_info, 
			set(prog_var), 
			set(prog_var), 
			list(case), list(case)).
:- mode annotate_lbu_in_switch(in, in, in, out, in, out) is det.

annotate_lbu_in_switch(HLDS, ProcInfo, Lbu0, Lbu, 
			Cases0, Cases) :- 
	list__map_foldl(
		pred(Case0::in, Case::out, 
		      L0::in, L::out) is det :-
			(
			Case0 = case(CONS,Goal0), 
			annotate_lbu_in_goal(HLDS, ProcInfo, Lbu0, 
					Lnew, Goal0, Goal),
			Case  = case(CONS,Goal),
			set__union(L0, Lnew, L)
			),
		Cases0, Cases, 
		Lbu0, Lbu).

:- pred annotate_lbu_in_disj(module_info, proc_info, 
			set(prog_var), 
			set(prog_var), 
			list(hlds_goal), list(hlds_goal)).
:- mode annotate_lbu_in_disj(in, in, in, out, in, out) is det.

annotate_lbu_in_disj(HLDS, ProcInfo, Lbu0, Lbu, 
			Goals0, Goals) :- 
	list__map_foldl(
		pred(Goal0::in, Goal::out, 
		      L0::in, L::out) is det :-
			(
			annotate_lbu_in_goal(HLDS, ProcInfo, Lbu0, 
					Lnew, Goal0, Goal),
			set__union(L0, Lnew, L)
			),
		Goals0, Goals, 
		Lbu0, Lbu).

:- pred determinism_is_nondet(prog_data__determinism).
:- mode determinism_is_nondet(in) is semidet.

determinism_is_nondet(nondet).
determinism_is_nondet(multidet).
determinism_is_nondet(cc_nondet).
determinism_is_nondet(cc_multidet).

:- pred info_get_backtrack_vars(hlds_goal_info, set(prog_var)).
:- mode info_get_backtrack_vars(in, out) is det.

info_get_backtrack_vars(Info, Vars):- 
	goal_info_get_resume_point(Info, ResPoint), 
	(
		ResPoint = resume_point(ResVars, _)
	->
		Vars = ResVars
	;
		set__init(Vars)
	). 


:- end_module sr_lbu.
