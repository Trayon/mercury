%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2003-2004, 2006-2008 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: analysis.m.
% Main authors: stayl, wangp.
%
% An inter-module analysis framework, as described in
%
%   Nicholas Nethercote. The Analysis Framework of HAL,
%   Chapter 7: Inter-module Analysis, Master's Thesis,
%   University of Melbourne, September 2001, revised April 2002.
%   <http://www.cl.cam.ac.uk/~njn25/pubs/masters2001.ps.gz>.
%
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module analysis.
:- interface.

:- import_module bool.
:- import_module io.
:- import_module list.
:- import_module maybe.
:- import_module set.
:- import_module unit.

%-----------------------------------------------------------------------------%

    % The intention is that eventually any compiler can use this library
    % via .NET by defining an instance of this type class.
:- typeclass compiler(Compiler) where [
    func compiler_name(Compiler) = string,

    % Describe the analyses which can be performed by a compiler.
    %
    func analyses(Compiler, analysis_name) = analysis_type is semidet,

    % module_id_to_read_file_name(Compiler, ModuleId, Ext, FileName)
    %
    pred module_id_to_read_file_name(Compiler::in, module_id::in,
        string::in, maybe_error(string)::out, io::di, io::uo) is det,

    % module_id_to_write_file_name(Compiler, ModuleId, Ext, FileName)
    %
    pred module_id_to_write_file_name(Compiler::in, module_id::in,
        string::in, string::out, io::di, io::uo) is det
].

:- type module_id == string.

:- type analysis_name == string.

:- type analysis_type
    --->    some [Call, Answer]
            analysis_type(
                unit(Call),
                unit(Answer)
            ) => analysis(Call, Answer).

    % An analysis is defined by a type describing call patterns and
    % a type defining answer patterns.  If the analysis needs to store
    % more information about the function being analysed (e.g. arity)
    % it should be stored as part of the type for call patterns.
    %
:- typeclass analysis(Call, Answer) <=
        (call_pattern(Call), answer_pattern(Answer))
    where
