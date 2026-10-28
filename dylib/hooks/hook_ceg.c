// CEG hooks
#include "hooks.h"
#include "../feats/ceg.h"
#include "../feats/compat.h"
#include "../util/a64.h"
#include "../util/log.h"
#include "../util/ptr.h"

#include <libgen.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define JOB_FLAGS_PROTON 140
#define JOB_FLAGS_KEEP   0x10

static void *orig_ExtractGUIDs = NULL;
typedef void (*fn_ExtractGUIDs)(uint8_t *job);

static np_ceg_job_layout_t g_job;
static int                 g_job_known;

#define JOB_PROBE_INSNS 32

void np_hooks_ceg_probe_job(uintptr_t extract_guids) {
    g_job_known = extract_guids &&
        np_ceg_probe_job_layout((const uint32_t *)extract_guids, JOB_PROBE_INSNS, &g_job) == 0;
    if (extract_guids && !g_job_known)
        NP_ERR("[ceg] download job layout unknown, CEG jobs stay with the client");
}

// Steam crashes when a CEG game launches if the steamservice hook didn't install.
static atomic_int g_service_ready;

void np_hooks_ceg_service_installed(void) {
    atomic_store(&g_service_ready, 1);
}

static void instrument_RequestCustomBinary(void *address, void *ctx_) {
    (void)address;
    np_arm64_ctx_t *ctx = (np_arm64_ctx_t *)ctx_;
    uint32_t appid = (uint32_t)ctx->general.x[1];
    np_ceg_note_tool(appid, np_compat_app_tool_dir(appid));
}

// macOS Steam's ExtractGUIDsFromFile is a stub
static void hook_ExtractGUIDs(uint8_t *job) {
    fn_ExtractGUIDs orig = (fn_ExtractGUIDs)orig_ExtractGUIDs;
    if (!g_job_known) {
        if (orig)
            orig(job);
        return;
    }

    uint32_t appid = *(uint32_t *)(job + g_job.appid);
    uint64_t path_ptr = *(uint64_t *)(job + g_job.path);
    const char *path = np_plausible_addr(path_ptr) ? (const char *)path_ptr : NULL;
    char tool_dir[1024];
    const char *tool = np_ceg_tool_for_app(appid, tool_dir, sizeof(tool_dir)) ? tool_dir : NULL;

    if (!tool)
        NP_LOG("[ceg] appID %u: no compat tool recorded, leaving the job to the client", appid);
    if (tool && !atomic_load(&g_service_ready)) {
        NP_WARN("[ceg] appID %u: the steamservice hook is not in place, leaving the job to "
                "the client", appid);
        tool = NULL;
    }

    np_ceg_guids_t guids;
    if (path && tool && np_ceg_read_guids(path, &guids) == 0 &&
        np_ceg_note_app(appid, path) == 0) {
        memcpy(job + g_job.guids, &guids, sizeof(guids));
        uint32_t *flags = (uint32_t *)(job + g_job.flags);
        uint32_t was = *flags;
        *flags = JOB_FLAGS_PROTON | (was & JOB_FLAGS_KEEP);
        static const uint8_t zero[16];
        NP_LOG("[ceg] appID %u: GUIDs read from %s (%s), flags %u -> %u", appid, path,
               memcmp(guids.merge, zero, 16) ? "already customized" : "not customized yet",
               was, *flags);
        return;
    }

    if (tool)
        NP_WARN("[ceg] appID %u: no STEAM_GUIDD in %s, leaving the job to the client",
                appid, path ? path : "<no path>");
    if (orig)
        orig(job);
}

// CDRM::OnDRMDownloadJobFinish(this, path, appid, result), which macOS Steam doesn't log.
static void instrument_DRMJobFinish(void *address, void *ctx_) {
    (void)address;
    np_arm64_ctx_t *ctx = (np_arm64_ctx_t *)ctx_;
    uint64_t path = ctx->general.x[1];
    NP_LOG("[ceg] appID %u: CEG job finished with result %u (%s)",
           (uint32_t)ctx->general.x[2], (uint32_t)ctx->general.x[3],
           np_plausible_addr(path) ? (const char *)path : "<no path>");
}

