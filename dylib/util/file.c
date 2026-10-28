// File/Path Helpers.
#include "file.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <pwd.h>
#include <sys/stat.h>

#define NP_READ_CEILING (16u * 1024u * 1024u)

uint8_t *np_read_file_max(const char *path, size_t max, int flags, size_t *out_len) {
    int oflags = O_RDONLY | O_NONBLOCK | O_CLOEXEC;
    if (flags & NP_FILE_NOFOLLOW)
        oflags |= O_NOFOLLOW;
    int fd = open(path, oflags);
    if (fd < 0)
        return NULL;

    struct stat meta;
    if (fstat(fd, &meta) != 0 || !S_ISREG(meta.st_mode) ||
        meta.st_size <= 0 || (uintmax_t)meta.st_size > max) {
        close(fd);
        return NULL;
    }

    size_t total = (size_t)meta.st_size;
    uint8_t *data = (uint8_t *)malloc(total);
    if (!data) {
        close(fd);
        return NULL;
    }

    size_t got = 0;
    while (got < total) {
        ssize_t n = pread(fd, data + got, total - got, (off_t)got);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0) {
            free(data);
            close(fd);
            return NULL;
        }
        got += (size_t)n;
    }

    close(fd);
    *out_len = total;
    return data;
}

uint8_t *np_read_whole_file(const char *path, size_t *out_len) {
    return np_read_file_max(path, NP_READ_CEILING, 0, out_len);
}

int np_write_file_new(const char *path, const void *data, size_t size) {
    if (unlink(path) != 0 && errno != ENOENT)
        return -1;
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644);
    if (fd < 0)
        return -1;

    const uint8_t *p = data;
    while (size) {
        ssize_t n = write(fd, p, size);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0) {
            int saved = errno;
            close(fd);
            unlink(path);
            errno = saved;
            return -1;
        }
        p += n;
        size -= (size_t)n;
    }
    if (close(fd) != 0) {
        int saved = errno;
        unlink(path);
        errno = saved;
        return -1;
    }
    return 0;
}

const char *np_home_dir(void) {
    const char *env = getenv("HOME");
    if (env && env[0])
        return env;

    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_dir && pw->pw_dir[0])
        return pw->pw_dir;
    return NULL;
}

void np_support_path(char *buf, size_t bufsz, const char *home, const char *rel) {
    static const char base[] = "/Library/Application Support/protonish";
    if (rel && rel[0])
        snprintf(buf, bufsz, "%s%s/%s", home, base, rel);
    else
        snprintf(buf, bufsz, "%s%s", home, base);
}
