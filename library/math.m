%---------------------------------------------------------------------------%
% Copyright (C) 1995-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: math.m
% Main author: bromage
% Stability: high
%
% Higher mathematical operations.  (The basics are in float.m.)
%
% By default, domain errors are currently handled by a program abort.
% This is because Mercury originally did not have exceptions built in.
%
% For better performance, it is possible to disable the Mercury domain
% checking by compiling with `--intermodule-optimization' and the C macro
% symbol `ML_OMIT_MATH_DOMAIN_CHECKS' defined, e.g. by using
% `MCFLAGS=--intermodule-optimization' and
% `MGNUCFLAGS=-DML_OMIT_MATH_DOMAIN_CHECKS' in your Mmakefile,
% or by compiling with the command
% `mmc --intermodule-optimization --cflags -DML_OMIT_MATH_DOMAIN_CHECKS'.
%
% For maximum performance, all Mercury domain checking can be disabled by
% recompiling this module using `MGNUCFLAGS=-DML_OMIT_MATH_DOMAIN_CHECKS'
% or `mmc --cflags -DML_OMIT_MATH_DOMAIN_CHECKS' as above. You can
% either recompile the entire library, or just copy `math.m' to your
% application's source directory and link with it directly instead of as
% part of the library.
%
% Note that the above performance improvements are semantically safe,
% since the C math library and/or floating point hardware perform these
% checks for you.  The benefit of having the Mercury library perform the
% checks instead is that Mercury will tell you in which function or
% predicate the error occurred, as well as giving you a stack trace if
% that is enabled; with the checks disabled you only have the information
% that the floating-point exception signal handler gives you.
%
%---------------------------------------------------------------------------%

:- module math.
:- interface.

%---------------------------------------------------------------------------%
% Mathematical constants

	% Pythagoras' number
:- func math__pi = float.
:- mode math__pi = out is det.

	% Base of natural logarithms
:- func math__e = float.
:- mode math__e = out is det.

%---------------------------------------------------------------------------%
% "Next integer" operations

	% math__ceiling(X) = Ceil is true if Ceil is the smallest integer
	% not less than X.
:- func math__ceiling(float) = float.
:- mode math__ceiling(in) = out is det.

	% math__floor(X) = Floor is true if Floor is the largest integer
	% not greater than X.
:- func math__floor(float) = float.
:- mode math__floor(in) = out is det.

	% math__round(X) = Round is true if Round is the integer
	% closest to X.  If X has a fractional value of 0.5, it
	% is rounded up.
:- func math__round(float) = float.
:- mode math__round(in) = out is det.

	% math__truncate(X) = Trunc is true if Trunc is the integer
	% closest to X such that |Trunc| =< |X|.
:- func math__truncate(float) = float.
:- mode math__truncate(in) = out is det.

%---------------------------------------------------------------------------%
% Polynomial roots

	% math__sqrt(X) = Sqrt is true if Sqrt is the positive square
	% root of X.
	%
	% Domain restriction: X >= 0
:- func math__sqrt(float) = float.
:- mode math__sqrt(in) = out is det.

:- type math__quadratic_roots
	--->	no_roots
	;	one_root(float)
	;	two_roots(float, float).

	% math__solve_quadratic(A, B, C) = Roots is true if Roots are
	% the solutions to the equation Ax^2 + Bx + C.
	%
	% Domain restriction: A \= 0
:- func math__solve_quadratic(float, float, float) = quadratic_roots.
:- mode math__solve_quadratic(in, in, in) = out is det.

%---------------------------------------------------------------------------%
% Power/logarithm operations

	% math__pow(X, Y) = Res is true if Res is X raised to the
	% power of Y.
	%
	% Domain restriction: X >= 0 and (X = 0 implies Y > 0)
:- func math__pow(float, float) = float.
:- mode math__pow(in, in) = out is det.

	% math__exp(X) = Exp is true if Exp is X raised to the
	% power of e.
:- func math__exp(float) = float.
:- mode math__exp(in) = out is det.

	% math__ln(X) = Log is true if Log is the natural logarithm
	% of X.
	%
	% Domain restriction: X > 0
:- func math__ln(float) = float.
:- mode math__ln(in) = out is det.

	% math__log10(X) = Log is true if Log is the logarithm to
	% base 10 of X.
	%
	% Domain restriction: X > 0
