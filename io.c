/*
 * io.c - File I/O for the sorter.
 * See io.h for the public API.
 */
#include "io.h"

#include "logging.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Line read buffer (must be > the max_length policy value passed by
 * the caller into load_strings).                                    */
#define BUF_SIZE 4096

/* ------------------------------------------------------------------ */
/*  Output-path construction (H-01 fix)                               */
/* ------------------------------------------------------------------ */

/**
 * Build the output path from the input path by inserting
 * "_ordered_asc" or "_ordered_desc" right before the file extension:
 *     data.txt      -> data_ordered_asc.txt
 *     data.tar.gz   -> data.tar_ordered_asc.gz
 *     data          -> data_ordered_asc
 *     /dir.d/data   -> /dir.d/data_ordered_asc   (H-01: dot in dir)
 *     .hidden       -> .hidden_ordered_asc       (leading-dot file)
 *
 * Returns a newly allocated string (caller must free) or NULL on
 * allocation failure.
 */
char *build_output_path(const char *input, int ascending)
{
    const char *suffix = ascending ? "_ordered_asc" : "_ordered_desc";
    size_t      input_len = strlen(input);
    const char *basename_start;
    const char *dot;
    size_t      stem_len;    /* length of input up to extension dot */
    size_t      len;
    char       *result;

    /* Find the basename: everything after the last '/' (or the full
     * path when there's no slash). */
    const char *last_slash = strrchr(input, '/');
    if (last_slash != NULL)
        basename_start = last_slash + 1;
    else
        basename_start = input;

    /* Search for the extension ONLY within the basename.
     * A dot at position 0 of the basename is a dotfile (e.g. ".hidden"),
     * not an extension separator.  */
    dot = strrchr(basename_start, '.');
    if (dot == NULL || dot == basename_start)
        dot = NULL;   /* no real extension */

    if (dot != NULL)
        stem_len = (size_t)(dot - input);   /* dir + stem up to dot */
    else
        stem_len = input_len;

    len = stem_len + strlen(suffix) + (dot ? strlen(dot) : 0) + 1;
    result = malloc(len);
    if (!result)
        return NULL;

    snprintf(result, len, "%.*s%s%s",
             (int)stem_len, input, suffix,
             dot ? dot : "");
    return result;
}

/* ------------------------------------------------------------------ */
/*  Input parsing (M-02, L-02 fix)                                    */
/* ------------------------------------------------------------------ */

/**
 * Drain remaining bytes of a physical line that did not fit in the
 * buffer.  Returns 0 on success, -1 on I/O error, 1 on EOF.
 */
static int drain_long_line(FILE *fp, char *buf, size_t bufsz)
{
    while (strchr(buf, '\n') == NULL) {
        if (fgets(buf, (int)bufsz, fp) == NULL)
            return ferror(fp) ? -1 : 1;
    }
    return 0;
}

