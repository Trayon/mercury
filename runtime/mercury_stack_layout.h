/*
** Copyright (C) 1998-2002 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

#ifndef MERCURY_STACK_LAYOUT_H
#define MERCURY_STACK_LAYOUT_H

/*
** mercury_stack_layout.h -
**	Definitions for stack layout data structures. These are generated by
**	the compiler, and are used by the parts of the runtime system that need
**	to look at the stacks (and sometimes the registers) and make sense of
**	their contents. The parts of the runtime system that need to do this
**	include exception handling, the debugger, and (eventually) the
**	accurate garbage collector.
**
**	For a general description of the idea of stack layouts, see the paper
**	"Run time type information in Mercury" by Tyson Dowd, Zoltan Somogyi,
**	Fergus Henderson, Thomas Conway and David Jeffery, which is available
**	from the Mercury web site. The relevant section is section 3.8, but be
**	warned: while the general principles remain applicable, the details
**	have changed since that paper was written.
**
** NOTE: The constants and data-structures used here need to be kept in
** sync with the ones generated in the compiler. If you change anything here,
** you may need to change stack_layout.m, layout.m, and/or layout_out.m in
** the compiler directory as well.
*/

#include "mercury_types.h"
#include "mercury_std.h"			/* for MR_VARIABLE_SIZED */
#include "mercury_tags.h"

/* forward declarations */
typedef	struct MR_Proc_Layout_Struct	MR_Proc_Layout;
typedef struct MR_Module_Layout_Struct	MR_Module_Layout;

/*-------------------------------------------------------------------------*/
/*
** Definitions for MR_PredFunc. This enum should EXACTLY match the definition
** of the `pred_or_func' type in browser/util.m.
*/

typedef	enum { MR_PREDICATE, MR_FUNCTION } MR_PredFunc;

/*-------------------------------------------------------------------------*/
/*
** Definitions for MR_Determinism
*/

/*
** The max_soln component of the determinism is encoded in the 1 and 2 bits.
** The can_fail component of the determinism is encoded in the 4 bit.
** The first_solution component of the determinism is encoded in the 8 bit.
**
** MR_DETISM_AT_MOST_MANY could also be defined as ((d) & 3) == 3),
** but this would be less efficient, since the C compiler does not know
** that we do not set the 1 bit unless we also set the 2 bit.
*/

typedef	MR_int_least16_t	MR_Determinism;

#define	MR_DETISM_DET		6
#define	MR_DETISM_SEMI		2
#define	MR_DETISM_NON		3
#define	MR_DETISM_MULTI		7
#define	MR_DETISM_ERRONEOUS	4
#define	MR_DETISM_FAILURE	0
#define	MR_DETISM_CCNON		10
#define	MR_DETISM_CCMULTI	14

#define	MR_DETISM_MAX		14

#define MR_DETISM_AT_MOST_ZERO(d)	(((d) & 3) == 0)
#define MR_DETISM_AT_MOST_ONE(d)	(((d) & 3) == 2)
#define MR_DETISM_AT_MOST_MANY(d)	(((d) & 1) != 0)

#define MR_DETISM_CAN_FAIL(d)		(((d) & 4) == 0)

#define MR_DETISM_FIRST_SOLN(d)		(((d) & 8) != 0)

#define MR_DETISM_DET_STACK(d)		(!MR_DETISM_AT_MOST_MANY(d) \
					|| MR_DETISM_FIRST_SOLN(d))

/*-------------------------------------------------------------------------*/
/*
** Definitions for MR_Long_Lval and MR_Short_Lval
*/

/*
** MR_Long_Lval is a MR_uint_least32_t which describes an location.
** This includes lvals such as stack slots, general registers, and special
** registers such as succip, hp, etc, as well as locations whose address is
** given as a typeinfo inside the type class info structure pointed to by an
** lval.
**
** What kind of location an MR_Long_Lval refers to is encoded using
** a low tag with MR_LONG_LVAL_TAGBITS bits; the type MR_Long_Lval_Type
** describes the different tag values. The interpretation of the rest of
** the word depends on the location type:
**
**  Locn		Tag	Rest
**  MR_r(Num)		 0	Num (register number)
**  MR_f(Num)		 1	Num (register number)
**  MR_stackvar(Num)	 2	Num (stack slot number)
**  MR_framevar(Num)	 3	Num (stack slot number)
**  MR_succip		 4
**  MR_maxfr		 5
**  MR_curfr		 6
**  MR_hp		 7
**  MR_sp		 8
**  indirect(Base, N)	 9	See below
**  unknown		10	(The location is not known)
**
** For indirect references, the word exclusive of the tag consists of
** (a) an integer with MR_LONG_LVAL_OFFSETBITS bits giving the index of
** the typeinfo inside a type class info (to be interpreted by
** MR_typeclass_info_type_info or the predicate
** private_builtin:type_info_from_typeclass_info, which calls it) and
** (b) a MR_Long_Lval value giving the location of the pointer to the
** type class info.  This MR_Long_Lval value will *not* have an indirect
** tag.
**
** This data is generated in stack_layout__represent_locn_as_int,
** which must be kept in sync with the constants and macros defined here.
*/

typedef MR_uint_least32_t	MR_Long_Lval;

