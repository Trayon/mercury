:- module intermod_c_code2.

:- interface.

:- some [U] pred c_code(T::in, U::out) is det.

:- implementation.

c_code(T, U) :- c_code_2(T, U).

:- some [U] pred c_code_2(T::in, U::out) is det.

:- pragma c_code(c_code_2(T::in, U::out),
"{
	U = T;
	TypeInfo_for_U = TypeInfo_for_T;
}").

