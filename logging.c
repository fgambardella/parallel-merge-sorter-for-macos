/*
 * logging.c - Implementation of the leveled logging facility.
 * See logging.h for the public API.
 *
 * M-06 fixes:
 *   - Validate fmt (reject NULL and empty string).
 *   - Use localtime_r instead of localtime for thread safety.
 *   - Emit each log record under a mutex to prevent interleaving.
 *   - Handle NULL from localtime_r / strftime failure gracefully.
 */
#include "logging.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdarg.h>
#include <pthread.h>

/* Module-private state: the current minimum severity. Set once at
 * startup before threads are created, then treated as immutable.     */
static LogLevel g_log_level = LOG_LEVEL_INFO;

/* Mutex protecting stderr output (M-06: prevent record interleaving). */
static pthread_mutex_t g_log_mutex = PTHREAD_MUTEX_INITIALIZER;

/** Set the minimum severity that will be emitted. */
void log_set_level(LogLevel level)
{
    g_log_level = level;
}

/** Pick up an optional LOG_LEVEL=DEBUG|INFO|WARN|ERROR env setting. */
void log_set_level_from_env(void)
{
    const char *env = getenv("LOG_LEVEL");

    if (!env)
        return;

    if      (strcmp(env, "DEBUG") == 0) g_log_level = LOG_LEVEL_DEBUG;
    else if (strcmp(env, "INFO")  == 0) g_log_level = LOG_LEVEL_INFO;
    else if (strcmp(env, "WARN")  == 0) g_log_level = LOG_LEVEL_WARN;
    else if (strcmp(env, "ERROR") == 0) g_log_level = LOG_LEVEL_ERROR;
}

/** Human-readable tag for a log level. */
static const char *log_level_tag(LogLevel level)
{
    switch (level) {
        case LOG_LEVEL_DEBUG: return "DEBUG";
        case LOG_LEVEL_INFO:  return "INFO ";
        case LOG_LEVEL_WARN:  return "WARN ";
        case LOG_LEVEL_ERROR: return "ERROR";
        default:              return "?????";
    }
}

/**
 * Core logging function.
 *
 * Emits:  2026-08-19 15:48:01 [LEVEL] file:line message
 * Messages with severity below the active level are discarded.
 * Thread-safe (M-06).
 */
void log_write(LogLevel level, const char *file, int line,
               const char *fmt, ...)
{
    char  timestamp[32];
    time_t now;
    struct tm tm_buf;

    if (level < g_log_level)
        return;

    /* M-06 fix: validate fmt to prevent UB on empty/NULL format. */
    if (fmt == NULL || fmt[0] == '\0') {
        /* Nothing useful to log. */
        return;
    }

    now = time(NULL);

    /* M-06 fix: use localtime_r for thread safety; handle NULL. */
    if (localtime_r(&now, &tm_buf) == NULL) {
        snprintf(timestamp, sizeof(timestamp), "(no timestamp)");
    } else if (strftime(timestamp, sizeof(timestamp),
                        "%Y-%m-%d %H:%M:%S", &tm_buf) == 0) {
        snprintf(timestamp, sizeof(timestamp), "(no timestamp)");
    }

    /* M-06 fix: emit the entire record under a lock so multi-threaded
     * logging doesn't interleave partial lines. */
    pthread_mutex_lock(&g_log_mutex);

    fprintf(stderr, "%s [%s] %s:%d ",
            timestamp, log_level_tag(level), file, line);

    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);

    if (fmt[strlen(fmt) - 1] != '\n')
        fputc('\n', stderr);

    pthread_mutex_unlock(&g_log_mutex);
}
