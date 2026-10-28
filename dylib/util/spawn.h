// Steam child process helper
#ifndef NOTPROTON_UTIL_SPAWN_H
#define NOTPROTON_UTIL_SPAWN_H

#include <signal.h>
#include <spawn.h>

#define NP_SPAWN_OWN_GROUP 0x1

static inline int np_spawn_attr_clean(posix_spawnattr_t *attr, int flags) {
    int rc = posix_spawnattr_init(attr);
    if (rc != 0)
        return rc;
    sigset_t none, all;
    sigemptyset(&none);
    sigfillset(&all);
    posix_spawnattr_setsigmask(attr, &none);
    posix_spawnattr_setsigdefault(attr, &all);
    short spawn_flags = POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF |
                        POSIX_SPAWN_CLOEXEC_DEFAULT;
    if (flags & NP_SPAWN_OWN_GROUP) {
        spawn_flags |= POSIX_SPAWN_SETPGROUP;
        posix_spawnattr_setpgroup(attr, 0);
    }
    posix_spawnattr_setflags(attr, spawn_flags);
    return 0;
}

#endif // NOTPROTON_UTIL_SPAWN_H
