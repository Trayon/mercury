/*
** Copyright (C) 1997-2001 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_conf_param.h:
**	Defines various configuration parameters. 
**
**	Configuration parameters fall into three groups.
**	They can be set automatically by autoconf.
**	They can be passed on the command line (e.g. the mgnuc
**	script sets some options based on the grade).
**	Or their values can be implied by the settings of other parameters.
**
**	The ones defined in mercury_conf.h are determined by autoconf.
**	The remainder are documented and/or defined by this file,
**	#included by mercury_conf.h.
*/

/*
** IMPORTANT NOTE:
** This file must not contain any #include statements,
** and may not define any global variables,
** for reasons explained in mercury_imp.h.
** This file should contain _only_ configuration macros.
*/

#ifndef MERCURY_CONF_PARAM_H
#define MERCURY_CONF_PARAM_H

/*---------------------------------------------------------------------------*/
/*
** Documentation for configuration parameters which can be set on the
** command line via `-D'.
*/

/*
** Code generation options:
**
** MR_HIGHLEVEL_CODE
** MR_HIGHLEVEL_DATA
** MR_USE_GCC_NESTED_FUNCTIONS
** USE_GCC_GLOBAL_REGISTERS
** USE_GCC_NONLOCAL_GOTOS
** USE_ASM_LABELS
** CONSERVATIVE_GC
** NATIVE_GC		[not yet working]
** NO_TYPE_LAYOUT
** BOXED_FLOAT
** MR_USE_TRAIL
** MR_RESERVE_TAG
** MR_USE_MINIMAL_MODEL
**	See the documentation for
**		--high-level-code
**		--high-level-data
**		--gcc-nested-functions
**		--gcc-global-registers
**		--gcc-non-local-gotos
**		--gcc-asm-labels
**		--gc conservative
**		--gc accurate		[not yet working]
**		--no-type-layout
**		--unboxed-float
**		--use-trail
**		--reserve-tag
**		--use-minimal-model
**	(respectively) in the mmc help message or the Mercury User's Guide.
**
** USE_SINGLE_PREC_FLOAT:
**	Use C's `float' rather than C's `double' for the
**	Mercury floating point type (`MR_Float').
**
** MR_USE_REGPARM:
**	For the MLDS back-end (i.e. MR_HIGHLEVEL_CODE),
**	on x86, use a different (more efficient) calling convention.
**	This requires the use of a very recent version of gcc --
**	more recent that gcc 2.95.2.
**	For details, see the definition of the MR_CALL macro in
**	runtime/mercury_std.h.
**
** MR_AVOID_MACROS:
**	For the MLDS back-end (i.e. MR_HIGHLEVEL_CODE),
**	use inline functions rather than macros for a few builtins.
**
** PARALLEL
**	Enable support for parallelism [not yet working].
**
** MR_NO_BACKWARDS_COMPAT
**	Disable backwards compatibility with C code using obsolete low-level
**	constructs, e.g. referring to variables and macros without their MR_
**	prefixes.
**
** MR_EXTRA_BACKWARDS_COMPAT
**	Add extra backwards compatibility with C code using obsolete low-level
**	constructs, e.g. referring to variables and macros without their MR_
**	prefixes.
*/

/*
** Runtime checking options:
**
** MR_CHECK_FOR_OVERFLOW
**	(Implied by MR_LOWLEVEL_DEBUG.)
**	Check for overflow of the various memory
**	areas, e.g. heap, det stack, nondet stack,
**	before every access that might result in overflow. 
**	Causes the generated code to become bigger and less efficient.
**	Slows down compilation.
**
**	Normally MR_CHECK_FOR_OVERFLOW is not set, since
**	we trap overflows using mprotect().
*/