typedef enum {
	MR_LONG_LVAL_TYPE_R,
	MR_LONG_LVAL_TYPE_F,
	MR_LONG_LVAL_TYPE_STACKVAR,
	MR_LONG_LVAL_TYPE_FRAMEVAR,
	MR_LONG_LVAL_TYPE_SUCCIP,
	MR_LONG_LVAL_TYPE_MAXFR,
	MR_LONG_LVAL_TYPE_CURFR,
	MR_LONG_LVAL_TYPE_HP,
	MR_LONG_LVAL_TYPE_SP,
	MR_LONG_LVAL_TYPE_INDIRECT,
	MR_LONG_LVAL_TYPE_UNKNOWN 
} MR_Long_Lval_Type;

/* This must be in sync with stack_layout__long_lval_tag_bits */
#define MR_LONG_LVAL_TAGBITS	4

#define MR_LONG_LVAL_TYPE(Locn) 					\
	((MR_Long_Lval_Type)						\
		(((MR_Word) Locn) & ((1 << MR_LONG_LVAL_TAGBITS) - 1)))

#define MR_LONG_LVAL_NUMBER(Locn) 					\
	((int) ((MR_Word) Locn) >> MR_LONG_LVAL_TAGBITS)

/* This must be in sync with stack_layout__offset_bits */
#define MR_LONG_LVAL_OFFSETBITS	6

#define MR_LONG_LVAL_INDIRECT_OFFSET(LocnNumber) 			\
	((int) ((LocnNumber) & ((1 << MR_LONG_LVAL_OFFSETBITS) - 1)))

#define MR_LONG_LVAL_INDIRECT_BASE_LVAL(LocnNumber)			\
	(((MR_Word) (LocnNumber)) >> MR_LONG_LVAL_OFFSETBITS)

#define	MR_LONG_LVAL_STACKVAR(n)					\
	((MR_Word) ((n) << MR_LONG_LVAL_TAGBITS) + MR_LONG_LVAL_TYPE_STACKVAR)

#define	MR_LONG_LVAL_FRAMEVAR(n)					\
	((MR_Word) ((n) << MR_LONG_LVAL_TAGBITS) + MR_LONG_LVAL_TYPE_FRAMEVAR)

#define	MR_LONG_LVAL_R_REG(n)						\
	((MR_Word) ((n) << MR_LONG_LVAL_TAGBITS) + MR_LONG_LVAL_TYPE_R)

/*
** MR_Short_Lval is a MR_uint_least8_t which describes an location. This
** includes lvals such as stack slots and general registers that have small
** numbers, and special registers such as succip, hp, etc.
**
** What kind of location an MR_Long_Lval refers to is encoded using
** a low tag with 2 bits; the type MR_Short_Lval_Type describes
** the different tag values. The interpretation of the rest of the word
** depends on the location type:
**
**  Locn		Tag	Rest
**  MR_r(Num)		 0	Num (register number)
**  MR_stackvar(Num)	 1	Num (stack slot number)
**  MR_framevar(Num)	 2	Num (stack slot number)
**  special reg		 3	MR_Long_Lval_Type
**
** This data is generated in stack_layout__represent_locn_as_byte,
** which must be kept in sync with the constants and macros defined here.
*/

typedef MR_uint_least8_t	MR_Short_Lval;

typedef enum {
	MR_SHORT_LVAL_TYPE_R,
	MR_SHORT_LVAL_TYPE_STACKVAR,
	MR_SHORT_LVAL_TYPE_FRAMEVAR,
	MR_SHORT_LVAL_TYPE_SPECIAL
} MR_Short_Lval_Type;

/* This must be in sync with stack_layout__short_lval_tag_bits */
#define MR_SHORT_LVAL_TAGBITS	2

#define MR_SHORT_LVAL_TYPE(Locn) 					\
	((MR_Short_Lval_Type)						\
		(((MR_Word) Locn) & ((1 << MR_SHORT_LVAL_TAGBITS) - 1)))

#define MR_SHORT_LVAL_NUMBER(Locn) 					\
	((int) ((MR_Word) Locn) >> MR_SHORT_LVAL_TAGBITS)

#define	MR_SHORT_LVAL_STACKVAR(n)					\
	((MR_Short_Lval) (((n) << MR_SHORT_LVAL_TAGBITS)		\
		+ MR_SHORT_LVAL_TYPE_STACKVAR))

#define	MR_SHORT_LVAL_FRAMEVAR(n)					\
	((MR_Short_Lval) (((n) << MR_SHORT_LVAL_TAGBITS)		\
		+ MR_SHORT_LVAL_TYPE_FRAMEVAR))

#define	MR_SHORT_LVAL_R_REG(n)						\
	((MR_Short_Lval) (((n) << MR_SHORT_LVAL_TAGBITS)		\
		+ MR_SHORT_LVAL_TYPE_R))

/*-------------------------------------------------------------------------*/
/*
** Definitions for MR_Label_Layout
*/

