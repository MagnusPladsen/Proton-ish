# M1: Wine Runtime Abstraction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put CrossOver behind a `WineRuntime` abstraction and make runner paths, the tools list and the run script runtime-aware, with no behaviour change for CrossOver users — so M2 can add Highball as a second runtime.

**Architecture:** A `RuntimeKind` enum tags every `RunnerBuild`; a `WineRuntime` protocol (one implementation, `CrossOverRuntime`) owns the loader path, Wine layout, base environment and access check that are hard-coded to CrossOver today. Runner clones move from `runners/crossover-<build>/CrossOver/` to `runners/<runtime>-<build>/root/`. The tools TSV gains a `runtime` column (`name\tbuild\tflavor\truntime\tdisplay`), the dylib accepts both 4- and 5-column lines and writes a per-tool `runtime` file, and `compat_run.sh` reads it to derive the runner root.

**Tech Stack:** Swift 6.4 / SwiftPM / swift-testing (app), C (dylib, `compatcheck.c`), POSIX sh (`compat_run.sh`, shell checks), GNU Make.

**Spec:** `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` (sections 2, 3, 9/M1). Task 6 amends spec §2.4 and §3 for the decisions recorded in Global Constraints.

## Global Constraints

- **No behaviour change for CrossOver.** Every existing test keeps passing; only tests that pin the old on-disk layout or TSV width change, and only as listed in each task.
- Runner layout: `runners/<runtime>-<build>/root/` where `<runtime>` is `RuntimeKind.rawValue` (`crossover`). Staging: `.<runtime>-<build>.new`, trash: `.<runtime>-<build>.removing`.
- Prefix template ids: `<runtime>-<build>-<unixdir>` (unchanged for CrossOver: `crossover-<build>-x86_64-unix`).
- Tools TSV: `name\tbuild\tflavor\truntime\tdisplay`. The dylib also accepts the old 4-column form and treats it as `runtime = crossover`. Display is always the **last** field.
- `runtime` values accepted by the dylib: `crossover` only in M1 (M2 adds `highball`).
- CrossOver tool names stay exactly as they are (`protonish`, `protonish-fex`, `protonish-26.3`, …). Renaming them would break every user's per-game tool mapping. Spec §3's `protonish-crossover-<build>` naming applies to new runtimes only (amended in Task 6).
- The run script keeps `CX_ROOT` as a top-level assignment (`envcheck.sh:45` evals the `^CX_ROOT=` … `^wine_unix=` block, and CrossOver itself reads `CX_ROOT`). No `setup_crossover_env` function in M1; M2 introduces the runtime `case` when a second runtime exists.
- No on-disk migration of `runners/crossover-*/CrossOver`: Proton-ish has never been released, so no user has a Proton-ish runner. NotProton's runners are migrated in M3.
- The legacy `runners/current` symlink parser (`RunnerStore.legacyHolder`, `RunnerSwitchTests` symlink fixtures) is untouched — it reads the 1.0.x layout.
- Keep internal names (`NotProtonApp`, `np_` symbols, `NOTPROTON_*`, marker files). `make brandcheck` stays clean.
- Commits via the `/commit` skill format; README gets a dated "Changes from upstream" line (user rule).

## Review Focus

1. **Half-shipped TSV change** — today's parser (`compat.c:334-356`) stops at 4 fields, so a 5-column line written by a new app would be misread (runtime taken as the display name). The writer and parser change in the same task (Task 4), with a compatcheck case for both widths.
2. **`remove_tool` leaving directories behind** — if `runtime` is not added to its file list (`compat.c:510-512`), `rmdir` fails and stale `protonish-*` tool dirs pile up in Steam. Pinned by a compatcheck case in Task 4.
3. **Run-script and app disagreeing on the root path** — `compat_run.sh` and `PrefixTools.layout` are kept in sync by hand. Pinned by `PrefixToolsTests.matchesRunScript`, `buildcheck.sh` and `envcheck.sh` in Task 5.
4. **`last_wine_build` reading the wrong TSV column** — it reads `$4` as the display today; with the new column it must read the last field. Pinned by `buildcheck.sh` assertions on the display text in Task 5.
5. **Template cleanup deleting live templates** — the regex at `RunnerInstaller.swift:154` decides which template directories are deletable; generalising it must still spare non-matching names (`TemplateCleanupTests:54`). Pinned in Task 2.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `app/Sources/NotProtonApp/Model/WineRuntime.swift` (new) | `RuntimeKind`, `WineRuntime` protocol, `CrossOverRuntime` | 1, 3 |
| `app/Sources/NotProtonApp/Model/SupportedRunner.swift` | `RunnerBuild.runtime` | 1 |
| `app/Sources/NotProtonApp/Support/SupportPaths.swift` | runtime-aware `runnerRoot`/`clonedRoot`/`prefixTemplate` | 2 |
| `app/Sources/NotProtonApp/Model/RunnerStore.swift` | `clonedBuilds` parsing, TSV writer | 2, 4 |
| `app/Sources/NotProtonApp/Model/RunnerInstaller.swift` | `root` landing, leftovers, template regex | 2 |
| `app/Sources/NotProtonApp/Model/CrossOverSource.swift`, `PrefixTools.swift`, `RunnerSetup.swift` | route through `WineRuntime` | 3 |
| `dylib/feats/compat.c` | TSV parser, `runtime` file write/remove | 4 |
| `dylib/feats/compat_run.sh`, `lsteamclient/build.sh` | runtime-aware root, `last_wine_build`, template id | 5 |
| tests: `app/Tests/NotProtonAppTests/WineRuntimeTests.swift` (new) + listed existing tests, `dylib/tests/compatcheck.c`, `buildcheck.sh`, `envcheck.sh` | | 1–5 |

