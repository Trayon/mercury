%-----------------------------------------------------------------------------%
% regex.m
% Ralph Becket <rafe@cs.mu.oz.au>
% Copyright (C) 2002, 2006 The University of Melbourne
% vim: ft=mercury ts=4 sw=4 et wm=0 tw=0
%
% This module provides basic string matching and search and replace
% functionality using regular expressions defined as strings of the
% form recognised by tools such as sed and grep.
%
% The regular expression langauge matched is a subset of POSIX 1003.2
% with a few minor differences:
% - bounds {[n][,[m]]} are not recognised;
% - collating elements [.ab.] in character sets are not recognised;
% - equivalence classes [=x=] in character sets are not recognised;
% - character classes [:space:] in character sets are not recognised;
% - special inter-character patterns such as ^, $, \<, \> are not recognised;
% - to include a literal `-' in a character set, use the range `---' or
% include `-' as one end-point of a range (e.g. [!--]);
% - regex will complain if `-' appears other than as an end-point
% of a range or the range delimiter in a character set;
% - regex is a little more sensible about including `[' and `]' in character
% sets - either character can appear as and end-point of a range;
% - literal `)' must be backslash escaped, even in the absence of an `(';
% - `.' matches any character except `\n';
% - [^...] matches any character not in ... or `\n'.
% NOTE: these minor differences may go away in a future revision of this
% module.
%
%-----------------------------------------------------------------------------%

:- module regex.

:- interface.

:- import_module string, list.
:- import_module lex.

    % The type of (compiled) regular expressions.
    %
:- type regex.
:- inst regex == lexer.

    % A function for converting a POSIX style regex string to a regex
    % suitable for the string matching operations provided in this
    % module.
    %
    % An exception is thrown if the regex string is malformed.  We
    % memoize this function for efficiency (it is cheaper to look up a
    % string in a hash table than to parse it and recompute the regex.)
    %
    % A regex string obeys the following grammar.  Note that alternation
    % has lowest priority, followed by concatenation, followed by
    % *, + and ?.  Hence "ab*" is equivalent to "a(b*)" and not "(ab)*"
    % while "ab|cd" is equivalent to "(ab)|(cd)" and not "a(b|c)d".
    %
    % <regex> ::= <char>                % Single char
    %           |  <regex><regex>       % Concatenation
    %           |  .                    % Any char but \n
    %           |  <set>                % Any char in set
    %           |  <regex>|<regex>      % Alternation
    %           |  <regex>*             % Kleene closure (zero or more)
    %           |  <regex>+             % One or more occurrences
    %           |  <regex>?             % Zero or one occurrence
    %           |  (<regex>)
    %
    % (Note the need to use double-backslashes in Mercury strings.
    % The following chars must be escaped if they are intended
    % literally: .|*+?()[]\.  Escapes should not be used in sets.)
    %
    % <char>   ::= \<any char>          % Literal char used in regexes
    %           |  <ordinary char>      % All others
    %
    % <escaped char> ::= . | | | * | + | ? | ( | ) | [ | ] | \
    %
    % (If the first char in a <set'> is ] then it is taken as part of
    % the char set and not the closing bracket.  Similarly, ] may appear
    % as the end char in a range and it will not be taken as the closing
    % bracket.)
    %
    % <set>    ::= [^<set'>]            % Any char not in <set'> or '\n'
    %           |  [<set'>]             % Any char in <set'>
    %
    % <set'>   ::= <any char>-<any char>% Any char in range
    %           |  <any char>           % Literal char
    %           |  <set'><set'>         % Set union
    %
:- func regex(string) = regex.
:- mode regex(in    ) = out(regex) is det.

    % This is a utility function for lex - it compiles a string into a
    % regexp (not a regex, which is for use with this module) suitable
    % for use in lexemes.
    %
    % We memoize this function for efficiency (it is cheaper to look up a
    % string in a hash table than to parse it and recompute the regexp.)
    %
:- func regexp(string) = regexp.

    % left_match(Regex, String, Substring, Start, Count)
    %   succeeds iff Regex maximally matches the first Count characters
    %   of String.
    %
    %   This is equivalent to the goal
    %
    %       {Substring, Start, Count} = head(matches(Regex, String)),
    %       Start = 0
    %
:- pred left_match(regex,     string, string, int, int).
:- mode left_match(in(regex), in,     out,    out, out) is semidet.

    % right_match(Regex, String, Substring, Start, Count)
    %   succeeds iff Regex maximally matches the last Count characters
    %   of String.
    %
    %   This is equivalent to the goal
    %
    %       {Substring, Start, Count} = last(matches(Regex, String)),
    %       Start + Count = length(String)
    %
:- pred right_match(regex,     string, string, int, int).
:- mode right_match(in(regex), in,     out,    out, out) is semidet.

    % first_match(Regex, String, Substring, Start, Count)
    %   succeeds iff Regex matches some Substring of String,
    %   setting Substring, Start and Count to the maximal first
    %   such occurrence.
    %
    %   This is equivalent to the goal
    %
    %       {Substring, Start, Count} = head(matches(Regex, String))
    %
:- pred first_match(regex,     string, string, int, int).
:- mode first_match(in(regex), in,     out,    out, out) is semidet.

    % exact_match(Regex, String)
    %   succeeds iff Regex exactly matches String.
    %
:- pred exact_match(regex,     string).
:- mode exact_match(in(regex), in    ) is semidet.

    % matches(Regex, String) = [{Substring, Start, Count}, ...]
    %   Regex exactly matches Substring = substring(String, Start, Count).
    %   None of the {Start, Count} regions will overlap and are in
    %   ascending order with respect to Start.
    %
:- func matches(regex,     string) = list({string, int, int}).
:- mode matches(in(regex), in    ) = out is det.

    % replace_first(Regex, Replacement, String)
    %   computes the string formed by replacing the maximal first match
    %   of Regex (if any) in String with Replacement.
    %
:- func replace_first(regex,     string, string) = string.
:- mode replace_first(in(regex), in,     in    ) = out is det.

    % replace_all(Regex, Replacement, String)
    %   computes the string formed by replacing the maximal non-overlapping
    %   matches of Regex in String with Replacement.
    %
:- func replace_all(regex,     string, string) = string.
:- mode replace_all(in(regex), in,     in    ) = out is det.

    % change_first(Regex, ChangeFn, String)
    %   computes the string formed by replacing the maximal first match
    %   of Regex (Substring, if any) in String with ChangeFn(Substring).
    %
:- func change_first(regex,     func(string) = string,     string) = string.
:- mode change_first(in(regex), func(in    ) = out is det, in    ) = out is det.

    % change_all(Regex, ChangeFn, String)
    %   computes the string formed by replacing the maximal non-overlapping
    %   matches of Regex, Substring, in String with ChangeFn(Substring).
    %
:- func change_all(regex,     func(string) = string,     string) = string.
:- mode change_all(in(regex), func(in    ) = out is det, in    ) = out is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module int, char, bool, require, std_util, pair, io.



:- type regex == lexer(string, string).

:- type lexer_state == lexer_state(string, string).



    % This states of the regex parser.
    %
:- type parser_state
    --->    res(list(re))                        % Parsing as usual.
    ;       esc(list(re))                        % A character escape.
    ;       set1(list(re))                       % The char set parsing states.
    ;       set2(bool, list(re))
    ;       set3(bool, char, chars, list(re))
    ;       set4(bool, char, chars, list(re))
    ;       set5(bool, chars, list(re)).

    % The possible semi-parsed regexes.
    %
:- type re
    --->    re(regexp)                      % An ordinary regexp.
    ;       char(regexp)                    % A single char regexp.
    ;       lpar                            % A left parenthesis.
    ;       alt(regexp).                    % An alternation.

:- type chars == list(char).

%-----------------------------------------------------------------------------%

:- pragma memo(regex/1).

regex(S) = init([regexp(S) - id], read_from_string).

%-----------------------------------------------------------------------------%

:- pragma memo(regexp/1).

regexp(S) = finish_regex(S, foldl(compile_regex(S), S, res([]))).

%-----------------------------------------------------------------------------%

:- func compile_regex(string, char, parser_state) = parser_state.

    % res: we are looking for the next regex or operator.
    %
compile_regex(S, C, res(REs)) =
    (      if C = ('.')  then res([re(dot) | REs])
      else if C = ('|')  then res(alt(S, REs))
      else if C = ('*')  then res(star(S, REs))
      else if C = ('+')  then res(plus(S, REs))
      else if C = ('?')  then res(opt(S, REs))
      else if C = ('(')  then res([lpar | REs])
      else if C = (')')  then res(rpar(S, REs))
      else if C = ('[')  then set1(REs)
      else if C = (']')  then regex_error("`]' without opening `['", S)
      else if C = ('\\') then esc(REs)
      else                    res([char(re(C)) | REs])
    ).

    % esc: the current char has been \ escaped.
    %
