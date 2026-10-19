# Proton-ish: Highball runtime support — design

- **Date:** 2026-10-14
- **Status:** Approved in conversation, awaiting written-spec review
- **Repo:** https://github.com/MagnusPladsen/Proton-ish (fork of https://github.com/NotProtonNot/NotProton)

## 1. Intent

Proton-ish is a public GPLv3 fork of NotProton that brings Steam Play to the macOS
Steam client with a free Wine runtime option. v1 supports two runtimes:

- **CrossOver** — unchanged behaviour from upstream, including its licence check.
- **Highball** (https://github.com/gauthierpiarrette/highball) — its Wine 11 engine
  (built from CrossOver 26.3 sources), Rosetta only.

Upstream explicitly rejects non-CrossOver runtimes (README, `CONTRIBUTING.md` policy #2,
issue #37). This work lives only in the fork and is never proposed upstream.

### Success criteria

1. A user with Highball's Wine 11 engine installed and no CrossOver can install
   Proton-ish, select a `protonish-highball-*` compatibility tool in Steam, and launch a
   Windows game whose Steamworks calls (login, overlay) work through lsteamclient.
2. The CrossOver path behaves exactly as upstream at the merged upstream commit.
3. Existing NotProton users can switch to Proton-ish without losing game prefixes or
   per-game tool selections.
4. The fork complies with every licence and credit obligation in section 7.

### Out of scope for v1

- Highball's Wine 10 (Sikarugir) engine. `resolve.py` already resolves its hook
  constants (verified on `x64-sikarugir10.0_6-r21`), but `WINE_MODREF` offsets and
  lsteamclient's Wine 11.15 unix-call ABI are unverified on Wine 10. Follow-up work.
- Highball's arm64 / FEX engine line (not shipped to players yet).
- A source-built engine with Proton's steamclient patches (reference:
  https://github.com/Drustburn/steamplay-mac). Possible later replacement for
  binary patching if re-pinning becomes a burden.
- Running side by side with upstream NotProton.
- Notarisation (needs a paid Apple Developer account).

## 2. Architecture

### 2.1 `WineRuntime` abstraction

A Swift protocol `WineRuntime` in `app/Sources/NotProtonApp/Model/` with two
implementations: `CrossOverRuntime` (existing code moved behind the protocol, no
behaviour change) and `HighballRuntime`. Each implementation supplies:

| Concern | CrossOver | Highball |
|---|---|---|
| Discovery | `CrossOver*.app` in `/Applications`, `~/Applications`, manual paths (existing `CrossOverSource`) | `engines/*/manifest.json` under the Highball home (`$HIGHBALL_HOME`, else `config.json` `home`, else `~/Library/Application Support/Highball`); `Highball.app` in `/Applications` or `~/Applications` |
| Source root | `CrossOver.app/Contents/SharedSupport/CrossOver` | `engines/<id>/` (copies `engine/`, `frameworks/`, `renderers/`, `manifest.json`) |
| Identity | SHA-256 of `lib/wine/x86_64-unix/wine` (existing) | engine id + SHA-256 of `engine/bin/wine` |
| Layout | loader `lib/wine/x86_64-unix/wine`, FEX `lib/wine/aarch64-unix/wine.app/...`, `bin/wineserver*` | loader `engine/bin/wine`, server `engine/bin/wineserver`, libs `engine/lib/wine/{i386,x86_64}-windows`, `engine/lib/wine/x86_64-unix` |
| Access gate | `CrossOverLicense.requireValid` (unchanged) | none for the runtime; D3DMetal requires `apple-gptk-license-*` in the manifest's `acceptedLicenses` |
| Engine install (M2d, 2026-10-15) | the user's CrossOver | `highball-env install` (HighballKit's `EngineStore.install`) into Highball's standard home, manifest and licence text from the pinned Highball package; licence accepted only by the user in the app |
| Base env | `CX_ROOT`, `CX_HOME`, GPTK path (existing) | manifest `baseEnv` with `${frameworks}` → `root/frameworks` |
| Renderers | `CX_GRAPHICS_BACKEND` values (existing) | folders present under `root/renderers/` |
| Signing | extend existing entitlements (existing) | write fresh entitlements (section 4.6) |

`RunnerSetup`, `RunnerInstaller`, `RunnerStore`, `RunnerPatcher`, `PrefixTools` and
`SystemStatus` call through the protocol instead of hard-coding CrossOver paths. Their
existing closure parameters (`license:`, `verify:`, `stage:`, `patch:`) are the seams.

### 2.2 Shared, unchanged components

`NtdllPatcher`, `ntdll-patch/` (detours, `resolve.py`, `build*.sh`), `lsteamclient`,
`steam-shim`, `overlay-shim` and the dylib's Steam hooks are shared by both runtimes.
Both runtimes go through one pipeline: copy → verify hashes → patch ntdll → install
builtins → sign.

### 2.3 Supported builds

`RunnerBuild` in `SupportedRunner.swift` gains `runtime: RuntimeKind`
(`.crossover`, `.highball`). The allow-list stays hash-pinned. Each supported Highball
Wine 11 engine revision gets an entry: loader hash, clean and patched ntdll hashes for
x86_64 and i386, one Rosetta `CompatTool`.

### 2.4 Dylib and run script

- The app's `tools` TSV gains a `runtime` column: `name\tbuild\tflavor\truntime\tdisplay`.
  The strict parser in `dylib/feats/compat.c` accepts it and requires the `protonish`
  name prefix.
- `write_tool` writes a `runtime` file next to `flavor` and `build`; `remove_tool`
  removes it.
- `compat_run.sh` reads `runtime` (default `crossover`) and derives
  `CX_ROOT=$support/runners/<runtime>-<build>/root`. `CX_ROOT` stays a top-level assignment
  (CrossOver reads it, and `envcheck.sh` evaluates that block). M2 adds a `case "$np_runtime"`
  for Highball-specific setup when the second runtime exists.
- `PrefixTools.layout` mirrors the script's layout logic for app-side Wine tools
  (winecfg, regedit, winetricks, prefix rebuild).

## 3. On-disk layout

```
~/Library/Application Support/protonish/
  runners/crossover-<build>/root/
  runners/highball-<engine-id>/root/
  bridge/wine/<build>/<arch>/ntdll.dll
  tools
~/Library/Application Support/Steam/compatibilitytools.d/protonish-*/
```

- Every runner's content lives under `root/`, replacing the hard-coded `crossover-` /
  `CrossOver/` assumptions in `SupportPaths`, `RunnerStore`, `RunnerInstaller`
  (including the `crossover-[A-Za-z0-9.-]+-(x86_64|aarch64)-unix` regex),
  `DeploymentContent`, `compat_run.sh` (`:157`, `:305`, `:636`) and `lsteamclient/build.sh`.
- Tool names: CrossOver tools keep their existing names (`protonish`, `protonish-fex`,
  `protonish-26.3`, …) so users' per-game tool choices survive. New runtimes use
  `protonish-<runtime>-<engine-id>`, e.g. `protonish-highball-x64-crossover26.3-r25`.
  Display name example: `Highball Wine 11 (r25)`.
- Copies use `cp -c -R` (APFS clone) with `cp -R` fallback, as upstream.
- Prefix and runner marker files keep their upstream names (`notproton-build`,
  `notproton-msync`, `*.notproton-orig`, `notproton-template`, lock files). They are
  invisible to users, and keeping them means existing prefixes need no migration.
  `NOTPROTON_*` environment variables are also kept, because users' saved Steam launch
  options contain them.

## 4. Highball runner pipeline

Observed on `x64-sikarugir10.0_6-r21`; must be re-confirmed on the Wine 11 engine at the
start of milestone M2:

- The loader is `engine/bin/wine` (x86_64 Mach-O). `engine/lib/wine/x86_64-unix/` holds
  `ntdll.so` but no loader.
- The loader carries no entitlements.
- `ntdll.dll` keeps Wine's debug-trace strings (`build_module`, `alloc_module`), and
  `resolve.py` resolves all constants for both arches with payloads fitting in padding.

### 4.1 Discover

Scan `engines/*/manifest.json`. An engine whose loader hash matches a pinned
`RunnerBuild` is installable. Anything else shows its state (section 5).

### 4.2 Copy

Copy the contents of `engines/<id>/engine/` flat into `runners/.highball-<id>.new/root`, so
`root/lib/wine/...` has the same shape as a CrossOver clone and the shared patching, builtin
and bridge code works unchanged. Copy `frameworks/`, `renderers/` and `manifest.json` next to
it, write `root/runtime.env` from the manifest's `baseEnv` (with `${frameworks}` expanded),
then rename to `runners/highball-<id>/root`. Run `scrubDownloadMarkers` (removes
`com.apple.quarantine`, `com.apple.provenance`).

The engine ships two loaders: `bin/wine` (unsigned launcher, used as the build's identity hash)
and `lib/wine/x86_64-unix/wine` (the real loader). Games run the latter, exactly as with
CrossOver, and it is the one that gets the entitlements (implemented in M2a).

### 4.3 Verify

Loader SHA-256 and clean `ntdll.dll` hashes for `x86_64-windows` and `i386-windows`
against the pinned entry.

### 4.4 Patch ntdll

Constants from `resolve.py`; payloads built with `build.sh` / `build32.sh` and checked in
like upstream's. Entries added to `NtdllPatcher.byBuild`, `resolve.py PINNED`,
`apply.py` and `build-ntdll.sh`. M2 starts by confirming the `WINE_MODREF` offsets
hard-coded in `detour.c` (x64 `+0x30/+0x60/+0x68`) and `detour32.c` (i386
`+0x18/+0x30/+0x34`) against the Wine 11 engine. If they differ, the detours get
per-build offsets.

### 4.5 Install builtins

`lsteamclient.dll` (i386, x86_64) and `lsteamclient.so` (x86_64) into
`root/engine/lib/wine/...` via the existing `RunnerPatcher.installBuiltins`, with the
layout supplied by the runtime. M2 confirms lsteamclient (built against Wine 11.15)
loads and makes unix calls correctly on the engine.

### 4.6 Sign

For a loader without entitlements, write a fresh plist with
`com.apple.security.cs.allow-dyld-environment-variables` and
`com.apple.security.cs.disable-library-validation` (Highball injects
`libhbaudiobuf.dylib` via `DYLD_INSERT_LIBRARIES`), then
`codesign -f -s - --options runtime --entitlements <plist>`. `RunnerPatcher.verify`
checks these entitlements on status refresh. The CrossOver signing path is unchanged.

### 4.7 Launch (`setup_highball_env`)

- `WINELOADER=root/engine/bin/wine`, `WINESERVER=root/engine/bin/wineserver`,
  `WINEDLLPATH` with `root/engine/lib/wine/x86_64-windows` first,
  `PATH=root/engine/bin:...`.
- Manifest `baseEnv` applied with `${frameworks}` expanded.
- Graphics (amended 2026-10-15, M2b): the run script asks `highball-env`, which links
  Highball's HighballKit, for the environment Highball would use. It maps the panel's
  launch options onto `BottleSettings`, applies the game's highball-db row and the
  environment-only steps of its recipe, and returns `Bottle.environment()`; renderer folders,
  the GPTK licence gate, the D3DMetal timestamp shim and fallbacks (DXMT → DXVK → WineD3D)
  are Highball's. Proton-ish keeps `WINELOADER`, `WINESERVER`, `WINEPREFIX`, `WINEDLLPATH`,
  `PATH`, `WINEDEBUG` and `WINEMSYNC`. Any helper failure keeps `runtime.env` + DXMT. The
  prefix-changing recipe steps are M2c.
- Prefix recipes, M2c (2026-10-19, user decisions in brackets): the `registry`, `file` and
  `copy` steps of the game's highball-db recipe are applied to the Steam prefix before the
  launch. `installer`, `winetricks` and `winver` keep the "not applied yet" log note; the
  bundled database has none.
  - `highball-env --install-path <game folder> --applied <marker>` plans the prefix steps next
    to the environment. Registry steps become one REGEDIT4 file,
    `$WINEPREFIX/drive_c/protonish-recipe.reg`, imported as `C:\protonish-recipe.reg` (amended
    2026-10-19 during implementation: inside `drive_c`, so the import does not depend on the
    `Z:` drive); the run script imports it with `wine reg import` under the game's own
    environment, right after `highball_environment`, the way `import_prefix_settings` already
    does, so Highball's msync mismatch (highball#32) cannot occur. `file` and `copy` steps are written by `highball-env` itself, no Wine run. A
    target under `Program Files (x86)/Steam/steamapps/common/<installdir>/` is rewritten to the
    real game folder from `--install-path`, because the game lives on the Mac disk and reaches
    the prefix through a drive letter, not under drive C. Other targets stay under `drive_c`.
  - Once per prefix per database version [user decision]: the marker
    `$STEAM_COMPAT_DATA_PATH/protonish-recipe` records recipe id, highball-db commit and engine
    build; the run script writes it only after the import succeeds. Same recipe and commit: skip
    with one log line. A missing `copy` target (game reinstalled) counts as not applied, as in
    HighballKit's `artifactsPresent`. No rollback [user decision]: a changed recipe overwrites,
    keys it no longer names stay, as in Highball.
  - `optIn` is ignored [user decision]: every recipe applies, the environment steps of M2b
    included, so Half-Life 2 and RaceRoom behave like every other row.
  - A recipe pinned to another engine line (`engine: x64-sikarugir10.0_6-r5`) applies by default
    with a log line naming both engines [user decision]. The Status screen's Highball section
    gets the switch "Apply game fixes verified on other engines", default on, stored in
    `<support>/recipe-other-engines` and passed to `highball-env --other-engines apply|skip`;
    off skips the whole recipe with a log note. One game can override the switch with the
    Steam launch option `PROTONISH_RECIPE_OTHER_ENGINES=0` or `=1` [user decision, option C].
    The switch's footer text in the app and the README's Highball section name the launch
    option, so the user learns about it where the switch is. Another revision of the same line
    always applies.
  - Code: `HighballEnvCore/PrefixRecipe.swift` holds the pure planning (REGEDIT4 text for
    `REG_SZ` and `REG_DWORD`, key escaping, target rewrite, skip decision, engine-line policy)
    and one applier; `highball-env` prints `# recipe: …` lines the run script logs; the run
    script gains `apply_prefix_recipe`. Manual check: Portal 2 (`autoexec.cfg` in `portal2/cfg`,
    `VideoMemorySize` in `user.reg`, one HDR map load without device loss) and Warframe (the
    launcher draws and updates); both recipes were verified by Highball on the Wine 10 line.
- Graphics, M2d (2026-10-15): the app writes `<support>/renderers` (per Highball tool, the
  renderers `highball-env renderers` reports available) and the dylib passes the tools lacking
  D3DMetal or DXVK to the panel, which hides those entries. `highball-env --exe` applies
  Highball's DirectX 12-only take-over; without the licence the game stays and the log says so.
- Default tool (M2d): `<support>/default-tool` is the app's request (name sets, empty clears
  when ours); the dylib applies it at Steam start through `SetCompatToolMapping(0, …)`, records
  Steam's current default in `<support>/steam-default-tool`, and with no request adopts a
  Highball tool only when Steam has no default (option C, user decision).
- Windows user: after `wineboot`, the script reads the real profile folder under
  `drive_c/users/` (excluding `Public`) and links it to `steamuser`, instead of assuming
  `users/crossover`. This handles Highball engine patch 0001.
- Game Mode launcher `.app` bundles use `com.protonish.launcher.$app_id` and link the
  runtime's loader.

## 5. Error handling

| Condition | User-facing result |
|---|---|
| No Highball and no CrossOver | "Install CrossOver or Highball to use Proton-ish." |
| Highball present, only Wine 10 engines | "Proton-ish needs Highball's Wine 11 engine. Turn it on in Highball → Engines." |
| Wine 11 engine with unpinned hash | "Highball engine `<id>` isn't supported yet." + link to the fork's issue tracker |
| CrossOver licence invalid | Existing upstream message, unchanged |
| ntdll hash mismatch before or after patching | Abort, restore `ntdll.dll.notproton-orig`, show the error (existing behaviour) |
| Loader signing fails | Abort runner install, show the `codesign` output |
| D3DMetal requested without GPTK licence | Option hidden; launch falls back to DXMT with a log line |
| Highball deletes or updates an engine after cloning | No effect; Proton-ish uses its own clone |
| Recipe `.reg` import fails | Launch continues, marker not written, log line; retried next launch |
| Recipe step type without support (`installer`, `winetricks`, `winver`, `dotnet48` requirement) | Log line "not applied yet"; rest of the recipe applies |

## 6. Migration from NotProton

Runs once when Proton-ish detects any of: `~/Library/Application Support/notproton/`,
`notproton.dylib` injected into Steam, or `compatibilitytools.d/notproton-*`.

1. Prompt: "NotProton is installed. Switch to Proton-ish?" Requires Steam to be closed,
   as upstream's installer already does.
2. Move runners: rename `notproton/runners/crossover-<b>/CrossOver` →
   `protonish/runners/crossover-<b>/root`. Re-verify hashes.
3. Remap games: rewrite `notproton-*` → `protonish-*` in Steam's `config.vdf`
   `CompatToolMapping`, reusing the existing `legacyToolName` / `legacyHolders` logic.
4. Prefixes stay in `steamapps/compatdata/<appid>/pfx` untouched; marker files keep
   their upstream names (section 3), so no per-prefix changes are needed.
5. Uninstall NotProton using upstream's uninstall routine (restore the Steam bundle,
   remove the dylib and `notproton-*` tools). Old template prefixes are deleted and
   rebuilt on first launch.
