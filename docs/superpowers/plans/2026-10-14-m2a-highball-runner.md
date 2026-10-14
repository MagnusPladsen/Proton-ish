# M2a: Highball Runner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user with Highball's Wine 11 engine (`x64-crossover26.3-r19`) and no CrossOver set up a `protonish-highball-*` compatibility tool in Proton-ish and launch a Windows game from macOS Steam through it.

**Architecture:** Highball becomes the second `RuntimeKind`. A Highball runner copies `engines/<id>/engine/*` straight into `runners/highball-<id>/root/`, so `root/lib/wine/...` has the same shape as a CrossOver clone and the existing ntdll patching, builtin install, bridge staging and run-script paths work unchanged. Only the loader location (`root/bin/wine` instead of `root/lib/wine/x86_64-unix/wine`), loader signing (unsigned → fresh entitlements), environment (`root/runtime.env` from the manifest's `baseEnv`, DXMT renderer, `WINEUSERNAME=steamuser`) and discovery/UI differ.

**Tech Stack:** Swift 6.4 / SwiftUI / swift-testing, C (dylib), POSIX sh, mingw-w64 + Python/capstone (ntdll payloads), GNU Make.

**Spec:** `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` §2, §4, §5, §9 (M2). Task 11 amends §4.2 for the flattened layout decided here.

## Global Constraints

- Supported Highball engine in M2a: `x64-crossover26.3-r19` only (what Highball 0.10.10 offers). Rosetta only; one compat tool per engine.
- Highball engine home: `$HIGHBALL_HOME` if set, else `home` from `~/Library/Application Support/Highball/config.json` if present, else `~/Library/Application Support/Highball`. Engines: `<home>/engines/<id>/manifest.json`.
- Runner layout: `runners/highball-<engine-id>/root/` = contents of `engines/<id>/engine/` (so `root/bin/wine`, `root/bin/wineserver`, `root/lib/wine/{i386-windows,x86_64-windows,x86_64-unix}`, `root/share/wine`) **plus** `root/frameworks/`, `root/renderers/`, `root/manifest.json` copied from `engines/<id>/`, plus `root/runtime.env` written by the app.
- `RunnerBuild` for Highball: `bundleVersion` = engine id (`x64-crossover26.3-r19`), `releaseVersion` = `r19`, `flavor` = nil, `runtime` = `.highball`. Build ids must stay within the dylib's build charset `[A-Za-z0-9.-]`.
- Tool name `protonish-highball-x64-crossover26.3-r19`, display `Highball Wine 11 (r19)`, flavor `rosetta`.
- Highball needs no licence: `accessStatus` returns `licensed: true`. The CrossOver licence path is unchanged.
- Loader signing for a loader with no entitlements: fresh plist with `com.apple.security.cs.allow-dyld-environment-variables` and `com.apple.security.cs.disable-library-validation`, `codesign -f -s - --options runtime`. CrossOver loaders keep the existing extend-entitlements path.
- Renderer in M2a: DXMT always (`WINEDLLPATH_PREPEND=$CX_ROOT/renderers/dxmt/wine` when that directory exists). The options-panel mapping is M2b. Never copy or redistribute D3DMetal outside the user's own machine.
- `WINEUSERNAME=steamuser` for Highball (Highball's patch 0001 makes Wine use `WINEUSERNAME`, which is how Proton gets `C:\users\steamuser`).
- Wine 10 engines are listed as "not supported" (their `ntdll.so` lacks `ntdll_get_unix_file_name`/`ntdll_get_dos_file_name`, which `lsteamclient.so` imports).
- No behaviour change for CrossOver. Keep internal names; `make brandcheck` clean; commits via `/commit` format; README changelog line.

## Review Focus

1. **Runtime decided by the wrong source** — runner bookkeeping must read the runtime from the directory name (M1 review finding, spec §9 M2), or an unsupported Highball build can't be removed and its templates get deleted. Pinned in Task 1 with a real `highball-<id>` directory.
2. **Signing skipped silently** — `RunnerPatcher.unixLoaders` only scans `lib/wine/*-unix`, so a Highball loader at `root/bin/wine` would be neither signed nor verified, and `DYLD_*` variables would be stripped at launch. Pinned in Task 6 with an unsigned binary fixture.
3. **Clone identity wrong after signing** — signing rewrites `root/bin/wine`; `verifyClone` must hash the clean copy (`Clean.copy(of:)`), and the loader path must come from the build's runtime, not `CrossOverSource`. Pinned in Task 4.
4. **Run script launching Highball with CrossOver's loader** — the existing selection falls back to `lib/wine/x86_64-unix/wine`, which doesn't exist in a Highball root. Pinned by an envcheck case in Task 8.
5. **`runtime.env` as an injection vector** — the run script must only export validated `KEY=VALUE` lines (key `[A-Z_][A-Z0-9_]*`), never `eval` or source the file. Pinned by an envcheck case with a malicious line in Task 8.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `app/Sources/NotProtonApp/Model/WineRuntime.swift` | `.highball`, `HighballRuntime`, runtime-from-directory | 1, 2 |
| `app/Sources/NotProtonApp/Support/SupportPaths.swift`, `Model/RunnerStore.swift` | runtime from directory name | 1 |
| `dylib/feats/compat.c` | accept `highball` | 1 |
| `app/Sources/NotProtonApp/Model/HighballSource.swift` (new) | engine discovery | 3 |
| `app/Sources/NotProtonApp/Model/RunnerInstaller.swift` | Highball clone + `runtime.env` | 4 |
| `ntdll-patch/*`, `app/Sources/NotProtonApp/Resources/detour{2,32}-hb-r19.bin`, `app/Package.swift`, `Model/NtdllPatcher.swift`, `Model/SupportedRunner.swift` | r19 pins | 5 |
| `app/Sources/NotProtonApp/Model/RunnerPatcher.swift` | loader at `root/bin/wine`, fresh-entitlement signing | 6 |
| `app/Sources/NotProtonApp/Model/RunnerSetup.swift` | `run(from: HighballEngine)`, runtime-aware licence | 7 |
| `dylib/feats/compat_run.sh` | Highball branch, `runtime.env`, launcher `.app` | 8 |
| `app/Sources/NotProtonApp/SystemStatus.swift`, `Views/StatusView.swift`, `Localizable.xcstrings` | Highball section + Set Up | 9 |
| `README.md`, spec | docs | 10, 11 |

### FULL CHECK

Same as M1 (`export PATH="$PWD/scratch/fontvenv/bin:$PATH"; make all overlay-shim iconmaker appinfo && make app && make -s app-tests && for t in l10ncheck sigcheck callscheck webpatch-fixtures peicon-fixtures panel-behavior spawn-env compatcheck compatsvc-check shortcutcheck launch-shell envcheck buildcheck settingscheck routecheck bridgecheck gamedrivecheck launchercheck seedcheck scriptcheck runcheck brandcheck mincheck; do make -s $t || exit 1; done`).

### Engine fixture for Tasks 3–6

The r19 Wine tarball: `https://github.com/gauthierpiarrette/highball-engine/releases/download/engine-wine-11.0-20261005T184024Z-0019-forza-trial/engine-wine-11.0-20261005T184024Z-0019-forza-trial.tar.gz`, sha256 `d20d540a26775b4065d1922018411f36716de4e5e15a1327aae25d5400fc84b9`. Extract to `scratch/hb-r19/` (gitignored); it yields `scratch/hb-r19/engine/`. Known clean hashes: x86_64 `ntdll.dll` `6fc64ddf477780ea949cf3b02ce5d6bc147da596c9feb9f7379d3ea7f55433ca`, i386 `ntdll.dll` `e0c057cfd6d12bb62df58b7f71cfcf9a07704b4ffd1095442e784eea3f3f0bd2`.

---

### Task 0: Branch, baseline, engine fixture

- [ ] **Step 1:** `git checkout main && git pull --ff-only origin main && git checkout -b feat/m2a-highball-runner`
- [ ] **Step 2:** FULL CHECK → pass (519+ tests).
- [ ] **Step 3:** Download and verify the engine fixture:
```bash
mkdir -p scratch/hb-r19 && cd scratch/hb-r19 \
 && curl -fsSL -o wine.tar.gz "<tarball URL above>" \
 && echo "d20d540a26775b4065d1922018411f36716de4e5e15a1327aae25d5400fc84b9  wine.tar.gz" | shasum -a 256 -c \
 && tar xzf wine.tar.gz && shasum -a 256 engine/bin/wine engine/lib/wine/*-windows/ntdll.dll; cd ../..
```
Expected: `wine.tar.gz: OK`; the two ntdll hashes match the fixture section. Record the `engine/bin/wine` hash in the ledger (it is the loader pin for Task 5).

---

### Task 1: `.highball` and `HighballRuntime`

**Files:** `WineRuntime.swift`; test `WineRuntimeTests.swift`.

**Interfaces:** `RuntimeKind.highball` (with `RuntimeKind.runtime` returning `HighballRuntime()` for it); `struct HighballRuntime: WineRuntime` — `unixLoader(inRoot:)` → `root/bin/wine`; `layout(root:flavor:)` → loader `root/bin/wine`, server `root/bin/wineserver`, unixDir `root/lib/wine/x86_64-unix` (flavor ignored); `baseEnvironment(root:)` → `["CX_FWD_COMPAT_GL_CTX": "1", "WINEUSERNAME": "steamuser"]` merged with the parsed `root/runtime.env`; `accessStatus(root:)` → `CrossOverLicense.Status(licensed: true, detail: "", diagnostic: "highball: no licence")`. Static `HighballRuntime.parseEnvFile(_ text: String) -> [String: String]` accepts only lines matching `^[A-Z_][A-Z0-9_]*=.*$`, ignores everything else.

- [ ] **Step 1: Failing tests:**
```swift
    @Test("Highball's loader and server live in bin, its unix libraries in lib/wine")
    func highballLayout() {
        let root = URL(filePath: "/R/root")
        let runtime = RuntimeKind.highball.runtime
        #expect(runtime.unixLoader(inRoot: root).path(percentEncoded: false) == "/R/root/bin/wine")
        let layout = runtime.layout(root: root, flavor: .fex)
        #expect(layout.loader.path(percentEncoded: false) == "/R/root/bin/wine")
        #expect(layout.server.path(percentEncoded: false) == "/R/root/bin/wineserver")
        #expect(layout.unixDir.path(percentEncoded: false) == "/R/root/lib/wine/x86_64-unix")
        #expect(runtime.accessStatus(root: root).licensed)
    }

    @Test("runtime.env keeps only plain KEY=VALUE lines")
    func envFileParsing() {
        let parsed = HighballRuntime.parseEnvFile("""
        DYLD_FALLBACK_LIBRARY_PATH=/R/root/frameworks
        WINEDEBUG=fixme-all
        # comment
        lower=no
        BAD KEY=no
        $(touch /tmp/x)=no
        GST_PLUGIN_PATH=/a b/c
        """)
        #expect(parsed == ["DYLD_FALLBACK_LIBRARY_PATH": "/R/root/frameworks", "WINEDEBUG": "fixme-all",
                           "GST_PLUGIN_PATH": "/a b/c"])
    }
```
- [ ] **Step 2:** FAIL. **Step 3: Implement** in `WineRuntime.swift`: add `case highball` to `RuntimeKind` and `case .highball: HighballRuntime()` to `RuntimeKind.runtime`, then:
```swift
// Highball's engine copied flat into root: bin/wine is the loader and there is no licence
struct HighballRuntime: WineRuntime {
    var kind: RuntimeKind { .highball }

    func unixLoader(inRoot root: URL) -> URL { root.appending(path: "bin/wine") }

    func layout(root: URL, flavor: CompatTool.Flavor) -> PrefixTools.WineLayout {
        PrefixTools.WineLayout(
            loader: root.appending(path: "bin/wine"),
            server: root.appending(path: "bin/wineserver"),
            unixDir: root.appending(path: "lib/wine/x86_64-unix")
        )
    }

    func baseEnvironment(root: URL) -> [String: String] {
        let file = (try? String(contentsOf: root.appending(path: "runtime.env"), encoding: .utf8)) ?? ""
        return Self.parseEnvFile(file).merging(["CX_FWD_COMPAT_GL_CTX": "1", "WINEUSERNAME": "steamuser"]) { _, fixed in fixed }
    }

    func accessStatus(root: URL) -> CrossOverLicense.Status {
        CrossOverLicense.Status(licensed: true, detail: "", diagnostic: "highball: no licence")
    }

    static func parseEnvFile(_ text: String) -> [String: String] {
        var env: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.wholeMatch(of: #/[A-Z_][A-Z0-9_]*=.*/#) != nil,
                  let eq = line.firstIndex(of: "=") else { continue }
            env[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return env
    }
}
```
- [ ] **Step 4:** PASS. **Step 5:** FULL CHECK; commit `Add the Highball runtime`.

---

### Task 2: Runtime from the directory name, dylib accepts `highball`

**Files:** `WineRuntime.swift`, `SupportPaths.swift:53-75`, `RunnerStore.swift:42-50`, `dylib/feats/compat.c` (`is_runtime`), tests `WineRuntimeTests.swift`, `dylib/tests/compatcheck.c`.

**Interfaces:**
- Consumes: `RuntimeKind.highball` (Task 1). Produces: `SupportPaths.runtime(forBuild:runners:)` — the kind whose `runners/<kind>-<build>` directory exists, else `SupportedRunners.build(id:)?.runtime`, else `.crossover`; `runnerRoot(forBuild:runners:)` uses it. `RunnerStore.clonedBuilds` unchanged in signature.

- [ ] **Step 1: Failing tests** — in `WineRuntimeTests`:
  - replace `supportedBuildsAreCrossOver` with:
```swift
    @Test("Every supported build names a known runtime")
    func supportedBuildsHaveRuntimes() {
        #expect(SupportedRunners.all.allSatisfy { RuntimeKind.allCases.contains($0.runtime) })
    }
```
  - add:
```swift
    @Test("A clone's runtime comes from its directory, even for a build no longer supported")
    func runtimeFromDirectory() throws {
        let runners = FileManager.default.temporaryDirectory.appending(path: "np-rt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: runners) }
        try FileManager.default.createDirectory(at: runners.appending(path: "highball-x64-old-r1/root/lib/wine"),
                                                withIntermediateDirectories: true)
        #expect(SupportPaths.runtime(forBuild: "x64-old-r1", runners: runners) == .highball)
        #expect(SupportPaths.runnerRoot(forBuild: "x64-old-r1", runners: runners).lastPathComponent == "highball-x64-old-r1")
        #expect(RunnerStore.clonedBuilds(in: runners) == ["x64-old-r1"])
        #expect(RunnerInstaller.hasClone(forBuild: "x64-old-r1", runners: runners))
    }
```
  - `compatcheck.c` `tool_list_cases`: add fixture line `"protonish-highball-x64-crossover26.3-r19\tx64-crossover26.3-r19\trosetta\thighball\tHighball Wine 11 (r19)\n"` before `"protonish-26.3\t…"`'s duplicate line, raise `check(kept == 4` to `kept == 5`, and add `check(strcmp(g_tools[4].runtime, "highball") == 0, "a highball tool keeps its runtime");` (adjust the index to the line's position among kept lines; keep `protonish-rt … winehq` rejected).
- [ ] **Step 2:** run `swift test --filter WineRuntimeTests` and `make -s compatcheck` → FAIL (runtime still looked up from `SupportedRunners`; kept 4).
- [ ] **Step 3: Implement.** `SupportPaths`:
```swift
    static func runtime(forBuild build: String, runners: URL = SupportPaths.runners) -> RuntimeKind {
        let fm = FileManager.default
        if let kind = RuntimeKind.allCases.first(where: {
            fm.fileExists(atPath: runners.appending(path: "\($0.rawValue)-\(build)").path(percentEncoded: false))
        }) { return kind }
        return SupportedRunners.build(id: build)?.runtime ?? .crossover
    }

    static func runnerRoot(forBuild build: String, runners: URL = SupportPaths.runners) -> URL {
        runners.appending(path: "\(runtime(forBuild: build, runners: runners).rawValue)-\(build)")
    }
```
  (`prefixTemplate` keeps calling `runtime(forBuild:)` with the default `runners`.) `compat.c`:
```c
static int is_runtime(const char *s) {
    return s && (strcmp(s, "crossover") == 0 || strcmp(s, "highball") == 0);
}
```
- [ ] **Step 4:** tests PASS. **Step 5:** FULL CHECK; commit `Read runner runtimes from their directories`.

---

### Task 3: Highball engine discovery

**Files:** Create `app/Sources/NotProtonApp/Model/HighballSource.swift`; test `app/Tests/NotProtonAppTests/HighballSourceTests.swift`.

**Interfaces:**
```swift
enum HighballSupport: Sendable, Equatable { case supported(RunnerBuild), unsupported, unreadable }
struct HighballEngine: Sendable, Identifiable {
    let id: String          // engine id from manifest.json
    let directory: URL      // engines/<id>
    let displayName: String
    let support: HighballSupport
    var isUsable: Bool
}
enum HighballSource {
    static func home(environment: [String: String] = ProcessInfo.processInfo.environment,
                     defaultHome: URL = SupportPaths.applicationSupport.appending(path: "Highball")) -> URL
    static func discover(home: URL = HighballSource.home()) -> [HighballEngine]
}
```
Identity: sha256 of `engines/<id>/engine/bin/wine` → `SupportedRunners.build(loaderSHA256:)` with `runtime == .highball`.

- [ ] **Step 1: Failing tests** (`HighballSourceTests.swift`): (a) `home` honours `HIGHBALL_HOME`, then `config.json` `{"home": "/X"}` inside the default home, then the default; (b) `discover` on a temp home with `engines/x64-fake-r1/{manifest.json, engine/bin/wine}` returns one engine with id `x64-fake-r1`, `displayName` from manifest `displayName`, support `.unsupported` (unknown loader hash); (c) a directory without `manifest.json` is skipped; (d) a manifest that is not JSON yields `.unreadable`. Write each as a `@Test` using `scratchDirectory(_:)` from `TestSupport.swift`.
- [ ] **Step 2:** FAIL (no type). **Step 3: Implement** `HighballSource.swift`:
```swift
// Finds Highball's installed engines. Highball keeps them outside its app bundle.

import Foundation

enum HighballSupport: Sendable, Equatable {
    case supported(RunnerBuild)
    case unsupported
    case unreadable
}

struct HighballEngine: Sendable, Identifiable {
    let id: String
    let directory: URL
    let displayName: String
    let support: HighballSupport
    var isUsable: Bool { if case .supported = support { true } else { false } }
    var engineRoot: URL { directory.appending(path: "engine") }
}

enum HighballSource {
    static func home(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultHome: URL = SupportPaths.applicationSupport.appending(path: "Highball")
    ) -> URL {
        if let override = environment["HIGHBALL_HOME"], !override.isEmpty { return URL(filePath: override) }
        let config = defaultHome.appending(path: "config.json")
        if let data = try? Data(contentsOf: config),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let home = object["home"] as? String, !home.isEmpty {
            return URL(filePath: home)
        }
        return defaultHome
    }

    static func discover(home: URL = HighballSource.home()) -> [HighballEngine] {
        let engines = home.appending(path: "engines")
        let entries = (try? FileManager.default.contentsOfDirectory(at: engines, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap(inspect).sorted { $0.id < $1.id }
    }

    static func inspect(_ directory: URL) -> HighballEngine? {
        let manifest = directory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path(percentEncoded: false)) else { return nil }
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return HighballEngine(id: directory.lastPathComponent, directory: directory,
                                  displayName: directory.lastPathComponent, support: .unreadable)
        }
        let id = (object["id"] as? String) ?? directory.lastPathComponent
        let name = (object["displayName"] as? String) ?? id
        let loader = directory.appending(path: "engine/bin/wine")
        let support: HighballSupport
        if let hash = Digest.sha256IfPresent(loader),
           let build = SupportedRunners.build(loaderSHA256: hash), build.runtime == .highball {
            support = .supported(build)
        } else {
            support = .unsupported
        }
        return HighballEngine(id: id, directory: directory, displayName: name, support: support)
    }
}
```
- [ ] **Step 4:** PASS. **Step 5:** FULL CHECK; commit `Discover Highball engines`.

---

### Task 4: Cloning a Highball engine

**Files:** `RunnerInstaller.swift`; tests `RunnerInstallerTests.swift`.

**Interfaces:**
- Consumes: `HighballEngine`, `HighballRuntime`.
- Produces: `RunnerInstaller.clone(from engine: HighballEngine, replacingExisting: Bool = false, runners: URL = SupportPaths.runners) throws -> RunnerBuild`; `RunnerInstaller.writeRuntimeEnv(manifest: URL, root: URL) throws`; `verifyClone` uses `build.runtime.runtime.unixLoader(inRoot:)`.

- [ ] **Step 1: Failing tests:** build a fake engine dir in a scratch dir: `engines/x64-fake-r1/{manifest.json, engine/bin/wine, engine/lib/wine/x86_64-windows/ntdll.dll, engine/lib/wine/i386-windows/ntdll.dll, frameworks/libX.dylib, renderers/dxmt/wine/x86_64-windows/d3d11.dll}` with a manifest `{"id":"x64-fake-r1","displayName":"Fake","baseEnv":{"DYLD_FALLBACK_LIBRARY_PATH":"${frameworks}","WINEDEBUG":"fixme-all","bad key":"x"}}`, and a `RunnerBuild` pinned to those bytes with `runtime: .highball` (mirror `makeSupportedInstall`'s pinning). Assert after `clone(from:)`: `runners/highball-x64-fake-r1/root/bin/wine` exists; `root/lib/wine/x86_64-windows/ntdll.dll` exists; `root/frameworks/libX.dylib` and `root/renderers/dxmt/wine/x86_64-windows/d3d11.dll` exist; `root/manifest.json` exists; `root/runtime.env` contains exactly `DYLD_FALLBACK_LIBRARY_PATH=<root>/frameworks` and `WINEDEBUG=fixme-all` (sorted, `bad key` dropped); `hasClone` is true. A second test: tampering `root/bin/wine` after cloning makes `verifyClone` throw "does not match build".
- [ ] **Step 2:** FAIL. **Step 3: Implement.**
```swift
    static func clone(from engine: HighballEngine, replacingExisting: Bool = false,
                      runners: URL = SupportPaths.runners) throws -> RunnerBuild {
        guard case .supported(let build) = engine.support else {
            throw StepFailure(step: step, detail: String(localized: "Highball engine \(engine.id) isn't supported yet."))
        }
        let fm = FileManager.default
        let target = runners.appending(path: "\(build.runtime.rawValue)-\(build.id)")
        let existing = hasClone(forBuild: build.id, runners: runners)
        let occupied = fm.fileExists(atPath: target.path(percentEncoded: false))
        if !existing || replacingExisting {
            let staging = runners.appending(path: ".\(target.lastPathComponent).new")
            try? fm.removeItem(at: staging)
            try copyPayload(from: engine.engineRoot, to: staging)
            let root = staging.appending(path: SupportPaths.clonedFolder)
            for extra in ["frameworks", "renderers", "manifest.json"] {
                let source = engine.directory.appending(path: extra)
                guard fm.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
                let copied = try Shell.run("/bin/cp", ["-c", "-R", source.path(percentEncoded: false),
                                                       root.appending(path: extra).path(percentEncoded: false)])
                if copied.status != 0 {
                    let plain = try Shell.run("/bin/cp", ["-R", source.path(percentEncoded: false),
                                                          root.appending(path: extra).path(percentEncoded: false)])
                    guard plain.status == 0 else {
                        throw StepFailure(step: step, detail: String(localized: "Copying \(extra) failed. \(plain.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"))
                    }
                }
            }
            scrubDownloadMarkers(at: root)
            try writeRuntimeEnv(manifest: root.appending(path: "manifest.json"), root: target.appending(path: SupportPaths.clonedFolder))
            if occupied { try fm.removeItem(at: target) }
            try fm.moveItem(at: staging, to: target)
        }
        try verifyClone(build: build, root: target.appending(path: SupportPaths.clonedFolder))
        return build
    }

    // The manifest's baseEnv, with ${frameworks} pointing into the clone. The run script reads it.
    static func writeRuntimeEnv(manifest: URL, root: URL) throws {
        let data = try Data(contentsOf: manifest)
        let object = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let base = (object["baseEnv"] as? [String: String]) ?? [:]
        let frameworks = root.appending(path: "frameworks").path(percentEncoded: false)
        let lines = base
            .filter { $0.key.wholeMatch(of: #/[A-Z_][A-Z0-9_]*/#) != nil && !$0.value.contains("\n") }
            .map { "\($0.key)=\($0.value.replacingOccurrences(of: "${frameworks}", with: frameworks))" }
            .sorted()
        // Written next to the staged manifest, before the staging directory moves into place
        let staged = manifest.deletingLastPathComponent().appending(path: "runtime.env")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: staged, options: .atomic)
    }
```
(The `root` argument is the **final** root so `${frameworks}` points at the installed location; the file is written into the staging root.) In `verifyClone`, replace `CrossOverSource.unixLoader(inRoot: root)` with `build.runtime.runtime.unixLoader(inRoot: root)`. In `CrossOverSource.verifyPatchInputs`, keep as is (it hashes `root/lib/wine/<arch>/ntdll.dll`, valid for both runtimes); change its step text from "Verify CrossOver" to `String(localized: "Verify runner")` and add the zh-Hans translation `验证运行器` to `Localizable.xcstrings`.
- [ ] **Step 4:** PASS (`RunnerInstallerTests`, `RunnerSetupTests`, `CrossOverSourceTests`), `make -s l10ncheck` after `make app`. **Step 5:** FULL CHECK; commit `Clone Highball engines into flat runner roots`.

---

### Task 5: Pin the r19 engine (payloads, hashes, supported build)

**Files:** `ntdll-patch/resolve.py` (`PINNED`), `ntdll-patch/apply.py` (`PAYLOAD_BY_CLEAN_SHA`), `ntdll-patch/build-ntdll.sh` (HB_R19 vars + flavor case), new `app/Sources/NotProtonApp/Resources/detour2-hb-r19.bin`, `detour32-hb-r19.bin`, `app/Package.swift`, `NtdllPatcher.swift` (`byBuild`), `SupportedRunner.swift` (`all`).

- [ ] **Step 1: Failing test** — the existing `NtdllPatcherTests` loops (`patchesMatchRecordedArches`, `everyPinnedPayloadResolves`, `everyPinnedPayloadFitsItsCave`) cover any new entry. Add to `WineRuntimeTests`:
```swift
    @Test("Highball r19 is a supported Rosetta build with one tool")
    func highballR19Supported() throws {
        let build = try #require(SupportedRunners.build(id: "x64-crossover26.3-r19"))
        #expect(build.runtime == .highball)
        #expect(build.tools.map(\.name) == ["protonish-highball-x64-crossover26.3-r19"])
        #expect(build.tools.allSatisfy { $0.flavor == .rosetta })
        #expect(NtdllPatcher.byBuild["x64-crossover26.3-r19"]?.count == 2)
    }
```
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: Derive constants.** `cd ntdll-patch && python3 resolve.py ../scratch/hb-r19/engine/lib/wine` (use the capstone venv from M0, e.g. `scratch/fontvenv/bin/pip install capstone` then that python). Expected: x86_64 hook `0x484f3`, cave `0x7a0a0` (padding, 3936 bytes); i386 hook `0x453d0`, cave `0xaf000` (`placement section`). Copy every printed value (`hookRVA`, `stolen`, `caveRVA`, `caveSize`, `wm`, `resume`, `load_path`, exports) into a new `PINNED` entry keyed by each clean sha (follow the shape of the existing `26.3.0.39832` entries in `PINNED`, leaving `payload` empty for now).
- [ ] **Step 4: Build payloads.** `sh build.sh ../scratch/hb-r19/engine/lib/wine/x86_64-windows/ntdll.dll hb-r19` and `sh build32.sh ../scratch/hb-r19/engine/lib/wine/i386-windows/ntdll.dll hb-r19`. Expected: `detour2-hb-r19.bin`, `detour32-hb-r19.bin`, with their sha256 printed. Put those shas into `PINNED[…]['payload']`, add both clean shas to `apply.py` `PAYLOAD_BY_CLEAN_SHA`, rerun both builds → they now verify against the pin. Copy the two `.bin` files to `app/Sources/NotProtonApp/Resources/` and add `.copy("Resources/detour2-hb-r19.bin")`, `.copy("Resources/detour32-hb-r19.bin")` to `app/Package.swift` next to the `-cx26` entries.
- [ ] **Step 5: Patched hashes.** Add `HB_R19_CLEAN_X86_64/I386` and `HB_R19_PATCHED_*` variables and a `hb-r19) BUILD=x64-crossover26.3-r19 ;;` flavor case to `build-ntdll.sh` mirroring `cx26`; run `CX_ROOT=../scratch/hb-r19/engine sh build-ntdll.sh` with the patched values left empty, read the printed patched sha256 for each arch, fill them in, rerun → "matches" for both.
- [ ] **Step 6: Swift pins.** `NtdllPatcher.byBuild["x64-crossover26.3-r19"]`: two `NtdllPatch` entries shaped like `26.3.0.39832` — x86_64 with `payloadResource: "detour2-hb-r19"`, `caveRVA`/`payloadRVA` `0x7a0a0`, `caveSize: 3936`, default `.padding`; i386 with `"detour32-hb-r19"`, `0xaf000`, `caveSize: 0x1000`, `placement: .section`; hooks/stolen/machine/magic/imageBase from resolve.py, payload shas from Step 4. `SupportedRunners.all` gains:
```swift
        RunnerBuild(
            bundleVersion: "x64-crossover26.3-r19",
            releaseVersion: "r19",
            flavor: nil,
            loaderSHA256: "<engine/bin/wine sha256 recorded in Task 0>",
            cleanNtdll: [
                .x86_64Windows: "6fc64ddf477780ea949cf3b02ce5d6bc147da596c9feb9f7379d3ea7f55433ca",
                .i386Windows: "e0c057cfd6d12bb62df58b7f71cfcf9a07704b4ffd1095442e784eea3f3f0bd2",
            ],
            patchedNtdll: [
                .x86_64Windows: "<from Step 5>",
                .i386Windows: "<from Step 5>",
            ],
            tools: [
                CompatTool(name: "protonish-highball-x64-crossover26.3-r19", flavor: .rosetta,
                           display: "Highball Wine 11 (r19)"),
            ],
            runtime: .highball
        ),
```
  The three `<…>` values are produced by Steps 0/5 of this plan and must be real hashes before committing (`git grep -n '<engine/bin/wine\|<from Step 5>'` must print nothing).
- [ ] **Step 7:** `swift test --filter 'WineRuntimeTests|NtdllPatcherTests'` PASS. **Step 8:** FULL CHECK; commit `Pin Highball engine x64-crossover26.3-r19`.

---

### Task 6: Find and sign Highball's loader

**Files:** `RunnerPatcher.swift` (`unixLoaders`, `grantLoaderEntitlement`, `sign`, `name(of:)`); test `RunnerPatcherTests.swift`.

**Interfaces:** `unixLoaders(in:)` also returns `root/bin/wine` when it exists and no `lib/wine/*-unix/wine` exists; `grantLoaderEntitlement` signs a loader with no entitlements using a fresh plist (`allow-dyld-environment-variables`, `disable-library-validation`); `name(of:)` returns `bin/wine` for it.

- [ ] **Step 1: Failing tests:**
```swift
    @Test("Highball's bin/wine is found as the loader")
    func binLoaderFound() throws {
        let root = try scratchDirectory("hb-loader")
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = root.appending(path: "bin/wine")
        try FileManager.default.createDirectory(at: loader.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "lib/wine/x86_64-unix"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: loader)
        #expect(RunnerPatcher.unixLoaders(in: root) == [loader])
        #expect(RunnerPatcher.unixArches(in: root) == ["x86_64-unix"])
    }

    @Test("A loader with no entitlements is signed with a fresh set")
    func unsignedLoaderGetsFreshEntitlements() throws {
        let root = try scratchDirectory("hb-sign")
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = root.appending(path: "bin/wine")
        try FileManager.default.createDirectory(at: loader.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: loader)
        _ = try Shell.run("/usr/bin/codesign", ["--remove-signature", loader.path(percentEncoded: false)])
        let signed = try RunnerPatcher.grantEntitlementsForTesting(root: root)
        #expect(signed == ["bin/wine"])
        let granted = try #require(RunnerPatcher.entitlements(of: loader))
        #expect(granted.contains("com.apple.security.cs.allow-dyld-environment-variables"))
        #expect(granted.contains("com.apple.security.cs.disable-library-validation"))
    }
```
  (`/usr/bin/true` is a universal Mach-O; removing its signature on a copy gives an unsigned fixture. If `entitlements(of:)` is private, make it `static` internal; add `static func grantEntitlementsForTesting(root:) throws -> [String] { try grantLoaderEntitlement(root: root) }` only if `grantLoaderEntitlement` must stay private — prefer making `grantLoaderEntitlement` internal and calling it directly, and record which in the ledger.)
- [ ] **Step 2:** FAIL. **Step 3: Implement.** `unixLoaders`:
```swift
    static func unixLoaders(in root: URL) -> [URL] {
        let fm = FileManager.default
        let wine = root.appending(path: "lib/wine")
        let entries = (try? fm.contentsOfDirectory(at: wine, includingPropertiesForKeys: nil)) ?? []
        let inUnix = entries
            .filter { $0.lastPathComponent.hasSuffix("-unix") }
            .flatMap { [$0.appending(path: "wine"), $0.appending(path: "wine.app/Contents/MacOS/wine")] }
            .filter { fm.fileExists(atPath: $0.path(percentEncoded: false)) }
            .sorted { $0.path < $1.path }
        if !inUnix.isEmpty { return inUnix }
        // Highball keeps its loader in bin, next to wineserver
        let bin = root.appending(path: "bin/wine")
        return fm.fileExists(atPath: bin.path(percentEncoded: false)) ? [bin] : []
    }
```
  `unixArches`: when the only loader is `bin/wine`, return `["x86_64-unix"]` (the existing fallback already does). `name(of:)`: if the loader's parent is `bin`, return `"bin/wine"`. `grantLoaderEntitlement`: replace the `guard let existing, !existing.isEmpty else { throw … }` with:
```swift
        let base = (existing?.isEmpty == false) ? existing! : Self.freshEntitlements
        do { try sign(loader, addingTo: base) } catch { restoreClean(loader); throw error }
```
  and add:
```swift
    // For a loader that ships unsigned (Highball): enough to keep DYLD_* variables and load
    // the unsigned dylibs Highball injects
    static let freshEntitlements = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
    </dict></plist>
    """
```
  (`sign` already adds `allow-dyld-environment-variables` with PlistBuddy.) Existing CrossOver tests asserting "carries no entitlements to extend" must be updated: that error no longer exists; replace with an assertion that an unsigned loader ends up with both entitlements (record as a ruling — the spec §4.6 requires it).
- [ ] **Step 4:** PASS. **Step 5:** FULL CHECK; commit `Find and sign Highball's unsigned loader`.

---

### Task 7: Set up a Highball runner

**Files:** `RunnerSetup.swift`; test `RunnerSetupTests.swift`.

**Interfaces:** `RunnerSetup.run(from engine: HighballEngine, replacingExisting: Bool = false, report:) throws -> Outcome` = `report(.cloning)`, `RunnerInstaller.clone(from: engine…)`, `prepare(build…)`. `prepare`'s default `license` becomes runtime-aware.

- [ ] **Step 1: Failing test:** `prepare` on a Highball build root (fake clone with `runtime: .highball`, stub `verify`/`stage`/`patch` closures as existing `RunnerSetupTests` do) succeeds without a CrossOver licence file present, and writes the tool list line with `\thighball\t`.
- [ ] **Step 2:** FAIL (default licence closure checks CrossOver). **Step 3: Implement:** change the `license` parameter to `license: ((RunnerBuild, URL) -> CrossOverLicense.Status)? = nil` and inside `prepare` use `let status = license?(build, root) ?? build.runtime.runtime.accessStatus(root: root)`; update existing callers/tests that pass a `license:` closure to the two-argument form. Add `run(from engine: HighballEngine, …)`. `Phase.cloning.label`: change "Copying CrossOver" to `String(localized: "Copying the Wine runtime")` (+ zh-Hans `正在复制 Wine 运行时`).
- [ ] **Step 4:** PASS. **Step 5:** FULL CHECK; commit `Set up Highball runners`.

---

### Task 8: Run script — Highball branch

**Files:** `dylib/feats/compat_run.sh`; tests `dylib/tests/envcheck.sh`, `app/Tests/NotProtonAppTests/PrefixToolsTests.swift`.

- [ ] **Step 1: Failing tests** — `envcheck.sh`, new section after "Runtime read from the tool directory":
```sh
echo "== Highball runner environment =="
hb_block=$(sed -n '/^# Highball: loader in bin/,/^fi # highball$/p' "$SRC")
[ -n "$hb_block" ] || { echo "FAIL: Highball block not found"; exit 1; }
hb=$(mktemp -d)
CX_ROOT="$hb/root"; np_runtime=highball
mkdir -p "$CX_ROOT/bin" "$CX_ROOT/lib/wine/x86_64-unix" "$CX_ROOT/renderers/dxmt/wine"
printf 'DYLD_FALLBACK_LIBRARY_PATH=%s/frameworks\nlower=x\n$(touch %s/pwned)=x\nWINEDEBUG=fixme-all\n' "$CX_ROOT" "$hb" > "$CX_ROOT/runtime.env"
WINELOADER=/wrong; WINESERVER=/wrong; wine_unix=/wrong
eval "$hb_block"
is "Highball loader is bin/wine" "$CX_ROOT/bin/wine" "$WINELOADER"
is "Highball server is bin/wineserver" "$CX_ROOT/bin/wineserver" "$WINESERVER"
is "Highball unix dir" "$CX_ROOT/lib/wine/x86_64-unix" "$wine_unix"
is "runtime.env value exported" "$CX_ROOT/frameworks" "$DYLD_FALLBACK_LIBRARY_PATH"
is "runtime.env never executes" "no" "$([ -e "$hb/pwned" ] && echo yes || echo no)"
is "DXMT renderer is prepended" "$CX_ROOT/renderers/dxmt/wine" "$WINEDLLPATH_PREPEND"
is "Windows user is steamuser" "steamuser" "$WINEUSERNAME"
rm -rf "$hb"
```
  `PrefixToolsTests`: add a case asserting `PrefixTools.layout`/`environment` for a Highball runner use `bin/wine` (after Step 3 routes PrefixTools through the build's runtime — see below).
- [ ] **Step 2:** FAIL (block missing). **Step 3: Implement.** In `compat_run.sh`, directly before `export WINELOADER WINESERVER`:
```sh
# Highball: loader in bin, engine environment from runtime.env, DXMT, Proton's user name
if [ "$np_runtime" = highball ]; then
  wine_unix="$CX_ROOT/lib/wine/x86_64-unix"
  WINELOADER="$CX_ROOT/bin/wine"
  WINESERVER="$CX_ROOT/bin/wineserver"
  if [ -r "$CX_ROOT/runtime.env" ]; then
    while IFS= read -r np_env_line || [ -n "$np_env_line" ]; do
      case "$np_env_line" in
        [A-Z_]*=*)
          np_env_key=${np_env_line%%=*}
          case "$np_env_key" in *[!A-Z0-9_]*) continue ;; esac
          export "$np_env_key=${np_env_line#*=}"
          ;;
      esac
    done < "$CX_ROOT/runtime.env"
  fi
  [ ! -d "$CX_ROOT/renderers/dxmt/wine" ] || export WINEDLLPATH_PREPEND="$CX_ROOT/renderers/dxmt/wine"
  export CX_FWD_COMPAT_GL_CTX=1 WINEUSERNAME=steamuser
fi # highball
```
  Launcher `.app` (around `ln "$WINELOADER" "$loader_macos/wine"`): for Highball the loader finds its libraries relative to `../lib`; after the hard link add:
```sh
if [ "$np_runtime" = highball ]; then
  ln -sfn "$CX_ROOT/lib" "$loader_app/Contents/lib"
  ln -sfn "$CX_ROOT/share" "$loader_app/Contents/share"
fi
```
  App side: `PrefixTools.layout(runner:flavor:)` and `environment(prefix:runner:flavor:)` gain a `runtime: RuntimeKind = .crossover` parameter used instead of the hard-coded `.crossover`; callers that know the build (`PrefixTools.swift:70,197,218,271`, `PrefixRebuild.swift:15`) pass `SupportPaths.runtime(forBuild: build)`.
- [ ] **Step 4:** `make -s envcheck runcheck seedcheck buildcheck launchercheck` and `swift test --filter 'PrefixToolsTests|LaunchEnvTests|ShimAgreementTests'` PASS. **Step 5:** FULL CHECK; commit `Launch games through Highball runners`.

---

### Task 9: Highball in the Status screen

**Files:** `SystemStatus.swift`, `Views/StatusView.swift`, `Resources/Localization/Localizable.xcstrings`; test `SystemStatusTests.swift`.

**Interfaces:** `StatusSnapshot.highball: [HighballEngine]` (filled by `HighballSource.discover()` in `capture()`); `SystemStatus.setUpHighball(_ engine: HighballEngine, replacingExisting: Bool = false) async` (mirrors `setUpRunner(from:)` but calls `RunnerSetup.run(from: engine…)` with no licence question); `SystemStatus.highballNotice: String?` — "Proton-ish needs Highball's Wine 11 engine. Switch an environment to Wine 11 in Highball's environment settings." when engines exist but none is Wine 11 (`id.hasPrefix("x64-crossover")`), "Highball engine %@ isn't supported yet." for an unsupported Wine 11 engine, nil otherwise.

- [ ] **Step 1: Failing tests** in `SystemStatusTests`: `highballNotice` for (a) only `x64-sikarugir10.0_6-r21` → Wine 11 message; (b) `x64-crossover26.3-r99` unsupported → "isn't supported yet" with the id; (c) supported r19 → nil; (d) no engines → nil. Build `HighballEngine` values directly.
- [ ] **Step 2:** FAIL. **Step 3: Implement** the snapshot field, `highballNotice`, and `setUpHighball`. In `StatusView`, add a `highballSection` after `crossOverSection` (same `Section`/`StatusRow` pattern as `crossOverSection` at `StatusView.swift:529-571`): header "Highball"; one row per discovered engine — title `engine.displayName`, subtitle `engine.id`; trailing button "Set Up" (enabled when `engine.isUsable` and the build is not installed) or "Reinstall" (installed) calling `Task { await status.setUpHighball(engine, replacingExisting: installed) }`; unsupported engines show "Not supported yet"; footer shows `highballNotice` when non-nil; when no Highball home exists, show "Not found. Install Highball from gethighball.com." Add every new user-visible string to `Localizable.xcstrings` with a zh-Hans translation (strings: "Highball", "Set Up", "Reinstall", "Not supported yet", "Not found. Install Highball from gethighball.com.", the two notices) — reuse existing keys where they already exist (`Set Up`, `Reinstall` likely exist; check with `grep`).
- [ ] **Step 4:** tests PASS; `make app && make -s l10ncheck` PASS. **Step 5:** FULL CHECK; commit `Show Highball engines on the Status screen`.

---

### Task 10: End-to-end test with the user (manual gate)

- [ ] **Step 1:** Ask the user to confirm the Highball environment has been switched to Wine 11 and `~/Library/Application Support/Highball/engines/x64-crossover26.3-r19/engine/bin/wine` exists; verify its sha256 equals the Task 0 pin.
- [ ] **Step 2:** `make app && open out/Proton-ish.app`; user clicks Install (Steam integration) and then Highball → Set Up.
- [ ] **Step 3:** Verify on disk: `~/Library/Application Support/protonish/runners/highball-x64-crossover26.3-r19/root/` exists; `bin/wine` has both entitlements (`codesign -d --entitlements - …`); `lib/wine/x86_64-windows/ntdll.dll` hash = patched pin; tools file has the highball line.
- [ ] **Step 4:** User restarts Steam, picks a free Windows game, sets Compatibility → "Highball Wine 11 (r19)", plays. Collect `protonish-run.log` from the game's prefix. Success = game window opens and Steam shows the user as in-game (lsteamclient working). Record outcome in the ledger. If it fails, use superpowers:systematic-debugging with the log; do not mark M2a done.

---

### Task 11: Docs

- [ ] **Step 1:** README: under "Why Proton-ish exists" change "starting with Highball (in progress, not usable yet)" to "starting with Highball (Wine 11 engine; Wine 10 is not supported yet)"; add "Changes from upstream" line `- 2026-10-14: Highball support: set up a Highball Wine 11 engine as a Steam Play compatibility tool.`; add bug-template runtime option `Highball` back.
- [ ] **Step 2:** Spec §4.2: replace the copy description with the flattened layout from Global Constraints; §1 "Out of scope": add "Highball Wine 10 engines (need an lsteamclient build against Wine 10)". Remove the M2 bookkeeping note added after M1 (done in Task 1).
- [ ] **Step 3:** brandcheck docs check that forbids "Highball" in the bug template: remove that one check (Highball is now supported). FULL CHECK. Commit `Document Highball support`.
