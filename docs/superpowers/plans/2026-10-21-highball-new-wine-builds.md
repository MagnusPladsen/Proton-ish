# Highball engines with a new Wine build: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a manifest in the pinned HighballKit package uses a Wine build Proton-ish has not pinned, the engines job downloads it, hashes it, compares its ntdll constants with the pinned builds, and opens a review PR that pins it (same constants) or an issue with the report (different constants).

**Architecture:** Python does the analysis and the file edits (`scripts/sync/engine_pins.py`, shared with `pin-engines.sh`; `scripts/sync/wine_build.py`), shell does the GitHub and git flow (`scripts/sync/highball-engine.sh`), as the other sync scripts do. `ntdll-patch/resolve.py` and `apply.py` stay the only code that understands ntdll; the new code calls them. Every external command (gh, download, resolve, apply) is overridable by an environment variable so `scripts/sync/test-sync.sh` runs offline.

**Tech Stack:** POSIX sh, Python 3 (`python3 -I`, stdlib only plus capstone for `resolve.py`), GitHub Actions `ubuntu-latest`, Swift (`swift test`) for verification.

**Spec:** `docs/superpowers/specs/2026-10-21-highball-new-wine-builds-design.md`

## Global Constraints

- Start from `main` with #49 (`pin-engines.sh`) and #50 (auto-merge retry) merged; rebase `docs/highball-new-wine-builds` onto it first.
- A G1 PR never gets auto-merge and never bumps `dylib/version.h` (spec §4).
- Hashes come only from bytes whose `sha256` matched the manifest's `components.wine.sha256` (spec §4).
- Patched hashes come from `ntdll-patch/apply.py`, payloads from `app/Sources/NotProtonApp/Resources/*.bin` (spec §4, D3). No new `.bin` files, no `Package.swift` change.
- "Match" compares, per architecture: `hookRVA stolen caveRVA caveSize placement wm resume load_path exports imageBase machine magic fill` (spec D2, plus `fill`, which `apply.py` checks).
- One PR or issue per Wine build in any state, branch `sync/engine-<wine sha256, first 12>` (D9).
- Only analysis failures become issues; download, checksum, network and gh errors exit non-zero (D10).
- Engine lines handled: the ones already in `HIGHBALL_ENGINES` (today `x64-crossover26.3`).
- capstone is pinned: `python3 -m pip install --user capstone==5.0.9` (the version the hand pins used).
- Python runs as `python3 -I`; a script that imports a sibling adds its own directory to `sys.path` explicitly.
- Bot commits use `git_identity` from `common.sh`; labels `upstream-sync` and `highball-engine`.

## Review Focus

1. A download that is truncated or has the wrong sha256: the job fails before any PR or issue exists. Test in Task 5.
2. Two revisions in the pinned package use the same unknown build: one PR, pinning the newest revision only (G3). Test in Task 5.
3. A reviewer closed the build's PR without merging: no new PR or issue on the next run (D9). Test in Task 5.
4. One architecture's ntdll makes `resolve.py` exit non-zero: that is an analysis failure, so an issue with the error text, not a red job (D10). Test in Task 3.
5. A Wine URL whose tag has no `-<4 digits>-` serial: names fall back to the sha prefix (`hb-1d1a130c0108`, `highballBuild1d1a130c0108`). Test in Task 4.

---

### Task 1: Shared Swift and Makefile pin edits, and a dry run for `pin-engines.sh`

**Files:**
- Create: `scripts/sync/engine_pins.py`
- Modify: `scripts/sync/pin-engines.sh` (becomes `exec python3 -I scripts/sync/engine_pins.py pin "$@"` after the `cd`)
- Test: `scripts/sync/test-sync.sh` (the "Highball engine pins" section)

