%---------------------------------------------------------------------------%
% Copyright (C) 1999-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% This module defines the representation of basic types used by
% the bytecode interpreter and by the Aditi bytecodes.
%
% Note: This file is included in both the Mercury compiler
% and the Aditi bytecode assembler.
%
% Author: zs, aet, stayl.
%
%---------------------------------------------------------------------------%

:- module bytecode_data.

:- interface.

:- import_module io, int, list, string.

:- pred output_string(string, io__state, io__state).
:- mode output_string(in, di, uo) is det.

:- pred string_to_byte_list(string, list(int)).
:- mode string_to_byte_list(in, out) is det.

:- pred output_byte(int, io__state, io__state).
:- mode output_byte(in, di, uo) is det.

/*
** Spit out an `int' in a portable `highest common denominator' format.
** This format is: big-endian, 64-bit, 2's-complement int.
**
** NOTE: We -assume- the machine architecture uses 2's-complement.
*/
:- pred output_int(int, io__state, io__state).
:- mode output_int(in, di, uo) is det.

:- pred int_to_byte_list(int, list(int)).
:- mode int_to_byte_list(in, out) is det.

/*
** Same as output_int and int_to_byte_list, except only use 32 bits.
*/
:- pred output_int32(int, io__state, io__state).
:- mode output_int32(in, di, uo) is det.

:- pred int32_to_byte_list(int, list(int)).
:- mode int32_to_byte_list(in, out) is det.

/*
** Spit out a `short' in a portable format.
** This format is: big-endian, 16-bit, 2's-complement.
**
** NOTE: We -assume- the machine architecture uses 2's-complement.
*/
:- pred output_short(int, io__state, io__state).
:- mode output_short(in, di, uo) is det.

:- pred short_to_byte_list(int, list(int)).
:- mode short_to_byte_list(in, out) is det.

/*
** Spit out a `float' in a portable `highest common denominator format.
** This format is: big-endian, 64-bit, IEEE-754 floating point value.
**
** NOTE: We -assume- the machine architecture uses IEEE-754.
*/
:- pred output_float(float, io__state, io__state).
:- mode output_float(in, di, uo) is det.

