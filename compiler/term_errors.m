%-----------------------------------------------------------------------------%
% Copyright (C) 1997-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% term_errors.m
% Main author: crs.
% 
% This module prints out the various error messages that are produced by
% the various modules of termination analysis.
%
%-----------------------------------------------------------------------------%

:- module term_errors.

:- interface.

:- import_module hlds_module, hlds_pred, prog_data.

:- import_module io, bag, std_util, list, assoc_list.

:- type termination_error
	--->	pragma_c_code
			% The analysis result depends on the change constant
			% of a piece of pragma C code, (which cannot be
			% obtained without analyzing the C code, which is
			% something we cannot do).
			% Valid in both passes.

	;	imported_pred
			% The SCC contains some imported procedures,
			% whose code is not accessible.

	;	can_loop_proc_called(pred_proc_id, pred_proc_id)
			% can_loop_proc_called(Caller, Callee, Context)  
			% The call from Caller to Callee at the associated
			% context is to a procedure (Callee) whose termination
			% info is set to can_loop.
			% Although this error does not prevent us from
			% producing argument size information, it would
			% prevent us from proving termination.
			% We look for this error in pass 1; if we find it,
			% we do not perform pass 2.

	;	horder_args(pred_proc_id, pred_proc_id)
			% horder_args(Caller, Callee, Context)
			% The call from Caller to Callee at the associated
			% context has some arguments of a higher order type.
			% Valid in both passes.

	;	horder_call
			% horder_call
			% There is a higher order call at the associated
			% context.
			% Valid in both passes.

	;	inf_termination_const(pred_proc_id, pred_proc_id)
			% inf_termination_const(Caller, Callee, Context)
			% The call from Caller to Callee at the associated
			% context is to a procedure (Callee) whose arg size
			% info is set to infinite.
			% Valid in both passes.

	;	not_subset(pred_proc_id, bag(prog_var), bag(prog_var))
			% not_subset(Proc, SupplierVariables, InHeadVariables)
			% This error occurs when the bag of active variables
			% is not a subset of the input head variables.
			% Valid error only in pass 1.

	;	inf_call(pred_proc_id, pred_proc_id)
			% inf_call(Caller, Callee)
			% The call from Caller to Callee at the associated
			% context has infinite weight.
			% Valid error only in pass 2.

	;	cycle(pred_proc_id, assoc_list(pred_proc_id, prog_context))
			% cycle(StartPPId, CallSites)
			% In the cycle of calls starting at StartPPId and
			% going through the named call sites may be an
			% infinite loop.
			% Valid error only in pass 2.

	;	no_eqns
			% There are no equations in this SCC.
			% This has 2 possible causes. (1) If the predicate has
			% no output arguments, no equations will be created
			% for them. The change constant of the predicate is
			% undefined, but it will also never be used.
			% (2) If the procedure is a builtin predicate, with
			% an empty body, traversal cannot create any equations.
			% Valid error only in pass 1.

	;	too_many_paths
			% There were too many distinct paths to be analyzed.
			% Valid in both passes (which analyze different sets
			% of paths).

	;	solver_failed
			% The solver could not find finite termination
			% constants for the procedures in the SCC.
			% Valid only in pass 1.

	;	is_builtin(pred_id)
			% The termination constant of the given builtin is
			% set to infinity; this happens when the type of at
			% least one output argument permits a norm greater
			% than zero.

	;	does_not_term_pragma(pred_id).
			% The given procedure has a does_not_terminate pragma.

:- type term_errors__error == pair(prog_context, termination_error).

:- pred term_errors__report_term_errors(list(pred_proc_id)::in,
	list(term_errors__error)::in, module_info::in,
	io__state::di, io__state::uo) is det.

% An error is considered an indirect error if it is due either to a
% language feature we cannot analyze or due to an error in another part
% of the code. By default, we do not issue warnings about indirect errors,
% since in the first case, the programmer cannot do anything about it,
% and in the second case, the piece of code that the programmer *can* do
% something about is not this piece.

:- pred indirect_error(term_errors__termination_error).
:- mode indirect_error(in) is semidet.

:- implementation.

:- import_module hlds_out, prog_out, passes_aux, error_util.
:- import_module term, varset.
:- import_module mercury_to_mercury, term_util, options, globals.

:- import_module bool, int, string, map, bag, require.

indirect_error(horder_call).
indirect_error(pragma_c_code).
indirect_error(imported_pred).
indirect_error(can_loop_proc_called(_, _)).
indirect_error(horder_args(_, _)).
indirect_error(does_not_term_pragma(_)).