// CWorkItemFunctionCall fields
#define ITEM_MGR_OFF      0xE0
#define ITEM_RESULT_OFF   0xE8
#define ITEM_CRC_OFF      0xEC
#define ITEM_APPID_OFF    0xF4
#define ITEM_FN_OFF       0xF8
#define ITEM_CALLID_OFF   0xFC
#define ITEM_IN_OFF       0x100
#define ITEM_IN_SIZE_OFF  0x108
#define ITEM_OUT_OFF      0x110
#define ITEM_OUT_SIZE_OFF 0x118
#define ITEM_FLAGS_OFF    0x11C
#define CALL_FLAG_PROTON  0x8

// CServiceModuleManager fields
#define MGR_TREE_ROOT_OFF  0x20
#define MGR_TREE_COUNT_OFF 0x2C
#define MGR_TREE_NODES_OFF 0x38
#define NODE_STRIDE        32
#define NODE_KEY_OFF       16
#define NODE_VALUE_OFF     24
#define MODULE_SIZE_OFF    44
#define MODULE_DATA_OFF    48

static const uint8_t *find_module(const uint8_t *mgr, uint32_t crc, uint32_t *size) {
    int32_t idx = *(const int32_t *)(mgr + MGR_TREE_ROOT_OFF);
    int32_t count = *(const int32_t *)(mgr + MGR_TREE_COUNT_OFF);
    uint64_t nodes = *(const uint64_t *)(mgr + MGR_TREE_NODES_OFF);
    for (int hops = 0; idx >= 0 && idx < count && hops < 64 && np_plausible_ptr(nodes);
         hops++) {
        const uint8_t *node = (const uint8_t *)nodes + (size_t)idx * NODE_STRIDE;
        uint32_t key = *(const uint32_t *)(node + NODE_KEY_OFF);
        if (key == crc) {
            uint64_t module = *(const uint64_t *)(node + NODE_VALUE_OFF);
            if (!np_plausible_ptr(module)) return NULL;
            uint64_t data = *(const uint64_t *)(module + MODULE_DATA_OFF);
            *size = *(const uint32_t *)(module + MODULE_SIZE_OFF);
            return np_plausible_addr(data) && *size ? (const uint8_t *)data : NULL;
        }
        idx = *(const int32_t *)(node + (key > crc ? 0 : 4));
    }
    return NULL;
}

// Steam frees both buffers with its own allocator.
#define MEM_VT_ALLOC 16
#define MEM_VT_FREE  32

typedef void *(*fn_mem_getter)(void);
typedef void *(*fn_mem_alloc)(void *self, size_t size);
typedef void  (*fn_mem_free)(void *self, void *p, size_t unused);

static fn_mem_getter g_mem;

static void *steam_alloc(size_t size) {
    void *mem = g_mem ? g_mem() : NULL;
    return mem ? (*(fn_mem_alloc *)(*(uint8_t **)mem + MEM_VT_ALLOC))(mem, size) : NULL;
}

static void steam_free(void *p) {
    void *mem = p && g_mem ? g_mem() : NULL;
    if (mem)
        (*(fn_mem_free *)(*(uint8_t **)mem + MEM_VT_FREE))(mem, p, 0);
}

static void *orig_ThreadProcess = NULL;
typedef uint64_t (*fn_ThreadProcess)(uint8_t *item);

static uint64_t finish_call(uint8_t *item, uint32_t result) {
    *(uint32_t *)(item + ITEM_RESULT_OFF) = result;
    steam_free(*(void **)(item + ITEM_IN_OFF));
    *(void **)(item + ITEM_IN_OFF) = NULL;
    return 1;
}