/*
** Debugging options:
**
** MR_STACK_TRACE
**	Require the inclusion of the layout information needed by error/1
**	and the debugger to print stack traces. This effect is achieved by
**	including MR_STACK_TRACE in the mangled grade (see mercury_grade.h).
**
** MR_REQUIRE_TRACING
**	Require that all Mercury procedures linked in should be compiled
**	with at least interface tracing.  This effect is achieved
**	by including MR_REQUIRE_TRACING in the mangled grade
**	(see mercury_grade.h).
**	Note that MR_REQUIRE_TRACING is talking about execution tracing,
**	not stack tracing; these are two independently configurable features.
**
** MR_LOWLEVEL_DEBUG
**	Enables various low-level debugging stuff,
**	that was in the distant past used to debug
**	the low-level code generation.
**	Causes the generated code to become VERY big and VERY inefficient.
**	Slows down compilation a LOT.
**
** MR_DEBUG_DD_BACK_END
**	Enables low-level debugging messages on the operation of the
**	declarative debugging back end.
**
** MR_DEBUG_GOTOS
**	(Implied by MR_LOWLEVEL_DEBUG.)
**	Enables low-level debugging of gotos.
**	Causes the generated code to become bigger and less efficient.
**	Slows down compilation.
**
** MR_DEBUG_AGC_SCHEDULING
**	Display debugging information while scheduling accurate garbage
**	collection.
**
** MR_DEBUG_AGC_COLLECTION
**	Display debugging information while collecting garbage using the
**	accurate garbage collector.
**
** MR_DEBUG_AGC_FORWARDING
**	Display debugging information when leaving or finding forwarding
**	pointers during accurate garbage collection.
**
** MR_DEBUG_AGC_PRINT_VARS
**	Display the values of live variables during accurate garbage
**	collection.
**
** MR_DEBUG_AGC_SMALL_HEAP
**	Use a small heap to trigger garbage collection more often.
**
** MR_DEBUG_AGC_ALL
** 	Turn on all debugging information for accurate garbage
** 	collection.  (Equivalent to all MR_DEBUG_AGC_* macros above).
**
** MR_TABLE_DEBUG
** 	Enables low-level debugging messages from the tabling system.
**
** MR_DEBUG_JMPBUFS
** 	Enables low-level debugging messages from MR_call_engine and the
** 	code handling exceptions.
*/

#if MR_DEBUG_AGC_ALL
  #define MR_DEBUG_AGC_SCHEDULING
  #define MR_DEBUG_AGC_COLLECTION
  #define MR_DEBUG_AGC_FORWARDING
  #define MR_DEBUG_AGC_PRINT_VARS
  #define MR_DEBUG_AGC_SMALL_HEAP
#endif

/*
** MR_LABEL_STRUCTS_INCLUDE_NUMBER
**	Include a label number in each label layout structure.
*/

/*
** Profiling options:
**
** MEASURE_REGISTER_USAGE
** Enable this if you want to measure the number of times
** each register is used.  (Note that the measurement includes
** uses which occur inside debugging routines, so to get an accurate
** count you should not also enable low-level debugging.)
**
** MR_MPROF_PROFILE_CALLS
** Enables call count profiling for mprof.
**
** MR_MPROF_PROFILE_TIME
** Enables time profiling for mprof.
**
** MR_MPROF_PROFILE_MEMORY
** Enables profiling of memory usage for mprof.
**
** MR_DEEP_PROFILING
** Enables deep profiling.
**
** MR_DEEP_PROFILING_PERF_TEST
** Allows the selective performance testing of various aspects of deep
** profiling. For implementors only.
**
** MR_USE_ACTIVATION_COUNTS
** Selects the activation counter approach to deep profiling over the
** save/restore approach (the two approaches are documented in the deep
** profiling paper). For implementors only.
*/

/*
** Experimental options:
**
** MR_TRACE_HISTOGRAM
** Enable this if you want to count the number of execution tracing events
** at various call depths.
**
** MR_TYPE_CTOR_STATS
** If you want to keep statistics on the number of times the generic unify,
** index and compare functions are invoked with various kinds of type
** constructors, then set this macro to a string giving the name of the file
** to which the statistics should be appended when the program exits.
**
** MR_TABLE_STATISTICS
** Enable this if you want to gather statistics about the operation of the
** tabling system. The results are reported via io__report_tabling_stats.
*/

/*---------------------------------------------------------------------------*/
/*
** Settings of configuration parameters which can be passed on
** the command line, but which are also implied by other parameters.
*/