term_errors__report_term_errors(SCC, Errors, Module) -->
	{ get_context_from_scc(SCC, Module, Context) },
	( { SCC = [PPId] } ->
		{ Pieces0 = [words("Termination of")] },
		{ term_errors__describe_one_proc_name(PPId, Module, PredName) },
		{ list__append(Pieces0, [fixed(PredName)], Pieces1) },
		{ Single = yes(PPId) }
	;
		{ Pieces0 = [words("Termination of the mutually recursive procedures")] },
		{ term_errors__describe_several_proc_names(SCC, Module, Context,
			ProcNames) },
		{ list__map(lambda([PN::in, FPN::out] is det,
			(FPN = fixed(PN))),
			ProcNames, ProcNamePieces) },
		{ list__append(Pieces0, ProcNamePieces, Pieces1) },
		{ Single = no }
	),
	(
		{ Errors = [] },
		% XXX this should never happen
		% XXX but for some reason, it often does
		% { error("empty list of errors") }
		{ Pieces2 = [words("not proven, for unknown reason(s).")] },
		{ list__append(Pieces1, Pieces2, Pieces) },
		write_error_pieces(Context, 0, Pieces)
	;
		{ Errors = [Error] },
		{ Pieces2 = [words("not proven for the following reason:")] },
		{ list__append(Pieces1, Pieces2, Pieces) },
		write_error_pieces(Context, 0, Pieces),
		term_errors__output_error(Error, Single, no, 0, Module)
	;
		{ Errors = [_, _ | _] },
		{ Pieces2 = [words("not proven for the following reasons:")] },
		{ list__append(Pieces1, Pieces2, Pieces) },
		write_error_pieces(Context, 0, Pieces),
		term_errors__output_errors(Errors, Single, 1, 0, Module)
	).

:- pred term_errors__report_arg_size_errors(list(pred_proc_id)::in,
	list(term_errors__error)::in, module_info::in,
	io__state::di, io__state::uo) is det.

term_errors__report_arg_size_errors(SCC, Errors, Module) -->
	{ get_context_from_scc(SCC, Module, Context) },
	( { SCC = [PPId] } ->
		{ Pieces0 = [words("Termination constant of")] },
		{ term_errors__describe_one_proc_name(PPId, Module, ProcName) },
		{ list__append(Pieces0, [fixed(ProcName)], Pieces1) },
		{ Single = yes(PPId) }
	;
		{ Pieces0 = [words("Termination constants"),
			words("of the mutually recursive procedures")] },
		{ term_errors__describe_several_proc_names(SCC, Module,
			Context, ProcNames) },
		{ list__map(lambda([PN::in, FPN::out] is det,
			(FPN = fixed(PN))),
			ProcNames, ProcNamePieces) },
		{ list__append(Pieces0, ProcNamePieces, Pieces1) },
		{ Single = no }
	),
	{ Piece2 = words("set to infinity for the following") },
	(
		{ Errors = [] },
		{ error("empty list of errors") }
	;
		{ Errors = [Error] },
		{ Piece3 = words("reason:") },
		{ list__append(Pieces1, [Piece2, Piece3], Pieces) },
		write_error_pieces(Context, 0, Pieces),
		term_errors__output_error(Error, Single, no, 0, Module)
	;
		{ Errors = [_, _ | _] },
		{ Piece3 = words("reasons:") },
		{ list__append(Pieces1, [Piece2, Piece3], Pieces) },
		write_error_pieces(Context, 0, Pieces),
		term_errors__output_errors(Errors, Single, 1, 0, Module)
	).

:- pred term_errors__output_errors(list(term_errors__error)::in,
	maybe(pred_proc_id)::in, int::in, int::in, module_info::in,
	io__state::di, io__state::uo) is det.

term_errors__output_errors([], _, _, _, _) --> [].
term_errors__output_errors([Error | Errors], Single, ErrNum0, Indent, Module)
		-->
	term_errors__output_error(Error, Single, yes(ErrNum0), Indent, Module),
	{ ErrNum1 is ErrNum0 + 1 },
	term_errors__output_errors(Errors, Single, ErrNum1, Indent, Module).

:- pred term_errors__output_error(term_errors__error::in,
	maybe(pred_proc_id)::in, maybe(int)::in, int::in, module_info::in,
	io__state::di, io__state::uo) is det.

