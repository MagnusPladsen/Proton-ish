# M2c: highball-db Prefix Recipes at Launch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Windows game run through a `protonish-highball-*` tool gets the `registry`, `file` and `copy` steps of its highball-db recipe applied to its Steam prefix before the first launch, once per prefix per database version, the way Highball applies them to its own bottles.

**Architecture:** `highball-env` (the helper that already computes the launch environment with HighballKit) also plans and applies the prefix steps: it writes `file` and `copy` targets itself, rewrites game-folder paths to the real Steam install folder, and turns the registry steps into one `.reg` file inside `drive_c`. The run script imports that file with `wine reg import` under the game's own environment, then writes a marker so the next launch skips the recipe. A Status screen switch, overridable per game with a Steam launch option, decides whether recipes verified on another Wine line apply.

**Tech Stack:** Swift 6 / SwiftPM / swift-testing (`HighballEnvCore`, `highball-env`, `NotProtonApp`), HighballKit 0.10.16 (`Recipe`, `EngineStore`, `RecipeRunner.copySource`), POSIX sh (`dylib/feats/compat_run.sh`, `dylib/tests/envcheck.sh`), GNU Make, String Catalog.

**Spec:** `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` §4.7, bullet "Prefix recipes, M2c (2026-10-19)" and the two M2c rows in §5. Task 9 amends the spec where this plan deviates (the `.reg` file lives in `drive_c`, see Global Constraints).

**User decisions (2026-10-19):** every recipe applies, `optIn` ignored; once per prefix per database version; no rollback; recipes pinned to another engine line apply by default, with a global switch and a per-game launch option (option C), and the user is told about the launch option where the switch is; manual test games Portal 2 (620) and Warframe (230410); M2c before the Wine 10 Sikarugir pin.

## Global Constraints

