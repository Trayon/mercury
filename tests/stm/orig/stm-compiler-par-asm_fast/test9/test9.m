%------------------------------------------------------------------------------%
% test9.m
% <lmika@csse.unimelb.edu.au>
% Sat Oct  6 16:53:50 EST 2007
% vim: ft=mercury ff=unix ts=4 sw=4 et
%
%------------------------------------------------------------------------------%

:- module test9.

:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%------------------------------------------------------------------------------%

:- implementation.

:- import_module univ.

%------------------------------------------------------------------------------%

main(!IO) :-
    X = univ(123),
    io.write(X, !IO),
    io.nl(!IO),
    ( X = univ(Y) ->
        io.write_int(Y, !IO),
        io.nl(!IO)
    ;
        io.write_string("X is not univ", !IO)
    ).

%------------------------------------------------------------------------------%
%------------------------------------------------------------------------------%
