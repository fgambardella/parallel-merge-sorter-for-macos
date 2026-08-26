/*
 * test_1e_oom_list.c
 *
 * Bug Condition Exploration Test for C-M05:
 *   When memory allocation fails inside list_new_node(), the system
 *   calls exit(EXIT_FAILURE) immediately, bypassing cleanup of the
 *   open input file, partial list, and centralized error path.
 *
 * Strategy:
 *   Intercept malloc via macro to fail after N successful allocations.
 *   Call list_new_node and check if it returns NULL (expected fix) or
 *   exits the process (current buggy behavior).
 *
 *   We fork a child process to call list_new_node with failing malloc.
 *   If the child exits with EXIT_FAILURE (status 1), it means
 *   list_new_node called exit() instead of returning NULL.
 *
 * EXPECTED: Test FAILS because list_new_node calls exit(EXIT_FAILURE)
 *   instead of returning NULL to the caller.
 *
 * Validates: Requirements 1.7
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

/* ---- Fault injection for malloc ---- */
static int g_malloc_fail_enabled = 0;
static int g_malloc_call_count = 0;
static int g_malloc_fail_after = 0;  /* Fail after this many successful calls */

static void *fake_malloc(size_t size)
{
    extern void *malloc(size_t) __asm("_malloc");
    if (g_malloc_fail_enabled) {
        g_malloc_call_count++;
        if (g_malloc_call_count > g_malloc_fail_after) {
            return NULL;  /* Simulate OOM */
        }
    }
    return malloc(size);
}

#define malloc fake_malloc

/* Include production sources */
#include "../../logging.c"
#include "../../list.c"

#undef malloc

int main(void)
{
    /*
     * Test: list_new_node should return NULL on malloc failure.
     * On unfixed code, it calls exit(EXIT_FAILURE) instead.
     *
     * We use fork() to safely test whether exit() is called:
     * - Child: enable malloc failure, call list_new_node
     * - Parent: check child's exit status
     *
     * If child exits with status 1 (EXIT_FAILURE): exit() was called (bug)
     * If child exits with status 0: list_new_node returned NULL (fixed)
     */

    pid_t pid = fork();
    if (pid < 0) {
        perror("fork");
        return 1;
    }

    if (pid == 0) {
        /* ---- Child process ---- */
        /* Make malloc fail on the very first call (node allocation) */
        g_malloc_fail_enabled = 1;
        g_malloc_fail_after = 0;  /* Fail immediately */
        g_malloc_call_count = 0;

        Node *result = list_new_node("test_string");

        if (result == NULL) {
            /* Good: function returned NULL instead of calling exit() */
            _exit(0);
        } else {
            /* Unexpected: allocation somehow succeeded despite fake_malloc */
            _exit(2);
        }
        /* If list_new_node calls exit(EXIT_FAILURE), we'll never reach here.
         * The child process will exit with status 1. */
    }

    /* ---- Parent process ---- */
    int status;
    waitpid(pid, &status, 0);

    int test_passed = 1;

    if (WIFEXITED(status)) {
        int exit_code = WEXITSTATUS(status);
        if (exit_code == 0) {
            printf("PASS: test_1e - list_new_node returned NULL on malloc failure\n");
        } else if (exit_code == 1) {
            printf("FAIL: test_1e - list_new_node called exit(EXIT_FAILURE) "
                   "on malloc failure\n");
            printf("  Counterexample: malloc returns NULL for node allocation;\n");
            printf("  list_new_node calls exit(1) instead of returning NULL.\n");
            printf("  This bypasses cleanup: open file descriptors leaked,\n");
            printf("  partial list not freed, error path not taken.\n");
            printf("  Bug C-M05 confirmed: fatal exit on OOM.\n");
            test_passed = 0;
        } else if (exit_code == 2) {
            printf("ERROR: malloc succeeded despite injection (test setup issue)\n");
            test_passed = 0;
        } else {
            printf("ERROR: child exited with unexpected code %d\n", exit_code);
            test_passed = 0;
        }
    } else if (WIFSIGNALED(status)) {
        printf("ERROR: child killed by signal %d\n", WTERMSIG(status));
        test_passed = 0;
    }

    return test_passed ? 0 : 1;
}