/*
** An MR_Label_Layout structure describes the debugging and accurate gc
** information available at a given label.
**
** The MR_sll_entry field points to the proc layout structure of the procedure
** in which the label occurs.
**
** The MR_sll_port field will contain a negative number if there is no
** execution tracing port associated with the label. If there is, the
** field will contain a value of type MR_Trace_Port. For labels associated
** with events, this will be the port of the event. For return labels,
** this port will be exception (since exception events are associated with
** the return from the call that raised the exception).
**
** The MR_sll_goal_path field contains an offset into the module-wide string
** table, leading to a string that gives the goal path associated with the
** label. If there is no meaningful goal path associated with the label,
** the offset will be zero, leading to the empty string.
**
** The remaining fields give information about the values live at the given
** label, if this information is available. If it is available, the
** MR_has_valid_var_count macro will return true and the last three fields are
** meaningful; if it is not available, the macro will return false and the last
** three fields are not meaningful (i.e. you are looking at an
** MR_Label_Layout_No_Var_Info structure).
**
** The format in which we store information about the values live at the label
** is somewhat complicated, due to our desire to make this information compact.
** We can represent a location in one of two ways, as an 8-bit MR_Short_Lval
** or as a 32-bit MR_Long_Lval. We prefer representing a location as an
** MR_Short_Lval, but of course not all locations can be represented in
** this way, so those other locations are represented as MR_Long_Lvals.
**
** The MR_sll_var_count field, if it is valid, is encoded by the formula
** (#Long << MR_SHORT_COUNT_BITS + #Short), where #Short is the number
** data items whose descriptions fit into an MR_Short_Lval and #Long is the
** number of data items whose descriptions do not. (The number of distinct
** values that fit into 8 bits also fits into 8 bits, but since some
** locations hold the value of more than one variable at a time, not all
** the values need to be distinct; this is why MR_SHORT_COUNT_BITS is
** more than 8.)
**
** The MR_sll_locns_types field point a memory area that contain three vectors
** back to back. The first vector has #Long + #Short word-sized elements,
** each of which is a pointer to a MR_PseudoTypeInfo giving the type of a live
** data item, with a small integer instead of a pointer representing a special
** kind of live data item (e.g. a saved succip or hp). The second vector is
** an array of #Long MR_Long_Lvals, and the third is an array of #Short
** MR_Short_Lvals, each of which describes a location. The pseudotypeinfo
** pointed to by the slot at subscript i in the first vector describes
** the type of the data stored in slot i in the second vector if i < #Long, and
** the type of the data stored in slot i - #Long in the third vector
** otherwise.
**
** The MR_sll_var_nums field may be NULL, which means that there is no
** information about the variable numbers of the live values. If the field
** is not NULL, it points to a vector of variable numbers, which has an element
** for each live data item. This is either the live data item's HLDS variable
** number, or one of two special values. Zero means that the live data item
** is not a variable (e.g. it is a saved copy of succip). The largest possible
** 16-bit number on the other hand means "the number of this variable does not
** fit into 16 bits". With the exception of these special values, the value
** in this slot uniquely identifies the live data item. (Not being able to
** uniquely identify nonvariable data items is never a problem. Not being able
** to uniquely identify variables is a problem, at the moment, only to the
** extent that the debugger cannot print their names.)
**
** The types of the live variables may or may not have type variables in them.
** If they do not, the MR_sll_tvars field will be NULL. If they do, it will
** point to an MR_Type_Param_Locns structure that gives the locations of the
** typeinfos for those type variables. This structure gives the number of type
** variables and their locations, so that the code that needs the type
** parameters can materialize all the type parameters from their location
** descriptions in one go. This is an optimization, since the type parameter
** vector could simply be indexed on demand by the type variable's variable
** number stored within the MR_PseudoTypeInfos stored inside the first vector
** pointed to by the MR_sll_locns_types field.
**
** Since we allocate type variable numbers sequentially, the MR_tp_param_locns
** vector will usually be dense. However, after all variables whose types
** include e.g. type variable 2 have gone out of scope, variables whose
** types include type variable 3 may still be around. In cases like this,
** the entry for type variable 2 will be zero; this signals to the code
** in the internal debugger that materializes typeinfo structures that
** this typeinfo structure need not be materialized. Note that the array
** element MR_tp_param_locns[i] describes the location of the typeinfo
** structure for type variable i+1, since array offsets start at zero
** but type variable numbers start at one.
**
** XXX: Presently, inst information is ignored; we assume that all live values
** are ground.
*/

typedef	struct MR_Type_Param_Locns_Struct {
	MR_uint_least32_t		MR_tp_param_count;
	MR_Long_Lval			MR_tp_param_locns[MR_VARIABLE_SIZED];
} MR_Type_Param_Locns;

typedef	struct MR_Label_Layout_Struct {
	const MR_Proc_Layout		*MR_sll_entry;
	MR_int_least16_t		MR_sll_port;
	MR_int_least16_t		MR_sll_goal_path;
	MR_Integer			MR_sll_var_count; /* >= 0 */
	const void			*MR_sll_locns_types;
	const MR_uint_least16_t		*MR_sll_var_nums;
	const MR_Type_Param_Locns	*MR_sll_tvars;
} MR_Label_Layout;

typedef	struct MR_Label_Layout_No_Var_Info_Struct {
	const MR_Proc_Layout		*MR_sll_entry;
	MR_int_least16_t		MR_sll_port;
	MR_int_least16_t		MR_sll_goal_path;
	MR_Integer			MR_sll_var_count; /* < 0 */
} MR_Label_Layout_No_Var_Info;

