// Windows PE resource reader
#ifndef NOTPROTON_UTIL_PE_H
#define NOTPROTON_UTIL_PE_H

#include <stddef.h>
#include <stdint.h>

#define NP_PE_MAX_SECTIONS 96
#define NP_PE_MAX_ENTRIES  512

#define NP_RT_ICON         3
#define NP_RT_RCDATA       10
#define NP_RT_GROUP_ICON   14

typedef struct {
    const uint8_t *p;
    size_t         n;
    size_t         sects;
    uint32_t       nsects;
    uint32_t       rsrc_rva;
    size_t         rsrc;
} np_pe_view_t;

static inline int np_pe_rd8(const np_pe_view_t *pe, size_t off, uint8_t *v) {
    if (off >= pe->n) return 0;
    *v = pe->p[off];
    return 1;
}

static inline int np_pe_rd16(const np_pe_view_t *pe, size_t off, uint16_t *v) {
    if (pe->n < 2 || off > pe->n - 2) return 0;
    *v = (uint16_t)((uint16_t)pe->p[off] | ((uint16_t)pe->p[off + 1] << 8));
    return 1;
}

static inline int np_pe_rd32(const np_pe_view_t *pe, size_t off, uint32_t *v) {
    if (pe->n < 4 || off > pe->n - 4) return 0;
    *v = (uint32_t)pe->p[off]             | ((uint32_t)pe->p[off + 1] << 8) |
         ((uint32_t)pe->p[off + 2] << 16) | ((uint32_t)pe->p[off + 3] << 24);
    return 1;
}

int np_pe_open(np_pe_view_t *pe, const uint8_t *p, size_t n);

int np_pe_rva_off(const np_pe_view_t *pe, uint32_t rva, size_t *off);

int np_pe_dir_find(const np_pe_view_t *pe, size_t dir, uint32_t id, const char *name,
                   uint32_t *target);

int np_pe_rcdata(const np_pe_view_t *pe, const char *name, size_t *at, uint32_t *size);

#endif // NOTPROTON_UTIL_PE_H
