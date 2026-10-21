# Highball engines with a new Wine build: automated pinning

Date: 2026-10-21. Status: approved 2026-10-21.
Follows `scripts/sync/pin-engines.sh` (PR #49), which pins revisions that reuse a Wine build
Proton-ish already supports.

## 1. Intent

Highball publishes a new Wine build (`gauthierpiarrette/highball-engine` release
`engine-wine-11.0-<timestamp>-<serial>-<name>`) every week or two, and engine revisions that use
it follow in a HighballKit release. Today the engines job (`scripts/sync/highball-engine.sh`)
opens an issue for each new build, and a person does M2a Task 5 by hand
(`docs/superpowers/plans/2026-10-14-m2a-highball-runner.md`): download the engine, run
`ntdll-patch/resolve.py`, build or reuse detour payloads, record clean and patched ntdll and
loader hashes, edit five files.

The owner's words: "For a new Wine build it can do the hashing and open a PR for review." The
machine does all of the mechanical work; a person reviews and merges, because a new Wine build is
new code that `lsteamclient` and the detours have never met.

Evidence that most of it is mechanical: engine build 0024 (r25) hooks at the same offsets as
build 0021 (r19) and takes r19's payloads unchanged, only the image hashes differ
(`ntdll-patch/build-ntdll.sh`, `NtdllPatcher.highballBuild0024`).

## 2. Goals

- G1. A new Wine build on a supported engine line (today `x64-crossover26.3`) becomes a PR, not an
  issue, when its ntdll resolves to the same hook constants as a pinned build (same hooks, stolen
  bytes, caves, exports). The PR reuses that build's payloads and carries every hash.
- G2. A new Wine build whose constants differ becomes an issue, as today, but with `resolve.py`'s
  report, the clean hashes and the differences from the nearest pinned build already in it.
- G3. The PR pins the newest manifest revision that uses the new build. Once that PR is merged,
  later revisions on the same build are pinned by `pin-engines.sh` with no person involved.
- G4. Same safety as the hand-made pins: the app keeps refusing any engine whose bytes don't
  match the pinned hashes, and CI's `NtdllPatcherTests` loops cover the new entries.

## 3. Non-goals

- Building new detour payloads in CI (mingw). That is the G2 case; it stays human work.
- Launching a game. No CI runner can; that is what the review is for.
- The Wine 10 Sikarugir line and arm64 lines. Different line, different spike.
- CrossOver builds. Out of scope; NotProton upstream pins those.

## 4. Anti-goals

- A PR with a new Wine build that merges itself. G1 PRs never get auto-merge and never bump
  `dylib/version.h`; the reviewer bumps when merging is meant to ship.
- Hashes computed from anything but the bytes Highball publishes, verified against the
  manifest's `sha256` before use.
- Duplicated patch logic. Patched hashes come from the existing `ntdll-patch/apply.py`, so the
  tool that pinned r19 and r25 by hand is the one that pins the next build.

## 5. Constraints

- The engines job runs on `ubuntu-latest` with `SYNC_TOKEN`; `resolve.py` needs `capstone`
  (pip, pin the version). The Wine download is about 335 MB.
- The Makefile's `app-payload` step fails when a `HIGHBALL_ENGINES` id has no manifest in the
  pinned HighballKit package, so a pin can only name a manifest that package already has.
- Highball publishes Wine builds no manifest ever uses (`0015-coreaudio-trial`,
  `0019-forza-trial`, …), and release serials are not in time order.
- Files a pin touches today, all of which the PR must edit consistently:
  `ntdll-patch/resolve.py` (`PINNED`, keyed by clean ntdll sha),
  `ntdll-patch/apply.py` (`PAYLOAD_BY_CLEAN_SHA`),
  `ntdll-patch/build-ntdll.sh` (`HB_<build>_*` variables and flavor case),
  `app/Sources/NotProtonApp/Model/NtdllPatcher.swift` (a `highballBuild<serial>` table),
  `app/Sources/NotProtonApp/Model/SupportedRunner.swift` (`RunnerBuild`), `Makefile`
  (`HIGHBALL_ENGINES`).

## 6. Decided

- D1. Two outcomes per new build: G1 PR (constants match a pinned build) or G2 issue (they don't,
  or a step fails). No third path.
- D2. "Match" means every value `resolve.py` reports for both architectures equals the pinned
  build's: hook RVA, stolen bytes, cave RVA and size, placement, `wm`, `resume`, `load_path`,
  every export address, image base, machine and magic. Any difference is G2.
- D3. Payloads are reused by resource name (`detour2-hb-r19`, `detour32-hb-r19` today); no new
  `.bin` files and no `Package.swift` change in a G1 PR.
- D4. The new table in `NtdllPatcher.swift` is named after the engine build serial
  (`highballBuild0025`), shaped like `highballBuild0024`.
- D5. Download default: same rule as `pin-engines.sh`: the new revision becomes the download when
  its `minMacOS` is no newer than the app's minimum; otherwise it goes before the current one.
- D6. The PR body says what a reviewer must do before merging: launch a game through the new
  engine, then bump the version (`scripts/sync/bump-release.sh`) if it should ship.

Settled after the builder check (the spec writer's calls, not the owner's):

- D7. Detection is driven by manifests, not release tags. A Wine build matters only when a
  manifest in the pinned HighballKit package uses it: `pin-engines.sh` already reports those as
  `unknown <id> <url>`. That is the trigger for G1 or G2. Trial builds no manifest uses are never
  downloaded and never become issues. The release-tag loop in `highball-engine.sh` and
  `scripts/sync/known-highball-engine` are retired.
- D8. Because of D7, a G1 PR waits until the HighballKit bump that brings the manifest has merged
  (the highball job's PR merges itself within about 20 minutes). G1 never bumps HighballKit, so
  the two jobs never edit the same pin.
- D9. One PR or issue per Wine build, ever. The branch is `sync/engine-<wine sha, first 12>`; a
  PR or issue for that build in any state, open or closed, stops the job from making another. A
  reviewer turns a build down by closing its PR; reopening it is the way back.
- D10. Only analysis failures become G2 issues: `resolve.py` refusing the ntdll, or constants
  that differ (D2). Download, checksum, network and GitHub errors fail the job, which shows red
  and tries again on the next run.
- D11. `pin-engines.sh` runs on every highball job run against the pinned package, not only on a
  HighballKit bump (a change to #49). When it pins something without a bump, the job opens the
  same kind of self-merging, releasing PR. So revisions that arrive while a G1 PR is open are
  pinned by themselves after it merges, without waiting for the next HighballKit release.
- D12. When several unknown Wine builds are present at once, only the one used by the newest
  revision is handled; older ones are superseded and skipped, as `pin-engines.sh` already does.

## 7. Left to the builder

- Script layout: extend `highball-engine.sh` or add a script it calls; reuse `pin-engines.sh`'s
  Swift insertion code or share it.
- How `resolve.py`'s output is compared (its `--sh` mode prints shell variables already).
- How the job reads the pinned package's manifests: a `swift package resolve` checkout, or the
  files at the pinned tag through `gh api`, which lets it stay on `ubuntu-latest`. Either way it
  reads the pinned version (D8), never Highball's latest.
- Test fixtures: a tiny fake engine tarball cannot carry a real ntdll, so the comparison and file
  edits are tested against recorded `resolve.py` output; one real run against build 0024's
  download proves the pipeline end to end (it must reproduce r25's pinned hashes exactly).

## 8. Success

- Re-running the job against engine build 0024 as if it were new produces a PR whose hashes equal
  r25's pinned ones byte for byte, and whose Swift and Python edits pass the full check.
- The next real Highball Wine build reaches a review PR, or a G2 issue with the report, without
  anyone running a command.