- **Branch:** `feature/m2c-prefix-recipes` (exists, two spec commits on it). Never commit to `main`. Commits through `/commit` format: subject, bullets, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Stage named files only, never `git add -A`. No push unless the user asks.
- **Git identity:** `git config user.email` in `~/git/NotProton` is `93226629+MagnusPladsen@users.noreply.github.com`; keep it.
- **Step types in scope:** `registry` (`REG_SZ`, `REG_DWORD`; the bundled database has only these, 17 values, all `HKCU`), `file` (3 in the database), `copy` (2, both `asNative: true`). `installer`, `winetricks`, `winver` and `requires: ["dotnet48"]` keep the log note "not applied yet". `optIn` is never read.
- **Registry file:** `$WINEPREFIX/drive_c/protonish-recipe.reg`, imported as `C:\protonish-recipe.reg` (the same route `import_prefix_settings` uses for `notproton-settings.*`), format `Windows Registry Editor Version 5.00`, CRLF line ends, `HKCU` expanded to `HKEY_CURRENT_USER`, `HKLM` to `HKEY_LOCAL_MACHINE`. REG_SZ data escapes `\` as `\\` and `"` as `\"`; REG_DWORD data is decimal in the database and written as `dword:%08x`. An empty value name writes `@=`. The spec names `$STEAM_COMPAT_DATA_PATH/protonish-recipe.reg`; this plan uses `drive_c` so Wine reads it through `C:` without depending on the `Z:` drive. Task 9 corrects the spec.
- **Marker:** `$STEAM_COMPAT_DATA_PATH/protonish-recipe`, three lines: recipe id, highball-db commit (full hash from `GameData.commit`), engine build id. Written by the run script only after the `.reg` import succeeded (or no `.reg` was needed). The helper prints `# recipe: <id> <commit> <engine>` when the run script should record.
- **Target rewrite:** a `file`/`copy` target `Program Files (x86)/Steam/steamapps/common/<installdir>/<rest>` becomes `<install path>/<rest>` when `<installdir>` equals the last path component of `--install-path` case-insensitively (Steam's `installdir` is that folder's name). Any other target goes under `drive_c`. A path containing a `..` component is refused with a note. `copy` sources come from `RecipeRunner.copySource(engineRoot:_:)`, which already refuses absolute paths and `..`.
- **Engine line:** `engineLine(of:)` strips the trailing `-r<digits>` from an engine id (`x64-crossover26.3-r25` → `x64-crossover26.3`, `x64-sikarugir10.0_6-r5` → `x64-sikarugir10.0_6`). Same line, any revision: apply silently. Other line: apply with a note when allowed, else skip the whole recipe (environment steps from M2b included? **No**: M2b's environment steps are unaffected by the switch; only the prefix steps are skipped. The log says so.)
- **Switch:** `<support>/recipe-other-engines` holds `apply` or `skip`; a missing file means `apply`. The run script passes `--other-engines apply|skip`. The Steam launch option `PROTONISH_RECIPE_OTHER_ENGINES=0` or `=1` on one game wins over the switch; `highball-env` reads it from its environment (the run script exports launch options).
- **Helper contract (unchanged):** output lines are `KEY=VALUE`, `# note: …`, `# error: …`, and now `# recipe: …`. Exit 0 and `# error:` on failure. The helper has 10 s; file and copy steps are a few small files.
- **Logging:** every note the helper prints lands in `protonish-run.log` as `highball-env: note: …`; the run script's own lines start with `recipe:`.
- **CrossOver runners:** untouched; the helper only runs when `np_runtime = highball`.
- **Tests:** swift-testing, one assertion per test where possible, `@Suite`/`@Test` with sentence titles, as in `app/Tests/HighballEnvCoreTests/GameTuningTests.swift`. Shell tests go in `dylib/tests/envcheck.sh` (`make envcheck`). `make runcheck` (shellcheck) must stay clean. `make brandcheck` flags a user-visible "NotProton".
- **Strings:** every `String(localized:)` key goes into `app/Sources/NotProtonApp/Resources/Localization/Localizable.xcstrings` with a `zh-Hans` translation, written by a script like the scratchpad's `catalog-guidance.py` (`json.dumps(ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)`, no trailing newline). `make l10ncheck` must pass. Interpolations use `%@`.
- **Docs:** README `## Using Highball` and a dated line under `## Changes from upstream`; `.claude/TODO.md` M2c items marked done.
- **Build:** `app/Sources/NotProtonApp/Resources/payload/run` is a build copy of `dylib/feats/compat_run.sh`; edit the source, never the payload.

## Review Focus

1. **Recipe data as an injection vector:** a REG_SZ value containing `"` or `\` or a newline must not break the `.reg` file or write a different key. Pinned in Task 1 (escaping, newline refused).
2. **A `file` target that climbs out of the prefix** (`../../..` in a path) must be refused, not written. Pinned in Task 2.
3. **A game in a second Steam library** (install path not under the default library) must get its `autoexec.cfg` in its real folder, not under `drive_c`. Pinned in Task 2 (rewrite is driven by `--install-path`, not by a folder under `drive_c`).
4. **A reinstalled game lost the copied DLL** while the marker still says applied; the copy must come back. Pinned in Task 4.
5. **A failed `reg import` must not lose the launch and must not write the marker**, and a stale `.reg` from an earlier crashed launch must not be imported for a recipe that no longer applies. Pinned in Task 7.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `app/Sources/HighballEnvCore/PrefixRecipe.swift` (new) | REGEDIT text, target rewrite, engine-line decision, marker, apply | 1–5 |
| `app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift` (new) | pure-function tests | 1–5 |
| `app/Sources/HighballEnvCore/GameTuning.swift` | stop noting registry/file/copy as "not applied yet" | 6 |
| `app/Sources/HighballEnvCore/LaunchEnvironment.swift` | call `PrefixRecipe.run`, print `# recipe:` | 6 |
| `app/Sources/highball-env/main.swift` | `--install-path`, `--applied`, `--reg`, `--other-engines` | 6 |
| `app/Tests/HighballEnvCoreTests/LaunchEnvironmentTests.swift` | end-to-end helper test | 6 |
| `dylib/feats/compat_run.sh` | pass the options, parse `# recipe:`, `apply_prefix_recipe` | 7 |
| `dylib/tests/envcheck.sh` | shell tests for the above | 7 |
| `app/Sources/NotProtonApp/Model/OtherEngineFixes.swift` (new) | the switch's file | 8 |
| `app/Tests/NotProtonAppTests/OtherEngineFixesTests.swift` (new) | its tests | 8 |
| `app/Sources/NotProtonApp/SystemStatus.swift`, `Views/StatusView.swift` | snapshot field, action, row | 8 |
| `Localizable.xcstrings` | new keys | 8 |
| `README.md`, `.claude/TODO.md`, spec | docs | 9 |

---

### Task 1: Registry steps become REGEDIT text

**Files:**
- Create: `app/Sources/HighballEnvCore/PrefixRecipe.swift`
- Create: `app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift`

**Interfaces:**
- Consumes: `HighballKit.Recipe.Step.registry(key:name:type:data:)`.
- Produces: `PrefixRecipe.registryText(_ steps: [Recipe.Step]) -> (text: String?, notes: [String])`; `text` is nil when no registry step was usable.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import HighballKit
import Testing

@testable import HighballEnvCore

@Suite("Prefix recipe steps")
struct PrefixRecipeTests {

    // A recipe as highball-db ships it; HighballKit decodes the same JSON the helper reads
    func recipe(_ steps: [[String: Any]], id: String = "game", engine: String? = nil) throws -> Recipe {
        var json: [String: Any] = ["id": id, "kind": "game", "title": id, "steps": steps]
        if let engine { json["engine"] = engine }
        return try JSONDecoder().decode(Recipe.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func registry(_ key: String, _ name: String, _ type: String, _ data: String) -> [String: Any] {
        ["type": "registry", "key": key, "name": name, "valueType": type, "data": data]
    }

    @Test("A REG_SZ value becomes a quoted line under its expanded key")
    func regSZ() throws {
        let steps = try recipe([registry("HKCU\\Software\\Wine\\AppDefaults\\portal2.exe\\Direct3D", "VideoMemorySize", "REG_SZ", "2047")]).steps
        #expect(PrefixRecipe.registryText(steps).text ==
            "Windows Registry Editor Version 5.00\r\n\r\n[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\portal2.exe\\Direct3D]\r\n\"VideoMemorySize\"=\"2047\"\r\n")
    }

    @Test("A REG_DWORD value is written as eight hex digits")
    func regDWORD() throws {
        let steps = try recipe([registry("HKCU\\Software\\Valve\\Source\\hl2\\Settings", "VendorID", "REG_DWORD", "4098")]).steps
        #expect(PrefixRecipe.registryText(steps).text?.contains("\"VendorID\"=dword:00001002\r\n") == true)
    }

    @Test("Backslashes and quotes in REG_SZ data are escaped")
    func regEscaping() throws {
        let steps = try recipe([registry("HKCU\\Software\\Test", "Path", "REG_SZ", "C:\\Games\\\"x\"")]).steps
        #expect(PrefixRecipe.registryText(steps).text?.contains("\"Path\"=\"C:\\\\Games\\\\\\\"x\\\"\"\r\n") == true)
    }

    @Test("An empty value name is the key's default value")
    func regDefaultValue() throws {
        let steps = try recipe([registry("HKCU\\Software\\Test", "", "REG_SZ", "v")]).steps
        #expect(PrefixRecipe.registryText(steps).text?.contains("\r\n@=\"v\"\r\n") == true)
    }

    @Test("Two values under one key share one key header")
    func regSharedKey() throws {
        let steps = try recipe([registry("HKCU\\Software\\Test", "A", "REG_SZ", "1"),
                                registry("HKCU\\Software\\Test", "B", "REG_SZ", "2")]).steps
        #expect(PrefixRecipe.registryText(steps).text?.components(separatedBy: "[HKEY_CURRENT_USER\\Software\\Test]").count == 2)
    }

    @Test("A value type the writer does not know is noted and left out")
    func regUnknownType() throws {
        let steps = try recipe([registry("HKCU\\Software\\Test", "Blob", "REG_BINARY", "00ff")]).steps
        let result = PrefixRecipe.registryText(steps)
        #expect(result.text == nil)
        #expect(result.notes == ["registry value Blob not applied: REG_BINARY is not supported yet"])
    }

    @Test("REG_DWORD data that is not a number is noted and left out")
    func regBadNumber() throws {
        let steps = try recipe([registry("HKCU\\Software\\Test", "N", "REG_DWORD", "lots")]).steps
        #expect(PrefixRecipe.registryText(steps).notes == ["registry value N not applied: 'lots' is not a number"])
    }

    @Test("A line break in data is refused, it would start a new line in the file")
    func regLineBreak() throws {
        let steps = try recipe([registry("HKCU\\Software\\Test", "N", "REG_SZ", "a\nb")]).steps
        #expect(PrefixRecipe.registryText(steps).notes == ["registry value N not applied: data has a line break"])
    }

    @Test("A key outside HKCU and HKLM is refused")
    func regUnknownRoot() throws {
        let steps = try recipe([registry("HKCR\\steam", "x", "REG_SZ", "1")]).steps
        #expect(PrefixRecipe.registryText(steps).notes == ["registry value x not applied: key root HKCR is not supported"])
    }

    @Test("Without registry steps there is no file")
    func regNone() throws {
        let steps = try recipe([["type": "environment", "name": "A", "value": "1"]]).steps
        #expect(PrefixRecipe.registryText(steps).text == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: compile error, `PrefixRecipe` not found.

- [ ] **Step 3: Write the implementation**

```swift
// The prefix-changing steps of a highball-db recipe, applied to a Steam prefix the way Highball
// applies them to its own bottles: registry values through one .reg file the run script imports
// under the game's environment, files and engine copies written here. Highball's RecipeRunner
// runs `wine reg add` itself; a Steam launch has one Wine environment, the game's, so the
// import happens there instead.

import Foundation
import HighballKit

public enum PrefixRecipe {

    // One .reg file for every registry step, in the format `reg import` reads
    static func registryText(_ steps: [Recipe.Step]) -> (text: String?, notes: [String]) {
        var notes: [String] = []
        var lines: [String] = []
        var lastKey: String?
        for case let .registry(key, name, type, data) in steps {
            guard let expanded = expandRoot(key) else {
                notes.append("registry value \(name) not applied: key root \(key.split(separator: "\\").first.map(String.init) ?? key) is not supported")
                continue
            }
            guard !data.contains(where: \.isNewline) else {
                notes.append("registry value \(name) not applied: data has a line break")
                continue
            }
            guard let value = registryValue(type: type, data: data, name: name, notes: &notes) else { continue }
            if expanded != lastKey {
                if lastKey != nil { lines.append("") }
                lines.append("[\(expanded)]")
                lastKey = expanded
            }
            lines.append((name.isEmpty ? "@" : "\"\(name)\"") + "=" + value)
        }
        guard !lines.isEmpty else { return (nil, notes) }
        return ((["Windows Registry Editor Version 5.00", ""] + lines).joined(separator: "\r\n") + "\r\n", notes)
    }

    private static func expandRoot(_ key: String) -> String? {
        let parts = key.split(separator: "\\", maxSplits: 1).map(String.init)
        let root: String? = switch parts.first {
        case "HKCU", "HKEY_CURRENT_USER": "HKEY_CURRENT_USER"
        case "HKLM", "HKEY_LOCAL_MACHINE": "HKEY_LOCAL_MACHINE"
        default: nil
        }
        guard let root else { return nil }
        return parts.count == 2 ? root + "\\" + parts[1] : root
    }

    private static func registryValue(type: String, data: String, name: String, notes: inout [String]) -> String? {
        switch type {
        case "REG_SZ":
            return "\"" + data.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        case "REG_DWORD":
            guard let number = UInt32(data) else {
                notes.append("registry value \(name) not applied: '\(data)' is not a number")
                return nil
            }
            return String(format: "dword:%08x", number)
        default:
            notes.append("registry value \(name) not applied: \(type) is not supported yet")
            return nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: 10 tests pass. HighballKit decodes a registry step's type from `"valueType"` (default `REG_DWORD` when absent), so the test helper's JSON matches the database.

- [ ] **Step 5: Commit**

```bash
cd ~/git/NotProton && git add app/Sources/HighballEnvCore/PrefixRecipe.swift app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift
git commit -F - <<'EOF'
Turn highball-db registry steps into a .reg file

- PrefixRecipe.registryText writes REG_SZ and REG_DWORD values under
  HKCU and HKLM in the format wine reg import reads
- Unknown types, roots and line breaks are noted and left out

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 2: File targets land in the game's real folder

**Files:**
- Modify: `app/Sources/HighballEnvCore/PrefixRecipe.swift`
- Modify: `app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift`

**Interfaces:**
- Produces: `PrefixRecipe.target(of path: String, driveC: URL, installPath: URL?) -> URL?` (nil when refused).

- [ ] **Step 1: Write the failing tests** (append inside the suite)

```swift
    static let driveC = URL(fileURLWithPath: "/pfx/drive_c")
    static let install = URL(fileURLWithPath: "/Volumes/Games/SteamLibrary/steamapps/common/Portal 2")

    @Test("A path in the game's Steam folder is rewritten to the real install folder")
    func targetInGameFolder() {
        let url = PrefixRecipe.target(of: "Program Files (x86)/Steam/steamapps/common/Portal 2/portal2/cfg/autoexec.cfg",
                                      driveC: Self.driveC, installPath: Self.install)
        #expect(url?.path == "/Volumes/Games/SteamLibrary/steamapps/common/Portal 2/portal2/cfg/autoexec.cfg")
    }

    @Test("The install folder name matches case-insensitively, as Steam's installdir does")
    func targetCaseInsensitive() {
        let url = PrefixRecipe.target(of: "Program Files (x86)/Steam/steamapps/common/portal 2/portal2/cfg/video.txt",
                                      driveC: Self.driveC, installPath: Self.install)
        #expect(url?.path == "/Volumes/Games/SteamLibrary/steamapps/common/Portal 2/portal2/cfg/video.txt")
    }

    @Test("Another game's folder stays under drive C")
    func targetOtherGame() {
        let url = PrefixRecipe.target(of: "Program Files (x86)/Steam/steamapps/common/Portal/portal/cfg/autoexec.cfg",
                                      driveC: Self.driveC, installPath: Self.install)
        #expect(url?.path == "/pfx/drive_c/Program Files (x86)/Steam/steamapps/common/Portal/portal/cfg/autoexec.cfg")
    }

    @Test("A path outside the Steam library stays under drive C")
    func targetPlain() {
        let url = PrefixRecipe.target(of: "users/steamuser/Documents/My Games/x.ini", driveC: Self.driveC, installPath: Self.install)
        #expect(url?.path == "/pfx/drive_c/users/steamuser/Documents/My Games/x.ini")
    }

    @Test("Without an install path nothing is rewritten")
    func targetNoInstallPath() {
        let url = PrefixRecipe.target(of: "Program Files (x86)/Steam/steamapps/common/Portal 2/portal2/cfg/autoexec.cfg",
                                      driveC: Self.driveC, installPath: nil)
        #expect(url?.path == "/pfx/drive_c/Program Files (x86)/Steam/steamapps/common/Portal 2/portal2/cfg/autoexec.cfg")
    }

    @Test("A path that climbs out with .. is refused")
    func targetDotDot() {
        #expect(PrefixRecipe.target(of: "users/../../../etc/hosts", driveC: Self.driveC, installPath: Self.install) == nil)
    }

    @Test("An absolute path is refused")
    func targetAbsolute() {
        #expect(PrefixRecipe.target(of: "/etc/hosts", driveC: Self.driveC, installPath: Self.install) == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: compile error, `target(of:driveC:installPath:)` missing.

- [ ] **Step 3: Write the implementation** (add to `PrefixRecipe`)

```swift
    static let steamCommon = "Program Files (x86)/Steam/steamapps/common/"

    // Where a file or copy step's target goes. Highball's bottles hold the Steam library under
    // drive C; a Steam game on the Mac lives in its library folder and reaches the prefix
    // through a drive letter, so a target in the game's folder goes there.
    public static func target(of path: String, driveC: URL, installPath: URL?) -> URL? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.hasPrefix("/"), !parts.contains(".."), !parts.contains("") else { return nil }
        if let installPath, path.hasPrefix(steamCommon) {
            let inside = path.dropFirst(steamCommon.count).split(separator: "/", maxSplits: 1).map(String.init)
            if inside.count == 2, inside[0].caseInsensitiveCompare(installPath.lastPathComponent) == .orderedSame {
                return installPath.appending(path: inside[1])
            }
        }
        return driveC.appending(path: path)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: 17 tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/git/NotProton && git add app/Sources/HighballEnvCore/PrefixRecipe.swift app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift
git commit -F - <<'EOF'
Send recipe files to the game's real Steam folder

- PrefixRecipe.target rewrites steamapps/common/<installdir> targets
  to the folder Steam launched the game from
- Absolute paths and .. components are refused

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 3: Recipes pinned to another engine line

**Files:**
- Modify: `app/Sources/HighballEnvCore/PrefixRecipe.swift`
- Modify: `app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift`

**Interfaces:**
- Produces: `PrefixRecipe.EngineDecision` (`.apply`, `.applyWithNote(verifiedOn:)`, `.skip(verifiedOn:)`), `PrefixRecipe.engineDecision(recipeEngine: String?, running: String, otherEngines: Bool) -> EngineDecision`, `PrefixRecipe.engineLine(of: String) -> String`, `PrefixRecipe.otherEnginesAllowed(switchValue: String?, launchOption: String?) -> Bool`.

- [ ] **Step 1: Write the failing tests** (append inside the suite)

```swift
    @Test("The engine line is the id without its revision")
    func engineLine() {
        #expect(PrefixRecipe.engineLine(of: "x64-sikarugir10.0_6-r5") == "x64-sikarugir10.0_6")
    }

    @Test("A recipe without an engine applies")
    func engineNone() {
        #expect(PrefixRecipe.engineDecision(recipeEngine: nil, running: "x64-crossover26.3-r25", otherEngines: false) == .apply)
    }

    @Test("Another revision of the same line applies without a note")
    func engineSameLine() {
        #expect(PrefixRecipe.engineDecision(recipeEngine: "x64-crossover26.3-r15", running: "x64-crossover26.3-r25", otherEngines: false) == .apply)
    }

    @Test("Another line applies with a note when allowed")
    func engineOtherLineAllowed() {
        #expect(PrefixRecipe.engineDecision(recipeEngine: "x64-sikarugir10.0_6-r5", running: "x64-crossover26.3-r25", otherEngines: true)
            == .applyWithNote(verifiedOn: "x64-sikarugir10.0_6-r5"))
    }

    @Test("Another line is skipped when not allowed")
    func engineOtherLineSkipped() {
        #expect(PrefixRecipe.engineDecision(recipeEngine: "x64-sikarugir10.0_6-r5", running: "x64-crossover26.3-r25", otherEngines: false)
            == .skip(verifiedOn: "x64-sikarugir10.0_6-r5"))
    }

    @Test("No switch file means other engines are allowed")
    func switchMissing() {
        #expect(PrefixRecipe.otherEnginesAllowed(switchValue: nil, launchOption: nil))
    }

    @Test("The switch set to skip turns other engines off")
    func switchSkip() {
        #expect(!PrefixRecipe.otherEnginesAllowed(switchValue: "skip", launchOption: nil))
    }

    @Test("The launch option 0 beats a switch set to apply")
    func launchOptionOff() {
        #expect(!PrefixRecipe.otherEnginesAllowed(switchValue: "apply", launchOption: "0"))
    }

    @Test("The launch option 1 beats a switch set to skip")
    func launchOptionOn() {
        #expect(PrefixRecipe.otherEnginesAllowed(switchValue: "skip", launchOption: "1"))
    }

    @Test("A launch option that is neither 0 nor 1 is ignored")
    func launchOptionOther() {
        #expect(!PrefixRecipe.otherEnginesAllowed(switchValue: "skip", launchOption: "yes"))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: compile error.

- [ ] **Step 3: Write the implementation** (add to `PrefixRecipe`)

```swift
    public enum EngineDecision: Equatable, Sendable {
        case apply
        case applyWithNote(verifiedOn: String)
        case skip(verifiedOn: String)
    }

    // "x64-crossover26.3-r25" -> "x64-crossover26.3": revisions of one line are cumulative
    public static func engineLine(of id: String) -> String {
        guard let range = id.range(of: "-r[0-9]+$", options: .regularExpression) else { return id }
        return String(id[..<range.lowerBound])
    }

    // A recipe verified on another Wine line still usually works; the user decides whether to
    // trust it, by the switch or per game
    public static func engineDecision(recipeEngine: String?, running: String, otherEngines: Bool) -> EngineDecision {
        guard let recipeEngine, engineLine(of: recipeEngine) != engineLine(of: running) else { return .apply }
        return otherEngines ? .applyWithNote(verifiedOn: recipeEngine) : .skip(verifiedOn: recipeEngine)
    }

    // The switch file holds "apply" or "skip" (missing is apply); the game's launch option
    // PROTONISH_RECIPE_OTHER_ENGINES=0|1 wins
    public static func otherEnginesAllowed(switchValue: String?, launchOption: String?) -> Bool {
        switch launchOption {
        case "0": false
        case "1": true
        default: switchValue?.trimmingCharacters(in: .whitespacesAndNewlines) != "skip"
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: 27 tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/git/NotProton && git add app/Sources/HighballEnvCore/PrefixRecipe.swift app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift
git commit -F - <<'EOF'
Decide whether a recipe from another engine line applies

- PrefixRecipe.engineDecision: same line applies, another line applies
  with a note or is skipped by the switch
- PROTONISH_RECIPE_OTHER_ENGINES=0|1 on a game beats the switch

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 4: The marker, once per prefix per database version

**Files:**
- Modify: `app/Sources/HighballEnvCore/PrefixRecipe.swift`
- Modify: `app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift`

**Interfaces:**
- Produces: `PrefixRecipe.record(recipeID:commit:engine:) -> String` (the `# recipe:` payload, space separated), `PrefixRecipe.isApplied(marker: String?, recipeID: String, commit: String, engine: String, copyTargetsPresent: Bool) -> Bool`. The run script writes the marker as three lines from that payload.

- [ ] **Step 1: Write the failing tests** (append inside the suite)

```swift
    @Test("The record names recipe, database commit and engine, space separated")
    func recordText() {
        #expect(PrefixRecipe.record(recipeID: "portal-2", commit: "483aac46", engine: "x64-crossover26.3-r25") == "portal-2 483aac46 x64-crossover26.3-r25")
    }

    @Test("A marker with the same recipe, commit and engine means applied")
    func appliedSame() {
        #expect(PrefixRecipe.isApplied(marker: "portal-2\n483aac46\nx64-crossover26.3-r25\n", recipeID: "portal-2",
                                       commit: "483aac46", engine: "x64-crossover26.3-r25", copyTargetsPresent: true))
    }

    @Test("A newer database applies the recipe again")
    func appliedNewCommit() {
        #expect(!PrefixRecipe.isApplied(marker: "portal-2\n483aac46\nx64-crossover26.3-r25\n", recipeID: "portal-2",
                                        commit: "ffffffff", engine: "x64-crossover26.3-r25", copyTargetsPresent: true))
    }

    @Test("A prefix rebuilt on another engine applies the recipe again")
    func appliedNewEngine() {
        #expect(!PrefixRecipe.isApplied(marker: "portal-2\n483aac46\nx64-crossover26.3-r19\n", recipeID: "portal-2",
                                        commit: "483aac46", engine: "x64-crossover26.3-r25", copyTargetsPresent: true))
    }

    @Test("A missing copied file applies the recipe again, the game was reinstalled")
    func appliedCopyGone() {
        #expect(!PrefixRecipe.isApplied(marker: "csgo-legacy\n483aac46\nx64-crossover26.3-r25\n", recipeID: "csgo-legacy",
                                        commit: "483aac46", engine: "x64-crossover26.3-r25", copyTargetsPresent: false))
    }

    @Test("No marker means not applied")
    func appliedNoMarker() {
        #expect(!PrefixRecipe.isApplied(marker: nil, recipeID: "portal-2", commit: "483aac46", engine: "x64-crossover26.3-r25", copyTargetsPresent: true))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: compile error.

- [ ] **Step 3: Write the implementation** (add to `PrefixRecipe`)

```swift
    // What the run script records after a successful import, as one "# recipe:" line
    public static func record(recipeID: String, commit: String, engine: String) -> String {
        "\(recipeID) \(commit) \(engine)"
    }

    // The marker is the record as three lines. A copy target that went missing counts as not
    // applied, HighballKit's artifactsPresent rule: the game was reinstalled under it.
    public static func isApplied(marker: String?, recipeID: String, commit: String, engine: String, copyTargetsPresent: Bool) -> Bool {
        guard copyTargetsPresent, let marker else { return false }
        let lines = marker.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.count >= 3 && lines[0] == recipeID && lines[1] == commit && lines[2] == engine
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: 33 tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/git/NotProton && git add app/Sources/HighballEnvCore/PrefixRecipe.swift app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift
git commit -F - <<'EOF'
Apply a recipe once per prefix per highball-db version

- PrefixRecipe.record and isApplied: recipe id, database commit and
  engine build make the marker; a missing copy target re-applies

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 5: Apply the steps

**Files:**
- Modify: `app/Sources/HighballEnvCore/PrefixRecipe.swift`
- Modify: `app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4; `HighballKit.RecipeRunner.copySource(engineRoot:_:)`; `Recipe.id`, `Recipe.engine`, `Recipe.steps`.
- Produces:

```swift
public struct Context: Sendable {
    public var driveC: URL          // <prefix>/drive_c
    public var engineRoot: URL      // InstalledEngine.root
    public var engineID: String
    public var dbCommit: String
    public var installPath: URL?
    public var marker: URL?         // $STEAM_COMPAT_DATA_PATH/protonish-recipe
    public var registryFile: URL?   // <prefix>/drive_c/protonish-recipe.reg
    public var otherEngines: Bool
}
public struct Outcome: Equatable, Sendable { public var notes: [String]; public var record: String? }
public static func run(recipe: Recipe, context: Context) -> Outcome
```

`record` is non-nil only when every in-scope step succeeded and the run script should write the marker after importing the `.reg` (if one was written).

- [ ] **Step 1: Write the failing tests** (append inside the suite)

```swift
    struct Fixture {
        let work: URL
        var driveC: URL { work.appending(path: "pfx/drive_c") }
        var engine: URL { work.appending(path: "engine") }
        var install: URL { work.appending(path: "library/steamapps/common/Portal 2") }
        var marker: URL { work.appending(path: "compat/protonish-recipe") }
        var reg: URL { driveC.appending(path: "protonish-recipe.reg") }
        func context(otherEngines: Bool = true, installPath: Bool = true) -> PrefixRecipe.Context {
            .init(driveC: driveC, engineRoot: engine, engineID: "x64-crossover26.3-r25", dbCommit: "483aac46",
                  installPath: installPath ? install : nil, marker: marker, registryFile: reg, otherEngines: otherEngines)
        }
    }

    func fixture() throws -> Fixture {
        let work = FileManager.default.temporaryDirectory.appending(path: "prefix-recipe-\(UUID().uuidString)")
        let f = Fixture(work: work)
        for dir in [f.driveC, f.install, f.marker.deletingLastPathComponent(), f.engine.appending(path: "engine/lib/wine/i386-windows")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var dll = Data(count: 0x60)
        dll.replaceSubrange(0x40..<0x51, with: Data("Wine builtin DLL\0".utf8))
        try dll.write(to: f.engine.appending(path: "engine/lib/wine/i386-windows/d3d9.dll"))
        return f
    }

    let portal2Steps: [[String: Any]] = [
        ["type": "registry", "key": "HKCU\\Software\\Wine\\AppDefaults\\portal2.exe\\Direct3D", "name": "VideoMemorySize", "valueType": "REG_SZ", "data": "2047"],
        ["type": "file", "path": "Program Files (x86)/Steam/steamapps/common/Portal 2/portal2/cfg/autoexec.cfg", "contents": "mat_tonemapping_occlusion_use_stencil 1\n"],
        ["type": "note", "text": "ignored"],
    ]

    @Test("A file step lands in the game's folder")
    func runWritesFile() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        _ = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2"), context: f.context())
        #expect(try String(contentsOf: f.install.appending(path: "portal2/cfg/autoexec.cfg"), encoding: .utf8) == "mat_tonemapping_occlusion_use_stencil 1\n")
    }

    @Test("Registry steps become the .reg file in drive C")
    func runWritesRegistry() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        _ = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2"), context: f.context())
        #expect(try String(contentsOf: f.reg, encoding: .utf8).contains("\"VideoMemorySize\"=\"2047\""))
    }

    @Test("The outcome carries the record for the run script")
    func runRecord() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let outcome = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2"), context: f.context())
        #expect(outcome.record == "portal-2 483aac46 x64-crossover26.3-r25")
    }

    @Test("The outcome says what was done")
    func runNotes() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let outcome = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2"), context: f.context())
        #expect(outcome.notes == ["recipe portal-2: 1 registry value, 1 file, 0 copies"])
    }

    @Test("A copy step takes the file from the engine and blanks Wine's builtin marker")
    func runCopyNative() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let steps: [[String: Any]] = [["type": "copy", "from": "engine/lib/wine/i386-windows/d3d9.dll",
                                       "to": "Program Files (x86)/Steam/steamapps/common/Portal 2/bin/d3d9.dll", "asNative": true]]
        _ = PrefixRecipe.run(recipe: try recipe(steps), context: f.context())
        let copied = try Data(contentsOf: f.install.appending(path: "bin/d3d9.dll"))
        #expect(copied[0x40..<0x51] == Data(count: 0x11))
    }

    @Test("A copy source outside the engine is refused and nothing is recorded")
    func runCopyOutside() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let steps: [[String: Any]] = [["type": "copy", "from": "../secret", "to": "x.dll", "asNative": false]]
        let outcome = PrefixRecipe.run(recipe: try recipe(steps), context: f.context())
        #expect(outcome.record == nil)
    }

    @Test("A refused step is noted")
    func runCopyOutsideNote() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let steps: [[String: Any]] = [["type": "copy", "from": "../secret", "to": "x.dll", "asNative": false]]
        let outcome = PrefixRecipe.run(recipe: try recipe(steps), context: f.context())
        #expect(outcome.notes.contains("recipe game: copy ../secret not applied: not a file inside the engine"))
    }

    @Test("A recipe already applied writes nothing")
    func runAlreadyApplied() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        try "portal-2\n483aac46\nx64-crossover26.3-r25\n".write(to: f.marker, atomically: true, encoding: .utf8)
        _ = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2"), context: f.context())
        #expect(!FileManager.default.fileExists(atPath: f.reg.path))
    }

    @Test("A recipe already applied says so and asks for no record")
    func runAlreadyAppliedOutcome() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        try "portal-2\n483aac46\nx64-crossover26.3-r25\n".write(to: f.marker, atomically: true, encoding: .utf8)
        let outcome = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2"), context: f.context())
        #expect(outcome == .init(notes: ["recipe portal-2 already applied (highball-db 483aac46)"], record: nil))
    }

    @Test("A stale .reg from an earlier launch is removed when nothing is to import")
    func runRemovesStaleReg() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        try "stale".write(to: f.reg, atomically: true, encoding: .utf8)
        try "portal-2\n483aac46\nx64-crossover26.3-r25\n".write(to: f.marker, atomically: true, encoding: .utf8)
        _ = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2"), context: f.context())
        #expect(!FileManager.default.fileExists(atPath: f.reg.path))
    }

    @Test("A recipe from another engine line is skipped when the switch is off")
    func runSkippedByEngine() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let outcome = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2", engine: "x64-sikarugir10.0_6-r5"),
                                       context: f.context(otherEngines: false))
        #expect(outcome == .init(notes: ["recipe portal-2 skipped: verified on x64-sikarugir10.0_6-r5, this engine is x64-crossover26.3-r25; turn on Apply game fixes verified on other engines in Proton-ish, or set the launch option PROTONISH_RECIPE_OTHER_ENGINES=1"], record: nil))
    }

    @Test("A recipe from another engine line applies with a note when the switch is on")
    func runOtherEngineNoted() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let outcome = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2", engine: "x64-sikarugir10.0_6-r5"), context: f.context())
        #expect(outcome.notes.first == "recipe portal-2 was verified on x64-sikarugir10.0_6-r5, this engine is x64-crossover26.3-r25; applying anyway")
    }

    @Test("A recipe with only environment steps has nothing to apply and no record")
    func runNoPrefixSteps() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let outcome = PrefixRecipe.run(recipe: try recipe([["type": "environment", "name": "A", "value": "1"]]), context: f.context())
        #expect(outcome == .init(notes: [], record: nil))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: compile error.

