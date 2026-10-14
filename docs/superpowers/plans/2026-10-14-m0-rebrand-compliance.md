# M0: Proton-ish Rebrand and Fork Compliance — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the NotProton fork into "Proton-ish": its own identity, update feed, on-disk names, user-visible branding and licence/credit compliance, with CrossOver behaviour otherwise identical to upstream.

**Architecture:** Literal-by-literal renames at each source of truth plus its known hard-coded duplicates, guarded by a new `brandcheck` script that fails while any upstream identifier remains in a renamed bucket. Internal names (Swift module `NotProtonApp`, C `np_`/`NOTPROTON_*_H` symbols, `NOTPROTON_*` env vars, prefix marker files) are deliberately kept so upstream merges stay cheap and existing prefixes keep working.

**Tech Stack:** Swift 6 / SwiftPM / SwiftUI + Sparkle 2.10 (app), C (dylib), POSIX sh (`compat_run.sh`, checks), Python 3 (l10n tooling), GNU Make, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` (sections 7 and 9/M0). Task 10 amends spec §3 and §6 for the kept identifiers.

## Global Constraints

- Display name: `Proton-ish`. Identifier form: `protonish`.
- Bundle ID: `com.magnuspladsen.protonish`.
- Game launcher bundle IDs: `com.protonish.launcher.$app_id`.
- Support dir: `~/Library/Application Support/protonish/`; caches: `~/Library/Caches/protonish/`.
- Dylib filename: `protonish.dylib`.
- Compat tool name prefix: `protonish` (must keep containing `proton` for Steam Cloud, `dylib/feats/compat.c:16-18`).
- `SUFeedURL`: `https://github.com/MagnusPladsen/Proton-ish/releases/latest/download/appcast.xml`.
- `SUPublicEDKey`: a newly generated key. Upstream's key `rDOXzJ+vt12aWeu9hATgvz6q46MlRcgR4gbTfj5YuWQ=` must not remain anywhere.
- Never modify `LICENSE`, `LICENSE.fonts`, `LICENSE.lsteamclient`, `LICENSE.steam-shim`.
- KEEP unchanged (merge cost / user data): Swift module and target names (`NotProtonApp`, `NotProtonAppTests`, executable `NotProtonApp`), C header guards and `NOTPROTON_VERSION`, all `NOTPROTON_*` environment variables, the localStorage key `NotProtonLaunchMigrated_`, and prefix/runner marker files (`notproton-build`, `notproton-msync`, `*.notproton-orig`, `notproton-template`, `.notproton-*.lock`, `notproton-game-drive`, `notproton-hidden-controllers`, `notproton-settings.*`, `notproton-icon.source`, `.notproton-icon-*`, `.notproton-write-probe-*`, `*.notproton-pending`).
- Never commit secrets. The Sparkle private key lives outside the repo.
- Commits: use the `/commit` skill (user rule). No pushes without asking the user.
- Toolchain: Xcode 27 (matches upstream CI `.github/workflows/app.yml:20-27`).

## Review Focus

1. **Upstream identifiers left in an unrenamed duplicate** (e.g. a second hard-coded `Application Support/notproton`) → the app and dylib would disagree on paths and Steam Play would silently not register. Pinned by `brandcheck` sections in Tasks 2–4.
2. **Sparkle still trusting upstream** → a Proton-ish install would accept upstream's signed update and be replaced by NotProton. Pinned by the `updates` brandcheck section in Task 5.
3. **Release workflow committing/tagging as `NotProtonNot`** (`.github/workflows/release.yml:66-67`) → fork releases impersonate upstream's identity. Pinned by the `release` brandcheck section in Task 7.
4. **Run-script mark mismatch** — `RUN_SCRIPT_MARK` in `compat.c:486` must equal line 2 of `compat_run.sh` byte for byte, or the dylib treats its own tool dirs as foreign and prunes/refuses them. Pinned by `compatcheck` (already asserts the mark) plus the `tools` brandcheck section in Task 4.
5. **Localization catalog drift** — renaming a source string without re-keying `Localizable.xcstrings` (or breaking its exact formatting) leaves untranslated UI and fails `l10ncheck`. Pinned by running `make -s l10ncheck` in Task 6.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `dylib/tests/brandcheck.sh` (new) | Fails while upstream identifiers remain, per section | 1 |
| `Makefile` | `brandcheck` target; renamed paths, artifacts, defaults domain | 1–7 |
| `app/Sources/NotProtonApp/Support/SupportPaths.swift` | Support dir, dylib name, tool prefix filter | 2–4 |
| `dylib/util/file.c`, `dylib/feats/compat.c`, `dylib/feats/compatsvc.h` | dylib-side support path, tool prefix, mark, sentinel | 2, 4 |
| `dylib/feats/compat_run.sh` | Run script paths, mark, launcher ID, user alerts | 2, 4, 5, 6 |
| `app/Sources/NotProtonApp/Model/SupportedRunner.swift` | Tool names | 4 |
| `app/Info.plist` | Bundle ID, name, icon name, feed, key | 5, 7 |
| `app/Sources/NotProtonApp/Resources/Localization/Localizable.xcstrings` | UI strings | 6, 8 |
| `scripts/rebrand_strings.py` (new, dev tool) | Rewrites UI strings and catalog keys consistently | 6 |
| `.github/workflows/app.yml`, `release.yml` | Artifact names, release identity | 7 |
| `helpers/icon.swift` | Distinct placeholder icon colours | 7 |
| `app/Sources/NotProtonApp/Support/AboutCredits.swift` (new) | Fork credit + no-affiliation text | 8 |
| `app/Sources/NotProtonApp/App.swift` | Window title, About menu | 6, 8 |
| `README.md`, `NOTICE`, `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/*` | Compliance docs | 9 |
| `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` | Amend kept identifiers | 10 |

### Standard verification command (referred to as **FULL CHECK**)

Run from the repo root. Every task's final verification runs this; each command must exit 0.

```bash
make all overlay-shim iconmaker appinfo \
 && make -s l10ncheck sigcheck callscheck webpatch-fixtures peicon-fixtures panel-behavior \
      spawn-env compatcheck compatsvc-check shortcutcheck launch-shell envcheck buildcheck \
      settingscheck routecheck bridgecheck gamedrivecheck launchercheck seedcheck \
      scriptcheck runcheck \
 && make -s app-tests
```