/**
 * Parse the input file and append one node per valid line.
 *
 * Rules:
 *   - lines whose length (without the trailing newline) exceeds
 *     max_length are rejected with a WARN log;
 *   - empty lines are skipped (DEBUG log);
 *   - embedded NUL bytes are rejected (WARN log);
 *   - embedded CR is stripped only when it is the byte immediately
 *     before the terminating newline (CRLF), not elsewhere (M-02).
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

    if (max_length >= BUF_SIZE) {
        LOG_ERROR("max_length (%zu) must be < BUF_SIZE (%d).",
                  max_length, BUF_SIZE);
        return -1;
    }

    fp = fopen(path, "r");
    if (!fp) {
        LOG_ERROR("Cannot open input file \"%s\": %s.",
                  path, strerror(errno));
        return -1;
    }

    LOG_INFO("Reading strings from \"%s\".", path);

    while (fgets(line, sizeof(line), fp) != NULL) {
        line_no++;

        size_t slen = strlen(line);
        int has_newline = (slen > 0 && line[slen - 1] == '\n');

        /* Line did not fit in the buffer: it definitely exceeds
         * max_length (BUF_SIZE > max_length).  Consume the rest of
         * the physical line so its tail is not parsed as a new one.
         * L-02 fix: use a helper that returns error/EOF clearly. */
        if (!has_newline && slen == sizeof(line) - 1) {
            LOG_WARN("Line %d exceeds buffer; skipped.", line_no);
            int dr = drain_long_line(fp, line, sizeof(line));
            if (dr < 0) {
                LOG_ERROR("I/O error draining long line %d.", line_no);
                fclose(fp);
                return -1;
            }
            continue;
        }

        /* M-02 fix: reject embedded NUL bytes.
         * If fgets didn't find '\n' AND strlen < bufsize-1, and we're
         * not at EOF, there must be an embedded NUL byte. */
        if (!has_newline && slen < sizeof(line) - 1 && !feof(fp)) {
            LOG_WARN("Line %d contains embedded NUL byte(s); skipped.",
                     line_no);
            continue;
        }

        /* Strip only a trailing LF, or trailing CRLF.  Embedded \r is
         * NOT stripped (M-02 fix). */
        if (has_newline) {
            line[slen - 1] = '\0';
            slen--;
            if (slen > 0 && line[slen - 1] == '\r') {
                line[slen - 1] = '\0';
                slen--;
            }
        }

        if (line[0] == '\0') {
            LOG_DEBUG("Line %d is empty; skipped.", line_no);
            continue;
        }

        if (strlen(line) > max_length) {
            LOG_WARN("Line %d exceeds MAX_LENGTH (%zu); skipped.",
                     line_no, max_length);
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

/* ------------------------------------------------------------------ */
/*  Output writing (H-02, M-01 fix)                                   */
/* ------------------------------------------------------------------ */

/**
 * Write the sorted list to the output file atomically.
 *
 * Strategy (H-02):
 *   1. Write to a temporary file in the same directory.
 *   2. Check every write + fflush/fclose.
 *   3. Preserve input file permissions (M-01).
 *   4. Atomically rename to the final path.
 *   5. On failure, unlink the temp and leave previous output intact.
 *
 * Returns EXIT_SUCCESS on success, EXIT_FAILURE on I/O error.
 */
int write_output(const char *path, Node *head, const char *input_path)
{
    int          fd = -1;
    FILE        *fp = NULL;
    int          i  = 0;
    const Node  *curr;
    char        *tmppath = NULL;
    size_t       pathlen = strlen(path);
    struct stat  st;
    mode_t       mode = 0644;  /* fallback if stat fails */

    /* Determine permissions from input file (M-01). */
    if (input_path && stat(input_path, &st) == 0)
        mode = st.st_mode & 0777;

    /* Build temp file path: same directory + ".XXXXXX" suffix. */
    tmppath = malloc(pathlen + 8);
    if (!tmppath) {
        LOG_ERROR("Out of memory (temp path).");
        return EXIT_FAILURE;
    }
    snprintf(tmppath, pathlen + 8, "%s.XXXXXX", path);

    /* Create a unique temp file securely (H-02: no symlink follow). */
    fd = mkstemp(tmppath);
    if (fd < 0) {
        LOG_ERROR("Cannot create temp file \"%s\": %s.",
                  tmppath, strerror(errno));
        free(tmppath);
        return EXIT_FAILURE;
    }

    /* Set permissions before writing (M-01). */
    if (fchmod(fd, mode) != 0) {
        LOG_WARN("Cannot set permissions on \"%s\": %s.",
                 tmppath, strerror(errno));
    }

    fp = fdopen(fd, "w");
    if (!fp) {
        LOG_ERROR("Cannot fdopen temp file \"%s\": %s.",
                  tmppath, strerror(errno));
        close(fd);
        unlink(tmppath);
        free(tmppath);
        return EXIT_FAILURE;
    }

    curr = head;
    while (curr) {
        if (fprintf(fp, "%s\n", curr->data) < 0) {
            LOG_ERROR("Write error on \"%s\": %s.",
                      tmppath, strerror(errno));
            fclose(fp);
            unlink(tmppath);
            free(tmppath);
            return EXIT_FAILURE;
        }
        curr = curr->next;
        i++;
    }

    /* Flush and close, checking for delayed write errors. */
    if (fflush(fp) != 0 || fclose(fp) != 0) {
        LOG_ERROR("Error finalizing \"%s\": %s.",
                  tmppath, strerror(errno));
        unlink(tmppath);
        free(tmppath);
        return EXIT_FAILURE;
    }

    /* Atomically publish the output (H-02). */
    if (rename(tmppath, path) != 0) {
        LOG_ERROR("Cannot rename \"%s\" -> \"%s\": %s.",
                  tmppath, path, strerror(errno));
        unlink(tmppath);
        free(tmppath);
        return EXIT_FAILURE;
    }

    free(tmppath);
    LOG_INFO("Wrote %d string(s) to \"%s\".", i, path);
    return EXIT_SUCCESS;
}