term_errors__output_error(Context - Error, Single, ErrorNum, Indent, Module) -->
	{ term_errors__description(Error, Single, Module, Pieces0, Reason) },
	{ ErrorNum = yes(N) ->
		string__int_to_string(N, Nstr),
		string__append_list(["Reason ", Nstr, ":"], Preamble),
		Pieces = [fixed(Preamble) | Pieces0]
	;
		Pieces = Pieces0
	},
	write_error_pieces(Context, Indent, Pieces),
	( { Reason = yes(InfArgSizePPId) } ->
		{ lookup_proc_arg_size_info(Module, InfArgSizePPId, ArgSize) },
		( { ArgSize = yes(infinite(ArgSizeErrors)) } ->
			% XXX the next line is cheating
			{ ArgSizePPIdSCC = [InfArgSizePPId] },
			term_errors__report_arg_size_errors(ArgSizePPIdSCC,
				ArgSizeErrors, Module)
		;
			{ error("inf arg size procedure does not have inf arg size") }
		)
	;
		[]
	).

:- pred term_errors__description(termination_error::in,
	maybe(pred_proc_id)::in, module_info::in, list(format_component)::out,
	maybe(pred_proc_id)::out) is det.

term_errors__description(horder_call, _, _, Pieces, no) :-
	Pieces = [words("It contains a higher order call.")].

term_errors__description(pragma_c_code, _, _, Pieces, no) :-
	Pieces = [words("It depends on the properties of"),
		words("foreign language code included via a"),
		fixed("`pragma c_code'"),
		words("declaration.")].

term_errors__description(inf_call(CallerPPId, CalleePPId),
		Single, Module, Pieces, no) :-
	(
		Single = yes(PPId),
		require(unify(PPId, CallerPPId), "caller outside this SCC"),
		Piece1 = words("It")
	;
		Single = no,
		term_errors__describe_one_proc_name(CallerPPId, Module,
			ProcName),
		Piece1 = fixed(ProcName)
	),
	Piece2 = words("calls"),
	term_errors__describe_one_proc_name(CalleePPId, Module, CalleePiece),
	Pieces3 = [words("with an unbounded increase"),
		words("in the size of the input arguments.")],
	Pieces = [Piece1, Piece2, fixed(CalleePiece) | Pieces3].

term_errors__description(can_loop_proc_called(CallerPPId, CalleePPId),
		Single, Module, Pieces, no) :-
	(
		Single = yes(PPId),
		require(unify(PPId, CallerPPId), "caller outside this SCC"),
		Piece1 = words("It")
	;
		Single = no,
		term_errors__describe_one_proc_name(CallerPPId, Module,
			ProcName),
		Piece1 = fixed(ProcName)
	),
	Piece2 = words("calls"),
	term_errors__describe_one_proc_name(CalleePPId, Module, CalleePiece),
	Pieces3 = [words("which could not be proven to terminate.")],
	Pieces = [Piece1, Piece2, fixed(CalleePiece) | Pieces3].

term_errors__description(imported_pred, _, _, Pieces, no) :-
	Pieces = [words("It contains one or more"),
		words("predicates and/or functions"),
		words("imported from another module.")].

term_errors__description(horder_args(CallerPPId, CalleePPId), Single, Module,
		Pieces, no) :-
	(
		Single = yes(PPId),
		require(unify(PPId, CallerPPId), "caller outside this SCC"),
		Piece1 = words("It")
	;
		Single = no,
		term_errors__describe_one_proc_name(CallerPPId, Module,
			ProcName),
		Piece1 = fixed(ProcName)
	),
	Piece2 = words("calls"),
	term_errors__describe_one_proc_name(CalleePPId, Module, CalleePiece),
	Pieces3 = [words("with one or more higher order arguments.")],
	Pieces = [Piece1, Piece2, fixed(CalleePiece) | Pieces3].

term_errors__description(inf_termination_const(CallerPPId, CalleePPId),
		Single, Module, Pieces, yes(CalleePPId)) :-
	(
		Single = yes(PPId),
		require(unify(PPId, CallerPPId), "caller outside this SCC"),
		Piece1 = words("It")
	;
		Single = no,
		term_errors__describe_one_proc_name(CallerPPId, Module,
			ProcName),
		Piece1 = fixed(ProcName)
	),
	Piece2 = words("calls"),
	term_errors__describe_one_proc_name(CalleePPId, Module, CalleePiece),
	Pieces3 = [words("which has a termination constant of infinity.")],
	Pieces = [Piece1, Piece2, fixed(CalleePiece) | Pieces3].