:- pred float_to_byte_list(float, list(int)).
:- mode float_to_byte_list(in, out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module char, require.

output_string(Val) -->
	io__write_bytes(Val),
	io__write_byte(0).

string_to_byte_list(Val, List) :-
	string__to_char_list(Val, Chars),
	ToInt = (pred(C::in, I::out) is det :- char__to_int(C, I)),
	list__map(ToInt, Chars, List0),
	list__append(List0, [0], List).

output_byte(Val) -->
	( { Val < 256 } ->
		io__write_byte(Val)
	;
		{ error("byte does not fit in eight bits") }
	).

output_short(Val) -->
	output_int(16, Val).

short_to_byte_list(Val, Bytes) :-
	int_to_byte_list(16, Val, Bytes).

output_int32(IntVal) -->
	output_int(32, IntVal).

int32_to_byte_list(IntVal, List) :-
	int_to_byte_list(32, IntVal, List).

output_int(IntVal) -->
	{ int__bits_per_int(IntBits) },
	( { IntBits > bytecode_int_bits } ->
		{ error("size of int is larger than size of bytecode integer.")}
	;
		output_int(bytecode_int_bits, IntVal)
	).

int_to_byte_list(IntVal, Bytes) :-
	int__bits_per_int(IntBits),
	( IntBits > bytecode_int_bits ->
		error("size of int is larger than size of bytecode integer.")
	;
		int_to_byte_list(bytecode_int_bits, IntVal, Bytes)
	).

:- pred output_int(int, int, io__state, io__state).
:- mode output_int(in, in, di, uo) is det.

output_int(Bits, IntVal) -->
	output_int(io__write_byte, Bits, IntVal).

:- pred int_to_byte_list(int, int, list(int)).
:- mode int_to_byte_list(in, in, out) is det.

int_to_byte_list(Bits, IntVal, Bytes) :-
	output_int(cons, Bits, IntVal, [], RevBytes),
	list__reverse(RevBytes, Bytes).

:- pred cons(T, list(T), list(T)).
:- mode cons(in, in, out) is det.

cons(T, List, [T | List]).

:- pred output_int(pred(int, T, T), int, int, T, T).
:- mode output_int(pred(in, in, out) is det, in, in, in, out) is det.
:- mode output_int(pred(in, di, uo) is det, in, in, di, uo) is det.

output_int(Writer, Bits, IntVal) -->
	{ int__bits_per_int(IntBits) },
	{ 
		Bits < IntBits,
		int__pow(2, Bits - 1, MaxVal),
		( IntVal >= MaxVal
		; IntVal < -MaxVal
		)
	->
		string__format(
		"error: bytecode_data__output_int: %d does not fit in %d bits",
			[i(IntVal), i(Bits)], Msg),
		error(Msg)
	;
		true
	},
	{ Bits > IntBits ->
		ZeroPadBytes is (Bits - IntBits) // bits_per_byte
	;
		ZeroPadBytes = 0
	},
	output_padding_zeros(Writer, ZeroPadBytes),
	{ BytesToDump = Bits // bits_per_byte },
	{ FirstByteToDump is BytesToDump - ZeroPadBytes - 1 },
	output_int_bytes(Writer, FirstByteToDump, IntVal).

:- func bytecode_int_bits = int.
:- mode bytecode_int_bits = out is det.

bytecode_int_bits = bits_per_byte * bytecode_int_bytes.

:- func bytecode_int_bytes = int.
:- mode bytecode_int_bytes = out is det.

bytecode_int_bytes = 8.

:- func bits_per_byte = int.
:- mode bits_per_byte = out is det.

bits_per_byte = 8.

:- pred output_padding_zeros(pred(int, T, T), int, T, T).
:- mode output_padding_zeros(pred(in, in, out) is det, in, in, out) is det.
:- mode output_padding_zeros(pred(in, di, uo) is det, in, di, uo) is det.

output_padding_zeros(Writer, NumBytes) -->
	( { NumBytes > 0 } ->
		call(Writer, 0),
		{ NumBytes1 is NumBytes - 1 },
		output_padding_zeros(Writer, NumBytes1)
	;
		[]
	).

:- pred output_int_bytes(pred(int, T, T), int, int, T, T).
:- mode output_int_bytes(pred(in, in, out) is det, in, in, in, out) is det.
:- mode output_int_bytes(pred(in, di, uo) is det, in, in, di, uo) is det.

output_int_bytes(Writer, ByteNum, IntVal) -->
	( { ByteNum >= 0 } ->
		{ BitShifts is ByteNum * bits_per_byte },
		{ Byte is (IntVal >> BitShifts) mod (1 << bits_per_byte) },
		{ ByteNum1 is ByteNum - 1 },
		call(Writer, Byte),
		output_int_bytes(Writer, ByteNum1, IntVal)
	;
		[]
	).

output_float(Val) -->
	{ float_to_float64_bytes(Val, B0, B1, B2, B3, B4, B5, B6, B7) },
	output_byte(B0),
	output_byte(B1),
	output_byte(B2),
	output_byte(B3),
	output_byte(B4),
	output_byte(B5),
	output_byte(B6),
	output_byte(B7).

float_to_byte_list(Val, [B0, B1, B2, B3, B4, B5, B6, B7]) :-
	float_to_float64_bytes(Val, B0, B1, B2, B3, B4, B5, B6, B7).

/*
** Convert a `float' to the representation used in the bytecode.
** That is, a sequence of eight bytes.
*/
:- pred float_to_float64_bytes(float::in, 
		int::out, int::out, int::out, int::out, 
		int::out, int::out, int::out, int::out) is det.
:- pragma c_code(
	float_to_float64_bytes(FloatVal::in, B0::out, B1::out, B2::out, B3::out,
		B4::out, B5::out, B6::out, B7::out),
	will_not_call_mercury,
	"

	{
		MR_Float64	float64;
		unsigned char	*raw_mem_p;

		float64 = (MR_Float64) FloatVal;
		raw_mem_p = (unsigned char*) &float64;

		#if defined(MR_BIG_ENDIAN)
			B0 = raw_mem_p[0];
			B1 = raw_mem_p[1];
			B2 = raw_mem_p[2];
			B3 = raw_mem_p[3];
			B4 = raw_mem_p[4];
			B5 = raw_mem_p[5];
			B6 = raw_mem_p[6];
			B7 = raw_mem_p[7];
		#elif defined(MR_LITTLE_ENDIAN)
			B7 = raw_mem_p[0];
			B6 = raw_mem_p[1];
			B5 = raw_mem_p[2];
			B4 = raw_mem_p[3];
			B3 = raw_mem_p[4];
			B2 = raw_mem_p[5];
			B1 = raw_mem_p[6];
			B0 = raw_mem_p[7];
		#else
			#error	""Weird-endian architecture""
		#endif
	}
	
	"
).

%---------------------------------------------------------------------------%