#define	MR_label_goal_path(layout)					    \
	((MR_PROC_LAYOUT_HAS_EXEC_TRACE((layout)->MR_sll_entry)) ?	    \
		((layout)->MR_sll_entry->MR_sle_module_layout		    \
		 	->MR_ml_string_table				    \
		+ (layout)->MR_sll_goal_path)				    \
	: "")

#define	MR_SHORT_COUNT_BITS	10
#define	MR_SHORT_COUNT_MASK	((1 << MR_SHORT_COUNT_BITS) - 1)

#define	MR_has_valid_var_count(sll)					    \
		(((sll)->MR_sll_var_count) >= 0)
#define	MR_has_valid_var_info(sll)					    \
		(((sll)->MR_sll_var_count) > 0)
#define	MR_long_desc_var_count(sll)					    \
		(((sll)->MR_sll_var_count) >> MR_SHORT_COUNT_BITS)
#define	MR_short_desc_var_count(sll)					    \
		(((sll)->MR_sll_var_count) & MR_SHORT_COUNT_MASK)
#define	MR_all_desc_var_count(sll)					    \
		(MR_long_desc_var_count(sll) + MR_short_desc_var_count(sll))

#define	MR_var_pti(sll, i)						    \
		(((MR_PseudoTypeInfo *) ((sll)->MR_sll_locns_types))[(i)])
#define	MR_end_of_var_ptis(sll)						    \
		(&MR_var_pti((sll), MR_all_desc_var_count(sll)))
#define	MR_long_desc_var_locn(sll, i)					    \
		(((MR_uint_least32_t *) MR_end_of_var_ptis(sll))[(i)])
#define	MR_end_of_long_desc_var_locns(sll)				    \
		(&MR_long_desc_var_locn((sll), MR_long_desc_var_count(sll)))
#define	MR_short_desc_var_locn(sll, i)					    \
		(((MR_uint_least8_t *)					    \
			MR_end_of_long_desc_var_locns(sll))		    \
		 		[((i) - MR_long_desc_var_count(sll))])

/*
** Define a stack layout for an internal label.
**
** The MR_MAKE_INTERNAL_LAYOUT_WITH_ENTRY variant allows you to specify
** the label name (l) and the entry label name (e) independently, which
** means that it can be used for labels in code fragments which are
** simultaneously part of several procedures. (Some hand-written code
** in the library is like this; the different procedures usually differ
** only in attributes such as the uniqueness of their arguments.)
**
** The MR_MAKE_INTERNAL_LAYOUT variant assumes that the internal label
** is in the procedure named by the entry label.
**
** The only useful information in the structures created by these macros
** is the reference to the procedure layout, which allows you to find the
** stack frame size and the succip location, thereby enabling stack tracing.
**
** For the native garbage collector, we will need to add meaningful
** live value information as well to these macros.
*/ 

#define MR_MAKE_INTERNAL_LAYOUT_WITH_ENTRY(label, entry) \
	MR_Label_Layout_No_Var_Info mercury_data__label_layout__##label = {\
		(MR_Proc_Layout *) &mercury_data__proc_layout__##entry,	\
		-1,							\
		0,							\
		-1		/* No info about live values */		\
	}

