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

    @Test("A supported tool is shown by its display name")
    func displayOfOurs() {
        let tool = SupportedRunners.all.first { $0.runtime == .highball }!.tools.first!
        #expect(DefaultTool.display(of: tool.name) == tool.display)
    }

    @Test("Another tool is shown by its name")
    func displayOfOthers() {
        #expect(DefaultTool.display(of: "proton_9") == "proton_9")
    }

    @Test("Highball is adopted as the default only when Steam has none and nothing was asked yet",
          arguments: [
            (nil, "", true), (nil, "proton_9", false), (nil, nil, false),
            ("", "", false), ("protonish-highball-x64-crossover26.3-r19", "", false),
          ] as [(String?, String?, Bool)])
    func adoption(request: String?, steamDefault: String?, adopt: Bool) {
        #expect(DefaultTool.shouldAdopt(request: request, steamDefault: steamDefault) == adopt)
    }

    @Test("The Highball tool name is the newest installed Highball build's")
    func highballTool() {
        let builds = SupportedRunners.all.filter { $0.runtime == .highball }
        #expect(DefaultTool.highballTool(installed: builds) == "protonish-highball-x64-crossover26.3-r25")
        #expect(DefaultTool.highballTool(installed: Array(builds.prefix(1))) == "protonish-highball-x64-crossover26.3-r19")
        #expect(DefaultTool.highballTool(installed: []) == nil)
    }

    @Test("A request for an older Highball tool follows the newest one; anything else stays",
          arguments: [
            ("protonish-highball-x64-crossover26.3-r19", true),
            ("protonish-highball-x64-crossover26.3-r25", false),
            ("protonish-preview-41073", false),
            ("proton_9", false),
            ("", false),
          ])
    func follow(request: String, follows: Bool) {
        #expect(DefaultTool.shouldFollow(request: request, newest: "protonish-highball-x64-crossover26.3-r25") == follows)
    }

    @Test("No request never follows")
    func noRequestNeverFollows() {
        #expect(!DefaultTool.shouldFollow(request: nil, newest: "protonish-highball-x64-crossover26.3-r25"))
    }

    @Test("Only Proton-ish's own tools count as ours")
    func ours() {
        #expect(DefaultTool.isOurs("protonish-26.3"))
        #expect(!DefaultTool.isOurs("proton_9"))
    }
}