### FULL CHECK (run from repo root; prerequisites from M0 already installed: Xcode 27, cmake, Dobby in `vendor/dobby`, mingw-w64/bison/flex, `scratch/fontvenv`, built bridge)

```bash
export PATH="$PWD/scratch/fontvenv/bin:$PATH"
make all overlay-shim iconmaker appinfo && make app && make -s app-tests \
 && for t in l10ncheck sigcheck callscheck webpatch-fixtures peicon-fixtures panel-behavior spawn-env \
      compatcheck compatsvc-check shortcutcheck launch-shell envcheck buildcheck settingscheck routecheck \
      bridgecheck gamedrivecheck launchercheck seedcheck scriptcheck runcheck brandcheck mincheck; do
      make -s $t || exit 1; done
```

---

### Task 0: Branch and green baseline

- [ ] **Step 1:** `git checkout main && git pull --ff-only origin main && git checkout -b feat/m1-runtime-abstraction`
- [ ] **Step 2:** Run FULL CHECK. Expected: all pass, `Test run with 510 tests` (or more if the icon PR merged first). Stop and report if anything fails.

---

### Task 1: `RuntimeKind` and `RunnerBuild.runtime`

**Files:**
- Create: `app/Sources/NotProtonApp/Model/WineRuntime.swift`
- Modify: `app/Sources/NotProtonApp/Model/SupportedRunner.swift:14-50`
- Test: `app/Tests/NotProtonAppTests/WineRuntimeTests.swift` (new)

**Interfaces:**
- Produces: `enum RuntimeKind: String, Sendable, CaseIterable { case crossover }`; `RunnerBuild.runtime: RuntimeKind` (default `.crossover`), preserved by `matching(loaderSHA256:)`.

- [ ] **Step 1: Failing test** — create `app/Tests/NotProtonAppTests/WineRuntimeTests.swift`:

```swift
import Foundation
import Testing

@testable import NotProtonApp

@Suite("Wine runtime")
struct WineRuntimeTests {

    @Test("Every supported build is a CrossOver build")
    func supportedBuildsAreCrossOver() {
        #expect(!SupportedRunners.all.isEmpty)
        #expect(SupportedRunners.all.allSatisfy { $0.runtime == .crossover })
    }

    @Test("A rebuild keeps the runtime of the build it belongs to")
    func rebuildKeepsRuntime() throws {
        let build = try #require(SupportedRunners.all.first { !$0.rebuilds.isEmpty })
        let rebuild = try #require(build.rebuilds.first)
        #expect(build.matching(loaderSHA256: rebuild.loaderSHA256)?.runtime == build.runtime)
    }

    @Test("The runtime's raw value is the runner directory prefix")
    func rawValueIsDirectoryPrefix() {
        #expect(RuntimeKind.crossover.rawValue == "crossover")
    }
}
```

- [ ] **Step 2:** `cd app && swift test --no-parallel --filter WineRuntimeTests; cd ..` → Expected: compile FAIL, `cannot find 'RuntimeKind'` / `value of type 'RunnerBuild' has no member 'runtime'`.

- [ ] **Step 3: Implement.** Create `app/Sources/NotProtonApp/Model/WineRuntime.swift`:

```swift
// The Wine distribution a runner is copied from

import Foundation

enum RuntimeKind: String, Sendable, CaseIterable {
    case crossover
}
```

In `SupportedRunner.swift`, add the stored property after `rebuilds` and thread it through `matching`:

```swift
    var tools: [CompatTool] = []
    var rebuilds: [RunnerRebuild] = []
    var runtime: RuntimeKind = .crossover
```
```swift
        return RunnerBuild(
            bundleVersion: bundleVersion, releaseVersion: releaseVersion, flavor: flavor,
            loaderSHA256: rebuild.loaderSHA256, cleanNtdll: rebuild.cleanNtdll,
            patchedNtdll: rebuild.patchedNtdll, tools: tools, rebuilds: rebuilds, runtime: runtime
        )
```