#define MR_MAKE_INTERNAL_LAYOUT(entry, labelnum)			\
	MR_MAKE_INTERNAL_LAYOUT_WITH_ENTRY(entry##_i##labelnum, entry)

/*-------------------------------------------------------------------------*/
/*
** Definitions for MR_Proc_Layout
*/

/*
** The MR_Stack_Traversal structure contains the following fields:
**
** The code_addr field points to the start of the procedure's code.
** This allows the profiler to figure out which procedure a sampled program
** counter belongs to, and allows the debugger to implement retry.
**
** The succip_locn field encodes the location of the saved succip if it is
** saved in a general purpose stack slot. If the succip is saved in a special
** purpose stack slot (as it is for model_non procedures) or if the procedure
** never saves the succip (as in leaf procedures), this field will contain -1.
**
** The stack_slots field gives the number of general purpose stack slots
** in the procedure.
**
** The detism field encodes the determinism of the procedure.
*/

typedef struct MR_Stack_Traversal_Struct {
	MR_Code			*MR_trav_code_addr;
	MR_Long_Lval		MR_trav_succip_locn;
	MR_int_least16_t	MR_trav_stack_slots;
	MR_Determinism		MR_trav_detism;
} MR_Stack_Traversal;

/*
** MR_Proc_Id is a union. The usual alternative identifies ordinary
** procedures, while the other alternative identifies automatically generated
** unification, comparison and index procedures. The meanings of the fields
** in both forms are the same as in procedure labels. The runtime system
** can figure out which form is present by using the macro
** MR_PROC_LAYOUT_COMPILER_GENERATED, which will return true only if
** the procedure is of the second type.
**
** The compiler generates MR_User_Proc_Id and MR_Compiler_Proc_Id structures
** in order to avoid having to initialize the MR_Proc_Id union through the
** inapplicable alternative, since the C standard in widespread use now
** doesn't support that.
**
** The places that know about the structure of procedure ids include
** browser/dl.m and besides all the places that refer to the C types below.
*/

typedef struct MR_User_Proc_Id_Struct {
	MR_PredFunc		MR_user_pred_or_func;
	MR_ConstString		MR_user_decl_module;
	MR_ConstString		MR_user_def_module;
	MR_ConstString		MR_user_name;
	MR_int_least16_t	MR_user_arity;
	MR_int_least16_t	MR_user_mode;
} MR_User_Proc_Id;

typedef struct MR_Compiler_Proc_Id_Struct {
	MR_ConstString		MR_comp_type_name;
	MR_ConstString		MR_comp_type_module;
	MR_ConstString		MR_comp_def_module;
	MR_ConstString		MR_comp_pred_name;
	MR_int_least16_t	MR_comp_arity;
	MR_int_least16_t	MR_comp_mode;
} MR_Compiler_Proc_Id;

typedef union MR_Proc_Id_Union {
	MR_User_Proc_Id		MR_proc_user;
	MR_Compiler_Proc_Id	MR_proc_comp;
} MR_Proc_Id;

#define	MR_PROC_LAYOUT_COMPILER_GENERATED(entry)			\
	MR_PROC_ID_COMPILER_GENERATED(entry->MR_sle_proc_id)

#define	MR_PROC_ID_COMPILER_GENERATED(proc_id)				\
	((MR_Unsigned) (proc_id).MR_proc_user.MR_user_pred_or_func	\
	 	> MR_FUNCTION)

/*
** The MR_Exec_Trace structure contains the following fields.
**
** The call_label field points to the label layout structure for the label
** associated with the call event at the entry to the procedure. The purpose
** of this field is to allow the debugger to find out which variables
** are where on entry, so it can reexecute the procedure if asked to do so
** and if the values of the required variables are still available.
**
** The module_layout field points to the module info structure of the module
** containing the procedure. This allows the debugger access to the string table
** stored there, as well the table associating source-file contexts with labels.
**
** The proc_rep field contains a representation of the body of the procedure
** as a Mercury term of type goal_rep, defined in program_representation.m.
** Note that the type of this field is `MR_Word *', not `MR_Word',
** for the same reasons that MR_mkword() has type `MR_Word *' rather
** than `MR_Word' (see the comment in runtime/mercury_tags.h).
** It will be a null pointer if no such representation is available.
**
** The used_var_names field points to an array that contains offsets
** into the string table, with the offset at index i-1 giving the name of
** variable i (since variable numbers start at one). If a variable has no name
** or cannot be referred to from an event, the offset will be zero, at which
** offset the string table will contain an empty string. The string table
** is restricted to be small enough to be addressed with 16 bits;
** a string is reserved near the start for a string that says "too many
** variables". Stack_layout.m will generate a reference to this string
** instead of generating an offset that does not fit into 16 bits.
** Therefore using the stored offset to index into the string table
** is always safe.
**
** The max_var_num field gives the number of elements in the used_var_names
** table.
**
** The max_r_num field tells the debugger which Mercury abstract machine
** registers need saving in MR_trace: besides the special registers, it is
** the general-purpose registers rN for values of N up to and including the
** value of this field. Note that this field contains an upper bound; in
** general, there will be calls to MR_trace at which the number of the highest
** numbered general purpose (i.e. rN) registers is less than this. However,
** storing the upper bound gets us almost all the benefit (of not saving and
** restoring all the thousand rN registers) for a small fraction of the static
** space cost of storing the actual number in label layout structures.
**
** If the procedure is compiled with deep tracing, the maybe_from_full field
** will contain a negative number. If it is compiled with shallow tracing,
** it will contain the number of the stack slot that holds the flag that says
** whether this incarnation of the procedure was called from deeply traced code
** or not. (The determinism of the procedure decides whether the stack slot
** refers to a stackvar or a framevar.)
**
** If tabling of I/O actions is enabled, the maybe_io_seq field will contain
** the number of the stack slot that holds the value the I/O action counter
** had on entry to this procedure. Even procedures that do not have I/O state
** arguments will have such a slot, since they or their descendants may call
** unsafe_perform_io.
**
** If trailing is not enabled, the maybe_trail field will contain a negative
** number. If it is enabled, it will contain number of the first of two stack
** slots used for checkpointing the state of the trail on entry to the
** procedure. The first contains the trail pointer, the second the ticket.
**
** If the procedure lives on the nondet stack, or if it cannot create any
** temporary nondet stack frames, the maybe_maxfr field will contain a negative
** number. If it lives on the det stack, and can create temporary nondet stack
** frames, it will contain the number number of the stack slot that contains the
** value of maxfr on entry, for use in executing the retry debugger command
** from the middle of the procedure.
**
** The eval_method field contains a representation of the evaluation method
** used by the procedure. The retry command needs this information if it is
** to reset the call tables of the procedure invocations being retried.
**
** We cannot put enums into structures as bit fields. To avoid wasting space,
** we put MR_EvalMethodInts into structures instead of MR_EvalMethods
** themselves.
**
** If --trace-decl is not set, the maybe_decl field will contain a negative
** number. If it is set, it will contain the number of the first of two stack
** slots used by the declarative debugger; the other slot is the next higher
** numbered one. (The determinism of the procedure decides whether the stack
** slot refers to a stackvar or a framevar.)
*/

typedef	enum {
	MR_EVAL_METHOD_NORMAL,
	MR_EVAL_METHOD_LOOP_CHECK,
	MR_EVAL_METHOD_MEMO,
	MR_EVAL_METHOD_MINIMAL,
	MR_EVAL_METHOD_TABLE_IO
} MR_EvalMethod;

typedef	MR_int_least8_t		MR_EvalMethodInt;

typedef	struct MR_Exec_Trace_Struct {
	const MR_Label_Layout	*MR_exec_call_label;
	const MR_Module_Layout	*MR_exec_module_layout;
	MR_Word			*MR_exec_proc_rep;
	const MR_int_least16_t	*MR_exec_used_var_names;
	MR_int_least16_t	MR_exec_max_var_num;
	MR_int_least16_t	MR_exec_max_r_num;
	MR_int_least8_t		MR_exec_maybe_from_full;
	MR_int_least8_t		MR_exec_maybe_io_seq;
	MR_int_least8_t		MR_exec_maybe_trail;
	MR_int_least8_t		MR_exec_maybe_maxfr;
	MR_EvalMethodInt	MR_exec_eval_method_CAST_ME;
	MR_int_least8_t		MR_exec_maybe_call_table;
	MR_int_least8_t		MR_exec_maybe_decl_debug;
} MR_Exec_Trace;

/*-------------------------------------------------------------------------*/
/*
** Definitions for MR_Proc_Layout
**
** Proc layout structures contain one, two or three substructures.
**
** - The first substructure is the MR_Stack_Traversal structure, which contains
**   information that enables the stack to be traversed, e.g. for accurate gc.
**   It is always present if proc layouts are present at all.
**
** - The second group is the MR_Proc_Id union, which identifies the
**   procedure in terms that are meaningful to both humans and machines.
**   It will be generated only if the module is compiled with stack tracing,
**   execution tracing or profiling. The MR_Proc_Id union has two alternatives,
**   one for user-defined procedures and one for procedures of the compiler
**   generated Unify, Index and Compare predicates.
**
** - The third group is the MR_Exec_Trace structure, which contains
**   information specifically intended for the debugger. It will be generated
**   only if the module is compiled with execution tracing.
**
** The runtime system considers all proc layout structures to be of type
** MR_Proc_Layout, but must use the macros defined below to check for the 
** existence of each substructure before accessing the fields of that
** substructure. The macros are MR_PROC_LAYOUT_HAS_PROC_ID to check for the
** MR_Proc_Id substructure and MR_PROC_LAYOUT_HAS_EXEC_TRACE to check for the
** MR_Exec_Trace substructure.
**
** The reason why some substructures may be missing is to save space.
** If the options with which a module is compiled do not require execution
** tracing, then the MR_Exec_Trace substructure will not present, and if the
** options do not require procedure identification, then the MR_Proc_Id
** substructure will not be present either
**
** The compiler itself generates proc layout structures using the following
** five types.
**
** - When generating only stack traversal information, the compiler will
**   generate proc layout structures of type MR_Proc_Layout_Traversal.
**
** - When generating only stack traversal and procedure id information, the
**   compiler will generate proc layout structures of types MR_Proc_Layout_User
**   and MR_Proc_Layout_Compiler.
**
** - When generating all three groups of information, the compiler will
**   generate proc layout structures of types MR_Proc_Layout_User_Exec
**   and MR_Proc_Layout_Compiler_Exec.
*/

struct MR_Proc_Layout_Struct {
	MR_Stack_Traversal	MR_sle_traversal;
	MR_Proc_Id		MR_sle_proc_id;
	MR_Exec_Trace		MR_sle_exec_trace;
};

typedef	struct MR_Proc_Layout_Traversal_Struct {
	MR_Stack_Traversal	MR_trav_traversal;
	MR_Word			MR_trav_no_proc_id;	/* will be -1 */
} MR_Proc_Layout_Traversal;

typedef	struct MR_Proc_Layout_User_Struct {
	MR_Stack_Traversal	MR_user_traversal;
	MR_User_Proc_Id		MR_user_id;
	MR_Word			MR_user_no_exec_trace;	/* will be NULL */
} MR_Proc_Layout_User;

typedef	struct MR_Proc_Layout_Compiler_Struct {
	MR_Stack_Traversal	MR_comp_traversal;
	MR_Compiler_Proc_Id	MR_comp_id;
	MR_Word			MR_comp_no_exec_trace;	/* will be NULL */
} MR_Proc_Layout_Compiler;

typedef	struct MR_Proc_Layout_User_Exec_Struct {
	MR_Stack_Traversal	MR_user_exec_traversal;
	MR_User_Proc_Id		MR_user_exec_id;
	MR_Exec_Trace		MR_user_exec_trace;
} MR_Proc_Layout_User_Exec;

typedef	struct MR_Proc_Layout_Compiler_Exec_Struct {
	MR_Stack_Traversal	MR_comp_exec_traversal;
	MR_Compiler_Proc_Id	MR_comp_exec_id;
	MR_Exec_Trace		MR_comp_exec_trace;
} MR_Proc_Layout_Compiler_Exec;

#define	MR_PROC_LAYOUT_HAS_PROC_ID(entry)			\
		((MR_Word) entry->MR_sle_user.MR_user_pred_or_func != -1)

#define	MR_PROC_LAYOUT_HAS_EXEC_TRACE(entry)			\
		(MR_PROC_LAYOUT_HAS_PROC_ID(entry)		\
		&& entry->MR_sle_call_label != NULL)

#define	MR_sle_code_addr	MR_sle_traversal.MR_trav_code_addr
#define	MR_sle_succip_locn	MR_sle_traversal.MR_trav_succip_locn
#define	MR_sle_stack_slots	MR_sle_traversal.MR_trav_stack_slots
#define	MR_sle_detism		MR_sle_traversal.MR_trav_detism

#define	MR_sle_user		MR_sle_proc_id.MR_proc_user
#define	MR_sle_comp		MR_sle_proc_id.MR_proc_comp

#define	MR_sle_call_label	MR_sle_exec_trace.MR_exec_call_label
#define	MR_sle_module_layout	MR_sle_exec_trace.MR_exec_module_layout
#define	MR_sle_proc_rep	MR_sle_exec_trace.MR_exec_proc_rep
#define	MR_sle_used_var_names	MR_sle_exec_trace.MR_exec_used_var_names
#define	MR_sle_max_var_num	MR_sle_exec_trace.MR_exec_max_var_num
#define	MR_sle_max_r_num	MR_sle_exec_trace.MR_exec_max_r_num
#define	MR_sle_maybe_from_full	MR_sle_exec_trace.MR_exec_maybe_from_full
#define	MR_sle_maybe_io_seq	MR_sle_exec_trace.MR_exec_maybe_io_seq
#define	MR_sle_maybe_trail	MR_sle_exec_trace.MR_exec_maybe_trail
#define	MR_sle_maybe_maxfr	MR_sle_exec_trace.MR_exec_maybe_maxfr
#define	MR_sle_maybe_call_table MR_sle_exec_trace.MR_exec_maybe_call_table
#define	MR_sle_maybe_decl_debug MR_sle_exec_trace.MR_exec_maybe_decl_debug

#define	MR_sle_eval_method(proc_layout_ptr)				\
			((MR_EvalMethod) (proc_layout_ptr)->		\
				MR_sle_exec_trace.MR_exec_eval_method_CAST_ME)

/*
** Define a layout structure for a procedure, containing information
** for the first two substructures.
**
** The slot count and the succip location parameters do not have to be
** supplied for procedures that live on the nondet stack, since for such
** procedures the size of the frame can be deduced from the prevfr field
** and the location of the succip is fixed.
**
** An unknown slot count should be signalled by MR_PROC_NO_SLOT_COUNT.
** An unknown succip location should be signalled by MR_LONG_LVAL_TYPE_UNKNOWN.
**
** For the procedure identification, we always use the same module name
** for the defining and declaring modules, since procedures whose code
** is hand-written as C modules cannot be inlined in other Mercury modules.
**
** Due to the possibility that code addresses are not static, any use of
** the MR_MAKE_PROC_LAYOUT macro has to be accompanied by a call to the
** MR_INIT_PROC_LAYOUT_ADDR macro in the initialization code of the C module
** that defines the entry. (The cast in the body of MR_INIT_PROC_LAYOUT_ADDR
** is needed because compiler-generated layout structures may use any of the
** five variant types listed above.)
*/ 

#define	MR_PROC_NO_SLOT_COUNT		-1

#ifdef	MR_STATIC_CODE_ADDRESSES
 #define	MR_MAKE_PROC_LAYOUT_ADDR(entry)		MR_STATIC(entry)
 #define	MR_INIT_PROC_LAYOUT_ADDR(entry)		do { } while (0)
#else
 #define	MR_MAKE_PROC_LAYOUT_ADDR(entry)		((MR_Code *) NULL)
 #define	MR_INIT_PROC_LAYOUT_ADDR(entry)				\
		do {							\
			((MR_Proc_Layout *) &				\
			mercury_data__proc_layout__##entry)		\
				->MR_sle_code_addr = MR_ENTRY(entry);	\
		} while (0)
#endif

#define MR_MAKE_PROC_LAYOUT(entry, detism, slots, succip_locn,		\
		pf, module, name, arity, mode) 				\
	MR_Proc_Layout_User mercury_data__proc_layout__##entry = {	\
		{							\
			MR_MAKE_PROC_LAYOUT_ADDR(entry),		\
			succip_locn,					\
			slots,						\
			detism						\
		},							\
		{							\
			pf,						\
			module,						\
			module,						\
			name,						\
			arity,						\
			mode						\
		},							\
		0							\
	}

