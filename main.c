/*
 * main.c - Linked List String Sorter (File I/O edition)
 *
 * Reads a list of strings from an input file, stores them in a heap-
 * allocated singly linked list, sorts them lexicographically (asc or
 * desc) by swapping the data pointers in-place, and writes the result
 * to a new file: the input file name with "_ordered_asc" or
 * "_ordered_desc" inserted before the file extension
 * (e.g. data.txt -> data_ordered_asc.txt).
 *
 * Usage:  ./sorter [--order asc|desc] <input_file>
 *
 *   --order asc   ascending sort (default)
 *   --order desc  descending sort
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <time.h>

/* ------------------------------------------------------------------ */
/*  Configuration                                                     */
/* ------------------------------------------------------------------ */

#define MAX_LENGTH 256   /* Maximum accepted length of a data line   */
#define BUF_SIZE   4096  /* Line read buffer (must be > MAX_LENGTH)  */
#define PATH_MAX_LEN 1024

/* ------------------------------------------------------------------ */
/*  Logging system                                                    */
/*                                                                    */
/*  Levels (lowest to highest severity):                              */
/*      DEBUG < INFO < WARN < ERROR                                   */
/*                                                                    */
/*  Only messages with severity >= the current level are emitted.     */
/*  The level can be overridden at runtime with the LOG_LEVEL         */
/*  environment variable: LOG_LEVEL=DEBUG|INFO|WARN|ERROR             */
/* ------------------------------------------------------------------ */

/* Logging implementation lives in logging.c. The public API and the
 * LOG_* macros are provided by logging.h.                             */
#include "logging.h"

/* Linked-list implementation lives in list.c. The Node type and the
 * list API (list_new_node / list_append / free_list) come from list.h. */
#include "list.h"

/* File I/O implementation lives in io.c. The API (build_output_path /
 * load_strings / write_output) is provided by io.h.                  */
#include "io.h"

/* Multi-threaded merge sort implementation lives in mergesort.c. The
 * public API (parallel_mergesort) is provided by mergesort.h.      */
#include "mergesort.h"

/* ------------------------------------------------------------------ */
/*  I/O helpers                                                       */
/* ------------------------------------------------------------------ */

/**
 * Parse command-line arguments.
 *
 * Usage:  ./sorter [--order asc|desc] <input_file>
 *   - input_file is required and must be exactly one positional argument;
 *   - --order defaults to ascending when omitted;
 *   - unknown options, a missing value, or a bad value are fatal.
 *
 * Returns 0 on success, -1 on failure.
 */
static int parse_args(int argc, char *argv[], const char **input,
                      int *ascending)
{
    *ascending = 1;   /* default: ascending */

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--order") == 0) {
            if (i + 1 >= argc) {
                LOG_ERROR("Missing value for --order (expected asc or desc).");
                return -1;
            }
            i++;
            if      (strcmp(argv[i], "asc")  == 0) *ascending = 1;
            else if (strcmp(argv[i], "desc") == 0) *ascending = 0;
            else {
                LOG_ERROR("Invalid --order value \"%s\" (expected asc or desc).",
                          argv[i]);
                return -1;
            }
            LOG_DEBUG("Sort order set to %s.", *ascending ? "ascending" : "descending");
        } else if (argv[i][0] == '-' && argv[i][1] != '\0') {
            LOG_ERROR("Unknown option \"%s\".", argv[i]);
            return -1;
        } else {
            if (*input != NULL) {
                LOG_ERROR("Multiple input files given (\"%s\", \"%s\").",
                          *input, argv[i]);
                return -1;
            }
            *input = argv[i];
        }
    }

    if (*input == NULL) {
        LOG_ERROR("Missing required <input_file> argument.");
        return -1;
    }
    return 0;
}

/**
 * Sort the list lexicographically using a multi-threaded merge sort.
 * Only the char* data pointers of the nodes are rewritten; the linked
 * structure itself is left untouched.
 */
static void sort_list(Node *head, int ascending)
{
    Node  *current;
    char **items = NULL, **tmp = NULL;
    int    n = 0, i = 0;

    LOG_DEBUG("Starting %s sort (multi-threaded merge sort).",
              ascending ? "ascending" : "descending");

    /* Count nodes. */
    for (current = head; current != NULL; current = current->next)
        n++;

    if (n <= 1) {
        LOG_DEBUG("Nothing to sort (%d string).", n);
        return;
    }

    /* Allocate the two scratch pointer arrays (O(n) space). */
    items = malloc((size_t)n * sizeof *items);
    tmp   = malloc((size_t)n * sizeof *tmp);
    if (!items || !tmp) {
        LOG_ERROR("Fatal: out of memory (sort buffers).");
        free(items);
        free(tmp);
        exit(EXIT_FAILURE);
    }

    /* Collect the string pointers into the array. */
    for (current = head; current != NULL; current = current->next)
        items[i++] = current->data;

    /* Multi-threaded merge sort (O(n log n)). */
    parallel_mergesort(items, tmp, n, ascending);

    /* Copy the sorted order back into the node data pointers. */
    i = 0;
    for (current = head; current != NULL; current = current->next)
        current->data = items[i++];

    free(items);
    free(tmp);
    LOG_DEBUG("Sort finished (%d strings).", n);
}

/* ------------------------------------------------------------------ */
/*  main                                                              */
/* ------------------------------------------------------------------ */

int main(int argc, char *argv[])
{
	Node        *head = NULL, *tail = NULL;
    const char  *input_path = NULL;
    char        *output_path;
    int          ascending, n, rc = 0;

    log_set_level_from_env();

    /* ---- parse command line ---- */
    if (parse_args(argc, argv, &input_path, &ascending) != 0) {
        fprintf(stderr, "Usage: %s [--order asc|desc] <input_file>\n",
                argv[0]);
        return EXIT_FAILURE;
    }

    LOG_INFO("=== Linked-List String Sorter (File I/O) ===");

    /* Wall-clock start (nanosecond precision). */
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    /* ---- parse input file ---- */
    n = load_strings(input_path, MAX_LENGTH, &head, &tail);
    if (n < 0)
        return EXIT_FAILURE;

    if (n == 0) {
        LOG_WARN("No strings to sort; nothing written.");
    } else {
        /* ---- sort ---- */
        sort_list(head, ascending);

        /* ---- derive output path & write ---- */
        output_path = build_output_path(input_path, ascending);
        LOG_INFO("Sorted list (%s):", ascending ? "ascending" : "descending");
        rc = write_output(output_path, head);
        free(output_path);
    }

    /* ---- cleanup ---- */
    free_list(head);

    /* ---- timing (emitted as an INFO log) ---- */
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long long elapsed_ns =
        (long long)(t1.tv_sec - t0.tv_sec) * 1000000000LL +
        (long long)(t1.tv_nsec - t0.tv_nsec);
    LOG_INFO("Elapsed time: %lld.%09lld s",
             elapsed_ns / 1000000000LL, elapsed_ns % 1000000000LL);

    return rc;
}
