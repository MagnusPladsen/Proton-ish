# M2b: Highball Launch Environment via HighballKit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A game run through a `protonish-highball-*` tool gets the launch environment Highball itself would give it: the renderer picked in Steam's Graphics dropdown (or Highball's per-game choice on Automatic), DLSS, Metal HUD, the D3DMetal timestamp shim, DXVK/DXMT config and logs, the audio buffer fix, and the environment fixes from Highball's game database and recipes. Highball's improvements reach Proton-ish by bumping one pinned dependency, not by re-implementing them.

**Architecture:** A new executable, `highball-env`, links Highball's own Swift library `HighballKit` (GPL-3, same as Proton-ish), pinned to an exact release. The run script calls it for Highball tools with the Steam prefix, engine id, Steam app id and the panel's launch-option variables; it builds an in-memory `Bottle` for the prefix, maps the panel variables onto `BottleSettings`, applies the game's database row and the environment-only parts of its recipe, runs Highball's own pre-launch steps (`prepareDLSSBridge`, `writeDxvkConfig`) and prints `Bottle.environment(engine:renderer:)` as `KEY=VALUE` lines. The run script exports them, except the keys Proton-ish owns. Renderer folders, licence gate and shim live in the user's Highball install (`InstalledEngine` from `EngineStore`), exactly where Highball uses them. A snapshot of highball-db (CC0) ships inside the app and is refreshed with each Highball bump.