- [ ] **Step 3: Write the implementation** (add to `PrefixRecipe`)

```swift
    public struct Context: Sendable {
        public var driveC: URL
        public var engineRoot: URL
        public var engineID: String
        public var dbCommit: String
        public var installPath: URL?
        public var marker: URL?
        public var registryFile: URL?
        public var otherEngines: Bool

        public init(driveC: URL, engineRoot: URL, engineID: String, dbCommit: String, installPath: URL?,
                    marker: URL?, registryFile: URL?, otherEngines: Bool) {
            self.driveC = driveC; self.engineRoot = engineRoot; self.engineID = engineID; self.dbCommit = dbCommit
            self.installPath = installPath; self.marker = marker; self.registryFile = registryFile; self.otherEngines = otherEngines
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var notes: [String] = []
        // The "# recipe:" payload; nil when nothing should be recorded
        public var record: String?
        public init(notes: [String] = [], record: String? = nil) { self.notes = notes; self.record = record }
    }

    public static func run(recipe: Recipe, context: Context) -> Outcome {
        let steps = recipe.steps.filter(isPrefixStep)
        guard !steps.isEmpty else { return Outcome() }
        var outcome = Outcome()
        switch engineDecision(recipeEngine: recipe.engine, running: context.engineID, otherEngines: context.otherEngines) {
        case .skip(let verifiedOn):
            removeRegistryFile(context)
            outcome.notes.append("recipe \(recipe.id) skipped: verified on \(verifiedOn), this engine is \(context.engineID); turn on Apply game fixes verified on other engines in Proton-ish, or set the launch option PROTONISH_RECIPE_OTHER_ENGINES=1")
            return outcome
        case .applyWithNote(let verifiedOn):
            outcome.notes.append("recipe \(recipe.id) was verified on \(verifiedOn), this engine is \(context.engineID); applying anyway")
        case .apply:
            break
        }
        let marker = context.marker.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        if isApplied(marker: marker, recipeID: recipe.id, commit: context.dbCommit, engine: context.engineID,
                     copyTargetsPresent: copyTargetsPresent(steps, context)) {
            removeRegistryFile(context)
            outcome.notes.append("recipe \(recipe.id) already applied (highball-db \(context.dbCommit.prefix(8)))")
            return outcome
        }
        var failed = false
        let counts = apply(steps, recipe: recipe, context: context, notes: &outcome.notes, failed: &failed)
        outcome.notes.append("recipe \(recipe.id): \(counts.registry) registry value\(counts.registry == 1 ? "" : "s"), \(counts.files) file\(counts.files == 1 ? "" : "s"), \(counts.copies) cop\(counts.copies == 1 ? "y" : "ies")")
        if !failed { outcome.record = record(recipeID: recipe.id, commit: context.dbCommit, engine: context.engineID) }
        return outcome
    }

    static func isPrefixStep(_ step: Recipe.Step) -> Bool {
        switch step {
        case .registry, .file, .copy: true
        default: false
        }
    }

    private static func copyTargetsPresent(_ steps: [Recipe.Step], _ context: Context) -> Bool {
        steps.allSatisfy { step in
            guard case let .copy(_, to, _) = step, let url = target(of: to, driveC: context.driveC, installPath: context.installPath) else { return true }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    private static func removeRegistryFile(_ context: Context) {
        if let file = context.registryFile { try? FileManager.default.removeItem(at: file) }
    }

    private static func apply(_ steps: [Recipe.Step], recipe: Recipe, context: Context, notes: inout [String], failed: inout Bool)
        -> (registry: Int, files: Int, copies: Int) {
        var counts = (registry: 0, files: 0, copies: 0)
        let registry = registryText(steps)
        notes += registry.notes
        removeRegistryFile(context)
        if let text = registry.text, let file = context.registryFile {
            do {
                try text.write(to: file, atomically: true, encoding: .utf8)
                counts.registry = steps.filter { if case .registry = $0 { true } else { false } }.count - registry.notes.count
            } catch {
                failed = true
                notes.append("recipe \(recipe.id): registry file not written: \(error.localizedDescription)")
            }
        }
        for step in steps {
            switch step {
            case let .file(path, contents):
                guard let url = target(of: path, driveC: context.driveC, installPath: context.installPath) else {
                    failed = true; notes.append("recipe \(recipe.id): file \(path) not applied: path refused"); continue
                }
                do {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try contents.write(to: url, atomically: true, encoding: .utf8)
                    counts.files += 1
                } catch {
                    failed = true; notes.append("recipe \(recipe.id): file \(path) not written: \(error.localizedDescription)")
                }
            case let .copy(from, to, asNative):
                guard let source = RecipeRunner.copySource(engineRoot: context.engineRoot, from) else {
                    failed = true; notes.append("recipe \(recipe.id): copy \(from) not applied: not a file inside the engine"); continue
                }
                guard let dest = target(of: to, driveC: context.driveC, installPath: context.installPath) else {
                    failed = true; notes.append("recipe \(recipe.id): copy to \(to) not applied: path refused"); continue
                }
                do {
                    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    var data = try Data(contentsOf: source)
                    if asNative { data = withoutBuiltinMarker(data) }
                    try data.write(to: dest, options: .atomic)
                    counts.copies += 1
                } catch {
                    failed = true; notes.append("recipe \(recipe.id): copy \(from) not written: \(error.localizedDescription)")
                }
            default:
                break
            }
        }
        return counts
    }

    // Wine stamps its builtin DLLs with "Wine builtin DLL" at 0x40; blank, the loader treats
    // the file as native (HighballKit's RecipeRunner.withoutBuiltinMarker, not public)
    static func withoutBuiltinMarker(_ data: Data) -> Data {
        let marker = Data("Wine builtin DLL\0".utf8)
        guard data.count >= 0x40 + marker.count, data[0x40..<0x40 + marker.count] == marker else { return data }
        var out = data
        out.replaceSubrange(0x40..<0x40 + marker.count, with: Data(count: marker.count))
        return out
    }
```

