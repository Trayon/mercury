/*
** Copyright (C) 1998 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_trace_alias.c - implements the table of aliases for the
** internal debugger.
**
** Author: zs.
*/

#include "mercury_imp.h"
#include "mercury_trace_alias.h"
#include "mercury_array_macros.h"

static	MR_Alias	*MR_alias_records = NULL;
static	int		MR_alias_record_max = 0;
static	int		MR_alias_record_next = 0;

/* The initial size of the alias table. */
#define	INIT_ALIAS_COUNT	32

static	void		MR_trace_print_alias_num(FILE *fp, int slot);

void
MR_trace_add_alias(char *name, char **words, int word_count)
{
	bool	found;
	int	slot;
	int	i;
	int	count;

	MR_bsearch(MR_alias_record_next, slot, found,
		strcmp(MR_alias_records[slot].MR_alias_name, name));
	if (found) {
		count = MR_alias_records[slot].MR_alias_word_count;
		for (i = 0; i < count; i++) {
			free(MR_alias_records[slot].MR_alias_words[i]);
		}

		free(MR_alias_records[slot].MR_alias_name);
		free(MR_alias_records[slot].MR_alias_words);
	} else {
		MR_ensure_room_for_next(MR_alias_record, MR_Alias,
			INIT_ALIAS_COUNT);
		MR_prepare_insert_into_sorted(MR_alias_records,
			MR_alias_record_next, slot,
			strcmp(MR_alias_records[slot].MR_alias_name,
				name));
	}

	MR_alias_records[slot].MR_alias_name = MR_copy_string(name);
	MR_alias_records[slot].MR_alias_word_count = word_count;
	MR_alias_records[slot].MR_alias_words = checked_malloc(word_count
							* sizeof(char *));
	for (i = 0; i < word_count; i++) {
		MR_alias_records[slot].MR_alias_words[i]
			= MR_copy_string(words[i]);
	}
}

bool
MR_trace_remove_alias(const char *name)
{
	bool	found;
	int	slot;
	int	i;
	int	count;

	MR_bsearch(MR_alias_record_next, slot, found,
		strcmp(MR_alias_records[slot].MR_alias_name, name));
	if (! found) {
		return FALSE;
	} else {
		count = MR_alias_records[slot].MR_alias_word_count;
		for (i = 0; i < count; i++) {
			free(MR_alias_records[slot].MR_alias_words[i]);
		}

		free(MR_alias_records[slot].MR_alias_name);
		free(MR_alias_records[slot].MR_alias_words);

		for (i = slot; i < MR_alias_record_next - 1; i++) {
			MR_alias_records[slot] = MR_alias_records[slot+1];
		}

		MR_alias_record_next--;

		return TRUE;
	}
}

bool
MR_trace_lookup_alias(const char *name,
	char ***words_ptr, int *word_count_ptr)
{
	bool	found;
	int	slot;

	MR_bsearch(MR_alias_record_next, slot, found,
		strcmp(MR_alias_records[slot].MR_alias_name, name));
	if (found) {
		*word_count_ptr = MR_alias_records[slot].MR_alias_word_count;
		*words_ptr = MR_alias_records[slot].MR_alias_words;
		return TRUE;
	} else {
		return FALSE;
	}
}

void
MR_trace_print_alias(FILE *fp, const char *name)
{
	bool	found;
	int	slot;

	MR_bsearch(MR_alias_record_next, slot, found,
		strcmp(MR_alias_records[slot].MR_alias_name, name));
	if (found) {
		MR_trace_print_alias_num(fp, slot);
	} else {
		fprintf(fp, "There is no such alias.\n");
	}
}

void
MR_trace_print_all_aliases(FILE *fp)
{
	int	slot;

	for (slot = 0; slot < MR_alias_record_next; slot++) {
		MR_trace_print_alias_num(fp, slot);
	}
}

static void
MR_trace_print_alias_num(FILE *fp, int slot)
{
	int	i;

	fprintf(fp, "%-6s =>   ", MR_alias_records[slot].MR_alias_name);
	for (i = 0; i < MR_alias_records[slot].MR_alias_word_count; i++) {
		fprintf(fp, " %s", MR_alias_records[slot].MR_alias_words[i]);
	}

	fprintf(fp, "\n");
}