(`l10ncheck` needs the app's `.stringsdata`, which `make app-tests` / `swift build` produce; if it reports "build the app first", run `cd app && swift build && cd ..` and re-run.)

---

### Task 0: Toolchain and green baseline

**Files:** none modified.

- [ ] **Step 1: Confirm Xcode 27 is selected**

Run: `xcodebuild -version && swift --version`
Expected: `Xcode 27.x` and a Swift 6.3+ compiler. If it shows Xcode 26.x, run `sudo xcode-select -s /Applications/Xcode_27.0.app` (or wherever Xcode 27 is installed). Stop and ask the user if Xcode 27 is not installed.

- [ ] **Step 2: Install check prerequisites**

Run: `brew install shellcheck node && make dobby`
Expected: shellcheck 0.11.x on PATH (`shellcheck --version`), `node --version` prints, `make dobby` completes.

- [ ] **Step 3: Run FULL CHECK on the untouched branch**

Run: FULL CHECK (see above).
Expected: every target exits 0. Record the `swift test` summary line (number of tests) in the task report. If anything fails, STOP and report the failure verbatim — do not start renaming on a red baseline.

---

### Task 1: `brandcheck` guard script

**Files:**
- Create: `dylib/tests/brandcheck.sh`
- Modify: `Makefile` (add target after the `seedcheck` target, ~line 101)

**Interfaces:**
- Produces: `sh dylib/tests/brandcheck.sh [section...]` — sections `support dylib tools identity updates strings release docs`; no args = all. Exit 0 when clean, 1 with `file:line: text` listing otherwise. `make brandcheck` runs all sections.

- [ ] **Step 1: Write the check script**

Create `dylib/tests/brandcheck.sh`:

```sh
#!/bin/sh
# Fails while an upstream NotProton identifier remains in a bucket Proton-ish renames.
# Usage: brandcheck.sh [support|dylib|tools|identity|updates|strings|release|docs]...
set -u

cd "$(git rev-parse --show-toplevel)" || exit 2

# Paths that may name upstream: credit docs, licences, the spec/plans, this script.
EXCLUDE=":(exclude)docs/superpowers :(exclude)LICENSE* :(exclude)NOTICE :(exclude)README.md :(exclude)CONTRIBUTING.md :(exclude).github/ISSUE_TEMPLATE :(exclude)dylib/tests/brandcheck.sh :(exclude)scripts/rebrand_strings.py"

failed=0

# Pathspecs below contain globs meant for git, not the shell
set -f

# check <section> <extended-regex>
check() {
    section=$1; pattern=$2
    # shellcheck disable=SC2086
    hits=$(git grep -n -E -e "$pattern" -- . $EXCLUDE 2>/dev/null || true)
    if [ -n "$hits" ]; then
        printf '==> brandcheck %s: upstream identifier /%s/ still present\n%s\n' "$section" "$pattern" "$hits"
        failed=1
    fi
}

run_section() {
    case $1 in
    support)
        check support 'Application Support/notproton'
        check support 'supportDirName = "notproton"'
        check support 'notproton-steam-bundles\.json'
        ;;
    dylib)
        check dylib 'notproton(\.arm64|\.x86_64)?\.dylib'
        check dylib 'Info\.plist\.before-notproton'
        check dylib 'notproton\.log'
        ;;
    tools)
        check tools 'notproton(-fex|-preview|-26\.3)'
        check tools 'TOOL_DIR_NAME +"notproton"'
        check tools 'legacyToolName = "notproton"'
        check tools 'hasPrefix\("notproton"\)'
        check tools 'notproton\.none'
        check tools '# notproton CrossOver compatibility tool shim'
        ;;
    identity)
        check identity 'com\.notproton\.'
        ;;
    updates)
        check updates 'NotProtonNot/NotProton/releases'
        check updates 'rDOXzJ\+vt12aWeu9hATgvz6q46MlRcgR4gbTfj5YuWQ='
        ;;
    strings)
        # User-visible "NotProton" outside comments. Skips NotProtonApp/NotProtonLaunchMigrated (regex),
        # and the fork credit (AboutCredits.swift, catalog lines naming NotProtonNot).
        hits=$(git grep -n -E 'NotProton([^A-Za-z]|$)' -- \
                 'app/Sources/*.swift' 'app/Sources/*.xcstrings' 'dylib/*.c' 'dylib/*.h' 'dylib/feats/compat_run.sh' \
                 ':(exclude)app/Sources/NotProtonApp/Support/AboutCredits.swift' 2>/dev/null \
               | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*(//|#|\*|/\*)' \
               | grep -v 'NotProtonNot' || true)
        if [ -n "$hits" ]; then
            printf '==> brandcheck strings: user-visible "NotProton" still present\n%s\n' "$hits"
            failed=1
        fi
        check strings '\[notproton\]'
        check strings 'notproton-(run|wine)\.log'
        ;;
    release)
        check release 'NotProton\.(app|zip|txt|icon|icns)'
        check release 'name: NotProton$'
        check release 'user\.name NotProtonNot'
        check release 'NotProtonNot@users\.noreply'
        check release 'app-icon NotProton'
        check release '<string>NotProton</string>'   # CFBundleName, CFBundleIconFile, CFBundleIconName
        ;;
    docs)
        for f in NOTICE README.md CONTRIBUTING.md; do
            grep -q 'Proton-ish' "$f" || { echo "==> brandcheck docs: $f does not mention Proton-ish"; failed=1; }
        done
        grep -q 'fork of NotProton' README.md || { echo "==> brandcheck docs: README lacks the fork credit"; failed=1; }
        grep -q 'not affiliated' README.md || { echo "==> brandcheck docs: README lacks the no-affiliation statement"; failed=1; }
        grep -q 'Modified by Proton-ish contributors' NOTICE || { echo "==> brandcheck docs: NOTICE lacks the modification notice"; failed=1; }
        [ -d .github/ISSUE_TEMPLATE ] || { echo "==> brandcheck docs: .github/ISSUE_TEMPLATE missing"; failed=1; }
        ;;
    *)
        echo "brandcheck: unknown section $1" >&2; exit 2 ;;
    esac
}

if [ $# -eq 0 ]; then
    set -- support dylib tools identity updates strings release docs
fi
for s in "$@"; do run_section "$s"; done

if [ $failed -eq 0 ]; then
    echo "==> brandcheck: clean ($*)"
fi
exit $failed
```

- [ ] **Step 2: Add the Makefile target**

Insert after the `seedcheck` target block in `Makefile` (after line ~100, before `envcheck:`):

```make
.PHONY: brandcheck
brandcheck:
	@sh dylib/tests/brandcheck.sh
```

- [ ] **Step 3: Run it to verify it fails on the unrenamed tree**

Run: `make brandcheck; echo "exit=$?"`
Expected: many `==> brandcheck <section>:` blocks across every section and `exit=2` from make (script exit 1). This is the failing test for Tasks 2–9.

- [ ] **Step 4: Lint the new script**

Run: `shellcheck dylib/tests/brandcheck.sh && make -s scriptcheck`
Expected: no shellcheck findings; scriptcheck passes (it lints `git ls-files` scripts, so `git add dylib/tests/brandcheck.sh` first if scriptcheck does not see it).

- [ ] **Step 5: Commit**

```bash
git add dylib/tests/brandcheck.sh Makefile
```
Commit via `/commit` with subject: `Add brandcheck guard for the Proton-ish rebrand`.

---

### Task 2: Support directory → `protonish`

**Files:**
- Modify: `app/Sources/NotProtonApp/Support/SupportPaths.swift:1,7,18`
- Modify: `app/Sources/NotProtonApp/Model/SteamModifications.swift:8`
- Modify: `dylib/util/file.c:60`
- Modify: `dylib/feats/compat.c:424`
- Modify: `dylib/feats/compat_run.sh:20,1310,1378`
- Modify: `Makefile:390`
- Modify: `bridge/fetch-valve.sh:21`, `bridge/verify.sh:27`, `lsteamclient/build.sh:69,78,79`, `ntdll-patch/build-ntdll.sh:13`, `steam-shim/build.sh:31`
- Test: `app/Tests/NotProtonAppTests/DetectionTests.swift:222-229`, `PrefixToolsTests.swift:34,42`, `RunnerSwitchTests.swift:336`, `UninstallTests.swift:58`, `dylib/tests/envcheck.sh:42`, `dylib/tests/shortcut-launch.py:21`

**Interfaces:**
- Produces: `SupportPaths.supportDirName == "protonish"`; C `np_support_path()` base `/Library/Application Support/protonish`; shell `$np_support` = `$HOME/Library/Application Support/protonish`.

- [ ] **Step 1: Update tests to expect the new path (failing test)**

Run:
```bash
sed -i '' 's#Application Support/notproton#Application Support/protonish#g' \
  app/Tests/NotProtonAppTests/DetectionTests.swift \
  app/Tests/NotProtonAppTests/PrefixToolsTests.swift \
  app/Tests/NotProtonAppTests/RunnerSwitchTests.swift \
  app/Tests/NotProtonAppTests/UninstallTests.swift \
  dylib/tests/envcheck.sh dylib/tests/shortcut-launch.py
git grep -n -E '"notproton"' -- app/Tests/NotProtonAppTests/DetectionTests.swift app/Tests/NotProtonAppTests/PrefixToolsTests.swift app/Tests/NotProtonAppTests/RunnerSwitchTests.swift app/Tests/NotProtonAppTests/UninstallTests.swift
```
For each remaining `"notproton"` hit printed, open the line: if it builds a support-dir path (e.g. `appending(path: "notproton")` next to `Application Support`), change it to `"protonish"`; if it is a compat tool name, leave it for Task 4.

- [ ] **Step 2: Run the affected tests to verify they fail**

Run: `cd app && swift test --no-parallel --filter 'DetectionTests|PrefixToolsTests|RunnerSwitchTests|UninstallTests' ; cd ..`
Expected: FAIL on the path assertions just changed.

- [ ] **Step 3: Rename the sources of truth and duplicates**

In `SupportPaths.swift`:
```swift
// Path construction for the Proton-ish support directory and Steam
```
```swift
    static let supportDirName = "protonish"
```
```swift
    // ~/Library/Application Support/protonish
```

In `SteamModifications.swift:8` change `"notproton-steam-bundles.json"` to `"protonish-steam-bundles.json"`.

In `dylib/util/file.c:60`:
```c
    static const char base[] = "/Library/Application Support/protonish";
```

Then:
```bash
sed -i '' 's#Application Support/notproton#Application Support/protonish#g' \
  dylib/feats/compat.c dylib/feats/compat_run.sh Makefile \
  bridge/fetch-valve.sh bridge/verify.sh lsteamclient/build.sh \
  ntdll-patch/build-ntdll.sh steam-shim/build.sh
```

- [ ] **Step 4: Run tests and the section check**

Run: `sh dylib/tests/brandcheck.sh support && make -s envcheck && cd app && swift test --no-parallel --filter 'DetectionTests|PrefixToolsTests|RunnerSwitchTests|UninstallTests'; cd ..`
Expected: `==> brandcheck: clean (support)`, envcheck passes, filtered Swift tests PASS.

- [ ] **Step 5: FULL CHECK**

Run: FULL CHECK. Expected: all exit 0.

- [ ] **Step 6: Commit**

```bash
git add -u
```
Commit via `/commit`, subject: `Move support directory to Application Support/protonish`.

---

### Task 3: Dylib and Steam-bundle artifact names

**Files:**
- Modify: `app/Sources/NotProtonApp/Support/SupportPaths.swift:8`
- Modify: `app/Sources/NotProtonApp/Model/DeploymentContent.swift:153`, `Model/SteamInstaller.swift:271`
- Modify: `app/Sources/NotProtonApp/Model/SteamBundle.swift:21`
- Modify: `dylib/util/log.c:77`
- Modify: `Makefile:12,58,59,60,323,372,496,497,524,527,557`
- Test: `app/Tests/NotProtonAppTests/DetectionTests.swift:231`, `DeploymentContentTests.swift:120,130,154,171`, `InstallPayloadTests.swift:33,73,103`, `SteamRepairTests.swift:120,185,260,269`, `SystemStatusTests.swift:154`, `SteamInstallerTests.swift:321`, `dylib/tests/spawn-env.c:86`

**Interfaces:**
- Produces: `SupportPaths.dylibName == "protonish.dylib"`; `SteamBundle.plistBackupName == "Info.plist.before-protonish"`; built artifact `out/protonish.dylib`; dylib log file `protonish.log`.

- [ ] **Step 1: Update tests (failing test)**

```bash
sed -i '' -e 's#notproton\.dylib#protonish.dylib#g' -e 's#Info\.plist\.before-notproton#Info.plist.before-protonish#g' \
  app/Tests/NotProtonAppTests/DetectionTests.swift \
  app/Tests/NotProtonAppTests/DeploymentContentTests.swift \
  app/Tests/NotProtonAppTests/InstallPayloadTests.swift \
  app/Tests/NotProtonAppTests/SteamRepairTests.swift \
  app/Tests/NotProtonAppTests/SystemStatusTests.swift \
  app/Tests/NotProtonAppTests/SteamInstallerTests.swift \
  dylib/tests/spawn-env.c
```

- [ ] **Step 2: Run to verify failure**

Run: `cd app && swift test --no-parallel --filter 'DetectionTests|DeploymentContentTests|InstallPayloadTests|SteamRepairTests|SystemStatusTests|SteamInstallerTests'; cd ..`
Expected: FAIL on dylib-name and backup-name assertions.

- [ ] **Step 3: Rename in sources**

`SupportPaths.swift:8`:
```swift
    static let dylibName = "protonish.dylib"
```
`DeploymentContent.swift:153` and `SteamInstaller.swift:271`: replace the literal `"notproton.dylib"` with `SupportPaths.dylibName` (removes the duplicates).
`SteamBundle.swift:21`:
```swift
    static let plistBackupName = "Info.plist.before-protonish"
```
Then:
```bash
sed -i '' -e 's#notproton\.arm64\.dylib#protonish.arm64.dylib#g' -e 's#notproton\.x86_64\.dylib#protonish.x86_64.dylib#g' \
  -e 's#notproton\.dylib#protonish.dylib#g' Makefile
sed -i '' 's#notproton\.log#protonish.log#g' dylib/util/log.c
make clean
```

- [ ] **Step 4: Verify**

Run: `sh dylib/tests/brandcheck.sh support dylib && make all && ls out/protonish.dylib && make -s spawn-env && cd app && swift test --no-parallel --filter 'DetectionTests|DeploymentContentTests|InstallPayloadTests|SteamRepairTests|SystemStatusTests|SteamInstallerTests'; cd ..`
Expected: brandcheck clean for both sections; `out/protonish.dylib` exists; spawn-env passes; tests PASS.

- [ ] **Step 5: FULL CHECK**, then **Step 6: Commit** (`git add -u`), `/commit` subject: `Rename dylib and Steam backup artifacts to protonish`.

---

### Task 4: Compat tool name prefix → `protonish`

**Files:**
- Modify: `app/Sources/NotProtonApp/Model/SupportedRunner.swift:94-99,149,180,199,200,217,236,237`
- Modify: `app/Sources/NotProtonApp/Support/SupportPaths.swift:111,115`
- Modify: `dylib/feats/compat.c:19,486`, `dylib/feats/compatsvc.h:24`, `dylib/feats/compat_run.sh:2`
- Test: `app/Tests/NotProtonAppTests/DetectionTests.swift:127-181`, `RunnerSwitchTests.swift:111-334`, `PrefixToolsTests.swift:1473,1479`, `UninstallTests.swift:37,39,57,63`, `dylib/tests/compatcheck.c`, `dylib/tests/buildcheck.sh:28`, `dylib/tests/gatecheck.c`, `dylib/tests/panel-behavior/{fex,harness,migration}.js`

**Interfaces:**
- Produces: tool names `protonish`, `protonish-fex`, `protonish-fex-rosetta`, `protonish-preview`, `protonish-fex-41069`, `protonish-fex-rosetta-41069`, `protonish-preview-41069`, `protonish-26.3`; `SupportedRunners.legacyToolName == "protonish"`; C `TOOL_DIR_NAME "protonish"`; `NP_COMPAT_TOOL_NONE "protonish.none"`; run-script mark `# protonish CrossOver compatibility tool shim`. `SupportPaths.Steam.notprotonTools()` keeps its Swift name (internal) but filters on `"protonish"`.

- [ ] **Step 1: Update tests (failing test)**

```bash
FILES="app/Tests/NotProtonAppTests/DetectionTests.swift app/Tests/NotProtonAppTests/RunnerSwitchTests.swift app/Tests/NotProtonAppTests/PrefixToolsTests.swift app/Tests/NotProtonAppTests/UninstallTests.swift dylib/tests/compatcheck.c dylib/tests/buildcheck.sh dylib/tests/gatecheck.c dylib/tests/panel-behavior/fex.js dylib/tests/panel-behavior/harness.js dylib/tests/panel-behavior/migration.js"
sed -i '' -E -e 's#notproton(-fex|-preview|-26\.3)#protonish\1#g' \
  -e 's#notproton\.none#protonish.none#g' \
  -e 's## notproton CrossOver compatibility tool shim## protonish CrossOver compatibility tool shim#g' $FILES
git grep -n -E '"notproton"|notproton/|/notproton\b' -- $FILES
```
For each remaining hit: if it is the bare legacy tool name or a `compatibilitytools.d/notproton` tool directory, change `notproton` → `protonish`. If it is a prefix marker (`notproton-build`, `notproton-msync`, `notproton-template`, `notproton-orig`, …), leave it unchanged (Global Constraints: KEEP).

- [ ] **Step 2: Run to verify failure**

Run: `make -s compatcheck buildcheck panel-behavior; cd app && swift test --no-parallel --filter 'DetectionTests|RunnerSwitchTests|PrefixToolsTests|UninstallTests'; cd ..`
Expected: FAIL on tool-name assertions.

- [ ] **Step 3: Rename in sources**

`SupportedRunner.swift`:
```bash
sed -i '' -E 's#notproton(-fex|-preview|-26\.3)#protonish\1#g' app/Sources/NotProtonApp/Model/SupportedRunner.swift
sed -i '' 's#legacyToolName = "notproton"#legacyToolName = "protonish"#' app/Sources/NotProtonApp/Model/SupportedRunner.swift
```
`SupportPaths.swift:115`:
```swift
        entries.filter { $0.lastPathComponent.hasPrefix("protonish") }
```
`dylib/feats/compat.c:19`:
```c
#define TOOL_DIR_NAME "protonish"
```
`dylib/feats/compat.c:486`:
```c
#define RUN_SCRIPT_MARK "\n# protonish CrossOver compatibility tool shim\n"
```
`dylib/feats/compatsvc.h:24`:
```c
#define NP_COMPAT_TOOL_NONE "protonish.none"
```
`dylib/feats/compat_run.sh:2`:
```sh
# protonish CrossOver compatibility tool shim
```

- [ ] **Step 4: Verify**

Run: `sh dylib/tests/brandcheck.sh support dylib tools && make all && make -s compatcheck compatsvc-check buildcheck panel-behavior webpatch-fixtures && cd app && swift test --no-parallel --filter 'DetectionTests|RunnerSwitchTests|PrefixToolsTests|UninstallTests'; cd ..`
Expected: brandcheck clean; all checks PASS (compatcheck asserts the mark matches the embedded script).

- [ ] **Step 5: FULL CHECK**, then **Step 6: Commit** (`git add -u`), `/commit` subject: `Rename compat tool prefix to protonish`.

---

### Task 5: Bundle identity and Sparkle update feed

**Files:**
- Modify: `app/Info.plist:19,39,41`
- Modify: `Makefile:495`
- Modify: `dylib/feats/compat_run.sh:1340`
- Modify: `dylib/hooks/hook_shortcut_bundle.c:79`, `overlay-shim/overlay_shim.m:805`
- Modify (scratch xattr names in tests only): `app/Tests/NotProtonAppTests/BridgePayloadTests.swift:187,200`, `SteamInstallerTests.swift:229,239`
- Test: `dylib/tests/launchercheck.sh` (existing), brandcheck `identity updates`

**Interfaces:**
- Produces: `CFBundleIdentifier` `com.magnuspladsen.protonish`; launcher IDs `com.protonish.launcher.<appid>`; Sparkle public key in `Info.plist`; private key at `~/.config/protonish/sparkle_ed25519_private_key` (outside the repo, mode 600) for M4.

- [ ] **Step 1: Run the section to see it fail**

Run: `sh dylib/tests/brandcheck.sh identity updates; echo "exit=$?"`
Expected: hits for `com.notproton.` and the upstream feed/key; `exit=1`.

- [ ] **Step 2: Generate the Sparkle key pair (local only)**

```bash
swift package resolve --package-path app
GEN=app/.build/artifacts/sparkle/Sparkle/bin/generate_keys
"$GEN" --account protonish            # creates the key in the login Keychain, prints the public key
mkdir -p ~/.config/protonish && chmod 700 ~/.config/protonish
"$GEN" --account protonish -x ~/.config/protonish/sparkle_ed25519_private_key
chmod 600 ~/.config/protonish/sparkle_ed25519_private_key
"$GEN" --account protonish -p          # prints the public key again; copy it
```
Expected: a base64 public key (44 chars ending in `=`). Never `git add` anything under `~/.config/protonish`.

- [ ] **Step 3: Update `app/Info.plist`**

```xml
	<key>CFBundleIdentifier</key>
	<string>com.magnuspladsen.protonish</string>
```
```xml
	<key>SUFeedURL</key>
	<string>https://github.com/MagnusPladsen/Proton-ish/releases/latest/download/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>PASTE_THE_PUBLIC_KEY_FROM_STEP_2</string>
```
Replace `PASTE_THE_PUBLIC_KEY_FROM_STEP_2` with the actual printed key before saving — the literal placeholder must not be committed (Step 5 checks).

- [ ] **Step 4: Remaining identifiers**

```bash
sed -i '' 's#defaults read com\.notproton\.NotProton#defaults read com.magnuspladsen.protonish#' Makefile
sed -i '' 's#com\.notproton\.launcher\.#com.protonish.launcher.#' dylib/feats/compat_run.sh
sed -i '' 's#"com\.notproton\.shortcut-bundle"#"com.protonish.shortcut-bundle"#' dylib/hooks/hook_shortcut_bundle.c
sed -i '' 's#com\.notproton\.overlay\.announce#com.protonish.overlay.announce#' overlay-shim/overlay_shim.m
sed -i '' -e 's#com\.notproton\.test#com.protonish.test#g' -e 's#com\.notproton\.keep#com.protonish.keep#g' \
  app/Tests/NotProtonAppTests/BridgePayloadTests.swift app/Tests/NotProtonAppTests/SteamInstallerTests.swift
```

- [ ] **Step 5: Verify**

Run:
```bash
sh dylib/tests/brandcheck.sh identity updates \
 && ! grep -q PASTE_THE_PUBLIC_KEY app/Info.plist \
 && /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' app/Info.plist | grep -E '^[A-Za-z0-9+/]{43}=$' \
 && make -s launchercheck overlay-shim-tests
```
Expected: brandcheck clean; key matches the base64 shape; launchercheck and overlay-shim-tests PASS.

- [ ] **Step 6: FULL CHECK**, then **Step 7: Commit** (`git add -u`), `/commit` subject: `Give Proton-ish its own bundle ID and Sparkle feed`.

---

### Task 6: User-visible strings → "Proton-ish"

**Files:**
- Create: `scripts/rebrand_strings.py`
- Modify: every Swift source listed under bucket G (`BridgePayload.swift:48`, `DeploymentContent.swift:141`, `InstallPayload.swift:6,25`, `PrefixTools.swift:36,37,286`, `RunnerPatcher.swift:129`, `SteamInstaller.swift:45,95,111,115,190,263,289,292`, `SteamRepair.swift:64`, `Uninstall.swift:34,40,45,48`, `ValveFetcher.swift:61`, `PinnedDownload.swift:80,83,85`, `WriteRefused.swift:37,39`, `SystemStatus.swift:311,347,351,457,469,481,566,567`, `PrefixesView.swift:23`, `StatusView.swift` (all `NotProton` literals), `RemoveEverythingCommand.swift:22,24`, `AppLog.swift:18`, `App.swift:17`)
- Modify: `app/Sources/NotProtonApp/Resources/Localization/Localizable.xcstrings`
- Modify: `app/Info.plist:23` (`CFBundleName`)
- Modify: `dylib/feats/compat_run.sh` (alerts and log lines; `notproton-run.log` / `notproton-wine.log`)
- Modify: `dylib/feats/compat.c:365`, `dylib/util/log.h:20`, `dylib/feats/webpatch.c:342,346,347,349`
- Test: `app/Tests/NotProtonAppTests/SteamInstallerTests.swift:554`, `PrefixToolsTests.swift` (log names), `dylib/tests/settingscheck.sh` (log names if asserted), `make -s l10ncheck`

**Interfaces:**
- Produces: all user-facing text says `Proton-ish`; prefix log files `protonish-run.log`, `protonish-wine.log` (`PrefixTools` constants); dylib log prefix `[protonish]`.

- [ ] **Step 1: Write the rewrite tool**

Create `scripts/rebrand_strings.py`:

```python
#!/usr/bin/env python3
"""One-off dev tool: rename the user-visible product name NotProton -> Proton-ish.

Rewrites string literals in Swift sources and the keys + values of Localizable.xcstrings
together, so catalog keys keep matching source strings. Leaves NotProtonApp, NotProtonNot,
NotProtonLaunchMigrated_ and comments alone. Writes the catalog in the exact format
dylib/tests/l10ncheck.py expects.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "app/Sources/NotProtonApp"
CATALOG = SOURCES / "Resources/Localization/Localizable.xcstrings"
WORD = re.compile(r"NotProton(?![A-Za-z_])")
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def rename(text: str) -> str:
    return WORD.sub("Proton-ish", text)


def rewrite_swift(path: pathlib.Path) -> bool:
    original = path.read_text()
    out = []
    for line in original.splitlines(keepends=True):
        if line.lstrip().startswith("//"):
            out.append(line)
            continue
        out.append(STRING_LITERAL.sub(lambda m: rename(m.group(0)), line))
    updated = "".join(out)
    if updated != original:
        path.write_text(updated)
        return True
    return False


def rewrite_catalog() -> None:
    data = json.loads(CATALOG.read_text())
    strings = {}
    for key, entry in data["strings"].items():
        new_key = rename(key)
        if new_key in strings and new_key != key:
            sys.exit(f"collision after rename: {new_key!r}")
        strings[new_key] = json.loads(rename(json.dumps(entry, ensure_ascii=False)))
    data["strings"] = strings
    formatted = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
    formatted = re.sub(r"^( *)(.*) : \{\}", lambda m: f"{m[1]}{m[2]} : {{\n\n{m[1]}}}", formatted, flags=re.M)
    CATALOG.write_text(formatted)


def main() -> None:
    changed = [p for p in sorted(SOURCES.rglob("*.swift")) if rewrite_swift(p)]
    rewrite_catalog()
    for p in changed:
        print(f"rewrote {p.relative_to(ROOT)}")
    print(f"rewrote {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Update tests (failing test)**

```bash
sed -i '' 's#"newer NotProton"#"newer Proton-ish"#' app/Tests/NotProtonAppTests/SteamInstallerTests.swift
sed -i '' -E 's#notproton-(run|wine)\.log#protonish-\1.log#g' \
  app/Tests/NotProtonAppTests/PrefixToolsTests.swift dylib/tests/settingscheck.sh dylib/tests/seedcheck.sh
```
Run: `sh dylib/tests/brandcheck.sh strings; echo "exit=$?"` → Expected: hits, `exit=1`.

- [ ] **Step 3: Apply the renames**

```bash
python3 scripts/rebrand_strings.py
sed -i '' -E 's#notproton-(run|wine)\.log#protonish-\1.log#g' \
  app/Sources/NotProtonApp/Model/PrefixTools.swift dylib/feats/compat_run.sh
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Proton-ish' app/Info.plist   # icon names are Task 7
sed -i '' 's#"\[notproton\]"#"[protonish]"#' dylib/util/log.h
sed -i '' -E 's#NotProton([^A-Za-z]|$)#Proton-ish\1#g' dylib/feats/compat.c dylib/feats/webpatch.c
```
Then edit `dylib/feats/compat_run.sh` by hand: in every user-facing alert/log string (bucket G lines 204, 290, 291, 332, 334, 627, 628, 929, 1061, 1080, 1088, 1090, 1099, 1227, 1240), change `NotProton` → `Proton-ish`. Do NOT touch `NOTPROTON_*` variables or `notproton-*` marker filenames.

`CFBundleIconFile`/`CFBundleIconName` must still read `NotProton` after this step; Task 7 renames them together with the icon build. `app/Info.plist` is checked by the `release` brandcheck section (Task 7), not `strings`. Verify here with `/usr/libexec/PlistBuddy -c 'Print :CFBundleName' -c 'Print :CFBundleIconName' app/Info.plist` → `Proton-ish` then `NotProton`.

- [ ] **Step 4: Verify**

```bash
sh dylib/tests/brandcheck.sh strings
cd app && swift build && cd ..
make -s l10ncheck runcheck seedcheck settingscheck webpatch-fixtures panel-behavior
cd app && swift test --no-parallel --filter 'SteamInstallerTests|PrefixToolsTests'; cd ..
```
Expected: brandcheck clean; l10ncheck reports all strings translated for zh-Hans with no format problem; other checks and tests PASS. If l10ncheck lists a key "not in the catalog", the Swift literal and catalog key diverged — fix the literal so it matches the renamed catalog key exactly.

- [ ] **Step 5: FULL CHECK**, then **Step 6: Commit** (`git add -u scripts/rebrand_strings.py`), `/commit` subject: `Rename user-visible product name to Proton-ish`.

---

### Task 7: Build artifacts, release workflow and placeholder icon

**Files:**
- Modify: `Makefile:508,577,578,579,585,601,624,626,628`
- Modify: `app/Info.plist:15,17` (`CFBundleIconFile`, `CFBundleIconName`)
- Modify: `.github/workflows/app.yml:138,143`
- Modify: `.github/workflows/release.yml:31,38,39,40,42,53,66,67,72`
- Modify: `helpers/icon.swift:256-257`
- Test: brandcheck `release`, `make app`, `make -s mincheck`

**Interfaces:**
- Produces: `out/Proton-ish.app`, `out/artifact/Proton-ish.zip`, CI artifact `Proton-ish`, release notes `release/Proton-ish.txt` (basename must match the zip for Sparkle's `generate_appcast`), icon name `Proton-ish`.

- [ ] **Step 1: Run the section to see it fail**

Run: `sh dylib/tests/brandcheck.sh release; echo "exit=$?"` → Expected: hits, `exit=1`.

- [ ] **Step 2: Rename artifacts**

```bash
sed -i '' -E -e 's#NotProton\.(app|zip|txt|icon|icns)#Proton-ish.\1#g' -e 's#--app-icon NotProton#--app-icon Proton-ish#g' \
  Makefile .github/workflows/app.yml .github/workflows/release.yml
sed -i '' -E 's#^(          name: )NotProton$#\1Proton-ish#' .github/workflows/app.yml .github/workflows/release.yml
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile Proton-ish' -c 'Set :CFBundleIconName Proton-ish' app/Info.plist
```
Leave `NotProtonApp_NotProtonApp.bundle` and the `NotProtonApp` executable lines in the Makefile unchanged (module name, Global Constraints: KEEP).

- [ ] **Step 3: Release identity**

In `.github/workflows/release.yml`, replace lines 66-67:
```yaml
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
```

- [ ] **Step 4: Placeholder icon colours**

In `helpers/icon.swift`, replace the `linear-gradient` pair (lines ~256-257) with a teal gradient so the icon is visibly distinct from upstream:
```swift
            "srgb:0.10196,0.52941,0.52941,1.00000",
            "srgb:0.04706,0.27059,0.30196,1.00000",
```

- [ ] **Step 5: Verify**

```bash
sh dylib/tests/brandcheck.sh release
make app && test -d out/Proton-ish.app && make -s mincheck
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' out/Proton-ish.app/Contents/Info.plist
ls out/Proton-ish.app/Contents/Resources/ | grep -E 'Proton-ish\.icns|Assets\.car'
```
Expected: brandcheck clean; `make app` builds `out/Proton-ish.app` (requires `make bridge` payload; if `make app` fails only because the bridge payload is missing, run `make bridge fonts` first — it builds the Wine tree and takes a long time); mincheck passes; icon name `Proton-ish`; both icon files present.

- [ ] **Step 6: FULL CHECK**, then **Step 7: Commit** (`git add -u`), `/commit` subject: `Rename build artifacts and release identity for Proton-ish`.

---

### Task 8: About panel credit

**Files:**
- Create: `app/Sources/NotProtonApp/Support/AboutCredits.swift`
- Create: `app/Tests/NotProtonAppTests/AboutCreditsTests.swift`
- Modify: `app/Sources/NotProtonApp/App.swift:35-37`
- Modify: `app/Sources/NotProtonApp/Resources/Localization/Localizable.xcstrings` (new keys + zh-Hans)

**Interfaces:**
- Produces: `enum AboutCredits { static var text: String; static func show() }`.

- [ ] **Step 1: Write the failing test**

Create `app/Tests/NotProtonAppTests/AboutCreditsTests.swift`:
```swift
import Testing
@testable import NotProtonApp

struct AboutCreditsTests {
    @Test func creditsNameUpstreamAndDisclaimAffiliation() {
        let text = AboutCredits.text
        #expect(text.contains("fork of NotProton"))
        #expect(text.contains("https://github.com/NotProtonNot/NotProton"))
        #expect(text.contains("not affiliated"))
        #expect(text.contains("Valve"))
        #expect(text.contains("CodeWeavers"))
        #expect(text.contains("Highball"))
        #expect(text.contains("GPLv3"))
    }
}
```
(If the existing test files use XCTest rather than swift-testing, mirror their style: check `head -5 app/Tests/NotProtonAppTests/SupportPathsTests.swift` or any test file and use the same framework.)

- [ ] **Step 2: Run to verify failure**

Run: `cd app && swift test --no-parallel --filter AboutCreditsTests; cd ..`
Expected: FAIL — `cannot find 'AboutCredits' in scope`.

- [ ] **Step 3: Implement**

Create `app/Sources/NotProtonApp/Support/AboutCredits.swift`:
```swift
// Fork credit shown in the About panel

import AppKit

enum AboutCredits {

    static var text: String {
        String(localized: """
        Proton-ish is a fork of NotProton by NotProtonNot (https://github.com/NotProtonNot/NotProton), \
        released under GPLv3. It is not affiliated with or endorsed by NotProton, Valve, CodeWeavers or Highball.
        """)
    }

    @MainActor
    static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: text)
        ])
        NSApplication.shared.activate()
    }
}
```
In `App.swift`, replace the `CommandGroup(after: .appInfo)` block with:
```swift
        CommandGroup(replacing: .appInfo) {
            Button("About Proton-ish") { AboutCredits.show() }
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.check() }
        }