`run` and `apply` are each over the 30-line guideline; `apply` is one switch over step kinds and `run` is the decision ladder. If the reviewer objects, split `apply` into `applyFile` and `applyCopy` returning `Bool` success, nothing else changes.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter PrefixRecipeTests 2>&1 | tail -5`
Expected: 46 tests pass. The `registry` count test (`runNotes`) expects `1 registry value`; the count formula is "registry steps minus notes the registry writer produced".

- [ ] **Step 5: Commit**

```bash
cd ~/git/NotProton && git add app/Sources/HighballEnvCore/PrefixRecipe.swift app/Tests/HighballEnvCoreTests/PrefixRecipeTests.swift
git commit -F - <<'EOF'
Apply a recipe's file, copy and registry steps to a Steam prefix

- PrefixRecipe.run writes files and engine copies (builtin marker
  blanked for asNative), the .reg file for the run script, and returns
  the record to write after the import
- Skips a recipe the marker already names, or one from another engine
  line when the switch is off

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 6: `highball-env` plans the prefix steps

**Files:**
- Modify: `app/Sources/HighballEnvCore/GameTuning.swift:49-50`
- Modify: `app/Sources/HighballEnvCore/LaunchEnvironment.swift`
- Modify: `app/Sources/highball-env/main.swift`
- Modify: `app/Tests/HighballEnvCoreTests/LaunchEnvironmentTests.swift`
- Check: `app/Tests/HighballEnvCoreTests/GameTuningTests.swift` for a test expecting "not applied yet" on registry/file/copy