6. Delete `notproton/` only after every step succeeds. On any failure, move everything
   back and show the error.

## 7. Fork compliance

- Keep `LICENSE` (GPLv3), `NOTICE`, `LICENSE.lsteamclient`, `LICENSE.steam-shim`,
  `LICENSE.fonts` unchanged.
- GPLv3 §5a: add "Modified by Proton-ish contributors, 2026" to `NOTICE`; add a dated
  `CHANGES` section to the README.
- Every release binary corresponds to a public git tag (source availability, §6).
- Redistribute no more Valve material than upstream does.
- README opens with: "Proton-ish is a fork of NotProton by NotProtonNot" (linked), and
  states it is not affiliated with or endorsed by NotProton, Valve, CodeWeavers or
  Highball. The same credit appears in the app's About screen.
- New app icon (placeholder in v1); no upstream, Valve or CodeWeavers artwork.
- Issue templates route to the fork's tracker. `CONTRIBUTING.md` rewritten for the fork,
  including how to pin a new Highball engine.
- Never redistribute CrossOver, Highball or D3DMetal files. The CrossOver licence check
  stays; no trial workarounds.
- Keep the `upstream` remote and merge `upstream/main` regularly.

### Rebranding touchpoints

- `app/Info.plist`: `CFBundleIdentifier` → `com.magnuspladsen.protonish`;
  `SUFeedURL` → `https://github.com/MagnusPladsen/Proton-ish/releases/latest/download/appcast.xml`;
  `SUPublicEDKey` → new key. The private key goes into the `SPARKLE_PRIVATE_KEY`
  Actions secret. **Leaving upstream's feed and key in place would let upstream releases
  silently replace Proton-ish installs.**