compile_regex(_, C, esc(REs)) =
    res([char(re(C)) | REs]).

    % set1: we have just seen the opening [.
    %
compile_regex(_, C, set1(REs)) =
    (      if C = ('^') then set2(yes, REs)
      else                   set3(no,  C, [], REs)
    ).

    % set2: we are looking for the first char in the set, which may
    % include ].
    %
compile_regex(_, C, set2(Complement, REs)) =
                             set3(Complement, C, [], REs).

    % set3: we are looking for a char or - or ].
    %
compile_regex(_, C, set3(Complement, C0, Cs, REs)) =
    (      if C = (']') then res([char_set(Complement, [C0 | Cs]) | REs])
      else if C = ('-') then set4(Complement, C0, Cs, REs)
      else                   set3(Complement, C, [C0 | Cs], REs)
    ).

    % set4: we have just seen a `-' for a range.
    %
compile_regex(_, C, set4(Complement, C0, Cs, REs)) =
                             set5(Complement, push_range(C0, C, Cs), REs).

    % set5: we are looking for a char or ].
    %
compile_regex(_, C, set5(Complement, Cs, REs)) =
    (      if C = (']') then res([char_set(Complement, Cs) | REs])
      else                   set3(Complement, C, Cs, REs)
    ).

%-----------------------------------------------------------------------------%

    % Turn a list of chars into an any or anybut.
    %
:- func char_set(bool, chars) = re.

char_set(no,  Cs) = re(any(from_char_list(Cs))).
char_set(yes, Cs) = re(anybut(from_char_list([('\n') | Cs]))).

%-----------------------------------------------------------------------------%

    % Push a range of chars onto a char list.
    %
:- func push_range(char, char, chars) = chars.

push_range(A, B, Cs) = Rg ++ Cs :-
    Lo = min(to_int(A), to_int(B)),
    Hi = max(to_int(A), to_int(B)),
    Rg = map(int_to_char, Lo `..` Hi).


:- func int_to_char(int) = char.

int_to_char(X) =
    ( if char__to_int(C, X) then C else func_error("regex__int_to_char") ).

%-----------------------------------------------------------------------------%

:- func finish_regex(string, parser_state) = regexp.

finish_regex(S, esc(_)) =
    regex_error("expected char after `\\'", S).

