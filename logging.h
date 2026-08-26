/* ------------------------------------------------------------------
 * logging.h - Lightweight leveled logging facility
 *
 * Severity:  DEBUG < INFO < WARN < ERROR
 *
 * Only messages with severity >= the current level are emitted.
 * The level can be overridden at runtime with the LOG_LEVEL
 * environment variable: LOG_LEVEL=DEBUG|INFO|WARN|ERROR
 *
 * The current level is module-private state inside logging.c and is
 * changed only through log_set_level() / log_set_level_from_env().
 * ------------------------------------------------------------------ */
#ifndef LOGGING_H
#define LOGGING_H

typedef enum {
    LOG_LEVEL_DEBUG = 0,
    LOG_LEVEL_INFO  = 1,
    LOG_LEVEL_WARN  = 2,
    LOG_LEVEL_ERROR = 3
} LogLevel;

/** Set the minimum severity that will be emitted. */
void log_set_level(LogLevel level);

/** Pick up an optional LOG_LEVEL=DEBUG|INFO|WARN|ERROR env setting. */
void log_set_level_from_env(void);

/**
 * Core logging function.
 *
 * Emits:  2026-08-19 15:48:01 [LEVEL] file:line message
 * Messages with severity below the active level are discarded.
 */
void log_write(LogLevel level, const char *file, int line,
               const char *fmt, ...);

/* Logging macros - the caller's __FILE__/__LINE__ are captured
 * automatically, so call sites stay as clean as a plain printf.      */
#define LOG_DEBUG(...) log_write(LOG_LEVEL_DEBUG, __FILE__, __LINE__, __VA_ARGS__)
#define LOG_INFO(...)  log_write(LOG_LEVEL_INFO,  __FILE__, __LINE__, __VA_ARGS__)
#define LOG_WARN(...)  log_write(LOG_LEVEL_WARN,  __FILE__, __LINE__, __VA_ARGS__)
#define LOG_ERROR(...) log_write(LOG_LEVEL_ERROR, __FILE__, __LINE__, __VA_ARGS__)

#endif /* LOGGING_H */