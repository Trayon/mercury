%-----------------------------------------------------------------------------%
% Copyright (C) 1994-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% File: options.m.
% Main author: fjh.

% This defines the stuff necessary so that getopt.m
% can parse the command-line options.

% IMPORTANT NOTE: any changes to the options should be
% reflected in both the help message produced below,
% and in the Mercury User's Guide (../doc/user_guide.texi).

%-----------------------------------------------------------------------------%

:- module options.
:- interface.
:- import_module char, io, getopt.

:- pred short_option(char::in, option::out) is semidet.
:- pred long_option(string::in, option::out) is semidet.
:- pred option_defaults(option::out, option_data::out) is nondet.

:- pred special_handler(option::in, special_data::in, option_table::in,
	maybe_option_table::out) is semidet.
%	special_handler(Option, ValueForThatOption, OptionTableIn,
%			MaybeOptionTableOut).
%	This predicate is invoked whenever getopt finds an option
%	(long or short) designated as special, with special_data holding
%	the argument of the option (if any). The predicate can change the
%	option table in arbitrary ways in the course of handling the option,
%	or it can return an error message.
%	The canonical examples of special options are -O options in compilers,
%	which set many other options at once.
%	The MaybeOptionTableOut may either be ok(OptionTableOut), or it may
%	be error(ErrorString).

:- pred options_help(io__state::di, io__state::uo) is det.

:- type option_table == option_table(option).
:- type maybe_option_table == maybe_option_table(option).

:- type option	
	% Warning options
		--->	inhibit_warnings
		;	halt_at_warn
		;	halt_at_syntax_errors
		;	warn_singleton_vars
		;	warn_overlapping_scopes
		;	warn_det_decls_too_lax
		;	warn_nothing_exported
		;	warn_unused_args
		;	warn_interface_imports
		;	warn_missing_opt_files
		;	warn_missing_trans_opt_deps
		;	warn_non_stratification
		;	warn_simple_code
		;	warn_duplicate_calls
		;	warn_missing_module_name
		;	warn_wrong_module_name
	% Verbosity options
		;	verbose
		;	very_verbose
		;	verbose_errors
		;	statistics
		;	debug_types
		;	debug_modes
		;	debug_det
		;	debug_opt
		;	debug_vn	% vn = value numbering
		;	debug_pd	% pd = partial deduction/deforestation
	% Output options
		;	make_short_interface
		;	make_interface
		;	make_private_interface
		;	make_optimization_interface
		;	make_transitive_opt_interface
		;	generate_dependencies
		;	generate_module_order
		;	convert_to_mercury
		;	convert_to_goedel
		;	typecheck_only
		;	errorcheck_only
		;	compile_to_c
		;	compile_only
		;	output_grade_string
	% Auxiliary output options
		;	assume_gmake
		;	trace
		;	generate_bytecode
		;	generate_prolog
		;	prolog_dialect
		;	line_numbers
		;	auto_comments
		;	show_dependency_graph
		;	dump_hlds
		;	dump_hlds_alias
		;	dump_hlds_options
	% Language semantics options
		;	reorder_conj
		;	reorder_disj
		;	fully_strict
		;	strict_sequential
		;	infer_types
		;	infer_modes
		;	infer_det
		;	infer_all
		;	type_inference_iteration_limit
		;	mode_inference_iteration_limit
	% Compilation Model options
		;	grade
		;	gcc_non_local_gotos
		;	gcc_global_registers
		;	asm_labels
		;	gc
		;	parallel
		;	profiling		% profile_time + profile_calls
		;	time_profiling		% profile_time + profile_calls
		;	memory_profiling	% profime_mem + profile_calls
		;	profile_calls
		;	profile_time
		;	profile_memory
		;	debug
		;	stack_trace
		;	require_tracing
		;	use_trail
		;	pic_reg
		;	tags
		;	num_tag_bits
		;	bits_per_word
		;	bytes_per_word
		;	conf_low_tag_bits
				% The undocumented conf_low_tag_bits option
				% is used by the `mmc' script to pass the
				% default value for num_tag_bits
				% assuming --tags low.
				% The reason that `mmc' doesn't just
				% pass a default value for --num-tag-bits
				% is that we want to be able to give an
				% error message if the user specifies
				% `--tags high' and doesn't specify
				% `--num-tag-bits'.
		;	args
		;	highlevel_c
		;	unboxed_float
		;	sync_term_size % in words
		;	type_layout
	% Options for internal use only
	% (the values of these options are implied by the
	% settings of other options)
				% Stack layout information required to do
				% a stack trace.
		;	basic_stack_layout
				% Stack layout information required to do
				% accurate GC.
		;	agc_stack_layout
				% Stack layout information required to do
				% procedure identification.
		;	procid_stack_layout
				% Stack layout information required to do
				% execution tracing.
		;	trace_stack_layout
				% Use an alternate calculation of liveness
				% where typeinfos are live for any live data
				% the includes that type variable.
		;	typeinfo_liveness
	% Code generation options
		;	low_level_debug
		;	trad_passes
		;	polymorphism
		;	reclaim_heap_on_failure
		;	reclaim_heap_on_semidet_failure
		;	reclaim_heap_on_nondet_failure
		;	lazy_code
		;	have_delay_slot
		;	num_real_r_regs
		;	num_real_f_regs
		;	num_real_r_temps
		;	num_real_f_temps
		;	cc
		;	cflags
		;	cflags_for_regs
		;	cflags_for_gotos
		;	c_debug
		;	c_include_directory
		;	aditi
		;	fact_table_max_array_size
				% maximum number of elements in a single 
				% fact table data array

		;	fact_table_hash_percent_full
				% how full the fact table hash tables should
				% be allowed to get, given as an integer
				% percentage.

	% Optimization Options
		;	opt_level
		;	opt_space	% default is to optimize time
		;	intermodule_optimization
		;	use_opt_files
		;	use_trans_opt_files
		;	transitive_optimization
		;	split_c_files
	%	- HLDS
		;	inlining
		;	inline_simple
		;	inline_single_use
		;	inline_compound_threshold
		;	inline_simple_threshold
		;	inline_vars_threshold
		;	intermod_inline_simple_threshold
		;	common_struct
		;	common_goal
		;	constraint_propagation
		;	optimize_unused_args
		;	intermod_unused_args
		;	optimize_higher_order
		;	type_specialization
		;	higher_order_size_limit
		;	optimize_constructor_last_call
		;	optimize_duplicate_calls
		;	constant_propagation
		;	excess_assign
		;	optimize_saved_vars
		;	follow_code
		;	prev_code
		;	optimize_dead_procs
		;	deforestation
		;	deforestation_depth_limit
		;	deforestation_cost_factor
		;	deforestation_vars_threshold
		;	termination
		;	vanessa_termination
		;	benoy_widening
		;	check_termination
		;	verbose_check_termination
		;	termination_single_args
		;	termination_norm
		;	termination_error_limit
		;	termination_path_limit
	%	- HLDS->LLDS
		;	smart_indexing
		;	  dense_switch_req_density
		;	  lookup_switch_req_density
		;	  dense_switch_size
		;	  lookup_switch_size
		;	  string_switch_size
		;	  tag_switch_size
		;	  try_switch_size
		;	  binary_switch_size
		;	static_ground_terms
		;	middle_rec
		;	simple_neg
		;	follow_vars
		;	allow_hijacks
	%	- LLDS
		;	optimize
		;	optimize_peep
		;	optimize_jumps
		;	optimize_fulljumps
		;	optimize_labels
		;	optimize_dups
%%% unused:	;	optimize_copyprop
		;	optimize_value_number
		;	optimize_frames
		;	optimize_delay_slot
		;	optimize_repeat
		;	optimize_vnrepeat
		;	pred_value_number
		;	vn_fudge
	%	- C
		;	use_macro_for_redo_fail
		;	emit_c_loops
		;	procs_per_c_function
		;	everything_in_one_c_function
		;	c_optimize
		;	inline_alloc
	% Link options
		;	output_file_name
		;	link_flags
		;	link_library_directories
		;	link_libraries
		;	link_objects
	% Miscellaneous Options
		;	heap_space
		;	search_directories
		;	intermod_directories
		;	use_search_directories_for_intermod
		;	use_subdirs
		;	help.

:- implementation.

:- import_module string, bool, int, map, std_util, assoc_list, require, list.
:- import_module handle_options.

:- type option_category
	--->	warning_option
	;	verbosity_option
	;	output_option
	;	aux_output_option
	;	language_semantics_option
	;	compilation_model_option
	;	code_gen_option
	;	special_optimization_option
	;	optimization_option
	;	link_option
	;	miscellaneous_option.

option_defaults(Option, Default) :-
	option_defaults_2(_Category, OptionsList),
	list__member(Option - Default, OptionsList).

:- pred option_defaults_2(option_category, list(pair(option, option_data))).
:- mode option_defaults_2(in, out) is det.
:- mode option_defaults_2(out, out) is multidet.

