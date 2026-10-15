import Foundation
import Testing

@testable import NotProtonApp

@Suite("Steam's default tool")
struct DefaultToolTests {

    @Test("A request file reads as its first line; no file is no request")
    func requestParsing() throws {
        let work = try scratchDirectory("default-tool")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "default-tool")
        #expect(DefaultTool.request(at: file) == nil)
        try DefaultTool.set("protonish-highball-x64-crossover26.3-r19", at: file)
        #expect(DefaultTool.request(at: file) == "protonish-highball-x64-crossover26.3-r19")
        try DefaultTool.clear(at: file)
        #expect(DefaultTool.request(at: file) == "")
    }

    @Test("Steam's recorded default distinguishes none from not yet known")
    func steamDefault() throws {
        let work = try scratchDirectory("steam-default")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "steam-default-tool")
        #expect(DefaultTool.steamDefault(at: file) == nil)
        try Data("\n".utf8).write(to: file)
        #expect(DefaultTool.steamDefault(at: file) == "")
        try Data("proton_9\n".utf8).write(to: file)
        #expect(DefaultTool.steamDefault(at: file) == "proton_9")
    }

    @Test("Highball is adopted as the default only when Steam has none and nothing was asked yet",
          arguments: [
            (nil, "", true), (nil, "proton_9", false), (nil, nil, false),
            ("", "", false), ("protonish-highball-x64-crossover26.3-r19", "", false),
          ] as [(String?, String?, Bool)])
    func adoption(request: String?, steamDefault: String?, adopt: Bool) {
        #expect(DefaultTool.shouldAdopt(request: request, steamDefault: steamDefault) == adopt)
    }

    @Test("The Highball tool name comes from the installed Highball build")
    func highballTool() {
        let builds = SupportedRunners.all.filter { $0.runtime == .highball }
        #expect(DefaultTool.highballTool(installed: builds) == "protonish-highball-x64-crossover26.3-r19")
        #expect(DefaultTool.highballTool(installed: []) == nil)
    }

    @Test("Only Proton-ish's own tools count as ours")
    func ours() {
        #expect(DefaultTool.isOurs("protonish-26.3"))
        #expect(!DefaultTool.isOurs("proton_9"))
    }
}
