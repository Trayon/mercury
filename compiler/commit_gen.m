%---------------------------------------------------------------------------%
% Copyright (C) 1997-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: commit_gen.m
%
% Main authors: conway, fjh, zs.
%
% The predicates of this module generate code for performing commits.
%
%---------------------------------------------------------------------------%

:- module commit_gen.

:- interface.

:- import_module hlds_goal, code_model, llds, code_info.

:- pred commit_gen__generate_commit(code_model::in, hlds_goal::in,
	code_tree::out, code_info::in, code_info::out) is det.

:- implementation.

:- import_module code_gen, tree.
:- import_module std_util, require.

commit_gen__generate_commit(OuterCodeModel, Goal, Code) -->
	{ Goal = _ - InnerGoalInfo },
	{ goal_info_get_code_model(InnerGoalInfo, InnerCodeModel) },
	(
		{ OuterCodeModel = model_det },
		(
			{ InnerCodeModel = model_det },
			code_gen__generate_goal(InnerCodeModel, Goal, Code)
		;
			{ InnerCodeModel = model_semi },
			{ error("semidet model in det context") }
		;
			{ InnerCodeModel = model_non },
			code_info__prepare_for_det_commit(CommitInfo,
				PreCommit),
			code_gen__generate_goal(InnerCodeModel, Goal, GoalCode),
			code_info__generate_det_commit(CommitInfo, Commit),
			{ Code = tree(PreCommit, tree(GoalCode, Commit)) }
		)
	;
		{ OuterCodeModel = model_semi },
		(
			{ InnerCodeModel = model_det },
			code_gen__generate_goal(InnerCodeModel, Goal, Code)
		;
			{ InnerCodeModel = model_semi },
			code_gen__generate_goal(InnerCodeModel, Goal, Code)
		;
			{ InnerCodeModel = model_non },
			code_info__prepare_for_semi_commit(CommitInfo,
				PreCommit),
			code_gen__generate_goal(InnerCodeModel, Goal, GoalCode),
			code_info__generate_semi_commit(CommitInfo, Commit),
			{ Code = tree(PreCommit, tree(GoalCode, Commit)) }
		)
	;
		{ OuterCodeModel = model_non },
		code_gen__generate_goal(InnerCodeModel, Goal, Code)
	).