**Interfaces:**
- Produces, in `engine_pins.py`:
  - `add_runner_build(runner_text: str, source: str, engine: str, display: str, needs_newer_macos: bool, hashes: dict | None = None) -> str | None`: copies `source`'s `RunnerBuild` block under `engine` with the comment line and placement `pin-engines.sh` uses today; `hashes` is `{"loader": str, "clean": {"x86_64-windows": str, "i386-windows": str}, "patched": {...}}` and replaces those values in the copy. `None` when `source` has no block.
  - `add_patch_entry(patcher_text: str, source: str, engine: str, table: str | None = None) -> str | None`: adds `"<engine>": <table or source's table>,` after `source`'s line. `None` when `source`'s entry is inline.
  - `add_bundled_engine(makefile_text: str, engine: str) -> str`
  - `tool_display(source_display: str, engine: str, manifest_display: str) -> str`
  - `pinned_engines(makefile_text: str) -> list[str]`, `app_minimum_macos(package_swift_text: str) -> str`, `needs_newer_macos(manifest: dict, minimum: str) -> bool`
  - CLI `engine_pins.py pin [--dry-run] <manifest dir>`: today's `pin-engines.sh` behaviour and output; `--dry-run` prints the same lines and writes nothing.

- [ ] **Step 1: Write the failing test.** In the pins section, after the r28 case's first `runpin`, add a case that runs `sh scripts/sync/pin-engines.sh --dry-run engines` on a fresh `pins` fixture with the r28 manifest:
  `is "a dry run says what it would pin" "pinned x64-crossover26.3-r28 like x64-crossover26.3-r27" "$(cat "$work/out")"` and
  `hasnt "and writes nothing" 'x64-crossover26.3-r28' "$runner"`. Copy `engine_pins.py` into the fixture in `pins()`.
- [ ] **Step 2:** `make -s synccheck`. Expected: FAIL on the two new checks.
- [ ] **Step 3:** Move the Python from `pin-engines.sh` into `engine_pins.py` behind the functions above; add `--dry-run`.
- [ ] **Step 4:** `make -s synccheck`. Expected: every check passes, old and new.
- [ ] **Step 5:** Commit `Share the engine pin edits and give pin-engines.sh a dry run`.

### Task 2: `resolve.py --json` and `--pinned`

**Files:**
- Modify: `ntdll-patch/resolve.py` (`__main__` block only)
- Test: `scripts/sync/test-sync.sh`, new section "resolve.py modes"

**Interfaces:**
- Produces: `python3 -I ntdll-patch/resolve.py --json <ntdll.dll>` prints `json.dumps(resolve(path), sort_keys=True)` (integers stay integers). `--pinned <clean sha256>` prints `PINNED[sha]` as JSON, or exits 1 with nothing on stdout when the sha is not pinned. Both take exactly one argument.

