%---------------------------------------------------------------------------%
% Copyright (C) 1993-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% This module imports all the modules in the Mercury library.
%
% It is used as a way for the Makefiles to know which library interface
% files, objects, etc., need to be installed.
% 
% ---------------------------------------------------------------------------%
% ---------------------------------------------------------------------------%

:- module library.

:- interface.

:- pred library__version(string::out) is det.

%---------------------------------------------------------------------------%

:- implementation.

% Note: if you add a new module to this list, you must also a new clause
% to mercury_std_library_module/1 in compiler/modules.m.

:- import_module array, assoc_list, bag, benchmarking.
:- import_module bimap, bintree, bintree_set, bool.
:- import_module bt_array, char, counter, dir, eqvclass, float.
:- import_module math, getopt, graph, group, int.
:- import_module io, list, map, multi_map, pqueue, queue, random, relation.
:- import_module require, set, set_bbbtree, set_ordlist, set_unordlist, stack.
:- import_module std_util, string, term, term_io, tree234, varset.
:- import_module store, rbtree, parser, lexer, ops.
:- import_module prolog.
:- import_module integer, rational.
:- import_module exception, gc.
:- import_module time.
:- import_module pprint.

:- import_module builtin, private_builtin, table_builtin.

% library__version must be implemented using pragma c_code,
% so we can get at the MR_VERSION and MR_FULLARCH configuration
% parameters.  We can't just generate library.m from library.m.in
% at configuration time, because that would cause bootstrapping problems --
% might not have a Mercury compiler around to compile library.m with.

:- pragma c_code(library__version(Version::out), will_not_call_mercury, "
	ConstString version_string = 
		MR_VERSION "", configured for "" MR_FULLARCH;
	/*
	** Cast away const needed here, because Mercury declares Version
	** with type String rather than ConstString.
	*/
	Version = (String) (Word) version_string;
").

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