**Interfaces:**
- Consumes: `PrefixRecipe.run(recipe:context:)`, `PrefixRecipe.otherEnginesAllowed(switchValue:launchOption:)`, `InstalledEngine.root`, `GameData.commit`, `GameData.recipe(for:)`.
- Produces: `LaunchEnvironment.Request` gains `installPath: URL?`, `recipeMarker: URL?`, `registryFile: URL?`, `otherEngines: Bool` (defaults nil/nil/nil/true). Output gains a `# recipe: <id> <commit> <engine>` line, first, when there is a record. New helper options: `--install-path <dir>`, `--applied <file>`, `--reg <file>`, `--other-engines apply|skip`.

- [ ] **Step 1: Write the failing test** (append to `LaunchEnvironmentTests`; reuse its `install(renderers:)` helper)

```swift
    private func gameData(recipeSteps: [[String: Any]]) throws -> GameData {
        let json: [String: Any] = [
            "source": ["commit": "483aac46"],
            "games": [["id": "portal-2", "title": "Portal 2", "steam_appid": 620, "status": "community"]],
            "recipes": [["id": "portal-2", "kind": "game", "title": "Portal 2", "steps": recipeSteps]],
        ]
        return try GameData(json: JSONSerialization.data(withJSONObject: json))
    }

    @Test("The prefix steps of the game's recipe are planned and announced")
    func prefixRecipe() throws {
        let install = try install(renderers: ["dxmt"])
        defer { try? FileManager.default.removeItem(at: install.home.deletingLastPathComponent()) }
        let work = install.home.deletingLastPathComponent()
        let gameFolder = work.appending(path: "library/steamapps/common/Portal 2")
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        let data = try gameData(recipeSteps: [
            ["type": "registry", "key": "HKCU\\Software\\Wine\\AppDefaults\\portal2.exe\\Direct3D", "name": "VideoMemorySize", "valueType": "REG_SZ", "data": "2047"],
            ["type": "file", "path": "Program Files (x86)/Steam/steamapps/common/Portal 2/portal2/cfg/autoexec.cfg", "contents": "x\n"],
        ])
        let reg = install.prefix.appending(path: "drive_c/protonish-recipe.reg")
        let lines = LaunchEnvironment.lines(for: .init(
            prefix: install.prefix, engineID: Self.engineID, appID: 620, environment: [:], gameData: data,
            paths: HighballPaths(home: install.home), installPath: gameFolder,
            recipeMarker: work.appending(path: "protonish-recipe"), registryFile: reg, otherEngines: true))
        #expect(lines.first == "# recipe: portal-2 483aac46 \(Self.engineID)")
        #expect(FileManager.default.fileExists(atPath: gameFolder.appending(path: "portal2/cfg/autoexec.cfg").path))
        #expect(FileManager.default.fileExists(atPath: reg.path))
    }
```

`HighballPaths(home:)` is the construction the suite's existing `run(_:_:)` helper uses (`LaunchEnvironmentTests.swift:41`).

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter LaunchEnvironmentTests 2>&1 | tail -5`
Expected: compile error, `Request` has no `installPath`.

- [ ] **Step 3: Extend `LaunchEnvironment.Request` and `lines(for:)`**

In `Request`, after `paths`:

```swift
        public var installPath: URL?
        public var recipeMarker: URL?
        public var registryFile: URL?
        public var otherEngines: Bool
```

Extend `init` with `installPath: URL? = nil, recipeMarker: URL? = nil, registryFile: URL? = nil, otherEngines: Bool = true` and assign them.

In `lines(for:)`, inside the `if let appID …, let entry …` block, after `gameEnvironment = tuning.environment`:

```swift
                if let recipe = request.gameData?.recipe(for: entry) {
                    let outcome = PrefixRecipe.run(recipe: recipe, context: .init(
                        driveC: request.prefix.appending(path: "drive_c"), engineRoot: engine.root, engineID: request.engineID,
                        dbCommit: request.gameData?.commit ?? "", installPath: request.installPath, marker: request.recipeMarker,
                        registryFile: request.registryFile, otherEngines: request.otherEngines))
                    notes += outcome.notes
                    record = outcome.record
                }