/*
** MR_HIGHLEVEL_CODE implies BOXED_FLOAT,
** since unboxed float is currently not yet implemented for the MLDS back-end.
** XXX we really ought to fix that...
*/
#ifdef MR_HIGHLEVEL_CODE
  #define BOXED_FLOAT 1
#endif

/* MR_LOWLEVEL_DEBUG implies MR_DEBUG_GOTOS and MR_CHECK_FOR_OVERFLOW */
#ifdef MR_LOWLEVEL_DEBUG
  #define MR_DEBUG_GOTOS
  #define MR_CHECK_FOR_OVERFLOW
#endif

/*
** MR_DEEP_PROFILING_PORT_COUNTS.
** Enables deep profiling of port counts.
**
** MR_DEEP_PROFILING_TIMING.
** Enables deep profiling of time.
**
** MR_DEEP_PROFILING_MEMORY.
** Enables deep profiling of memory usage.
*/

#ifdef	MR_DEEP_PROFILING
  /* this is the default set of measurements in deep profiling grades */
  #define MR_DEEP_PROFILING_PORT_COUNTS
  #ifndef MR_DEEP_PROFILING_PERF_TEST
    #define MR_DEEP_PROFILING_TIMING
    #define MR_DEEP_PROFILING_MEMORY
  #endif
#else
  #undef  MR_DEEP_PROFILING_PORT_COUNTS
  #undef  MR_DEEP_PROFILING_TIMING
  #undef  MR_DEEP_PROFILING_MEMORY
#endif

/*---------------------------------------------------------------------------*/
/*
** Configuration parameters whose values are determined by the settings
** of other configuration parameters.  These parameters should not be
** set on the command line.
**
** You must make sure that you don't test the value of any of these parameters
** before its conditional definition.
*/

/*
** Static code addresses are available unless using gcc non-local gotos,
** without assembler labels.
*/

#ifdef MR_STATIC_CODE_ADDRESSES
  #error "MR_STATIC_CODE_ADDRESSES should not be defined on the command line"
#endif
#if !defined(USE_GCC_NONLOCAL_GOTOS) || defined(USE_ASM_LABELS)
  #define MR_STATIC_CODE_ADDRESSES
#endif

/* XXX document MR_BYTECODE_CALLABLE */

/*
** MR_INSERT_LABELS     -- labels need to be inserted into the label table. 
**			   (this also means the initialization code needs
**			   to be run some time before the first use of the
**			   label table).
**
** Note that for the MLDS back-end, the calls to MR_init_entry()
** that insert the function addresses in the label table are only
** output if the right compiler options are enabled.  So if you change
** the condition of this `#ifdef', and you want your changes to apply
** to the MLDS back-end too, you may also need to change the
** `need_to_init_entries' predicate in compiler/mlds_to_c.m.
*/

#ifdef MR_INSERT_LABELS
  #error "MR_INSERT_LABELS should not be defined on the command line"
#endif
#if defined(MR_STACK_TRACE) || defined(NATIVE_GC) || defined(MR_DEBUG_GOTOS) \
	|| defined(MR_BYTECODE_CALLABLE)
  #define MR_INSERT_LABELS
#endif

/*
** MR_INSERT_ENTRY_LABEL_NAMES -- the entry label table should contain
**				  the names of labels as well as their
**				  addresses and layouts (label names are
**				  quite big, so prefer not to include them
**				  unless they are necessary).
*/

#ifdef MR_INSERT_ENTRY_LABEL_NAMES
  #error "MR_INSERT_ENTRY_LABEL_NAMES should not be defined on the command line"
#endif
#if defined(MR_MPROF_PROFILE_CALLS) || defined(MR_DEBUG_GOTOS) \
		|| defined(MR_DEBUG_AGC_SCHEDULING)
  #define MR_INSERT_ENTRY_LABEL_NAMES
#endif

/*
** MR_INSERT_INTERNAL_LABEL_NAMES -- the internal label table should contain
**				     the names of labels as well as their
**				     addresses and layouts (label names are
**				     quite big, so prefer not to include them
**				     unless they are necessary).
*/

