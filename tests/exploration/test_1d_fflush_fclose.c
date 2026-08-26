/*
 * test_1d_fflush_fclose.c
 *
 * Bug Condition Exploration Test for C-L01:
 *   When fflush(fp) fails during output finalization, the || operator
 *   short-circuits and fclose(fp) is never called, leaking the fd.
 *
 * Strategy:
 *   Intercept fflush via macro to return EOF (failure) for the output
 *   file. Track whether fclose is called after fflush failure.
 *   On unfixed code, the `||` short-circuit skips fclose.
 *
 *   We include io.c directly with fflush/fclose interception macros.
 *
 * EXPECTED: Test FAILS because fclose is not called after fflush failure.
 *
 * Validates: Requirements 1.8
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

/* ---- Fault injection state ---- */
static int g_fflush_should_fail = 0;
static int g_fflush_called = 0;
static int g_fclose_called_after_fflush_fail = 0;
static int g_fflush_failed = 0;
static FILE *g_tracked_fp = NULL;

/* ---- Wrap fflush ---- */
static int real_fflush(FILE *fp) {
    /* Call the actual fflush from libc */
    extern int fflush(FILE *) __asm("_fflush");
    return fflush(fp);
}

static int fake_fflush(FILE *fp)
{
    if (g_fflush_should_fail && fp == g_tracked_fp) {
        g_fflush_called = 1;
        g_fflush_failed = 1;
        return EOF;  /* Simulate failure */
    }
    return real_fflush(fp);
}

/* ---- Wrap fclose ---- */
static int real_fclose(FILE *fp) {
    extern int fclose(FILE *) __asm("_fclose");
    return fclose(fp);
}

static int fake_fclose(FILE *fp)
{
    if (fp == g_tracked_fp && g_fflush_failed) {
        g_fclose_called_after_fflush_fail = 1;
    }
    return real_fclose(fp);
}

/* ---- Wrap fdopen to track the output FILE* ---- */
static FILE *real_fdopen(int fd, const char *mode) {
    extern FILE *fdopen(int, const char *) __asm("_fdopen");
    return fdopen(fd, mode);
}

static FILE *fake_fdopen(int fd, const char *mode)
{
    FILE *fp = real_fdopen(fd, mode);
    if (fp && g_fflush_should_fail) {
        g_tracked_fp = fp;  /* Track the FILE* opened in write_output */
    }
    return fp;
}

#define fflush fake_fflush
#define fclose fake_fclose
#define fdopen fake_fdopen

/* Include production sources */
#include "../../logging.c"
#include "../../list.c"
#include "../../io.c"

#undef fflush
#undef fclose
#undef fdopen

int main(void)
{
    char tmpdir[] = "/tmp/test_1d_XXXXXX";
    if (mkdtemp(tmpdir) == NULL) {
        perror("mkdtemp");
        return 1;
    }

    /* Create a simple input file */
    char input_path[256], output_path[256];
    snprintf(input_path, sizeof(input_path), "%s/input.txt", tmpdir);
    snprintf(output_path, sizeof(output_path), "%s/output.txt", tmpdir);

    FILE *f = fopen(input_path, "w");
    fprintf(f, "hello\nworld\n");
    fclose(f);

    /* Build a simple list to write */
    Node *head = NULL, *tail = NULL;
    list_append(&head, &tail, "hello");
    list_append(&head, &tail, "world");

    /* Enable fault injection: make fflush fail */
    g_fflush_should_fail = 1;
    g_fflush_called = 0;
    g_fclose_called_after_fflush_fail = 0;
    g_fflush_failed = 0;
    g_tracked_fp = NULL;

    /* Call write_output - fflush will fail */
    write_output(output_path, head, (mode_t)0644);

    int test_passed = 1;

    if (!g_fflush_failed) {
        printf("ERROR: fflush was never triggered to fail (test setup issue)\n");
        test_passed = 0;
    } else if (g_fclose_called_after_fflush_fail) {
        printf("PASS: test_1d - fclose WAS called after fflush failure\n");
    } else {
        printf("FAIL: test_1d - fclose was NOT called after fflush failure\n");
        printf("  Counterexample: fflush(fp) returns EOF (simulated disk full);\n");
        printf("  the `if (fflush(fp) != 0 || fclose(fp) != 0)` expression\n");
        printf("  short-circuits: fflush != 0 is true, so || skips fclose.\n");
        printf("  File descriptor is leaked.\n");
        printf("  Bug C-L01 confirmed: fclose skipped due to || short-circuit.\n");
        test_passed = 0;
    }

    /* Cleanup */
    free_list(head);
    /* Clean up any temp files write_output may have created */
    char tmp_pattern[280];
    snprintf(tmp_pattern, sizeof(tmp_pattern), "%s.XXXXXX", output_path);
    unlink(output_path);
    unlink(input_path);
    rmdir(tmpdir);

    return test_passed ? 0 : 1;
}