static uint64_t hook_ThreadProcess(uint8_t *item) {
    uint32_t flags = *(uint32_t *)(item + ITEM_FLAGS_OFF);
    fn_ThreadProcess orig = (fn_ThreadProcess)orig_ThreadProcess;
    void **out_slot = (void **)(item + ITEM_OUT_OFF);
    uint32_t *out_size = (uint32_t *)(item + ITEM_OUT_SIZE_OFF);
    if (!(flags & CALL_FLAG_PROTON)) {
        if (orig)
            return orig(item);
        NP_ERR("[ceg] no original ThreadProcess, failing a native service call");
        *out_slot = NULL;
        *out_size = 0;
        return finish_call(item, NP_CEG_CALL_FAILED);
    }

    uint32_t max_out = *out_size;
    *out_slot = NULL;
    *out_size = 0;

    const uint8_t *mgr = *(uint8_t **)(item + ITEM_MGR_OFF);
    uint32_t crc = *(uint32_t *)(item + ITEM_CRC_OFF);
    uint32_t appid = *(uint32_t *)(item + ITEM_APPID_OFF);
    uint32_t size = 0;
    const uint8_t *module = np_plausible_ptr((uint64_t)mgr) ? find_module(mgr, crc, &size) : NULL;
    if (!module) {
        NP_ERR("[ceg] appID %u: module %08x is not loaded", appid, crc);
        return finish_call(item, NP_CEG_CALL_NO_MODULE);
    }

    uint8_t *out = NULL;
    uint32_t got = max_out;
    uint32_t result = np_ceg_service_call(module, size, crc, appid,
                                          *(uint32_t *)(item + ITEM_FN_OFF),
                                          *(uint32_t *)(item + ITEM_CALLID_OFF),
                                          *(void **)(item + ITEM_IN_OFF),
                                          *(uint32_t *)(item + ITEM_IN_SIZE_OFF),
                                          &out, &got);
    if (result == NP_CEG_CALL_OK && out && got) {
        void *copy = steam_alloc(got);
        if (copy) {
            memcpy(copy, out, got);
            *out_slot = copy;
            *out_size = got;
        } else {
            NP_ERR("[ceg] appID %u: Steam's allocator refused %u bytes", appid, got);
            result = NP_CEG_CALL_FAILED;
        }
    }
    free(out);
    return finish_call(item, result);
}

static uintptr_t allocator_getter(uintptr_t thread_process) {
    int calls = 0;
    for (uintptr_t at = thread_process; at < thread_process + 0x100; at += 4) {
        uintptr_t target;
        if (!a64_bl(at, *(const uint32_t *)at, &target)) continue;
        if (++calls != 3) continue;
        const uint32_t *next = (const uint32_t *)(at + 4);
        uint32_t rn, rt, off, rn2, rt2, off2;
        if (a64_ldr_uimm(next[1], 1, &rn, &rt, &off) && rn == 0 && off == 0 &&
            a64_ldr_uimm(next[2], 1, &rn2, &rt2, &off2) && rn2 == rt && off2 == MEM_VT_FREE)
            return target;
        return 0;
    }
    return 0;
}

int np_hooks_ceg_bind_service(const char *image_path, uintptr_t thread_process) {
    char dir[1024];
    snprintf(dir, sizeof(dir), "%s", image_path ? image_path : "");
    uintptr_t getter = thread_process ? allocator_getter(thread_process) : 0;
    if (!getter || !dir[0]) {
        NP_ERR("[ceg] steamservice allocator not found, Proton service calls stay off");
        return 0;
    }
    g_mem = (fn_mem_getter)getter;
    const char *client = dirname(dir);
    np_ceg_set_service(client);
    NP_LOG("[ceg] service calls run from %s", client);
    return 1;
}

static np_patch_entry_t g_client_hooks[] = {
    {
        .label      = "CDRM::RequestCustomBinary",
        .signature  = "CDRM::RequestCustomBinary",
        .optional   = 1,
        .entry      = (void *)instrument_RequestCustomBinary,
        .mode       = NP_PATCH_PREHOOK,
    },
    {
        .label      = "CClientDRMDownloadJob::ExtractGUIDsFromFile",
        .signature  = "CClientDRMDownloadJob::ExtractGUIDsFromFile",
        .optional   = 1,
        .entry      = (void *)hook_ExtractGUIDs,
        .trampoline = &orig_ExtractGUIDs,
    },
    {
        .label      = "CDRM::OnDRMDownloadJobFinish",
        .signature  = "CDRM::OnDRMDownloadJobFinish",
        .optional   = 1,
        .entry      = (void *)instrument_DRMJobFinish,
        .mode       = NP_PATCH_PREHOOK,
    },
};

static np_patch_entry_t g_service_hooks[] = {
    {
        .label      = "CWorkItemFunctionCall::ThreadProcess",
        .signature  = "CWorkItemFunctionCall::ThreadProcess",
        .optional   = 1,
        .entry      = (void *)hook_ThreadProcess,
        .trampoline = &orig_ThreadProcess,
    },
};

int np_hooks_ceg_count(void) {
    return (int)(sizeof(g_client_hooks) / sizeof(g_client_hooks[0]));
}

np_patch_entry_t *np_hooks_ceg_defs(void) {
    return g_client_hooks;
}

int np_hooks_ceg_service_count(void) {
    return (int)(sizeof(g_service_hooks) / sizeof(g_service_hooks[0]));
}

np_patch_entry_t *np_hooks_ceg_service_defs(void) {
    return g_service_hooks;
}