#ifdef MR_INSERT_INTERNAL_LABEL_NAMES
  #error "MR_INSERT_INTERNAL_LABEL_NAMES should not be defined on the command line"
#endif
#if defined(MR_DEBUG_GOTOS) || defined(MR_DEBUG_AGC_SCHEDULING)
  #define MR_INSERT_INTERNAL_LABEL_NAMES
#endif

/*
** MR_NEED_INITIALIZATION_AT_START -- the module specific initialization code
**				      must be run before any Mercury code
**				      is run.
**
** You need to run initialization code for grades without static
** code addresses, for profiling, and any time you need to insert
** labels into the label table.
*/

#ifdef MR_NEED_INITIALIZATION_AT_START
  #error "MR_NEED_INITIALIZATION_AT_START should not be defined on the command line"
#endif
#if !defined(MR_STATIC_CODE_ADDRESSES) || defined(MR_MPROF_PROFILE_CALLS) \
	|| defined(MR_MPROF_PROFILE_TIME) || defined(DEBUG_LABELS)
  #define MR_NEED_INITIALIZATION_AT_START
#endif

/*
** MR_MAY_NEED_INITIALIZATION -- the module specific initialization code
**				 may be needed, either at start or later.
**
** You need to run initialization code for grades without static
** code addresses, for profiling, and any time you need to insert
** labels into the label table.
*/

#ifdef MR_MAY_NEED_INITIALIZATION
  #error "MR_MAY_NEED_INITIALIZATION should not be defined on the command line"
#endif
#if defined(MR_NEED_INITIALIZATION_AT_START) || defined(MR_INSERT_LABELS)
  #define MR_MAY_NEED_INITIALIZATION
#endif

/*
** MR_USE_DECLARATIVE_DEBUGGER -- include support for declarative
**				  debugging in the internal debugger.
**
** MR_USE_DECL_STACK_SLOT      -- reserve a stack slot for use by the
**				  declarative debugger.  Requires programs
**				  to be compiled with the flag `--trace-decl'.
*/

#if defined(CONSERVATIVE_GC) && !defined(MR_DISABLE_DECLARATIVE_DEBUGGER)
  #define MR_USE_DECLARATIVE_DEBUGGER
#endif

/*---------------------------------------------------------------------------*/

/*
** Memory protection and signal handling.
*/

#if defined(HAVE_SIGINFO) && defined(PC_ACCESS)
  #define MR_CAN_GET_PC_AT_SIGNAL
#endif

/*
** MR_CHECK_OVERFLOW_VIA_MPROTECT  --	Can check for overflow of various
**					memory zones using mprotect() like
**					functionality.
*/
#if (defined(HAVE_MPROTECT) && defined(HAVE_SIGINFO)) || defined(_WIN32)
  #define MR_CHECK_OVERFLOW_VIA_MPROTECT
#endif

/*
** MR_PROTECTPAGE   -- 	MR_protect_pages() can be defined to provide the same
**			functionality as the system call mprotect().
*/
#if defined(HAVE_MPROTECT) || defined(_WIN32)
  #define MR_PROTECTPAGE
#endif

/*
** MR_MSVC_STRUCTURED_EXCEPTIONS
** 	Use Microsoft Visual C structured exceptions for signal handling.
*/
#if defined(_MSC_VER)
  #define MR_MSVC_STRUCTURED_EXCEPTIONS
#endif

/*---------------------------------------------------------------------------*/

/*
** Win32 API specific.
*/

/*
** MR_WIN32 -- The Win32 API is available.
**
** MR_WIN32_GETSYSTEMINFO -- Is GetSystemInfo() available?
**
** MR_WIN32_VIRTUAL_ALLOC -- Is VirtualAlloc() available?
*/
#if _WIN32
  #define MR_WIN32
  #define MR_WIN32_GETSYSTEMINFO
  #define MR_WIN32_VIRTUAL_ALLOC
  #define MR_WIN32_GETPROCESSTIMES
#endif

/*---------------------------------------------------------------------------*/

#endif /* MERCURY_CONF_PARAM_H */
