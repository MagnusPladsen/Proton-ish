// Windows PE resource reader
#include "pe.h"

#include <string.h>

int np_pe_open(np_pe_view_t *pe, const uint8_t *p, size_t n) {
    memset(pe, 0, sizeof(*pe));
    pe->p = p;
    pe->n = n;

    uint16_t mz, nsects, opt_size, magic;
    uint32_t peo32, sig;
    if (!np_pe_rd16(pe, 0, &mz) || mz != 0x5A4D) return 0;
    if (!np_pe_rd32(pe, 0x3C, &peo32)) return 0;

    size_t peo = peo32;
    if (!np_pe_rd32(pe, peo, &sig) || sig != 0x00004550) return 0;
    if (!np_pe_rd16(pe, peo + 6, &nsects) || !np_pe_rd16(pe, peo + 20, &opt_size) ||
        !np_pe_rd16(pe, peo + 24, &magic)) return 0;

    size_t dir_base, count_at;
    if (magic == 0x10B) {
        dir_base = peo + 24 + 96;
        count_at = peo + 24 + 92;
    } else if (magic == 0x20B) {
        dir_base = peo + 24 + 112;
        count_at = peo + 24 + 108;
    } else {
        return 0;
    }

    uint32_t dir_count, rsrc_rva;
    if (!np_pe_rd32(pe, count_at, &dir_count) || dir_count <= 2) return 0;
    if (!np_pe_rd32(pe, dir_base + 16, &rsrc_rva) || rsrc_rva == 0) return 0;

    if (nsects == 0 || nsects > NP_PE_MAX_SECTIONS) return 0;
    size_t sects = peo + 24 + opt_size;
    if (sects > pe->n || (pe->n - sects) / 40 < nsects) return 0;

    pe->sects    = sects;
    pe->nsects   = nsects;
    pe->rsrc_rva = rsrc_rva;
    return np_pe_rva_off(pe, rsrc_rva, &pe->rsrc);
}

int np_pe_rva_off(const np_pe_view_t *pe, uint32_t rva, size_t *off) {
    for (uint32_t i = 0; i < pe->nsects; i++) {
        size_t s = pe->sects + (size_t)i * 40;
        uint32_t vsz, va, rsz, raw;
        if (!np_pe_rd32(pe, s + 8, &vsz) || !np_pe_rd32(pe, s + 12, &va) ||
            !np_pe_rd32(pe, s + 16, &rsz) || !np_pe_rd32(pe, s + 20, &raw)) return 0;
        uint32_t span = vsz > rsz ? vsz : rsz;
        if (rva >= va && (uint64_t)rva < (uint64_t)va + span) {
            *off = (size_t)raw + (size_t)(rva - va);
            return 1;
        }
    }
    return 0;
}

static int name_is(const np_pe_view_t *pe, size_t at, const char *name) {
    uint16_t len;
    size_t want = strlen(name);
    if (!np_pe_rd16(pe, at, &len) || len != want) return 0;
    for (uint16_t k = 0; k < len; k++) {
        uint16_t c;
        if (!np_pe_rd16(pe, at + 2 + 2 * (size_t)k, &c) || c != (uint8_t)name[k]) return 0;
    }
    return 1;
}

int np_pe_dir_find(const np_pe_view_t *pe, size_t dir, uint32_t id, const char *name,
                   uint32_t *target) {
    uint16_t named, ids;
    if (!np_pe_rd16(pe, dir + 12, &named) || !np_pe_rd16(pe, dir + 14, &ids)) return 0;
    int total = named + ids;
    if (total > NP_PE_MAX_ENTRIES) total = NP_PE_MAX_ENTRIES;
    for (int i = 0; i < total; i++) {
        uint32_t key, off;
        size_t e = dir + 16 + (size_t)i * 8;
        if (!np_pe_rd32(pe, e, &key) || !np_pe_rd32(pe, e + 4, &off)) return 0;
        int is_named = (key & 0x80000000u) != 0;
        if (name ? (is_named && name_is(pe, pe->rsrc + (key & 0x7FFFFFFFu), name))
                 : (!is_named && key == id)) {
            *target = off;
            return 1;
        }
    }
    return 0;
}

int np_pe_rcdata(const np_pe_view_t *pe, const char *name, size_t *at, uint32_t *size) {
    uint32_t type, entry, lang, rva;
    if (!np_pe_dir_find(pe, pe->rsrc, NP_RT_RCDATA, NULL, &type) ||
        !(type & 0x80000000u)) return 0;
    if (!np_pe_dir_find(pe, pe->rsrc + (type & 0x7FFFFFFFu), 0, name, &entry) ||
        !(entry & 0x80000000u)) return 0;

    size_t langs = pe->rsrc + (entry & 0x7FFFFFFFu);
    uint16_t named, ids;
    if (!np_pe_rd16(pe, langs + 12, &named) || !np_pe_rd16(pe, langs + 14, &ids) ||
        named + ids == 0) return 0;
    if (!np_pe_rd32(pe, langs + 16 + 4, &lang) || (lang & 0x80000000u)) return 0;

    size_t data = pe->rsrc + lang;
    if (!np_pe_rd32(pe, data, &rva) || !np_pe_rd32(pe, data + 4, size)) return 0;
    if (!np_pe_rva_off(pe, rva, at) || *at > pe->n || pe->n - *at < *size) return 0;
    return 1;
}