[
    func analysis_name(Call::unused, Answer::unused) =
        (analysis_name::out) is det,

    % The version number should be changed when the Call or Answer
    % types are changed so that results which use the old types
    % can be discarded.
    %
    func analysis_version_number(Call::unused, Answer::unused) =
        (int::out) is det,

    func preferred_fixpoint_type(Call::unused, Answer::unused) =
        (fixpoint_type::out) is det,

    % `top' and `bottom' should not really depend on the call pattern.
    % However some analyses may choose to store extra information about
    % the function in their `Call' types that might be needed for the
    % answer pattern.
    %
    func bottom(Call) = Answer,
    func top(Call) = Answer
].

:- type fixpoint_type
    --->    least_fixpoint
            % Start at `bottom'.
            % Must run to completion.

    ;       greatest_fixpoint.
            % Start at `top'.
            % Can stop at any time.

:- typeclass call_pattern(Call)
    <= (partial_order(Call), to_string(Call)) where [].

:- typeclass answer_pattern(Answer)
    <= (partial_order(Answer), to_string(Answer)) where [].

    % Extra information may be stored in a module's `.analysis' file, apart
    % from the analysis results.  This information is indexed by a string key.
    % The extra information must be convertable to/from a string.
    %
:- type extra_info_key == string.

:- typeclass extra_info(ExtraInfo) <= to_string(ExtraInfo) where [].

:- type analysis_result(Call, Answer)
    --->    analysis_result(
                ar_call     :: Call,
                ar_answer   :: Answer,
                ar_status   :: analysis_status
            ).

:- typeclass partial_order(T) where [
    pred more_precise_than(T::in, T::in) is semidet,
    pred equivalent(T::in, T::in) is semidet
].

:- typeclass to_string(S) where [
    func to_string(S) = string,
    func from_string(string) = S is semidet
].

    % A call pattern that can be used by analyses that do not need
    % finer granularity.
    %
:- type any_call
    --->    any_call.

:- instance call_pattern(any_call).
:- instance partial_order(any_call).
:- instance to_string(any_call).

    % The status of a module or a specific analysis result.
    %
:- type analysis_status
    --->    invalid
    ;       suboptimal
    ;       optimal.

    % Least upper bound of two analysis_status values.
    %
:- func lub(analysis_status, analysis_status) = analysis_status.

    % This will need to encode language specific details like whether
    % it is a predicate or a function, and the arity and mode number.
:- type func_id == string.

    % Holds information used while analysing a module.
:- type analysis_info.

:- func init_analysis_info(Compiler) = analysis_info <= compiler(Compiler).

%-----------------------------------------------------------------------------%

    % Look up all results for a given function.
    %
    % N.B. Newly recorded results will NOT be found. This is intended
    % for looking up results from _other_ modules.
    %
:- pred lookup_results(analysis_info::in, module_id::in, func_id::in,
    list(analysis_result(Call, Answer))::out) is det
    <= analysis(Call, Answer).

    % Look up all results for a given function and call pattern CP such
    % that the results have call patterns CP' that are equivalent to CP
    % or less specific than CP.
    %
    % N.B. Newly recorded results will NOT be found. This is intended
    % for looking up results from _other_ modules.
    %
:- pred lookup_matching_results(analysis_info::in, module_id::in, func_id::in,
    Call::in, list(analysis_result(Call, Answer))::out) is det
    <= analysis(Call, Answer).

    % Look up the best result matching a given call.
    %
    % N.B. Newly recorded results will NOT be found. This is intended
    % for looking up results from _other_ modules.
    %
    % If the returned best result has a call pattern that is different
    % from the given call pattern, then it is the analysis writer's
    % responsibility to request a more precise analysis from the called module,
    % using `record_request'.
    %
:- pred lookup_best_result(analysis_info::in, module_id::in, func_id::in,
    Call::in, maybe(analysis_result(Call, Answer))::out) is det
    <= analysis(Call, Answer).

    % Record an analysis result for a (usually local) function.
    %
    % XXX At the moment the result is assumed to be for a function local to
    % the currently-compiled module and things will probably break if it isn't.
    %
:- pred record_result(module_id::in, func_id::in, Call::in, Answer::in,
    analysis_status::in, analysis_info::in, analysis_info::out) is det
    <= analysis(Call, Answer).

    % Record the dependency of a module on the analysis result of another
    % module.
    %
:- pred record_dependency(module_id::in, analysis_name::in, module_id::in,
    func_id::in, Call::in, analysis_info::in, analysis_info::out) is det
    <= call_pattern(Call).

    % Lookup all the requests for a given (usually local) function.
    %
:- pred lookup_requests(analysis_info::in, analysis_name::in, module_id::in,
    func_id::in, list(Call)::out) is det
    <= call_pattern(Call).

    % Record a request for a function in an imported module.
    %
:- pred record_request(analysis_name::in, module_id::in, func_id::in,
    Call::in, analysis_info::in, analysis_info::out) is det
    <= call_pattern(Call).

%-----------------------------------------------------------------------------%

    % Lookup extra information about a module, using the key given.
    %
:- pred lookup_module_extra_info(analysis_info::in, module_id::in,
    extra_info_key::in, maybe(ExtraInfo)::out) is det
    <= extra_info(ExtraInfo).

    % Record extra information about a module under the given key.
    %
:- pred record_module_extra_info(module_id::in, extra_info_key::in,
    ExtraInfo::in, analysis_info::in, analysis_info::out) is det
    <= extra_info(ExtraInfo).

%-----------------------------------------------------------------------------%

    % prepare_intermodule_analysis(ModuleIds, LocalModuleIds, !Info, !IO)
    %
    % This predicate should be called before any pass begins to use the
    % analysis framework.  It ensures that all the analysis files 
    % are loaded so that lookups can be satisfied.  ModuleIds is the set of
    % all modules that are directly or indirectly imported by the module being
    % analysed.  LocalModuleIds is the set of non-"library" modules.
    %
:- pred prepare_intermodule_analysis(set(module_id)::in, set(module_id)::in,
    analysis_info::in, analysis_info::out, io::di, io::uo) is det.

     % module_is_local(Info, ModuleId, IsLocal).
     %
     % IsLocal is `yes' if the module is not a "library" module, i.e. we are
     % able to reanalyse the module. The set of local modules is set in
     % `prepare_intermodule_analysis'.
    %
:- pred module_is_local(analysis_info::in, module_id::in, bool::out)
    is det.

    % Should be called after all analysis is completed to write the
    % requests and results for the current compilation to the
    % analysis files.
    %
:- pred write_analysis_files(Compiler::in, module_id::in, set(module_id)::in,
    analysis_info::in, analysis_info::out, io::di, io::uo) is det
    <= compiler(Compiler).

%-----------------------------------------------------------------------------%

    % read_module_overall_status(Compiler, ModuleId, MaybeModuleStatus, !IO)
    %
    % Attempt to read the overall status from a module `.analysis' file.
    %
:- pred read_module_overall_status(Compiler::in, module_id::in,
    maybe(analysis_status)::out, io::di, io::uo) is det
    <= compiler(Compiler).

:- pred enable_debug_messages(bool::in, io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- include_module analysis.file.

:- import_module analysis.file.
:- import_module libs.
:- import_module libs.compiler_util.

:- import_module map.
:- import_module require.
:- import_module string.
:- import_module univ.

%-----------------------------------------------------------------------------%

:- type analysis_info
    --->    some [Compiler]
            analysis_info(
                compiler :: Compiler,

                % The set of local modules, i.e. for which we can issue
                % requests.
                %
                local_module_ids :: set(module_id),

                % Holds outstanding requests for more specialised variants
                % of procedures. Requests are added to this map as analyses
                % proceed and written out to disk at the end of the
                % compilation of this module.
                %
                analysis_requests :: analysis_map(analysis_request),

                % The overall status of each module.
                %
                module_statuses :: map(module_id, analysis_status),

                % The "old" map stores analysis results read in from disk.
                % New results generated while analysing the current module
                % are added to the "new" map. After all the analyses
                % the two maps are compared to see which analysis results
                % have changed. Other modules may need to be marked or
                % invalidated as a result. Then "new" results are moved
                % into the "old" map, from where they can be written to disk.
                %
                old_analysis_results :: analysis_map(some_analysis_result),
                new_analysis_results :: analysis_map(some_analysis_result),

                % The extra info map stores any extra information needed
                % by one or more analysis results.
                %
                old_extra_infos     :: map(module_id, module_extra_info_map),
                new_extra_infos     :: map(module_id, module_extra_info_map),

                % The Inter-module Dependency Graph records dependencies
                % of an entire module's analysis results on another module's
                % answer patterns. e.g. assume module M1 contains function F1
                % that has an analysis result that used the answer F2:CP2->AP2
                % from module M2. If AP2 changes then all of M1 will either be
                % marked `suboptimal' or `invalid'. Finer-grained dependency
                % tracking would allow only F1 to be recompiled, instead of
                % all of M1, but we don't do that.
                %
                % IMDGs are loaded from disk into the old map. During analysis
                % any dependences of the current module on other modules
                % is added into the new map. At the end of analysis all the
                % arcs which terminate at the current module are cleared
                % from the old map and replaced by those in the new map.
                %
                % XXX: Check if we really need two maps.
                %
                old_imdg :: analysis_map(imdg_arc),
                new_imdg :: analysis_map(imdg_arc)
            )
            => compiler(Compiler).

    % An analysis result is a call pattern paired with an answer.
    % The result has a status associated with it.
    %
:- type some_analysis_result
    --->    some [Call, Answer]
            some_analysis_result(
                some_ar_call    :: Call,
                some_ar_answer  :: Answer,
                some_ar_status  :: analysis_status
            )
            => analysis(Call, Answer).

:- type analysis_request
    --->    some [Call]
            analysis_request(
                Call
            )
            => call_pattern(Call).

:- type imdg_arc
    --->    some [Call]
            imdg_arc(
                Call,       % Call pattern of the analysis result
                            % being depended on.
                module_id   % The module that _depends on_ this function's
                            % result.
            )
            => call_pattern(Call).

:- type analysis_map(T)         == map(module_id, module_analysis_map(T)).
:- type module_analysis_map(T)  == map(analysis_name, func_analysis_map(T)).
:- type func_analysis_map(T)    == map(func_id, list(T)).

:- type module_extra_info_map   == map(extra_info_key, string).

%-----------------------------------------------------------------------------%
%
% The "any" call pattern
%

:- instance call_pattern(any_call) where [].
:- instance partial_order(any_call) where [
    more_precise_than(_, _) :-
        semidet_fail,
    equivalent(_, _) :-
        semidet_succeed
].
:- instance to_string(any_call) where [
    to_string(any_call) = "",
    from_string("") = any_call
].

%-----------------------------------------------------------------------------%

init_analysis_info(Compiler) =
    'new analysis_info'(Compiler, set.init, map.init, map.init, map.init,
        map.init, map.init, map.init, map.init, map.init).

%-----------------------------------------------------------------------------%

lookup_results(Info, ModuleId, FuncId, ResultList) :-
    lookup_results(Info, ModuleId, FuncId, no, ResultList).

:- pred lookup_results(analysis_info::in, module_id::in, func_id::in,
    bool::in, list(analysis_result(Call, Answer))::out) is det
    <= analysis(Call, Answer).

lookup_results(Info, ModuleId, FuncId, AllowInvalidModules, ResultList) :-
    trace [io(!IO)] (
        debug_msg((pred(!.IO::di, !:IO::uo) is det :-
            io.write_string("% Looking up analysis results for ", !IO),
            io.write_string(ModuleId, !IO),
            io.write_string(".", !IO),
            io.write_string(FuncId, !IO),
            io.nl(!IO)
        ), !IO)
    ),
    (
        AllowInvalidModules = no,
        Info ^ module_statuses ^ det_elem(ModuleId) = invalid
    ->
        ResultList = []
    ;
        lookup_results_2(Info ^ old_analysis_results, ModuleId, FuncId,
            ResultList),
        trace [io(!IO)] (
            debug_msg((pred(!.IO::di, !:IO::uo) is det :-
                io.write_string("% Found these results: ", !IO),
                io.print(ResultList, !IO),
                io.nl(!IO)
            ), !IO)
        )
    ).

:- pred lookup_results_2(analysis_map(some_analysis_result)::in, module_id::in,
    func_id::in, list(analysis_result(Call, Answer))::out) is det
    <= analysis(Call, Answer).

lookup_results_2(Map, ModuleId, FuncId, ResultList) :-
    AnalysisName = analysis_name(_ : Call, _ : Answer),
    (
        ModuleResults = Map ^ elem(ModuleId),
        Results = ModuleResults ^ elem(AnalysisName) ^ elem(FuncId)
    ->
        % XXX we might have to discard results which are
        % `invalid' or `fixpoint_invalid' if they are written at all
        ResultList = list.map(
            (func(Result) = analysis_result(Call, Answer, Status) :-
                Result = some_analysis_result(Call0, Answer0, Status),
                det_univ_to_type(univ(Call0), Call),
                det_univ_to_type(univ(Answer0), Answer)
            ), Results)
    ;
        ResultList = []
    ).

lookup_matching_results(Info, ModuleId, FuncId, Call, ResultList) :-
    lookup_results(Info, ModuleId, FuncId, AllResultsList),
    ResultList = list.filter(
        (pred(Result::in) is semidet :-
            ResultCall = Result ^ ar_call,
            ( more_precise_than(Call, ResultCall)
            ; equivalent(Call, ResultCall)
            )
        ), AllResultsList).

lookup_best_result(Info, ModuleId, FuncId, Call, MaybeBestResult) :-
    trace [io(!IO)] (
        debug_msg((pred(!.IO::di, !:IO::uo) is det :-
            io.write_string("% Looking up best analysis result for ", !IO),
            io.write_string(ModuleId, !IO),
            io.write_string(".", !IO),
            io.write_string(FuncId, !IO),
            io.nl(!IO)
        ), !IO)
    ),
    lookup_matching_results(Info, ModuleId, FuncId, Call, MatchingResults),
    (
        MatchingResults = [],
        MaybeBestResult = no
    ;
        MatchingResults = [_ | _],
        MaybeBestResult = yes(BestResult),
        most_precise_answer(MatchingResults, BestResult)
    ).

:- pred most_precise_answer(
    list(analysis_result(Call, Answer))::in(non_empty_list),
    analysis_result(Call, Answer)::out) is det
    <= analysis(Call, Answer).

most_precise_answer([Result | Results], BestResult) :-
    list.foldl(more_precise_answer, Results, Result, BestResult).

:- pred more_precise_answer(analysis_result(Call, Answer)::in,
    analysis_result(Call, Answer)::in,
    analysis_result(Call, Answer)::out) is det
    <= analysis(Call, Answer).

more_precise_answer(Result, Best0, Best) :-
    ResultAnswer = Result ^ ar_answer,
    BestAnswer0 = Best0 ^ ar_answer,
    ( more_precise_than(ResultAnswer, BestAnswer0) ->
        Best = Result
    ; 
        Best = Best0
    ).

:- pred lookup_exactly_matching_result_even_from_invalid_modules(
    analysis_info::in, module_id::in, func_id::in, Call::in,
    maybe(analysis_result(Call, Answer))::out) is det
    <= analysis(Call, Answer).

lookup_exactly_matching_result_even_from_invalid_modules(Info, ModuleId,
        FuncId, Call, MaybeResult) :-
    lookup_results(Info, ModuleId, FuncId, yes, AllResultsList),
    ResultList = list.filter(
        (pred(R::in) is semidet :-
            equivalent(Call, R ^ ar_call)
        ), AllResultsList),
    (
        ResultList = [],
        MaybeResult = no
    ;
        ResultList = [Result],
        MaybeResult = yes(Result)
    ;
        ResultList = [_, _ | _],
        unexpected(this_file,
            "lookup_exactly_matching_result: " ++
            "zero or one exactly matching results expected")
    ).

%-----------------------------------------------------------------------------%

record_result(ModuleId, FuncId, CallPattern, AnswerPattern, Status, !Info) :-
    Map0 = !.Info ^ new_analysis_results,
    record_result_in_analysis_map(ModuleId, FuncId,
    CallPattern, AnswerPattern, Status, Map0, Map),
    !Info ^ new_analysis_results := Map.

:- pred record_result_in_analysis_map(module_id::in, func_id::in,
    Call::in, Answer::in, analysis_status::in,
    analysis_map(some_analysis_result)::in,
    analysis_map(some_analysis_result)::out) is det
    <= analysis(Call, Answer).

record_result_in_analysis_map(ModuleId, FuncId,
        CallPattern, AnswerPattern, Status, !Map) :-
    ( ModuleResults0 = map.search(!.Map, ModuleId) ->
        ModuleResults1 = ModuleResults0
    ;
        ModuleResults1 = map.init
    ),
    AnalysisName = analysis_name(CallPattern, AnswerPattern),
    ( AnalysisResults0 = map.search(ModuleResults1, AnalysisName) ->
        AnalysisResults1 = AnalysisResults0
    ;
        AnalysisResults1 = map.init
    ),
    ( FuncResults0 = map.search(AnalysisResults1, FuncId) ->
        FuncResults1 = FuncResults0
    ;
        FuncResults1 = []
    ),
    !:Map = map.set(!.Map, ModuleId,
        map.set(ModuleResults1, AnalysisName,
            map.set(AnalysisResults1, FuncId, FuncResults))),
    FuncResults = [Result | FuncResults1],
    Result = 'new some_analysis_result'(CallPattern, AnswerPattern, Status).

%-----------------------------------------------------------------------------%

lookup_requests(Info, AnalysisName, ModuleId, FuncId, CallPatterns) :-
    map.lookup(Info ^ analysis_requests, ModuleId, ModuleRequests),
    ( CallPatterns0 = ModuleRequests ^ elem(AnalysisName) ^ elem(FuncId) ->
        CallPatterns = list.filter_map(
            (func(analysis_request(Call0)) = Call is semidet :-
                univ(Call) = univ(Call0)
            ), CallPatterns0)
    ;
        CallPatterns = []
    ).

record_request(AnalysisName, ModuleId, FuncId, CallPattern, !Info) :-
    ( ModuleResults0 = map.search(!.Info ^ analysis_requests, ModuleId) ->
        ModuleResults1 = ModuleResults0
    ;
        ModuleResults1 = map.init
    ),
    ( AnalysisResults0 = map.search(ModuleResults1, AnalysisName) ->
        AnalysisResults1 = AnalysisResults0
    ;
        AnalysisResults1 = map.init
    ),
    ( FuncResults0 = map.search(AnalysisResults1, FuncId) ->
        FuncResults1 = FuncResults0
    ;
        FuncResults1 = []
    ),
    !Info ^ analysis_requests :=
        map.set(!.Info ^ analysis_requests, ModuleId,
            map.set(ModuleResults1, AnalysisName,
                map.set(AnalysisResults1, FuncId,
                    ['new analysis_request'(CallPattern) | FuncResults1]))).

%-----------------------------------------------------------------------------%

record_dependency(CallerModuleId, AnalysisName, CalleeModuleId, FuncId, Call,
        !Info) :-
    ( CallerModuleId = CalleeModuleId ->
        % XXX this assertion breaks compiling the standard library with
        % --analyse-trail-usage at the moment
        %
        % error("record_dependency: " ++ CalleeModuleId ++ " and " ++
        %    CallerModuleId ++ " must be different")
        true
    ;
        ( Analyses0 = map.search(!.Info ^ new_imdg, CalleeModuleId) ->
            Analyses1 = Analyses0
        ;
            Analyses1 = map.init
        ),
        ( Funcs0 = map.search(Analyses1, AnalysisName) ->
            Funcs1 = Funcs0
        ;
            Funcs1 = map.init
        ),
        ( FuncArcs0 = map.search(Funcs1, FuncId) ->
            FuncArcs1 = FuncArcs0
        ;
            FuncArcs1 = []
        ),
        Dep = 'new imdg_arc'(Call, CallerModuleId),
        % XXX this should really be a set to begin with
        ( list.member(Dep, FuncArcs1) ->
            true
        ;
            !Info ^ new_imdg :=
                map.set(!.Info ^ new_imdg, CalleeModuleId,
                    map.set(Analyses1, AnalysisName,
                        map.set(Funcs1, FuncId, FuncArcs))),
                            FuncArcs = [Dep | FuncArcs1]
        )
    ).

%-----------------------------------------------------------------------------%

lookup_module_extra_info(Info, ModuleId, Key, MaybeExtraInfo) :-
    ModuleExtraInfos = Info ^ old_extra_infos ^ det_elem(ModuleId),
    (
        String = ModuleExtraInfos ^ elem(Key),
        ExtraInfo = from_string(String)
    ->
        MaybeExtraInfo = yes(ExtraInfo)
    ;
        MaybeExtraInfo = no
    ).

record_module_extra_info(ModuleId, Key, ExtraInfo, !Info) :-
    ( ModuleMap0 = !.Info ^ new_extra_infos ^ elem(ModuleId) ->
        ModuleMap1 = ModuleMap0
    ;
        ModuleMap1 = map.init
    ),
    ModuleMap = map.set(ModuleMap1, Key, to_string(ExtraInfo)),
    !Info ^ new_extra_infos ^ elem(ModuleId) := ModuleMap.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

    % The algorithm is from Nick's thesis, pp. 108-9.
    % Or my corruption thereof.
    % See the `analysis/README' file for a reference.
    %
    % For each new analysis result (P^M:DP --> Ans_new):
    %   Read in the registry of M if necessary
    %   If there is an existing analysis result (P^M:DP --> Ans_old):
    %   if Ans_new \= Ans_old:
    %       Replace the entry in the registry with P^M:DP --> Ans_new
    %       if Ans_new `more_precise_than` Ans_old
    %       Status = suboptimal
    %       else
    %       Status = invalid
    %       For each entry (Q^N:DQ --> P^M:DP) in the IMDG:
    %       % Mark Q^N:DQ --> _ (_) with Status
    %       Actually, we don't do that.  We only mark the
    %       module N's _overall_ status with the
    %       least upper bound of its old status and Status.
    %   Else (P:DP --> Ans_old) did not exist:
    %   Insert result (P:DP --> Ans_new) into the registry.
    %
    % Finally, clear out the "new" analysis results map.  When we write
    % out the analysis files we will do it from the "old" results map.
    %
:- pred update_analysis_registry(analysis_info::in, analysis_info::out,
    io::di, io::uo) is det.

update_analysis_registry(!Info, !IO) :-
    debug_msg(io.write_string("% Updating analysis registry.\n"), !IO),
    map.foldl2(update_analysis_registry_2, !.Info ^ new_analysis_results,
        !Info, !IO),
    !Info ^ new_analysis_results := map.init.

:- pred update_analysis_registry_2(module_id::in,
    module_analysis_map(some_analysis_result)::in,
    analysis_info::in, analysis_info::out, io::di, io::uo) is det.

update_analysis_registry_2(ModuleId, ModuleMap, !Info, !IO) :-
    map.foldl2(update_analysis_registry_3(ModuleId), ModuleMap, !Info, !IO).

:- pred update_analysis_registry_3(module_id::in, analysis_name::in,
    func_analysis_map(some_analysis_result)::in,
    analysis_info::in, analysis_info::out, io::di, io::uo) is det.

update_analysis_registry_3(ModuleId, AnalysisName, FuncMap, !Info, !IO) :-
    map.foldl2(update_analysis_registry_4(ModuleId, AnalysisName),
        FuncMap, !Info, !IO).

:- pred update_analysis_registry_4(module_id::in, analysis_name::in,
    func_id::in, list(some_analysis_result)::in,
    analysis_info::in, analysis_info::out, io::di, io::uo) is det.

update_analysis_registry_4(ModuleId, AnalysisName, FuncId, NewResults,
        !Info, !IO) :-
    % XXX Currently we do not prevent there being more than one recorded result
    % for a given call pattern.
    list.foldl2(update_analysis_registry_5(ModuleId, AnalysisName, FuncId),
        NewResults, !Info, !IO).

:- pred update_analysis_registry_5(module_id::in, analysis_name::in,
    func_id::in, some_analysis_result::in,
    analysis_info::in, analysis_info::out, io::di, io::uo) is det.

update_analysis_registry_5(ModuleId, AnalysisName, FuncId, NewResult,
        !Info, !IO) :-
    NewResult = some_analysis_result(Call, NewAnswer, NewStatus),
    lookup_exactly_matching_result_even_from_invalid_modules(!.Info,
        ModuleId, FuncId, Call, MaybeResult),
    (
        % There was a previous answer for this call pattern.
        %
        MaybeResult = yes(OldResult),
        OldResult = analysis_result(_OldCall, OldAnswer, OldStatus),
        ( equivalent(NewAnswer, OldAnswer) ->
            debug_msg((pred(!.IO::di, !:IO::uo) is det :-
                io.write_string("% No change in the result ", !IO),
                io.write_string(ModuleId, !IO),
                io.write_string(".", !IO),
                io.write_string(FuncId, !IO),
                io.write_string(":", !IO),
                io.write(Call, !IO),
                io.write_string(" --> ", !IO),
                io.write(NewAnswer, !IO),
                io.nl(!IO)
            ), !IO),

            ( NewStatus \= OldStatus ->
                OldMap0 = !.Info ^ old_analysis_results,
                replace_result_in_analysis_map(ModuleId, FuncId,
                    Call, NewAnswer, NewStatus, OldMap0, OldMap),
                !Info ^ old_analysis_results := OldMap
            ;
                true
            )
        ;
            % Answer has changed.
            % Replace the old answer in the registry with the new answer.
            OldMap0 = !.Info ^ old_analysis_results,
            replace_result_in_analysis_map(ModuleId, FuncId,
                Call, NewAnswer, NewStatus, OldMap0, OldMap),
            !Info ^ old_analysis_results := OldMap,

            % If the answer is more precise than before then dependent modules
            % should be marked suboptimal. Otherwise the answer is less precise
            % than it was before, so dependent modules should be invalidated.
            ( more_precise_than(NewAnswer, OldAnswer) ->
                Status = suboptimal
            ;
                Status = invalid
            ),
            debug_msg((pred(!.IO::di, !:IO::uo) is det :-
                io.write_string("% ", !IO),
                io.write(OldAnswer, !IO),
                io.write_string(" changed to ", !IO),
                io.write(NewAnswer, !IO),
                io.nl(!IO),
                io.write_string("Mark dependent modules as ", !IO),
                io.write(Status, !IO),
                io.nl(!IO),
                io.write_string("The modules to mark are: ", !IO),
                io.write(DepModules, !IO),
                io.nl(!IO)
            ), !IO),
            DepModules = imdg_dependent_modules(
                !.Info ^ old_imdg ^ det_elem(ModuleId), AnalysisName,
                FuncId, Call),
            set.fold2(taint_module_overall_status(Status), DepModules,
                !Info, !IO)
        )
    ;
        % There was no previous answer for this call pattern.
        % Just add this result to the registry.
        MaybeResult = no,
        OldMap0 = !.Info ^ old_analysis_results,
        record_result_in_analysis_map(ModuleId, FuncId,
            Call, NewAnswer, NewStatus, OldMap0, OldMap),
        !Info ^ old_analysis_results := OldMap
    ).

    % replace_result_in_analysis_map(ModuleId, FuncId, Call, Answer, Status,
    %   !Map)
    %
    % Replace an analysis result for the given function/call pattern with a
    % new result. A previous result _must_ already exist in the map with
    % exactly the same call pattern.
    %
:- pred replace_result_in_analysis_map(module_id::in, func_id::in,
    Call::in, Answer::in, analysis_status::in,
    analysis_map(some_analysis_result)::in,
    analysis_map(some_analysis_result)::out) is det
    <= analysis(Call, Answer).

replace_result_in_analysis_map(ModuleId, FuncId, CallPattern, AnswerPattern,
        Status, Map0, Map) :-
    AnalysisName = analysis_name(CallPattern, AnswerPattern),
    ModuleResults0 = map.lookup(Map0, ModuleId),
    AnalysisResults0 = map.lookup(ModuleResults0, AnalysisName),
    FuncResults0 = map.lookup(AnalysisResults0, FuncId),
    replace_result_in_list(CallPattern, AnswerPattern, Status,
    FuncResults0, FuncResults),
    Map = map.det_update(Map0, ModuleId,
    map.det_update(ModuleResults0, AnalysisName,
    map.det_update(AnalysisResults0, FuncId, FuncResults))).

:- pred replace_result_in_list(Call::in, Answer::in, analysis_status::in,
    list(some_analysis_result)::in, list(some_analysis_result)::out)
    is det <= analysis(Call, Answer).

replace_result_in_list(Call, Answer, Status, Results0, Results) :-
    (
        Results0 = [],
        unexpected(this_file,
            "replace_result_in_list: found no result to replace")
    ;
        Results0 = [H0 | T0],
        det_univ_to_type(univ(H0 ^ some_ar_call), HCall),
        ( equivalent(Call, HCall) ->
            H = 'new some_analysis_result'(Call, Answer, Status),
            T = T0
        ;
            H = H0,
            replace_result_in_list(Call, Answer, Status, T0, T)
        ),
        Results = [H | T]
    ).

:- func imdg_dependent_modules(module_analysis_map(imdg_arc), analysis_name,
    func_id, Call) = set(module_id)
    <= call_pattern(Call).

imdg_dependent_modules(ModuleMap, AnalysisName, FuncId, Call) =
    (
        map.search(ModuleMap, AnalysisName, FuncAnalysisMap),
        map.search(FuncAnalysisMap, FuncId, IMDGEntries)
    ->
        set.from_list(list.filter_map(arc_module_id(Call), IMDGEntries))
    ;
        set.init
    ).

    % XXX: compiler aborts if the modes are removed
:- func arc_module_id(Call::in, imdg_arc::in) = (module_id::out) is semidet
    <= call_pattern(Call).

arc_module_id(CallA, imdg_arc(CallB0, ModuleId)) = ModuleId :-
    det_univ_to_type(univ(CallB0), CallB),
    equivalent(CallA, CallB).

:- pred taint_module_overall_status(analysis_status::in, module_id::in,
    analysis_info::in, analysis_info::out, io::di, io::uo) is det.

taint_module_overall_status(Status, ModuleId, !Info, !IO) :-
    (
        Status = optimal
    ;
        ( Status = suboptimal
        ; Status = invalid
        ),

        % We may not have loaded the analysis results for this module yet.
        % Even though we loaded all the analysis files of modules reachable
        % from the initial module beforehand, a _caller_ of the initial module
        % may not be part of that set.
        ensure_old_module_analysis_results_loaded(ModuleId, !Info, !IO),

        ModuleStatus0 = !.Info ^ module_statuses ^ det_elem(ModuleId),
        ModuleStatus = lub(ModuleStatus0, Status),
        debug_msg((pred(!.IO::di, !:IO::uo) is det :-
            io.print("% Tainting the overall module status of ", !IO),
            io.print(ModuleId, !IO),
            io.print(" with ", !IO),
            io.print(ModuleStatus, !IO),
            io.nl(!IO)
        ), !IO),
        !Info ^ module_statuses ^ elem(ModuleId) := ModuleStatus
    ).

%-----------------------------------------------------------------------------%

:- pred update_extra_infos(analysis_info::in, analysis_info::out) is det.

update_extra_infos(!Info) :-
    map.foldl(update_extra_infos_2,
        !.Info ^ new_extra_infos, !.Info ^ old_extra_infos, ExtraInfos),
    !Info ^ old_extra_infos := ExtraInfos,
    !Info ^ new_extra_infos := map.init.

:- pred update_extra_infos_2(module_id::in, module_extra_info_map::in,
    map(module_id, module_extra_info_map)::in,
    map(module_id, module_extra_info_map)::out) is det.

update_extra_infos_2(ModuleId, ExtraInfoB, ModuleMap0, ModuleMap) :-
    ( ExtraInfoA = ModuleMap0 ^ elem(ModuleId) ->
        map.overlay(ExtraInfoA, ExtraInfoB, ExtraInfo),
        ModuleMap = ModuleMap0 ^ elem(ModuleId) := ExtraInfo
    ;
        ModuleMap = ModuleMap0 ^ elem(ModuleId) := ExtraInfoB
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

    % For each module N imported by M:
    %   Delete all entries leading to module M from N's IMDG:
    %   For each P^M:DP in S (call patterns to analyse):
    %       add P^M:DP --> Q^N:DQ to N's IMDG
    %
:- pred update_intermodule_dependencies(module_id::in, set(module_id)::in,
    analysis_info::in, analysis_info::out) is det.

update_intermodule_dependencies(ModuleId, ImportedModules, !Info) :-
    set.fold(update_intermodule_dependencies_2(ModuleId), ImportedModules,
        !Info).

:- pred update_intermodule_dependencies_2(module_id::in, module_id::in,
    analysis_info::in, analysis_info::out) is det.

update_intermodule_dependencies_2(ModuleId, ImportedModuleId, !Info) :-
    trace [io(!IO)] (
        debug_msg((pred(!.IO::di, !:IO::uo) is det :-
            io.print("% Clearing entries involving ", !IO),
            io.print(ModuleId, !IO),
            io.print(" from ", !IO),
            io.print(ImportedModuleId, !IO),
            io.print("'s IMDG.\n", !IO)
        ), !IO)
    ),
    IMDG0 = !.Info ^ old_imdg ^ det_elem(ImportedModuleId),
    clear_imdg_entries_pointing_at(ModuleId, IMDG0, IMDG1),

    ( NewArcs = !.Info ^ new_imdg ^ elem(ImportedModuleId) ->
        map.union(combine_func_imdg, IMDG1, NewArcs, IMDG)
    ;
        IMDG = IMDG1
    ),
    !Info ^ old_imdg ^ elem(ImportedModuleId) := IMDG,
    !Info ^ new_imdg := map.delete(!.Info ^ new_imdg, ImportedModuleId).

:- pred clear_imdg_entries_pointing_at(module_id::in,
    module_analysis_map(imdg_arc)::in,
    module_analysis_map(imdg_arc)::out) is det.

clear_imdg_entries_pointing_at(ModuleId, Map0, Map) :-
    map.map_values(clear_imdg_entries_pointing_at_2(ModuleId), Map0, Map).

:- pred clear_imdg_entries_pointing_at_2(module_id::in, analysis_name::in,
    func_analysis_map(imdg_arc)::in,
    func_analysis_map(imdg_arc)::out) is det.

clear_imdg_entries_pointing_at_2(ModuleId, _, FuncMap0, FuncMap) :-
    map.map_values(clear_imdg_entries_pointing_at_3(ModuleId),
        FuncMap0, FuncMap).

:- pred clear_imdg_entries_pointing_at_3(module_id::in, func_id::in,
    list(imdg_arc)::in, list(imdg_arc)::out) is det.

clear_imdg_entries_pointing_at_3(ModuleId, _, Arcs0, Arcs) :-
    list.filter((pred(imdg_arc(_, ModId)::in) is semidet :- ModuleId \= ModId),
        Arcs0, Arcs).

:- pred combine_func_imdg(func_analysis_map(imdg_arc)::in,
    func_analysis_map(imdg_arc)::in, func_analysis_map(imdg_arc)::out) is det.

combine_func_imdg(FuncImdgA, FuncImdgB, FuncImdg) :-
    map.union(combine_imdg_lists, FuncImdgA, FuncImdgB, FuncImdg).

:- pred combine_imdg_lists(list(imdg_arc)::in, list(imdg_arc)::in,
    list(imdg_arc)::out) is det.

combine_imdg_lists(ArcsA, ArcsB, ArcsA ++ ArcsB).

%-----------------------------------------------------------------------------%

prepare_intermodule_analysis(ModuleIds, LocalModuleIds, !Info, !IO) :-
    set.fold2(ensure_analysis_files_loaded, ModuleIds, !Info, !IO),
    !Info ^ local_module_ids := LocalModuleIds.

:- pred ensure_analysis_files_loaded(module_id::in,
    analysis_info::in, analysis_info::out, io::di, io::uo) is det.

ensure_analysis_files_loaded(ModuleId, !Info, !IO) :-
    ensure_old_module_analysis_results_loaded(ModuleId, !Info, !IO),
    ensure_old_imdg_loaded(ModuleId, !Info, !IO).

:- pred ensure_old_module_analysis_results_loaded(module_id::in,
    analysis_info::in, analysis_info::out, io::di, io::uo) is det.

ensure_old_module_analysis_results_loaded(ModuleId, !Info, !IO) :-
    ( map.search(!.Info ^ old_analysis_results, ModuleId, _Results) ->
        % sanity check
        map.lookup(!.Info ^ module_statuses, ModuleId, _StatusMustExist)
    ;
        read_module_analysis_results(!.Info, ModuleId,
            ModuleStatus, ModuleResults, ExtraInfos, !IO),
        !Info ^ module_statuses ^ elem(ModuleId) := ModuleStatus,
        !Info ^ old_analysis_results ^ elem(ModuleId) := ModuleResults,
        !Info ^ old_extra_infos ^ elem(ModuleId) := ExtraInfos
    ).

:- pred ensure_old_imdg_loaded(module_id::in, analysis_info::in,
    analysis_info::out, io::di, io::uo) is det.

ensure_old_imdg_loaded(ModuleId, !Info, !IO) :-
    Map0 = !.Info ^ old_imdg,
    ( map.search(Map0, ModuleId, _) ->
        % already loaded
        true
    ;
        read_module_imdg(!.Info, ModuleId, IMDG, !IO),
        map.det_insert(Map0, ModuleId, IMDG, Map),
        !Info ^ old_imdg := Map
    ).

module_is_local(Info, ModuleId, IsLocal) :-
    ( set.contains(Info ^ local_module_ids, ModuleId) ->
        IsLocal = yes
    ;
        IsLocal = no
    ).

%-----------------------------------------------------------------------------%

    % In this procedure we have just finished compiling module ModuleId
    % and will write out data currently cached in the analysis_info structure
    % out to disk.
    %
write_analysis_files(Compiler, ModuleId, ImportedModuleIds, !Info, !IO) :-
    % The current module was just compiled so we set its status to the
    % lub of all the new analysis results generated.
    ( NewResults = !.Info ^ new_analysis_results ^ elem(ModuleId) ->
        ModuleStatus = lub_result_statuses(NewResults)
    ; 
        ModuleStatus = optimal,
        % Force an `.analysis' file to be written out for this module,
        % even though there are no results recorded for it.
        !Info ^ new_analysis_results ^ elem(ModuleId) := map.init
    ),

    update_analysis_registry(!Info, !IO),
    update_extra_infos(!Info),

    !Info ^ module_statuses ^ elem(ModuleId) := ModuleStatus,

    update_intermodule_dependencies(ModuleId, ImportedModuleIds, !Info),
    (
        map.is_empty(!.Info ^ new_analysis_results),
        map.is_empty(!.Info ^ new_extra_infos)
    ->
        true
    ;
        io.print("Warning: new_analysis_results or extra_infos is not empty\n",
            !IO),
        io.print(!.Info ^ new_analysis_results, !IO),
        io.nl(!IO),
        io.print(!.Info ^ new_extra_infos, !IO),
        io.nl(!IO)
    ),

    % Write the results for all the modules we know of.  For the module being
    % compiled, the analysis results may have changed. For other modules,
    % their overall statuses may have changed.
    write_local_modules(!.Info, write_module_analysis_results,
        !.Info ^ old_analysis_results, !IO),

    % Write the requests for the imported modules.
    write_local_modules(!.Info, write_module_analysis_requests,
        !.Info ^ analysis_requests, !IO),

    % Remove the requests for the current module since we (should have)
    % fulfilled them in this pass.
    empty_request_file(!.Info, ModuleId, !IO),

    % Write the intermodule dependency graphs.
    write_local_modules(!.Info, write_module_imdg, !.Info ^ old_imdg, !IO),

    % Touch a timestamp file to indicate the last time that this module was
    % analysed.
    module_id_to_write_file_name(Compiler, ModuleId, ".analysis_date",
        TimestampFileName, !IO),
    io.open_output(TimestampFileName, Result, !IO),
    (
        Result = ok(OutputStream),
        io.write_string(OutputStream, "\n", !IO),
        io.close_output(OutputStream, !IO)
    ;
        Result = error(IOError),
        unexpected(this_file,
            "write_analysis_files: " ++ io.error_message(IOError))
    ).

:- type write_module_analysis_map(T) ==
    (pred(analysis_info, module_id, module_analysis_map(T), io, io)).
:- mode write_module_analysis_map == in(pred(in, in, in, di, uo) is det).

:- pred write_local_modules(analysis_info::in,
    write_module_analysis_map(T)::write_module_analysis_map,
    analysis_map(T)::in, io::di, io::uo) is det.

write_local_modules(Info, Write, AnalysisMap, !IO) :-
    map.foldl(write_local_modules_2(Info, Write), AnalysisMap, !IO).

:- pred write_local_modules_2(analysis_info::in,
    write_module_analysis_map(T)::write_module_analysis_map,
    module_id::in, module_analysis_map(T)::in, io::di, io::uo) is det.

write_local_modules_2(Info, Write, ModuleId, ModuleResults, !IO) :-
    module_is_local(Info, ModuleId, IsLocal),
    (
        IsLocal = yes,
        Write(Info, ModuleId, ModuleResults, !IO)
    ;
        IsLocal = no,
        debug_msg((pred(!.IO::di, !:IO::uo) is det :-
            io.write_string("% Not writing file for non-local module ", !IO),
            io.write_string(ModuleId, !IO),
            io.nl(!IO)
        ), !IO)
    ).

:- pred write_module_analysis_results(analysis_info::in, module_id::in,
    module_analysis_map(some_analysis_result)::in, io::di, io::uo) is det.

write_module_analysis_results(Info, ModuleId, ModuleResults, !IO) :-
    ModuleStatus = Info ^ module_statuses ^ det_elem(ModuleId),
    ( ModuleExtraInfo0 = Info ^ old_extra_infos ^ elem(ModuleId) ->
        ModuleExtraInfo = ModuleExtraInfo0
    ;
        ModuleExtraInfo = map.init
    ),
    analysis.file.write_module_analysis_results(Info, ModuleId,
        ModuleStatus, ModuleResults, ModuleExtraInfo, !IO).

%-----------------------------------------------------------------------------%

read_module_overall_status(Compiler, ModuleId, MaybeModuleStatus, !IO) :-
    analysis.file.read_module_overall_status(Compiler, ModuleId,
        MaybeModuleStatus, !IO).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

lub(StatusA, StatusB) = Status :-
    compare(Cmp, StatusA, StatusB),
    (
        Cmp = (=),
        Status = StatusA
    ;
        Cmp = (<),
        Status = StatusA
    ;
        Cmp = (>),
        Status = StatusB
    ).

:- func lub_result_statuses(module_analysis_map(some_analysis_result))
    = analysis_status.

lub_result_statuses(ModuleMap) =
    map.foldl(lub_result_statuses_2, ModuleMap, optimal).

:- func lub_result_statuses_2(analysis_name,
    func_analysis_map(some_analysis_result), analysis_status) =
    analysis_status.

lub_result_statuses_2(_AnalysisName, FuncMap, Acc) =
    map.foldl(lub_result_statuses_3, FuncMap, Acc).

:- func lub_result_statuses_3(func_id, list(some_analysis_result),
    analysis_status) = analysis_status.

lub_result_statuses_3(_FuncId, Results, Acc) =
    list.foldl(lub_result_statuses_4, Results, Acc).

:- func lub_result_statuses_4(some_analysis_result, analysis_status)
    = analysis_status.

lub_result_statuses_4(Result, Acc) = lub(Result ^ some_ar_status, Acc).

%-----------------------------------------------------------------------------%

:- mutable(debug_analysis, bool, no, ground, [untrailed, attach_to_io_state]).

enable_debug_messages(Debug, !IO) :-
    set_debug_analysis(Debug, !IO).

:- pred debug_msg(pred(io, io)::in(pred(di, uo) is det), io::di, io::uo)
    is det.

debug_msg(P, !IO) :-
    get_debug_analysis(Debug, !IO),
    (
        Debug = yes,
        P(!IO)
    ;
        Debug = no
    ).

%-----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "analysis.m".

%-----------------------------------------------------------------------------%
:- end_module analysis.
%-----------------------------------------------------------------------------%