%-----------------------------------------------------------------------------%
% Copyright (C) 1993-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: prog_io.m.
% Main author: fjh.
%
% This module defines predicates for parsing Mercury programs.
%
% In some ways the representation of programs here is considerably
% more complex than is necessary for the compiler.
% The basic reason for this is that it was designed to preserve
% as much information about the source code as possible, so that
% this representation could also be used for other tools such
% as Mercury-to-Goedel converters, pretty-printers, etc.
% Currently the only information that is lost is that comments and
% whitespace are stripped, any redundant parenthesization
% are lost, distinctions between different spellings of the same
% operator (eg "\+" vs "not") are lost, and DCG clauses get expanded.
% It would be a good idea to preserve all those too (well, maybe not
% the redundant parentheses), but right now it's not worth the effort.
%
% So that means that this phase of compilation is purely parsing.
% No simplifications are done (other than DCG expansion). 
% The results of this phase specify
% basically the same information as is contained in the source code,
% but in a parse tree rather than a flat file.
% Simplifications are done only by make_hlds.m, which transforms
% the parse tree which we built here into the HLDS.
%
% Some of this code is a rather bad example of cut-and-paste style reuse.
% It should be cleaned up to eliminate most of the duplication.
% But that task really needs to wait until we implement higher-order
% predicates.  For the moment, just be careful that any changes
% you make are reflected correctly in all similar parts of this
% file.
%
% Implication and equivalence implemented by squirrel, who would also
% like to get her hands on this file and give it a good clean up and
% put it into good clean "mercury" style!

% Wishlist:
%
% 1.  implement importing/exporting operators with a particular fixity
%     eg. :- import_op prefix(+). % only prefix +, not infix
%     (not important, but should be there for reasons of symmetry.)
% 2.  improve the handling of type and inst parameters 
% 3.  improve the error reporting (most of the semidet preds should
%     be det and should return a meaningful indication of where an
%     error occured).

:- module prog_io.

:- interface.

:- import_module prog_data, prog_io_util.
:- import_module bool, varset, term, list, io. 

%-----------------------------------------------------------------------------%

% This module (prog_io) exports the following predicates:

	% prog_io__read_module(FileName, DefaultModuleName, Search, Error,
	%				ActualModuleName, Messages, Program)
	% Reads and parses the module in file `FileName',
	% using the default module name `DefaultModuleName'.
	% If Search is yes, search directories given by the option
	% search_directories.
	% Error is `fatal' if the file coudn't be opened, `yes'
	% if a syntax error was detected, and `no' otherwise.
	% ActualModuleName is the module name specified in the
	% `:- module' declaration, if any, or the DefaultModuleName
	% if there is no `:- module' declaration.
	% Messages is a list of warning/error messages.
	% Program is the parse tree.

:- type module_error
	--->	no	% no errors
	;	yes	% some syntax errors
	;	fatal.	% couldn't open the file

:- type file_name == string.
:- type dir_name == string.

:- pred prog_io__read_module(file_name, module_name, bool,
		module_error, module_name, message_list, item_list,
		io__state, io__state).
:- mode prog_io__read_module(in, in, in, out, out, out, out, di, uo) is det.

	% Same as prog_io__read_module, but use intermod_directories
	% instead of search_directories when searching for the file.
	% Also report an error if the actual module name doesn't match
	% the expected module name.
:- pred prog_io__read_opt_file(file_name, module_name, bool,
		module_error, message_list, item_list, io__state, io__state).
:- mode prog_io__read_opt_file(in, in, in, out, out, out, di, uo) is det.

	% check_module_has_expected_name(FileName, ExpectedName, ActualName):
	%	Check that two module names are equal,
	%	and report an error if they aren't.
:- pred check_module_has_expected_name(file_name, module_name, module_name,
		io__state, io__state).
:- mode check_module_has_expected_name(in, in, in, di, uo) is det.

	% search_for_file(Dirs, FileName, Found, IO0, IO)
	%
	% Search Dirs for FileName, opening the file if it is found.
:- pred search_for_file(list(dir_name), file_name, bool, io__state, io__state).
:- mode search_for_file(in, in, out, di, uo) is det.

	% parse_item(ModuleName, VarSet, Term, MaybeItem)
	%
	% parse Term. If successful, MaybeItem is bound to the parsed item,
	% otherwise it is bound to an appropriate error message.
	% Qualify appropriate parts of the item, with ModuleName as the
	% module name.
:- pred parse_item(module_name, varset, term, maybe_item_and_context). 
:- mode parse_item(in, in, in, out) is det.

	% parse_decl(ModuleName, VarSet, Term, Result)
	%
	% parse Term as a declaration. If successful, Result is bound to the
	% parsed item, otherwise it is bound to an appropriate error message.
	% Qualify appropriate parts of the item, with ModuleName as the module
	% name.
:- pred parse_decl(module_name, varset, term, maybe_item_and_context).
:- mode parse_decl(in, in, in, out) is det.

%-----------------------------------------------------------------------------%

	%	A QualifiedTerm is one of
	%		Name(Args)
	%		Module:Name(Args)
	%	(or if Args is empty, one of
	%		Name
	%		Module:Name)
	%	where Module is a SymName.
	%	For backwards compatibility, we allow `__'
	%	as an alternative to `:'.

	% sym_name_and_args takes a term and returns a sym_name and a list of
	% argument terms.
	% It fails if the input is not valid syntax for a QualifiedTerm.
:- pred sym_name_and_args(term(T), sym_name, list(term(T))).
:- mode sym_name_and_args(in, out, out) is semidet.

	% parse_qualified_term/4 takes a term (and also the containing
	% term, and a string describing the context from which it
	% was called [e.g. "clause head"])
	% and returns a sym_name and a list of argument terms.
	% Returns an error on ill-formed input.
	% See also parse_implicitly_qualified_term/5 (below).
:- pred parse_qualified_term(term(T), term(T), string, maybe_functor(T)).
:- mode parse_qualified_term(in, in, in, out) is det.

	% parse_implicitly_qualified_term(DefaultModName, Term,
	%	ContainingTerm, Msg, Result):
	%
	% parse_implicitly_qualified_term/5 takes a default module name
	% and a term,
	% (and also the containing term, and a string describing
	% the context from which it was called (e.g. "clause head"),
	% and returns a sym_name and a list of argument terms.
	% Returns an error on ill-formed input or a module qualifier that
	% doesn't match the DefaultModName.
	%
	% Note: parse_qualified_term/4 is used for places where a symbol
	% is _used_, in which case no default module name exists, whereas
	% parse_implicitly_qualified_term/5 is used for places where a symbol
	% is _defined_; in that case, there is a default module name (the
	% name of the current module) -- specifying a module qualifier
	% explicitly is redundant, but it is allowed, so long as the
	% module qualifier specified matches the default.
:- pred parse_implicitly_qualified_term(module_name, term(T), term(T), string,
					maybe_functor(T)).
:- mode parse_implicitly_qualified_term(in, in, in, in, out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module prog_io_goal, prog_io_dcg, prog_io_pragma, prog_io_util.
:- import_module prog_io_typeclass.
:- import_module hlds_data, hlds_pred, prog_util, prog_out.
:- import_module globals, options, (inst).

:- import_module int, string, std_util, parser, term_io, dir, require.
:- import_module assoc_list.

%-----------------------------------------------------------------------------%

prog_io__read_module(FileName, DefaultModuleName, Search,
		Error, ModuleName, Messages, Items) -->
	prog_io__read_module_2(FileName, DefaultModuleName, Search,
		search_directories, Error, ModuleName, Messages, Items).

prog_io__read_opt_file(FileName, DefaultModuleName, Search, 
		Error, Messages, Items) -->
	prog_io__read_module_2(FileName, DefaultModuleName, Search, 
		intermod_directories, Error, ModuleName, Messages, Items),
	check_module_has_expected_name(FileName,
		DefaultModuleName, ModuleName).

check_module_has_expected_name(FileName, ExpectedName, ActualName) -->
	( { ActualName \= ExpectedName } ->
		{ prog_out__sym_name_to_string(ActualName, ActualString) },
		{ prog_out__sym_name_to_string(ExpectedName, ExpectedString) },
		io__stderr_stream(ErrStream),
		io__write_strings(ErrStream, [
			"Error: file `", FileName,
				"' contains the wrong module.\n",
			"Expected module `", ExpectedString,
				"', found module `", ActualString, "'.\n"
		]),
		io__set_exit_status(1)
	;
		[]
	).

		
% This implementation uses io__read_term to read in the program
% term at a time, and then converts those terms into clauses and
% declarations, checking for errors as it goes.
% Note that rather than using difference lists, we just
% build up the lists of items and messages in reverse order
% and then reverse them afterwards.  (Using difference lists would require
% late-input modes.)

:- pred prog_io__read_module_2(file_name, module_name, bool, option,
		module_error, module_name, message_list, item_list,
		io__state, io__state).
:- mode prog_io__read_module_2(in, in, in, in, out, out, out, out,
		di, uo) is det.

prog_io__read_module_2(FileName, DefaultModuleName, Search,
		SearchOpt, Error, ModuleName, Messages, Items) -->
	( 
		{ Search = yes }
	->
		globals__io_lookup_accumulating_option(SearchOpt, 
			Dirs)
	;
		{ dir__this_directory(CurrentDir) },
		{ Dirs = [CurrentDir] }
	),
	search_for_file(Dirs, FileName, R),
	( { R = yes } ->
		read_all_items(DefaultModuleName, ModuleName,
			Messages, Items, Error),
		io__seen
	;
		io__progname_base("prog_io.m", Progname),
		{
		  string__append(Progname, ": can't open file `", Message1),
		  string__append(Message1, FileName, Message2),
		  string__append(Message2, "'", Message),
		  dummy_term(Term),
		  Messages = [Message - Term],
		  Error = fatal,
		  Items = [],
		  ModuleName = DefaultModuleName
		}
	).

search_for_file([], _, no) --> [].
search_for_file([Dir | Dirs], FileName, R) -->
	{ dir__this_directory(Dir) ->
		ThisFileName = FileName
	;
		dir__directory_separator(Separator),
		string__first_char(Tmp1, Separator, FileName),
		string__append(Dir, Tmp1, ThisFileName)
	},
	io__see(ThisFileName, R0),
	( { R0 = ok } ->
		{ R = yes }
	;
		search_for_file(Dirs, FileName, R)
	).

%-----------------------------------------------------------------------------%

	% extract the final `:- end_module' declaration if any

:- type module_end ---> no ; yes(module_name, prog_context).

:- pred get_end_module(item_list, module_name, item_list, module_end).
:- mode get_end_module(in, in, out, out) is det.

get_end_module(RevItems0, ModuleName, RevItems, EndModule) :-
	(
		%
		% Note: if the module name in the end_module declaration
		% does not match what we expect, given the source file name,
		% then we assume that it is for a nested module, and so
		% we leave it alone.  If it is not for a nested module,
		% the error will be caught by make_hlds.m.
		%
		RevItems0 = [
			module_defn(_VarSet, end_module(ModuleName)) - Context
			    | RevItems1]
	->
		RevItems = RevItems1,
		EndModule = yes(ModuleName, Context)
	;
		RevItems = RevItems0,
		EndModule = no
	).

%-----------------------------------------------------------------------------%

	% check that the module starts with a :- module declaration,
	% and that the end_module declaration (if any) is correct,
	% and construct the final parsing result.

:- pred check_end_module(module_end, message_list, item_list, module_error,
		message_list, item_list, module_error, io__state, io__state).
:- mode check_end_module(in, in, in, in, out, out, out, di, uo) is det.

check_end_module(EndModule, Messages0, Items0, Error0,
		Messages, Items, Error) -->
    %
    % double-check that the first item is a `:- module ModuleName'
    % declaration, and remove it from the front of the item list
    %
    {
        Items0 = [module_defn(_VarSet, module(ModuleName1)) - _Context1
		| Items1]
    ->
	Items = Items1,
	%
        % check that the end module declaration (if any)
        % matches the begin module declaration 
	%
        (
            EndModule = yes(ModuleName2, Context2),
            ModuleName1 \= ModuleName2
        ->
	    dummy_term_with_context(Context2, Term),
            add_error(
"`:- end_module' declaration doesn't match `:- module' declaration",
			Term, Messages0, Messages),
	    Error = yes
        ;
	    Messages = Messages0,
	    Error = Error0
        )
    ;
	% if there's no `:- module' declaration at this point, it is
	% an internal error -- read_first_item should have inserted one
	error("check_end_module: no `:- module' declaration")
    }.

%-----------------------------------------------------------------------------%

	% Create a dummy term.
	% Used for error messages that are not associated with any
	% particular term or context.
