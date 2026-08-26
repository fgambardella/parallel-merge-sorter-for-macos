/*
 * io.c - File I/O for the sorter.
 * See io.h for the public API.
 */
#include "io.h"

#include "logging.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Line read buffer (must be > the max_length policy value passed by
 * the caller into load_strings).                                    */
#define BUF_SIZE 4096

/**
 * Build the output path from the input path by inserting
 * "_ordered_asc" or "_ordered_desc" right before the file extension:
 *     data.txt      -> data_ordered_asc.txt
 *     data.tar.gz   -> data.tar_ordered_asc.gz
 *     data          -> data_ordered_asc
 * Returns a newly allocated string (caller must free) or NULL on
 * allocation failure.
 */
char *build_output_path(const char *input, int ascending)
{
    const char *suffix = ascending ? "_ordered_asc" : "_ordered_desc";
    const char *dot    = strrchr(input, '.');
    const char *base;
    size_t      base_len, len;
    char       *result;

    /* Require a real extension: a dot at position 0 (hidden file,
     * e.g. ".gitignore") or a missing dot means "no extension".     */
    if (dot != NULL && dot != input)
        base_len = (size_t)(dot - input);
    else
        base_len = strlen(input);

    len = base_len + strlen(suffix) + strlen(dot != NULL && dot != input
                                             ? dot : "") + 1;
    result = malloc(len);
    if (!result) {
        LOG_ERROR("Fatal: out of memory (output path).");
        exit(EXIT_FAILURE);
    }

    base = input;
    snprintf(result, len, "%.*s%s%s",
             (int)base_len, base, suffix,
             (dot != NULL && dot != input) ? dot : "");
    return result;
}

/**
 * Parse the input file and append one node per valid line.
 *
 * Rules:
 *   - lines whose length (without the trailing newline) exceeds
 *     max_length are rejected with a WARN log;
 *   - empty / whitespace-only lines are skipped (DEBUG log);
 *   - read errors and a file whose lines don't fit in BUF_SIZE are
 *     reported as WARN and the offending line is skipped.
 *
 * Returns the number of strings loaded, or -1 on fatal I/O errors.
 */
int load_strings(const char *path, size_t max_length,
                 Node **head, Node **tail)
{
    FILE *fp;
    char  line[BUF_SIZE];
    int   line_no = 0, count = 0;

    fp = fopen(path, "r");
    if (!fp) {
        LOG_ERROR("Cannot open input file \"%s\".", path);
        return -1;
    }

    LOG_INFO("Reading strings from \"%s\".", path);

    while (fgets(line, sizeof(line), fp) != NULL) {
        line_no++;

        /* Line did not fit in the buffer: it definitely exceeds
         * max_length (BUF_SIZE > max_length).  Consume the rest of
         * the physical line so its tail is not parsed as a new one. */
        if (strchr(line, '\n') == NULL &&
            strlen(line) == sizeof(line) - 1) {
            LOG_WARN("Line %d exceeds MAX_LENGTH (%d); skipped.",
                     line_no, (int)max_length);
            while (strchr(line, '\n') == NULL &&
                   fgets(line, sizeof(line), fp) != NULL)
                line_no++;
            continue;
        }

        line[strcspn(line, "\r\n")] = '\0';

        if (line[0] == '\0') {
            LOG_DEBUG("Line %d is empty; skipped.", line_no);
            continue;
        }

        if ((int)strlen(line) > (int)max_length) {
            LOG_WARN("Line %d exceeds MAX_LENGTH (%d); skipped.",
                     line_no, (int)max_length);
            continue;
        }

        list_append(head, tail, line);
        count++;
    }

    if (ferror(fp)) {
        LOG_ERROR("I/O error while reading \"%s\".", path);
        fclose(fp);
        return -1;
    }

    fclose(fp);
    LOG_INFO("Loaded %d string(s) from \"%s\".", count, path);
    return count;
}

/**
 * Write the sorted list to the output file, one plain string per line.
 * Returns EXIT_SUCCESS on success, EXIT_FAILURE on I/O error.
 */
int write_output(const char *path, Node *head)
{
    FILE *fp;
    int   i = 0;
    const Node *curr;

    fp = fopen(path, "w");
    if (!fp) {
        LOG_ERROR("Cannot open output file \"%s\".", path);
        return EXIT_FAILURE;
    }

    curr = head;
    while (curr) {
        fprintf(fp, "%s\n", curr->data);
        curr = curr->next;
        i++;
    }

    if (fclose(fp) != 0) {
        LOG_ERROR("Error closing output file \"%s\".", path);
        return EXIT_FAILURE;
    }

    LOG_INFO("Wrote %d string(s) to \"%s\".", i, path);
    return EXIT_SUCCESS;
}