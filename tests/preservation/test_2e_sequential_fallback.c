/*
 * test_2e_sequential_fallback.c
 *
 * Preservation Property Test 2e: Sequential fallback preservation
 *
 * When MSortJob allocation fails (depth < MSORT_MAX_DEPTH), the system
 * degrades gracefully to fully sequential sorting of both halves, and
 * the output is correct.
 *
 * Strategy: Use macro interposition on malloc to fail ONLY for
 * MSortJob-sized allocations (sizeof(MSortJob) = the per-thread job
 * struct), while allowing all other allocations to succeed normally.
 * This exercises the existing OOM fallback in msort() at line ~98-103.
 *
 * Validates: Requirements 3.2
 * EXPECTED: Test PASSES on unfixed code (MSortJob OOM fallback works)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

/* ---- Fault injection: fail malloc only for MSortJob-sized allocs ---- */

/*
 * We need to know the size of MSortJob. Looking at mergesort.c, it is:
 *   typedef struct {
 *       char    **src;      // 8 bytes (64-bit)
 *       char    **tmp;      // 8 bytes
 *       int       lo, hi;   // 4 + 4 bytes
 *       int       ascending; // 4 bytes
 *       int       depth;    // 4 bytes
 *   } MSortJob;
 * Total: 32 bytes on 64-bit (with padding).
 *
 * But instead of hard-coding, we'll include mergesort.c and use its
 * actual sizeof.
 */

/* Flag to control whether MSortJob-sized mallocs fail */
static int g_fail_job_malloc = 0;
static size_t g_job_size = 0;  /* Will be set after MSortJob is defined */

/* Save the real malloc */
static void *real_malloc(size_t size)
{
    /* On macOS, we can just call the real malloc since we only
     * interpose at the source level in mergesort.c */
    extern void *malloc(size_t);
    return malloc(size);
}

/* Our intercepting malloc */
static void *fake_malloc(size_t size)
{
    if (g_fail_job_malloc && size == g_job_size) {
        return NULL;  /* Fail MSortJob allocation */
    }
    return real_malloc(size);
}

/* Interpose malloc in mergesort.c only */
#define malloc fake_malloc

/* Include production sources */
#include "../../logging.c"
#include "../../mergesort.c"

/* Undo the macro */
#undef malloc

/* ------------------------------------------------------------------ */
/*  Deterministic PRNG (xorshift32)                                   */
/* ------------------------------------------------------------------ */

static unsigned int rng_state;

static void rng_seed(unsigned int seed) { rng_state = seed; }

static unsigned int rng_next(void)
{
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}

/* ------------------------------------------------------------------ */
/*  Verification helpers                                              */
/* ------------------------------------------------------------------ */

static int is_sorted_asc(char **arr, int n)
{
    for (int i = 0; i < n - 1; i++)
        if (strcmp(arr[i], arr[i + 1]) > 0)
            return 0;
    return 1;
}

static int is_sorted_desc(char **arr, int n)
{
    for (int i = 0; i < n - 1; i++)
        if (strcmp(arr[i], arr[i + 1]) < 0)
            return 0;
    return 1;
}

/* ------------------------------------------------------------------ */
/*  Test runner                                                       */
/* ------------------------------------------------------------------ */

/* Test sizes that exercise the parallel paths (> MSORT_BASE_CASE=1024) */
static const int test_sizes[] = {
    1025, 1500, 2048, 3000, 5000, 8000, 10000
};
#define NUM_SIZES (int)(sizeof(test_sizes) / sizeof(test_sizes[0]))
#define TRIALS_PER_SIZE 3

int main(void)
{
    int total_pass = 0, total_fail = 0;

    log_set_level(LOG_LEVEL_ERROR);

    /* Determine the size of MSortJob from the included mergesort.c */
    g_job_size = sizeof(MSortJob);

    printf("Test 2e: Sequential fallback preservation (MSortJob OOM)\n");
    printf("=========================================================\n");
    printf("  MSortJob size: %zu bytes\n", g_job_size);

    rng_seed(20260822u);

    for (int si = 0; si < NUM_SIZES; si++) {
        int n = test_sizes[si];

        for (int trial = 0; trial < TRIALS_PER_SIZE; trial++) {
            char **items = malloc((size_t)n * sizeof(char *));
            char **tmp   = malloc((size_t)n * sizeof(char *));
            char **orig  = malloc((size_t)n * sizeof(char *));
            if (!items || !tmp || !orig) {
                fprintf(stderr, "FAIL: test alloc failed\n");
                return 1;
            }

            /* Generate random strings */
            for (int i = 0; i < n; i++) {
                int len = 3 + (int)(rng_next() % 15);
                items[i] = malloc((size_t)len + 1);
                if (!items[i]) {
                    fprintf(stderr, "FAIL: string alloc failed\n");
                    return 1;
                }
                for (int j = 0; j < len; j++)
                    items[i][j] = (char)(0x41 + (rng_next() % 26));
                items[i][len] = '\0';
            }

            memcpy(orig, items, (size_t)n * sizeof(char *));

            /* Enable MSortJob malloc failure */
            g_fail_job_malloc = 1;

            /* ---- Test ascending sort with job malloc failure ---- */
            parallel_mergesort(items, tmp, n, 1);

            g_fail_job_malloc = 0;

            if (!is_sorted_asc(items, n)) {
                printf("FAIL: n=%d trial=%d ascending - not sorted with job OOM\n",
                       n, trial);
                total_fail++;
            } else {
                total_pass++;
            }

            /* Reset for descending */
            memcpy(items, orig, (size_t)n * sizeof(char *));

            g_fail_job_malloc = 1;
            parallel_mergesort(items, tmp, n, 0);
            g_fail_job_malloc = 0;

            if (!is_sorted_desc(items, n)) {
                printf("FAIL: n=%d trial=%d descending - not sorted with job OOM\n",
                       n, trial);
                total_fail++;
            } else {
                total_pass++;
            }

            /* Cleanup */
            for (int i = 0; i < n; i++) free(orig[i]);
            free(items);
            free(tmp);
            free(orig);
        }
    }

    printf("\n");
    printf("Results: %d passed, %d failed\n", total_pass, total_fail);

    if (total_fail == 0) {
        printf("PASS: test_2e - sequential fallback preserves sort correctness\n");
        return 0;
    } else {
        printf("FAIL: test_2e - sequential fallback failures found\n");
        return 1;
    }
}