```

Declare `var record: String?` next to `var notes`. At the end replace the `return HighballEnvironment.lines(...)` with:

```swift
            var output = HighballEnvironment.lines(highball: highball, user: request.environment, notes: notes)
            if let record { output.insert("# recipe: " + record, at: 0) }
            return output
```

- [ ] **Step 4: Stop the "not applied yet" note for the steps M2c handles**

In `GameTuning.apply`, change

```swift
            case .installer, .registry, .winetricks, .winver, .file, .copy:
                result.notes.append("highball-db step not applied yet: \(name(of: step))")
```

to

```swift
            case .registry, .file, .copy:
                break  // PrefixRecipe applies these to the prefix
            case .installer, .winetricks, .winver:
                result.notes.append("highball-db step not applied yet: \(name(of: step))")
```

Run `grep -n 'not applied yet' app/Tests/HighballEnvCoreTests/*.swift`; if a test asserts the note for `registry`, `file` or `copy`, change that test to use a `winetricks` step (`["type": "winetricks", "verbs": ["dotnet48"]]`) so it keeps pinning the remaining note.

- [ ] **Step 5: Parse the new options in `main.swift`**

After `let request = LaunchEnvironment.Request(` construction, replace it with:

```swift
let launchOption = ProcessInfo.processInfo.environment["PROTONISH_RECIPE_OTHER_ENGINES"]
let request = LaunchEnvironment.Request(
    prefix: URL(fileURLWithPath: prefix), engineID: engine, appID: options["appid"].flatMap(Int.init),
    environment: ProcessInfo.processInfo.environment, gameData: gameData,
    exe: options["exe"].map { URL(fileURLWithPath: $0) },
    installPath: options["install-path"].map { URL(fileURLWithPath: $0) },
    recipeMarker: options["applied"].map { URL(fileURLWithPath: $0) },
    registryFile: options["reg"].map { URL(fileURLWithPath: $0) },
    otherEngines: PrefixRecipe.otherEnginesAllowed(switchValue: options["other-engines"], launchOption: launchOption))
```

Update the usage comment at the top of the file: `[--install-path <game folder>] [--applied <marker>] [--reg <file>] [--other-engines apply|skip]`.

- [ ] **Step 6: Run the HighballEnvCore tests**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter HighballEnvCoreTests 2>&1 | tail -5`
Expected: all pass, including the new `prefixRecipe` test.

- [ ] **Step 7: Build the helper and try it against the real engine and database**

Run:

```bash
cd ~/git/NotProton/app && swift build --product highball-env 2>&1 | tail -2
W=$(mktemp -d); mkdir -p "$W/pfx/drive_c" "$W/Portal 2"
.build/debug/highball-env --prefix "$W/pfx" --engine x64-crossover26.3-r25 --appid 620 \
  --db Sources/NotProtonApp/Resources/payload/highball-db.json --install-path "$W/Portal 2" \
  --applied "$W/marker" --reg "$W/pfx/drive_c/protonish-recipe.reg" --other-engines apply | grep -i 'recipe\|^#' | head
cat "$W/pfx/drive_c/protonish-recipe.reg"; find "$W/Portal 2" -type f
```

Expected: first line `# recipe: portal-2 483aac4628cc7d3209299fe283c506de05c6eb4e x64-crossover26.3-r25`, a note `recipe portal-2: 1 registry value, 2 files, 0 copies`, the `.reg` with `VideoMemorySize`, and `portal2/cfg/autoexec.cfg` plus `portal2/cfg/video.txt` under the fake game folder. Run it a second time with the marker written by hand (`printf 'portal-2\n483aac4628cc7d3209299fe283c506de05c6eb4e\nx64-crossover26.3-r25\n' > "$W/marker"`) and expect the "already applied" note and no `.reg`.

- [ ] **Step 8: Commit**

```bash
cd ~/git/NotProton && git add app/Sources/HighballEnvCore/GameTuning.swift app/Sources/HighballEnvCore/LaunchEnvironment.swift app/Sources/highball-env/main.swift app/Tests/HighballEnvCoreTests/LaunchEnvironmentTests.swift app/Tests/HighballEnvCoreTests/GameTuningTests.swift
git commit -F - <<'EOF'
highball-env plans a game's prefix recipe

- --install-path, --applied, --reg and --other-engines feed
  PrefixRecipe.run; the first output line is "# recipe:" when the run
  script should record the marker
- GameTuning no longer notes registry, file and copy as unapplied

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

(Drop `GameTuningTests.swift` from the `git add` if Step 4 did not touch it.)

---

### Task 7: The run script imports the registry file and records the marker

**Files:**
- Modify: `dylib/feats/compat_run.sh:1150-1217` (`highball_environment`), `:1274` (call site)
- Modify: `dylib/tests/envcheck.sh:118-196`

**Interfaces:**
- Consumes: the helper's `# recipe: <id> <commit> <engine>` line, the `.reg` at `$WINEPREFIX/drive_c/protonish-recipe.reg`, the switch file `$np_support/recipe-other-engines`.
- Produces: `apply_prefix_recipe` (shell function), marker `$STEAM_COMPAT_DATA_PATH/protonish-recipe`, log lines `recipe: …`, variable `np_hb_recipe`.

- [ ] **Step 1: Write the failing shell tests**

In `dylib/tests/envcheck.sh`, change the existing argument assertion (around line 159) to the new argument list:

```sh
is "the helper gets the prefix, engine, app id, database and recipe paths" \
  "args: --prefix $WINEPREFIX --engine x64-crossover26.3-r19 --appid 1086940 --db $np_support/highball-db.json --applied $STEAM_COMPAT_DATA_PATH/protonish-recipe --reg $WINEPREFIX/drive_c/protonish-recipe.reg --other-engines apply" \
  "$(grep '^args:' "$log")"
```

(`STEAM_COMPAT_INSTALL_PATH` is unset in that block, so no `--install-path`.) Then append, before the `unset -v GST_PLUGIN_PATH …` line, a new block:

```sh
echo "== Prefix recipe (apply_prefix_recipe) =="
hb_apply_fn=$(sed -n '/^apply_prefix_recipe() {$/,/^} # apply_prefix_recipe$/p' "$SRC")
[ -n "$hb_apply_fn" ] || { echo "FAIL: apply_prefix_recipe not found"; exit 1; }
eval "$hb_apply_fn"
mkdir -p "$WINEPREFIX/drive_c"
hb_marker="$STEAM_COMPAT_DATA_PATH/protonish-recipe"
hb_reg="$WINEPREFIX/drive_c/protonish-recipe.reg"
fake_wine() { printf '#!/bin/sh\necho "wine: $*" >> "%s"\nexit %s\n' "$log" "$1" > "$hb/wine"; chmod +x "$hb/wine"; }
WINELOADER="$hb/wine"
reset_recipe() { reset_hb; np_hb_recipe=""; rm -f "$hb_marker" "$hb_reg"; }

reset_recipe
STEAM_COMPAT_INSTALL_PATH="$hb/Portal 2"; mkdir -p "$STEAM_COMPAT_INSTALL_PATH"
helper 'echo "args: $*" >&2; echo "# recipe: portal-2 483aac46 x64-crossover26.3-r19"; echo "# note: recipe portal-2: 1 registry value, 1 file, 0 copies"; echo "GST_PLUGIN_PATH=/HB/gst"'
highball_environment
is "the game folder is passed as the install path" "1" "$(grep -c -- "--install-path $hb/Portal 2 " "$log")"
is "the recipe line is kept for the import" "portal-2 483aac46 x64-crossover26.3-r19" "$np_hb_recipe"
is "the recipe line is not exported" "" "${recipe:-}"
unset -v STEAM_COMPAT_INSTALL_PATH

printf 'Windows Registry Editor Version 5.00\r\n' > "$hb_reg"
fake_wine 0
apply_prefix_recipe
is "the registry file is imported through C:" "1" "$(grep -c 'wine: reg import C:\\protonish-recipe.reg' "$log")"
is "the marker holds recipe, commit and engine" "portal-2 483aac46 x64-crossover26.3-r19" "$(tr '\n' ' ' < "$hb_marker" | sed 's/ $//')"
is "the registry file is removed after the import" "no" "$([ -e "$hb_reg" ] && echo yes || echo no)"

reset_recipe
np_hb_recipe="portal-2 483aac46 x64-crossover26.3-r19"
printf 'Windows Registry Editor Version 5.00\r\n' > "$hb_reg"
fake_wine 1
apply_prefix_recipe
is "a failed import writes no marker" "no" "$([ -e "$hb_marker" ] && echo yes || echo no)"
is "a failed import is logged" "1" "$(grep -c 'recipe: registry import exited status=1' "$log")"

reset_recipe
np_hb_recipe="warframe 483aac46 x64-crossover26.3-r19"
fake_wine 0
apply_prefix_recipe
is "a recipe without registry values still gets its marker" "warframe" "$(head -1 "$hb_marker")"
is "nothing is imported without a registry file" "0" "$(grep -c 'wine: reg import' "$log")"

reset_recipe
printf 'stale\r\n' > "$hb_reg"
fake_wine 0
apply_prefix_recipe
is "a stale registry file is removed when no recipe applies" "no" "$([ -e "$hb_reg" ] && echo yes || echo no)"
is "a stale registry file is never imported" "0" "$(grep -c 'wine: reg import' "$log")"

reset_recipe
printf 'skip\n' > "$np_support/recipe-other-engines"
helper 'echo "args: $*" >&2'
highball_environment
is "the switch file reaches the helper" "1" "$(grep -c -- '--other-engines skip' "$log")"
rm -f "$np_support/recipe-other-engines"
```

- [ ] **Step 2: Run the shell tests to verify they fail**

Run: `cd ~/git/NotProton && make envcheck 2>&1 | grep -c FAIL`
Expected: a non-zero count (argument assertion, `apply_prefix_recipe not found` exits early; that is the failure).

- [ ] **Step 3: Pass the new options in `highball_environment`**

Replace the two `set --` lines in `highball_environment` with:

```sh
  # The game's executable lets Highball spot a DirectX 12-only program; the install path, marker
  # and registry file are for the prefix steps of the game's recipe
  hb_other=apply
  [ "$(tr -d ' \t\n' < "$np_support/recipe-other-engines" 2>/dev/null)" = skip ] && hb_other=skip
  set -- --prefix "$WINEPREFIX" --engine "$np_build" --appid "${app_id:-0}" --db "$np_support/highball-db.json"
  [ -z "$hb_exe" ] || [ ! -f "$hb_exe" ] || set -- "$@" --exe "$hb_exe"
  [ -z "${STEAM_COMPAT_INSTALL_PATH:-}" ] || [ ! -d "$STEAM_COMPAT_INSTALL_PATH" ] \
    || set -- "$@" --install-path "$STEAM_COMPAT_INSTALL_PATH"
  set -- "$@" --applied "$STEAM_COMPAT_DATA_PATH/protonish-recipe" \
    --reg "$WINEPREFIX/drive_c/protonish-recipe.reg" --other-engines "$hb_other"
```

In the first `while IFS= read -r hb_line` loop, add a case **before** the `'#'*` case:

```sh
      '# recipe: '*)
        np_hb_recipe=${hb_line#'# recipe: '}
        # Three safe words, or nothing: a recipe id, a commit hash and an engine id
        case "$np_hb_recipe" in
          *[!A-Za-z0-9._\ -]*|*' '*' '*' '*) np_hb_recipe="" ;;
        esac
        continue ;;
```

Add `np_hb_recipe=""` next to `np_hb_env_file=""` above the function.

- [ ] **Step 4: Add `apply_prefix_recipe` and call it**

Directly after `} # highball_environment`:

```sh
# Highball: the prefix steps of the game's highball-db recipe. highball-env wrote the files and
# engine copies itself and the registry values as C:\protonish-recipe.reg; the import runs here,
# under the game's own environment. The marker makes the next launch skip the recipe.
apply_prefix_recipe() {
  hb_reg="$WINEPREFIX/drive_c/protonish-recipe.reg"
  hb_marker="$STEAM_COMPAT_DATA_PATH/protonish-recipe"
  if [ -z "$np_hb_recipe" ]; then
    rm -f "$hb_reg"
    return 0
  fi
  hb_status=0
  if [ -f "$hb_reg" ]; then
    without_lock_fds "$WINELOADER" reg import 'C:\protonish-recipe.reg' >> "$log" 2>&1 || hb_status=$?
    rm -f "$hb_reg"
  fi
  if [ "$hb_status" -ne 0 ]; then
    echo "recipe: registry import exited status=$hb_status, tried again at the next launch" >> "$log" 2>&1 || true
    return 0
  fi
  # shellcheck disable=SC2086 # the three words become three lines
  printf '%s\n' $np_hb_recipe > "$hb_marker" 2>/dev/null \
    && echo "recipe: $np_hb_recipe recorded" >> "$log" 2>&1 || true
} # apply_prefix_recipe
```

At the call site (`:1274`):

```sh
  if [ "$np_runtime" = highball ]; then
    stage_step="highball environment"
    highball_environment "$1"
    stage_step="prefix recipe"
    apply_prefix_recipe
  fi
```

- [ ] **Step 5: Run the shell tests and the linter**

Run: `cd ~/git/NotProton && make envcheck runcheck 2>&1 | tail -8`
Expected: no `FAIL` lines, `runcheck: the run script lints and parses clean`. If shellcheck complains about the `'# recipe: '*)` pattern, quote it as `"# recipe: "*)`.

- [ ] **Step 6: Commit**

```bash
cd ~/git/NotProton && git add dylib/feats/compat_run.sh dylib/tests/envcheck.sh
git commit -F - <<'EOF'
Import the recipe's registry file and record the marker at launch

- highball_environment passes the game folder, marker, registry file
  and the other-engines switch; "# recipe:" is kept, not exported
- apply_prefix_recipe imports C:\protonish-recipe.reg under the game's
  environment and writes protonish-recipe only when that succeeded

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 8: The switch in the Status screen

**Files:**
- Create: `app/Sources/NotProtonApp/Model/OtherEngineFixes.swift`
- Create: `app/Tests/NotProtonAppTests/OtherEngineFixesTests.swift`
- Modify: `app/Sources/NotProtonApp/SystemStatus.swift:16-62` (snapshot), `:475-487` (next to `setDefaultTool`)
- Modify: `app/Sources/NotProtonApp/Views/StatusView.swift:637-663`
- Modify: `app/Sources/NotProtonApp/Resources/Localization/Localizable.xcstrings`

**Interfaces:**
- Produces: `OtherEngineFixes.file`, `OtherEngineFixes.isOn(at:) -> Bool`, `OtherEngineFixes.set(_:at:) throws`, `StatusSnapshot.otherEngineFixes: Bool`, `SystemStatus.setOtherEngineFixes(on:) async`.
- File content: `apply` or `skip` plus newline; the run script reads it (Task 7).

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import NotProtonApp

@Suite("Game fixes verified on other engines")
struct OtherEngineFixesTests {

    @Test("Without the file the switch is on")
    func missingFileIsOn() throws {
        let work = try scratchDirectory("other-engine-fixes")
        defer { try? FileManager.default.removeItem(at: work) }
        #expect(OtherEngineFixes.isOn(at: work.appending(path: "recipe-other-engines")))
    }

    @Test("Turning the switch off writes skip")
    func offWritesSkip() throws {
        let work = try scratchDirectory("other-engine-fixes")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "recipe-other-engines")
        try OtherEngineFixes.set(false, at: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "skip\n")
    }

    @Test("A file saying skip reads as off")
    func skipReadsOff() throws {
        let work = try scratchDirectory("other-engine-fixes")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "recipe-other-engines")
        try OtherEngineFixes.set(false, at: file)
        #expect(!OtherEngineFixes.isOn(at: file))
    }

    @Test("Turning the switch back on reads as on")
    func onReadsOn() throws {
        let work = try scratchDirectory("other-engine-fixes")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "recipe-other-engines")
        try OtherEngineFixes.set(false, at: file)
        try OtherEngineFixes.set(true, at: file)
        #expect(OtherEngineFixes.isOn(at: file))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter OtherEngineFixesTests 2>&1 | tail -5`
Expected: compile error.

- [ ] **Step 3: Write the model**

```swift
// Whether highball-db recipes verified on another Wine line apply to a Steam prefix. The run
// script passes the file's word to highball-env; one game can override it with the Steam launch
// option PROTONISH_RECIPE_OTHER_ENGINES=0 or 1.

import Foundation

enum OtherEngineFixes {
    static let step = String(localized: "Game fixes from other engines")

    static var file: URL { SupportPaths.support.appending(path: "recipe-other-engines") }

    // Missing file: on. Only the word "skip" turns it off, so a damaged file fails open.
    static func isOn(at url: URL = file) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return true }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) != "skip"
    }

    static func set(_ on: Bool, at url: URL = file) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(((on ? "apply" : "skip") + "\n").utf8).write(to: url, options: .atomic)
        } catch {
            throw StepFailure(step: step, detail: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/git/NotProton/app && swift test --no-parallel --filter OtherEngineFixesTests 2>&1 | tail -5`
Expected: 4 tests pass.

- [ ] **Step 5: Snapshot, action and row**

`SystemStatus.swift`, in `StatusSnapshot` after `steamLiveDefaultTool`:

```swift
    var otherEngineFixes: Bool = true
```

and in `capture`, after the `steamLiveDefaultTool:` argument:

```swift
            otherEngineFixes: OtherEngineFixes.isOn()
```

After `setDefaultTool(on:)`:

```swift
    func setOtherEngineFixes(on wanted: Bool) async {
        await perform(from: OtherEngineFixes.step) { _ in
            try OtherEngineFixes.set(wanted)
            return wanted
                ? String(localized: "Game fixes verified on other engines apply from the next game launch.")
                : String(localized: "Only game fixes verified on this engine apply from the next game launch.")
        }
    }
```

`StatusView.swift`, in `highballSection` change

```swift
        if snapshot.installedRunners.contains(where: { $0.runtime == .highball }) {
            defaultToolRow(snapshot)
        }
```

to

```swift
        if snapshot.installedRunners.contains(where: { $0.runtime == .highball }) {
            defaultToolRow(snapshot)
            otherEngineFixesRow(snapshot)
        }
```

and after `defaultToolRow` add:

```swift
    private func otherEngineFixesRow(_ snapshot: StatusSnapshot) -> some View {
        StatusRow(
            title: String(localized: "Apply game fixes verified on other engines"),
            value: snapshot.otherEngineFixes
                ? String(localized: "Fixes highball-db verified on another Wine engine apply too. One game can opt out with the launch option PROTONISH_RECIPE_OTHER_ENGINES=0.")
                : String(localized: "Only fixes verified on this Wine engine apply. One game can opt in with the launch option PROTONISH_RECIPE_OTHER_ENGINES=1."),
            toggle: Binding(
                get: { snapshot.otherEngineFixes },
                set: { wanted in Task { await status.setOtherEngineFixes(on: wanted) } }
            )
        )
        .disabled(!status.isIdle)
    }
```

- [ ] **Step 6: Catalog strings**

Write `catalog-m2c.py` in the scratchpad on the pattern of `catalog-guidance.py` and run it against `Localizable.xcstrings`:

```python
import json, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    cat = json.load(f)
strings = cat["strings"]

def add(key, zh):
    assert key not in strings, key
    strings[key] = {"localizations": {"zh-Hans": {"stringUnit": {"state": "translated", "value": zh}}}}

add("Game fixes from other engines", "来自其他引擎的游戏修复")
add("Apply game fixes verified on other engines", "应用在其他引擎上验证过的游戏修复")
add("Fixes highball-db verified on another Wine engine apply too. One game can opt out with the launch option PROTONISH_RECIPE_OTHER_ENGINES=0.",
    "highball-db 在其他 Wine 引擎上验证过的修复也会应用。单个游戏可用启动选项 PROTONISH_RECIPE_OTHER_ENGINES=0 退出。")
add("Only fixes verified on this Wine engine apply. One game can opt in with the launch option PROTONISH_RECIPE_OTHER_ENGINES=1.",
    "仅应用在此 Wine 引擎上验证过的修复。单个游戏可用启动选项 PROTONISH_RECIPE_OTHER_ENGINES=1 启用。")
add("Game fixes verified on other engines apply from the next game launch.", "从下次启动游戏起，将应用在其他引擎上验证过的游戏修复。")
add("Only game fixes verified on this engine apply from the next game launch.", "从下次启动游戏起，仅应用在此引擎上验证过的游戏修复。")

text = json.dumps(cat, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
print(len(strings))
```

Run: `python3 -I <scratchpad>/catalog-m2c.py app/Sources/NotProtonApp/Resources/Localization/Localizable.xcstrings && make l10ncheck 2>&1 | tail -3`
Expected: 497 strings, `l10ncheck` passes.

- [ ] **Step 7: Build and run the full app tests**

Run: `cd ~/git/NotProton && make -s app-tests 2>&1 | tail -5`
Expected: all suites pass (601 app tests before this milestone plus the new ones; HighballEnvCore 41 plus the new ones).

- [ ] **Step 8: Look at it**

Run `bash ~/.claude/skills/runapp/run.sh` (10-minute timeout), then capture the window (`swift $S/wid.swift` → `screencapture -x -l <id>`) and check the new row sits under "Use Highball for all Windows games", reads "Apply game fixes verified on other engines", is on, and its footer names the launch option. Toggle it off and confirm `~/Library/Application Support/protonish/recipe-other-engines` reads `skip`; toggle it back on.

- [ ] **Step 9: Commit**

```bash
cd ~/git/NotProton && git add app/Sources/NotProtonApp/Model/OtherEngineFixes.swift app/Tests/NotProtonAppTests/OtherEngineFixesTests.swift app/Sources/NotProtonApp/SystemStatus.swift app/Sources/NotProtonApp/Views/StatusView.swift app/Sources/NotProtonApp/Resources/Localization/Localizable.xcstrings
git commit -F - <<'EOF'
Switch for game fixes verified on other engines

- OtherEngineFixes writes apply or skip to recipe-other-engines; the
  Status screen's Highball section gets the switch, default on
- The footer names the per-game launch option
  PROTONISH_RECIPE_OTHER_ENGINES

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 9: Docs, spec, full check, manual test

**Files:**
- Modify: `README.md:102-103` (Using Highball bullets), `README.md` changelog (last dated line is 2026-10-19)
- Modify: `.claude/TODO.md` (M2c lines)
- Modify: `docs/superpowers/specs/2026-10-14-protonish-highball-design.md` (the `.reg` path)

- [ ] **Step 1: README**

Replace the two lines

```
- Per-game fixes from highball-db that only set variables, DLL overrides or DXVK options apply automatically.
  Fixes that change the Windows prefix (registry, winetricks) are not applied yet.
```

with

```
- Per-game fixes from highball-db apply automatically: variables, DLL overrides and DXVK options at every launch;
  registry values, config files and engine DLLs once per prefix per database version, before the first launch
  (Portal 2's `autoexec.cfg`, Warframe's launcher override). A fix is never undone when a later database drops it;
  rebuild the prefix for a clean slate. Installers and winetricks steps (`.NET` for Assetto Corsa) are not applied yet.
- **Fixes verified on another engine.** highball-db says which Wine engine a fix was checked on. By default a fix
  checked on another engine line still applies, and `protonish-run.log` says so. The switch **Apply game fixes verified
  on other engines** in the Status screen turns that off; one game can override the switch with the Steam launch option
  `PROTONISH_RECIPE_OTHER_ENGINES=0` or `=1`.
```

Add to `## Changes from upstream`, after the last 2026-10-19 line:

```
- 2026-10-19: highball-db fixes that change the Windows prefix (registry values, config files, engine DLLs) apply once per prefix per database version, written by `highball-env` and imported by the run script before the launch. Fixes verified on another engine line apply by default; the Status screen switch and the launch option `PROTONISH_RECIPE_OTHER_ENGINES` decide.
```

- [ ] **Step 2: TODO**

In `.claude/TODO.md` change

```
  - M2c: apply highball-db recipe steps that change the prefix (registry, winetricks, winver, copy, file, installer)
```

to

```
  - [x] M2c: apply highball-db recipe steps that change the prefix: registry, file, copy (completed: 2026-10-19); winetricks, winver, installer stay unapplied
```

and `prefix steps in M2c` on the import line to `prefix steps in M2c (completed: 2026-10-19)`.

- [ ] **Step 3: Spec**

In §4.7's M2c bullet replace `` `$STEAM_COMPAT_DATA_PATH/protonish-recipe.reg` `` with `` `$WINEPREFIX/drive_c/protonish-recipe.reg`, imported as `C:\protonish-recipe.reg` `` and append to that sentence: "(amended 2026-10-19 during implementation: inside `drive_c`, so the import does not depend on the `Z:` drive)".

- [ ] **Step 4: Brand and lint checks**

Run: `cd ~/git/NotProton && make brandcheck scriptcheck runcheck l10ncheck 2>&1 | tail -6`
Expected: all clean.

- [ ] **Step 5: Commit**

```bash
cd ~/git/NotProton && git add README.md .claude/TODO.md docs/superpowers/specs/2026-10-14-protonish-highball-design.md
git commit -F - <<'EOF'
Document prefix recipes and the other-engines switch

- README: which highball-db fixes apply when, the switch and the
  launch option; dated changelog line
- TODO: M2c done; spec: the .reg file lives in drive_c

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Full check**

Run the scratchpad `fullcheck.sh` in the background (`sh <scratchpad>/fullcheck.sh > <scratchpad>/fullcheck-m2c.log 2>&1`, about 15 minutes; do not edit the tree or switch branches while it runs; it rebuilds `out/Proton-ish.app` and kills the app open from there). Expected last line `FULLCHECK EXIT 0`.

- [ ] **Step 7: Manual test, Portal 2 and Warframe** (the user runs the games; the executor checks the files)

1. `bash ~/.claude/skills/runapp/run.sh --no-build`, Install (so the new `run` and `highball-env` reach `~/Library/Application Support/protonish/`), then the user launches **Portal 2** through Steam with Highball Wine 11 (r25).
2. Check:

```bash
D="$HOME/Library/Application Support/Steam/steamapps/compatdata/620"
cat "$D/protonish-recipe"
grep -n 'recipe' "$D/protonish-run.log" | tail -5
grep -c 'VideoMemorySize' "$D/pfx/user.reg"
cat "$HOME/Library/Application Support/Steam/steamapps/common/Portal 2/portal2/cfg/autoexec.cfg"
```

Expected: marker `portal-2`, the database commit and `x64-crossover26.3-r25`; log `highball-env: note: recipe portal-2: 1 registry value, 2 files, 0 copies` and `recipe: portal-2 … recorded`; `VideoMemorySize` present once in `user.reg`; `autoexec.cfg` holds `mat_tonemapping_occlusion_use_stencil 1`. The user loads one map with HDR on; no device loss. A second launch logs `already applied`.
3. The user launches **Warframe**. Expected: the launcher window draws text and buttons (not black), updates, reaches the login dialog. `compatdata/230410/pfx/user.reg` has `"dwrite"=""` under `AppDefaults\Launcher.exe\DllOverrides`.
4. Report both results in the PR body under "How to test".

- [ ] **Step 8: PR** (only when the user says push)

`git push -u origin feature/m2c-prefix-recipes`, then `gh pr create -R MagnusPladsen/Proton-ish --base main --head feature/m2c-prefix-recipes --title "feat: apply highball-db prefix recipes at launch" --body-file <scratchpad>/pr-m2c.md`, body ending with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## Self-review notes

- **Spec coverage:** registry/file/copy (Tasks 1, 2, 5), `.reg` import under the game's environment (7), once per prefix per db version with marker and missing-copy rule (4, 7), no rollback (5: overwrite only), `optIn` ignored (6: nothing reads it; M2b never did), other-engine default apply with note, switch, launch option, footer and README (3, 8, 9), unsupported step types noted (6), error rows (5 failure → no record, 7 import failure → no marker), manual test (9).
- **Types:** `PrefixRecipe.Context` and `Outcome` initialisers are defined in Task 5 before Task 6 uses them; `otherEnginesAllowed` (Task 3) is what `main.swift` calls; the shell variable `np_hb_recipe` is set in Task 7 Step 3 and read in Step 4; the file word `skip` is written by Task 8 and read by Task 7 and `otherEnginesAllowed`.
- **Review Focus:** 1 → Task 1 (`regEscaping`, `regLineBreak`); 2 → Task 2 (`targetDotDot`, `targetAbsolute`); 3 → Task 2 (`targetInGameFolder` with a `/Volumes/…` path); 4 → Task 4 (`appliedCopyGone`) and Task 5 (`copyTargetsPresent`); 5 → Task 7 (failed import, stale file).