:- func math__log10(float) = float.
:- mode math__log10(in) = out is det.

	% math__log2(X) = Log is true if Log is the logarithm to
	% base 2 of X.
	%
	% Domain restriction: X > 0
:- func math__log2(float) = float.
:- mode math__log2(in) = out is det.

	% math__log(B, X) = Log is true if Log is the logarithm to
	% base B of X.
	%
	% Domain restriction: X > 0 and B > 0 and B \= 1
:- func math__log(float, float) = float.
:- mode math__log(in, in) = out is det.

%---------------------------------------------------------------------------%
% Trigonometric operations

	% math__sin(X) = Sin is true if Sin is the sine of X.
:- func math__sin(float) = float.
:- mode math__sin(in) = out is det.

	% math__cos(X) = Cos is true if Cos is the cosine of X.
:- func math__cos(float) = float.
:- mode math__cos(in) = out is det.

	% math__tan(X) = Tan is true if Tan is the tangent of X.
:- func math__tan(float) = float.
:- mode math__tan(in) = out is det.

	% math__asin(X) = ASin is true if ASin is the inverse
	% sine of X, where ASin is in the range [-pi/2,pi/2].
	%
	% Domain restriction: X must be in the range [-1,1]
:- func math__asin(float) = float.
:- mode math__asin(in) = out is det.

	% math__acos(X) = ACos is true if ACos is the inverse
	% cosine of X, where ACos is in the range [0, pi].
	%
	% Domain restriction: X must be in the range [-1,1]
:- func math__acos(float) = float.
:- mode math__acos(in) = out is det.

	% math__atan(X) = ATan is true if ATan is the inverse
	% tangent of X, where ATan is in the range [-pi/2,pi/2].
:- func math__atan(float) = float.
:- mode math__atan(in) = out is det.

	% math__atan2(Y, X) = ATan is true if ATan is the inverse
	% tangent of Y/X, where ATan is in the range [-pi,pi].
:- func math__atan2(float, float) = float.
:- mode math__atan2(in, in) = out is det.

%---------------------------------------------------------------------------%
% Hyperbolic functions

	% math__sinh(X) = Sinh is true if Sinh is the hyperbolic
	% sine of X.
:- func math__sinh(float) = float.
:- mode math__sinh(in) = out is det.

	% math__cosh(X) = Cosh is true if Cosh is the hyperbolic
	% cosine of X.
:- func math__cosh(float) = float.
:- mode math__cosh(in) = out is det.

	% math__tanh(X) = Tanh is true if Tanh is the hyperbolic
	% tangent of X.
:- func math__tanh(float) = float.
:- mode math__tanh(in) = out is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.
:- import_module float.

% These operations are mostly implemented using the C interface.