```
Add both new strings to `Localizable.xcstrings` with zh-Hans translations by running this once:
```bash
python3 - <<'EOF'
import json, re, pathlib
p = pathlib.Path("app/Sources/NotProtonApp/Resources/Localization/Localizable.xcstrings")
d = json.loads(p.read_text())
add = {
  "About Proton-ish": "关于 Proton-ish",
  "Proton-ish is a fork of NotProton by NotProtonNot (https://github.com/NotProtonNot/NotProton), released under GPLv3. It is not affiliated with or endorsed by NotProton, Valve, CodeWeavers or Highball.":
  "Proton-ish 是 NotProtonNot 开发的 NotProton（https://github.com/NotProtonNot/NotProton）的分支，以 GPLv3 发布。它与 NotProton、Valve、CodeWeavers 或 Highball 无关，也未获得其认可。",
}
for k, v in add.items():
    d["strings"][k] = {"localizations": {"zh-Hans": {"stringUnit": {"state": "translated", "value": v}}}}
f = json.dumps(d, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
f = re.sub(r"^( *)(.*) : \{\}", lambda m: f"{m[1]}{m[2]} : {{\n\n{m[1]}}}", f, flags=re.M)
p.write_text(f)
EOF
```

- [ ] **Step 4: Verify**

Run: `cd app && swift test --no-parallel --filter AboutCreditsTests && swift build; cd .. && make -s l10ncheck`
Expected: test PASS; l10ncheck clean (if it reports the key differs, copy the exact key it prints into the catalog entry).

- [ ] **Step 5: FULL CHECK**, then **Step 6: Commit** (`git add app/Sources/NotProtonApp/Support/AboutCredits.swift app/Tests/NotProtonAppTests/AboutCreditsTests.swift -u`), `/commit` subject: `Add fork credit and no-affiliation notice to About panel`.

---

### Task 9: Compliance documents and issue templates

**Files:**
- Modify: `README.md` (full rewrite of the header; upstream body kept below)
- Modify: `NOTICE` (append)
- Modify: `CONTRIBUTING.md`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/config.yml`

- [ ] **Step 1: Run the section to see it fail**

Run: `sh dylib/tests/brandcheck.sh docs; echo "exit=$?"` → Expected: failures for all docs checks, `exit=1`.

- [ ] **Step 2: README header**

Replace lines 1-3 of `README.md` (the `# NotProton` title and the one-line description) with:
```markdown
# Proton-ish

Proton-ish brings the Steam Play experience from Linux Steam to the macOS Steam client,
using CrossOver or (coming soon) the free Highball Wine runtime.

> **Proton-ish is a fork of [NotProton](https://github.com/NotProtonNot/NotProton) by NotProtonNot.**
> All credit for the Steam integration, the lsteamclient port and steam-shim goes to upstream.
> Proton-ish is not affiliated with or endorsed by NotProton, Valve, CodeWeavers or Highball.
> Please report Proton-ish problems at https://github.com/MagnusPladsen/Proton-ish/issues, not upstream.

## Changes from upstream

- 2026-10-14: Rebranded to Proton-ish (bundle ID `com.magnuspladsen.protonish`, support
  directory `~/Library/Application Support/protonish/`, tool names `protonish-*`, own update feed).

The upstream documentation follows. Where it says "NotProton", read "Proton-ish" unless it refers
to the upstream project itself.

---
```
Replace the brew line (`README.md:22`, `brew install --cask notprotonnot/notproton/notproton`) with:
```markdown
**Homebrew:** not available yet for Proton-ish.
```
Replace `~/Library/Application Support/notproton/` at `README.md:45` with `~/Library/Application Support/protonish/`.

Add this section directly after the "Changes from upstream" section (before the `---` that introduces the upstream documentation):
```markdown
## Building from source

- Xcode 27 (the same toolchain upstream CI uses); older Xcode versions fail to type-check the app.
- `brew install shellcheck node` for the lint and panel checks.
- `make dobby && make all && make app-tests` builds the dylib and runs the Swift tests;
  `make bridge fonts app` builds the full `out/Proton-ish.app` (the bridge step compiles a Wine tree and takes a while).
- `make brandcheck` must stay clean: it fails if an upstream NotProton identifier slips back in.
```

Every later milestone (M1–M4) adds its own line to "Changes from upstream" and updates any README section it affects.

- [ ] **Step 3: NOTICE**

Append to `NOTICE`:
```text

Proton-ish modifications
========================

Modified by Proton-ish contributors, 2026. Proton-ish is a fork of NotProton
(https://github.com/NotProtonNot/NotProton). The modifications are licensed under
GPLv3, like the bulk of the project. Each modification is recorded in the git history
of https://github.com/MagnusPladsen/Proton-ish and summarised under "Changes from
upstream" in README.md. All licensing terms above continue to apply.
```

- [ ] **Step 4: CONTRIBUTING.md**

Replace lines 1-6 (title and intro, which state upstream's CrossOver-only policy) with:
```markdown
# Contributing to Proton-ish

Proton-ish is a fork of NotProton that adds free Wine runtimes (Highball first) next to
CrossOver. Contributions are welcome here; please do not send Proton-ish changes or
non-CrossOver issues to the upstream NotProton project, which does not accept them.

Keep upstream merges cheap: avoid renaming internal identifiers (Swift module names,
`np_` C symbols, `NOTPROTON_*` environment variables, prefix marker files).
```
Keep the remaining upstream sections, but delete the policy line stating that non-CrossOver runtimes are not a goal (policy #2) and renumber the remaining policies.

- [ ] **Step 5: Issue templates**

Create `.github/ISSUE_TEMPLATE/config.yml`:
```yaml
blank_issues_enabled: false
contact_links:
  - name: Upstream NotProton (CrossOver-only issues reproducible without Proton-ish)
    url: https://github.com/NotProtonNot/NotProton/issues
    about: Only for problems that also happen with upstream NotProton. Never report Proton-ish or Highball issues there.
```
Create `.github/ISSUE_TEMPLATE/bug_report.yml`:
```yaml
name: Bug report
description: Something in Proton-ish does not work
labels: [bug]
body:
  - type: input
    id: version
    attributes:
      label: Proton-ish version
    validations:
      required: true
  - type: dropdown
    id: runtime
    attributes:
      label: Wine runtime
      options: [CrossOver, Highball, Other]
    validations:
      required: true
  - type: input
    id: runtime_version
    attributes:
      label: Runtime version / engine id
      placeholder: "CrossOver 26.3, or Highball x64-crossover26.3-r25"
    validations:
      required: true
  - type: input
    id: macos
    attributes:
      label: macOS version and Mac model
    validations:
      required: true
  - type: textarea
    id: what
    attributes:
      label: What happened and what you expected
    validations:
      required: true
  - type: textarea
    id: logs
    attributes:
      label: protonish-run.log (from the game's prefix)
      render: text
```

- [ ] **Step 6: Verify**

Run: `sh dylib/tests/brandcheck.sh docs && make brandcheck`
Expected: docs clean, then the full brandcheck reports `==> brandcheck: clean (support dylib tools identity updates strings release docs)`.

- [ ] **Step 7: Commit** (`git add -u .github/ISSUE_TEMPLATE`), `/commit` subject: `Add fork credit, NOTICE modifications and issue templates`.

---

### Task 10: Wire brandcheck into CI, amend the spec, final verification

**Files:**
- Modify: `.github/workflows/lint.yml` (add a step after `make runcheck`, line ~46)
- Modify: `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` §3 and §6 step 4

- [ ] **Step 1: CI step**

In `.github/workflows/lint.yml`, after the step that runs `make runcheck`, add:
```yaml
      - name: Brand check
        run: make brandcheck
```

- [ ] **Step 2: Amend the spec**

In spec §3, replace the bullet beginning "Prefix record files:" with:
```markdown
- Prefix and runner marker files keep their upstream names (`notproton-build`,
  `notproton-msync`, `*.notproton-orig`, `notproton-template`, lock files). They are
  invisible to users, and keeping them means existing prefixes need no migration.
  `NOTPROTON_*` environment variables are also kept, because users' saved Steam launch
  options contain them.
```
In spec §6, replace step 4 with:
```markdown
4. Prefixes stay in `steamapps/compatdata/<appid>/pfx` untouched; marker files keep
   their upstream names (section 3), so no per-prefix changes are needed.
```

- [ ] **Step 3: FULL CHECK + brandcheck**

Run: FULL CHECK, then `make brandcheck`.
Expected: everything exits 0; brandcheck clean across all sections.

- [ ] **Step 4: Manual smoke test on the built app**

```bash
make app
open out/Proton-ish.app
```
Expected: window title "Proton-ish"; About menu shows "About Proton-ish" with the fork credit; the app icon is teal; Status screen strings say Proton-ish. Close the app. Do not install into Steam during M0 smoke testing unless the user asks.

- [ ] **Step 5: Commit** (`git add -u`), `/commit` subject: `Run brandcheck in CI and record kept upstream identifiers`.

- [ ] **Step 6: Ask the user** whether to push the branch and enable GitHub Actions on the fork (both outward-facing).