- [ ] **Step 4:** `cd app && swift test --no-parallel --filter WineRuntimeTests; cd ..` → PASS (3 tests).
- [ ] **Step 5:** FULL CHECK → pass. Commit (`WineRuntime.swift`, `SupportedRunner.swift`, `WineRuntimeTests.swift`): `Tag runner builds with their Wine runtime`.

---

### Task 2: Generic runner layout `<runtime>-<build>/root`

**Files:**
- Modify: `app/Sources/NotProtonApp/Support/SupportPaths.swift:50-70`
- Modify: `app/Sources/NotProtonApp/Model/RunnerStore.swift:42-50`
- Modify: `app/Sources/NotProtonApp/Model/RunnerInstaller.swift:91-98,153-155,242-265`
- Modify: `app/Sources/NotProtonApp/Model/DeploymentContent.swift:181,222` (display labels)
- Test: `app/Tests/NotProtonAppTests/WineRuntimeTests.swift`, `RunnerStateTests.swift:19`, `RunnerInstallerTests.swift:33,212`, `RunnerSwitchTests.swift:533,549`

**Interfaces:**
- Consumes: `RuntimeKind`, `RunnerBuild.runtime`, `SupportedRunners.build(id:)`.
- Produces: `SupportPaths.runtime(forBuild:) -> RuntimeKind` (looks up `SupportedRunners.build(id:)?.runtime`, default `.crossover`); `runnerRoot(forBuild:runners:)` → `runners/<runtime>-<build>`; `clonedRoot(forBuild:runners:)` → `…/root`; `SupportPaths.clonedFolder = "root"`; `prefixTemplate` → `<runtime>-<build>-<unixdir>`; `RunnerStore.clonedBuilds` returns build ids for any `RuntimeKind` prefix.

- [ ] **Step 1: Failing tests.** Append to `WineRuntimeTests`:

```swift
    @Test("A runner clone lives under <runtime>-<build>/root")
    func clonedRootIsGeneric() {
        let runners = URL(filePath: "/R")
        #expect(SupportPaths.runnerRoot(forBuild: "26.3.0.39832", runners: runners).path(percentEncoded: false)
            == "/R/crossover-26.3.0.39832")
        #expect(SupportPaths.clonedRoot(forBuild: "26.3.0.39832", runners: runners).path(percentEncoded: false)
            == "/R/crossover-26.3.0.39832/root")
    }

    @Test("Cloned builds are found under every runtime prefix, and nothing else is")
    func clonedBuildsAcrossRuntimes() throws {
        let runners = FileManager.default.temporaryDirectory.appending(path: "np-rt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: runners) }
        for name in ["crossover-26.3.0.39832", "crossover-27.0.0.40921-fex", "other-1", ".crossover-1.new"] {
            try FileManager.default.createDirectory(at: runners.appending(path: name), withIntermediateDirectories: true)
        }
        #expect(RunnerStore.clonedBuilds(in: runners) == ["26.3.0.39832", "27.0.0.40921-fex"])
    }
```

Update fixtures that hard-code the old layout:
- `RunnerStateTests.swift:19`: `let root = runners.appending(path: "crossover-\(build)/root")`
- `RunnerInstallerTests.swift:33`: `atPath: target.appending(path: "root/lib/wine").path(percentEncoded: false)`
- `RunnerInstallerTests.swift:212`: replace `"crossover-\(version)/CrossOver/lib/wine"` with `"crossover-\(version)/root/lib/wine"`
- `RunnerSwitchTests.swift:533,549`: replace `/CrossOver` with `/root` inside the `.crossover-<id>.removing/...` fixture paths (leave the `runners/current` symlink fixtures at :184-302 unchanged).

- [ ] **Step 2:** `cd app && swift test --no-parallel --filter 'WineRuntimeTests|RunnerStateTests|RunnerInstallerTests|RunnerSwitchTests|TemplateCleanupTests'; cd ..` → FAIL on the new path assertions and the updated fixtures.

- [ ] **Step 3: Implement.** `SupportPaths.swift` — replace the runner helpers:

```swift
    // Runner clones live in runners/<runtime>-<build>/root
    static let clonedFolder = "root"

    static func runtime(forBuild build: String) -> RuntimeKind {
        SupportedRunners.build(id: build)?.runtime ?? .crossover
    }

    static func runnerRoot(forBuild build: String, runners: URL = SupportPaths.runners) -> URL {
        runners.appending(path: "\(runtime(forBuild: build).rawValue)-\(build)")
    }
```
```swift
    static func clonedRoot(forBuild build: String, runners: URL = SupportPaths.runners) -> URL {
        runnerRoot(forBuild: build, runners: runners).appending(path: clonedFolder)
    }
```
```swift
    static func prefixTemplate(forBuild build: String, flavor: CompatTool.Flavor, in library: SteamLibrary) -> URL {
        library.compatdata.appending(path: prefixTemplateFolder)
            .appending(path: "\(runtime(forBuild: build).rawValue)-\(build)-\(flavor.unixDir)")
    }
```