/*
** In procedures compiled with execution tracing, three items are stored
** in stack slots with fixed numbers. They are:
**
**	the event number of the last event before the call event,
**	the call number, and
**	the call depth.
**
** Note that the first slot does not store the number of the call event
** itself, but rather the number of the call event minus one. The reason
** for this is that (a) incrementing the number stored in this slot would
** increase executable size, and (b) if the procedure is shallow traced,
** MR_trace may not be called for the call event, so we cannot shift the
** burden of initializing fields to the MR_trace of the call event either.
**
** The following macros will access the fixed slots. They can be used whenever
** MR_PROC_LAYOUT_HAS_EXEC_TRACE(entry) is true; which set you should use
** depends on the determinism of the procedure.
**
** These macros have to be kept in sync with compiler/trace.m.
*/

#define MR_event_num_framevar(base_curfr)    MR_based_framevar(base_curfr, 1)
#define MR_call_num_framevar(base_curfr)     MR_based_framevar(base_curfr, 2)
#define MR_call_depth_framevar(base_curfr)   MR_based_framevar(base_curfr, 3)

#define MR_event_num_stackvar(base_sp)	     MR_based_stackvar(base_sp, 1)
#define MR_call_num_stackvar(base_sp)	     MR_based_stackvar(base_sp, 2)
#define MR_call_depth_stackvar(base_sp)	     MR_based_stackvar(base_sp, 3)

