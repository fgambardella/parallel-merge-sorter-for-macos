/*
 * mergesort.c - Multi-threaded merge sort for arrays of C strings
 *
 * Implementation details (all private to this file):
 *   - ranges larger than MSORT_BASE_CASE are split in half and the two
 *     halves are sorted concurrently (left half in a child thread,
 *     right half in the current thread);
 *   - the number of parallel fork levels is capped at MSORT_MAX_DEPTH,
 *     bounding the total thread count (<= 2^MSORT_MAX_DEPTH);
 *   - sorted halves are merged into a secondary scratch buffer;
 *   - base cases (<= MSORT_BASE_CASE items) use insertion sort.
 *
 * Only the char* pointers in the caller's array are rearranged; the
 * pointed-to strings are never modified. No global variables are used:
 * all state travels through function parameters or per-thread job
 * structs, so every function here is thread-safe.
 *
 * Time: O(n log n)   Space: O(n) (the caller supplies the scratch array)
 */

#include "mergesort.h"

#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "logging.h"

/* ------------------------------------------------------------------ */
/*  Tuning constants (private)                                        */
/* ------------------------------------------------------------------ */

#define MSORT_BASE_CASE 1024  /* sort ranges <= this size sequentially */
#define MSORT_MAX_DEPTH 4     /* max parallel fork levels (<= 16 threads) */

/* ------------------------------------------------------------------ */
/*  Internal helpers (private)                                        */
/* ------------------------------------------------------------------ */

/* Per-job description for a worker thread. */
typedef struct {
    char    **src;      /* source buffer (this job's working array) */
    char    **tmp;      /* merge destination scratch buffer         */
    int       lo, hi;   /* half-open range [lo, hi)                 */
    int       ascending;
    int       depth;    /* current fork depth                       */
} MSortJob;

/* Forward declaration (recursive). */
static int msort(char **src, char **tmp, int lo, int hi,
                 int ascending, int depth);

/* Entry point for a worker thread: sort its job's range, then free. */
static void *msort_worker(void *arg)
{
    MSortJob *job = arg;

    int rc = msort(job->src, job->tmp, job->lo, job->hi,
                   job->ascending, job->depth);
    free(job);
    return rc == 0 ? NULL : (void *)(intptr_t)-1;
}

/**
 * Parallel top-down merge sort of src[lo, hi) using tmp as scratch.
 * On return, src[lo, hi) holds the sorted pointers.
 */
static int msort(char **src, char **tmp, int lo, int hi,
                 int ascending, int depth)
{
    int n = hi - lo;

    /* ---- base case: direction-aware insertion sort ---- */
    if (n <= MSORT_BASE_CASE) {
        int i;
        for (i = lo + 1; i < hi; i++) {
            char *key = src[i];
            int j = i - 1;
            while (j >= lo &&
                   (ascending
                    ? strcmp(src[j], key) > 0
                    : strcmp(src[j], key) < 0)) {
                src[j + 1] = src[j];
                j--;
            }
            src[j + 1] = key;
        }
        return 0;
    }

    int mid = lo + n / 2;

    if (depth < MSORT_MAX_DEPTH) {
        /* Sort the left half in a child thread, right half here. */
        MSortJob *job = malloc(sizeof *job);
        if (!job) {
            /* Out of memory: degrade to fully sequential. */
            LOG_DEBUG("msort: OOM at depth %d, sorting sequentially.",
                      depth);
            if (msort(src, tmp, lo, mid, ascending, depth + 1) != 0)
                return -1;
            if (msort(src, tmp, mid, hi, ascending, depth + 1) != 0)
                return -1;
        } else {
            pthread_t tid;
            job->src       = src;
            job->tmp       = tmp;
            job->lo        = lo;
            job->hi        = mid;
            job->ascending = ascending;
            job->depth     = depth + 1;

            if (pthread_create(&tid, NULL, msort_worker, job) != 0) {
                /* Thread creation failed: sort both halves inline. */
                LOG_DEBUG("msort: pthread_create failed, sorting inline.");
                free(job);
                if (msort(src, tmp, lo, mid, ascending, depth + 1) != 0)
                    return -1;
                if (msort(src, tmp, mid, hi, ascending, depth + 1) != 0)
                    return -1;
            } else {
                if (msort(src, tmp, mid, hi, ascending, depth + 1) != 0)
                    return -1;
                void *worker_ret = NULL;
                int jr = pthread_join(tid, &worker_ret);
                if (jr != 0) {
                    LOG_ERROR("msort: pthread_join failed (err=%d); "
                              "aborting sort.", jr);
                    return -1;
                }
                if (worker_ret != NULL) {
                    LOG_ERROR("msort: worker thread reported failure.");
                    return -1;
                }
            }
        }
    } else {
        /* Fork depth cap reached: sort both halves sequentially. */
        if (msort(src, tmp, lo, mid, ascending, depth + 1) != 0)
            return -1;
        if (msort(src, tmp, mid, hi, ascending, depth + 1) != 0)
            return -1;
    }

    /* ---- merge src[lo, mid) and src[mid, hi) into tmp, copy back ---- */
    int i = lo, j = mid, k = lo;
    while (i < mid && j < hi) {
        int c = strcmp(src[i], src[j]);
        if (ascending ? c <= 0 : c >= 0)
            tmp[k++] = src[i++];
        else
            tmp[k++] = src[j++];
    }
    while (i < mid) tmp[k++] = src[i++];
    while (j < hi)  tmp[k++] = src[j++];
    memcpy(src + lo, tmp + lo, (size_t)(hi - lo) * sizeof *src);
    return 0;
}

/* ------------------------------------------------------------------ */
/*  Public API                                                        */
/* ------------------------------------------------------------------ */

/**
 * Sort items[0, n) lexicographically using a multi-threaded merge sort.
 * items holds the sorted pointers on return; tmp must be scratch space
 * for n char* elements that does not alias items.
 */
int parallel_mergesort(char **items, char **tmp, int n, int ascending)
{
    if (n <= 0)
        return 0;
    return msort(items, tmp, 0, n, ascending, 0);
}