finish_regex(S, set1(_)) =
    regex_error("`[' without closing `]'", S).

finish_regex(S, set2(_, _)) =
    regex_error("`[' without closing `]'", S).

finish_regex(S, set3(_, _, _, _)) =
    regex_error("`[' without closing `]'", S).

finish_regex(S, set4(_, _, _, _)) =
    regex_error("`[' without closing `]'", S).

finish_regex(S, set5(_, _, _)) =
    regex_error("`[' without closing `]'", S).

finish_regex(S, res(REs)) =
    ( if   rpar(S, REs ++ [lpar]) = [RE]
      then extract_regex(RE)
      else regex_error("`(' without closing `)'", S)
    ).

%-----------------------------------------------------------------------------%

    % The *, + and ? regexes.
    %
:- func star(string, list(re)) = list(re).

star(S, REs) =
    ( if   ( REs = [re(RE) | REs0] ; REs = [char(RE) | REs0] )
      then [re(*(RE)) | REs0]
      else regex_error("`*' without preceding regex", S)
    ).

:- func plus(string, list(re)) = list(re).

plus(S, REs) =
    ( if   ( REs = [re(RE) | REs0] ; REs = [char(RE) | REs0] )
      then [re(+(RE)) | REs0]
      else regex_error("`+' without preceding regex", S)
    ).

