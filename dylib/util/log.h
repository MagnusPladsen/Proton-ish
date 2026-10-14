// Logs
#ifndef NOTPROTON_UTIL_LOG_H
#define NOTPROTON_UTIL_LOG_H

#include <stdio.h>
#include <time.h>

extern int np_log_level;
extern FILE *np_log_file;
void np_log_init(void);
void np_log_attach(void);

enum {
    NP_LVL_ERR = 0,
    NP_LVL_WARN,
    NP_LVL_INFO,
    NP_LVL_DBG,
};

#define NP_LOG_PREFIX "[protonish]"

#define NP_EMIT(level, tag, fmt, ...) do { \
    if (np_log_level >= (level)) { \
        time_t _now = time(NULL); \
        struct tm _cal; localtime_r(&_now, &_cal); \
        char _ts[24]; \
        strftime(_ts, sizeof(_ts), "%Y-%m-%d %H:%M:%S", &_cal); \
        FILE *_sinks[2] = { stderr, np_log_file }; \
        for (int _s = 0; _s < 2; _s++) { \
            if (_sinks[_s]) \
                fprintf(_sinks[_s], "%s " NP_LOG_PREFIX " %s " fmt "\n", \
                        _ts, tag, ##__VA_ARGS__); \
        } \
    } \
} while(0)

#define NP_ERR(fmt, ...)  NP_EMIT(NP_LVL_ERR,  "error", fmt, ##__VA_ARGS__)
#define NP_WARN(fmt, ...) NP_EMIT(NP_LVL_WARN, "warn",  fmt, ##__VA_ARGS__)
#define NP_LOG(fmt, ...)  NP_EMIT(NP_LVL_INFO, "info",  fmt, ##__VA_ARGS__)
#define NP_DBG(fmt, ...)  NP_EMIT(NP_LVL_DBG,  "debug", fmt, ##__VA_ARGS__)

int np_log_first_hit(const void *anchor, unsigned long tag);

#define NP_LOG_FIRST_KEY(key, fmt, ...) do { \
    static const char np_here = 0; \
    if (np_log_level >= NP_LVL_DBG || np_log_first_hit(&np_here, (unsigned long)(key))) \
        NP_LOG(fmt, ##__VA_ARGS__); \
} while(0)

#define NP_LOG_FIRST(fmt, ...) NP_LOG_FIRST_KEY(0, fmt, ##__VA_ARGS__)

#endif // NOTPROTON_UTIL_LOG_H
