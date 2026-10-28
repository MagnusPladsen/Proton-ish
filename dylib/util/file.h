// File/Path Helpers.
#ifndef NOTPROTON_UTIL_FILE_H
#define NOTPROTON_UTIL_FILE_H

#include <stdint.h>
#include <stddef.h>

#define NP_FILE_NOFOLLOW 0x1

// Caller owns the returned buffer.
uint8_t *np_read_file_max(const char *path, size_t max, int flags, size_t *out_len);

// Caller owns the returned buffer. Refuses anything over 16 MB.
uint8_t *np_read_whole_file(const char *path, size_t *out_len);

int np_write_file_new(const char *path, const void *data, size_t size);

const char *np_home_dir(void);

void np_support_path(char *buf, size_t bufsz, const char *home, const char *rel);

#endif // NOTPROTON_UTIL_FILE_H