option_defaults_2(warning_option, [
		% Warning Options
	inhibit_warnings	-	bool_special,
	halt_at_warn		-	bool(no),
	halt_at_syntax_errors	-	bool(no),
	%
	% IMPORTANT NOTE:
	% if you add any new warning options, or if you change
	% the default for an existing warning option to `yes',
	% then you will need to modify the handling of inhibit_warnings
	%
	warn_singleton_vars	-	bool(yes),
	warn_overlapping_scopes	-	bool(yes),
	warn_det_decls_too_lax	-	bool(yes),
	warn_nothing_exported	-	bool(yes),
	warn_unused_args	-	bool(no),
	warn_interface_imports	-	bool(yes),
	warn_non_stratification -	bool(no),
	warn_missing_opt_files  -	bool(yes),
	warn_missing_trans_opt_deps  -	bool(no),
	warn_simple_code	-	bool(yes),
	warn_duplicate_calls	-	bool(no),
	warn_missing_module_name -	bool(yes),
	warn_wrong_module_name -	bool(yes)
]).
option_defaults_2(verbosity_option, [
		% Verbosity Options
	verbose			-	bool(no),
	very_verbose		-	bool(no),
	verbose_errors		-	bool(no),
	statistics		-	bool(no),
	debug_types		- 	bool(no),
	debug_modes		- 	bool(no),
	debug_det		- 	bool(no),
	debug_opt		- 	bool(no),
	debug_vn		- 	int(0),
	debug_pd		-	bool(no)
]).
option_defaults_2(output_option, [
		% Output Options (mutually exclusive)
	generate_dependencies	-	bool(no),
	generate_module_order 	-	bool(no),
	make_short_interface	-	bool(no),
	make_interface		-	bool(no),
	make_private_interface	-	bool(no),
	make_optimization_interface -	bool(no),
	make_transitive_opt_interface -	bool(no),
	convert_to_mercury 	-	bool(no),
	convert_to_goedel 	-	bool(no),
	typecheck_only		-	bool(no),
	errorcheck_only		-	bool(no),
	compile_to_c		-	bool(no),
	compile_only		-	bool(no),
	output_grade_string	-	bool(no)
]).
option_defaults_2(aux_output_option, [
		% Auxiliary Output Options
	assume_gmake		-	bool(yes),
	trace			-	string("default"),
	generate_bytecode	-	bool(no),
	generate_prolog		-	bool(no),
	prolog_dialect		-	string("default"),
	line_numbers		-	bool(no),
	auto_comments		-	bool(no),
	show_dependency_graph	-	bool(no),
	dump_hlds		-	accumulating([]),
	dump_hlds_alias		-	string(""),
	dump_hlds_options	-	string("")
]).
option_defaults_2(language_semantics_option, [
	strict_sequential	-	special,
	reorder_conj		-	bool(yes),
	reorder_disj		-	bool(yes),
	fully_strict		-	bool(yes),
	infer_types		-	bool(no),
	infer_modes		-	bool(no),
	infer_det		-	bool(yes),
	infer_all		-	bool_special,
	type_inference_iteration_limit	-	int(60),
	mode_inference_iteration_limit	-	int(30)
]).
option_defaults_2(compilation_model_option, [
		% Compilation model options (ones that affect binary
		% compatibility).
	grade			-	string_special,
					% the `mmc' script will pass the
					% default grade determined
					% at configuration time
	gcc_non_local_gotos	-	bool(yes),
	gcc_global_registers	-	bool(yes),
	asm_labels		-	bool(yes),
	gc			-	string("conservative"),
	parallel		-	bool(no),
	profiling		-	bool_special,
	time_profiling		-	special,
	memory_profiling	-	special,
	profile_calls		-	bool(no),
	profile_time		-	bool(no),
	profile_memory		-	bool(no),
	debug			-	bool_special,
	require_tracing		-	bool(no),
	stack_trace		-	bool(no),
	use_trail		-	bool(no),
	pic_reg			-	bool(no),
	tags			-	string("low"),
	num_tag_bits		-	int(-1),
					% -1 is a special value which means
					% use the value of conf_low_tag_bits
					% instead
	bits_per_word		-	int(32),
					% A good default for the current
					% generation of architectures.
	bytes_per_word		-	int(4),
					% A good default for the current
					% generation of architectures.
	conf_low_tag_bits	-	int(2),
					% the `mmc' script will override the
					% above default with a value determined
					% at configuration time
	args			-	string("compact"),
	sync_term_size		-	int(8),
					% 8 is the size on linux (at the time
					% of writing) - will usually be over-
					% ridden by a value from configure.
	type_layout		-	bool(yes),
	basic_stack_layout	-	bool(no),
	agc_stack_layout	-	bool(no),
	procid_stack_layout	-	bool(no),
	trace_stack_layout	-	bool(no),
	typeinfo_liveness	-	bool(no),
	highlevel_c		-	bool(no),
	unboxed_float		-	bool(no)
]).
option_defaults_2(code_gen_option, [
		% Code Generation Options
	low_level_debug		-	bool(no),
	trad_passes		-	bool(yes),
	polymorphism		-	bool(yes),
	lazy_code		-	bool(yes),
	reclaim_heap_on_failure	-	bool_special,
	reclaim_heap_on_semidet_failure	-	bool(yes),
	reclaim_heap_on_nondet_failure	-	bool(yes),
	have_delay_slot		-	bool(no),
					% the `mmc' script may override the
					% above default if configure says
					% the machine has branch delay slots
	num_real_r_regs		-	int(5),
	num_real_f_regs		-	int(0),
	num_real_r_temps	-	int(5),
	num_real_f_temps	-	int(0),
					% the `mmc' script will override the
					% above defaults with values determined
					% at configuration time
	cc			-	string("gcc"),
					% the `mmc' script will override the
					% above default with a value determined
					% at configuration time
	cflags			-	accumulating([]),
	cflags_for_regs		-	string(""),
	cflags_for_gotos	-	string(""),
					% the `mmc' script will override the
					% above two defaults with values
					% determined at configuration time
	c_debug			-	bool(no),
	c_include_directory	-	string(""),
					% the `mmc' script will override the
					% above default with a value determined
					% at configuration time
	aditi			-	bool(no),
	fact_table_max_array_size -	int(1024),
	fact_table_hash_percent_full - 	int(90)
]).
option_defaults_2(special_optimization_option, [
		% Special optimization options.
		% These ones are not affected by `-O<n>'.
	opt_level		-	int_special,
	opt_space		-	special,
	intermodule_optimization -	bool(no),
	use_opt_files		-	bool(no),
	use_trans_opt_files	-	bool(no),
	transitive_optimization -	bool(no),
	check_termination	-	bool(no),
	verbose_check_termination -	bool(no),
	termination		-	bool(no),
	vanessa_termination	-	bool(yes),
	benoy_widening		-	int(2),
	termination_single_args	-	int(0),
	termination_norm	-	string("total"),
	termination_error_limit	-	int(3),
	termination_path_limit	-	int(256),
	split_c_files		-	bool(no)
]).
option_defaults_2(optimization_option, [
		% Optimization options
		%
		% IMPORTANT: the default here should be all optimizations OFF.
		% Optimizations should be enabled by the appropriate
		% optimization level in the opt_level table.
		%
% HLDS
	inlining		-	bool_special,
	inline_simple		-	bool(no),
	inline_single_use	-	bool(no),
	inline_compound_threshold -	int(0),
	inline_simple_threshold	-	int(5),	% has no effect until
						% --inline-simple is enabled
	inline_vars_threshold	-	int(100),
	intermod_inline_simple_threshold -	% has no effect until
					int(5),	% --intermodule-optimization
	common_struct		-	bool(no),
	common_goal		-	bool(yes),
		% common_goal is not really an optimization, since
		% it affects the semantics
	constraint_propagation	-	bool(no),
	optimize_duplicate_calls -	bool(no),
	constant_propagation	-	bool(no),
	excess_assign		-	bool(no),
	optimize_saved_vars	-	bool(no),
	prev_code		-	bool(no),
	follow_code		-	bool(no),
	optimize_unused_args	-	bool(no),
	intermod_unused_args	-	bool(no),
	optimize_higher_order	-	bool(no),
	type_specialization	-	bool(no),
	higher_order_size_limit	-	int(20),
	optimize_constructor_last_call -	bool(no),
	optimize_dead_procs	-	bool(no),
	deforestation		-	bool(no),
	deforestation_depth_limit	-	int(4),
	deforestation_cost_factor	-	int(1000),
	deforestation_vars_threshold 	-	int(200),

% HLDS -> LLDS
	smart_indexing		-	bool(no),
	dense_switch_req_density -	int(25),
		% Minimum density before using a dense switch
	lookup_switch_req_density -	int(25),
		% Minimum density before using a lookup switch
	dense_switch_size	-	int(4),
	lookup_switch_size	-	int(4),
	string_switch_size	-	int(8),
	tag_switch_size		-	int(3),
	try_switch_size		-	int(3),
	binary_switch_size	-	int(4),
	static_ground_terms	-	bool(no),
	middle_rec		-	bool(no),
	simple_neg		-	bool(no),
	follow_vars		-	bool(no),
	allow_hijacks		-	bool(yes),

% LLDS
	optimize		-	bool(no),
	optimize_peep		-	bool(no),
	optimize_jumps		-	bool(no),
	optimize_fulljumps	-	bool(no),
	optimize_labels		-	bool(no),
	optimize_dups		-	bool(no),
%%%	optimize_copyprop	-	bool(no),
	optimize_value_number	-	bool(no),
	optimize_frames		-	bool(no),
	optimize_delay_slot	-	bool(no),
	optimize_repeat		-	int(0),
	optimize_vnrepeat	-	int(1),		% ineffective unless
							% value_number is set
	pred_value_number	-	bool(no),
	vn_fudge		-	int(1000),

% LLDS -> C
	use_macro_for_redo_fail	-	bool(no),
	emit_c_loops		-	bool(no),
	procs_per_c_function	-	int(1),
	everything_in_one_c_function -	special,
	c_optimize		-	bool(no),
	inline_alloc		-	bool(no)
]).
option_defaults_2(link_option, [
		% Link Options
	output_file_name	-	string(""),
					% if the output_file_name is an empty
					% string, we use the name of the first
					% module on the command line
	link_flags		-	accumulating([]),
	link_library_directories -	accumulating([]),
	link_libraries		-	accumulating([]),
	link_objects		-	accumulating([])
]).
option_defaults_2(miscellaneous_option, [
		% Miscellaneous Options
	heap_space		-	int(0),
	search_directories 	-	accumulating(["."]),
	intermod_directories	-	accumulating([]),
	use_search_directories_for_intermod
				-	bool(yes),
	use_subdirs		-	bool(no),
	help 			-	bool(no)
]).

	% please keep this in alphabetic order
short_option('c', 			compile_only).
short_option('C', 			compile_to_c).
short_option('d', 			dump_hlds).
short_option('D', 			dump_hlds_alias).
short_option('e', 			errorcheck_only).
short_option('E', 			verbose_errors).
short_option('G', 			convert_to_goedel).
short_option('h', 			help).
short_option('i', 			make_interface).
short_option('I', 			search_directories).
short_option('l', 			link_libraries).
short_option('L', 			link_library_directories).
short_option('M', 			generate_dependencies).
short_option('N', 			debug_modes).
short_option('n', 			line_numbers).
short_option('o', 			output_file_name).
short_option('O', 			opt_level).
short_option('p', 			profiling).
short_option('P', 			convert_to_mercury).
short_option('s', 			grade).
short_option('S', 			statistics).
short_option('T', 			debug_types).
short_option('t', 			typecheck_only).
short_option('v', 			verbose).
short_option('V', 			very_verbose).
short_option('w', 			inhibit_warnings).
short_option('?', 			help).

% warning options
long_option("inhibit-warnings",		inhibit_warnings).
long_option("halt-at-warn",		halt_at_warn).
long_option("halt-at-syntax-errors",	halt_at_syntax_errors).
long_option("warn-singleton-variables",	warn_singleton_vars).
long_option("warn-overlapping-scopes",	warn_overlapping_scopes).
long_option("warn-det-decls-too-lax",	warn_det_decls_too_lax).
long_option("warn-nothing-exported",	warn_nothing_exported).
long_option("warn-unused-args",		warn_unused_args).
long_option("warn-interface-imports",	warn_interface_imports).
long_option("warn-non-stratification",	warn_non_stratification).
long_option("warn-missing-opt-files",	warn_missing_opt_files).
long_option("warn-missing-trans-opt-deps",	warn_missing_trans_opt_deps).
long_option("warn-simple-code",		warn_simple_code).
long_option("warn-duplicate-calls",	warn_duplicate_calls).
long_option("warn-missing-module-name",	warn_missing_module_name).
long_option("warn-wrong-module-name",	warn_wrong_module_name).

% verbosity options
long_option("verbose",			verbose).
long_option("very-verbose",		very_verbose).
long_option("verbose-error-messages",	verbose_errors).
long_option("statistics",		statistics).
long_option("debug-types",		debug_types).
long_option("debug-modes",		debug_modes).
long_option("debug-determinism",	debug_det).
long_option("debug-det",		debug_det).
long_option("debug-opt",		debug_opt).
long_option("debug-vn",			debug_vn).
long_option("debug-pd",			debug_pd).

% output options (mutually exclusive)
long_option("generate-dependencies",	generate_dependencies).
long_option("generate-module-order",	generate_module_order).
long_option("make-short-interface",	make_short_interface).
long_option("make-short-int",		make_short_interface).
long_option("make-interface",		make_interface).
long_option("make-int",			make_interface).
long_option("make-private-interface",	make_private_interface).
long_option("make-priv-int",		make_private_interface).
long_option("make-optimization-interface",
					make_optimization_interface).
long_option("make-optimisation-interface",
					make_optimization_interface).
long_option("make-opt-int",		make_optimization_interface).
long_option("make-transitive-optimization-interface",
					make_transitive_opt_interface).
long_option("make-transitive-optimisation-interface",
					make_transitive_opt_interface).
long_option("make-trans-opt", 		make_transitive_opt_interface).
long_option("convert-to-mercury", 	convert_to_mercury).
long_option("convert-to-Mercury", 	convert_to_mercury). 
long_option("pretty-print", 		convert_to_mercury).
long_option("convert-to-goedel", 	convert_to_goedel).
long_option("convert-to-Goedel", 	convert_to_goedel).
long_option("typecheck-only",		typecheck_only).
long_option("errorcheck-only",		errorcheck_only).
long_option("compile-to-c",		compile_to_c).
long_option("compile-to-C",		compile_to_c).
long_option("compile-only",		compile_only).
long_option("output-grade-string",	output_grade_string).

% aux output options
long_option("assume-gmake",		assume_gmake).
long_option("trace",			trace).
long_option("generate-bytecode",	generate_bytecode).
long_option("generate-prolog",		generate_prolog).
long_option("generate-Prolog",		generate_prolog).
long_option("prolog-dialect",		prolog_dialect).
long_option("line-numbers",		line_numbers).
long_option("auto-comments",		auto_comments).
long_option("show-dependency-graph",	show_dependency_graph).
long_option("dump-hlds",		dump_hlds).
long_option("dump-hlds-alias",		dump_hlds_alias).
long_option("dump-hlds-options",	dump_hlds_options).

% language semantics options
long_option("reorder-conj",		reorder_conj).
long_option("reorder-disj",		reorder_disj).
long_option("fully-strict",		fully_strict).
long_option("strict-sequential",	strict_sequential).
long_option("infer-all",		infer_all).
long_option("infer-types",		infer_types).
long_option("infer-modes",		infer_modes).
long_option("infer-determinism",	infer_det).
long_option("infer-det",		infer_det).
long_option("type-inference-iteration-limit",
					type_inference_iteration_limit).
long_option("mode-inference-iteration-limit",
					mode_inference_iteration_limit).

% compilation model options
long_option("grade",			grade).
long_option("gcc-non-local-gotos",	gcc_non_local_gotos).
long_option("gcc-global-registers",	gcc_global_registers).
long_option("asm-labels",		asm_labels).
long_option("gc",			gc).
long_option("garbage-collection",	gc).
long_option("parallel",			parallel).
long_option("profiling",		profiling).
long_option("time-profiling",		time_profiling).
long_option("memory-profiling",		memory_profiling).
long_option("profile-calls",		profile_calls).
long_option("profile-time",		profile_time).
long_option("profile-memory",		profile_memory).
long_option("debug",			debug).
% The following options are not allowed, because they're
% not very useful and would probably only confuse people.
% long_option("stack-trace",		stack_trace).
% long_option("require-tracing",	require_tracing).
long_option("use-trail",		use_trail).
long_option("pic-reg",			pic_reg).
long_option("tags",			tags).
long_option("num-tag-bits",		num_tag_bits).
long_option("bits-per-word",		bits_per_word).
long_option("bytes-per-word",		bytes_per_word).
long_option("conf-low-tag-bits",	conf_low_tag_bits).
long_option("args",			args).
long_option("arg-convention",		args).
long_option("type-layout",		type_layout).
long_option("agc-stack-layout",		agc_stack_layout).
long_option("basic-stack-layout",	basic_stack_layout).
long_option("procid-stack-layout",	procid_stack_layout).
long_option("trace-stack-layout",	trace_stack_layout).
long_option("typeinfo-liveness",	typeinfo_liveness).
long_option("highlevel-C",		highlevel_c).
long_option("highlevel-c",		highlevel_c).
long_option("high-level-C",		highlevel_c).
long_option("high-level-c",		highlevel_c).
long_option("unboxed-float",		unboxed_float).

% code generation options
long_option("low-level-debug",		low_level_debug).
long_option("polymorphism",		polymorphism).
long_option("trad-passes",		trad_passes).
long_option("lazy-code",		lazy_code).
long_option("reclaim-heap-on-failure",	reclaim_heap_on_failure).
long_option("reclaim-heap-on-semidet-failure",
					reclaim_heap_on_semidet_failure).
long_option("reclaim-heap-on-nondet-failure",
					reclaim_heap_on_nondet_failure).
long_option("branch-delay-slot",	have_delay_slot).
long_option("have-delay-slot",		have_delay_slot).
long_option("num-real-r-regs",		num_real_r_regs).
long_option("num-real-f-regs",		num_real_f_regs).
long_option("num-real-r-temps",		num_real_r_temps).
long_option("num-real-f-temps",		num_real_f_temps).
long_option("num-real-temps",		num_real_r_temps).	% obsolete
long_option("cc",			cc).
long_option("cflags",			cflags).
long_option("cflags-for-regs",		cflags_for_regs).
long_option("cflags-for-gotos",		cflags_for_gotos).
long_option("c-debug",			c_debug).
long_option("c-include-directory",	c_include_directory).
long_option("fact-table-max-array-size",fact_table_max_array_size).
long_option("fact-table-hash-percent-full",
					fact_table_hash_percent_full).

% optimization options

long_option("opt-level",		opt_level).
long_option("optimization-level",	opt_level).
long_option("optimisation-level",	opt_level).
long_option("opt-space",		opt_space).
long_option("optimize-space",		opt_space).
long_option("optimise-space",		opt_space).
long_option("intermodule-optimization", intermodule_optimization).
long_option("intermodule-optimisation", intermodule_optimization).
long_option("use-opt-files",		use_opt_files).
long_option("use-trans-opt-files",	use_trans_opt_files).
long_option("transitive-intermodule-optimization", 
					transitive_optimization).
long_option("transitive-intermodule-optimisation", 
					transitive_optimization).
long_option("trans-intermod-opt", 	transitive_optimization).

% HLDS->HLDS optimizations
long_option("inlining", 		inlining).
long_option("inline-simple",		inline_simple).
long_option("inline-single-use",	inline_single_use).
long_option("inline-compound-threshold",	inline_compound_threshold).
long_option("inline-simple-threshold",		inline_simple_threshold).
long_option("intermod-inline-simple-threshold",
					intermod_inline_simple_threshold).
long_option("inline-vars-threshold",		inline_vars_threshold).
long_option("common-struct",		common_struct).
long_option("common-goal",		common_goal).
long_option("excess-assign",		excess_assign).
long_option("optimize-duplicate-calls", optimize_duplicate_calls).
long_option("optimise-duplicate-calls", optimize_duplicate_calls).
long_option("optimise-constant-propagation", constant_propagation).
long_option("optimize-constant-propagation", constant_propagation).
long_option("optimize-saved-vars",	optimize_saved_vars).
long_option("optimise-saved-vars",	optimize_saved_vars).
long_option("prev-code",		prev_code).
long_option("follow-code",		follow_code).
long_option("constraint-propagation",	constraint_propagation).
long_option("optimize-unused-args",	optimize_unused_args).
long_option("optimise-unused-args",	optimize_unused_args).
long_option("intermod-unused-args",	intermod_unused_args).
long_option("optimize-higher-order",	optimize_higher_order).
long_option("optimise-higher-order",	optimize_higher_order).
long_option("type-specialization",	type_specialization).
long_option("type-specialisation",	type_specialization).
long_option("higher-order-size-limit",	higher_order_size_limit).
long_option("optimise-constructor-last-call",	optimize_constructor_last_call).
long_option("optimize-constructor-last-call",	optimize_constructor_last_call).
long_option("optimize-dead-procs",	optimize_dead_procs).
long_option("optimise-dead-procs",	optimize_dead_procs).
long_option("deforestation",		deforestation).
long_option("deforestation-depth-limit",	deforestation_depth_limit).
long_option("deforestation-cost-factor",	deforestation_cost_factor).
long_option("deforestation-vars-threshold",	deforestation_vars_threshold).
long_option("enable-termination",	termination).
long_option("enable-term",		termination).
long_option("vanessa-termination",	vanessa_termination).
long_option("benoy-widening",		benoy_widening).
long_option("check-termination",	check_termination).
long_option("check-term",		check_termination).
long_option("chk-term",			check_termination).
long_option("verbose-check-termination",verbose_check_termination).
long_option("verb-check-term",		verbose_check_termination).
long_option("verb-chk-term",		verbose_check_termination).
long_option("termination-single-argument-analysis",
					termination_single_args).
long_option("term-single-arg", 		termination_single_args).
long_option("termination-norm",		termination_norm).
long_option("term-norm",		termination_norm).
long_option("termination-error-limit",	termination_error_limit).
long_option("term-err-limit",		termination_error_limit).
long_option("termination-path-limit",	termination_path_limit).
long_option("term-path-limit",		termination_path_limit).

% HLDS->LLDS optimizations
long_option("smart-indexing",		smart_indexing).
long_option("dense-switch-req-density",	dense_switch_req_density).
long_option("lookup-switch-req-density",lookup_switch_req_density).
long_option("dense-switch-size",	dense_switch_size).
long_option("lookup-switch-size",	lookup_switch_size).
long_option("string-switch-size",	string_switch_size).
long_option("tag-switch-size",		tag_switch_size).
long_option("try-switch-size",		try_switch_size).
long_option("binary-switch-size",	binary_switch_size).
long_option("static-ground-terms",	static_ground_terms).
long_option("middle-rec",		middle_rec).
long_option("simple-neg",		simple_neg).
long_option("follow-vars",		follow_vars).
long_option("allow-hijacks",		allow_hijacks).

% LLDS optimizations
long_option("llds-optimize",		optimize).
long_option("llds-optimise",		optimize).
long_option("optimize-peep",		optimize_peep).
long_option("optimise-peep",		optimize_peep).
long_option("optimize-jumps",		optimize_jumps).
long_option("optimise-jumps",		optimize_jumps).
long_option("optimize-fulljumps",	optimize_fulljumps).
long_option("optimise-fulljumps",	optimize_fulljumps).
long_option("optimize-labels",		optimize_labels).
long_option("optimise-labels",		optimize_labels).
long_option("optimize-dups",		optimize_dups).
long_option("optimise-dups",		optimize_dups).
%%% long_option("optimize-copyprop",	optimize_copyprop).
%%% long_option("optimise-copyprop",	optimize_copyprop).
long_option("optimize-value-number",	optimize_value_number).
long_option("optimise-value-number",	optimize_value_number).
long_option("optimize-frames",		optimize_frames).
long_option("optimise-frames",		optimize_frames).
long_option("optimize-delay-slot",	optimize_delay_slot).
long_option("optimise-delay-slot",	optimize_delay_slot).
long_option("optimize-repeat",		optimize_repeat).
long_option("optimise-repeat",		optimize_repeat).
long_option("optimize-vnrepeat",	optimize_vnrepeat).
long_option("optimise-vnrepeat",	optimize_vnrepeat).
long_option("pred-value-number",	pred_value_number).
long_option("vn-fudge",			vn_fudge).

% LLDS->C optimizations
long_option("use-macro-for-redo-fail",	use_macro_for_redo_fail).
long_option("emit-c-loops",		emit_c_loops).
long_option("procs-per-c-function",	procs_per_c_function).
long_option("procs-per-C-function",	procs_per_c_function).
long_option("everything-in-one-c-function",	everything_in_one_c_function).
long_option("everything-in-one-C-function",	everything_in_one_c_function).
long_option("split-c-files",		split_c_files).
long_option("split-C-files",		split_c_files).
long_option("c-optimise",		c_optimize).
long_option("c-optimize",		c_optimize).
long_option("inline-alloc",		inline_alloc).

% link options
long_option("output-file",		output_file_name).
long_option("link-flags",		link_flags).
long_option("library-directory",	link_library_directories).
long_option("library",			link_libraries).
long_option("link-object",		link_objects).

% misc options
long_option("help",			help).
long_option("heap-space",		heap_space).
long_option("search-directory",		search_directories).
long_option("intermod-directory",	intermod_directories).
long_option("use-search-directories-for-intermod",
					use_search_directories_for_intermod).	
long_option("use-subdirs",		use_subdirs).	

%-----------------------------------------------------------------------------%

special_handler(grade, string(Grade), OptionTable0, Result) :-
	( convert_grade_option(Grade, OptionTable0, OptionTable) ->
		Result = ok(OptionTable)
	;
		string__append_list(["invalid grade `", Grade, "'"], Msg),
		Result = error(Msg)
	).
special_handler(profiling, bool(Value), OptionTable0, ok(OptionTable)) :-
	map__set(OptionTable0, profile_time, bool(Value), OptionTable1),
	map__set(OptionTable1, profile_calls, bool(Value), OptionTable2),
        map__set(OptionTable2, profile_memory, bool(no), OptionTable).
special_handler(time_profiling, none, OptionTable0, ok(OptionTable)) :-
	map__set(OptionTable0, profile_time, bool(yes), OptionTable1),
	map__set(OptionTable1, profile_calls, bool(yes), OptionTable2),
        map__set(OptionTable2, profile_memory, bool(no), OptionTable).
special_handler(memory_profiling, none, OptionTable0, ok(OptionTable)) :-
	map__set(OptionTable0, profile_time, bool(no), OptionTable1),
	map__set(OptionTable1, profile_calls, bool(yes), OptionTable2),
        map__set(OptionTable2, profile_memory, bool(yes), OptionTable).
special_handler(debug, bool(Value), OptionTable0, ok(OptionTable)) :-
	map__set(OptionTable0, stack_trace, bool(Value), OptionTable1),
	map__set(OptionTable1, require_tracing, bool(Value), OptionTable).
special_handler(inlining, bool(Value), OptionTable0, ok(OptionTable)) :-
	map__set(OptionTable0, inline_simple, bool(Value), OptionTable1),
	map__set(OptionTable1, inline_single_use, bool(Value), OptionTable2),
	(
		Value = yes,
		map__set(OptionTable2, inline_compound_threshold,
			int(10), OptionTable)
	;
		Value = no,
		map__set(OptionTable2, inline_compound_threshold,
			int(0), OptionTable)
	).
special_handler(everything_in_one_c_function, none, OptionTable0,
		ok(OptionTable)) :-
	map__set(OptionTable0, procs_per_c_function, int(0),
		OptionTable).
special_handler(reclaim_heap_on_failure, bool(Value), OptionTable0,
			ok(OptionTable)) :-
	map__set(OptionTable0, reclaim_heap_on_semidet_failure, bool(Value),
		OptionTable1),
	map__set(OptionTable1, reclaim_heap_on_nondet_failure, bool(Value),
		OptionTable).
special_handler(strict_sequential, none, OptionTable0, ok(OptionTable)) :-
	override_options([
			reorder_conj 	-	bool(no),
			reorder_disj 	-	bool(no),
			fully_strict 	-	bool(yes)
		], OptionTable0, OptionTable).
special_handler(inhibit_warnings, bool(Inhibit), OptionTable0, ok(OptionTable))
		:-
	bool__not(Inhibit, Enable),
	override_options([
			warn_singleton_vars	-	bool(Enable),
			warn_overlapping_scopes	-	bool(Enable),
			warn_det_decls_too_lax	-	bool(Enable),
			warn_nothing_exported	-	bool(Enable),
			warn_interface_imports	-	bool(Enable),
			warn_missing_opt_files	-	bool(Enable),
			warn_missing_trans_opt_deps -	bool(Enable),
			warn_simple_code	-	bool(Enable),
			warn_missing_module_name -	bool(Enable),
			warn_wrong_module_name	-	bool(Enable)
		], OptionTable0, OptionTable).
special_handler(infer_all, bool(Infer), OptionTable0, ok(OptionTable)) :-
	override_options([
			infer_types 		-	bool(Infer),
			infer_modes 		-	bool(Infer),
			infer_det	 	-	bool(Infer)
		], OptionTable0, OptionTable).
special_handler(opt_space, none, OptionTable0, ok(OptionTable)) :-
	opt_space(OptionSettingsList),
	override_options(OptionSettingsList, OptionTable0, OptionTable).
special_handler(opt_level, int(N0), OptionTable0, ok(OptionTable)) :-
	( N0 > 6 ->
		N = 6
	; N0 < -1 ->
		N = -1
	;
		N = N0
	),
	set_opt_level(N, OptionTable0, OptionTable).

:- pred set_opt_level(int, option_table, option_table).
:- mode set_opt_level(in, in, out) is det.

set_opt_level(N, OptionTable0, OptionTable) :-
	%
	% first reset all optimizations to their default
	% (the default should be all optimizations off)
	%
	option_defaults_2(optimization_option, OptimizationDefaults),
	override_options(OptimizationDefaults, OptionTable0, OptionTable1),
	%
	% next enable the optimization levels from 0 up to N.
	%
	enable_opt_levels(0, N, OptionTable1, OptionTable).

:- pred enable_opt_levels(int, int, option_table, option_table).
:- mode enable_opt_levels(in, in, in, out) is det.

enable_opt_levels(N0, N, OptionTable0, OptionTable) :-
	( N0 > N ->
		OptionTable = OptionTable0
	; opt_level(N0, OptionTable0, OptionSettingsList) ->
		override_options(OptionSettingsList, OptionTable0,
			OptionTable1),
		N1 is N0 + 1,
		enable_opt_levels(N1, N, OptionTable1, OptionTable)
	;
		error("Unknown optimization level")
	).

:- pred override_options(list(pair(option, option_data)),
	option_table, option_table).
:- mode override_options(in, in, out) is det.

override_options([], OptionTable, OptionTable).
override_options([Option - Value | Settings], OptionTable0, OptionTable) :-
	map__set(OptionTable0, Option, Value, OptionTable1),
	override_options(Settings, OptionTable1, OptionTable).

%-----------------------------------------------------------------------------%

:- pred opt_space(list(pair(option, option_data))::out) is det.

opt_space([
	optimize_dead_procs	-	bool(yes),
	optimize_labels		-	bool(yes),
	optimize_dups		-	bool(yes),
	optimize_fulljumps	-	bool(no),
	inline_alloc		-	bool(no),
	use_macro_for_redo_fail	-	bool(no)
]).

%-----------------------------------------------------------------------------%

:- pred opt_level(int::in, option_table::in,
	list(pair(option, option_data))::out) is semidet.

% Optimization level -1:
% Generate totally unoptimized code; turns off ALL optimizations that
% can be turned off, including HLDS->HLDS, HLDS->LLDS, LLDS->LLDS, LLDS->C,
% and C->object optimizations.  
% (However, there are some optimizations that can't be disabled.)

% Optimization level 0: aim to minimize overall compilation time.
% XXX I just guessed.  We should run lots of experiments.

opt_level(0, _, [
	optimize		-	bool(yes),
	optimize_repeat		-	int(1),
	optimize_peep		-	bool(yes),
	static_ground_terms	-	bool(yes),
	smart_indexing		-	bool(yes),
	optimize_jumps		-	bool(yes),
	optimize_labels		-	bool(yes),
	excess_assign		-	bool(yes)	% ???
]).

% Optimization level 1: apply optimizations which are cheap and
% have a good payoff while still keeping compilation time small

opt_level(1, OptionTable, [
	c_optimize		-	bool(yes),	% XXX we want `gcc -O1'
	optimize_frames		-	bool(yes),
	optimize_delay_slot	-	bool(DelaySlot),
	follow_vars		-	bool(yes),
	middle_rec		-	bool(yes),
	emit_c_loops		-	bool(yes)
	% dups?
]) :-
	getopt__lookup_bool_option(OptionTable, have_delay_slot, DelaySlot).

% Optimization level 2: apply optimizations which have a good
% payoff relative to their cost; but include optimizations
% which are more costly than with -O1

opt_level(2, _, [
	optimize_fulljumps	-	bool(yes),
	optimize_repeat		-	int(3),
	optimize_dups		-	bool(yes),
	optimize_dead_procs	-	bool(yes),
	follow_code		-	bool(yes),
	inline_simple		-	bool(yes),
	inline_single_use	-	bool(yes),
	inline_compound_threshold -	int(10),
	common_struct		-	bool(yes),
/****
% XXX optimize_duplicate_calls is broken --
% it doesn't take type information into account.
% See tests/hard_coded/dupcall_types_bug.m.
% We should re-enable the optimization only
% when we have fixed that bug.
	optimize_duplicate_calls -	bool(yes),
****/
	simple_neg		-	bool(yes)
]).

% Optimization level 3: apply optimizations which usually have a good
% payoff even if they increase compilation time quite a bit

opt_level(3, _, [
%%%	optimize_copyprop	-	bool(yes),
	optimize_saved_vars	-	bool(yes),
	optimize_unused_args	-	bool(yes),	
	optimize_higher_order	-	bool(yes),
	deforestation		-	bool(yes),
	constant_propagation	-	bool(yes),
	optimize_repeat		-	int(4)
]).

% Optimization level 4: apply optimizations which may have some
% payoff even if they increase compilation time quite a bit

% Currently this enables value_number
% and increases the inlining thresholds

opt_level(4, _, [
	optimize_value_number	-	bool(yes),
	inline_simple_threshold	-	int(8),
	inline_compound_threshold -	int(20)
]).

% Optimization level 5: apply optimizations which may have some
% payoff even if they increase compilation time a lot

% Currently this enables pred_value_number
% and runs a second pass of value numbering

opt_level(5, _, [
	pred_value_number	-	bool(yes),
	optimize_repeat		-	int(5),
	optimize_vnrepeat	-	int(2),
	inline_compound_threshold -	int(100)
]).

% Optimization level 6: apply optimizations which may have any
% payoff even if they increase compilation time to completely
% unreasonable levels

% Currently this sets `everything_in_one_c_function', which causes
% the compiler to put everything in the one C function and treat
% calls to predicates in the same module as local.
% We also enable inlining of GC_malloc(), redo(), and fail().

opt_level(6, _, [
	procs_per_c_function	-	int(0),	% everything in one C function
	inline_alloc		-	bool(yes),
	use_macro_for_redo_fail	-	bool(yes)
]).

%-----------------------------------------------------------------------------%

options_help -->
	io__write_string("\t-?, -h, --help\n"),
	io__write_string("\t\tPrint this usage message.\n"),
	options_help_warning,
	options_help_verbosity,
	options_help_output,
	options_help_aux_output,
	options_help_semantics,
	options_help_termination,
	options_help_compilation_model,
	options_help_code_generation,
	options_help_optimization,
	options_help_hlds_hlds_optimization,
	options_help_hlds_llds_optimization,
	options_help_llds_llds_optimization,
	options_help_output_optimization,
	options_help_object_optimization,
	options_help_link,
	options_help_misc.

:- pred options_help_warning(io__state::di, io__state::uo) is det.

options_help_warning -->
	io__write_string("\nWarning Options:\n"),
	write_tabbed_lines([
		"-w, --inhibit-warnings",
		"\tDisable all warning messages.",
		"--halt-at-warn",
		"\tThis option causes the compiler to treat all ",
		"\twarnings as if they were errors.  This means that",
		"\tif any warning is issued, the compiler will not",
		"\tgenerate code --- instead, it will return a",
		"\tnon-zero exit status.",
		"--halt-at-syntax-errors",
		"\tThis option causes the compiler to halt immediately",
		"\tafter syntax checking and not do any semantic checking",
		"\tif it finds any syntax errors in the program.",
		"--no-warn-singleton-variables",
		"\tDon't warn about variables which only occur once.",
		"--no-warn-overlapping-scopes",
		"\tDon't warn about variables which occur in overlapping scopes.",
		"--no-warn-det-decls-too-lax",
		"\tDon't warn about determinism declarations",
		"\twhich could have been stricter.",
		"--no-warn-nothing-exported",
		"\tDon't warn about modules which export nothing.",
		"--warn-unused-args",
		"\tWarn about predicate arguments which are not used.",
		"--warn-interface-imports",
		"\tWarn about modules imported in the interface, but",
		"\twhich are not used in the interface.",
		"--no-warn-missing-opt-files",
		"\tDisable warnings about `.opt' files which cannot be opened.",
		"--no-warn-missing-trans-opt-deps",
		"\tDisable warnings produced when the information required",
		"\tto allow `.trans_opt' files to be read when creating other",
		"\t`.trans_opt' files has been lost.  The information can be",
		"\trecreated by running `mmake <mainmodule>.depend'",
		"--warn-non-stratification",
		"\tWarn about possible non-stratification in the module.",
		"\tNon-stratification occurs when a predicate/function can call",
		"\titself negatively through some path along its call graph.",
		"--no-warn-simple-code",
		"\tDisable warnings about constructs which are so",
		"\tsimple that they are likely to be programming errors.",
		"--warn-duplicate-calls",
		"\tWarn about multiple calls to a predicate with the",
		"\tsame input arguments.",
		"--no-warn-missing-module-name",
		"\tDisable warnings for modules that do no start with",
		"\ta `:- module' declaration.",
		"--no-warn-wrong-module-name",
		"\tDisable warnings for modules whose `:- module'",
		"\tdeclaration does not match the module's file name."
	]).

:- pred options_help_verbosity(io__state::di, io__state::uo) is det.

options_help_verbosity -->
	io__write_string("\nVerbosity Options:\n"),
	write_tabbed_lines([
		"-v, --verbose",
		"\tOutput progress messages at each stage in the compilation.",
		"-V, --very_verbose",
		"\tOutput very verbose progress messages.",
		"-E, --verbose-error-messages",
		"\tExplain error messages.  Asks the compiler to give you a more",
		"\tdetailed explanation of any errors it finds in your program.",
		"-S, --statistics",
		"\tOutput messages about the compiler's time/space usage.",
		"\tAt the moment this option implies `--no-trad-passes', so you get",
		"\tinformation at the boundaries between phases of the compiler.",
		"-T, --debug-types",
		"\tOutput detailed debugging traces of the type checking.",
		"-N, --debug-modes",
		"\tOutput detailed debugging traces of the mode checking.",
		"--debug-det, --debug-determinism",
		"\tOutput detailed debugging traces of determinism analysis.",
		"--debug-opt",
		"\tOutput detailed debugging traces of the optimization process.",
		"--debug-vn <n>",
		"\tOutput detailed debugging traces of the value numbering",
		"\toptimization pass. The different bits in the number",
		"\targument of this option control the printing of",
		"\tdifferent types of tracing messages.",
		"--debug-pd",
		"\tOutput detailed debugging traces of the partial",
		"\tdeduction and deforestation process."
	]).

:- pred options_help_output(io__state::di, io__state::uo) is det.

options_help_output -->
	io__write_string("\nOutput Options:\n"),
	write_tabbed_lines([
		"These options are mutually exclusive.",
		"Only the first one specified will apply.",
		"If none of these options are specified, the default action",
		"is to link the named modules to produce an executable.\n",
		"-M, --generate-dependencies",
		"\tOutput `Make'-style dependencies for the module",
		"\tand all of its dependencies to `<module>.dep'.",
		"--generate-module-order",
		"\tOutput the strongly connected components of the module",
		"\tdependency graph in top-down order to `<module>.order'.",
		"\tImplies --generate-dependencies.",
		"-i, --make-int, --make-interface",
		"\tWrite the module interface to `<module>.int',",
		"\tand write the short interface to `<module>.int2'",
		"\tThis option should only be used by mmake.",
		"--make-priv-int, --make-private-interface",
		"\tWrite the private interface to `<module>.int0'.",
		"\tThis option should only be used by mmake.",
		"--make-short-int, --make-short-interface",
		"\tWrite the unqualified short interface to `<module>.int3'.",
		"\tThis option should only be used by mmake.",
		"--make-opt-int, --make-optimization-interface",
		"\tWrite inter-module optimization information to",
		"\t`<module>.opt'.",
		"\tThis option should only be used by mmake.",
		"--make-trans-opt",
		"--make-transitive-optimization-interface",
		"\tOutput transitive optimization information",
		"\tinto the `<module>.trans_opt' file.",
		"\tThis option should only be used by mmake.",
		"-G, --convert-to-goedel",
		"\tConvert to Goedel. Output to file `<module>.loc'.",
		"\tNote that some Mercury language constructs cannot",
		"\t(easily) be translated into Goedel.",
		"-P, --convert-to-mercury",
		"\tConvert to Mercury. Output to file `<module>.ugly'",
		"\tThis option acts as a Mercury ugly-printer.",
		"-t, --typecheck-only",
		"\tJust check that the code is syntactically correct and",
		"\ttype-correct. Don't check modes or determinism,",
		"\tand don't generate any code.",
		"-e, --errorcheck-only",
		"\tCheck the module for errors, but do not generate any code.",
		"-C, --compile-to-c",
		"\tGenerate C code in `<module>.c', but not object code.",
		"-c, --compile-only",
		"\tGenerate C code in `<module>.c' and object code in `<module>.o'",
		"\tbut do not attempt to link the named modules.",
		"\t--output-grade-string",
		"\tCompute the grade of the library to link with based on",
		"\tthe command line options, and print it to the standard",
		"\toutput."
	]).

:- pred options_help_aux_output(io__state::di, io__state::uo) is det.

options_help_aux_output -->
	io__write_string("\n Auxiliary Output Options:\n"),
	write_tabbed_lines([
		"--no-assume-gmake",
		"\tWhen generating `.dep' files, generate Makefile",
		"\tfragments that use only the features of standard make;",
		"\tdo not assume the availability of GNU Make extensions.",
		"--trace {minimum, interfaces, all, default}",
		"\tGenerate code that includes the specified level", 
		"\tof execution tracing.",
		"\tSee the [XXX not yet written!] chapter of the",
		"\tMercury User's Guide for details.",
		"--generate-bytecode",
		"\tOutput a bytecode form of the module for use",
		"\tby an experimental debugger.",
		"--generate-prolog",
		"\tConvert the program to Prolog. Output to file `<module>.pl'",
		"\tor `<module>.nl' (depending on the dialect).",
		"--prolog-dialect {sicstus,nu}",
		"\tTarget the named dialect if generating Prolog code.",
		"-l, --line-numbers",
		"\tOutput line numbers in the generated code.",
		"\tOnly works with the `-G' and `-P' options.",
		"--auto-comments",
		"\tOutput comments in the `<module>.c' file.",
		"\t(The code may be easier to understand if you also",
		"\tuse the `--no-llds-optimize' option.)",
		"--show-dependency-graph",
		"\tWrite out the dependency graph to `<module>.dependency_graph'.",
		"-d <n>, --dump-hlds <stage number or name>",
		"\tDump the HLDS (intermediate representation) after",
		"\tthe specified stage to `<module>.hlds_dump.<num>-<name>'.",
		"\tStage numbers range from 1-99.",
		"\tMultiple dump options accumulate.",
% This option is for developers only
%		"-D, --dump-hlds-alias <dump-alias>",
%		"\tWith `--dump-hlds', include extra detail in the dump.",
%		"\tEach dump alias is shorthand for a set of option letters.",
%		"\tThe list of aliases is in handle_options.m",
		"--dump-hlds-options <options>",
		"\tWith `--dump-hlds', include extra detail in the dump.",
		"\tEach type of detail is included in the dump if its",
		"\tcorresponding letter occurs in the option argument",
		"\t(see the Mercury User's Guide for details)."
	]).

:- pred options_help_semantics(io__state::di, io__state::uo) is det.

options_help_semantics -->
	io__write_string("\nLanguage semantics options:\n"),
	io__write_string("(See the Mercury language reference manual for detailed explanations.)\n"),
	write_tabbed_lines([
		"--no-reorder-conj",
		"\tExecute conjunctions left-to-right except where the modes imply",
		"\tthat reordering is unavoidable.",
		"--no-reorder-disj",
		"\tExecute disjunctions strictly left-to-right.",
		"--fully-strict",
		"\tDon't optimize away loops or calls to error/1.",
		"--infer-types",
		"\tIf there is no type declaration for a predicate or function,",
		"\ttry to infer the type, rather than just reporting an error.",
		"--infer-modes",
		"\tIf there is no mode declaration for a predicate,",
		"\ttry to infer the modes, rather than just reporting an error.",

		"--no-infer-det, --no-infer-determinism",
		"\tIf there is no determinism declaration for a procedure,",
		"\tdon't try to infer the determinism, just report an error.",
		"--type-inference-iteration-limit <n>",
		"\tPerform at most <n> passes of type inference (default: 60).",
		"--mode-inference-iteration-limit <n>",
		"\tPerform at most <n> passes of mode inference (default: 30)."
	]).


:- pred options_help_termination(io__state::di, io__state::uo) is det.

options_help_termination -->
	io__write_string("\nTermination Analysis Options:\n"),
	write_tabbed_lines([
		"--enable-term, --enable-termination",
		"\tAnalyse each predicate to discover if it terminates.",
		"--chk-term, --check-term, --check-termination",
		"\tEnable termination analysis, and emit warnings for some",
		"\tpredicates or functions that cannot be proved to terminate.  In",
		"\tmany cases where the compiler is unable to prove termination",
		"\tthe problem is either a lack of information about the",
		"\ttermination properties of other predicates, or because language",
		"\tconstructs (such as higher order calls) were used which could",
		"\tnot be analysed.  In these cases the compiler does not emit a",
		"\twarning of non-termination, as it is likely to be spurious.",
		"--verb-chk-term, --verb-check-term, --verbose-check-termination",
		"\tEnable termination analysis, and emit warnings for all",
		"\tpredicates or functions that cannot be proved to terminate.",
		"--term-single-arg <n>, --termination-single-argument-analysis <n>",
		"\tWhen performing termination analysis, try analyzing",
		"\trecursion on single arguments in strongly connected",
		"\tcomponents of the call graph that have up to <n> procedures.",
		"\tSetting this limit to zero disables single argument analysis.",
		"--termination-norm {simple, total, num-data-elems}",
		"\tThe norm defines how termination analysis measures the size",
		"\tof a memory cell. The `simple' norm says that size is always",
		"\tone.  The `total' norm says that it is the number of words",
		"\tin the cell.  The `num-data-elems' norm says that it is the",
		"\tnumber of words in the cell that contain something other",
		"\tthan pointers to cells of the same type.",
		"--term-err-limit <n>, --termination-error-limit <n>",
		"\tPrint at most <n> reasons for any single termination error",
		"\t(default: 3).",
		"--term-path-limit <n>, --termination-path-limit <n>",
		"\tPerform termination analysis only on predicates",
		"\twith at most <n> paths (default: 256)."
	]).


:- pred options_help_compilation_model(io__state::di, io__state::uo) is det.

options_help_compilation_model -->
	io__write_string("\nCompilation model options:\n"),
	write_tabbed_lines([
		"The following compilation options affect the generated",
		"code in such a way that the entire program must be",
		"compiled with the same setting of these options,",
		"and it must be linked to a version of the Mercury",
		"library which has been compiled with the same setting.",
		"-s <grade>, --grade <grade>",
		"\tSelect the compilation model. The <grade> should be one of",
		"\t`none', `reg', `jump', `asm_jump', `fast', `asm_fast',",
		"\tor one of those with `.gc', `.prof', `.proftime',",
		"\t`.profcalls', `.tr', `.sa', `.debug', and/or `.pic_reg'",
		"\tappended (in that order).",
		"\tDepending on your particular installation, only a subset",
		"\tof these possible grades will have been installed.",
		"\tAttempting to use a grade which has not been installed",
		"\twill result in an error at link time.",
		"--gcc-global-registers\t\t(grades: reg, fast, asm_fast)",
		"--no-gcc-global-registers\t(grades: none, jump, asm_jump)",
		"\tSpecify whether or not to use GNU C's",
		"\tglobal register variables extension.",
		"--gcc-non-local-gotos\t\t(grades: jump, fast, asm_jump, asm_fast)",
		"--no-gcc-non-local-gotos\t(grades: none, reg)",
		"\tSpecify whether or not to use GNU C's",
		"\t""labels as values"" extension.",
		"--asm-labels\t\t\t(grades: asm_jump, asm_fast)",
		"--no-asm-labels\t\t\t(grades: none, reg, jump, fast)",
		"\tSpecify whether or not to use GNU C's",
		"\tasm extensions for inline assembler labels.",
		"--gc {none, conservative, accurate}",
		"--garbage-collection {none, conservative, accurate}",
		"\t\t\t\t(`.gc' grades use `--gc conservative',",
		"\t\t\t\tother grades use `--gc none'.)",
		"\tSpecify which method of garbage collection to use",
		"\t(default: conservative).  `accurate' GC is not yet implemented.",
		"--use-trail\t\t\t(grade modifier: `.tr')",
		"\tEnable use of a trail.",
		"\tThis is necessary for interfacing with constraint solvers,",
		"\tor for backtrackable destructive update.",
		"-p, --profiling, --time-profiling",
		"\t\t\t\t(grade modifier: `.prof')",
		"\tEnable time and call profiling.  Insert profiling hooks in the",
		"\tgenerated code, and also output some profiling",
		"\tinformation (the static call graph) to the file",
		"\t`<module>.prof'.",
		"--memory-profiling\t\t(grade modifier: `.memprof')",
		"\tEnable memory and call profiling.",
/*****************
XXX The following options are not documented,
because they are currently not useful.
The idea was for you to be able to use --profile-calls
and --profile-time seperately, but that doesn't work
because compiling with --profile-time instead of
--profile-calls results in different code addresses, 
so you can't combine the data from versions of
your program compiled with different options.

		"--profile-calls\t\t(grade modifier: `.profcalls')",
		"\tSimilar to `--profiling', except that only gathers",
		"\tcall counts, not timing information.",
		"\tUseful on systems where time profiling is not supported,",
		"\tbut not as useful as `--memory-profiling'.",
		"--profile-time\t\t(grade modifier: `.proftime')",
		"\tSimilar to `--profiling', except that it only gathers",
		"\ttiming information, not call counts.",
		"--profile-memory\t\t(grade modifier: `.profmem')",
		"\tSimilar to `--memory-profiling', except that it only gathers",
		"\tmemory usage information, not call counts.",
********************/
		"--debug\t\t\t\t(grade modifier: `.debug')",
		"\tEnable Mercury-level debugging.",
		"\tSee the [XXX not yet written!] chapter of the",
		"\tMercury User's Guide for details.",
		"--pic-reg\t\t\t(grade modifier: `.pic_reg')",
		"[For Unix with intel x86 architecture only]",
		"\tSelect a register usage convention that is compatible,",
		"\twith position-independent code (gcc's `-fpic' option).",
		"\tThis is necessary when using shared libraries on Intel x86",
		"\tsystems running Unix.  On other systems it has no effect.",
		"--tags {none, low, high}\t(This option is not for general use.)",
		"\tSpecify whether to use the low bits or the high bits of ",
		"\teach word as tag bits (default: low).",
	% 	"\t\t`--tags none' implies `--num-tag-bits 0'.",
		"--num-tag-bits <n>\t\t(This option is not for general use.)",
		"\tUse <n> tag bits.",

		% The --conf-low-tag-bits option is reserved for use
		% by the `mmc' script; it is deliberately not documented.

		% The --bits-per-word option is intended for use
		% by the `mmc' script; it is deliberately not documented.

		% The --bytes-per-word option is intended for use
		% by the `mmc' script; it is deliberately not documented.

		"--branch-delay-slot\t\t(This option is not for general use.)",
		"\tAssume that branch instructions have a delay slot.",
		"--num-real-r-regs <n>\t\t(This option is not for general use.)",
		"\tAssume registers r1 up to r<n> are real general purpose",
		"\tregisters.",
		"--num-real-f-regs <n>\t\t(This option is not for general use.)",
		"\tAssume registers f1 up to f<n> are real floating point",
		"\tregisters.",
		"--num-real-r-temps <n>\t\t(This option is not for general use.)",
		"\tAssume that <n> non-float temporaries will fit into",
		"\treal machine registers.",
		"--num-real-f-temps <n>\t\t(This option is not for general use.)",
		"\tAssume that <n> float temporaries will fit into",
		"\treal machine registers.",
		"--args {simple, compact}",
		"--arg-convention {simple, compact}",
		"(This option is not for general use.)",
		"\tUse the specified argument passing convention",
		"\tin the generated low-level C code. With the `simple'",
		"\tconvention, the <n>th argument is passed in or out",
		"\tusing register r<n>. With the `compact' convention,",
		"\tthe <n>th input argument is passed using register r<n>,",
		"\tand the <n>th output argument is returned using",
		"\tregister r<n>. The compact convention generally leads to",
		"\tmore efficient code. Use of the simple convention requires the",
		"\tC code to be compiled with -UCOMPACT_ARGS.",

		"--no-type-layout",
		"(This option is not for general use.)",
		"\tDon't output base_type_layout structures or references",
		"\tto them. (The C code also needs to be compiled with",
		"\t`-DNO_TYPE_LAYOUT').",
	
		% This is a developer only option.
%		"--basic-stack-layout",
%		"(This option is not for general use.)",
%		"\tGenerate the simple stack_layout structures required",
%		"\tfor stack traces.",

		% This is a developer only option.
%		"--agc-stack-layout",
%		"(This option is not for general use.)",
%		"\tGenerate the stack_layout structures required for",
%		"\taccurate garbage collection.",
%
		% This is a developer only option.
%		"--procid-stack-layout",
%		"(This option is not for general use.)",
%		"\tGenerate the stack_layout structures required for",
%		"\tlooking up procedure identification information.",

		% This is a developer only option.
%		"--trace-stack-layout",
%		"(This option is not for general use.)",
%		"\tGenerate the stack_layout structures required for",
%		"\texecution tracing.",

		% This is a developer only option.
%		"--typeinfo-liveness",
%		"(This option is not for general use.)",
%		"\tUse an alternate technique for calculating liveness.",
%		"\tKeeps typeinfo variables around for as long as any data",
%		"\tthat has a type that contains that type variable is live",
%
		"--unboxed-float",
		"(This option is not for general use.)",
		"\tDon't box floating point numbers.",
		"\tThis assumes that a Mercury float will fit in a word.",
		"\tThe C code needs to be compiled with `-UBOXED_FLOAT'.",
		"\tIt may also need to be compiled with",
		"\t`-DUSE_SINGLE_PREC_FLOAT', if double precision",
		"\tfloats don't fit into a word."
	]).

:- pred options_help_code_generation(io__state::di, io__state::uo) is det.

options_help_code_generation -->
	io__write_string("\nCode generation options:\n"),
	write_tabbed_lines([
		"--low-level-debug",
		"\tEnables various low-level debugging stuff, that was in",
		"\tthe distant past used to debug the low-level code generation.",
		"\tYou don't want to use this option unless you are hacking",
		"\tthe Mercury compiler itself (and probably not even then).",
		"\tCauses the generated code to become VERY big and VERY",
		"\tinefficient.  Slows down compilation a LOT.",

		"--no-trad-passes",
		"\tThe default `--trad-passes' completely processes each predicate",
		"\tbefore going on to the next predicate.",
		"\tThis option tells the compiler",
		"\tto complete each phase of code generation on all predicates",
		"\tbefore going on the next phase on all predicates.",
	% 	"\t--no-polymorphism",
	% 	"\t\tDon't handle polymorphic types.",
	% 	"\t\t(Generates slightly more efficient code, but stops",
	% 	"\t\tpolymorphism from working except in special cases.)",
		"--no-reclaim-heap-on-nondet-failure",
		"\tDon't reclaim heap on backtracking in nondet code.",
		"--no-reclaim-heap-on-semidet-failure",
		"\tDon't reclaim heap on backtracking in semidet code.",
		"--no-reclaim-heap-on-failure",
		"\tCombines the effect of the two options above.",
		"--cc <compiler-name>",
		"\tSpecify which C compiler to use.",
		"--c-include-directory <dir>",
		"\tSpecify the directory containing the Mercury C header files.",
		"--cflags <options>",
		"\tSpecify options to be passed to the C compiler.",
		% The --cflags-for-regs and --cflags-for-gotos options
		% are reserved for use by the `mmc' script;
		% they are deliberately not documented.

		"--c-debug",
		"\tEnable debugging of the generated C code.",
		"\t(This has the same effect as `--cflags -g'.)",

		"--fact-table-max-array-size <n>",
		"\tSpecify the maximum number of elements in a single",
		"\t`pragma fact_table' data array (default: 1024).",
		"--fact-table-hash-percent-full <percentage>",
		"\tSpecify how full the `pragma fact_table' hash tables should be",
		"\tallowed to get.  Given as an integer percentage",
		"\t(valid range: 1 to 100, default: 90)."
	]).

:- pred options_help_optimization(io__state::di, io__state::uo) is det.

options_help_optimization -->
	io__write_string("\nOptimization Options:\n"),
	write_tabbed_lines([
		"-O <n>, --opt-level <n>, --optimization-level <n>",
		"\tSet optimization level to <n>.",
		"\tOptimization level -1 means no optimization",
		"\twhile optimization level 6 means full optimization.",
	% 	"\t\tFor a full description of each optimization level,",
	% 	"\t\tsee the Mercury User's Guide.",
		"--opt-space, --optimize-space",
		"\tTurn on optimizations that reduce code size",
		"\tand turn off optimizations that significantly",
		"\tincrease code size.",
		"--intermodule-optimization",
		"\tPerform inlining and higher-order specialization of",
		"\tthe code for predicates imported from other modules.",
		"\tThis option must be set throughout the compilation process.",
		"--trans-intermod-opt",
		"--transitive-intermodule-optimization",
		"\tImport the transitive intermodule optimization data.",
		"\tThis data is imported from `<module>.trans_opt' files.",
		"--use-opt-files",
		"\tPerform inter-module optimization using any",
		"\t`.opt' files which are already built,",
		"\te.g. those for the standard library, but do",
		"\tnot build any others.",
		"--use-trans-opt-files",
		"\tPerform inter-module optimization using any",
		"\t`.trans_opt' files which are already built,",
		"\te.g. those for the standard library, but do",
		"\tnot build any others.",
		"--split-c-files",
		"\tGenerate each C function in its own C file,",
		"\tso that the linker will optimize away unused code.",
		"\tThis option significantly increases compilation time,",
		"\tlink time, and intermediate disk space requirements,",
		"\tbut in return reduces the size of the final",
		"\texecutable, typically by about 10-20%.",
		"\tThis option is only useful with `--procs-per-c-function 1'."
	]).

:- pred options_help_hlds_hlds_optimization(io__state::di, io__state::uo)
	is det.

options_help_hlds_hlds_optimization -->
	io__write_string("\n    High-level (HLDS -> HLDS) optimizations:\n"),
	write_tabbed_lines([
		"--no-inlining",
		"\tDisable all forms of inlining.",
		"--no-inline-simple",
		"\tDisable the inlining of simple procedures.",
		"--no-inline-single-use",
		"\tDisable the inlining of procedures called only once.",
		"--inline-compound-threshold <threshold>",
		"\tInline a procedure if its size (measured roughly",
		"\tin terms of the number of connectives in its internal form),",
		"\tmultiplied by the number of times it is called,",
		"\tis below the given threshold.",
		"--inline-simple-threshold <threshold>",
		"\tInline a procedure if its size is less than the",
		"\tgiven threshold.",
		"--intermod-inline-simple-threshold",
		"\tSimilar to `--inline-simple-threshold', except used to",
		"\tdetermine which predicates should be included in",
		"\t`.opt' files. Note that changing this between writing",
		"\tthe `.opt' file and compiling to C may cause link errors,",
		"\tand too high a value may result in reduced performance.",
		"--no-common-struct",
		"\tDisable optimization of common term structures.",
		"--no-common-goal",
		"\tDisable optimization of common goals.",
		"\tAt the moment this optimization",
		"\tdetects only common deconstruction unifications.",
		"\tDisabling this optimization reduces the class of predicates",
		"\tthat the compiler considers to be deterministic.",
	% 	"\t--constraint-propagation",
	% 	"\t\tEnable the C-tranformation.  (Doesn't work.)",
		"--prev-code",
		"\tMigrate into the start of branched goals.",
		"--no-follow-code",
		"\tDon't migrate into the end of branched goals.",
		"--excess-assign",
		"\tRemove excess assignment unifications.",
		"--optimize-duplicate-calls",
		"\tOptimize away multiple calls to a predicate",
		"\twith the same input arguments.",
		"--optimize-saved-vars",
		"\tReorder goals to minimize the number of variables",
		"\tthat have to be saved across calls.",
		"--optimize-unused-args",
		"\tRemove unused predicate arguments.",
		"\tThis will cause the compiler to generate more",
		"\tefficient code for many polymorphic predicates.",
		"--intermod-unused-args",
		"\tPerform unused argument removal across module boundaries.",
		"\tThis option implies `--optimize-unused-args' and",
		"\t`--intermodule-optimization'.",

		"--optimize-higher-order",
		"\tEnable specialization of higher-order predicates.",
		"--type-specialization",
		"\tEnable specialization of polymorphic predicates.",
		"--higher-order-size-limit",
		"\tSet the maximum goal size of specialized versions created by",
		"\t`--optimize-higher-order' and `--type-specialization'.",
		"\tGoal size is measured as the number of calls, unifications",
		"\tand branched goals.",
		"--optimize-constructor-last-call",
		"\tEnable the optimization of ""last"" calls that are followed by",
		"\tconstructor application.",
		"--deforestation",
		"\tEnable deforestation. Deforestation is a program",
		"\ttransformation whose aim is to avoid the construction of",
		"\tintermediate data structures and to avoid repeated traversals",
		"\tover data structures within a conjunction.",
		"--deforestation-depth-limit",
		"\tSpecify a depth limit for the deforestation algorithm",
		"\tin addition to the usual termination checks.",
		"\tA value of -1 specifies no depth limit. The default is 4.",
		"--deforestation-vars-threshold",
		"\tSpecify a rough limit on the number of variables",
		"\tin a procedure created by deforestation.",
		"\tA value of -1 specifies no limit. The default is 200."
	]).
	 
:- pred options_help_hlds_llds_optimization(io__state::di, io__state::uo) is det.

options_help_hlds_llds_optimization -->
	io__write_string("\n    Medium-level (HLDS -> LLDS) optimizations:\n"),
	write_tabbed_lines([
		"--no-smart-indexing",
		"\tGenerate switches as a simple if-then-else chains;",
		"\tdisable string hashing and integer table-lookup indexing.",
		"--dense-switch-req-density <percentage>",
		"\tThe jump table generated for an atomic switch",
		"\tmust have at least this percentage of full slots (default: 25).",
		"--lookup-switch-req-density <percentage>",
		"\tThe jump table generated for an atomic switch",
		"\tin which all the outputs are constant terms",
		"\tmust have at least this percentage of full slots (default: 25).",
		"--dense-switch-size <n>",
		"\tThe jump table generated for an atomic switch",
		"\tmust have at least this many entries (default: 4).",
		"--lookup-switch-size <n>",
		"\tThe lookup table generated for an atomic switch",
		"\tmust have at least this many entries (default: 4).",
		"--string-switch-size <n>",
		"\tThe hash table generated for a string switch",
		"\tmust have at least this many entries (default: 8).",
		"--tag-switch-size <n>",
		"\tThe number of alternatives in a tag switch",
		"\tmust be at least this number (default: 3).",
		"--try-switch-size <n>",
		"\tThe number of alternatives in a try/retry chain switch",
		"\tmust be at least this number (default: 3).",
		"--binary-switch-size <n>",
		"\tThe number of alternatives in a binary search switch",
		"\tmust be at least this number (default: 4).",
		"--no-static-ground-terms",
		"\tDisable the optimization of constructing constant ground terms",
		"\tat compile time and storing them as static constants.",
		"--no-middle-rec",
		"\tDisable the middle recursion optimization.",
		"--no-simple-neg",
		"\tDon't generate simplified code for simple negations.",
		"--no-follow-vars",
		"\tDon't optimize the assignment of registers in branched goals."
%		"--no-allow-hijacks",
%		"\tDo not generate code in which a procedure hijacks",
%		"\ta nondet stack frame that possibly belongs to",
%		"\tanother procedure invocation\n".
	]).

:- pred options_help_llds_llds_optimization(io__state::di, io__state::uo) is det.

options_help_llds_llds_optimization -->
	io__write_string("\n    Low-level (LLDS -> LLDS) optimizations:\n"),
	write_tabbed_lines([
		"--no-llds-optimize",
		"\tDisable the low-level optimization passes.",
		"--optimize-dead-procs",
		"\tEnable dead predicate elimination.",
		"--no-optimize-peep",
		"\tDisable local peephole optimizations.",
		"--no-optimize-jumps",
		"\tDisable elimination of jumps to jumps.",
		"--no-optimize-fulljumps",
		"\tDisable elimination of jumps to ordinary code.",
		"--no-optimize-labels",
		"\tDisable elimination of dead labels and code.",
		"--optimize-dups",
		"\tEnable elimination of duplicate code.",
%%%		"--optimize-copyprop",
%%%		"\tEnable the copy propagation optimization.",
		"--optimize-value-number",
		"\tPerform value numbering on extended basic blocks.",
		"--no-optimize-frames",
		"\tDisable stack frame optimizations.",
		"--no-optimize-delay-slot",
		"\tDisable branch delay slot optimizations.",
		"--optimize-repeat <n>",
		"\tIterate most optimizations at most <n> times (default: 3).",
		"--optimize-vnrepeat <n>",
		"\tIterate value numbering at most <n> times (default: 1).",
		"--pred-value-number",
		"\tExtend value numbering to entire predicates."
	]).

:- pred options_help_output_optimization(io__state::di, io__state::uo) is det.

options_help_output_optimization -->
	io__write_string("\n    Output-level (LLDS -> C) optimizations:\n"),
	write_tabbed_lines([
		"--use-macro-for-redo-fail",
		"\tEmit the fail or redo macro instead of a branch",
		"\tto the fail or redo code in the runtime system.",
		"\tThis produces slightly bigger but slightly faster code.",
		"--no-emit-c-loops",
		"\tUse only gotos, don't emit C loop constructs.",
		"--procs-per-c-function <n>",
		"\tPut the code for up to <n> Mercury",
		"\tprocedures in a single C function.  The default",
		"\tvalue of <n> is one.  Increasing <n> can produce",
		"\tslightly more efficient code, but makes compilation slower.",
		"--everything-in-one-c-function",
		"\tThis option has the effect of putting the code for all",
		"\tthe Mercury procedures in a single C function,",
		"\twhich produces the most efficient code but tends to",
		"\tseverely stress the C compiler on large modules."
	]).

:- pred options_help_object_optimization(io__state::di, io__state::uo) is det.

options_help_object_optimization -->
	io__write_string("\n    Object-level (C -> object code) optimizations:\n"),
	write_tabbed_lines([
		"\tNote that if you are using Mmake, you need to pass these",
		"\toptions to `mgnuc' rather than to `mmc'.",
		"--no-c-optimize",
		"\tDon't enable the C compiler's optimizations.",
		"--inline-alloc",
		"\tInline calls to GC_malloc().",
		"\tThis can improve performance a fair bit,",
		"\tbut may significantly increase code size.",
		"\tThis option has no effect if `--gc conservative'",
		"\tis not set or if the C compiler is not GNU C."
	]).

:- pred options_help_link(io__state::di, io__state::uo) is det.

options_help_link -->
	io__write_string("\nLink Options:\n"),
	write_tabbed_lines([
		"-o <filename>, --output-file <filename>",
		"\tSpecify the name of the final executable.",
		"\t(The default executable name is the same as the name",
		"\tof the first module on the command line.)",
		"--link-flags <options>",
		"\tSpecify options to be passed to the linker.",
		"-L <directory>, --library-directory <directory>",
		"\tAppend <directory> to the list of directories in which",
		"\tto search for libraries.",
		"-l <library>, --library <library>",
		"\tLink with the specified library.",
		"--link-object <object-file>",
		"\tLink with the specified object file."
	]).

:- pred options_help_misc(io__state::di, io__state::uo) is det.

options_help_misc -->
	io__write_string("\nMiscellaneous Options:\n"),
	write_tabbed_lines([
	% 	"\t-H <n>, --heap-space <n>",
	% 	"\t\tPre-allocate <n> kilobytes of heap space.",
	% 	"\t\tThis option is now obsolete.  In the past it",
	% 	"\t\twas used to avoid NU-Prolog's",
	% 	"\t\t\t""Panic: growing stacks has required shifting the heap""",
	% 	"\t\tmessage.",

		"-I <dir>, --search-directory <dir>",
		"\tAdd <dir> to the list of directories to be searched for \n\t\timported modules.",
		"--intermod-directory <dir>",
		"\tAdd <dir> to the list of directories to be",
		"\tsearched for `.opt' files.",
		"--no-use-search-directories-for-intermod",
		"\tDon't add arguments to `--search-directory' to the list",
		"\tof directories to search for `.opt' files - use only the",
		"\tdirectories given by `--intermod-directory'.",
		"--use-subdirs",
		"\tGenerate intermediate files in a `Mercury' subdirectory,",
		"\trather than generating them in the current directory."
	]).

:- pred write_tabbed_lines(list(string), io__state, io__state).
:- mode write_tabbed_lines(in, di, uo) is det.

write_tabbed_lines([]) --> [].
write_tabbed_lines([Str|Strs]) -->
	io__write_char('\t'),
	io__write_string(Str),
	io__write_char('\n'),
	write_tabbed_lines(Strs).

:- end_module options.

%-----------------------------------------------------------------------------%
