%-----------------------------------------------------------------------------%
% Copyright (C) 2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
% File: enum.m.
% Author: stayl.
% Stability: very low.
%
% This module provides the typeclass `enum', which describes
% types which can be converted to and from integers without loss
% of information.
%
% The interface of this module is likely to change.
% At the moment it is probably best to only use the `enum'
% type class for types to be stored in `sparse_bitset's.
%
%-----------------------------------------------------------------------------%

:- module enum.

:- interface.

	% For all instances the following must hold:
	%	all [X, Int] (X = from_int(to_int(X)))
:- typeclass enum(T) where [
	func to_int(T) = int,
	func from_int(int) = T is semidet
].

%-----------------------------------------------------------------------------%