**Tech Stack:** Swift 6.4 / SwiftPM / swift-testing, POSIX sh, C + JS (webpatch), GNU Make, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` §5 (Graphics bullet). This plan replaces that bullet's hand-written mapping with HighballKit; Task 8 amends the spec.

**User decisions (2026-10-15):** reuse Highball's code instead of re-implementing (HighballKit route); the timestamp shim is done the way Highball does it (HighballKit does it); game DB as a bundled snapshot (live fetch later); test games Split Fiction (2001120, DX12) and Baldur's Gate 3 (1086940, DX11, has a macOS version).

## Global Constraints

- **Dependency:** `.package(url: "https://github.com/gauthierpiarrette/highball", exact: "<latest non-pre-release tag, 0.10.15 at writing>")`, product `HighballKit`, in `app/Package.swift`. Only the `highball-env` target depends on it; `NotProtonApp` does not. Sparkle stays `exact: "2.10.0"` (Highball's `from: "2.6.0"` is compatible); confirm resolution in Task 1.
- **Licences:** HighballKit GPL-3.0 (compatible with Proton-ish's GPL-3), highball-db curated data and recipes CC0-1.0. Do **not** ship `db/derived/` (ODbL) or `db/anticheat.json` (MIT) in this milestone. `NOTICE`, README Thanks and About credit both.
- **Keys Proton-ish owns** (dropped from `highball-env` output, the run script's values stay): `WINEPREFIX` (Steam's prefix is passed in, but the run script's value is authoritative), `WINELOADER`, `WINESERVER`, `WINEDLLPATH`, `PATH`, `WINEDEBUG` when the user set one, `WINEUSERNAME`, `CX_ROOT`, and the steamclient entries of `WINEDLLOVERRIDES` (run script appends them last, `compat_run.sh:1285`).
- **Panel → `BottleSettings` mapping** (Steam launch options arrive as environment variables):

  | Variable | Setting |
  |---|---|
  | `CX_GRAPHICS_BACKEND` empty / `dxmt` / `d3dmetal` / `dxvk` / `wined3d` | `renderer` with `rendererExplicit = false` for empty (database row and Highball defaults decide), `true` otherwise |
  | `MTL_HUD_ENABLED=1` | `metalHUD = true` |
  | `ROSETTA_ADVERTISE_AVX=1` | `advertiseAVX = true` |
  | `WINEMSYNC=0` / `1` | `sync = .none` / `.msync` (default `.msync`, Highball's default) |
  | `DXMT_ENABLE_NVEXT=1` or `D3DM_ENABLE_METALFX=1` | `dlssEnabled = true` |
  | user `WINEDLLOVERRIDES` | `dllOverrides` (so Highball's merge keeps the user's entries winning) |
  | other `DXMT_*`, `D3DM_*`, `DXVK_*`, `MTL_*` the user typed | passed through unchanged; they win over Highball's values (user intent), except `DXMT_CONFIG`, which is `;`-joined (Highball's own rule) |

- **Unavailable renderer:** HighballKit's `effectiveRenderer` already degrades (DXMT → DXVK → WineD3D) and returns a note; `highball-env` prints it as `# note: …` and the run script logs it. Licence gate is HighballKit's (`rendererDir("d3dmetal")` is nil without `apple-gptk-license-*`).
- **Recipes in M2b:** only steps that are pure environment or settings: `environment`, `renderer` (skipped when the user picked a renderer, HighballKit's `RecipeRunner.rendererToApply`), `dlloverride`, `dxvkconfig`. Steps that run Wine or change the prefix (`winver`, `registry`, `winetricks`, `copy`, `installer`) are logged as "skipped (M2c)" and left for M2c, because they run Highball's own Wine against the Steam prefix and need their own design.
- **Database lookup:** by Steam app id only (`GameDB.byAppID`). Snapshot at `Resources/highball-db/{games,recipes}/` plus `Resources/highball-db/SOURCE` (`<repo commit> <date>`).
- **Output contract:** `highball-env` prints only lines matching `^[A-Z_][A-Z0-9_]*=` with no newline in the value, plus `# `-prefixed notes; exit 0 with no `KEY=` lines on any failure (engine missing, Highball not installed) and a `# error: …` note. The run script falls back to today's DXMT-only behaviour when it gets nothing, and never `eval`s the output.
- **Where it lives:** built by `make app` into the payload as `highball-env` (like `iconmaker`, `appinfo`), installed to `$np_support/highball-env` by Install.
- **Engine lookup:** `EngineStore(paths: HighballPaths())` (honours `HIGHBALL_HOME` and Highball's `config.json` exactly as Highball does) → `engine(<engine id>)`. Proton-ish's patched engine copy stays the one that runs (`WINELOADER` etc. are Proton-ish's).
- No behaviour change for CrossOver runners. `make brandcheck` clean; commits via `/commit`; README changelog line; never commit to `main`.

## Review Focus

1. **User overrides lost** — a launch option the user typed (`WINEDLLOVERRIDES`, `DXMT_CONFIG`, `DXVK_HUD`) must survive Highball's environment. Pinned by mapping tests (Task 2) and an envcheck case (Task 5).
2. **Owned keys overwritten** — `highball-env` must never replace `WINELOADER`, `WINESERVER`, `WINEPREFIX`, `PATH`. Pinned by a test that feeds HighballKit output containing them (Task 3).
3. **Output as an injection vector** — the run script accepts only validated `KEY=VALUE` lines. Pinned by an envcheck case with a fake `highball-env` that prints hostile lines (Task 5).
4. **DYLD variables not reaching Wine** — HighballKit sets `DYLD_FALLBACK_*` and `DYLD_INSERT_LIBRARIES` (audio buffer, frame generation); the launcher's re-export (`compat_run.sh:1429`) must carry all of them. Pinned by an envcheck case on the generated launcher (Task 5).
5. **Launch blocked by the helper** — a crash, hang or missing Highball install must not stop the game. Pinned by envcheck cases (missing helper, helper exits 1, helper sleeps → 10 s timeout) (Task 5).
6. **CrossOver regressions** — the helper never runs for CrossOver runners. Pinned by an envcheck case (Task 5).

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `app/Package.swift`, `app/Package.resolved` | HighballKit dependency, `highball-env` target, `HighballEnvCore` library target | 1 |
| `app/Sources/HighballEnvCore/` (new) | panel mapping, owned-key filter, recipe subset, output formatting (testable) | 2, 3, 4 |
| `app/Sources/highball-env/main.swift` (new) | argument parsing, wiring | 3 |
| `app/Tests/HighballEnvCoreTests/` (new) | tests | 2, 3, 4 |
| `app/Sources/NotProtonApp/Resources/highball-db/` (new) | db snapshot | 4 |
| `scripts/refresh-highball-db.sh` (new) | copies `db/games` + `recipes` at a commit, writes `SOURCE` | 4 |
| `Makefile` | build `highball-env` into the payload | 1 |
| `dylib/feats/compat_run.sh`, `dylib/tests/envcheck.sh` | call helper, filter, export, forward | 5 |
| `dylib/feats/webpatch.c`, `dylib/hooks/hook_webpatch.c`, `dylib/tests/panel-behavior/*` | panel options for Highball tools | 6 |
| `NOTICE`, `README.md`, About credits, spec §5, `.claude/TODO.md` | docs | 8 |

---

### Task 0: Baseline

- [ ] Branch `feature/m2b-renderer-mapping` from `main` (done).
- [ ] Full check from the session notes; record the test count (553 at last run). It must not drop.

### Task 1: Dependency and empty helper

- [ ] Add the HighballKit package (exact tag), a `HighballEnvCore` library target (depends on HighballKit) and a `highball-env` executable target (depends on `HighballEnvCore`). `swift package resolve`; check `Package.resolved` keeps Sparkle 2.10.0.
- [ ] `main.swift` prints `# highball-env <HighballKit tag>` and exits 0.
- [ ] Makefile: `app-payload` copies the built `highball-env` into the payload; `make app` passes; Install copies it to `$np_support/highball-env` (follow how `appinfo` is installed; add to the payload manifest if there is one).
- [ ] Commit (after approval).

### Task 2: Panel variables → `BottleSettings`

- [ ] Failing tests, one per table row in Global Constraints, plus: `should leave renderer not explicit when CX_GRAPHICS_BACKEND is empty`, `should ignore an unknown CX_GRAPHICS_BACKEND value`, `should keep the user's WINEDLLOVERRIDES entries last`.
- [ ] Implement `PanelSettings.bottleSettings(environment: [String: String], engineID: String) -> BottleSettings`.
- [ ] Commit (after approval).

### Task 3: Environment output

- [ ] Failing tests: `should drop keys Proton-ish owns`, `should let user-typed DXMT_/D3DM_/DXVK_/MTL_ variables win`, `should join DXMT_CONFIG with ;`, `should reject values containing a newline`, `should print the renderer note as a comment`, `should print only an error note when the engine is missing`.
- [ ] Implement `HighballEnvironment.lines(env:userEnv:note:) -> [String]` and wire `main.swift`: args `--prefix <pfx> --engine <id> --appid <n>`; read panel variables from its own environment; `EngineStore().engine(id)`; `Bottle(url: prefix, settings:)`; `prepareDLSSBridge`, `writeDxvkConfig` (skip for WineD3D) as `WineRunner` does (`WineRunner.swift:143-146`); `environment(engine:renderer:)`; print.
- [ ] Commit (after approval).

### Task 4: Database snapshot and environment-only recipes

- [ ] `scripts/refresh-highball-db.sh <commit>`: shallow-fetch `gauthierpiarrette/highball-db` at the commit into a temp dir, copy `db/games/*.json` and `recipes/**/*.json` into the resource folder, write `SOURCE`, refuse to copy `db/derived` or `db/anticheat.json`. Run it once; commit the snapshot.
- [ ] Failing tests with fixture rows/recipes: `should apply the database row's renderer when the user picked Automatic`, `should not apply it when the user picked a renderer`, `should merge a recipe's environment step for the game`, `should apply dlloverride and dxvkconfig steps`, `should log and skip winver, registry, winetricks, copy and installer steps`, `should do nothing for an app id the database does not know`.
- [ ] Implement with HighballKit's `GameDB(directories:)`, `GameDBEntry.effectiveRenderer()`, `Recipe.load`, `RecipeRunner.rendererToApply`. Recipe matched when its id equals the row id (Highball `AppState.swift:389-393`).
- [ ] Commit (after approval).

### Task 5: Run script integration

- [ ] Failing envcheck cases with a fake `highball-env` script: exports its `KEY=VALUE` lines; drops owned keys and hostile lines (lowercase key, `$(…)` value is exported literally, never executed); logs `# note` lines; missing helper / exit 1 / no output → today's DXMT behaviour; hangs → killed after 10 s and fallback; CrossOver runtime → helper never called; generated launcher re-exports `DYLD_FALLBACK_LIBRARY_PATH`, `DYLD_FALLBACK_FRAMEWORK_PATH`, `DYLD_INSERT_LIBRARIES`.
- [ ] Implement in the Highball block (`compat_run.sh:178-199`): call `"$np_support/highball-env" --prefix "$WINEPREFIX" --engine "$np_build" --appid "$SteamAppId"` with a timeout, validate each line with the existing key filter, export, record the keys in `np_hb_keys` so they are forwarded with `--env`; keep `runtime.env` as the fallback when the helper gives nothing. Extend the launcher's DYLD re-export list.
- [ ] `make -s runcheck envcheck` green. Commit (after approval).

### Task 6: Panel options for Highball tools

- [ ] Failing panel-behavior cases: a Highball tool shows Automatic, D3DMetal, DXMT, DXVK, WineD3D (D3DMetal hidden when the tool's engine lacks the GPTK licence); CrossOver and FEX unchanged.
- [ ] `np_webpatch_set_renderer_gaps` alongside `np_webpatch_set_fex_tools`, filled in `hook_webpatch.c` from a per-tool file the app writes at Set Up (`tools/<name>/renderers`: one available renderer per line, from HighballKit's `rendererDir` checks). Filter `B` in `NP_CX_OPTIONS_BODY`.
- [ ] `make -s panel-behavior webpatch-fixtures` green. Commit (after approval).

### Task 7: End-to-end with the user (manual gate)

- [ ] Rebuild, Install, Set Up the Highball engine again.
- [ ] Add `WINEDEBUG=+loaddll` to the launch options; check `protonish-run.log` and `C:\highball` logs (`DXMT_LOG_PATH`/`DXVK_LOG_PATH`, they name the Direct3D implementation that served the process):
  - Emberward, Automatic → DXMT (also settles whether DXMT rendered before M2b)
  - Split Fiction (DX12), Automatic and D3DMetal → shim `d3d12.dll` then `apd12.dll`, reaches the menu. EA sign-in may block it; then note that and use BG3 for D3DMetal
  - Baldur's Gate 3 (force the Highball tool, it has a macOS version): Automatic (database says D3DMetal), DXMT, DXVK
  - WineD3D on any of them → Wine's builtin `d3d11.dll`
- [ ] Record results; anything broken becomes a TODO.

### Task 8: Docs and release

- [ ] `NOTICE`: HighballKit (GPL-3.0, link, pinned tag) and highball-db (CC0-1.0, commit from `SOURCE`). README Thanks + "Graphics on Highball" under "Using Highball" + changelog line. About credits.
- [ ] Spec §5: HighballKit route, keys Proton-ish owns, M2c for prefix-changing recipe steps.
- [ ] `.claude/TODO.md`: tick M2b; add M2c (prefix-changing recipe steps), live DB fetch, vkd3d.
- [ ] With the user's OK, bump `dylib/version.h` to `0.1.0-beta.3`; the PR body becomes the release notes.
