% Check that we don't emit inferred erroneous warnings for opt imported
% predicates.
:- module opt_det_warn.
:- interface.
:- import_module io.
:- pred main(io::di, io::uo) is det.
:- implementation.
:- import_module opt_det_warn2.
main(!IO) :-
	foo(!IO).
