/*
 * test_1a_pthread_create_fail.c
 *
 * Bug Condition Exploration Test for C-H01:
 *   When pthread_create fails in msort(), the right half [mid, hi)
 *   is never sorted before merge, producing incorrectly sorted output.
 *
 * Strategy:
 *   Intercept pthread_create via macro to always return EAGAIN.
 *   Create a descending array of 2048 strings (above MSORT_BASE_CASE=1024).
 *   Call parallel_mergesort and verify the output is correctly sorted.
 *
 * EXPECTED: Test FAILS on unfixed code because only the left half is
 *   sorted; the right half remains in its original (descending) order.
 *
 * Validates: Requirements 1.1
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* ---- Fault injection: intercept pthread_create ---- */
#include <pthread.h>

/* We need a real pthread_join for cleanup. Save original symbols. */
static int fake_pthread_create(pthread_t *t, const pthread_attr_t *a,
                               void *(*start)(void *), void *arg)
{
    (void)t; (void)a; (void)start; (void)arg;
    return EAGAIN;  /* Always fail */
}

/* Redirect pthread_create calls in mergesort.c to our fake */
#define pthread_create fake_pthread_create

/* Include the production source directly so the macro takes effect */
#include "../../logging.c"
#include "../../mergesort.c"

/* Undo the macro so we don't affect later code */
#undef pthread_create

#define NUM_ITEMS 2048

int main(void)
{
    char **items = malloc(NUM_ITEMS * sizeof(char *));
    char **tmp   = malloc(NUM_ITEMS * sizeof(char *));
    if (!items || !tmp) {
        fprintf(stderr, "FAIL: malloc failed\n");
        return 1;
    }

    /* Create descending strings: "02048", "02047", ..., "00001" */
    for (int i = 0; i < NUM_ITEMS; i++) {
        items[i] = malloc(8);
        if (!items[i]) {
            fprintf(stderr, "FAIL: malloc failed for item %d\n", i);
            return 1;
        }
        snprintf(items[i], 8, "%05d", NUM_ITEMS - i);
    }

    /* Sort ascending with all pthread_create calls failing */
    parallel_mergesort(items, tmp, NUM_ITEMS, 1);

    /* Verify: output must be sorted ascending */
    int sorted = 1;
    int first_unsorted = -1;
    for (int i = 0; i < NUM_ITEMS - 1; i++) {
        if (strcmp(items[i], items[i + 1]) > 0) {
            if (first_unsorted < 0) first_unsorted = i;
            sorted = 0;
        }
    }

    if (sorted) {
        printf("PASS: test_1a - output correctly sorted despite pthread_create failure\n");
    } else {
        printf("FAIL: test_1a - output NOT sorted at index %d: \"%s\" > \"%s\"\n",
               first_unsorted, items[first_unsorted], items[first_unsorted + 1]);
        printf("  Counterexample: pthread_create returns EAGAIN for %d items;\n", NUM_ITEMS);
        printf("  right half [%d, %d) was not sorted before merge.\n",
               NUM_ITEMS / 2, NUM_ITEMS);
        printf("  Bug C-H01 confirmed: only left half sorted, right half unsorted.\n");
    }

    /* Cleanup */
    for (int i = 0; i < NUM_ITEMS; i++) free(items[i]);
    free(items);
    free(tmp);

    return sorted ? 0 : 1;
}
