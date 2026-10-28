// Support for Steam CEG
#ifndef NOTPROTON_FEATS_CEG_H
#define NOTPROTON_FEATS_CEG_H

#include <stddef.h>
#include <stdint.h>

enum {
    NP_CEG_CALL_OK         = 1,
    NP_CEG_CALL_NO_MODULE  = 2,    // Steam sends the module and retries
    NP_CEG_CALL_FAILED     = 12,
    NP_CEG_CALL_TOO_BIG    = 15,
};

typedef struct {
    uint8_t drm[16];     // STEAM_GUIDD
    uint8_t split[16];   // STEAM_SPLIT_GUID
    uint8_t merge[16];   // STEAM_MINSTANCE, not set until Steam downloads the CEG binary
} np_ceg_guids_t;

int np_ceg_read_guids(const char *exe, np_ceg_guids_t *out);

int np_ceg_guids_from_image(const uint8_t *image, size_t len, np_ceg_guids_t *out);

// CClientDRMDownloadJob fields
typedef struct {
    uint32_t appid;
    uint32_t flags;
    uint32_t guids;
    uint32_t path;
} np_ceg_job_layout_t;

int np_ceg_probe_job_layout(const uint32_t *code, size_t count, np_ceg_job_layout_t *out);

void np_ceg_note_tool(uint32_t appid, const char *tool_dir);

// Returns 0 when the app has no compat tool.
int np_ceg_tool_for_app(uint32_t appid, char *buf, size_t size);

// Returns -1 unless the app is located under steamapps/common and has a compat tool.
int np_ceg_note_app(uint32_t appid, const char *exe);

void np_ceg_snapshot_env(void);

void np_ceg_set_service(const char *client_dir);

// Returns an NP_CEG_CALL_ result
uint32_t np_ceg_service_call(const void *module, uint32_t module_size, uint32_t crc,
                             uint32_t appid, uint32_t fn, uint32_t callid,
                             const void *in, uint32_t in_size,
                             uint8_t **out, uint32_t *out_size);

void np_ceg_stop(void);

#endif // NOTPROTON_FEATS_CEG_H