:- pred dummy_term(term).
:- mode dummy_term(out) is det.
dummy_term(Term) :-
	term__context_init(Context),
	dummy_term_with_context(Context, Term).

	% Create a dummy term with the specified context.
	% Used for error messages that are associated with some specific
	% context, but for which we don't want to print out the term
	% (or for which the term isn't available to be printed out).

:- pred dummy_term_with_context(term__context, term).
:- mode dummy_term_with_context(in, out) is det.
dummy_term_with_context(Context, Term) :-
	Term = term__functor(term__atom(""), [], Context).

%-----------------------------------------------------------------------------%

 	% Read a source file from standard in, first reading in
	% the input term by term and then parsing those terms and producing
	% a high-level representation.
	% Parsing is actually a 3-stage process instead of the
	% normal two-stage process:
	%	lexical analysis (chars -> tokens),
	% 	parsing stage 1 (tokens -> terms),
	%	parsing stage 2 (terms -> items).
	% The final stage produces a list of program items, each of
	% which may be a declaration or a clause.
	%
	% We use a continuation-passing style here.

:- pred read_all_items(module_name, module_name,
			message_list, item_list, module_error,
			io__state, io__state).
:- mode read_all_items(in, out, out, out, out, di, uo) is det.

read_all_items(DefaultModuleName, ModuleName, Messages, Items, Error) -->
	%
	% read all the items (the first one is handled specially)
	%
	io__input_stream(Stream),
	io__input_stream_name(Stream, SourceFileName),
	read_first_item(DefaultModuleName, SourceFileName, ModuleName,
		RevMessages, RevItems0, Error0),

	%
	% get the end_module declaration (if any),
	% check that it matches the initial module declaration (if any),
	% and remove both of them from the final item list.
	%
	{ get_end_module(RevItems0, ModuleName, RevItems, EndModule) },
	{ list__reverse(RevMessages, Messages0) },
	{ list__reverse(RevItems, Items0) },
	check_end_module(EndModule,
			Messages0, Items0, Error0,
			Messages, Items, Error).

%
% We need to jump through a few hoops when reading the first item,
% to allow the initial `:- module' declaration to be optional.
% The reason is that in order to parse an item, we need to know
% which module it is defined in (because we do some module
% qualification and checking of module qualifiers at parse time),
% but the initial `:- module' declaration and the declaration
% that follows it occur in different scopes, so we need to know
% what it is that we're parsing before we can parse it!
% We solve this dilemma by first parsing it in the root scope,
% and then if it turns out to not be a `:- module' declaration
% we reparse it in the default module scope.  Blecchh.
%
:- pred read_first_item(module_name, file_name, module_name,
		message_list, item_list, module_error, io__state, io__state).
:- mode read_first_item(in, in, out, out, out, out, di, uo) is det.

read_first_item(DefaultModuleName, SourceFileName, ModuleName,
	Messages, Items, Error) -->

	globals__io_lookup_bool_option(warn_missing_module_name, WarnMissing),
	globals__io_lookup_bool_option(warn_wrong_module_name, WarnWrong),
    
	%
	% parse the first term, treating it as occurring
	% within the scope of the special "root" module
	% (so that any `:- module' declaration is taken to
	% be a non-nested module unless explicitly qualified).
	%
	parser__read_term(SourceFileName, MaybeFirstTerm),
	{ root_module_name(RootModuleName) },
	{ process_read_term(RootModuleName, MaybeFirstTerm, MaybeFirstItem) },
	(
	    %
	    % apply and then skip `pragma source_file' decls,
	    % by calling ourselves recursively with the new source
	    % file name
	    %
	    { MaybeFirstItem = ok(FirstItem, _) },
	    { FirstItem = pragma(source_file(NewSourceFileName)) }
	->
	    read_first_item(DefaultModuleName, NewSourceFileName,
	    	ModuleName, Messages, Items, Error)
	;
	    %
	    % check if the first term was a `:- module' decl
	    %
	    { MaybeFirstItem = ok(FirstItem, FirstContext) },
	    { FirstItem = module_defn(_VarSet, ModuleDefn) },
	    { ModuleDefn = module(StartModuleName) }
	->
	    
	    %
	    % if so, then check that it matches the expected
	    % module name, and if not, report a warning
	    %
	    {
		match_sym_name(StartModuleName, DefaultModuleName)
	    ->
		ModuleName = DefaultModuleName,
		Messages0 = []
	    ;
		match_sym_name(DefaultModuleName, StartModuleName)
	    ->
		ModuleName = StartModuleName,
		Messages0 = []
	    ;
	    	prog_out__sym_name_to_string(StartModuleName,
			StartModuleNameString),
	    	string__append_list(["source file `", SourceFileName,
			"' contains module named `", StartModuleNameString,
			"'"], WrongModuleWarning),
	        maybe_add_warning(WarnWrong, MaybeFirstTerm, FirstContext,
			WrongModuleWarning, [], Messages0),

		% Which one should we use here?
		% We used to use the default module name
		% (computed from the filename)
		% but now we use the declared one.
		ModuleName = StartModuleName
	    },
	    { make_module_decl(ModuleName, FirstContext, FixedFirstItem) },
	    { Items0 = [FixedFirstItem] },
	    { Error0 = no },
	    read_items_loop(ModuleName, SourceFileName,
			Messages0, Items0, Error0,
			Messages, Items, Error)
	;
	    %
	    % if the first term was not a `:- module' decl,
	    % then issue a warning (if warning enabled), and
	    % insert an implicit `:- module ModuleName' decl.
	    %
	    { MaybeFirstItem = ok(_FirstItem, FirstContext0) ->
		FirstContext = FirstContext0
	    ;
	        term__context_init(SourceFileName, 1, FirstContext)
	    },
	    { WarnMissing = yes ->
		dummy_term_with_context(FirstContext, FirstTerm),
		add_warning(
			"module should start with a `:- module' declaration",
			FirstTerm, [], Messages0)
	    ;
		Messages0 = []
	    },
	    { ModuleName = DefaultModuleName },
	    { make_module_decl(ModuleName, FirstContext, FixedFirstItem) },
    
	    %
	    % reparse the first term, this time treating it as
	    % occuring within the scope of the implicit
	    % `:- module' decl rather than in the root module.
	    % 
	    { MaybeSecondTerm = MaybeFirstTerm },
	    { process_read_term(ModuleName, MaybeSecondTerm,
		MaybeSecondItem) },

	    { Items0 = [FixedFirstItem] },
	    { Error0 = no },
	    read_items_loop_2(MaybeSecondItem, ModuleName, SourceFileName,
		Messages0, Items0, Error0,
		Messages, Items, Error)
	).

:- pred make_module_decl(module_name, term__context, item_and_context).
:- mode make_module_decl(in, in, out) is det.

make_module_decl(ModuleName, Context, Item - Context) :-
	varset__init(EmptyVarSet),
	ModuleDefn = module(ModuleName),
	Item = module_defn(EmptyVarSet, ModuleDefn).

:- pred maybe_add_warning(bool, read_term, term__context, string,
		message_list, message_list).
:- mode maybe_add_warning(in, in, in, in, in, out) is det.

maybe_add_warning(DoWarn, MaybeTerm, Context, Warning, Messages0, Messages) :-
	( DoWarn = yes ->
		( MaybeTerm = term(_VarSet, Term) ->
			WarningTerm = Term
		;
			dummy_term_with_context(Context, WarningTerm)
		),
		add_warning(Warning, WarningTerm, Messages0, Messages)
	;
		Messages = Messages0
	).

%-----------------------------------------------------------------------------%

	% The code below was carefully optimized to run efficiently
	% in NU-Prolog.  We used to call read_item(MaybeItem) -
	% which does all the work for a single item -
	% via io__gc_call/1, which called the goal with garbage collection.
	% But optimizing for NU-Prolog is no longer a big priority...

:- pred read_items_loop(module_name, file_name,
			message_list, item_list, module_error, 
			message_list, item_list, module_error, 
			io__state, io__state).
:- mode read_items_loop(in, in, in, in, in, out, out, out, di, uo) is det.

read_items_loop(ModuleName, SourceFileName, Msgs1, Items1, Error1,
		Msgs, Items, Error) -->
	read_item(ModuleName, SourceFileName, MaybeItem),
 	read_items_loop_2(MaybeItem, ModuleName, SourceFileName,
			Msgs1, Items1, Error1, Msgs, Items, Error).

%-----------------------------------------------------------------------------%

:- pred read_items_loop_2(maybe_item_or_eof, module_name, file_name,
			message_list, item_list, module_error,
			message_list, item_list, module_error,
			io__state, io__state).
:- mode read_items_loop_2(in, in, in, in, in, in, out, out, out, di, uo) is det.

% do a switch on the type of the next item

read_items_loop_2(eof, _ModuleName, _SourceFileName, Msgs, Items, Error,
		Msgs, Items, Error) --> []. 
	% if the next item was end-of-file, then we're done.

read_items_loop_2(syntax_error(ErrorMsg, LineNumber), ModuleName,
		SourceFileName, Msgs0, Items0, _Error0, Msgs, Items, Error) -->
	% if the next item was a syntax error, then insert it in
	% the list of messages and continue looping
	{
	  term__context_init(SourceFileName, LineNumber, Context),
	  dummy_term_with_context(Context, Term),
	  ThisError = ErrorMsg - Term,
	  Msgs1 = [ThisError | Msgs0],
	  Items1 = Items0,
	  Error1 = yes
	},
	read_items_loop(ModuleName, SourceFileName, Msgs1, Items1, Error1,
		Msgs, Items, Error).

read_items_loop_2(error(M, T), ModuleName, SourceFileName,
		Msgs0, Items0, _Error0, Msgs, Items, Error) -->
	% if the next item was a semantic error, then insert it in
	% the list of messages and continue looping
	{
	  add_error(M, T, Msgs0, Msgs1),
	  Items1 = Items0,
	  Error1 = yes
	},
 	read_items_loop(ModuleName, SourceFileName, Msgs1, Items1, Error1,
			Msgs, Items, Error).

read_items_loop_2(ok(Item, Context), ModuleName0, SourceFileName0,
			Msgs0, Items0, Error0, Msgs, Items, Error) -->
	% if the next item was a valid item, check whether it was
	% a declaration that affects the current parsing context --
	% i.e. either a `module'/`end_module' declaration or a
	% `pragma source_file' declaration.  If so, set the new
	% parsing context according.  Next, unless the item is a
	% `pragma source_file' declaration, insert it into the item list.
	% Then continue looping.
	{ Item = pragma(source_file(NewSourceFileName)) ->
		SourceFileName = NewSourceFileName,
		ModuleName = ModuleName0,
		Items1 = Items0
	; Item = module_defn(_VarSet, module(NestedModuleName)) ->
		ModuleName = NestedModuleName,
		SourceFileName = SourceFileName0,
		Items1 = [Item - Context | Items0]
	; Item = module_defn(_VarSet, end_module(NestedModuleName)) ->
		root_module_name(RootModuleName),
		sym_name_get_module_name(NestedModuleName, RootModuleName,
			ParentModuleName),
		ModuleName = ParentModuleName,
		SourceFileName = SourceFileName0,
		Items1 = [Item - Context | Items0]
	;
		SourceFileName = SourceFileName0,
		ModuleName = ModuleName0,
		Items1 = [Item - Context | Items0]
	},
 	read_items_loop(ModuleName, SourceFileName, Msgs0, Items1, Error0,
			Msgs, Items, Error).

%-----------------------------------------------------------------------------%

	% read_item/1 reads a single item, and if it is a valid term
	% parses it.

:- type maybe_item_or_eof --->	eof
			;	syntax_error(file_name, int)
			;	error(string, term)
			;	ok(item, term__context).

:- pred read_item(module_name, file_name, maybe_item_or_eof,
			io__state, io__state).
:- mode read_item(in, in, out, di, uo) is det.

read_item(ModuleName, SourceFileName, MaybeItem) -->
	parser__read_term(SourceFileName, MaybeTerm),
	{ process_read_term(ModuleName, MaybeTerm, MaybeItem) }.

:- pred process_read_term(module_name, read_term, maybe_item_or_eof).
:- mode process_read_term(in, in, out) is det.

process_read_term(_ModuleName, eof, eof).
process_read_term(_ModuleName, error(ErrorMsg, LineNumber),
			syntax_error(ErrorMsg, LineNumber)).
process_read_term(ModuleName, term(VarSet, Term),
			MaybeItemOrEof) :-
	parse_item(ModuleName, VarSet, Term, MaybeItem),
	convert_item(MaybeItem, MaybeItemOrEof).

:- pred convert_item(maybe_item_and_context, maybe_item_or_eof).
:- mode convert_item(in, out) is det.

convert_item(ok(Item, Context), ok(Item, Context)).
convert_item(error(M, T), error(M, T)).

parse_item(ModuleName, VarSet, Term, Result) :-
 	( %%% some [Decl, DeclContext]
		Term = term__functor(term__atom(":-"), [Decl], _DeclContext)
	->
		% It's a declaration
		parse_decl(ModuleName, VarSet, Decl, Result)
	; %%% some [DCG_H, DCG_B, DCG_Context]
		% It's a DCG clause
		Term = term__functor(term__atom("-->"), [DCG_H, DCG_B],
			DCG_Context)
	->
		parse_dcg_clause(ModuleName, VarSet, DCG_H, DCG_B,
				DCG_Context, Result)
	;
		% It's either a fact or a rule
		( %%% some [H, B, TermContext]
			Term = term__functor(term__atom(":-"), [H, B],
						TermContext)
		->
			% it's a rule
			Head = H,
			Body = B,
			TheContext = TermContext
		;
			% it's a fact
			Head = Term,
			(
				Head = term__functor(_Functor, _Args,
							HeadContext)
			->
				TheContext = HeadContext
			;
					% term consists of just a single
					% variable - the context has been lost
				term__context_init(TheContext)
			),
			Body = term__functor(term__atom("true"), [], TheContext)
		),
		varset__coerce(VarSet, ProgVarSet),
		parse_goal(Body, ProgVarSet, Body2, ProgVarSet2),
		(
			Head = term__functor(term__atom("="),
					[FuncHead, FuncResult], _)
		->
			parse_implicitly_qualified_term(ModuleName,
				FuncHead, Head, "equation head", R2),
			process_func_clause(R2, FuncResult, ProgVarSet2, Body2,
				R3)
		;
			parse_implicitly_qualified_term(ModuleName,
				Head, Term, "clause head", R2),
			process_pred_clause(R2, ProgVarSet2, Body2, R3)
		),
		add_context(R3, TheContext, Result)
	).

:- pred process_pred_clause(maybe_functor, prog_varset, goal, maybe1(item)).
:- mode process_pred_clause(in, in, in, out) is det.
process_pred_clause(ok(Name, Args0), VarSet, Body,
		ok(pred_clause(VarSet, Name, Args, Body))) :-
	list__map(term__coerce, Args0, Args).
process_pred_clause(error(ErrMessage, Term0), _, _, error(ErrMessage, Term)) :-
	term__coerce(Term0, Term).

:- pred process_func_clause(maybe_functor, term, prog_varset, goal,
		maybe1(item)).
:- mode process_func_clause(in, in, in, in, out) is det.
process_func_clause(ok(Name, Args0), Result0, VarSet, Body,
		ok(func_clause(VarSet, Name, Args, Result, Body))) :-
	list__map(term__coerce, Args0, Args),
	term__coerce(Result0, Result).
process_func_clause(error(ErrMessage, Term0), _, _, _,
		error(ErrMessage, Term)) :-
	term__coerce(Term0, Term).

%-----------------------------------------------------------------------------%

:- type decl_attribute
	--->	purity(purity)
	;	quantifier(quantifier_type, list(tvar))
	;	constraints(quantifier_type, term).
		% the term here is the (not yet parsed) list of constraints

:- type quantifier_type
	--->	exist
	;	univ.

:- type decl_attrs == list(pair(decl_attribute, term)).
	% the term associated with each decl_attribute
	% is the term containing both the attribute and
	% the declaration that that attribute modifies;
	% this term is used when printing out error messages
	% for cases when attributes are used on declarations
	% where they are not allowed.

parse_decl(ModuleName, VarSet, F, Result) :-
	parse_decl_2(ModuleName, VarSet, F, [], Result).

	% parse_decl_2(ModuleName, VarSet, Term, Attributes, Result)
	% succeeds if Term is a declaration and binds Result to a
	% representation of that declaration.  Attributes is a list
	% of enclosing declaration attributes, in the order innermost to
	% outermost.
:- pred parse_decl_2(module_name, varset, term, decl_attrs,
		maybe_item_and_context).
:- mode parse_decl_2(in, in, in, in, out) is det.

parse_decl_2(ModuleName, VarSet, F, Attributes, Result) :-
	( 
		F = term__functor(term__atom(Atom), Args, Context)
	->
		(
			parse_decl_attribute(Atom, Args, Attribute, SubTerm)
		->
			NewAttributes = [Attribute - F | Attributes],
			parse_decl_2(ModuleName, VarSet, SubTerm,
				NewAttributes, Result)
		;
			process_decl(ModuleName, VarSet, Atom, Args,
				Attributes, R)
		->
			add_context(R, Context, Result)
		;
			Result = error("unrecognized declaration", F)
		)
	;
		Result = error("atom expected after `:-'", F)
	).

	% process_decl(ModuleName, VarSet, Attributes, Atom, Args, Result)
	% succeeds if Atom(Args) is a declaration and binds Result to a
	% representation of that declaration.  Attributes is a list
	% of enclosing declaration attributes, in the order outermost to
	% innermost.
:- pred process_decl(module_name, varset, string, list(term), decl_attrs,
		maybe1(item)).
:- mode process_decl(in, in, in, in, in, out) is semidet.

process_decl(ModuleName, VarSet, "type", [TypeDecl], Attributes, Result) :-
	parse_type_decl(ModuleName, VarSet, TypeDecl, Result0),
	check_no_attributes(Result0, Attributes, Result).

process_decl(ModuleName, VarSet, "pred", [PredDecl], Attributes, Result) :-
	parse_type_decl_pred(ModuleName, VarSet, PredDecl, Attributes, Result).

process_decl(ModuleName, VarSet, "func", [FuncDecl], Attributes, Result) :-
	parse_type_decl_func(ModuleName, VarSet, FuncDecl, Attributes, Result).

process_decl(ModuleName, VarSet, "mode", [ModeDecl], Attributes, Result) :-
	parse_mode_decl(ModuleName, VarSet, ModeDecl, Result0),
	check_no_attributes(Result0, Attributes, Result).

process_decl(ModuleName, VarSet, "inst", [InstDecl], Attributes, Result) :-
	parse_inst_decl(ModuleName, VarSet, InstDecl, Result0),
	check_no_attributes(Result0, Attributes, Result).

process_decl(_ModuleName, VarSet, "import_module", [ModuleSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_module_specifier, make_module, make_import,
		ModuleSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "use_module", [ModuleSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_module_specifier, make_module, make_use,
		ModuleSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "export_module", [ModuleSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_module_specifier, make_module, make_export,
		ModuleSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "import_sym", [SymSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_symbol_specifier, make_sym, make_import,
		SymSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "use_sym", [SymSpec], Attributes, Result) :-
	parse_symlist_decl(parse_symbol_specifier, make_sym, make_use,
		SymSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "export_sym", [SymSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_symbol_specifier, make_sym, make_export,
		SymSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "import_pred", [PredSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_predicate_specifier, make_pred, make_import,
		PredSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "use_pred", [PredSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_predicate_specifier, make_pred, make_use,
		PredSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "export_pred", [PredSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_predicate_specifier, make_pred, make_export,
		PredSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "import_func", [FuncSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_function_specifier, make_func, make_import,
		FuncSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "use_func", [FuncSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_function_specifier, make_func, make_use,
		FuncSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "export_func", [FuncSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_function_specifier, make_func, make_export,
		FuncSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "import_cons", [ConsSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_constructor_specifier, make_cons, make_import,
		ConsSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "use_cons", [ConsSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_constructor_specifier, make_cons, make_use,
		ConsSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "export_cons", [ConsSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_constructor_specifier, make_cons, make_export,
		ConsSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "import_type", [TypeSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_type_specifier, make_type, make_import,
		TypeSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "use_type", [TypeSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_type_specifier, make_type, make_use,
		TypeSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "export_type", [TypeSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_type_specifier, make_type, make_export,
		TypeSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "import_adt", [ADT_Spec], Attributes,
		Result) :-
	parse_symlist_decl(parse_adt_specifier, make_adt, make_import,
		ADT_Spec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "use_adt", [ADT_Spec], Attributes, Result) :-
	parse_symlist_decl(parse_adt_specifier, make_adt, make_use,
		ADT_Spec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "export_adt", [ADT_Spec], Attributes,
		Result) :-
	parse_symlist_decl(parse_adt_specifier, make_adt, make_export,
		ADT_Spec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "import_op", [OpSpec], Attributes,
		Result) :-
	parse_symlist_decl(parse_op_specifier, make_op, make_import,
		OpSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "use_op", [OpSpec], Attributes, Result) :-
	parse_symlist_decl(parse_op_specifier, make_op, make_use,
		OpSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet, "export_op", [OpSpec], Attributes, Result) :-
	parse_symlist_decl(parse_op_specifier, make_op, make_export,
		OpSpec, Attributes, VarSet, Result).

process_decl(_ModuleName, VarSet0, "interface", [], Attributes, Result) :-
	varset__coerce(VarSet0, VarSet),
	Result0 = ok(module_defn(VarSet, interface)),
	check_no_attributes(Result0, Attributes, Result).

process_decl(_ModuleName, VarSet0, "implementation", [], Attributes, Result) :-
	varset__coerce(VarSet0, VarSet),
	Result0 = ok(module_defn(VarSet, implementation)),
	check_no_attributes(Result0, Attributes, Result).

process_decl(_ModuleName, VarSet, "external", [PredSpec], Attributes,
		Result) :-
	parse_symbol_name_specifier(PredSpec, Result0),
	process_maybe1(make_external(VarSet), Result0, Result1),
	check_no_attributes(Result1, Attributes, Result).

process_decl(DefaultModuleName, VarSet0, "module", [ModuleName], Attributes,
		Result) :-
	parse_module_name(DefaultModuleName, ModuleName, Result0),
	(	
		Result0 = ok(ModuleNameSym), 
		varset__coerce(VarSet0, VarSet),
		Result1 = ok(module_defn(VarSet, module(ModuleNameSym)))
	;	
		Result0 = error(A, B),
		Result1 = error(A, B)
	),
	check_no_attributes(Result1, Attributes, Result).

process_decl(DefaultModuleName, VarSet0, "include_module", [ModuleNames],
		Attributes, Result) :-
	parse_list(parse_module_name(DefaultModuleName), ModuleNames, Result0),
	(	
		Result0 = ok(ModuleNameSyms), 
		varset__coerce(VarSet0, VarSet),
		Result1 = ok(module_defn(VarSet,
				include_module(ModuleNameSyms)))
	;	
		Result0 = error(A, B),
		Result1 = error(A, B)
	),
	check_no_attributes(Result1, Attributes, Result).

process_decl(DefaultModuleName, VarSet0, "end_module", [ModuleName],
		Attributes, Result) :-
	%
	% The name in an `end_module' declaration not inside the
	% scope of the module being ended, so the default module name
	% here is the parent of the previous default module name.
	%
	root_module_name(RootModuleName),
	sym_name_get_module_name(DefaultModuleName, RootModuleName,
		ParentOfDefaultModuleName),
	parse_module_name(ParentOfDefaultModuleName, ModuleName, Result0),
	(	
		Result0 = ok(ModuleNameSym), 
		varset__coerce(VarSet0, VarSet),
		Result1 = ok(module_defn(VarSet, end_module(ModuleNameSym)))
	;	
		Result0 = error(A, B),
		Result1 = error(A, B)
	),
	check_no_attributes(Result1, Attributes, Result).

	% NU-Prolog `when' declarations used to be silently ignored for
	% backwards compatibility.  We now issue a warning that they
	% are deprecated.  We should eventually drop support for them
	% entirely.
process_decl(_ModuleName, _VarSet, "when", [_Goal, _Cond], Attributes,
		Result) :-
	Result0 = ok(nothing),
	check_no_attributes(Result0, Attributes, Result).

process_decl(ModuleName, VarSet, "pragma", Pragma, Attributes, Result):-
	parse_pragma(ModuleName, VarSet, Pragma, Result0),
	check_no_attributes(Result0, Attributes, Result).

process_decl(ModuleName, VarSet, "promise", Assertion, Attributes, Result):-
	parse_assertion(ModuleName, VarSet, Assertion, Result0),
	check_no_attributes(Result0, Attributes, Result).

process_decl(ModuleName, VarSet, "typeclass", Args, Attributes, Result):-
	parse_typeclass(ModuleName, VarSet, Args, Result0),
	check_no_attributes(Result0, Attributes, Result).

process_decl(ModuleName, VarSet, "instance", Args, Attributes, Result):-
	parse_instance(ModuleName, VarSet, Args, Result0),
	check_no_attributes(Result0, Attributes, Result).

:- pred parse_decl_attribute(string, list(term), decl_attribute, term).
:- mode parse_decl_attribute(in, in, out, out) is semidet.

parse_decl_attribute("impure", [Decl], purity(impure), Decl).
parse_decl_attribute("semipure", [Decl], purity(semipure), Decl).
parse_decl_attribute("<=", [Decl, Constraints],
		constraints(univ, Constraints), Decl).
parse_decl_attribute("=>", [Decl, Constraints],
		constraints(exist, Constraints), Decl).
parse_decl_attribute("some", [TVars0, Decl],
		quantifier(exist, TVarsList), Decl) :-
	term__coerce(TVars0, TVars),
	parse_list_of_vars(TVars, TVarsList).
parse_decl_attribute("all", [TVars0, Decl],
		quantifier(univ, TVarsList), Decl) :-
	term__coerce(TVars0, TVars),
	parse_list_of_vars(TVars, TVarsList).

:- pred check_no_attributes(maybe1(item), decl_attrs, maybe1(item)).
:- mode check_no_attributes(in, in, out) is det.

check_no_attributes(Result0, Attributes, Result) :-
	(
		Result0 = ok(_),
		Attributes = [Attr - Term | _]
	->
		attribute_description(Attr, AttrDescr),
		string__append(AttrDescr, " not allowed here", Message),
		Result = error(Message, Term)
	;
		Result = Result0
	).

:- pred attribute_description(decl_attribute, string).
:- mode attribute_description(in, out) is det.

attribute_description(purity(_), "purity specifier").
attribute_description(quantifier(univ, _), "universal quantifier (`all')").
attribute_description(quantifier(exist, _), "existential quantifier (`some')").
attribute_description(constraints(univ, _), "type class constraint (`<=')").
attribute_description(constraints(exist, _),
	"existentially quantified type class constraint (`=>')").

%-----------------------------------------------------------------------------%

	% parse the assertion declaration. 
:- pred parse_assertion(module_name, varset, list(term), maybe1(item)).
:- mode parse_assertion(in, in, in, out) is semidet.

parse_assertion(_ModuleName, VarSet, [AssertionTerm], Result) :-
	varset__coerce(VarSet, ProgVarSet),
	parse_goal(AssertionTerm, ProgVarSet, AssertGoal, AssertVarSet),
	Result = ok(assertion(AssertGoal, AssertVarSet)).

%-----------------------------------------------------------------------------%

:- pred parse_type_decl(module_name, varset, term, maybe1(item)).
:- mode parse_type_decl(in, in, in, out) is det.
parse_type_decl(ModuleName, VarSet, TypeDecl, Result) :-
	( 
		TypeDecl = term__functor(term__atom(Name), Args, _),
		parse_type_decl_type(ModuleName, Name, Args, Cond, R) 
	->
		R1 = R,
		Cond1 = Cond
	;
		process_abstract_type(ModuleName, TypeDecl, R1),
		Cond1 = true
	),
	process_maybe1(make_type_defn(VarSet, Cond1), R1, Result).
		% we should check the condition for errs
		% (don't bother at the moment, since we ignore
		% conditions anyhow :-)

:- pred make_type_defn(varset, condition, type_defn, item).
:- mode make_type_defn(in, in, in, out) is det.

make_type_defn(VarSet0, Cond, TypeDefn, type_defn(VarSet, TypeDefn, Cond)) :-
	varset__coerce(VarSet0, VarSet).

:- pred make_external(varset, sym_name_specifier, item).
:- mode make_external(in, in, out) is det.

make_external(VarSet0, SymSpec, module_defn(VarSet, external(SymSpec))) :-
	varset__coerce(VarSet0, VarSet).

%-----------------------------------------------------------------------------%

	% add a warning message to the list of messages

:- pred add_warning(string, term, message_list, message_list).
:- mode add_warning(in, in, in, out) is det.
add_warning(Warning, Term, Msgs, [Msg - Term | Msgs]) :-
	string__append("Warning: ", Warning, Msg).

	% add an error message to the list of messages

:- pred add_error(string, term, message_list, message_list).
:- mode add_error(in, in, in, out) is det.
add_error(Error, Term, Msgs, [Msg - Term | Msgs]) :-
	string__append("Error: ", Error, Msg).

%-----------------------------------------------------------------------------%
	% parse_type_decl_type(Term, Condition, Result) succeeds
	% if Term is a "type" type declaration, and binds Condition
	% to the condition for that declaration (if any), and Result to
	% a representation of the declaration.

:- pred parse_type_decl_type(module_name, string, list(term), condition,
				maybe1(type_defn)).
:- mode parse_type_decl_type(in, in, in, out, out) is semidet.

parse_type_decl_type(ModuleName, "--->", [H, B], Condition, R) :-
	/* get_condition(...), */
	Condition = true,
	get_maybe_equality_pred(B, Body, EqualityPred),
	process_du_type(ModuleName, H, Body, EqualityPred, R).

parse_type_decl_type(ModuleName, "=", [H, B], Condition, R) :-
	get_condition(B, Body, Condition),
	process_uu_type(ModuleName, H, Body, R).

parse_type_decl_type(ModuleName, "==", [H, B], Condition, R) :-
	get_condition(B, Body, Condition),
	process_eqv_type(ModuleName, H, Body, R).

%-----------------------------------------------------------------------------%

	% parse_type_decl_pred(ModuleName, VarSet, Pred, Attributes, Result)
	% succeeds if Pred is a predicate type declaration, and binds Result
	% to a representation of the declaration.
:- pred parse_type_decl_pred(module_name, varset, term, decl_attrs,
		maybe1(item)).
:- mode parse_type_decl_pred(in, in, in, in, out) is det.

parse_type_decl_pred(ModuleName, VarSet, Pred, Attributes, R) :-
	get_condition(Pred, Body, Condition),
	get_determinism(Body, Body2, MaybeDeterminism),
        process_type_decl_pred(ModuleName, MaybeDeterminism, VarSet, Body2,
                                Condition, Attributes, R).

:- pred process_type_decl_pred(module_name, maybe1(maybe(determinism)), varset,
				term, condition, decl_attrs, maybe1(item)).
:- mode process_type_decl_pred(in, in, in, in, in, in, out) is det.

process_type_decl_pred(_MNm, error(Term, Reason), _, _, _, _,
			error(Term, Reason)).
process_type_decl_pred(ModuleName, ok(MaybeDeterminism), VarSet, Body,
			Condition, Attributes, R) :-
        process_pred(ModuleName, VarSet, Body, Condition, MaybeDeterminism,
		     Attributes, R).

%-----------------------------------------------------------------------------%

	% parse_type_decl_func(ModuleName, Varset, Func, Attributes, Result)
	% succeeds if Func is a function type declaration, and binds Result to
	% a representation of the declaration.
:- pred parse_type_decl_func(module_name, varset, term, decl_attrs,
		maybe1(item)).
:- mode parse_type_decl_func(in, in, in, in, out) is det.

parse_type_decl_func(ModuleName, VarSet, Func, Attributes, R) :-
	get_condition(Func, Body, Condition),
	get_determinism(Body, Body2, MaybeDeterminism),
        process_maybe1_to_t(process_func(ModuleName, VarSet, Body2, Condition,
					 Attributes), MaybeDeterminism, R).

%-----------------------------------------------------------------------------%

	% parse_mode_decl_pred(ModuleName, Pred, Condition, Result) succeeds
	% if Pred is a predicate mode declaration, and binds Condition
	% to the condition for that declaration (if any), and Result to
	% a representation of the declaration.
:- pred parse_mode_decl_pred(module_name, varset, term, maybe1(item)).
:- mode parse_mode_decl_pred(in, in, in, out) is det.

parse_mode_decl_pred(ModuleName, VarSet, Pred, Result) :-
	get_condition(Pred, Body, Condition),
	get_determinism(Body, Body2, MaybeDeterminism),
	process_maybe1_to_t(process_mode(ModuleName, VarSet, Body2, Condition),
			MaybeDeterminism, Result).

%-----------------------------------------------------------------------------%

	% get_maybe_equality_pred(Body0, Body, MaybeEqualPred):
	%	Checks if `Body0' is a term of the form
	%		`<body> where equality is <symname>'
	%	If so, returns the `<body>' in Body and the <symname> in
	%	MaybeEqualPred.  If not, returns Body = Body0 
	%	and `no' in MaybeEqualPred.

:- pred get_maybe_equality_pred(term, term, maybe1(maybe(sym_name))).
:- mode get_maybe_equality_pred(in, out, out) is det.

get_maybe_equality_pred(B, Body, MaybeEqualityPred) :-
	( 
		B = term__functor(term__atom("where"), Args, _Context1),
		Args = [Body1, Equality_Is_PredName]
	->
		Body = Body1,
		( 
			Equality_Is_PredName = term__functor(term__atom("is"),
				[Equality, PredName], _),
			Equality = term__functor(term__atom("equality"), [], _)
		->
			parse_symbol_name(PredName, MaybeEqualityPred0),
			process_maybe1(make_yes, MaybeEqualityPred0,
				MaybeEqualityPred)
		;
			MaybeEqualityPred = error("syntax error after `where'",
				Body)
		)
	;
		Body = B,
		MaybeEqualityPred = ok(no)
	).

:- pred make_yes(T::in, maybe(T)::out) is det.
make_yes(T, yes(T)).

	% get_determinism(Term0, Term, Determinism) binds Determinism
	% to a representation of the determinism condition of Term0, if any,
	% and binds Term to the other part of Term0. If Term0 does not
	% contain a determinism, then Determinism is bound to `unspecified'.

:- pred get_determinism(term, term, maybe1(maybe(determinism))).
:- mode get_determinism(in, out, out) is det.

get_determinism(B, Body, Determinism) :-
	( 
		B = term__functor(term__atom("is"), Args, _Context1),
		Args = [Body1, Determinism1]
	->
		Body = Body1,
		( 
		    (
			Determinism1 = term__functor(term__atom(Determinism2),
				[], _Context2),
			standard_det(Determinism2, Determinism3)
		    )
		->
			Determinism = ok(yes(Determinism3))
		;
			Determinism = error("invalid category", Determinism1)
		)
	;
		Body = B,
		Determinism = ok(no)
	).

%-----------------------------------------------------------------------------%

	% get_condition(Term0, Term, Condition) binds Condition
	% to a representation of the 'where' condition of Term0, if any,
	% and binds Term to the other part of Term0. If Term0 does not
	% contain a condition, then Condition is bound to true.

:- pred get_condition(term, term, condition).
:- mode get_condition(in, out, out) is det.

get_condition(Body, Body, true).

/********
% NU-Prolog supported type declarations of the form
%	:- pred p(T) where p(X) : sorted(X).
% or
%	:- type sorted_list(T) = list(T) where X : sorted(X).
%	:- pred p(sorted_list(T).
% There is some code here to support that sort of thing, but
% probably we would now need to use a different syntax, since
% Mercury now uses `where' for different purposes (e.g. specifying
% user-defined equality predicates; also for type classes, eventually...)
%
get_condition(B, Body, Condition) :-
	( 
		B = term__functor(term__atom("where"), [Body1, Condition1],
					_Context)
	->
		Body = Body1,
		Condition = where(Condition1)
	;
		Body = B,
		Condition = true
	).
********/

%-----------------------------------------------------------------------------%

	% This is for "Head = Body" (undiscriminated union) definitions.
:- pred process_uu_type(module_name, term, term, maybe1(type_defn)).
:- mode process_uu_type(in, in, in, out) is det.
process_uu_type(ModuleName, Head, Body, Result) :-
	check_for_errors(ModuleName, Head, Body, Result0),
	process_uu_type_2(Result0, Body, Result).

:- pred process_uu_type_2(maybe_functor, term, maybe1(type_defn)).
:- mode process_uu_type_2(in, in, out) is det.
process_uu_type_2(error(Error, Term), _, error(Error, Term)).
process_uu_type_2(ok(Name, Args0), Body0, ok(uu_type(Name, Args, List))) :-
	list__map(term__coerce, Args0, Args),
	term__coerce(Body0, Body),
	sum_to_list(Body, List).

%-----------------------------------------------------------------------------%

	% This is for "Head == Body" (equivalence) definitions.
:- pred process_eqv_type(module_name, term, term, maybe1(type_defn)).
:- mode process_eqv_type(in, in, in, out) is det.
process_eqv_type(ModuleName, Head, Body, Result) :-
	check_for_errors(ModuleName, Head, Body, Result0),
	process_eqv_type_2(Result0, Body, Result).

:- pred process_eqv_type_2(maybe_functor, term, maybe1(type_defn)).
:- mode process_eqv_type_2(in, in, out) is det.
process_eqv_type_2(error(Error, Term), _, error(Error, Term)).
process_eqv_type_2(ok(Name, Args0), Body0, Result) :-
	% check that all the variables in the body occur in the head
	(
		(
			term__contains_var(Body0, Var2),
			\+ term__contains_var_list(Args0, Var2)
		)
	->
		Result = error("free type parameter in RHS of type definition",
				Body0)
	;
		list__map(term__coerce, Args0, Args),
		term__coerce(Body0, Body),
		Result = ok(eqv_type(Name, Args, Body))
	).

%-----------------------------------------------------------------------------%

	% process_du_type(ModuleName, TypeHead, TypeBody, Result)
	% checks that its arguments are well formed, and if they are,
	% binds Result to a representation of the type information about the
	% TypeHead.
	% This is for "Head ---> Body" (constructor) definitions.
:- pred process_du_type(module_name, term, term, maybe1(maybe(equality_pred)),
			maybe1(type_defn)).
:- mode process_du_type(in, in, in, in, out) is det.
process_du_type(ModuleName, Head, Body, EqualityPred, Result) :-
	check_for_errors(ModuleName, Head, Body, Result0),
	process_du_type_2(ModuleName, Result0, Body, EqualityPred, Result).

:- pred process_du_type_2(module_name, maybe_functor, term,
			maybe1(maybe(equality_pred)), maybe1(type_defn)).
:- mode process_du_type_2(in, in, in, in, out) is det.
process_du_type_2(_, error(Error, Term), _, _, error(Error, Term)).
process_du_type_2(ModuleName, ok(Functor, Args0), Body, MaybeEqualityPred,
		Result) :-
	% check that body is a disjunction of constructors
	list__map(term__coerce, Args0, Args),
	(
		convert_constructors(ModuleName, Body, Constrs)
	->
		% check that all type variables in the body
		% are either explicitly existentially quantified
		% or occur in the head.
		(
			list__member(Ctor, Constrs),
			Ctor = ctor(ExistQVars, _Constraints, _CtorName,
					CtorArgs),
			assoc_list__values(CtorArgs, CtorArgTypes),
			term__contains_var_list(CtorArgTypes, Var),
			\+ list__member(Var, ExistQVars),
			\+ term__contains_var_list(Args, Var)
		->
			Result = error(
			"free type parameter in RHS of type definition",
					Body)
		
		% check that all type variables in existential quantifiers
		% do not occur in the head
		% (maybe this should just be a warning, not an error?
		% If we were to allow it, we would need to rename them apart.)
		;
			list__member(Ctor, Constrs),
			Ctor = ctor(ExistQVars, _Constraints, _CtorName,
					_CtorArgs),
			list__member(Var, ExistQVars),
			term__contains_var_list(Args, Var)
		->
			Result = error( "type variable has overlapping scopes (explicit type quantifier shadows argument type)", Body)

		% check that all type variables in existential quantifiers
		% occur somewhere in the constructor argument types
		% (not just the constraints)
		;
			list__member(Ctor, Constrs),
			Ctor = ctor(ExistQVars, _Constraints, _CtorName,
					CtorArgs),
			list__member(Var, ExistQVars),
			assoc_list__values(CtorArgs, CtorArgTypes),
			\+ term__contains_var_list(CtorArgTypes, Var)
		->
			Result = error(
"type variable in existential quantifier does not occur in arguments of constructor",
					Body)
		% check that all type variables in existential constraints
		% occur in the existential quantifiers
		% (XXX is this check overly conservative? Perhaps we should
		% allow existential constraints so long as they contain
		% at least one type variable which is existentially quantified,
		% rather than requiring all variables in them to be
		% existentially quantified.)
		;
			list__member(Ctor, Constrs),
			Ctor = ctor(ExistQVars, Constraints, _CtorName,
					_CtorArgs),
			list__member(Constraint, Constraints),
			Constraint = constraint(_Name, ConstraintArgs),
			term__contains_var_list(ConstraintArgs, Var),
			\+ list__member(Var, ExistQVars)
		->
			Result = error("type variables in class constraints introduced with `=>' must be explicitly existentially quantified using `some'",
					Body)
		;
			(
				MaybeEqualityPred = ok(EqualityPred),
				Result = ok(du_type(Functor, Args, Constrs,
							EqualityPred))
			;
				MaybeEqualityPred = error(Error, Term),
				Result = error(Error, Term)
			)
		)
	;
		Result = error("invalid RHS of type definition", Body)
	).

%-----------------------------------------------------------------------------%

	% process_abstract_type(ModuleName, TypeHead, Result)
	% checks that its argument is well formed, and if it is,
	% binds Result to a representation of the type information about the
	% TypeHead.

:- pred process_abstract_type(module_name, term, maybe1(type_defn)).
:- mode process_abstract_type(in, in, out) is det.
process_abstract_type(ModuleName, Head, Result) :-
	dummy_term(Body),
	check_for_errors(ModuleName, Head, Body, Result0),
	process_abstract_type_2(Result0, Result).

:- pred process_abstract_type_2(maybe_functor, maybe1(type_defn)).
:- mode process_abstract_type_2(in, out) is det.
process_abstract_type_2(error(Error, Term), error(Error, Term)).
process_abstract_type_2(ok(Functor, Args0), ok(abstract_type(Functor, Args))) :-
	list__map(term__coerce, Args0, Args).

%-----------------------------------------------------------------------------%

	%  check a type definition for errors

:- pred check_for_errors(module_name, term, term, maybe_functor).
:- mode check_for_errors(in, in, in, out) is det.
check_for_errors(ModuleName, Head, Body, Result) :-
	( Head = term__variable(_) ->
		%
		% `Head' has no term__context, so we need to get the
		% context from `Body'
		%
		( Body = term__functor(_, _, Context) ->
			dummy_term_with_context(Context, ErrorTerm)
		;
			dummy_term(ErrorTerm)
		),
		Result = error("variable on LHS of type definition", ErrorTerm)
	;
		parse_implicitly_qualified_term(ModuleName,
			Head, Head, "type definition", R),
		check_for_errors_2(R, Body, Head, Result)
	).

:- pred check_for_errors_2(maybe_functor, term, term, maybe_functor).
:- mode check_for_errors_2(in, in, in, out) is det.
check_for_errors_2(error(Msg, Term), _, _, error(Msg, Term)).
check_for_errors_2(ok(Name, Args), Body, Head, Result) :-
	check_for_errors_3(Name, Args, Body, Head, Result).

:- pred check_for_errors_3(sym_name, list(term), term, term, maybe_functor).
:- mode check_for_errors_3(in, in, in, in, out) is det.
check_for_errors_3(Name, Args, _Body, Head, Result) :-
	% check that all the head args are variables
	( %%%	some [Arg]
		(
			list__member(Arg, Args),
			Arg \= term__variable(_)
		)
	->
		Result = error("type parameters must be variables", Head)
	;
	% check that all the head arg variables are distinct
	  %%%	some [Arg2, OtherArgs]
		(
			list__member(Arg2, Args, [Arg2|OtherArgs]),
			list__member(Arg2, OtherArgs)
		)
	->
		Result = error("repeated type parameters in LHS of type defn", Head)
	;
		Result = ok(Name, Args)
	).

%-----------------------------------------------------------------------------%

	% Convert a list of terms separated by semi-colons
	% (known as a "disjunction", even thought the terms aren't goals
	% in this case) into a list of constructors

:- pred convert_constructors(module_name, term, list(constructor)).
:- mode convert_constructors(in, in, out) is semidet.
convert_constructors(ModuleName, Body, Constrs) :-
	disjunction_to_list(Body, List),
	convert_constructors_2(ModuleName, List, Constrs).

	% true if input argument is a valid list of constructors

:- pred convert_constructors_2(module_name, list(term), list(constructor)).
:- mode convert_constructors_2(in, in, out) is semidet.
convert_constructors_2(_, [], []).
convert_constructors_2(ModuleName, [Term | Terms], [Constr | Constrs]) :-
	convert_constructor(ModuleName, Term, Constr),
	convert_constructors_2(ModuleName, Terms, Constrs).

	% true if input argument is a valid constructor.

:- pred convert_constructor(module_name, term, constructor).
:- mode convert_constructor(in, in, out) is semidet.
convert_constructor(ModuleName, Term0, Result) :-
	( 
		Term0 = term__functor(term__atom("some"), [Vars, Term1], _)
	->
		parse_list_of_vars(Vars, ExistQVars0),
		list__map(term__coerce_var, ExistQVars0, ExistQVars),
		Term2 = Term1
	;
		ExistQVars = [],
		Term2 = Term0
	),
	get_existential_constraints_from_term(ModuleName, Term2, Term3,
		ok(Constraints)),
	( 
		% Note that as a special case, one level of
		% curly braces around the constructor are ignored.
		% This is to allow you to define ';'/2 and 'some'/2
		% constructors.
		Term3 = term__functor(term__atom("{}"), [Term4], _Context)
	->
		Term5 = Term4
	;
		Term5 = Term3
	),
	parse_implicitly_qualified_term(ModuleName,
		Term5, Term0, "constructor definition", ok(F, As)),
	convert_constructor_arg_list(ModuleName, As, Args),
	Result = ctor(ExistQVars, Constraints, F, Args).

%-----------------------------------------------------------------------------%

	% parse a `:- pred p(...)' declaration

:- pred process_pred(module_name, varset, term, condition, maybe(determinism),
			decl_attrs, maybe1(item)).
:- mode process_pred(in, in, in, in, in, in, out) is det.

process_pred(ModuleName, VarSet, PredType, Cond, MaybeDet, Attributes0,
		Result) :-
	get_class_context(ModuleName, Attributes0, Attributes, MaybeContext),
	(
		MaybeContext = ok(ExistQVars, Constraints),
		parse_implicitly_qualified_term(ModuleName,
			PredType, PredType, "`:- pred' declaration",
			R),
		process_pred_2(R, PredType, VarSet, MaybeDet, Cond,
			ExistQVars, Constraints, Attributes, Result)
	;
		MaybeContext = error(String, Term),
		Result = error(String, Term)
	).

:- pred process_pred_2(maybe_functor, term, varset, maybe(determinism),
			condition, existq_tvars, class_constraints, decl_attrs,
			maybe1(item)).
:- mode process_pred_2(in, in, in, in, in, in, in, in, out) is det.

process_pred_2(ok(F, As0), PredType, VarSet0, MaybeDet, Cond, ExistQVars,
		ClassContext, Attributes0, Result) :-
	( convert_type_and_mode_list(As0, As) ->
		( verify_type_and_mode_list(As) ->
	        	get_purity(Attributes0, Purity, Attributes),
			varset__coerce(VarSet0, TVarSet),
			varset__coerce(VarSet0, IVarSet),
			Result0 = ok(pred(TVarSet, IVarSet, ExistQVars, F,
				As, MaybeDet, Cond, Purity, ClassContext)),
			check_no_attributes(Result0, Attributes, Result)
		;
			Result = error("some but not all arguments have modes",
				PredType)
		)
	;
		Result = error("syntax error in `:- pred' declaration",
				PredType)
	).
process_pred_2(error(M, T), _, _, _, _, _, _, _, error(M, T)).

:- pred get_purity(decl_attrs, purity, decl_attrs).
:- mode get_purity(in, out, out) is det.

get_purity(Attributes0, Purity, Attributes) :-
	( Attributes0 = [purity(Purity0) - _ | Attributes1] ->
		Purity = Purity0,
		Attributes = Attributes1
	;
		Purity = (pure),
		Attributes = Attributes0
	).

%-----------------------------------------------------------------------------%

	% We could perhaps get rid of some code duplication between here and
	% prog_io_typeclass.m?

	% get_class_context(ModuleName, Attributes0, Attributes, MaybeContext):
	% Parse type quantifiers and type class constraints from the
	% declaration attributes in Attributes0.
	% MaybeContext is either bound to the correctly parsed context, or
	% an appropriate error message (if there was a syntax error).
	% Attributes is bound to the remaining attributes.

:- pred get_class_context(module_name, decl_attrs, decl_attrs,
			maybe2(existq_tvars, class_constraints)).
:- mode get_class_context(in, in, out, out) is det.

get_class_context(ModuleName, RevAttributes0, RevAttributes, MaybeContext) :-
	%
	% constraints and quantifiers should occur in the following
	% order (outermost to innermost):
	%
	%					operator	precedence
	%					-------         ----------
	%	1. universal quantifiers	all		950
	%	2. existential quantifiers	some		950
	%	3. universal constraints	<=		920
	%	4. existential constraints	=>		920	[*]
	%	5. the decl itself 		pred or func	800
	%
	% When we reach here, Attributes0 contains declaration attributes
	% in the opposite order -- innermost to outermost -- so we reverse
	% them before we start.
	%
	% [*] Note that the semantic meaning of `=>' is not quite
	%     the same as implication; logically speaking it's more
	%     like conjunction.  Oh well, at least it has the right
	%     precedence.
	%
	% In theory it could make sense to allow the order of 2 & 3 to be
	% swapped, or (in the case of multiple constraints & multiple
	% quantifiers) to allow arbitrary interleaving of 2 & 3, but in
	% practice it seems there would be little benefit in allowing that
	% flexibility, so we don't.
	%
	% Universal quantification is the default, so we just ignore
	% universal quantifiers.  (XXX It might be a good idea to check
	% that any universally quantified type variables do actually
	% occur somewhere in the type declaration, and are not also
	% existentially quantified, and if not, issue a warning or
	% error message.)

	list__reverse(RevAttributes0, Attributes0),
	get_quant_tvars(univ, ModuleName, Attributes0, [],
					Attributes1, _UnivQVars),
	get_quant_tvars(exist, ModuleName, Attributes1, [],
					Attributes2, ExistQVars),
	get_constraints(univ, ModuleName, Attributes2,
					Attributes3, MaybeUnivConstraints),
	get_constraints(exist, ModuleName, Attributes3,
					Attributes, MaybeExistConstraints),
	list__reverse(Attributes, RevAttributes),

	combine_quantifier_results(MaybeUnivConstraints, MaybeExistConstraints,
			ExistQVars, MaybeContext).

:- pred combine_quantifier_results(maybe1(list(class_constraint)),
		maybe1(list(class_constraint)), existq_tvars,
		maybe2(existq_tvars, class_constraints)).
:- mode combine_quantifier_results(in, in, in, out) is det.

combine_quantifier_results(error(Msg, Term), _, _, error(Msg, Term)).
combine_quantifier_results(ok(_), error(Msg, Term), _, error(Msg, Term)).
combine_quantifier_results(
	ok(UnivConstraints), ok(ExistConstraints), ExistQVars,
	ok(ExistQVars, constraints(UnivConstraints, ExistConstraints))).

:- pred get_quant_tvars(quantifier_type, module_name, decl_attrs, list(tvar),
		decl_attrs, list(tvar)).
:- mode get_quant_tvars(in, in, in, in, out, out) is det.

get_quant_tvars(QuantType, ModuleName, Attributes0, TVars0,
		Attributes, TVars) :-
	(	
		Attributes0 = [quantifier(QuantType, TVars1) - _ | Attributes1]
	->
		list__append(TVars0, TVars1, TVars2),
		get_quant_tvars(QuantType, ModuleName, Attributes1, TVars2,
			Attributes, TVars)
	;
		Attributes = Attributes0,
		TVars = TVars0
	).

:- pred get_constraints(quantifier_type, module_name, decl_attrs, decl_attrs, 
			maybe1(list(class_constraint))).
:- mode get_constraints(in, in, in, out, out) is det.

get_constraints(QuantType, ModuleName, Attributes0, Attributes,
		MaybeConstraints) :-
	(	
		Attributes0 = [constraints(QuantType, ConstraintsTerm) - _Term
				| Attributes1]
	->
		parse_class_constraints(ModuleName, ConstraintsTerm,
			MaybeConstraints0),
		% there may be more constraints of the same type --
		% collect them all and combine them
		get_constraints(QuantType, ModuleName, Attributes1,
			Attributes, MaybeConstraints1),
		combine_constraint_list_results(MaybeConstraints1,
			MaybeConstraints0, MaybeConstraints)
	;
		Attributes = Attributes0,
		MaybeConstraints = ok([])
	).

:- pred combine_constraint_list_results(maybe1(list(class_constraint)),
	maybe1(list(class_constraint)), maybe1(list(class_constraint))).
:- mode combine_constraint_list_results(in, in, out) is det.

combine_constraint_list_results(error(Msg, Term), _, error(Msg, Term)).
combine_constraint_list_results(ok(_), error(Msg, Term), error(Msg, Term)).
combine_constraint_list_results(ok(Constraints0), ok(Constraints1),
		ok(Constraints)) :-
	list__append(Constraints0, Constraints1, Constraints).

:- pred get_existential_constraints_from_term(module_name, term, term,
			maybe1(list(class_constraint))).
:- mode get_existential_constraints_from_term(in, in, out, out) is det.

get_existential_constraints_from_term(ModuleName, PredType0, PredType,
		MaybeExistentialConstraints) :-
	(	
		PredType0 = term__functor(term__atom("=>"), 
			[PredType1, ExistentialConstraints], _)
	->
		PredType = PredType1,
		parse_class_constraints(ModuleName, ExistentialConstraints,
			MaybeExistentialConstraints)
	;
		PredType = PredType0,
		MaybeExistentialConstraints = ok([])
	).

%-----------------------------------------------------------------------------%

	% Verify that among the arguments of a :- pred declaration,
	% either all arguments specify a mode or none of them do.

:- pred verify_type_and_mode_list(list(type_and_mode)).
:- mode verify_type_and_mode_list(in) is semidet.

verify_type_and_mode_list([]).
verify_type_and_mode_list([First | Rest]) :-
	verify_type_and_mode_list_2(Rest, First).

:- pred verify_type_and_mode_list_2(list(type_and_mode), type_and_mode).
:- mode verify_type_and_mode_list_2(in, in) is semidet.

verify_type_and_mode_list_2([], _).
verify_type_and_mode_list_2([Head | Tail], First) :-
	(
		Head = type_only(_),
		First = type_only(_)
	;
		Head = type_and_mode(_, _),
		First = type_and_mode(_, _)
	),
	verify_type_and_mode_list_2(Tail, First).

%-----------------------------------------------------------------------------%

	% parse a `:- func p(...)' declaration

:- pred process_func(module_name, varset, term, condition, decl_attrs,
			maybe(determinism), maybe1(item)).
:- mode process_func(in, in, in, in, in, in, out) is det.

process_func(ModuleName, VarSet, Term, Cond, Attributes0, MaybeDet, Result) :-
	get_class_context(ModuleName, Attributes0, Attributes, MaybeContext),
	(
		MaybeContext = ok(ExistQVars, Constraints),
		process_func_2(ModuleName, VarSet, Term,
			Cond, MaybeDet, ExistQVars, Constraints, Attributes,
			Result) 
	;
		MaybeContext = error(String, ErrorTerm),
		Result = error(String, ErrorTerm)
	).

:- pred process_func_2(module_name, varset, term, condition,
	maybe(determinism), existq_tvars, class_constraints, decl_attrs,
	maybe1(item)).
:- mode process_func_2(in, in, in, in, in, in, in, in, out) is det.

process_func_2(ModuleName, VarSet, Term, Cond, MaybeDet, 
		ExistQVars, Constraints, Attributes, Result) :-
	(
		Term = term__functor(term__atom("="),
				[FuncTerm, ReturnTypeTerm], _Context)
	->
		parse_implicitly_qualified_term(ModuleName, FuncTerm, Term,
			"`:- func' declaration", R),
		process_func_3(R, FuncTerm, ReturnTypeTerm, VarSet, MaybeDet,
				Cond, ExistQVars, Constraints, Attributes,
				Result)
	;
		Result = error("`=' expected in `:- func' declaration", Term)
	).


:- pred process_func_3(maybe_functor, term, term, varset, maybe(determinism),
			condition, existq_tvars, class_constraints, decl_attrs,
			maybe1(item)).
:- mode process_func_3(in, in, in, in, in, in, in, in, in, out) is det.

process_func_3(ok(F, As0), FuncTerm, ReturnTypeTerm, VarSet0, MaybeDet, Cond,
		ExistQVars, ClassContext, Attributes0, Result) :-
	( convert_type_and_mode_list(As0, As) ->
		( \+ verify_type_and_mode_list(As) ->
			Result = error("some but not all arguments have modes",
					FuncTerm)
		; convert_type_and_mode(ReturnTypeTerm, ReturnType) ->
			(
				As = [type_and_mode(_, _) | _],
				ReturnType = type_only(_)
			->
				Result = error(
		"function arguments have modes, but function result doesn't",
					FuncTerm)
			;
				As = [type_only(_) | _],
				ReturnType = type_and_mode(_, _)
			->
				Result = error(
		"function result has mode, but function arguments don't",
					FuncTerm)
			;
				get_purity(Attributes0, Purity, Attributes),
				varset__coerce(VarSet0, TVarSet),
				varset__coerce(VarSet0, IVarSet),
				Result0 = ok(func(TVarSet, IVarSet, ExistQVars,
					F, As, ReturnType, MaybeDet, Cond,
					Purity, ClassContext)),
				check_no_attributes(Result0, Attributes,
					Result)
			)
		;
			Result = error(
			"syntax error in return type of `:- func' declaration",
					ReturnTypeTerm)
		)
	;
		Result = error(
			"syntax error in arguments of `:- func' declaration",
					FuncTerm)
	).
process_func_3(error(M, T), _, _, _, _, _, _, _, _, error(M, T)).

%-----------------------------------------------------------------------------%

	% parse a `:- mode p(...)' declaration

:- pred process_mode(module_name, varset, term, condition, maybe(determinism),
		maybe1(item)).
:- mode process_mode(in, in, in, in, in, out) is det.

process_mode(ModuleName, VarSet, Term, Cond, MaybeDet, Result) :-
	(
		Term = term__functor(term__atom("="),
				[FuncTerm, ReturnTypeTerm], _Context)
	->
		parse_implicitly_qualified_term(ModuleName, FuncTerm, Term,
				"function `:- mode' declaration", R),
		process_func_mode(R, FuncTerm, ReturnTypeTerm, VarSet, MaybeDet,
				Cond, Result)
	;
		parse_implicitly_qualified_term(ModuleName, Term, Term,
				"predicate `:- mode' declaration", R),
		process_pred_mode(R, Term, VarSet, MaybeDet, Cond, Result)
	).

:- pred process_pred_mode(maybe_functor, term, varset, maybe(determinism),
			condition, maybe1(item)).
:- mode process_pred_mode(in, in, in, in, in, out) is det.

process_pred_mode(ok(F, As0), PredMode, VarSet0, MaybeDet, Cond, Result) :-
	(
		convert_mode_list(As0, As1)
	->
		list__map(constrain_inst_vars_in_mode, As1, As),
		varset__coerce(VarSet0, VarSet),
		Result = ok(pred_mode(VarSet, F, As, MaybeDet, Cond))
	;
		Result = error("syntax error in predicate mode declaration",
				PredMode)
	).
process_pred_mode(error(M, T), _, _, _, _, error(M, T)).

:- pred process_func_mode(maybe_functor, term, term, varset, maybe(determinism),
			condition, maybe1(item)).
:- mode process_func_mode(in, in, in, in, in, in, out) is det.

process_func_mode(ok(F, As0), FuncMode, RetMode0, VarSet0, MaybeDet, Cond,
		Result) :-
	(
		convert_mode_list(As0, As1)
	->
		list__map(constrain_inst_vars_in_mode, As1, As),
		( convert_mode(RetMode0, RetMode1) ->
			constrain_inst_vars_in_mode(RetMode1, RetMode),
			varset__coerce(VarSet0, VarSet),
			Result = ok(func_mode(VarSet, F, As, RetMode, MaybeDet,
					Cond))
		;
			Result = error(
		"syntax error in return mode of function mode declaration",
					RetMode0)
		)
	;
		Result = error(
		"syntax error in arguments of function mode declaration",
				FuncMode)
	).
process_func_mode(error(M, T), _, _, _, _, _, error(M, T)).

%-----------------------------------------------------------------------------%

% Replace all occurrences of inst_var(I) with
% ground(shared, constrained_inst_var(I)).

:- pred constrain_inst_vars_in_mode(mode, mode).
:- mode constrain_inst_vars_in_mode(in, out) is det.

constrain_inst_vars_in_mode(I0 -> F0, I -> F) :-
	constrain_inst_vars_in_inst(I0, I),
	constrain_inst_vars_in_inst(F0, F).
constrain_inst_vars_in_mode(user_defined_mode(Name, Args0),
		user_defined_mode(Name, Args)) :-
	list__map(constrain_inst_vars_in_inst, Args0, Args).

:- pred constrain_inst_vars_in_inst(inst, inst).
:- mode constrain_inst_vars_in_inst(in, out) is det.

constrain_inst_vars_in_inst(any(U), any(U)).
constrain_inst_vars_in_inst(free, free).
constrain_inst_vars_in_inst(free(T), free(T)).
constrain_inst_vars_in_inst(bound(U, BIs0), bound(U, BIs)) :-
	list__map((pred(functor(C, Is0)::in, functor(C, Is)::out) is det :-
		list__map(constrain_inst_vars_in_inst, Is0, Is)), BIs0, BIs).
constrain_inst_vars_in_inst(ground(U, none), ground(U, none)).
constrain_inst_vars_in_inst(ground(U, higher_order(PredInstInfo0)),
		ground(U, higher_order(PredInstInfo))) :-
	constrain_inst_vars_in_pred_inst_info(PredInstInfo0, PredInstInfo).
constrain_inst_vars_in_inst(ground(U, constrained_inst_var(V)),
		ground(U, constrained_inst_var(V))).
constrain_inst_vars_in_inst(not_reached, not_reached).
constrain_inst_vars_in_inst(inst_var(V),
		ground(shared, constrained_inst_var(V))).
constrain_inst_vars_in_inst(defined_inst(Name0), defined_inst(Name)) :-
	constrain_inst_vars_in_inst_name(Name0, Name).
constrain_inst_vars_in_inst(abstract_inst(N, Is0), abstract_inst(N, Is)) :-
	list__map(constrain_inst_vars_in_inst, Is0, Is).

:- pred constrain_inst_vars_in_pred_inst_info(pred_inst_info, pred_inst_info).
:- mode constrain_inst_vars_in_pred_inst_info(in, out) is det.

constrain_inst_vars_in_pred_inst_info(PII0, PII) :-
	PII0 = pred_inst_info(PredOrFunc, Modes0, Det),
	list__map(constrain_inst_vars_in_mode, Modes0, Modes),
	PII = pred_inst_info(PredOrFunc, Modes, Det).

:- pred constrain_inst_vars_in_inst_name(inst_name, inst_name).
:- mode constrain_inst_vars_in_inst_name(in, out) is det.

constrain_inst_vars_in_inst_name(Name0, Name) :-
	( Name0 = user_inst(SymName, Args0) ->
		list__map(constrain_inst_vars_in_inst, Args0, Args),
		Name = user_inst(SymName, Args)
	;
		Name = Name0
	).

%-----------------------------------------------------------------------------%

	% Parse a `:- inst <InstDefn>.' declaration.
	%
	% `==' is the correct operator to use, although we accept
	% `=' as well.  Since `=' was once the standard operator, make
	% sure warnings are given before it is phased out.
	%
:- pred parse_inst_decl(module_name, varset, term, maybe1(item)).
:- mode parse_inst_decl(in, in, in, out) is det.
parse_inst_decl(ModuleName, VarSet, InstDefn, Result) :-
	(
		InstDefn = term__functor(term__atom(Op), [H, B], _Context),
		( Op = "=" ; Op = "==" )
	->
		get_condition(B, Body, Condition),
		convert_inst_defn(ModuleName, H, Body, R),
		process_maybe1(make_inst_defn(VarSet, Condition), R, Result)
	;
		% XXX this is for `abstract inst' declarations,
		% which are not really supported
		InstDefn = term__functor(term__atom("is"), [
				Head,
				term__functor(term__atom("private"), [], _)
			], _)
	->
		Condition = true,
		convert_abstract_inst_defn(ModuleName, Head, R),
		process_maybe1(make_inst_defn(VarSet, Condition), R, Result)
	;
		InstDefn = term__functor(term__atom("--->"), [H, B], Context)
	->
		get_condition(B, Body, Condition),
		Body1 = term__functor(term__atom("bound"), [Body], Context),
		convert_inst_defn(ModuleName, H, Body1, R),
		process_maybe1(make_inst_defn(VarSet, Condition), R, Result)
	;
		Result = error("`==' expected in `:- inst' definition", InstDefn)
	).
		% we should check the condition for errs
		% (don't bother at the moment, since we ignore
		% conditions anyhow :-)

	% Parse a `:- inst <Head> ---> <Body>.' definition.
	%
:- pred convert_inst_defn(module_name, term, term, maybe1(inst_defn)).
:- mode convert_inst_defn(in, in, in, out) is det.
convert_inst_defn(ModuleName, Head, Body, Result) :-
	parse_implicitly_qualified_term(ModuleName,
		Head, Body, "inst definition", R),
	convert_inst_defn_2(R, Head, Body, Result).

:- pred convert_inst_defn_2(maybe_functor, term, term, maybe1(inst_defn)).
:- mode convert_inst_defn_2(in, in, in, out) is det.

convert_inst_defn_2(error(M, T), _, _, error(M, T)).
convert_inst_defn_2(ok(Name, ArgTerms), Head, Body, Result) :-
	(
		% check that all the head args are variables
		term__var_list_to_term_list(Args, ArgTerms)
	->
		(
			% check that all the head arg variables are distinct
			list__member(Arg2, Args, [Arg2|OtherArgs]),
			list__member(Arg2, OtherArgs)
		->
			Result = error(
				"repeated inst parameters in LHS of inst defn",
				Head)
		;
			% check that all the variables in the body occur
			% in the head
			term__contains_var(Body, Var2),
			\+ list__member(Var2, Args)
		->
			Result = error(
				"free inst parameter in RHS of inst definition",
				Body)
		;
			% check that the inst is a valid user-defined
			% inst, i.e. that it does not have the form of
			% one of the builtin insts
			\+ (
				convert_inst(Head, UserInst),
				UserInst = defined_inst(user_inst(_, _))
			)
		->
			Result = error("attempt to redefine builtin inst", Head)
		;
			% should improve the error message here
			(
				convert_inst(Body, ConvertedBody)
			->
				list__map(term__coerce_var, Args, InstArgs),
				Result = ok(eqv_inst(Name, InstArgs,
					ConvertedBody))
			;
				Result = error("syntax error in inst body",
					Body)
			)
		)
	;
		Result = error("inst parameters must be variables", Head)
	).

:- pred convert_abstract_inst_defn(module_name, term, maybe1(inst_defn)).
:- mode convert_abstract_inst_defn(in, in, out) is det.
convert_abstract_inst_defn(ModuleName, Head, Result) :-
	parse_implicitly_qualified_term(ModuleName, Head, Head,
		"inst definition", R),
	convert_abstract_inst_defn_2(R, Head, Result).

:- pred convert_abstract_inst_defn_2(maybe_functor, term, maybe1(inst_defn)).
:- mode convert_abstract_inst_defn_2(in, in, out) is det.
convert_abstract_inst_defn_2(error(M, T), _, error(M, T)).
convert_abstract_inst_defn_2(ok(Name, ArgTerms), Head, Result) :-
	(
		% check that all the head args are variables
		term__var_list_to_term_list(Args, ArgTerms)
	->
		(
			% check that all the head arg variables are distinct
			list__member(Arg2, Args, [Arg2|OtherArgs]),
			list__member(Arg2, OtherArgs)
		->
			Result = error(
			"repeated inst parameters in abstract inst definition",
				Head)
		;
			list__map(term__coerce_var, Args, InstArgs),
			Result = ok(abstract_inst(Name, InstArgs))
		)
	;
		Result = error("inst parameters must be variables", Head)
	).

:- pred make_inst_defn(varset, condition, inst_defn, item).
:- mode make_inst_defn(in, in, in, out) is det.

make_inst_defn(VarSet0, Cond, InstDefn, inst_defn(VarSet, InstDefn, Cond)) :-
	varset__coerce(VarSet0, VarSet).

%-----------------------------------------------------------------------------%

	% parse a `:- mode foo :: ...' or `:- mode foo = ...' definition.

:- pred parse_mode_decl(module_name, varset, term, maybe1(item)).
:- mode parse_mode_decl(in, in, in, out) is det.
parse_mode_decl(ModuleName, VarSet, ModeDefn, Result) :-
	( %%% some [H, B]
		mode_op(ModeDefn, H, B)
	->
		get_condition(B, Body, Condition),
		convert_mode_defn(ModuleName, H, Body, R),
		process_maybe1(make_mode_defn(VarSet, Condition), R, Result)
	;
		parse_mode_decl_pred(ModuleName, VarSet, ModeDefn, Result)
	).

	% People never seemed to remember what the right operator to use
	% in a `:- mode' declaration is, so the syntax is accepted both
	% `::' and `==', with `::' formerly the standard operator.  
	%
	%	% Old syntax
	% :- mode foo :: someinst -> someotherinst.
	%
	% But using `==' was a pain, because the precedence of `->' was
	% too high.  We now accept `>>' as an alternative to `->', and
	% `==' is now the standard operator to use in a `:- mode'
	% declaration.  This is part of a long term plan to free up
	% `::' as an operator so we can use it for mode qualification.
	%
	%	% New syntax
	% :- mode foo == someinst >> someotherinst.
	%
	% We still support `::' in mode declarations for backwards
	% compatibility, but it might be removed one day.
	% Before phasing it out, a deprecated syntax warning should be
	% given for a version or two.
	%
:- pred mode_op(term, term, term).
:- mode mode_op(in, out, out) is semidet.
mode_op(term__functor(term__atom(Op), [H, B], _), H, B) :-
	( Op = "==" ; Op = "::" ).

:- pred convert_mode_defn(module_name, term, term, maybe1(mode_defn)).
:- mode convert_mode_defn(in, in, in, out) is det.
convert_mode_defn(ModuleName, Head, Body, Result) :-
	parse_implicitly_qualified_term(ModuleName, Head, Head,
		"mode definition", R),
	convert_mode_defn_2(R, Head, Body, Result).

:- pred convert_mode_defn_2(maybe_functor, term, term, maybe1(mode_defn)).
:- mode convert_mode_defn_2(in, in, in, out) is det.
convert_mode_defn_2(error(M, T), _, _, error(M, T)).
convert_mode_defn_2(ok(Name, ArgTerms), Head, Body, Result) :-
	(
		% check that all the head args are variables
		term__var_list_to_term_list(Args, ArgTerms)
	->
		(
			% check that all the head arg variables are distinct
			list__member(Arg2, Args, [Arg2|OtherArgs]),
			list__member(Arg2, OtherArgs)
		->
			Result = error(
				"repeated parameters in LHS of mode defn",
				Head)
			% check that all the variables in the body occur
			% in the head
		;
			term__contains_var(Body, Var2),
			\+ list__member(Var2, Args)
		->
			Result = error(
				"free inst parameter in RHS of mode definition",
				Body)
		;
			% should improve the error message here
			(
				convert_mode(Body, ConvertedBody)
			->
				list__map(term__coerce_var, Args, InstArgs),
				Result = ok(eqv_mode(Name, InstArgs,
					ConvertedBody))
			;
				% catch-all error message - we should do
				% better than this
				Result = error(
					"syntax error in mode definition body",
					Body)
			)
		)
	;
		Result = error("mode parameters must be variables", Head)
	).

:- pred convert_type_and_mode_list(list(term), list(type_and_mode)).
:- mode convert_type_and_mode_list(in, out) is semidet.
convert_type_and_mode_list([], []).
convert_type_and_mode_list([H0|T0], [H|T]) :-
	convert_type_and_mode(H0, H),
	convert_type_and_mode_list(T0, T).

:- pred convert_type_and_mode(term, type_and_mode).
:- mode convert_type_and_mode(in, out) is semidet.
convert_type_and_mode(Term, Result) :-
	(
		Term = term__functor(term__atom("::"), [TypeTerm, ModeTerm],
				_Context)
	->
		convert_type(TypeTerm, Type),
		convert_mode(ModeTerm, Mode0),
		constrain_inst_vars_in_mode(Mode0, Mode),
		Result = type_and_mode(Type, Mode)
	;
		convert_type(Term, Type),
		Result = type_only(Type)
	).

:- pred make_mode_defn(varset, condition, mode_defn, item).
:- mode make_mode_defn(in, in, in, out) is det.
make_mode_defn(VarSet0, Cond, ModeDefn, mode_defn(VarSet, ModeDefn, Cond)) :-
	varset__coerce(VarSet0, VarSet).

%-----------------------------------------------------------------------------%

:- type parser(T) == pred(term, maybe1(T)).
:- mode parser    :: pred(in, out) is det.

:- type maker(T1, T2) == pred(T1, T2).
:- mode maker         :: pred(in, out) is det.

:- pred parse_symlist_decl(parser(T), maker(list(T), sym_list),
			maker(sym_list, module_defn),
			term, decl_attrs, varset, maybe1(item)).
:- mode parse_symlist_decl(parser, maker, maker, in, in, in, out) is det.

parse_symlist_decl(ParserPred, MakeSymListPred, MakeModuleDefnPred,
			Term, Attributes, VarSet, Result) :-
	parse_list(ParserPred, Term, Result0),
	process_maybe1(make_module_defn(MakeSymListPred, MakeModuleDefnPred,
			VarSet), Result0, Result1),
	check_no_attributes(Result1, Attributes, Result).

:- pred make_module_defn(maker(T, sym_list), maker(sym_list, module_defn),
			varset, T, item).
:- mode make_module_defn(maker, maker, in, in, out) is det.
make_module_defn(MakeSymListPred, MakeModuleDefnPred, VarSet0, T,
		module_defn(VarSet, ModuleDefn)) :-
	varset__coerce(VarSet0, VarSet),
	call(MakeSymListPred, T, SymList),
	call(MakeModuleDefnPred, SymList, ModuleDefn).

%-----------------------------------------------------------------------------%

	% Parse a comma-separated list (misleading described as
	% a "conjunction") of things.

:- pred parse_list(parser(T), term, maybe1(list(T))).
:- mode parse_list(parser, in, out) is det.
parse_list(Parser, Term, Result) :-
	conjunction_to_list(Term, List),
	parse_list_2(List, Parser, Result).

:- pred parse_list_2(list(term), parser(T), maybe1(list(T))).
:- mode parse_list_2(in, parser, out) is det.
parse_list_2([], _, ok([])).
parse_list_2([X|Xs], Parser, Result) :-
	call(Parser, X, X_Result),
	parse_list_2(Xs, Parser, Xs_Result),
	combine_list_results(X_Result, Xs_Result, Result).

	% If a list of things contains multiple errors, then we only
	% report the first one.

:- pred combine_list_results(maybe1(T), maybe1(list(T)), maybe1(list(T))).
:- mode combine_list_results(in, in, out) is det.
combine_list_results(error(Msg, Term), _, error(Msg, Term)).
combine_list_results(ok(_), error(Msg, Term), error(Msg, Term)).
combine_list_results(ok(X), ok(Xs), ok([X|Xs])).

%-----------------------------------------------------------------------------%

:- pred process_maybe1(maker(T1, T2), maybe1(T1), maybe1(T2)).
:- mode process_maybe1(maker, in, out) is det.
process_maybe1(Maker, ok(X), ok(Y)) :- call(Maker, X, Y).
process_maybe1(_, error(M, T), error(M, T)).

:- pred process_maybe1_to_t(maker(T1, maybe1(T2)), maybe1(T1), maybe1(T2)).
:- mode process_maybe1_to_t(maker, in, out) is det.
process_maybe1_to_t(Maker, ok(X), Y) :- call(Maker, X, Y).
process_maybe1_to_t(_, error(M, T), error(M, T)).

%-----------------------------------------------------------------------------%

:- pred make_module(list(module_specifier)::in, sym_list::out) is det.
make_module(X, module(X)).

:- pred make_sym(list(sym_specifier)::in, sym_list::out) is det.
make_sym(X, sym(X)).

:- pred make_pred(list(pred_specifier)::in, sym_list::out) is det.
make_pred(X, pred(X)).

:- pred make_func(list(func_specifier)::in, sym_list::out) is det.
make_func(X, func(X)).

:- pred make_cons(list(cons_specifier)::in, sym_list::out) is det.
make_cons(X, cons(X)).

:- pred make_type(list(type_specifier)::in, sym_list::out) is det.
make_type(X, type(X)).

:- pred make_adt(list(adt_specifier)::in, sym_list::out) is det.
make_adt(X, adt(X)).

:- pred make_op(list(op_specifier)::in, sym_list::out) is det.
make_op(X, op(X)).

%-----------------------------------------------------------------------------%
%
%	A symbol specifier is one of
%
%		SymbolNameSpecifier
%			Matches any symbol matched by the SymbolNameSpecifier.
%		TypedConstructorSpecifier
%			Matches any constructors matched by the
%			TypedConstructorSpecifier.
%		cons(ConstructorSpecifier)
%			Matches only constructors.
%		pred(PredSpecifier)
%			Matches only predicates, ie. constructors of type
%			`pred'.
%		adt(SymbolNameSpecifier)
%			Matches only type names.
%		type(SymbolNameSpecifier)
%			Matches type names matched by the SymbolNameSpecifier,
%			and also matches any constructors for the matched type
%			names.
%		op(SymbolNameSpecifier)
%			Matches only operators.
%		module(ModuleSpecifier)
%			Matches all symbols in the specified module.

:- pred parse_symbol_specifier(term, maybe1(sym_specifier)).
:- mode parse_symbol_specifier(in, out) is det.

parse_symbol_specifier(MainTerm, Result) :-
	( MainTerm = term__functor(term__atom(Functor), [Term], _Context) ->
		( Functor = "cons" ->
			parse_constructor_specifier(Term, Result0),
			process_maybe1(make_cons_symbol_specifier, Result0,
				Result)
		; Functor = "pred" ->
			parse_predicate_specifier(Term, Result0),
			process_maybe1(make_pred_symbol_specifier, Result0,
				Result)
		; Functor = "func" ->
			parse_function_specifier(Term, Result0),
			process_maybe1(make_func_symbol_specifier, Result0,
				Result)
		; Functor = "type" ->
			parse_type_specifier(Term, Result0),
			process_maybe1(make_type_symbol_specifier, Result0,
				Result)
		; Functor = "adt" ->
			parse_adt_specifier(Term, Result0),
			process_maybe1(make_adt_symbol_specifier, Result0,
				Result)
		; Functor = "op" ->
			parse_op_specifier(Term, Result0),
			process_maybe1(make_op_symbol_specifier, Result0,
				Result)
		; Functor = "module" ->
			parse_module_specifier(Term, Result0),
			process_maybe1(make_module_symbol_specifier, Result0,
				Result)
		;
			parse_constructor_specifier(MainTerm, Result0),
			process_maybe1(make_cons_symbol_specifier, Result0,
				Result)
		)
	;
		parse_constructor_specifier(MainTerm, Result0),
		process_maybe1(make_cons_symbol_specifier, Result0, Result)
	).

% 	Once we've parsed the appropriate type of symbol specifier, we
%	need to convert it to a sym_specifier.

:- pred make_pred_symbol_specifier(pred_specifier::in, sym_specifier::out)
	is det.
make_pred_symbol_specifier(PredSpec, pred(PredSpec)).

:- pred make_func_symbol_specifier(func_specifier::in, sym_specifier::out)
	is det.
make_func_symbol_specifier(FuncSpec, func(FuncSpec)).

:- pred make_cons_symbol_specifier(cons_specifier::in, sym_specifier::out)
	is det.
make_cons_symbol_specifier(ConsSpec, cons(ConsSpec)).

:- pred make_type_symbol_specifier(type_specifier::in, sym_specifier::out)
	is det.
make_type_symbol_specifier(TypeSpec, type(TypeSpec)).

:- pred make_adt_symbol_specifier(adt_specifier::in, sym_specifier::out) is det.
make_adt_symbol_specifier(ADT_Spec, adt(ADT_Spec)).

:- pred make_op_symbol_specifier(op_specifier::in, sym_specifier::out) is det.
make_op_symbol_specifier(OpSpec, op(OpSpec)).

:- pred make_module_symbol_specifier(module_specifier::in, sym_specifier::out)
	is det.
make_module_symbol_specifier(ModuleSpec, module(ModuleSpec)).

:- pred cons_specifier_to_sym_specifier(cons_specifier, sym_specifier).
:- mode cons_specifier_to_sym_specifier(in, out) is det.

cons_specifier_to_sym_specifier(sym(SymSpec), sym(SymSpec)).
cons_specifier_to_sym_specifier(typed(SymSpec), typed_sym(SymSpec)).

%-----------------------------------------------------------------------------%

%	A ModuleSpecifier is just an sym_name.

:- pred parse_module_specifier(term, maybe1(module_specifier)).
:- mode parse_module_specifier(in, out) is det.
parse_module_specifier(Term, Result) :-
	parse_symbol_name(Term, Result).

%	A ModuleName is an implicitly-quantified sym_name.
%
%	We check for module names starting with capital letters
%	as a special case, so that we can report a better error
%	message for that case.

:- pred parse_module_name(module_name, term, maybe1(module_name)).
:- mode parse_module_name(in, in, out) is det.
parse_module_name(DefaultModuleName, Term, Result) :-
	(
		Term = term__variable(_)
	->
		dummy_term(ErrorContext),
		Result = error("module names starting with capital letters must be quoted using single quotes (e.g. "":- module 'Foo'."")", ErrorContext)
	;
		parse_implicitly_qualified_symbol_name(DefaultModuleName,
				Term, Result)
	).

%-----------------------------------------------------------------------------%

%	A ConstructorSpecifier is one of
%		SymbolNameSpecifier
%		TypedConstructorSpecifier
%
%	A TypedConstructorSpecifier is one of
%		SymbolNameSpecifier::Type
%			Matches only constructors with the specified result
%			type.
%		SymbolName(ArgType1, ..., ArgTypeN)
%			Matches only constructors with the specified argument
%			types.
%		SymbolName(ArgType1, ..., ArgTypeN)::Type
%			Matches only constructors with the specified argument
%			and result types.

:- pred parse_constructor_specifier(term, maybe1(cons_specifier)).
:- mode parse_constructor_specifier(in, out) is det.
parse_constructor_specifier(Term, Result) :-
    (
	Term = term__functor(term__atom("::"), [NameArgsTerm, TypeTerm],
		_Context)
    ->
	parse_arg_types_specifier(NameArgsTerm, NameArgsResult),
	parse_type(TypeTerm, TypeResult),
	process_typed_constructor_specifier(NameArgsResult, TypeResult, Result)
    ;
	parse_arg_types_specifier(Term, TermResult),
	process_maybe1(make_untyped_cons_spec, TermResult, Result)
    ).

%-----------------------------------------------------------------------------%

%	A PredicateSpecifier is one of
%		SymbolName(ArgType1, ..., ArgTypeN)
%			Matches only predicates with the specified argument
%			types.
%		SymbolNameSpecifier

:- pred parse_predicate_specifier(term, maybe1(pred_specifier)).
:- mode parse_predicate_specifier(in, out) is det.
parse_predicate_specifier(Term, Result) :-
    (
	Term = term__functor(term__atom("/"), [_,_], _Context)
    ->
	parse_symbol_name_specifier(Term, NameResult),
        process_maybe1(make_arity_predicate_specifier, NameResult, Result)
    ;
	parse_qualified_term(Term, Term, "predicate specifier", TermResult),
	process_typed_predicate_specifier(TermResult, Result)
    ).

:- pred process_typed_predicate_specifier(maybe_functor, maybe1(pred_specifier)).
:- mode process_typed_predicate_specifier(in, out) is det.
process_typed_predicate_specifier(ok(Name, Args0), ok(Result)) :-
    ( Args0 = [] ->
	Result = sym(name(Name))
    ;
    	list__map(term__coerce, Args0, Args),
	Result = name_args(Name, Args)
    ).
process_typed_predicate_specifier(error(Msg, Term), error(Msg, Term)).

:- pred make_arity_predicate_specifier(sym_name_specifier, pred_specifier).
:- mode make_arity_predicate_specifier(in, out) is det.
make_arity_predicate_specifier(Result, sym(Result)).

%-----------------------------------------------------------------------------%

% 	Parsing the name & argument types of a constructor specifier is
% 	exactly the same as parsing a predicate specifier...

:- pred parse_arg_types_specifier(term, maybe1(pred_specifier)).
:- mode parse_arg_types_specifier(in, out) is det.
parse_arg_types_specifier(Term, Result) :-
    (
	Term = term__functor(term__atom("/"), [_,_], _Context)
    ->
	parse_symbol_name_specifier(Term, NameResult),
        process_maybe1(make_arity_predicate_specifier, NameResult, Result)
    ;
	parse_qualified_term(Term, Term, "constructor specifier", TermResult),
	process_typed_predicate_specifier(TermResult, Result)
    ).

% 	... but we have to convert the result back into the appropriate
% 	format.

:- pred process_typed_constructor_specifier(maybe1(pred_specifier),
		maybe1(type), maybe1(cons_specifier)).
:- mode process_typed_constructor_specifier(in, in, out) is det.
process_typed_constructor_specifier(error(Msg, Term), _, error(Msg, Term)).
process_typed_constructor_specifier(ok(_), error(Msg, Term), error(Msg, Term)).
process_typed_constructor_specifier(ok(NameArgs), ok(ResType), ok(Result)) :-
	process_typed_cons_spec_2(NameArgs, ResType, Result).

:- pred process_typed_cons_spec_2(pred_specifier, type, cons_specifier).
:- mode process_typed_cons_spec_2(in, in, out) is det.
process_typed_cons_spec_2(sym(Name), Res, typed(name_res(Name, Res))).
process_typed_cons_spec_2(name_args(Name, Args), Res,
			  typed(name_args_res(Name, Args, Res))).

:- pred make_untyped_cons_spec(pred_specifier::in, cons_specifier::out) is det.
make_untyped_cons_spec(sym(Name), sym(Name)).
make_untyped_cons_spec(name_args(Name, Args), typed(name_args(Name, Args))).

%-----------------------------------------------------------------------------%

%	A SymbolNameSpecifier is one of
%		SymbolName
%		SymbolName/Arity
%			Matches only symbols of the specified arity.
%	

:- pred parse_symbol_name_specifier(term, maybe1(sym_name_specifier)).
:- mode parse_symbol_name_specifier(in, out) is det.
parse_symbol_name_specifier(Term, Result) :-
    ( %%% some [NameTerm, ArityTerm, Context]
       	Term = term__functor(term__atom("/"), [NameTerm, ArityTerm], _Context)
    ->
        ( %%% some [Arity, Context2]
            ArityTerm = term__functor(term__integer(Arity), [], _Context2)
	->
            ( Arity >= 0 ->
		parse_symbol_name(NameTerm, NameResult),
		process_maybe1(make_name_arity_specifier(Arity), NameResult,
			Result)
	    ;
		Result = error("arity in symbol name specifier must be a non-negative integer", Term)
	    )
        ;
	    Result = error("arity in symbol name specifier must be an integer", Term)
        )
    ;
	parse_symbol_name(Term, SymbolNameResult),
	process_maybe1(make_name_specifier, SymbolNameResult, Result)
    ).

:- pred make_name_arity_specifier(arity, sym_name, sym_name_specifier).
:- mode make_name_arity_specifier(in, in, out) is det.
make_name_arity_specifier(Arity, Name, name_arity(Name, Arity)).

:- pred make_name_specifier(sym_name::in, sym_name_specifier::out) is det.
make_name_specifier(Name, name(Name)).

%-----------------------------------------------------------------------------%

%	A SymbolName is one of
%		Name
%			Matches symbols with the specified name in the
%			current namespace.
%		Module:Name
%			Matches symbols with the specified name exported
%			by the specified module (where Module is itself
%			a SymbolName).
%
%	We also allow the syntax `Module__Name'
%	as an alternative for `Module:Name'.

:- pred parse_symbol_name(term(T), maybe1(sym_name)).
:- mode parse_symbol_name(in, out) is det.
parse_symbol_name(Term, Result) :-
    ( 
       	Term = term__functor(term__atom(":"), [ModuleTerm, NameTerm], _Context)
    ->
        ( 
            NameTerm = term__functor(term__atom(Name), [], _Context1)
        ->
	    parse_symbol_name(ModuleTerm, ModuleResult),
            (
	    	ModuleResult = ok(Module),
		Result = ok(qualified(Module, Name))
	    ;
	    	ModuleResult = error(_, _),
		term__coerce(Term, ErrorTerm),
		Result = error("module name identifier expected before ':' in qualified symbol name", ErrorTerm)
            )
        ;
	    term__coerce(Term, ErrorTerm),
            Result = error("identifier expected after ':' in qualified symbol name", ErrorTerm)
	)
    ;
        ( 
            Term = term__functor(term__atom(Name), [], _Context3)
        ->
    	    string_to_sym_name(Name, "__", SymName),
	    Result = ok(SymName)
        ;
	    term__coerce(Term, ErrorTerm),
            Result = error("symbol name expected", ErrorTerm)
        )
    ).

:- pred parse_implicitly_qualified_symbol_name(module_name, term,
			maybe1(sym_name)).
:- mode parse_implicitly_qualified_symbol_name(in, in, out) is det.

parse_implicitly_qualified_symbol_name(DefaultModName, Term, Result) :-
	parse_symbol_name(Term, Result0),
	( Result0 = ok(SymName) ->
		(
			root_module_name(DefaultModName)
		->
			Result = Result0
		;
			SymName = qualified(ModName, _),
			\+ match_sym_name(ModName, DefaultModName)
		->
			Result = error("module qualifier in definition does not match preceding `:- module' declaration", Term)
		;
			unqualify_name(SymName, UnqualName),
			Result = ok(qualified(DefaultModName, UnqualName))
		)
	;
		Result = Result0
	).

%-----------------------------------------------------------------------------%

%	A QualifiedTerm is one of
%		Name(Args)
%		Module:Name(Args)
%	(or if Args is empty, one of
%		Name
%		Module:Name)
%	where Module is a SymName.
%	For backwards compatibility, we allow `__'
%	as an alternative to `:'.

sym_name_and_args(Term, SymName, Args) :-
	parse_qualified_term(Term, Term, "", ok(SymName, Args)).

parse_implicitly_qualified_term(DefaultModName, Term, ContainingTerm, Msg,
		Result) :-
	parse_qualified_term(Term, ContainingTerm, Msg, Result0),
	( Result0 = ok(SymName, Args) ->
		(
			root_module_name(DefaultModName)
		->
			Result = Result0
		;
			SymName = qualified(ModName, _),
			\+ match_sym_name(ModName, DefaultModName)
		->
			term__coerce(Term, ErrorTerm),
			Result = error("module qualifier in definition does not match preceding `:- module' declaration", ErrorTerm)
		;
			unqualify_name(SymName, UnqualName),
			Result = ok(qualified(DefaultModName, UnqualName), Args)
		)
	;
		Result = Result0
	).

parse_qualified_term(Term, ContainingTerm, Msg, Result) :-
    (
       	Term = term__functor(term__atom(":"), [ModuleTerm, NameArgsTerm],
		_Context)
    ->
        ( 
            NameArgsTerm = term__functor(term__atom(Name), Args, _Context2)
        ->
	    parse_symbol_name(ModuleTerm, ModuleResult),
            ( 
	    	ModuleResult = ok(Module),
	        Result = ok(qualified(Module, Name), Args)
	    ;
	        ModuleResult = error(_, _),
		term__coerce(Term, ErrorTerm),
		Result = error("module name identifier expected before ':' in qualified symbol name", ErrorTerm)
            )
        ;
	    term__coerce(Term, ErrorTerm),
            Result = error("identifier expected after ':' in qualified symbol name", ErrorTerm)
	)
    ;
        ( 
            Term = term__functor(term__atom(Name), Args, _Context4)
        ->
	    string_to_sym_name(Name, "__", SymName),
	    Result = ok(SymName, Args)
        ;
	    string__append("atom expected in ", Msg, ErrorMsg),
	    %
	    % since variables don't have any term__context,
	    % if Term is a variable, we use ContainingTerm instead
	    % (hopefully that _will_ have a term__context).
	    %
	    ( Term = term__variable(_) ->
	    	ErrorTerm0 = ContainingTerm
	    ;
	    	ErrorTerm0 = Term
	    ),
	    term__coerce(ErrorTerm0, ErrorTerm),
	    Result = error(ErrorMsg, ErrorTerm)
        )
    ).

%-----------------------------------------------------------------------------%

% predicates used to convert a sym_list to a program item

:- pred make_use(sym_list::in, module_defn::out) is det.
make_use(Syms, use(Syms)).

:- pred make_import(sym_list::in, module_defn::out) is det.
make_import(Syms, import(Syms)).

:- pred make_export(sym_list::in, module_defn::out) is det.
make_export(Syms, export(Syms)).

%-----------------------------------------------------------------------------%

%	A FuncSpecifier is just a constructur name specifier.

:- pred parse_function_specifier(term, maybe1(func_specifier)).
:- mode parse_function_specifier(in, out) is det.
parse_function_specifier(Term, Result) :-
	parse_constructor_specifier(Term, Result).

%	A TypeSpecifier is just a symbol name specifier.

:- pred parse_type_specifier(term, maybe1(sym_name_specifier)).
:- mode parse_type_specifier(in, out) is det.
parse_type_specifier(Term, Result) :-
	parse_symbol_name_specifier(Term, Result).

%	An ADT_Specifier is just a symbol name specifier.

:- pred parse_adt_specifier(term, maybe1(sym_name_specifier)).
:- mode parse_adt_specifier(in, out) is det.
parse_adt_specifier(Term, Result) :-
	parse_symbol_name_specifier(Term, Result).

%-----------------------------------------------------------------------------%

%	For the moment, an OpSpecifier is just a symbol name specifier.
% 	XXX We should allow specifying the fixity of an operator

:- pred parse_op_specifier(term, maybe1(op_specifier)).
:- mode parse_op_specifier(in, out) is det.
parse_op_specifier(Term, Result) :-
	parse_symbol_name_specifier(Term, R),
	process_maybe1(make_op_specifier, R, Result).

:- pred make_op_specifier(sym_name_specifier::in, op_specifier::out) is det.
make_op_specifier(X, sym(X)).

%-----------------------------------------------------------------------------%

	% types are represented just as ordinary terms

:- pred parse_type(term, maybe1(type)).
:- mode parse_type(in, out) is det.
parse_type(T0, ok(T)) :-
	term__coerce(T0, T).

:- pred convert_constructor_arg_list(module_name,
		list(term), list(constructor_arg)).
:- mode convert_constructor_arg_list(in, in, out) is semidet.

convert_constructor_arg_list(_, [], []).
convert_constructor_arg_list(ModuleName, [Term | Terms], [Arg | Args]) :-
	(
		Term = term__functor(term__atom("::"), [NameTerm, TypeTerm], _)
	->
		parse_implicitly_qualified_term(ModuleName, NameTerm, Term,
			"field name", NameResult),
		NameResult = ok(SymName, []),
		convert_type(TypeTerm, Type),
		Arg = yes(SymName) - Type
	;
		convert_type(Term, Type),
		Arg = no - Type
	),
	convert_constructor_arg_list(ModuleName, Terms, Args).

:- pred convert_type(term, type).
:- mode convert_type(in, out) is det.
convert_type(T0, T) :-
	term__coerce(T0, T).

%-----------------------------------------------------------------------------%

% We use the empty module name ('') as the "root" module name; when adding
% default module qualifiers in parse_implicitly_qualified_{term,symbol},
% if the default module is the root module then we don't add any qualifier.

:- pred root_module_name(module_name::out) is det.
root_module_name(unqualified("")).

%-----------------------------------------------------------------------------%
