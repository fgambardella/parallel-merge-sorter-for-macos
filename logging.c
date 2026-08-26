/*
 * logging.c - Implementation of the leveled logging facility.
 * See logging.h for the public API.
 */
#include "logging.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdarg.h>

/* Module-private state: the current minimum severity. Hidden from
 * other translation units and changed only through the public API.   */
static LogLevel g_log_level = LOG_LEVEL_INFO;

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
 */
void log_write(LogLevel level, const char *file, int line,
               const char *fmt, ...)
{
    char  timestamp[32];
    time_t now;
    struct tm *tm_now;

    if (level < g_log_level)
        return;

    now    = time(NULL);
    tm_now = localtime(&now);
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", tm_now);

    fprintf(stderr, "%s [%s] %s:%d ",
            timestamp, log_level_tag(level), file, line);

    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);

    if (fmt[strlen(fmt) - 1] != '\n')
        fputc('\n', stderr);
}