`RunnerStore.clonedBuilds`:

```swift
    static func clonedBuilds(in runners: URL = SupportPaths.runners) -> [String] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: runners, includingPropertiesForKeys: nil)) ?? []
        let prefixes = RuntimeKind.allCases.map { "\($0.rawValue)-" }
        return entries
            .map(\.lastPathComponent)
            .compactMap { name in prefixes.first(where: name.hasPrefix).map { String(name.dropFirst($0.count)) } }
            .sorted()
    }
```

`RunnerInstaller.removeLeftoverRemovals` — match any runtime:

```swift
    for entry in entries where entry.lastPathComponent.hasSuffix(".removing")
        && RuntimeKind.allCases.contains(where: { entry.lastPathComponent.hasPrefix(".\($0.rawValue)-") }) {
        try? fm.removeItem(at: entry)
    }
```

`RunnerInstaller.swift:154` template regex — any runtime prefix:

```swift
    let template = name.wholeMatch(of: #/[a-z]+-[A-Za-z0-9.-]+-(x86_64|aarch64)-unix/#) != nil
```

`RunnerInstaller.copyPayload` — land in `root`:

```swift
    let landing = target.appending(path: SupportPaths.clonedFolder)
```

`DeploymentContent.swift:181` and `:222` display labels: replace `"crossover-\(build)/\(path)"` with `"\(SupportPaths.runnerRoot(forBuild: build, runners: runners).lastPathComponent)/\(path)"` and `"crossover-\(build.id)/\(arch.rawValue)/ntdll.dll"` with `"\(build.runtime.rawValue)-\(build.id)/\(arch.rawValue)/ntdll.dll"`.

- [ ] **Step 4:** Re-run the Step 2 filter → PASS. Confirm `TemplateCleanupTests` (which requires `crossover--x86_64-unix`, `crossover-bad_build-x86_64-unix`, `crossover-26.3.0.39832-i386-unix` to survive) still passes.
- [ ] **Step 5:** FULL CHECK → **expected failures** in `buildcheck`/`envcheck`/`seedcheck`/`PrefixToolsTests.matchesRunScript` only if they assert the run script against the app's paths; the run script itself changes in Task 5. If any FULL CHECK failure is caused by the run script still using `crossover-$np_build/CrossOver`, record a ledger note and continue — Task 5 makes it green. Any other failure must be fixed here. Commit: `Move runner clones to <runtime>-<build>/root`.

---

### Task 3: `WineRuntime` protocol and `CrossOverRuntime`

**Files:**
- Modify: `app/Sources/NotProtonApp/Model/WineRuntime.swift`
- Modify: `app/Sources/NotProtonApp/Model/CrossOverSource.swift:146-152`
- Modify: `app/Sources/NotProtonApp/Model/PrefixTools.swift:123-173`
- Modify: `app/Sources/NotProtonApp/Model/RunnerSetup.swift` (`prepare` default `license:`)
- Test: `app/Tests/NotProtonAppTests/WineRuntimeTests.swift`

**Interfaces:**
- Consumes: `RuntimeKind`, `PrefixTools.WineLayout`, `CrossOverLicense.Status`.
- Produces:
```swift
protocol WineRuntime: Sendable {
    var kind: RuntimeKind { get }
    func unixLoader(inRoot root: URL) -> URL
    func layout(root: URL, flavor: CompatTool.Flavor) -> PrefixTools.WineLayout
    func baseEnvironment(root: URL) -> [String: String]
    func accessStatus(root: URL) -> CrossOverLicense.Status
}
extension RuntimeKind { var runtime: any WineRuntime }
struct CrossOverRuntime: WineRuntime
```
`CrossOverSource.unixLoader(inRoot:)`, `PrefixTools.layout(runner:flavor:)` and `PrefixTools.environment(prefix:runner:flavor:)` keep their signatures and delegate to `RuntimeKind.crossover.runtime`.

- [ ] **Step 1: Failing tests.** Append to `WineRuntimeTests`:

```swift
    @Test("CrossOver's loader is the x86_64 unix wine binary")
    func crossOverLoader() {
        let root = URL(filePath: "/R/root")
        #expect(RuntimeKind.crossover.runtime.unixLoader(inRoot: root).path(percentEncoded: false)
            == "/R/root/lib/wine/x86_64-unix/wine")
        #expect(CrossOverSource.unixLoader(inRoot: root) == RuntimeKind.crossover.runtime.unixLoader(inRoot: root))
    }

    @Test("CrossOver's base environment sets CX_ROOT and CX_HOME")
    func crossOverEnvironment() {
        let env = RuntimeKind.crossover.runtime.baseEnvironment(root: URL(filePath: "/R/root"))
        #expect(env["CX_ROOT"] == "/R/root")
        #expect(env["CX_HOME"]?.hasSuffix("/Library/Application Support/CrossOver") == true)
    }

    @Test("PrefixTools' layout is the runtime's layout")
    func layoutDelegates() {
        let root = URL(filePath: "/R/root")
        for flavor in CompatTool.Flavor.allCases {
            let a = PrefixTools.layout(runner: root, flavor: flavor)
            let b = RuntimeKind.crossover.runtime.layout(root: root, flavor: flavor)
            #expect(a.loader == b.loader && a.server == b.server && a.unixDir == b.unixDir)
        }
    }
```

- [ ] **Step 2:** `cd app && swift test --no-parallel --filter WineRuntimeTests; cd ..` → compile FAIL (`value of type 'RuntimeKind' has no member 'runtime'`).

- [ ] **Step 3: Implement.** Append to `WineRuntime.swift`:

```swift
// What differs between Wine distributions: where things live, the environment they need,
// and whether the user may use them
protocol WineRuntime: Sendable {
    var kind: RuntimeKind { get }
    func unixLoader(inRoot root: URL) -> URL
    func layout(root: URL, flavor: CompatTool.Flavor) -> PrefixTools.WineLayout
    func baseEnvironment(root: URL) -> [String: String]
    func accessStatus(root: URL) -> CrossOverLicense.Status
}

extension RuntimeKind {
    var runtime: any WineRuntime {
        switch self {
        case .crossover: CrossOverRuntime()
        }
    }
}

struct CrossOverRuntime: WineRuntime {
    var kind: RuntimeKind { .crossover }

    func unixLoader(inRoot root: URL) -> URL {
        root.appending(path: "lib/wine/x86_64-unix/wine")
    }

    func layout(root: URL, flavor: CompatTool.Flavor) -> PrefixTools.WineLayout {
        let fm = FileManager.default
        let bin = root.appending(path: "bin")
        func executable(_ url: URL) -> Bool { fm.isExecutableFile(atPath: url.path(percentEncoded: false)) }
        let arm = root.appending(path: "lib/wine/aarch64-unix")
        let armLoader = arm.appending(path: "wine.app/Contents/MacOS/wine")
        let armServer = bin.appending(path: "wineserver-arm64")
        if flavor == .fex, executable(armLoader), executable(armServer) {
            return PrefixTools.WineLayout(loader: armLoader, server: armServer, unixDir: arm)
        }
        let unix = root.appending(path: "lib/wine/x86_64-unix")
        let server = bin.appending(path: "wineserver")
        return PrefixTools.WineLayout(
            loader: unix.appending(path: "wine"),
            server: executable(server) ? server : bin.appending(path: "wineserver-x86"),
            unixDir: unix
        )
    }

    func baseEnvironment(root: URL) -> [String: String] {
        [
            "CX_ROOT": root.path(percentEncoded: false),
            "CX_HOME": SupportPaths.applicationSupport.appending(path: "CrossOver").path(percentEncoded: false),
        ]
    }

    func accessStatus(root: URL) -> CrossOverLicense.Status {
        CrossOverLicense.check(crossOverRoot: root)
    }
}
```

Before writing `layout`, open `PrefixTools.swift:146-173` and copy its body **exactly** (the code above mirrors the survey; if the file differs, the file wins). Then make `PrefixTools.layout` delegate:

```swift
    static func layout(runner: URL, flavor: CompatTool.Flavor = .fex) -> WineLayout {
        RuntimeKind.crossover.runtime.layout(root: runner, flavor: flavor)
    }
```

In `PrefixTools.environment`, replace the two `CX_ROOT`/`CX_HOME` assignments with:

```swift
        for (key, value) in RuntimeKind.crossover.runtime.baseEnvironment(root: runner) {
            environment[key] = value
        }
```

`CrossOverSource.swift`:

```swift
    static func unixLoader(inRoot root: URL) -> URL { RuntimeKind.crossover.runtime.unixLoader(inRoot: root) }
```

`RunnerSetup.prepare` default license closure:

```swift
    license: (URL) -> CrossOverLicense.Status = { RuntimeKind.crossover.runtime.accessStatus(root: $0) },
```

