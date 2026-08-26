#ifndef MERGESORT_H
#define MERGESORT_H

/*
 * mergesort.h - Multi-threaded merge sort for arrays of C strings
 *
 * Public API:
 *
 *   parallel_mergesort(items, tmp, n, ascending)
 *
 *     Sorts items[0, n) lexicographically (ascending or descending)
 *     using a top-down parallel merge sort. Only the char* pointers in
 *     the array are rearranged; the strings themselves are untouched.
 *
 *   items     - the array of string pointers to sort (output on return)
 *   tmp       - scratch buffer of at least n char* elements, used for
 *               merging; must not alias items
 *   n         - number of elements in items
 *   ascending - non-zero for ascending order, zero for descending
 *
 * Preconditions:
 *   - items and tmp must point to valid arrays of at least n elements.
 *   - n must be >= 0.
 *   - tmp must not overlap items.
 *
 * All internal helpers, the per-thread job struct, and the tuning
 * constants are private to mergesort.c; no global state is used.
 */

int parallel_mergesort(char **items, char **tmp, int n, int ascending);

#endif /* MERGESORT_H */