term_errors__description(not_subset(ProcPPId, OutputSuppliers, HeadVars),
		Single, Module, Pieces, no) :-
	(
		Single = yes(PPId),
		( PPId = ProcPPId ->
			Pieces1 = [words("The set of"),
				words("its output supplier variables")]
		;
			% XXX this should never happen (but it does)
			% error("not_subset outside this SCC"),
			term_errors__describe_one_proc_name(ProcPPId, Module,
				PPIdPiece),
			Pieces1 = [words("The set of"),
				words("output supplier variables of"),
				fixed(PPIdPiece)]
		)
	;
		Single = no,
		term_errors__describe_one_proc_name(ProcPPId, Module,
			PPIdPiece),
		Pieces1 = [words("The set of output supplier variables of"),
			fixed(PPIdPiece)]
	),
	ProcPPId = proc(PredId, ProcId),
	module_info_pred_proc_info(Module, PredId, ProcId, _, ProcInfo),
	proc_info_varset(ProcInfo, Varset),
	term_errors_var_bag_description(OutputSuppliers, Varset,
		OutputSuppliersNames),
	list__map(lambda([OS::in, FOS::out] is det, (FOS = fixed(OS))),
		OutputSuppliersNames, OutputSuppliersPieces),
	Pieces3 = [words("was not a subset of the head variables")],
	term_errors_var_bag_description(HeadVars, Varset, HeadVarsNames),
	list__map(lambda([HV::in, FHV::out] is det, (FHV = fixed(HV))),
		HeadVarsNames, HeadVarsPieces),
	list__condense([Pieces1, OutputSuppliersPieces, Pieces3,
		HeadVarsPieces], Pieces).

term_errors__description(cycle(_StartPPId, CallSites), _, Module, Pieces, no) :-
	( CallSites = [DirectCall] ->
		term_errors__describe_one_call_site(DirectCall, Module, Site),
		Pieces = [words("At the recursive call to"),
			fixed(Site),
			words("the arguments are"),
			words("not guaranteed to decrease in size.")]
	;
		Pieces1 = [words("In the recursive cycle"),
			words("through the calls to")],
		term_errors__describe_several_call_sites(CallSites, Module,
			Sites),
		list__map(lambda([S::in, FS::out] is det, (FS = fixed(S))),
			Sites, SitePieces),
		Pieces2 = [words("the arguments are"),
			words("not guaranteed to decrease in size.")],
		list__condense([Pieces1, SitePieces, Pieces2], Pieces)
	).

term_errors__description(too_many_paths, _, _, Pieces, no) :-
	Pieces = [words("There were too many execution paths"),
		words("for the analysis to process.")].

term_errors__description(no_eqns, _, _, Pieces, no) :-
	Pieces = [words("The analysis was unable to form any constraints"),
		words("between the arguments of this group of procedures.")].

term_errors__description(solver_failed, _, _, Pieces, no)  :-
	Pieces = [words("The solver found the constraints produced"),
		words("by the analysis to be infeasible.")].

term_errors__description(is_builtin(_PredId), _Single, _, Pieces, no) :-
	% XXX require(unify(Single, yes(_)), "builtin not alone in SCC"),
	Pieces = [words("It is a builtin predicate.")].

term_errors__description(does_not_term_pragma(PredId), Single, Module,
		Pieces, no) :-
	Pieces1 = [words("There was a `does_not_terminate' pragma defined on")],
	(
		Single = yes(PPId),
		PPId = proc(SCCPredId, _),
		require(unify(PredId, SCCPredId), "does not terminate pragma outside this SCC"),
		Piece2 = words("It")
	;
		Single = no,
		term_errors__describe_one_pred_name(PredId, Module,
			Piece2Nodot),
		string__append(Piece2Nodot, ".", Piece2Str),
		Piece2 = fixed(Piece2Str)
	),
	list__append(Pieces1, [Piece2], Pieces).

%----------------------------------------------------------------------------%

:- pred term_errors_var_bag_description(bag(prog_var)::in, prog_varset::in,
	list(string)::out) is det.

term_errors_var_bag_description(HeadVars, Varset, Pieces) :-
	bag__to_assoc_list(HeadVars, HeadVarCountList),
	term_errors_var_bag_description_2(HeadVarCountList, Varset, yes,
		Pieces).

:- pred term_errors_var_bag_description_2(assoc_list(prog_var, int)::in,
		prog_varset::in, bool::in, list(string)::out) is det.

