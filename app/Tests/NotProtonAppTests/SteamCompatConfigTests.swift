import Foundation
import Testing

@testable import NotProtonApp

@Suite("Steam's default tool in config.vdf")
struct SteamCompatConfigTests {

    private func config(defaultTool: String?, extra: String = "") -> String {
        let zero = defaultTool.map {
            "\t\t\t\t\t\"0\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"\($0)\"\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"priority\"\t\t\"75\"\n\t\t\t\t\t}\n"
        } ?? ""
        return """
        "InstallConfigStore"
        {
        \t"Software"
        \t{
        \t\t"Valve"
        \t\t{
        \t\t\t"Steam"
        \t\t\t{
        \t\t\t\t"CompatToolMapping"
        \t\t\t\t{
        \(zero)\t\t\t\t\t"945360"
        \t\t\t\t\t{
        \t\t\t\t\t\t"name"\t\t"protonish-highball-x64-crossover26.3-r19"
        \t\t\t\t\t\t"config"\t\t""
        \t\t\t\t\t\t"priority"\t\t"250"
        \t\t\t\t\t}
        \t\t\t\t}
        \(extra)\t\t\t}
        \t\t}
        \t}
        }
        """
    }

    @Test("The default tool is read from the \"0\" entry, not from a game's")
    func readsDefault() {
        #expect(SteamCompatConfig.defaultTool(in: config(defaultTool: "protonish-26.3")) == "protonish-26.3")
        #expect(SteamCompatConfig.defaultTool(in: config(defaultTool: nil)) == nil)
    }

    @Test("Our tool is removed as the default; the game's own mapping and everything else stay")
    func removesOurs() throws {
        let text = config(defaultTool: "protonish-highball-x64-crossover26.3-r19")
        let updated = try #require(SteamCompatConfig.removingDefaultTool(from: text))
        #expect(SteamCompatConfig.defaultTool(in: updated) == nil)
        #expect(updated == config(defaultTool: nil))
    }

    @Test("Someone else's default is left alone")
    func keepsForeign() {
        #expect(SteamCompatConfig.removingDefaultTool(from: config(defaultTool: "proton_9")) == nil)
    }

    @Test("A config without the section or with a \"0\" key elsewhere is left alone")
    func ignoresOtherZeroKeys() {
        let decoy = "\t\t\t\t\"Other\"\n\t\t\t\t{\n\t\t\t\t\t\"0\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"protonish-26.3\"\n\t\t\t\t\t}\n\t\t\t\t}\n"
        #expect(SteamCompatConfig.removingDefaultTool(from: config(defaultTool: nil, extra: decoy)) == nil)
        #expect(SteamCompatConfig.removingDefaultTool(from: "\"InstallConfigStore\"\n{\n}\n") == nil)
    }

    @Test("The file is rewritten only when something changed")
    func writesFile() throws {
        let work = try scratchDirectory("config-vdf")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "config.vdf")
        try Data(config(defaultTool: "protonish-26.3").utf8).write(to: file)
        #expect(try SteamCompatConfig.clearDefaultTool(in: file))
        #expect(try String(contentsOf: file, encoding: .utf8) == config(defaultTool: nil))
        #expect(try !SteamCompatConfig.clearDefaultTool(in: file))
        #expect(try !SteamCompatConfig.clearDefaultTool(in: work.appending(path: "missing.vdf")))
    }
}