:- func opt(string, list(re)) = list(re).

opt(S, REs) =
    ( if   ( REs = [re(RE) | REs0] ; REs = [char(RE) | REs0] )
      then [re(?(RE)) | REs0]
      else regex_error("`?' without preceding regex", S)
    ).

%-----------------------------------------------------------------------------%

    % Handle an alternation sign.
    %
:- func alt(string, list(re)) = list(re).

alt(S, REs) =
    (      if REs =   [alt(_)                                         | _   ]
      then    regex_error("`|' immediately following `|'", S)

      else if REs =   [lpar                                           | _   ]
      then    regex_error("`|' immediately following `('", S)

      else if REs =   [RE_B, alt(RE_A)                                | REs0]
      then            [alt(RE_A or extract_regex(RE_B))               | REs0]

      else if REs =   [RE, lpar                                       | REs0]
      then            [alt(extract_regex(RE)), lpar                   | REs0]

      else if REs =   [RE_B, RE_A                                     | REs0]
      then    alt(S,  [re(extract_regex(RE_A) ++ extract_regex(RE_B)) | REs0])

      else if REs =   [RE]
      then            [alt(extract_regex(RE))]

      else regex_error("`|' without preceding regex", S)
    ).

%-----------------------------------------------------------------------------%

    % Handle a closing parenthesis.
    %
:- func rpar(string, list(re)) = list(re).

rpar(S, REs) =
    (      if REs =   [alt(_)                                         | _   ]
      then    regex_error("`)' immediately following `|'", S)

      else if REs =   [RE_B, alt(RE_A)                                | REs0]
      then    rpar(S, [re(RE_A or extract_regex(RE_B))                | REs0])

      else if REs =   [lpar                                           | REs0]
      then            [nil                                            | REs0]

      else if REs =   [RE, lpar                                       | REs0]
      then            [RE                                             | REs0]

      else if REs =   [RE_B, RE_A                                     | REs0]
      then    rpar(S, [re(extract_regex(RE_A) ++ extract_regex(RE_B)) | REs0])

      else    regex_error("`)' without opening `('", S)
    ).

%-----------------------------------------------------------------------------%

:- func extract_regex(re) = regexp.

extract_regex(re(R))   = R.
extract_regex(char(R)) = R.
extract_regex(alt(_))  = func_error("regex__extract_regex").
extract_regex(lpar)    = func_error("regex__extract_regex").

%-----------------------------------------------------------------------------%

    % Throw a wobbly.
    %
:- func regex_error(string, string) = _.
:- mode regex_error(in, in) = out is erroneous.

regex_error(Msg, String) =
    func_error("regex: " ++ Msg ++ " in \"" ++ String ++ "\"").

%-----------------------------------------------------------------------------%

    % The empty regex.
    %
:- func nil = re.

nil = re(re("")).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

left_match(Regex, String, Substring, 0, length(Substring)) :-
    State = start(Regex, unsafe_promise_unique(String)),
    lex__read(ok(Substring), State, _).

%-----------------------------------------------------------------------------%

    % We have to keep trying successive suffixes of String until
    % we find a complete match.
    %
right_match(Regex, String, Substring, Start, length(Substring)) :-
    right_match_2(Regex, String, 0, length(String), Substring, Start).


:- pred right_match_2(regex,     string, int, int, string, int).
:- mode right_match_2(in(regex), in,     in,  in,  out,    out) is semidet.

