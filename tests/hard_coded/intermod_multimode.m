:- module intermod_multimode.
:- interface.

:- func func0 = string.
:- mode func0 = out is det.
	
:- func func1(int) = string.
:- mode func1(in) = out is det.
:- mode func1(out) = out is det.

:- func func2(int, int) = string.
:- mode func2(in, in) = out is det.
:- mode func2(in, out) = out is det.
:- mode func2(out, in) = out is det.
:- mode func2(out, out) = out is det.

:- impure pred test0.
:- mode test0 is det.

:- impure pred test1(int).
:- mode test1(in) is det.
:- mode test1(out) is det.

:- impure pred test2(int, int).
:- mode test2(in, in) is det.
:- mode test2(in, out) is det.
:- mode test2(out, in) is det.
:- mode test2(out, out) is det.

:- impure pred puts(string::in) is det.

:- implementation.

func0 = ("func0 = out" :: out).

:- pragma promise_pure(func1/1). % XXX technically this is a lie
func1(_::in) = ("func1(in) = out"::out).
func1(0::out) = ("func1(out) = out"::out).

:- pragma promise_pure(func2/2). % XXX technically this is a lie
func2(_::in, _::in) = (R::out) :-
	R = "func2(in, in) = out".
func2(_::in, 0::out) = (R::out) :-
	R = "func2(in, out) = out".
func2(0::out, _::in) = (R::out) :-
	R = "func2(out, in) = out".
func2(0::out, 0::out) = (R::out) :-
	R = "func2(out, out) = out".

test0 :-
	impure puts("test0").
	
test1(_::in) :-
	impure puts("test1(in)").
test1(0::out) :-
	impure puts("test1(out)").

test2(_::in, _::in) :-
	impure puts("test2(in, in)").
test2(_::in, 0::out) :-
	impure puts("test2(in, out)").
test2(0::out, _::in) :-
	impure puts("test2(out, in)").
test2(0::out, 0::out) :-
	impure puts("test2(out, out)").

:- pragma c_code(puts(S::in), [will_not_call_mercury], "puts(S)").
