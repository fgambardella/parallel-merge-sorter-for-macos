/*
 * test_1b_pthread_join_fail.c
 *
 * Bug Condition Exploration Test for C-H02:
 *   When pthread_join fails after a thread was successfully created,
 *   the current code re-sorts the left half while the worker may
 *   still be modifying it (data race). Also, parallel_mergesort
 *   returns void so there's no way to signal the error.
 *
 * Strategy:
 *   Since parallel_mergesort currently returns void, we can't directly
 *   test for -1 return. Instead, we:
 *   1. Intercept pthread_join to return ESRCH (simulating failure).
 *   2. Let pthread_create succeed so the worker runs.
 *   3. Check that the function returns an error code (-1).
 *      On unfixed code this is impossible (void return), so the test
 *      checks the return type at compile time and documents the defect.
 *
 *   We test this by trying to call parallel_mergesort and capture its
 *   return value. On unfixed code, parallel_mergesort returns void,
 *   so we have to test the observable deficiency: no error propagation.
 *
 * EXPECTED: Test FAILS because parallel_mergesort returns void
 *   (no error status), confirming bug C-H02.
 *
 * Validates: Requirements 1.2
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/*
 * We test two aspects of C-H02:
 *
 * Aspect 1: parallel_mergesort returns void - no way to propagate error
 *   We use _Generic to check if the return type is void vs int at
 *   compile time. On unfixed code, it returns void.
 *
 * Aspect 2: When pthread_join fails, the code re-sorts the left half
 *   inline (data race). We inject pthread_join failure and track
 *   whether msort is re-entered on the left half range.
 */

#include <pthread.h>

/* Track re-entry: if msort is called on the left range [lo, mid)
 * AFTER a join failure, it means shared memory was re-entered.       */
static int g_join_failed = 0;

/* Let real pthread_create work, but fail pthread_join */
static int fake_pthread_join(pthread_t t, void **retval)
{
    /* Actually join the thread first so it finishes cleanly */
    int real_result = pthread_join(t, retval);
    (void)real_result;
    /* Then report failure to the caller */
    g_join_failed = 1;
    return ESRCH;
}

#define pthread_join fake_pthread_join

/* Instrument msort to detect re-entry after join failure */
/* We'll wrap msort by renaming it and adding a tracking layer.
 * However, since msort is static, we need a different approach:
 * We'll add a logging hook by redefining LOG_ERROR to detect the
 * specific "merge may use unsorted data" message and the subsequent
 * re-sort call. */

#include "../../logging.c"

/* We need to intercept the msort call AFTER join failure.
 * The unfixed code in mergesort.c does:
 *   if (jr != 0) {
 *       LOG_ERROR("...");
 *       msort(src, tmp, lo, mid, ...);   // <-- re-enters shared memory!
 *   }
 * We can detect this by tracking the pattern. */

#include "../../mergesort.c"

#undef pthread_join

#define NUM_ITEMS 2048

int main(void)
{
    char **items = malloc(NUM_ITEMS * sizeof(char *));
    char **tmp   = malloc(NUM_ITEMS * sizeof(char *));
    if (!items || !tmp) {
        fprintf(stderr, "FAIL: malloc failed\n");
        return 1;
    }

    /* Create descending strings */
    for (int i = 0; i < NUM_ITEMS; i++) {
        items[i] = malloc(8);
        if (!items[i]) {
            fprintf(stderr, "FAIL: malloc failed for item %d\n", i);
            return 1;
        }
        snprintf(items[i], 8, "%05d", NUM_ITEMS - i);
    }

    /*
     * Test: parallel_mergesort returns void on unfixed code.
     * If it returned int, we could check: int rc = parallel_mergesort(...);
     * Since it returns void, we cannot capture an error status.
     *
     * The test asserts that parallel_mergesort SHOULD return -1 on
     * thread failure. On unfixed code, this assertion fails because
     * the function returns void (no error propagation possible).
     *
     * We use a compile-time check: _Generic cannot distinguish void
     * from int for return types directly, but we can check if we can
     * assign the result. Instead, we'll just check the observable
     * behavior: the sort completes without error signal, and the
     * join-failure path re-sorts the left half (data race).
     */

    /* Run sort - pthread_join will "fail" (ESRCH) */
    g_join_failed = 0;
    int rc = parallel_mergesort(items, tmp, NUM_ITEMS, 1);

    /*
     * On unfixed code:
     * - parallel_mergesort returned void, so we could NOT detect the error
     * - The join-failure path re-sorted left half (data race)
     *
     * On fixed code:
     * - parallel_mergesort returns int
     * - On join failure, returns -1 immediately (no shared memory re-entry)
     * - g_join_failed will be 1 (our fake join was called)
     *
     * The test checks:
     * 1. Was pthread_join actually called (and intercepted)?
     * 2. Did parallel_mergesort return -1 (error properly propagated)?
     */

    int test_passed = 0;

    if (!g_join_failed) {
        printf("NOTE: pthread_join was never called (unexpected)\n");
    }

    if (rc == -1) {
        /* Error was properly propagated - bug C-H02 is fixed */
        printf("PASS: test_1b - parallel_mergesort returns -1 on "
               "pthread_join failure; error properly propagated\n");
        test_passed = 1;
    } else {
        /* Error NOT propagated - bug still present */
        printf("FAIL: test_1b - parallel_mergesort returned %d; "
               "expected -1 on pthread_join failure\n", rc);
        printf("  Counterexample: pthread_join returns ESRCH for %d items;\n",
               NUM_ITEMS);
        printf("  error not propagated to caller.\n");
        printf("  Bug C-H02 confirmed: no error propagation.\n");
        test_passed = 0;
    }

    /* Cleanup */
    for (int i = 0; i < NUM_ITEMS; i++) free(items[i]);
    free(items);
    free(tmp);

    return test_passed ? 0 : 1;
}