- [ ] **Step 1: Write the failing test.** `--pinned e606762e531e8d749cb4075a3fea2ba063f4833dad9903074ec1762f91efc1a3` prints JSON with `hookRVA` `296179` (0x484f3) and `wm` `"r15"`; `--pinned 00…00` exits 1. When the installed engine `~/Library/Application Support/Highball/engines/x64-crossover26.3-r25` exists, `--json` on its `lib/wine/x86_64-windows/ntdll.dll` reports `hookRVA` `296179` and `caveRVA` `499872` (0x7a0a0). Skip the section with a `  skip` line when `python3 -c 'import capstone'` fails (CI's lint job has no capstone).
- [ ] **Step 2:** Run it. Expected: FAIL (unknown option).
- [ ] **Step 3:** Add the two modes next to `--sh`.
- [ ] **Step 4:** Run it. Expected: PASS locally (capstone in a venv: `python3 -m venv "$TMPDIR/cs" && "$TMPDIR/cs/bin/pip" install capstone==5.0.9`, then run the section with that python first on `PATH`).
- [ ] **Step 5:** Commit `Let resolve.py print its constants and pins as JSON`.

### Task 3: `wine_build.py check`

**Files:**
- Create: `scripts/sync/wine_build.py`
- Test: `scripts/sync/test-sync.sh`, new section "Wine build check"; fixtures as recorded JSON written by the test

**Interfaces:**
- Consumes: Task 2's `--json` and `--pinned`; `engine_pins.pinned_engines`.
- Produces: `wine_build.py check <engine dir>`, run from the repo root. `<engine dir>` holds `bin/wine` and `lib/wine/{x86_64,i386}-windows/ntdll.dll`. Prints one JSON object and exits 0 whatever the verdict:
  `{"loader": str, "clean": {"x86_64-windows": str, "i386-windows": str}, "match": str | null, "patched": {...} | null, "differences": [str], "report": str}`.
  - `match`: the newest engine in `HIGHBALL_ENGINES` whose clean shas (read from its `RunnerBuild` in `SupportedRunner.swift`) have `--pinned` constants equal to the new ntdlls' on every Global Constraints field, and whose `NtdllPatcher.swift` entry is a named table. Otherwise `null`.
  - `patched`: on a match, the sha256 of `$APPLY <src> <dst> <payload>` per architecture. The payload is the file in `app/Sources/NotProtonApp/Resources/` whose sha256 equals `--pinned`'s `payload`.
  - `differences`: against the newest pinned engine, one line per field, `"<arch> <field> <pinned> != <new>"`, integers as hex. Empty on a match.
  - `report`: `resolve.py`'s text report for both ntdlls, or its stderr when it exits non-zero. A non-zero `resolve.py` gives `match: null` and the error in `differences`.
  - Commands come from `RESOLVE` (default `python3 -I ntdll-patch/resolve.py`) and `APPLY` (default `python3 -I ntdll-patch/apply.py`).

- [ ] **Step 1: Write the failing tests.** Stub `RESOLVE` with a script answering `--json`, `--pinned` and the plain report from files the case writes. Fake ntdlls are any distinct bytes; their sha256 keys the stub's answers. Cases:
  - Constants equal to r27's pins: `match` is `x64-crossover26.3-r27`, `patched` holds the stub `APPLY`'s output hashes, `differences` is `[]`.
  - `hookRVA` 0x484f4 on x86_64: `match` is null, `differences` is `["x86_64-windows hookRVA 0x484f3 != 0x484f4"]`.
  - The stub exits 1 for the i386 ntdll with `cannot find build_module`: `match` is null, and `differences[0]` contains `cannot find build_module` (Review Focus 4).
  - `loader` and `clean` equal the sha256 of the fixture files.
- [ ] **Step 2:** `make -s synccheck`. Expected: FAIL.
- [ ] **Step 3:** Implement `check` in `wine_build.py`.
- [ ] **Step 4:** `make -s synccheck`. Expected: PASS.
- [ ] **Step 5:** Commit `Check a new Highball Wine build against the pinned ones`.

### Task 4: `wine_build.py pin`

**Files:**
- Modify: `scripts/sync/wine_build.py`
- Test: `scripts/sync/test-sync.sh`, "Wine build pin", on copies of the real `resolve.py`, `apply.py`, `build-ntdll.sh`, `NtdllPatcher.swift`, `SupportedRunner.swift`, `Makefile`, `app/Package.swift`

**Interfaces:**
- Consumes: Task 3's JSON on stdin; Task 1's functions.
- Produces: `wine_build.py pin <engine id> <manifest json path>` reads a matching `check` result on stdin and edits, in place:
  - `resolve.py` `PINNED`: two entries keyed by the new clean shas, values copied from the matched build's entries (same `payload`), after the matched i386 entry, with the comment `# <engine id> (engine build <serial>): same offsets as <match>, pinned by scripts/sync/wine_build.py`.
  - `apply.py` `PAYLOAD_BY_CLEAN_SHA`: the two shas mapped to the matched build's payload file names, after the matched lines.
  - `build-ntdll.sh`: `HB_<SERIAL>_CLEAN_X86_64/I386` and `HB_<SERIAL>_PATCHED_X86_64/I386` after the matched build's variables; a detection case echoing `hb-<serial>`; the flavor in both "pass FLAVOR=" and "unknown flavor" lists; a tools case with `BUILD=<engine id>`; a `patch_one` case using the matched build's payload names.
  - `NtdllPatcher.swift`: `static let highballBuild<serial> = <matched table>` after the matched table, with a comment naming the engine, and `"<engine id>": highballBuild<serial>,`.
  - `SupportedRunner.swift`: `add_runner_build` with the new hashes; display from `tool_display`; placement from `minMacOS`.
  - `Makefile`: `add_bundled_engine`.
  - Serial: the 4 digits in `-(\d{4})-` of the Wine URL's tag; without them, the first 12 characters of the Wine sha256 (Review Focus 5).
  - Exits 2 without writing when stdin's `match` is null.

- [ ] **Step 1: Write the failing tests.** Feed a recorded matching result (match `x64-crossover26.3-r27`, made-up hashes `aa…`, `bb…`, …) for engine `x64-crossover26.3-r90`, URL tag `engine-wine-11.0-20261101T000000Z-0025-test`. Assert:
  - `resolve.py` has the two keys.
  - `apply.py` maps them to `detour2-hb-r19.bin` and `detour32-hb-r19.bin`.
  - `build-ntdll.sh` has `HB_0025_CLEAN_X86_64=aa…` and `hb-0025)` twice.
  - `NtdllPatcher.swift` has `static let highballBuild0025 = highballBuild0024` and `"x64-crossover26.3-r90": highballBuild0025,`.
  - r90's `RunnerBuild` carries the new `loaderSHA256` and is the last Highball entry.
  - `Makefile` ends `HIGHBALL_ENGINES` with r90.
  - A URL tag without a serial gives `highballBuild<sha12>`.
  - `match: null` on stdin exits 2 and leaves every file unchanged.
  - The edited `build-ntdll.sh` passes `sh -n` and `shellcheck`.
- [ ] **Step 2:** `make -s synccheck`. Expected: FAIL.
- [ ] **Step 3:** Implement `pin`.
- [ ] **Step 4:** `make -s synccheck`. Expected: PASS.
- [ ] **Step 5:** Commit `Pin a new Highball Wine build that matches a pinned one`.

### Task 5: The engines job: manifests in, PR or issue out

**Files:**
- Modify: `scripts/sync/highball-engine.sh` (replace the release-tag loop), `scripts/sync/common.sh`, `.github/workflows/upstream-sync.yml` (engines job: capstone step, comment), `scripts/sync/test-sync.sh` (replace the "Highball engines" section)
- Delete: `scripts/sync/known-highball-engine`

**Interfaces:**
- Consumes: Task 1 (`--dry-run`), Task 3, Task 4.
- Produces, in `common.sh`:
  - `fetch_manifests <HighballKit version> <dir>`: a sparse, depth-1 clone of `gauthierpiarrette/highball` at tag `v<version>`, copying `spike/engines/*.json` into `<dir>`. Task 6 uses it.
  - `pr_ever_exists <branch>` and `issue_ever_exists <text>`: like `pr_exists` and `issue_exists`, with `--state all`.
- Flow of `highball-engine.sh`:
  1. Read the pin from `app/Package.swift`. Get the manifests from `HIGHBALL_MANIFESTS` when set, else `fetch_manifests`.
  2. `pin-engines.sh --dry-run`. Take the last `unknown` line (D12, G3).
  3. Stop with a log line when `pr_ever_exists sync/engine-<sha12>` or `issue_ever_exists <sha12>`.
  4. Download with `DOWNLOAD` (default `curl -fsSL --retry 3 -o`). Check sha256 and `size` against the manifest. Extract `engine/bin/wine` and both `ntdll.dll` files with `tar -xzf`. Any failure exits 1 (D10).
  5. Run `wine_build.py check`.
  6. If it matched: `git checkout -B sync/engine-<sha12> origin/main`, run `wine_build.py pin`, commit as the bot, push, and run `gh pr create` with the title `sync: Highball engine <id>, Wine build <serial>`. No auto-merge, no bump. The body lists the hashes, `match`, and the D6 reviewer steps: launch a game through `<id>`, then run `scripts/sync/bump-release.sh "<text>"` if it should ship.
  7. Otherwise: `gh issue create` with the title `Highball engine <id>: Wine build <serial> needs new detour work`. The body holds `differences`, the clean hashes, `report` in a fenced block, and the M2a Task 5 steps.
- Workflow: before the engines job's script step, add a step `python3 -m pip install --user capstone==5.0.9`.

- [ ] **Step 1: Write the failing tests.** Fixture: a tarball the test builds, holding `engine/bin/wine` and the two `ntdll.dll` files; `DOWNLOAD` copies it. Stub `RESOLVE`/`APPLY` as in Task 3, and set `HIGHBALL_MANIFESTS`. Cases:
  - Matching build: `pr create .* --head sync/engine-<sha12>` is logged, no `pr merge`, the branch's `version.h` is unchanged, and the branch's `Makefile` has the id.
  - Different constants: `issue create .* needs new detour work`, and no branch pushed.
  - Wrong sha256: exit 1, no `create` in the log (Review Focus 1).
  - Two revisions on the unknown build: one `pr create`, naming the newer id (Review Focus 2).
  - The stub's `pr list --state all` returns `7`: no download, no `create` (Review Focus 3).
  - Nothing unknown: nothing downloaded, no `create`.
- [ ] **Step 2:** `make -s synccheck`. Expected: FAIL.
- [ ] **Step 3:** Implement. Delete `known-highball-engine` and the old release-tag cases. Update the `cp` lists in `checkout()`.
- [ ] **Step 4:** `make -s synccheck && make -s scriptcheck`. Expected: PASS.
- [ ] **Step 5:** Commit `Turn new Highball Wine builds into review PRs or issues`.

### Task 6: `highball.sh` pins revisions on every run (D11)

**Files:**
- Modify: `scripts/sync/highball.sh`, `scripts/sync/test-sync.sh`

**Interfaces:**
- Consumes: `fetch_manifests` (Task 5), `pin-engines.sh`.
- Produces: `pin-engines.sh` runs on every run, against the manifests of the HighballKit version the branch ends up with: the new one on a bump, the pinned one otherwise. `HIGHBALL_MANIFESTS` still overrides. With no kit or db change but at least one pin, the branch is `sync/highball-engines-<last pinned id>`, and it gets the usual `bump_release` and auto-merge, with the changelog line `Supports Highball engine <revisions>.` Nothing pinned and nothing newer still logs `are current` and exits 0.

- [ ] **Step 1: Write the failing test.** Kit and db current, and the manifests have an r28 on r27's build. `pr create .* --head sync/highball-engines-x64-crossover26.3-r28` is logged, `pr merge --auto` is logged, and the branch's `version.h` is bumped. The existing "nothing newer reports current" case still passes with manifests holding nothing new.
- [ ] **Step 2:** `make -s synccheck`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make -s synccheck`. Expected: PASS.
- [ ] **Step 5:** Commit `Pin same-Wine Highball engines on every sync run`.

### Task 7: Real build, docs, full check

**Files:**
- Modify: `README.md` (Maintenance bullet "Highball engines", one changelog line via `changelog_line`)

- [ ] **Step 1: Real run on build 0024.** Download r25's Wine URL from `app/.build/checkouts/highball/spike/engines/x64-crossover26.3-r25.json` into the scratchpad, check its sha256 (`1d1a130c0108…`), extract, and run `wine_build.py check` with capstone. Expected: `loader` `8cce786bce298f601a415f2e2952a82512c02243689df5b40e0af8e6e63991ca`, `clean` `e606762e…`/`54137f36…`, `patched` `e51f33124c32…`/`9d204e484d62…` (the full values in `SupportedRunner.swift`), `match` `x64-crossover26.3-r27`.
- [ ] **Step 2: Real pin.** Pipe that result into `wine_build.py pin x64-crossover26.3-r90 <r25 manifest with id r90>`. Then `cd app && swift test --no-parallel --filter 'WineRuntimeTests|NtdllPatcherTests|DefaultToolTests|HighballSourceTests|DetectionTests|HighballInstallerTests'`. Expected: all pass, r90 is `HighballInstaller.build`. Then `git checkout --` the edited files.
- [ ] **Step 3: Docs.** The Maintenance bullet says new Wine builds that match a pinned build become review PRs, the others issues with the report, and that trial builds no manifest uses are ignored. Add one changelog line.
- [ ] **Step 4: Full check.** The FULL CHECK command in `docs/superpowers/plans/2026-10-14-m2a-highball-runner.md` (there is no single `make` target), plus `make -s synccheck`. Expected: exit 0.
- [ ] **Step 5:** Commit `Document the Wine build pipeline`. Push, and open the PR with no version bump.
