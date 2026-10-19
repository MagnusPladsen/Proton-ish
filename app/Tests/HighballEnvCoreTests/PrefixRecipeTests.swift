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

    @Test("A line break in the key is refused, it would inject a key header")
    func regKeyLineBreak() throws {
        let steps = try recipe([registry("HKCU\\Software\\Test\n[-HKEY_LOCAL_MACHINE\\Software]", "N", "REG_SZ", "a")]).steps
        #expect(PrefixRecipe.registryText(steps).notes == ["registry value N not applied: key has a line break"])
    }

    @Test("A line break in the value name is refused")
    func regNameLineBreak() throws {
        let steps = try recipe([registry("HKCU\\Software\\Test", "N\n\"M\"=\"x\"", "REG_SZ", "a")]).steps
        #expect(PrefixRecipe.registryText(steps).notes.first?.hasSuffix("not applied: name has a line break") == true)
    }

    @Test("Backslashes and quotes in the value name are escaped")
    func regNameEscaping() throws {
        let steps = try recipe([registry("HKCU\\Software\\Test", "a\\b\"c", "REG_SZ", "v")]).steps
        #expect(PrefixRecipe.registryText(steps).text?.contains("\"a\\\\b\\\"c\"=\"v\"\r\n") == true)
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

    struct Fixture {
        let work: URL
        var driveC: URL { work.appending(path: "pfx/drive_c") }
        var engine: URL { work.appending(path: "engine") }
        var install: URL { work.appending(path: "library/steamapps/common/Portal 2") }
        var marker: URL { work.appending(path: "pfx/protonish-recipe") }
        var reg: URL { driveC.appending(path: "protonish-recipe.reg") }
        func context(otherEngines: Bool = true, installPath: Bool = true, commit: String = "483aac46") -> PrefixRecipe.Context {
            .init(driveC: driveC, engineRoot: engine, engineID: "x64-crossover26.3-r25", dbCommit: commit,
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

    @Test("A copy source outside the engine is refused and the recipe is not complete")
    func runCopyOutside() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let steps: [[String: Any]] = [["type": "copy", "from": "../secret", "to": "x.dll", "asNative": false]]
        let outcome = PrefixRecipe.run(recipe: try recipe(steps), context: f.context())
        #expect(!outcome.complete)
    }

    @Test("A failed step still leaves the registry file for the import, with the record")
    func runFailedStepKeepsRegistry() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let steps = portal2Steps + [["type": "copy", "from": "../secret", "to": "x.dll", "asNative": false]]
        let outcome = PrefixRecipe.run(recipe: try recipe(steps, id: "portal-2"), context: f.context())
        #expect(outcome.record == "portal-2 483aac46 x64-crossover26.3-r25" && FileManager.default.fileExists(atPath: f.reg.path))
    }

    @Test("A complete recipe says so")
    func runComplete() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let outcome = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2"), context: f.context())
        #expect(outcome.complete)
    }

    @Test("A database without a commit applies nothing, the marker could never match")
    func runNoCommit() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.work) }
        let outcome = PrefixRecipe.run(recipe: try recipe(portal2Steps, id: "portal-2"), context: f.context(commit: ""))
        #expect(outcome == .init(notes: ["recipe portal-2 not applied: highball-db names no commit"], record: nil, complete: false))
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
        #expect(outcome == .init(notes: ["recipe portal-2 already applied (highball-db 483aac46)"], record: nil, complete: true))
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
        #expect(outcome == .init(notes: ["recipe portal-2 skipped: verified on x64-sikarugir10.0_6-r5, this engine is x64-crossover26.3-r25; turn on Apply game fixes verified on other engines in Proton-ish, or set the launch option PROTONISH_RECIPE_OTHER_ENGINES=1"], record: nil, complete: true))
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
        #expect(outcome == .init(notes: [], record: nil, complete: true))
    }
}