/*
** In model_non procedures compiled with --trace-redo, one or two other items
** are stored in fixed stack slots. These are
**
**	the address of the layout structure for the redo event
**	the saved copy of the from-full flag (only if trace level is shallow)
**
** The following macros will access these slots. They should be used only from
** within the code that calls MR_trace for the REDO event.
**
** This macros have to be kept in sync with compiler/trace.m.
*/

#define MR_redo_layout_framevar(base_curfr)   MR_based_framevar(base_curfr, 4)
#define MR_redo_fromfull_framevar(base_curfr) MR_based_framevar(base_curfr, 5)

/*-------------------------------------------------------------------------*/
/*
** Definitions for MR_Module_Layout
**
** The layout structure for a module contains the following fields.
**
** The MR_ml_name field contains the name of the module.
**
** The MR_ml_string_table field contains the module's string table, which
** contains strings referred to by other layout structures in the module
** (initially only the tables containing variables names, referred to from
** label layout structures). The MR_ml_string_table_size field gives the size
** of the table in bytes.
**
** The MR_ml_procs field points to an array containing pointers to the proc
** layout structures of all the procedures in the module; the MR_ml_proc_count
** field gives the number of entries in the array.
**
** The MR_ml_module_file_layout field points to an array of N file layout
** pointers if the module has labels corresponding to contexts that refer
** to the names of N files. For each file, the table gives its name, the
** number of labels in that file in this module, and for each such label,
** it gives its line number and a pointer to its label layout struct.
** The corresponding elements of the label_lineno and label_layout arrays
** refer to the same label. (The reason why they are not stored together
** is space efficiency; adding a 16 bit field to a label layout structure would
** require padding.) The labels are sorted on line number.
**
** The MR_ml_trace_level field gives the trace level that the module was
** compiled with.  If the MR_Trace_Level enum is modified, then the
** corresponding function in compiler/trace_params.m must also be updated.
*/