- `compat_run.sh:1340`: `com.notproton.launcher.*` → `com.protonish.launcher.*`.
- Dylib name `notproton.dylib` → `protonish.dylib`; support dir `notproton/` → `protonish/`.
- App name, window titles and user-visible strings: `NotProton` → `Proton-ish`.
  Internal Swift module and type names may stay as-is to keep upstream merges cheap.
- `.github/workflows/release.yml`: artifact names and appcast for Proton-ish.

## 8. Testing

- After every milestone: `swift test` (app), `dylib/tests/envcheck.sh`,
  `dylib/tests/compatcheck.c`, and the lint workflow all pass.
- New unit tests:
  - `HighballRuntime` discovery, identity and layout against a sample engine tree
    (including `HIGHBALL_HOME` and `config.json` overrides).
  - Manifest `baseEnv` expansion.
  - Fresh-entitlements signing path for a loader with no entitlements.
  - TSV `runtime` column parsing in the dylib.
  - Run-script Windows-user detection.
  - Migration: config.vdf remap, record-file rename, rollback on failure.
- End-to-end on a real Mac with Highball's Wine 11 engine: install → launch a free Steam
  game and confirm Steam login and overlay work → launch one DXMT or D3DMetal game.
- CrossOver: covered by the existing test suite and the no-behaviour-change rule for M1.
  No CrossOver licence is available for manual testing.