(M1 keeps `RuntimeKind.crossover` explicit at these call sites; M2 switches them to the build's runtime when a second runtime exists.)

- [ ] **Step 4:** `cd app && swift test --no-parallel --filter 'WineRuntimeTests|PrefixToolsTests|RunnerSetupTests|CrossOverSourceTests'; cd ..` → PASS.
- [ ] **Step 5:** FULL CHECK (same Task-5 caveat as Task 2). Commit: `Put CrossOver behind a WineRuntime protocol`.

---

### Task 4: `runtime` column in the tools list and per-tool `runtime` file

**Files:**
- Modify: `app/Sources/NotProtonApp/Model/RunnerStore.swift:99-101`
- Modify: `dylib/feats/compat.c:296-302,334-356,438-484,503-524`
- Test: `dylib/tests/compatcheck.c:231-298,333-372`, `app/Tests/NotProtonAppTests/DetectionTests.swift:177-181`, `dylib/tests/buildcheck.sh:28`

**Interfaces:**
- Consumes: `RunnerBuild.runtime` via `SupportedRunners.build(id:)`.
- Produces: TSV line `"\(name)\t\(build)\t\(flavor)\t\(runtime)\t\(display)\n"`; C `tool_entry_t.runtime[16]`; per-tool file `<tool dir>/runtime` containing `crossover\n`.

- [ ] **Step 1: Failing tests.**

`DetectionTests.swift:177-181` — expect the new width:
```swift
== "protonish-26.3\t26.3.0.39832\trosetta\tcrossover\tCrossOver 26.3\n"
```

`compatcheck.c` `tool_list_cases`: replace the fixture with 5-column lines plus one legacy 4-column line and one bad runtime:
```c
    fputs("protonish\t27.0.0.40921-fex\tfex\tcrossover\tCrossOver Preview (FEX)\n"
          "protonish-fex-41069\t27.0.0.41069-fex\tfex\tcrossover\tCrossOver Preview 41069 (FEX)\n"
          "protonish-fex-rosetta\t27.0.0.40921-fex\trosetta\tcrossover\tCrossOver Preview (Rosetta)\n"
          "protonish-26.3\t26.3.0.39832\trosetta\tCrossOver 26.3\n"
          "protonish\t26.3.0.39832\trosetta\tcrossover\tDuplicate\n"
          "proton-other\t1\trosetta\tcrossover\tForeign\n"
          "protonish-x\t1\tarm\tcrossover\tBad flavor\n"
          "protonish-q\t1\trosetta\tcrossover\tQuote\"d\n"
          "protonish-short\t1\trosetta\n"
          "protonish-rt\t1\trosetta\twinehq\tUnknown runtime\n"
          "protonish-six\t1\trosetta\tcrossover\tSix\textra\n"
          "\n", f);
```
and after the existing checks add:
```c
    check(strcmp(g_tools[0].runtime, "crossover") == 0
          && strcmp(g_tools[0].display, "CrossOver Preview (FEX)") == 0,
          "a five-column line carries its runtime and keeps the display");
    check(strcmp(g_tools[3].runtime, "crossover") == 0
          && strcmp(g_tools[3].display, "CrossOver 26.3") == 0,
          "a four-column line from an older app is a CrossOver tool");
```
Keep `check(kept == 4, …)` (the unknown-runtime and six-field lines must be rejected). Update the 40-line loop at :282 to `"protonish-%d\t1\trosetta\tcrossover\tTool %d\n"`.

`compatcheck.c` — new case function, called from `main` right after `stale_tool_cases();`:
```c
static void runtime_file_cases(void) {
    char root[] = "out/compatcheck-runtime.XXXXXX";
    if (!mkdtemp(root)) {
        check(0, "the runtime fixture directory can be made");
        return;
    }
    tool_entry_t tool = { 0 };
    snprintf(tool.name, sizeof(tool.name), "%s", "protonish-26.3");
    snprintf(tool.build, sizeof(tool.build), "%s", "26.3.0.39832");
    snprintf(tool.flavor, sizeof(tool.flavor), "%s", "rosetta");
    snprintf(tool.runtime, sizeof(tool.runtime), "%s", "crossover");
    snprintf(tool.display, sizeof(tool.display), "%s", "CrossOver 26.3");
    snprintf(tool.dir, sizeof(tool.dir), "%s/%s", root, tool.name);

    write_tool(&tool);
    char path[768];
    snprintf(path, sizeof(path), "%s/runtime", tool.dir);
    FILE *f = fopen(path, "r");
    char line[32] = { 0 };
    if (f) { fgets(line, sizeof(line), f); fclose(f); }
    check(strcmp(line, "crossover\n") == 0, "each tool directory records its runtime");

    remove_tool(root, tool.name);
    check(!exists(tool.dir), "removing a tool removes its runtime file and the directory");
    rmdir(root);
}
```

`buildcheck.sh:28` — write the 5-column form:
```sh
printf 'protonish\t27.0.0.40921-fex\tfex\tcrossover\tCrossOver Preview (FEX)\nprotonish-26.3\t26.3.0.39832\trosetta\tcrossover\tCrossOver 26.3\n' \
```

- [ ] **Step 2:** `make -s compatcheck; cd app && swift test --no-parallel --filter DetectionTests; cd ..` → FAIL (`tool_entry_t has no member named 'runtime'`; DetectionTests string mismatch).

- [ ] **Step 3: Implement.**

`RunnerStore.contents`:
```swift
    static func contents(_ tools: [InstalledTool]) -> String {
        tools.map { tool in
            let runtime = SupportPaths.runtime(forBuild: tool.build).rawValue
            return "\(tool.name)\t\(tool.build)\t\(tool.tool.flavor.rawValue)\t\(runtime)\t\(tool.display)\n"
        }.joined()
    }
```

`compat.c` struct (`:296-302`): add after `flavor`:
```c
    char runtime[16];
```

`compat.c` — add above `parse_tool_line`:
```c
// Wine runtimes this build of the dylib knows how to run
static int is_runtime(const char *s) {
    return s && strcmp(s, "crossover") == 0;
}
```

Replace `parse_tool_line` (`:334-356`):
```c
// name, build, flavor, [runtime,] display. Lines without a runtime come from an app
// that predates it and are CrossOver tools.
static int parse_tool_line(char *line, tool_entry_t *out) {
    char *field[5];
    int n = 0;
    char *save = NULL;
    for (char *tok = strtok_r(line, "\t", &save); tok && n < 5;
         tok = strtok_r(NULL, "\t", &save))
        field[n++] = tok;
    if (n == 5 && strtok_r(NULL, "\t", &save)) return 0;
    if (n != 4 && n != 5) return 0;
    const char *runtime = n == 5 ? field[3] : "crossover";
    const char *display = field[n - 1];

    if (!is_tool_name(field[0]) || !is_token(field[1], ".-")
        || (strcmp(field[2], "fex") != 0 && strcmp(field[2], "rosetta") != 0)
        || !is_runtime(runtime) || !is_display(display))
        return 0;
    if (strlen(field[0]) >= sizeof(out->name) || strlen(field[1]) >= sizeof(out->build)
        || strlen(display) >= sizeof(out->display))
        return 0;

    snprintf(out->name, sizeof(out->name), "%s", field[0]);
    snprintf(out->build, sizeof(out->build), "%s", field[1]);
    snprintf(out->flavor, sizeof(out->flavor), "%s", field[2]);
    snprintf(out->runtime, sizeof(out->runtime), "%s", runtime);
    snprintf(out->display, sizeof(out->display), "%s", display);
    return 1;
}
```
(The `strtok_r` check after the loop rejects lines with six or more fields, which the `n < 5` loop bound would otherwise truncate silently.)

`write_tool` — after the `build` file block:
```c
    snprintf(line, sizeof(line), "%s\n", tool->runtime);
    snprintf(path, sizeof(path), "%s/runtime", tool->dir);
    if (write_file(path, line, 0) == 0) wrote++;
    else NP_WARN("np_compat_ensure_tool_manifest: failed to write %s", path);
```

`remove_tool` file list:
```c
    static const char *const files[] = {
        "compatibilitytool.vdf", "toolmanifest.vdf", "run", "flavor", "build", "runtime",
    };
```

- [ ] **Step 4:** `make all && make -s compatcheck compatsvc-check buildcheck && cd app && swift test --no-parallel --filter 'DetectionTests|RunnerSwitchTests'; cd ..` → PASS. (`RunnerSwitchTests` prefixes like `"protonish-fex\t27.0.0.40921-fex\tfex\t"` still match because `runtime` follows `flavor`.)
- [ ] **Step 5:** FULL CHECK. Commit (app + dylib + tests together — Review Focus 1): `Add a runtime column to the compatibility tool list`.

---

### Task 5: Run script and build scripts follow the runtime

**Files:**
- Modify: `dylib/feats/compat_run.sh:140-171,302-316,636`
- Modify: `lsteamclient/build.sh:68-78`
- Test: `dylib/tests/buildcheck.sh:21,30,47`, `dylib/tests/envcheck.sh:44-45`, `app/Tests/NotProtonAppTests/RunnerSwitchTests.swift:622-641` (template names), `PrefixToolsTests.swift:45-107` (`matchesRunScript`)

**Interfaces:**
- Consumes: per-tool `runtime` file (Task 4), `runners/<runtime>-<build>/root` (Task 2), template id `<runtime>-<build>-<unixdir>` (Task 2).
- Produces: shell vars `np_runtime` (default `crossover`, charset-guarded `[a-z]`), `CX_ROOT="$np_support/runners/$np_runtime-$np_build/root"`.

- [ ] **Step 1: Failing tests.**

`buildcheck.sh`: replace every `runners/crossover-$1/CrossOver` / `runners/crossover-$build/CrossOver` with `runners/crossover-$1/root` / `runners/crossover-$build/root` (lines 21, 30, 47).
`envcheck.sh:44`: `library="$np_support/runners/crossover-$np_build/root/lib64/apple_gptk/external/libd3dshared.dylib"`. The eval at `:45` (`sed -n '/^CX_ROOT=/,/^wine_unix=/p'`) now also needs `np_runtime=crossover` set before the eval — add `np_runtime=crossover` next to where `np_build` is set in `envcheck.sh`.

- [ ] **Step 2:** `make -s buildcheck envcheck seedcheck; cd app && swift test --no-parallel --filter 'RunnerSwitchTests|PrefixToolsTests'; cd ..` → FAIL (script still builds `crossover-$np_build/CrossOver`; template names now `crossover-…` from `SupportPaths` but the script's `runner_id` is literal `crossover-` — it may still pass; the root-path assertions fail).

- [ ] **Step 3: Implement** in `compat_run.sh`.

After the `build` read (`:150-152`):
```sh
np_runtime=crossover
if [ -n "$np_tool_dir" ] && [ -r "$np_tool_dir/runtime" ]; then
  read -r np_runtime < "$np_tool_dir/runtime" || np_runtime=crossover
fi
case "$np_runtime" in ''|*[!a-z]*) np_runtime=crossover ;; esac
```
Replace `:157`:
```sh
CX_ROOT="$np_support/runners/$np_runtime-$np_build/root"
```
`last_wine_build` (`:305-316`):
```sh
  for inf in "$np_support"/runners/*-*/root/share/wine/wine.inf; do
```
```sh
    had_build=${inf#"$np_support/runners/"}
    had_build=${had_build%%/*}
    had_build=${had_build#*-}
    had_display=$(awk -F '\t' -v b="$had_build" '$2 == b { print $NF; exit }' \
      "$np_support/tools" 2>/dev/null) || had_display=""
```
Template id (`:636`):
```sh
[ -z "$np_build" ] || runner_id="$np_runtime-$np_build-${wine_unix##*/}"
```
Update `RunnerSwitchTests.templateNamesMatchTheScript` (`:622-641`): where it substitutes `$np_build` and `${wine_unix##*/}` into the extracted `runner_id`, also substitute `$np_runtime` with `crossover`.

`lsteamclient/build.sh:69`:
```sh
	for clone in "$HOME/Library/Application Support/protonish/runners"/*-*/root; do
```

- [ ] **Step 4:** `make all && make -s runcheck buildcheck envcheck seedcheck bridgecheck launchercheck && cd app && swift test --no-parallel --filter 'RunnerSwitchTests|PrefixToolsTests|LaunchEnvTests|ShimAgreementTests'; cd ..` → PASS. `buildcheck` asserts the display text from `last_wine_build`, which now comes from `$NF` (Review Focus 4).
- [ ] **Step 5:** FULL CHECK → all pass (this clears any Task 2/3 run-script caveats). Commit: `Derive the runner root from the tool's runtime in the run script`.

---

### Task 6: Docs, spec amendments, final verification

**Files:**
- Modify: `README.md` ("Changes from upstream")
- Modify: `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` §2.4, §3

- [ ] **Step 1: README** — add under "Changes from upstream":
```markdown
- 2026-10-14: Internal groundwork for more Wine runtimes: runners now live in
  `runners/<runtime>-<build>/root/`, and compatibility tools record their runtime. No change for CrossOver users.
```
- [ ] **Step 2: Spec §3** — replace the "Tool names:" bullet with:
```markdown
- Tool names: CrossOver tools keep their existing names (`protonish`, `protonish-fex`,
  `protonish-26.3`, …) so users' per-game tool choices survive. New runtimes use
  `protonish-<runtime>-<engine-id>`, e.g. `protonish-highball-x64-crossover26.3-r25`.
  Display name example: `Highball Wine 11 (r25)`.
```
Spec §2.4 — replace the bullet beginning "`compat_run.sh` reads `runtime`" with:
```markdown
- `compat_run.sh` reads `runtime` (default `crossover`) and derives
  `CX_ROOT=$support/runners/<runtime>-<build>/root`. `CX_ROOT` stays a top-level assignment
  (CrossOver reads it, and `envcheck.sh` evaluates that block). M2 adds a `case "$np_runtime"`
  for Highball-specific setup when the second runtime exists.
```
- [ ] **Step 3:** FULL CHECK + `make brandcheck` → all pass.
- [ ] **Step 4:** Commit: `Document the runtime groundwork`.
- [ ] **Step 5:** Ask the user before pushing / opening the PR.
