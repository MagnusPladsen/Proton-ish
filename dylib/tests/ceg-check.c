#include "../feats/ceg.h"
#include "../util/log.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define BUDGET_SECS 90

static const char *g_case = "startup";
static int g_fails;

static void on_alarm(int sig) {
    (void)sig;
    static const char msg[] = " did not finish within the time budget\n";
    write(2, "ceg-check: ", 11);
    write(2, g_case, strlen(g_case));
    write(2, msg, sizeof(msg) - 1);
    _exit(9);
}

static void check(int cond, const char *what) {
    printf("  %s  %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) g_fails++;
}

#define PEO       0x80u
#define OPT_SIZE  240u
#define SECT_OFF  (PEO + 24u + OPT_SIZE)
#define RSRC_OFF  0x400u
#define RSRC_RVA  0x1000u
#define RSRC_SIZE 0x800u

static void put16(uint8_t *p, unsigned v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void put32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}

typedef struct {
    const char    *name;
    const uint8_t *data;
    uint32_t       size;
} res_t;

static uint8_t *build_pe(const res_t *res, int nres, size_t *len) {
    size_t total = RSRC_OFF + RSRC_SIZE;
    uint8_t *img = calloc(1, total);
    img[0] = 'M'; img[1] = 'Z';
    put32(img + 0x3C, PEO);
    uint8_t *pe = img + PEO;
    pe[0] = 'P'; pe[1] = 'E';
    put16(pe + 6, 1);
    put16(pe + 20, OPT_SIZE);
    put16(pe + 24, 0x20B);
    put32(pe + 24 + 108, 16);
    put32(pe + 24 + 112 + 16, RSRC_RVA);
    uint8_t *sect = img + SECT_OFF;
    memcpy(sect, ".rsrc", 5);
    put32(sect + 8, RSRC_SIZE);
    put32(sect + 12, RSRC_RVA);
    put32(sect + 16, RSRC_SIZE);
    put32(sect + 20, RSRC_OFF);

    uint8_t *r = img + RSRC_OFF;
    put16(r + 14, 1);
    put32(r + 16, 10);
    put32(r + 20, 0x80000000u | 0x18);
    size_t type = 0x18;
    put16(r + type + 12, (unsigned)nres);
    size_t langs = type + 16 + (size_t)nres * 8;
    size_t data_entries = langs + (size_t)nres * 24;
    size_t names = data_entries + (size_t)nres * 16;
    size_t blobs = names + 0x100;
    for (int i = 0; i < nres; i++) {
        size_t name_at = names + (size_t)i * 40;
        size_t nlen = strlen(res[i].name);
        put16(r + name_at, (unsigned)nlen);
        for (size_t k = 0; k < nlen; k++) put16(r + name_at + 2 + 2 * k, (uint8_t)res[i].name[k]);
        put32(r + type + 16 + (size_t)i * 8, 0x80000000u | (uint32_t)name_at);
        size_t lang = langs + (size_t)i * 24;
        put32(r + type + 16 + (size_t)i * 8 + 4, 0x80000000u | (uint32_t)lang);
        put16(r + lang + 14, 1);
        put32(r + lang + 16, 0x409);
        size_t entry = data_entries + (size_t)i * 16;
        put32(r + lang + 20, (uint32_t)entry);
        size_t blob = blobs + (size_t)i * 32;
        put32(r + entry, RSRC_RVA + (uint32_t)blob);
        put32(r + entry + 4, res[i].size);
        memcpy(r + blob, res[i].data, res[i].size);
    }
    *len = total;
    return img;
}

static const uint8_t DRM[16]   = { 0x72, 0xfe, 0x8e, 0xd3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
static const uint8_t SPLIT[16] = { 0x1a, 0xb2, 0x2e, 0x61, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9 };
static const uint8_t MERGE[16] = { 0x55, 0x43, 0x8a, 0x48, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7 };
static const uint8_t ZERO[16];

static void pe_cases(const char *tmp) {
    np_ceg_guids_t g;
    size_t len;
    uint8_t *img;

    printf("== GUIDs from a PE image\n");
    g_case = "all three GUIDs";
    res_t all[] = { { "STEAM_GUIDD", DRM, 16 }, { "STEAM_SPLIT_GUID", SPLIT, 16 },
                    { "STEAM_MINSTANCE", MERGE, 16 } };
    img = build_pe(all, 3, &len);
    check(np_ceg_guids_from_image(img, len, &g) == 0 && !memcmp(g.drm, DRM, 16) &&
          !memcmp(g.split, SPLIT, 16) && !memcmp(g.merge, MERGE, 16),
          "all three GUIDs read");

    g_case = "truncated images";
    int early_pass = 0;
    for (size_t cut = 0; cut < len; cut += 7) {
        int rc = np_ceg_guids_from_image(img, cut, &g);
        if (rc == 0 && cut < RSRC_OFF) early_pass = 1;
    }
    check(!early_pass, "every truncation is read without overrun and none passes "
                          "before the resources");

    g_case = "corrupted images";
    srand(1234);
    for (int i = 0; i < 20000; i++) {
        uint8_t *copy = malloc(len);
        memcpy(copy, img, len);
        for (int k = 0; k < 8; k++) copy[(size_t)rand() % len] = (uint8_t)rand();
        np_ceg_guids_from_image(copy, len, &g);
        free(copy);
    }
    check(1, "20000 randomly corrupted images parse without a fault");

    g_case = "hostile entry count";
    uint8_t *hostile = malloc(len);
    memcpy(hostile, img, len);
    put16(hostile + RSRC_OFF + 0x18 + 12, 0xFFFF);
    put16(hostile + RSRC_OFF + 0x18 + 14, 0xFFFF);
    np_ceg_guids_from_image(hostile, len, &g);
    check(1, "a directory claiming 131070 entries is bounded");
    memcpy(hostile, img, len);
    put16(hostile + PEO + 6, 97);
    check(np_ceg_guids_from_image(hostile, len, &g) != 0, "97 sections are refused");
    free(hostile);

    g_case = "GUIDD only";
    free(img);
    res_t only[] = { { "STEAM_GUIDD", DRM, 16 } };
    img = build_pe(only, 1, &len);
    check(np_ceg_guids_from_image(img, len, &g) == 0 && !memcmp(g.split, ZERO, 16) &&
          !memcmp(g.merge, ZERO, 16), "STEAM_GUIDD alone is enough, the others stay zero");
    free(img);

    g_case = "no GUIDD";
    res_t none[] = { { "STEAM_SPLIT_GUID", SPLIT, 16 } };
    img = build_pe(none, 1, &len);
    check(np_ceg_guids_from_image(img, len, &g) != 0, "no STEAM_GUIDD is refused");
    free(img);

    g_case = "wrong size";
    res_t small[] = { { "STEAM_GUIDD", DRM, 15 } };
    img = build_pe(small, 1, &len);
    check(np_ceg_guids_from_image(img, len, &g) != 0, "a 15-byte STEAM_GUIDD is refused");
    free(img);

    g_case = "shorter name";
    res_t prefix[] = { { "STEAM_GUID", DRM, 16 } };
    img = build_pe(prefix, 1, &len);
    check(np_ceg_guids_from_image(img, len, &g) != 0, "STEAM_GUID does not match STEAM_GUIDD");

    g_case = "from a file";
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/game.exe", tmp);
    FILE *f = fopen(path, "wb");
    fwrite(img, 1, len, f);
    fclose(f);
    free(img);
    res_t file_res[] = { { "STEAM_GUIDD", DRM, 16 } };
    img = build_pe(file_res, 1, &len);
    f = fopen(path, "wb");
    fwrite(img, 1, len, f);
    fclose(f);
    free(img);
    check(np_ceg_read_guids(path, &g) == 0 && !memcmp(g.drm, DRM, 16), "read from a file");

    g_case = "a FIFO";
    snprintf(path, sizeof path, "%s/fifo.exe", tmp);
    mkfifo(path, 0600);
    check(np_ceg_read_guids(path, &g) != 0, "a FIFO is refused without blocking");
}

static void table_cases(void) {
    char buf[1024];
    printf("== app table\n");
    g_case = "app table";
    check(np_ceg_note_app(500, "/lib/steamapps/common/Game/bin/a.exe") != 0,
          "an app without a recorded tool is not noted");
    np_ceg_note_tool(500, "/tools/t");
    check(np_ceg_tool_for_app(500, buf, sizeof buf) && !strcmp(buf, "/tools/t"),
          "the recorded tool reads back");
    check(np_ceg_note_app(500, "/lib/steamapps/common/Game/bin/a.exe") == 0,
          "a game under steamapps/common is noted");
    check(np_ceg_note_app(500, "/lib/Game/a.exe") != 0, "a path outside steamapps/common is refused");
    check(np_ceg_note_app(500, "/lib/steamapps/common/Game") != 0, "an install folder alone is refused");
    check(np_ceg_note_app(500, "/lib/steamapps/common//a.exe") != 0, "an empty install folder name is refused");
    np_ceg_note_tool(501, NULL);
    check(!np_ceg_tool_for_app(501, buf, sizeof buf), "an app on no tool has no tool");
    for (uint32_t id = 600; id < 617; id++) np_ceg_note_tool(id, "/tools/t");
    check(!np_ceg_tool_for_app(600, buf, sizeof buf) && np_ceg_tool_for_app(616, buf, sizeof buf),
          "the 17th app evicts the oldest of 16");
}

static char g_tmp[PATH_MAX], g_client[PATH_MAX], g_tool[PATH_MAX], g_lib[PATH_MAX];

static void write_text(const char *path, const char *text) {
    FILE *f = fopen(path, "w");
    fputs(text, f);
    fclose(f);
}

static char *read_text(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return NULL;
    static char buf[65536];
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    fclose(f);
    buf[n] = 0;
    return buf;
}

static int exists(const char *path) {
    struct stat st;
    return lstat(path, &st) == 0;
}

static void set_mode(const char *mode) {
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/mode", g_tmp);
    write_text(path, mode);
}

static const char RUN_SCRIPT[] =
    "#!/bin/sh\n"
    "t=\"$(dirname \"$0\")/..\"\n"
    "env > \"$t/env.txt\"\n"
    "printf '%s\\n' \"$@\" > \"$t/args.txt\"\n"
    "pwd -P > \"$t/cwd.txt\"\n"
    "id=\"$6\"\n"
    "in=\"legacycompat/servicecall_$id.in\"\n"
    "out=\"legacycompat/servicecall_$id.out\"\n"
    "cat \"$in\" > \"$t/in.txt\" 2>/dev/null\n"
    "case \"$(cat \"$t/mode\")\" in\n"
    "  ok)    printf 'SURVEY-OUTPUT' > \"$out\" ;;\n"
    "  empty) : > \"$out\" ;;\n"
    "  fail)  printf 'PART' > \"$out\"; exit 3 ;;\n"
    "  big)   head -c 100 /dev/zero > \"$out\" ;;\n"
    "  none)  ;;\n"
    "  sleep) sleep 60 & echo $! > \"$t/child.pid\"; wait ;;\n"
    "esac\n"
    "exit 0\n";

static const uint8_t MODULE[] = "MZ fake survey module bytes";

static uint32_t call(uint32_t appid, uint32_t callid, uint32_t max, uint8_t **out, uint32_t *size) {
    *size = max;
    return np_ceg_service_call(MODULE, sizeof MODULE, 0xf19a9d4a, appid, 1, callid,
                               "INPUT", 5, out, size);
}

static int dll_holds_module(void) {
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/legacycompat/servicecall_%u.dll", g_client, 0xf19a9d4au);
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    uint8_t buf[sizeof MODULE];
    size_t n = fread(buf, 1, sizeof buf, f);
    int extra = fgetc(f) != EOF;
    fclose(f);
    return n == sizeof MODULE && !extra && !memcmp(buf, MODULE, sizeof MODULE);
}

static void *stop_later(void *arg) {
    (void)arg;
    usleep(800 * 1000);
    np_ceg_stop();
    return NULL;
}

static void call_cases(void) {
    char path[PATH_MAX], target[PATH_MAX];
    uint8_t *out;
    uint32_t size;
    const uint32_t app = 700;

    printf("== service call through a fake tool\n");
    np_ceg_note_tool(app, g_tool);
    char exe[PATH_MAX];
    snprintf(exe, sizeof exe, "%s/steamapps/common/Game/bin/game.exe", g_lib);
    np_ceg_note_app(app, exe);

    g_case = "unknown app";
    check(call(999, 1, 64, &out, &size) == NP_CEG_CALL_FAILED && !out,
          "an app no job set up fails");

    g_case = "success";
    set_mode("ok");
    uint32_t rc = call(app, 41, 64, &out, &size);
    check(rc == NP_CEG_CALL_OK && size == 13 && out && !memcmp(out, "SURVEY-OUTPUT", 13),
          "the module's output comes back");
    free(out);
    snprintf(path, sizeof path, "%s/legacycompat", g_client);
    check(exists(path), "legacycompat is created when it is missing");
    check(dll_holds_module(), "the module is written as servicecall_<crc>.dll");
    snprintf(path, sizeof path, "%s/in.txt", g_tmp);
    check(read_text(path) && !strcmp(read_text(path), "INPUT"), "the input reaches the helper");
    snprintf(path, sizeof path, "%s/legacycompat/servicecall_41.in", g_client);
    check(!exists(path), "the .in file is removed");
    snprintf(path, sizeof path, "%s/legacycompat/servicecall_41.out", g_client);
    check(!exists(path), "the .out file, a survey of the machine, is removed");

    snprintf(path, sizeof path, "%s/args.txt", g_tmp);
    char want[PATH_MAX * 2];
    snprintf(want, sizeof want, "run\n%s/legacycompat/SteamService.exe\n/runfunc\n%u\n1\n41\n64\n",
             g_client, 0xf19a9d4au);
    check(read_text(path) && !strcmp(read_text(path), want), "the helper gets run run SteamService.exe /runfunc crc fn id max");
    snprintf(path, sizeof path, "%s/cwd.txt", g_tmp);
    char real_client[PATH_MAX];
    realpath(g_client, real_client);
    char cwd_want[PATH_MAX + 2];
    snprintf(cwd_want, sizeof cwd_want, "%s\n", real_client);
    check(read_text(path) && !strcmp(read_text(path), cwd_want), "the helper starts in the client folder");

    snprintf(path, sizeof path, "%s/env.txt", g_tmp);
    char *env = read_text(path);
    char line[PATH_MAX * 2];
    check(env && !strstr(env, "\nSteamAppId=") && !strstr(env, "\nSteamGameId="),
          "the helper gets neither SteamAppId nor SteamGameId, so Steam does not take it for the game");
    check(env && strstr(env, "STEAM_COMPAT_PROTON=1\n") && !strstr(env, "STEAM_COMPAT_PROTON=7"),
          "STEAM_COMPAT_PROTON is set once, replacing an inherited value");
    snprintf(line, sizeof line, "STEAM_COMPAT_DATA_PATH=%s/steamapps/compatdata/%u\n", g_lib, app);
    check(env && strstr(env, line), "the prefix is the game library's compatdata");
    snprintf(line, sizeof line, "STEAM_COMPAT_INSTALL_PATH=%s/steamapps/common/Game\n", g_lib);
    check(env && strstr(env, line), "the install path is the game's folder");
    check(env && strstr(env, "NP_CHECK_SNAPSHOT=taken\n") && !strstr(env, "NP_CHECK_LATER="),
          "the environment is the one copied at startup");

    g_case = "stale module";
    snprintf(path, sizeof path, "%s/legacycompat/servicecall_%u.dll", g_client, 0xf19a9d4au);
    FILE *f = fopen(path, "wb");
    uint8_t junk[sizeof MODULE];
    memset(junk, 'X', sizeof junk);
    fwrite(junk, 1, sizeof junk, f);
    fclose(f);
    call(app, 42, 64, &out, &size);
    free(out);
    check(dll_holds_module(), "a cached module of the same size but other bytes is rewritten");

    g_case = "planted symlink";
    snprintf(target, sizeof target, "%s/victim.txt", g_tmp);
    write_text(target, "untouched");
    snprintf(path, sizeof path, "%s/legacycompat/servicecall_43.in", g_client);
    symlink(target, path);
    call(app, 43, 64, &out, &size);
    free(out);
    check(read_text(target) && !strcmp(read_text(target), "untouched"),
          "a symlink at the .in path is replaced, not written through");

    g_case = "empty output";
    set_mode("empty");
    check(call(app, 44, 64, &out, &size) == NP_CEG_CALL_OK && !out && size == 0,
          "an empty output is a success with nothing to return");

    g_case = "failed helper";
    set_mode("fail");
    check(call(app, 45, 64, &out, &size) == NP_CEG_CALL_FAILED && !out,
          "a helper that exits non-zero fails the call, its partial output dropped");
    snprintf(path, sizeof path, "%s/legacycompat/servicecall_45.out", g_client);
    check(!exists(path), "the partial output is removed");

    g_case = "too big";
    set_mode("big");
    check(call(app, 46, 64, &out, &size) == NP_CEG_CALL_TOO_BIG && !out,
          "more output than allowed is refused");

    g_case = "no output";
    set_mode("none");
    check(call(app, 47, 64, &out, &size) == NP_CEG_CALL_FAILED && !out,
          "a helper that writes nothing fails the call");

    g_case = "timeout";
    set_mode("sleep");
    time_t start = time(NULL);
    check(call(app, 48, 64, &out, &size) == NP_CEG_CALL_FAILED,
          "a helper past the timeout fails the call");
    check(time(NULL) - start < 15, "and the call returns soon after the timeout");
    snprintf(path, sizeof path, "%s/child.pid", g_tmp);
    char *pid_text = read_text(path);
    pid_t child = pid_text ? (pid_t)atoi(pid_text) : 0;
    usleep(200 * 1000);
    check(child > 0 && kill(child, 0) != 0, "the helper's own children are stopped with it");

    g_case = "stop";
    unlink(path);
    pthread_t t;
    pthread_create(&t, NULL, stop_later, NULL);
    start = time(NULL);
    check(call(app, 49, 64, &out, &size) == NP_CEG_CALL_FAILED, "stopping Steam fails a running call");
    check(time(NULL) - start < 5, "and ends it at once instead of waiting out the timeout");
    pthread_join(t, NULL);
    snprintf(path, sizeof path, "%s/legacycompat/servicecall_49.in", g_client);
    check(!exists(path), "its files are removed");
    set_mode("ok");
    check(call(app, 50, 64, &out, &size) == NP_CEG_CALL_FAILED, "no call starts once Steam is stopping");
}

// The first 20 instructions of ExtractGUIDsFromFile in Steam 1792618285 (stable) and
// 1793056502 (beta).
static const uint32_t STUB_1792618285[20] = {
    0xa9bd6ffc, 0xa9014ff4, 0xa9027bfd, 0x910083fd, 0xd110c3ff, 0xaa0003f3, 0xd00083a8,
    0xf940b108, 0xf9400108, 0xf81d83a8, 0x39462008, 0x373802c8, 0xf940ee68, 0xf0007949,
    0x9104ad29, 0xf100011f, 0x9a880134, 0xb9416e73, 0x9432bd2a, 0xb9400008,
};
static const uint32_t STUB_1793056502[20] = {
    0xa9bd6ffc, 0xa9014ff4, 0xa9027bfd, 0x910083fd, 0xd110c3ff, 0xaa0003f3, 0xd00084c8,
    0xf947f908, 0xf9400108, 0xf81d83a8, 0x39466008, 0x373802c8, 0xf940f668, 0xd0007a69,
    0x910a9529, 0xf100011f, 0x9a880134, 0xb9417e73, 0x9433345b, 0xb9400008,
};

static void job_layout_cases(void) {
    np_ceg_job_layout_t l;
    uint32_t code[20];

    g_case = "job layout 1792618285";
    check(np_ceg_probe_job_layout(STUB_1792618285, 20, &l) == 0 && l.appid == 364 &&
          l.flags == 392 && l.guids == 424 && l.path == 472, "the baseline build reads as itself");

    g_case = "job layout 1793056502";
    check(np_ceg_probe_job_layout(STUB_1793056502, 20, &l) == 0 && l.appid == 380 &&
          l.flags == 408 && l.guids == 440 && l.path == 488, "the beta's 16-byte shift is found");

    g_case = "job layout uneven shift";
    memcpy(code, STUB_1793056502, sizeof code);
    code[17] = 0xb9417a73;   // appid at 376
    check(np_ceg_probe_job_layout(code, 20, &l) != 0, "fields moving by different amounts are refused");

    g_case = "job layout wrong bit";
    memcpy(code, STUB_1793056502, sizeof code);
    code[11] = 0x373002c8;   // TBNZ W8,#6
    check(np_ceg_probe_job_layout(code, 20, &l) != 0, "a flags test on another bit is refused");

    g_case = "job layout other base";
    memcpy(code, STUB_1793056502, sizeof code);
    code[5] = 0xaa0103f3;    // MOV X19,X1
    check(np_ceg_probe_job_layout(code, 20, &l) != 0, "loads off another register are refused");

    g_case = "job layout truncated";
    check(np_ceg_probe_job_layout(STUB_1793056502, 12, &l) != 0, "a stub cut before the loads is refused");
}

int main(void) {
    signal(SIGALRM, on_alarm);
    alarm(BUDGET_SECS);
    np_log_level = -1;

    snprintf(g_tmp, sizeof g_tmp, "%s/ceg-check.XXXXXX", getenv("TMPDIR") ? getenv("TMPDIR") : "/tmp");
    if (!mkdtemp(g_tmp)) { perror("mkdtemp"); return 2; }

    pe_cases(g_tmp);
    table_cases();
    job_layout_cases();

    snprintf(g_client, sizeof g_client, "%s/client", g_tmp);
    snprintf(g_tool, sizeof g_tool, "%s/tool", g_tmp);
    snprintf(g_lib, sizeof g_lib, "%s/lib", g_tmp);
    mkdir(g_client, 0755);
    mkdir(g_tool, 0755);
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/run", g_tool);
    write_text(path, RUN_SCRIPT);
    chmod(path, 0755);

    setenv("SteamAppId", "999", 1);
    setenv("SteamGameId", "999", 1);
    setenv("STEAM_COMPAT_PROTON", "7", 1);
    setenv("NP_CHECK_SNAPSHOT", "taken", 1);
    np_ceg_snapshot_env();
    setenv("NP_CHECK_LATER", "after", 1);
    np_ceg_set_service(g_client);

    call_cases();

    char cmd[PATH_MAX + 16];
    snprintf(cmd, sizeof cmd, "rm -rf '%s'", g_tmp);
    system(cmd);

    if (g_fails) {
        printf("ceg-check: %d failed\n", g_fails);
        return 1;
    }
    printf("==> ceg-check: GUIDs read from hostile images safely, service calls run, fail and stop cleanly\n");
    return 0;
}