## 9. Milestones

Each milestone leaves `main` building with all tests passing.

1. **M0, rebrand and compliance.** Section 7 in full. CrossOver behaves exactly as upstream.
2. **M1, runtime abstraction.** Introduce `WineRuntime`, move CrossOver behind it,
   generic `root/` layout, `runtime` column and file. No behaviour change.
3. **M2, Highball Wine 11 runner.** Starts with the verification gate: install the
   Wine 11 engine, confirm loader location, entitlements, `resolve.py` output,
   `WINE_MODREF` offsets and lsteamclient ABI. If the gate fails, stop and revise this
   spec. Then sections 4 and 5.
   M2 must also make runner bookkeeping read the runtime from the directory name: today
   `SupportPaths.runtime(forBuild:)` looks the build up in `SupportedRunners` and falls back to
   `crossover`, and `RunnerStore.clonedBuilds` drops the prefix. With a second runtime, a
   Highball build that leaves `SupportedRunners` could not be removed and its templates would be
   deleted (M1 review finding). Write the failing test first, with a real `highball-<id>` clone.
4. **M3, NotProton migration.** Section 6.
5. **M4, release pipeline.** Own appcast and Sparkle key, tagged signed release. Brew tap
   afterwards.
6. **M5, automation.** Section 10.

M2 also adds in-app engine notices: the Status screen shows when an installed Highball
engine is newer than every pinned build ("Highball engine `<id>` is not supported yet; an
update to Proton-ish will add it"), and when a Proton-ish update adds support for an engine
the user already has ("Set up `<id>` now"). App updates themselves come from Sparkle's
existing "Check for Updates…" once M4 publishes the appcast.

## 10. Automation (M5)

Goal: keep Proton-ish current with upstream NotProton and new Highball engines with as
little manual work as possible, while a human approves every release.

- **Upstream sync.** A scheduled GitHub Actions workflow (daily) fetches `upstream/main`,
  merges it into a `sync/upstream-<date>` branch and opens a PR against `main`. CI (full
  build, tests, `brandcheck`) runs on the PR. Conflicts are left in the PR for a human.
- **Highball engine re-pin.** A scheduled workflow (daily) reads Highball's engine
  manifests from https://github.com/gauthierpiarrette/highball-engine releases. For each new
  Wine 11 engine it downloads the tarball (sha256-verified against the manifest), runs
  `ntdll-patch/resolve.py`, builds the detour payloads, adds the `SupportedRunners` and
  `NtdllPatcher` entries and opens a PR. The PR is labelled "needs game test": a human
  launches one Steam game on that engine before merging.
- **Release on merge.** Merging a PR that bumps `dylib/version.h` triggers `release.yml`:
  build, sign the appcast with the Sparkle key from the `SPARKLE_PRIVATE_KEY` secret,
  publish the GitHub release. Users get it through Sparkle in the app.
- **Human gate.** No auto-merge. Every sync or re-pin PR and every release needs one human
  approval, because a bad Steam hook or a wrong pin breaks Steam Play for every user.

## 11. Risks

| Risk | Mitigation |
|---|---|
| lsteamclient ABI differs on Highball's Wine 11 | M2 verification gate before any feature work |
| Highball releases engine revisions often | Hash pinning keeps installed runners stable; `resolve.py` automates re-pinning; documented in `CONTRIBUTING.md` |
| Upstream merges conflict with the refactor | Keep internal names, isolate changes behind `WineRuntime`, merge upstream often |
| Steam client updates break injection | Inherited from upstream; pick up their fixes via merges |
| Gatekeeper friction from ad-hoc signing | Same as upstream (`APP_SIGN_ID ?= -`); document in README |
| CrossOver regressions undetected | Existing tests and the no-behaviour-change rule in M1 |