term_errors_var_bag_description_2([], _, _, ["{}"]).
term_errors_var_bag_description_2([Var - Count | VarCounts], Varset, First,
		[Piece | Pieces]) :-
	varset__lookup_name(Varset, Var, VarName),
	( Count > 1 ->
		string__append(VarName, "*", VarCountPiece0),
		string__int_to_string(Count, CountStr),
		string__append(VarCountPiece0, CountStr, VarCountPiece)
	;
		VarCountPiece = VarName
	),
	( First = yes ->
		string__append("{", VarCountPiece, Piece0)
	;
		Piece0 = VarCountPiece
	),
	( VarCounts = [] ->
		string__append(Piece0, "}.", Piece),
		Pieces = []
	;
		Piece = Piece0,
		term_errors_var_bag_description_2(VarCounts, Varset, First,
			Pieces)
	).

%----------------------------------------------------------------------------%

:- pred term_errors__describe_one_pred_name(pred_id::in, module_info::in,
	string::out) is det.

	% The code of this predicate duplicates the functionality of
	% hlds_out__write_pred_id. Changes here should be made there as well.

term_errors__describe_one_pred_name(PredId, Module, Piece) :-
	module_info_pred_info(Module, PredId, PredInfo),
	pred_info_module(PredInfo, ModuleName),
	prog_out__sym_name_to_string(ModuleName, ModuleNameString),
	pred_info_name(PredInfo, PredName),
	pred_info_arity(PredInfo, Arity),
	pred_info_get_is_pred_or_func(PredInfo, PredOrFunc),
	(
		PredOrFunc = predicate,
		PredOrFuncPart = "predicate ",
		OrigArity = Arity
	;
		PredOrFunc = function,
		PredOrFuncPart = "function ",
		OrigArity is Arity - 1
	),
	string__int_to_string(OrigArity, ArityPart),
	string__append_list([
		PredOrFuncPart,
		ModuleNameString,
		":",
		PredName,
		"/",
		ArityPart
		], Piece).

:- pred term_errors__describe_one_proc_name(pred_proc_id::in, module_info::in,
	string::out) is det.

term_errors__describe_one_proc_name(proc(PredId, ProcId), Module, Piece) :-
	term_errors__describe_one_pred_name(PredId, Module, PredPiece),
	proc_id_to_int(ProcId, ProcIdInt),
	string__int_to_string(ProcIdInt, ProcIdPart),
	string__append_list([
		PredPiece,
		" mode ",
		ProcIdPart
		], Piece).

:- pred term_errors__describe_several_proc_names(list(pred_proc_id)::in,
	module_info::in, prog_context::in, list(string)::out) is det.

term_errors__describe_several_proc_names([], _, _, []).
term_errors__describe_several_proc_names([PPId | PPIds], Module,
		Context, Pieces) :-
	term_errors__describe_one_proc_name(PPId, Module, Piece0),
	( PPIds = [] ->
		Pieces = [Piece0]
	; PPIds = [LastPPId] ->
		term_errors__describe_one_proc_name(LastPPId, Module,
			LastPiece),
		Pieces = [Piece0, "and", LastPiece]
	;
		string__append(Piece0, ",", Piece),
		term_errors__describe_several_proc_names(PPIds, Module,
			Context, Pieces1),
		Pieces = [Piece | Pieces1]
	).

:- pred term_errors__describe_one_call_site(pair(pred_proc_id,
	prog_context)::in, module_info::in, string::out) is det.

term_errors__describe_one_call_site(PPId - Context, Module, Piece) :-
	term_errors__describe_one_proc_name(PPId, Module, ProcName),
	term__context_file(Context, FileName),
	term__context_line(Context, LineNumber),
	string__int_to_string(LineNumber, LineNumberPart),
	string__append_list([
		ProcName,
		" at ",
		FileName,
		":",
		LineNumberPart
		], Piece).

:- pred term_errors__describe_several_call_sites(assoc_list(pred_proc_id,
	prog_context)::in, module_info::in, list(string)::out) is det.

term_errors__describe_several_call_sites([], _, []).
term_errors__describe_several_call_sites([Site | Sites], Module, Pieces) :-
	term_errors__describe_one_call_site(Site, Module, Piece0),
	( Sites = [] ->
		Pieces = [Piece0]
	; Sites = [LastSite] ->
		term_errors__describe_one_call_site(LastSite, Module,
			LastPiece),
		Pieces = [Piece0, "and", LastPiece]
	;
		string__append(Piece0, ",", Piece),
		term_errors__describe_several_call_sites(Sites, Module,
			Pieces1),
		Pieces = [Piece | Pieces1]
	).

%----------------------------------------------------------------------------%