typedef enum {
	MR_DEFINE_MERCURY_ENUM_CONST(MR_TRACE_LEVEL_NONE),
	MR_DEFINE_MERCURY_ENUM_CONST(MR_TRACE_LEVEL_SHALLOW),
	MR_DEFINE_MERCURY_ENUM_CONST(MR_TRACE_LEVEL_DEEP),
	MR_DEFINE_MERCURY_ENUM_CONST(MR_TRACE_LEVEL_DECL),
	MR_DEFINE_MERCURY_ENUM_CONST(MR_TRACE_LEVEL_DECL_REP)
} MR_Trace_Level;

typedef struct MR_Module_File_Layout_Struct {
	MR_ConstString			MR_mfl_filename;
	MR_Integer			MR_mfl_label_count;
	/* the following fields point to arrays of size MR_mfl_label_count */
	const MR_int_least16_t		*MR_mfl_label_lineno;
	const MR_Label_Layout		**MR_mfl_label_layout;
} MR_Module_File_Layout;

struct MR_Module_Layout_Struct {
	MR_ConstString			MR_ml_name;
	MR_Integer			MR_ml_string_table_size;
	const char			*MR_ml_string_table;
	MR_Integer			MR_ml_proc_count;
	const MR_Proc_Layout		**MR_ml_procs;
	MR_Integer			MR_ml_filename_count;
	const MR_Module_File_Layout	**MR_ml_module_file_layout;
	MR_Trace_Level			MR_ml_trace_level;
};

/*-------------------------------------------------------------------------*/
/*
** Definitions for MR_Closure_Id
**
** Each closure contains an MR_Closure_Id structure. The proc_id field
** identifies the procedure called by the closure. The other fields identify
** the context where the closure was created.
**
** The compiler generates closure id structures as either MR_User_Closure_Id
** or MR_Compiler_Closure_Id structures in order to avoid initializing the
** MR_Proc_Id union through an inappropriate member.
*/

typedef struct MR_Closure_Id_Struct {
	MR_Proc_Id		proc_id;
	MR_ConstString		module_name;
	MR_ConstString		file_name;
	MR_Integer		line_number;
	MR_ConstString		goal_path;
} MR_Closure_Id;

typedef struct MR_User_Closure_Id_Struct {
	MR_User_Proc_Id		proc_id;
	MR_ConstString		module_name;
	MR_ConstString		file_name;
	MR_Integer		line_number;
	MR_ConstString		goal_path;
} MR_User_Closure_Id;

typedef struct MR_Compiler_Closure_Id_Struct {
	MR_Compiler_Proc_Id	proc_id;
	MR_ConstString		module_name;
	MR_ConstString		file_name;
	MR_Integer		line_number;
	MR_ConstString		goal_path;
} MR_Compiler_Closure_Id;

#endif /* not MERCURY_STACK_LAYOUT_H */
