# M2d: One-Click Highball Engine and Default Tool — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A user with only Steam and Proton-ish gets a working Highball setup: Proton-ish downloads Highball's Wine engine itself (no Highball app), asks once about Apple's D3DMetal licence, sets it up, and can make it Steam's default tool for every Windows game. Also from M2b's follow-ups: Automatic sends DirectX 12-only games to D3DMetal, and the Graphics dropdown hides what the engine can't run.

**Architecture:** Everything Highball-specific stays Highball's code via HighballKit. `highball-env` gains two subcommands: `install` (wraps `EngineStore.install(manifest, accepted:, progress:)`) and `accept` (wraps `EngineStore.accept(license:engine:)`). The engine manifest and Apple's licence text come from the pinned Highball package checkout at build time (`spike/engines/<id>.json`, `spike/d3dmetal-license.txt`), so bumping the HighballKit pin also bumps them. Engines go into Highball's standard home (`HighballPaths()`), so the existing Set Up flow (copy from Highball's engine folder) and `highball-env` launches work unchanged, and a later Highball app install shares the engine. The default tool is set from inside Steam: the dylib already wraps `CCompatManager::SetCompatToolMapping` (`np_compat_map_tool`, app `0` = global default); the app writes a request file and the dylib applies it when Steam's compat manager appears.

**Tech Stack:** Swift 6.4 / SwiftUI / swift-testing, C (dylib), POSIX sh, GNU Make.

**Spec:** `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` §4 (discovery), §5. Task 9 amends them.

## Global Constraints

