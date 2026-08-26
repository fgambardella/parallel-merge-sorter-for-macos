/* ------------------------------------------------------------------
 * io.h - File I/O for the sorter
 *
 * - build_output_path(): derive the output file name from the input
 *   name (inserts the "ordered_asc" / "ordered_desc" qualifier and
 *   preserves the input extension).  Searches for the extension only
 *   within the basename, not directory components.
 * - load_strings():      read lines from the input file into the list.
 * - write_output():      write the (sorted) list to the output file
 *                        atomically, preserving input permissions.
 *
 * Policy values (maximum accepted line length) are passed in by the
 * caller - no hidden globals.
 * ------------------------------------------------------------------ */
#ifndef IO_H
#define IO_H

#include <stddef.h>
#include <sys/types.h>

#include "list.h"

/**
 * Allocate the output path for the given input path.
 * Example:  "data.txt" + ascending=1  ->  "data_ordered_asc.txt"
 *
 * The extension is identified only within the basename (after the
 * last '/'), so dotted directory names are not misinterpreted.
 * A leading dot in the basename (dotfile) is not treated as an
 * extension separator.
 *
 * @param input_path  The input file path.
 * @param ascending   Non-zero for ascending, zero for descending.
 * @return A malloc'd string (caller frees) or NULL on alloc failure.
 */
char *build_output_path(const char *input_path, int ascending);

/**
 * Read lines from `path` and append each valid line to the list.
 *
 * Lines longer than max_length are skipped with a warning; blank
 * lines are skipped silently.  Embedded NUL bytes are rejected.
 * Only a trailing CRLF or LF is stripped; embedded CR is preserved.
 *
 * max_length must be strictly less than the internal buffer size
 * (4096).
 *
 * If input_mode is non-NULL, the input file's permission bits are
 * captured via fstat(fileno(fp)) while the file is still open
 * (C-M02 fix: eliminates TOCTOU window).  Falls back to 0600 if
 * fstat fails.
 *
 * Returns the number of strings loaded, or -1 on fatal error
 * (e.g. the file could not be opened).
 */
int load_strings(const char *path, size_t max_length,
                 Node **head, Node **tail, mode_t *input_mode);

/**
 * Write every string in the list to `path` atomically, one per line.
 *
 * Writes to a temporary file then renames it into place.  The output
 * file's permissions are set to `input_mode`.  Symlinks at the
 * destination are not followed.
 *
 * The caller is responsible for capturing the input file's mode
 * (e.g. via fstat on the open descriptor) and passing it here,
 * eliminating the TOCTOU window of a pathname-based stat.
 *
 * @param path        The output file path.
 * @param head        The list to write (may be NULL for empty output).
 * @param input_mode  Permission bits for the output file.
 * @return EXIT_SUCCESS on success, EXIT_FAILURE on fatal error.
 */
int write_output(const char *path, Node *head, mode_t input_mode);

#endif /* IO_H */
