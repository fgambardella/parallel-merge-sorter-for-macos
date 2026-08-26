/* ------------------------------------------------------------------
 * io.h - File I/O for the sorter
 *
 * - build_output_path(): derive the output file name from the input
 *   name (inserts the "ordered_asc" / "ordered_desc" qualifier and
 *   preserves the input extension).
 * - load_strings():      read lines from the input file into the list.
 * - write_output():      write the (sorted) list to the output file.
 *
 * Policy values (maximum accepted line length) are passed in by the
 * caller - no hidden globals.
 * ------------------------------------------------------------------ */
#ifndef IO_H
#define IO_H

#include <stddef.h>

#include "list.h"

/**
 * Allocate the output path for the given input path.
 * Example:  "data.txt" + desc=false  ->  "data_ordered_asc.txt"
 *
 * Returns a malloc'd string (caller frees) or NULL on failure.
 */
char *build_output_path(const char *input_path, int desc);

/**
 * Read lines from `path` and append each valid line to the list.
 *
 * Lines longer than max_length are skipped with a warning; blank
 * lines are skipped silently.
 *
 * Returns the number of strings loaded, or -1 on fatal error
 * (e.g. the file could not be opened).
 */
int load_strings(const char *path, size_t max_length,
                 Node **head, Node **tail);

/**
 * Write every string in the list to `path`, one per line.
 *
 * Returns EXIT_SUCCESS, or EXIT_FAILURE on fatal error.
 */
int write_output(const char *path, Node *head);

#endif /* IO_H */