right_match_2(Regex, String, I, Length, Substring, Start) :-
    I =< Length,
    Substring0 = substring(String, I, max_int),
    ( if exact_match(Regex, Substring0) then
        Substring = Substring0,
        Start     = I
      else
        right_match_2(Regex, String, I + 1, Length, Substring, Start)
    ).

%-----------------------------------------------------------------------------%

first_match(Regex, String, Substring, Start, length(Substring)) :-
    State = start(Regex, unsafe_promise_unique(String)),
    first_match_2(Substring, Start, State).


:- pred first_match_2(string, int, lexer_state).
:- mode first_match_2(out,    out, di         ) is semidet.

first_match_2(Substring, Start, !.State) :-
    lex__offset_from_start(Start0, !State),
    lex__read(Result,         !State),
    (
        Result = error(_, _),
        first_match_2(Substring, Start, !.State)
    ;
        Result = ok(Substring),
        Start  = Start0
    ).

%-----------------------------------------------------------------------------%

exact_match(Regex, String) :-
    State = start(Regex, unsafe_promise_unique(String)),
    lex__read(ok(String), State, _).

%-----------------------------------------------------------------------------%

matches(Regex, String) = Matches :-
    State   = start(Regex, unsafe_promise_unique(String)),
    Matches = matches_2(length(String), -1, State).


:- func matches_2(int, offset, lexer_state) = list({string, int, int}).
:- mode matches_2(in,  in,     di)          = out is det.

matches_2(Length, LastEnd, State0) = Matches :-
    lex__offset_from_start(Start0, State0, State1),
    lex__read(Result, State1, State2),
    lex__offset_from_start(End, State2, State3),
    (
        Result  = eof,
        Matches = []
    ;
        Result  = error(_, _),
        Matches = matches_2(Length, End, State3)
    ;
        Result  = ok(Substring),
        Start   = Start0,
        Count   = End - Start,

            % If we matched the empty string then we have to advance
            % at least one char (and finish if we get eof.)
            %
            % If we've reached the end of the input then also finish
            % (this avoids the situation where, say, ".*" produces
            % two matches for "foo" - "foo" and the notional null string
            % at the end.)
            %
            % If we matched the empty string at the same point the
            % last match ended, then we ignore this solution and
            % move on.
            %
        Matches =
            ( if Count = 0, Start = LastEnd then

                    % This is an empty match at the same point as the end
                    % of our last match.  We have to ignore it and move on.
                    % 
                ( if   lex__read_char(ok(_), State3, State4)
                  then matches_2(Length, End, State4)
                  else []
                )

              else

                [ {Substring, Start, Count} |
                  ( if End = Length then
                        []
                    else if Count = 0 then
                        ( if   lex__read_char(ok(_), State3, State4)
                          then matches_2(Length, End, State4)
                          else []
                        )
                    else
                      matches_2(Length, End, State3)
                  )
                ]
            )
    ).

%-----------------------------------------------------------------------------%

replace_first(Regex, Replacement, String) =
    change_first(Regex, func(_) = Replacement, String).

%-----------------------------------------------------------------------------%

replace_all(Regex, Replacement, String) =
    change_all(Regex, func(_) = Replacement, String).

%-----------------------------------------------------------------------------%

change_first(Regex, ChangeFn, String) =
    ( if first_match(Regex, String, Substring, Start, Count) then
        append_list([
            substring(String, 0, Start),
            ChangeFn(Substring),
            substring(String, Start + Count, max_int)
        ])
      else
        String
    ).

%-----------------------------------------------------------------------------%

change_all(Regex, ChangeFn, String) =
    append_list(change_all_2(String, ChangeFn, 0, matches(Regex, String))).


:- func change_all_2(string, func(string) = string, int,
            list({string, int, int})) = list(string).

change_all_2(String, _ChangeFn, I, []) =
    [ substring(String, I, max_int) ].

change_all_2(String, ChangeFn, I, [{Substring, Start, Count} | Matches]) =
    [ substring(String, I, Start - I),
      ChangeFn(Substring)
    | change_all_2(String, ChangeFn, Start + Count, Matches) ].

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