- **Supported engine:** `x64-crossover26.3-r19` only (the one with payload pins). The Makefile copies only manifests listed in `HIGHBALL_ENGINES` (default `x64-crossover26.3-r19`) into the payload.
- **Downloads:** only the URLs and sha256 in Highball's manifest, through HighballKit (it verifies hashes and sizes). Proton-ish hosts nothing. Total for r19 ≈ 440 MB; the UI states the size from the manifest before starting.
- **D3DMetal licence:** shown in full (`d3dmetal-license.txt` from the pinned package) with Accept / Not now before the download, exactly as Highball's `engine install --accept-d3dmetal`. Declining still installs the engine; D3DMetal stays off (HighballKit's gate). Acceptance can be given later from the Highball row ("Enable D3DMetal…") via `highball-env accept`. Never accept on the user's behalf, never pre-tick.
- **Where the helper runs from:** the app runs `highball-env` from its own bundle payload (`InstallPayload.locate().highballEnv`), so it works before Install deployed it.
- **User decisions (2026-10-15):** engines go into Highball's standard home, shared with the Highball app (1a); the default tool follows option C below.
- **Default tool (option C):** after a successful Set Up of a Highball engine, the app turns the switch on automatically **only if Steam has no global default tool yet** (the dylib reports app 0's mapping in a status file it writes at manager registration: `~/Library/Application Support/protonish/steam-default-tool`), and shows "Highball is now Steam's default for Windows games" with the switch beside it. If a default exists (e.g. a CrossOver tool), nothing changes and only the switch is offered. Switch "Use Highball for all Windows games" on the Status screen. On: request file `~/Library/Application Support/protonish/default-tool` containing the tool name; the dylib maps app 0 to it once per Steam start when the current global mapping differs, and logs it. Off: the file holds an empty line; the dylib clears app 0 only if it is currently one of Proton-ish's tools. Remove Everything deletes the file and clears app 0 if it is a Proton-ish tool.
- **DX12-only:** `highball-env --exe <path>` and HighballKit's `Bottle.direct3D12TakeOver(…, programNeedsDirect3D12: { ProgramNeeds.direct3D12Only(program: exe) })`, with the same inputs Highball passes (no per-game override, row renderer, `rendererExplicit`). The run script passes the game's exe when the launch command names one under the game folder.
- **Dropdown filtering (M2b Task 6):** at Set Up and after `accept`, the app writes `tools/<tool>/renderers` (one available renderer per line, from HighballKit's `Renderer.availability`); the dylib passes per-tool gaps to the panel JS; a hidden mode shows as Automatic.
- No behaviour change for CrossOver. `make brandcheck` clean; commits via `/commit` per task (user approved per-task commits on 2026-10-15); README changelog; never commit to `main`.

## Review Focus

1. **Licence accepted without the user** — no code path may pass `accepted: ["apple-gptk-license-…"]` unless the user clicked Accept in this session's sheet or used "Enable D3DMetal…". Pinned by a Swift test on the view model (Task 3) and a helper test that `install` without `--accept-d3dmetal` leaves `acceptedLicenses` empty (Task 2).
2. **Global default clobbered** — the dylib must not change app 0 when the user picked a non-Proton-ish default, unless the switch is on; turning the switch off must not clear someone else's default. Pinned by compatcheck cases (Task 5).
3. **Half-installed engine used** — an interrupted download must not leave an engine `HighballSource.discover` reports as ready. HighballKit stages and renames; verify and pin with a test that kills the helper mid-install (Task 2).
4. **DX12 take-over overriding the user** — an explicit Graphics choice always stands. Pinned by a helper test (Task 6).

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Makefile` | copy engine manifests + licence text into the payload | 1 |
| `app/Sources/highball-env/main.swift`, `app/Sources/HighballEnvCore/EngineInstall.swift` (new) | `install`, `accept` subcommands, progress lines | 2 |
| `app/Sources/NotProtonApp/Model/HighballInstaller.swift` (new), `SystemStatus.swift`, `Views/StatusView.swift` | download flow, licence sheet, progress, Enable D3DMetal | 3, 4 |
| `dylib/feats/compat.c` / `compatsvc.c` / hooks, `dylib/tests/compatcheck.c` | default-tool request | 5 |
| `app/Sources/NotProtonApp/...` (switch + Remove Everything) | default-tool switch | 5 |
| `app/Sources/HighballEnvCore/LaunchEnvironment.swift`, `dylib/feats/compat_run.sh`, `dylib/tests/envcheck.sh` | `--exe`, DX12 take-over | 6 |
| `dylib/feats/webpatch.c`, `dylib/hooks/hook_webpatch.c`, panel tests, app Set Up | dropdown filtering | 7 |
| README, spec, TODO | docs, beta.4 | 9 |

---

### Task 0: Baseline
- [ ] Branch `feature/m2d-engine-install` from `main` after PR #9 merges (or from `feature/m2b-renderer-mapping` if it has not). Full check; record counts (553 + 30).

### Task 1: Ship the manifest and licence text
- [ ] Makefile: copy `$(HIGHBALL_PKG)/spike/engines/<id>.json` for each id in `HIGHBALL_ENGINES` to `payload/highball-engines/` and `spike/d3dmetal-license.txt` to `payload/highball-engines/d3dmetal-license.txt`, where `HIGHBALL_PKG` is the resolved checkout (`app/.build/checkouts/highball`). Fail the build if a listed manifest is missing.
- [ ] Payload plumbing like `highball-db.json` (Located, missing list, PayloadState not needed: these stay in the app bundle, not deployed). Test: `InstallPayload.locate` reports a missing manifest.
- [ ] Commit.

### Task 2: `highball-env install` and `accept`
- [ ] Failing tests against a fake manifest whose components point at `file://` fixtures (HighballKit downloads with URLSession; confirm `file://` works, else serve with a local `Process`-started `python3 -m http.server` in the test): installs into `HighballPaths(home:)`; without `--accept-d3dmetal` `acceptedLicenses` is empty; with it, it holds `apple-gptk-license-2023-08-17`; a hash mismatch fails and leaves no engine; `accept` adds the id to an installed engine; progress lines have the form `progress <component> <bytes> <total>`.
- [ ] Implement `EngineInstall.install(manifest:accept:paths:progress:)` and `EngineInstall.accept(engineID:paths:)`; `main.swift` dispatches on the first argument (`install`, `accept`, else today's environment mode). Final line `installed <id>` or `# error: …`; exit 1 on failure for these subcommands.
- [ ] Commit.

### Task 3: Download flow in the app
- [ ] Failing tests for `HighballInstaller` (process runner injected): parses progress lines into a fraction; maps exit/`# error` to a user-facing failure; passes `--accept-d3dmetal` only when `licenceAccepted == true`; after success triggers the existing Set Up path for that engine.
- [ ] Status screen, Highball section when no supported engine is found: replace "Not found. Install Highball from gethighball.com." with a **Download Highball engine (440 MB)** button. It opens a sheet: what gets downloaded and from where (Highball's GitHub releases), Apple's licence text in a scroll view, buttons **Accept and download** / **Download without D3DMetal** / **Cancel**. Progress row while downloading; cancel kills the helper.
- [ ] Strings localized (en + zh-Hans) like the rest of the UI; `l10ncheck` green.
- [ ] Commit.

### Task 4: Enable D3DMetal later
- [ ] Highball row: when the engine's manifest lacks the licence id, an **Enable D3DMetal…** button opens the licence sheet (Accept / Cancel) and runs `highball-env accept`; refresh the row and rewrite `tools/<tool>/renderers` (Task 7).
- [ ] Tests for the view model path. Commit.

### Task 5: Default tool switch
- [ ] compatcheck (failing first): request names a Proton-ish tool and app 0 maps elsewhere → mapped once and logged; request empty and app 0 is a Proton-ish tool → cleared; request empty and app 0 is someone else's → untouched; no file → untouched; second manager registration in the same Steam run → no second call.
- [ ] dylib: read `~/Library/Application Support/protonish/default-tool` (bounded read, tool name validated against registered tools) in `np_compat_register_crossover` after registration; apply via `np_compat_map_tool(mgr, 0, …)` and `np_compatsvc_state_changed()`.
- [ ] dylib also writes app 0's current mapping (tool name or empty) to `steam-default-tool` at manager registration, before applying any request.
- [ ] App: switch on the Status screen ("Use Highball for all Windows games", shown when a Highball tool is set up), writes the file; after Set Up, turn it on automatically only when `steam-default-tool` exists and is empty (option C), with the notice; tests for: no default → on + notice, CrossOver default → off, status file missing (Steam never ran with this build) → off; footnote "Applies the next time Steam starts". Remove Everything clears it. Tests for the file contents and Remove Everything.
- [ ] Commit.

### Task 6: DirectX 12-only games on Automatic
- [ ] Failing helper tests with a fixture PE that imports only `d3d12.dll` (build the import table bytes in the test, or check in a tiny PE produced by mingw in `dylib/tests` fixtures): Automatic + engine with D3DMetal (licensed) → D3DMetal; explicit DXMT → stays DXMT; row says DXMT and not explicit → stays (Highball's rule); no `--exe` → unchanged.
- [ ] Run script: pass `--exe "$game_exe"` when the launch command's first `.exe` argument resolves to a file; envcheck case for the argument.
- [ ] Commit.

### Task 7: Dropdown hides what the engine can't run
- [ ] As M2b Task 6, with availability from HighballKit (`Renderer.availability(in:)`) written to `tools/<tool>/renderers` at Set Up and after `accept`. panel-behavior cases. Commit.

### Task 8: End-to-end with the user (manual gate)
- [ ] On the user's Mac, temporarily move `~/Library/Application Support/Highball` aside (with permission), Remove Everything, install the new build, download the engine through Proton-ish (decline D3DMetal first), Set Up, switch on the default tool, restart Steam, launch Among Us without touching its Compatibility settings. Then Enable D3DMetal and launch a DX12 game if one is installed. Restore the Highball folder afterwards.

### Task 9: Docs and release
- [ ] README Quick start: requirements, install Proton-ish, Open Anyway, **Download engine** in Proton-ish, switch on "Use Highball for all Windows games", play. Highball app becomes optional. Changelog line. Spec amendments. TODO ticks. With the user's OK, `0.1.0-beta.4`.