:- pragma c_header_code("

	#include <math.h>

	/*
	** Mathematical constants.
	**
	** The maximum number of significant decimal digits which
	** can be packed into an IEEE-754 extended precision
	** floating point number is 18.  Therefore 20 significant
	** decimal digits for these constants should be plenty.
	*/

	#define	ML_FLOAT_E		2.7182818284590452354
	#define	ML_FLOAT_PI		3.1415926535897932384
	#define	ML_FLOAT_LN2		0.69314718055994530941

	void ML_math_domain_error(const char *where);

"). % end pragma c_header_code

:- pragma c_code("

	#include ""mercury_trace_base.h""
	#include <stdio.h>

	/*
	** Handle domain errors.
	*/
	void
	ML_math_domain_error(const char *where)
	{
		fflush(stdout);
		fprintf(stderr,
			""Software error: Domain error in call to `%s'\\n"",
			where);
		MR_trace_report(stderr);
	#ifndef MR_HIGHLEVEL_CODE
		MR_dump_stack(MR_succip, MR_sp, MR_curfr, FALSE);
	#endif
		exit(1);
	}

"). % end pragma c_code

%
% Mathematical constants from math.m
%
	% Pythagoras' number
:- pragma c_code(math__pi = (Pi::out), [will_not_call_mercury, thread_safe],"
	Pi = ML_FLOAT_PI;
").

	% Base of natural logarithms
:- pragma c_code(math__e = (E::out), [will_not_call_mercury, thread_safe],"
	E = ML_FLOAT_E;
").

%
% math__ceiling(X) = Ceil is true if Ceil is the smallest integer
% not less than X.
%
:- pragma c_code(math__ceiling(Num::in) = (Ceil::out),
		[will_not_call_mercury, thread_safe],"
	Ceil = ceil(Num);
").

%
% math__floor(X) = Floor is true if Floor is the largest integer
% not greater than X.
%
:- pragma c_code(math__floor(Num::in) = (Floor::out),
		[will_not_call_mercury, thread_safe],"
	Floor = floor(Num);
").

%
% math__round(X) = Round is true if Round is the integer
% closest to X.  If X has a fractional component of 0.5,
% it is rounded up.
%
:- pragma c_code(math__round(Num::in) = (Rounded::out),
		[will_not_call_mercury, thread_safe],"
	Rounded = floor(Num+0.5);
").

%
% math__truncate(X) = Trunc is true if Trunc is the integer
% closest to X such that |Trunc| =< |X|.
%
:- pragma c_code(math__truncate(X::in) = (Trunc::out),
		[will_not_call_mercury, thread_safe],"
	if (X < 0.0) {
		Trunc = ceil(X);
	} else {
		Trunc = floor(X);
	}
").

%
% math__sqrt(X) = Sqrt is true if Sqrt is the positive square
% root of X.  
%
% Domain restrictions:
%		X >= 0
%
:- pragma c_code(math__sqrt(X::in) = (SquareRoot::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X < 0.0) {
		ML_math_domain_error(""math__sqrt"");
	}
#endif
	SquareRoot = sqrt(X);
").

%
% math__solve_quadratic(A, B, C) = Roots is true if Roots are
% the solutions to the equation Ax^2 + Bx + C.
%
% Domain restrictions:
% 		A \= 0
%
math__solve_quadratic(A, B, C) = Roots :-
	%
	% This implementation is designed to minimise numerical errors;
	% it is adapted from "Numerical recipes in C".
	%
	DSquared = B * B - 4.0 * A * C,
	compare(CmpD, DSquared, 0.0),
	(
		CmpD = (<),
		Roots = no_roots
	;
		CmpD = (=),
		Root = -0.5 * B / A,
		Roots = one_root(Root)
	;
		CmpD = (>),
		D = sqrt(DSquared),
		compare(CmpB, B, 0.0),
		(
			CmpB = (<),
			Q = -0.5 * (B - D),
			Root1 = Q / A,
			Root2 = C / Q
		;
			CmpB = (=),
			Root1 = -0.5 * D / A,
			Root2 = -Root1
		;
			CmpB = (>),
			Q = -0.5 * (B + D),
			Root1 = Q / A,
			Root2 = C / Q
		),
		Roots = two_roots(Root1, Root2)
	).

%
% math__pow(X, Y) = Res is true if Res is X raised to the
% power of Y.
%
% Domain restrictions:
%		X >= 0
%		X = 0 implies Y > 0
%
:- pragma c_code(math__pow(X::in, Y::in) = (Res::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X < 0.0) {
		ML_math_domain_error(""math__pow"");
	}
	if (X == 0.0) {
		if (Y <= 0.0) {
			ML_math_domain_error(""math__pow"");
		}
		Res = 0.0;
	} else {
		Res = pow(X, Y);
	}
#else
	Res = pow(X, Y);
#endif
").

%
% math__exp(X) = Exp is true if Exp is X raised to the
% power of e.
%
:- pragma c_code(math__exp(X::in) = (Exp::out),
		[will_not_call_mercury, thread_safe],"
	Exp = exp(X);
").

%
% math__ln(X) = Log is true if Log is the natural logarithm
% of X.
%
% Domain restrictions:
%		X > 0
%
:- pragma c_code(math__ln(X::in) = (Log::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X <= 0.0) {
		ML_math_domain_error(""math__ln"");
	}
#endif
	Log = log(X);
").

%
% math__log10(X) = Log is true if Log is the logarithm to
% base 10 of X.
%
% Domain restrictions:
%		X > 0
%
:- pragma c_code(math__log10(X::in) = (Log10::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X <= 0.0) {
		ML_math_domain_error(""math__log10"");
	}
#endif
	Log10 = log10(X);
").

%
% math__log2(X) = Log is true if Log is the logarithm to
% base 2 of X.
%
% Domain restrictions:
%		X > 0
%
:- pragma c_code(math__log2(X::in) = (Log2::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X <= 0.0) {
		ML_math_domain_error(""math__log2"");
	}
#endif
	Log2 = log(X) / ML_FLOAT_LN2;
").

%
% math__log(B, X) = Log is true if Log is the logarithm to
% base B of X.
%
% Domain restrictions:
%		X > 0
%		B > 0
%		B \= 1
%
:- pragma c_code(math__log(B::in, X::in) = (Log::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X <= 0.0 || B <= 0.0) {
		ML_math_domain_error(""math__log"");
	}
	if (B == 1.0) {
		ML_math_domain_error(""math__log"");
	}
#endif
	Log = log(X)/log(B);
").

%
% math__sin(X) = Sin is true if Sin is the sine of X.
%
:- pragma c_code(math__sin(X::in) = (Sin::out),
		[will_not_call_mercury, thread_safe],"
	Sin = sin(X);
").

%
% math__cos(X) = Sin is true if Cos is the cosine of X.
%
:- pragma c_code(math__cos(X::in) = (Cos::out),
		[will_not_call_mercury, thread_safe],"
	Cos = cos(X);
").

%
% math__tan(X) = Tan is true if Tan is the tangent of X.
%
:- pragma c_code(math__tan(X::in) = (Tan::out),
		[will_not_call_mercury, thread_safe],"
	Tan = tan(X);
").

%
% math__asin(X) = ASin is true if ASin is the inverse
% sine of X, where ASin is in the range [-pi/2,pi/2].
%
% Domain restrictions:
%		X must be in the range [-1,1]
%
:- pragma c_code(math__asin(X::in) = (ASin::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X < -1.0 || X > 1.0) {
		ML_math_domain_error(""math__asin"");
	}
#endif
	ASin = asin(X);
").

%
% math__acos(X) = ACos is true if ACos is the inverse
% cosine of X, where ACos is in the range [0, pi].
%
% Domain restrictions:
%		X must be in the range [-1,1]
%
:- pragma c_code(math__acos(X::in) = (ACos::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X < -1.0 || X > 1.0) {
		ML_math_domain_error(""math__acos"");
	}
#endif
	ACos = acos(X);
").

%
% math__atan(X) = ATan is true if ATan is the inverse
% tangent of X, where ATan is in the range [-pi/2,pi/2].
%
:- pragma c_code(math__atan(X::in) = (ATan::out),
		[will_not_call_mercury, thread_safe],"
	ATan = atan(X);
").

%
% math__atan2(Y, X) = ATan is true if ATan is the inverse
% tangent of Y/X, where ATan is in the range [-pi,pi].
%
:- pragma c_code(math__atan2(Y::in, X::in) = (ATan2::out), 
		[will_not_call_mercury, thread_safe], "
	ATan2 = atan2(Y, X);
").

%
% math__sinh(X) = Sinh is true if Sinh is the hyperbolic
% sine of X.
%
:- pragma c_code(math__sinh(X::in) = (Sinh::out),
		[will_not_call_mercury, thread_safe],"
	Sinh = sinh(X);
").

%
% math__cosh(X) = Cosh is true if Cosh is the hyperbolic
% cosine of X.
%
:- pragma c_code(math__cosh(X::in) = (Cosh::out),
		[will_not_call_mercury, thread_safe],"
	Cosh = cosh(X);
").

%
% math__tanh(X) = Tanh is true if Tanh is the hyperbolic
% tangent of X.
%
:- pragma c_code(math__tanh(X::in) = (Tanh::out),
		[will_not_call_mercury, thread_safe],"
	Tanh = tanh(X);
").

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

/*
** OBSOLETE OBSOLETE OBSOLETE 
**
** The predicate forms of the above functions are now deprecated.
** We provide them for compatibility reasons but they will be removed
** at a later release. Hence they are tagged `obsolete'.
*/

:- interface.

%---------------------------------------------------------------------------%
% Mathematical constants

	% Pythagoras' number
:- pred math__pi(float).
:- mode math__pi(out) is det.
:- pragma obsolete(math__pi/1).

	% Base of natural logarithms
:- pred math__e(float).
:- mode math__e(out) is det.
:- pragma obsolete(math__e/1).

%---------------------------------------------------------------------------%
% "Next integer" operations

	% math__ceiling(X, Ceil) is true if Ceil is the smallest integer
	% not less than X.
:- pred math__ceiling(float, float).
:- mode math__ceiling(in, out) is det.
:- pragma obsolete(math__ceiling/2).

	% math__floor(X, Floor) is true if Floor is the largest integer
	% not greater than X.
:- pred math__floor(float, float).
:- mode math__floor(in, out) is det.
:- pragma obsolete(math__floor/2).

	% math__round(X, Round) is true if Round is the integer
	% closest to X.  If X has a fractional value of 0.5, it
	% is rounded up.
:- pred math__round(float, float).
:- mode math__round(in, out) is det.
:- pragma obsolete(math__round/2).

	% math__truncate(X, Trunc) is true if Trunc is the integer
	% closest to X such that |Trunc| =< |X|.
:- pred math__truncate(float, float).
:- mode math__truncate(in, out) is det.
:- pragma obsolete(math__truncate/2).

%---------------------------------------------------------------------------%
% Power/logarithm operations

	% math__sqrt(X, Sqrt) is true if Sqrt is the positive square
	% root of X.
	%
	% Domain restriction: X >= 0
:- pred math__sqrt(float, float).
:- mode math__sqrt(in, out) is det.
:- pragma obsolete(math__sqrt/2).

	% math__pow(X, Y, Res) is true if Res is X raised to the
	% power of Y.
	%
	% Domain restriction: X >= 0 and (X = 0 implies Y > 0)
:- pred math__pow(float, float, float).
:- mode math__pow(in, in, out) is det.
:- pragma obsolete(math__pow/3).

	% math__exp(X, Exp) is true if Exp is X raised to the
	% power of e.
:- pred math__exp(float, float).
:- mode math__exp(in, out) is det.
:- pragma obsolete(math__exp/2).

	% math__ln(X, Log) is true if Log is the natural logarithm
	% of X.
	%
	% Domain restriction: X > 0
:- pred math__ln(float, float).
:- mode math__ln(in, out) is det.
:- pragma obsolete(math__ln/2).

	% math__log10(X, Log) is true if Log is the logarithm to
	% base 10 of X.
	%
	% Domain restriction: X > 0
:- pred math__log10(float, float).
:- mode math__log10(in, out) is det.
:- pragma obsolete(math__log10/2).

	% math__log2(X, Log) is true if Log is the logarithm to
	% base 2 of X.
	%
	% Domain restriction: X > 0
:- pred math__log2(float, float).
:- mode math__log2(in, out) is det.
:- pragma obsolete(math__log2/2).

	% math__log(B, X, Log) is true if Log is the logarithm to
	% base B of X.
	%
	% Domain restriction: X > 0 and B > 0 and B \= 1
:- pred math__log(float, float, float).
:- mode math__log(in, in, out) is det.
:- pragma obsolete(math__log/3).

%---------------------------------------------------------------------------%
% Trigonometric operations

	% math__sin(X, Sin) is true if Sin is the sine of X.
:- pred math__sin(float, float).
:- mode math__sin(in, out) is det.
:- pragma obsolete(math__sin/2).

	% math__cos(X, Cos) is true if Cos is the cosine of X.
:- pred math__cos(float, float).
:- mode math__cos(in, out) is det.
:- pragma obsolete(math__cos/2).

	% math__tan(X, Tan) is true if Tan is the tangent of X.
:- pred math__tan(float, float).
:- mode math__tan(in, out) is det.
:- pragma obsolete(math__tan/2).

	% math__asin(X, ASin) is true if ASin is the inverse
	% sine of X, where ASin is in the range [-pi/2,pi/2].
	%
	% Domain restriction: X must be in the range [-1,1]
:- pred math__asin(float, float).
:- mode math__asin(in, out) is det.
:- pragma obsolete(math__asin/2).

	% math__acos(X, ACos) is true if ACos is the inverse
	% cosine of X, where ACos is in the range [0, pi].
	%
	% Domain restriction: X must be in the range [-1,1]
:- pred math__acos(float, float).
:- mode math__acos(in, out) is det.
:- pragma obsolete(math__acos/2).

	% math__atan(X, ATan) is true if ATan is the inverse
	% tangent of X, where ATan is in the range [-pi/2,pi/2].
:- pred math__atan(float, float).
:- mode math__atan(in, out) is det.
:- pragma obsolete(math__atan/2).

	% math__atan2(Y, X, ATan) is true if ATan is the inverse
	% tangent of Y/X, where ATan is in the range [-pi,pi].
:- pred math__atan2(float, float, float).
:- mode math__atan2(in, in, out) is det.
:- pragma obsolete(math__atan2/3).

%---------------------------------------------------------------------------%
% Hyperbolic functions

	% math__sinh(X, Sinh) is true if Sinh is the hyperbolic
	% sine of X.
:- pred math__sinh(float, float).
:- mode math__sinh(in, out) is det.
:- pragma obsolete(math__sinh/2).

	% math__cosh(X, Cosh) is true if Cosh is the hyperbolic
	% cosine of X.
:- pred math__cosh(float, float).
:- mode math__cosh(in, out) is det.
:- pragma obsolete(math__cosh/2).

	% math__tanh(X, Tanh) is true if Tanh is the hyperbolic
	% tangent of X.
:- pred math__tanh(float, float).
:- mode math__tanh(in, out) is det.
:- pragma obsolete(math__tanh/2).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

% These operations are all implemented using the C interface.


%
% Mathematical constants from math.m
%
	% Pythagoras' number
:- pragma c_code(math__pi(Pi::out), [will_not_call_mercury, thread_safe],
		"Pi = ML_FLOAT_PI;").

	% Base of natural logarithms
:- pragma c_code(math__e(E::out), [will_not_call_mercury, thread_safe],
		"E = ML_FLOAT_E;").

%
% math__ceiling(X, Ceil) is true if Ceil is the smallest integer
% not less than X.
%
:- pragma c_code(math__ceiling(Num::in, Ceil::out),
		[will_not_call_mercury, thread_safe],
	"Ceil = ceil(Num);").

%
% math__floor(X, Floor) is true if Floor is the largest integer
% not greater than X.
%
:- pragma c_code(math__floor(Num::in, Floor::out),
		[will_not_call_mercury, thread_safe],
	"Floor = floor(Num);").

%
% math__round(X, Round) is true if Round is the integer
% closest to X.  If X has a fractional component of 0.5,
% it is rounded up.
%
:- pragma c_code(math__round(Num::in, Rounded::out),
		[will_not_call_mercury, thread_safe], "
	Rounded = floor(Num+0.5);
").

%
% math__truncate(X, Trunc) is true if Trunc is the integer
% closest to X such that |Trunc| =< |X|.
%
:- pragma c_code(math__truncate(X::in, Trunc::out),
		[will_not_call_mercury, thread_safe], "
	if (X < 0.0) {
		Trunc = ceil(X);
	} else {
		Trunc = floor(X);
	}
").

%
% math__sqrt(X, Sqrt) is true if Sqrt is the positive square
% root of X.  
%
% Domain restrictions:
%		X >= 0
%
:- pragma c_code(math__sqrt(X::in, SquareRoot::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X < 0.0) {
		ML_math_domain_error(""math__sqrt"");
	}
#endif
	SquareRoot = sqrt(X);
").

%
% math__pow(X, Y, Res) is true if Res is X raised to the
% power of Y.
%
% Domain restrictions:
%		X >= 0
%		X = 0 implies Y > 0
%
:- pragma c_code(math__pow(X::in, Y::in, Res::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X < 0.0) {
		ML_math_domain_error(""math__pow"");
	}
	if (X == 0.0) {
		if (Y <= 0.0) {
			ML_math_domain_error(""math__pow"");
		}
		Res = 0.0;
	} else {
		Res = pow(X, Y);
	}
#else
	Res = pow(X, Y);
#endif
").

%
% math__exp(X, Exp) is true if Exp is X raised to the
% power of e.
%
:- pragma c_code(math__exp(X::in, Exp::out),
		[will_not_call_mercury, thread_safe], "
	Exp = exp(X);
").

%
% math__ln(X, Log) is true if Log is the natural logarithm
% of X.
%
% Domain restrictions:
%		X > 0
%
:- pragma c_code(math__ln(X::in, Log::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X <= 0.0) {
		ML_math_domain_error(""math__ln"");
	}
#endif
	Log = log(X);
").

%
% math__log10(X, Log) is true if Log is the logarithm to
% base 10 of X.
%
% Domain restrictions:
%		X > 0
%
:- pragma c_code(math__log10(X::in, Log10::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X <= 0.0) {
		ML_math_domain_error(""math__log10"");
	}
#endif
	Log10 = log10(X);
").

%
% math__log2(X, Log) is true if Log is the logarithm to
% base 2 of X.
%
% Domain restrictions:
%		X > 0
%
:- pragma c_code(math__log2(X::in, Log2::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X <= 0.0) {
		ML_math_domain_error(""math__log2"");
	}
#endif
	Log2 = log(X) / ML_FLOAT_LN2;
").

%
% math__log(B, X, Log) is true if Log is the logarithm to
% base B of X.
%
% Domain restrictions:
%		X > 0
%		B > 0
%		B \= 1
%
:- pragma c_code(math__log(B::in, X::in, Log::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X <= 0.0 || B <= 0.0) {
		ML_math_domain_error(""math__log"");
	}
	if (B == 1.0) {
		ML_math_domain_error(""math__log"");
	}
#endif
	Log = log(X)/log(B);
").

%
% math__sin(X, Sin) is true if Sin is the sine of X.
%
:- pragma c_code(math__sin(X::in, Sin::out),
		[will_not_call_mercury, thread_safe], "
	Sin = sin(X);
").

%
% math__cos(X, Cos) is true if Cos is the cosine of X.
%
:- pragma c_code(math__cos(X::in, Cos::out),
		[will_not_call_mercury, thread_safe], "
	Cos = cos(X);
").

%
% math__tan(X, Tan) is true if Tan is the tangent of X.
%
:- pragma c_code(math__tan(X::in, Tan::out),
		[will_not_call_mercury, thread_safe], "
	Tan = tan(X);
").

%
% math__asin(X, ASin) is true if ASin is the inverse
% sine of X, where ASin is in the range [-pi/2,pi/2].
%
% Domain restrictions:
%		X must be in the range [-1,1]
%
:- pragma c_code(math__asin(X::in, ASin::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X < -1.0 || X > 1.0) {
		ML_math_domain_error(""math__asin"");
	}
#endif
	ASin = asin(X);
").

%
% math__acos(X, ACos) is true if ACos is the inverse
% cosine of X, where ACos is in the range [0, pi].
%
% Domain restrictions:
%		X must be in the range [-1,1]
%
:- pragma c_code(math__acos(X::in, ACos::out),
		[will_not_call_mercury, thread_safe], "
#ifndef ML_OMIT_MATH_DOMAIN_CHECKS
	if (X < -1.0 || X > 1.0) {
		ML_math_domain_error(""math__acos"");
	}
#endif
	ACos = asin(X);
").

%
% math__atan(X, ATan) is true if ATan is the inverse
% tangent of X, where ATan is in the range [-pi/2,pi/2].
%
:- pragma c_code(math__atan(X::in, ATan::out),
		[will_not_call_mercury, thread_safe], "
	ATan = atan(X);
").

%
% math__atan2(Y, X, ATan) is true if ATan is the inverse
% tangent of Y/X, where ATan is in the range [-pi,pi].
%
:- pragma c_code(math__atan2(Y::in, X::in, ATan2::out),
		[will_not_call_mercury, thread_safe], "
	ATan2 = atan2(Y, X);
").

%
% math__sinh(X, Sinh) is true if Sinh is the hyperbolic
% sine of X.
%
:- pragma c_code(math__sinh(X::in, Sinh::out),
		[will_not_call_mercury, thread_safe], "
	Sinh = sinh(X);
").

%
% math__cosh(X, Cosh) is true if Cosh is the hyperbolic
% cosine of X.
%
:- pragma c_code(math__cosh(X::in, Cosh::out),
		[will_not_call_mercury, thread_safe], "
	Cosh = cosh(X);
").

%
% math__tanh(X, Tanh) is true if Tanh is the hyperbolic
% tangent of X.
%
:- pragma c_code(math__tanh(X::in, Tanh::out),
		[will_not_call_mercury, thread_safe], "
	Tanh = tanh(X);
").

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
