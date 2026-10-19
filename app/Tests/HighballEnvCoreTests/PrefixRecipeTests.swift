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
}
