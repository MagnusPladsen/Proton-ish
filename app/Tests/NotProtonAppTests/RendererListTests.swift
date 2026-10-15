import Foundation
import Testing

@testable import NotProtonApp

@Suite("Renderer list for the options panel")
struct RendererListTests {

    static let highball = SupportedRunners.all.last { $0.runtime == .highball }!
    static let crossOver = SupportedRunners.all.first { $0.runtime == .crossover }!

    @Test("Each Highball tool gets one line with its engine's renderers; CrossOver tools are left out")
    func writesHighballToolsOnly() throws {
        let work = try scratchDirectory("renderers")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "renderers")
        let tools = [
            InstalledTool(tool: Self.highball.tools[0], build: Self.highball.id),
            InstalledTool(tool: Self.crossOver.tools[0], build: Self.crossOver.id),
        ]
        var asked: [String] = []
        try RendererList.sync(tools: tools, builds: [Self.highball, Self.crossOver], helper: URL(filePath: "/helper"),
                              file: file) { _, engine in
            asked.append(engine)
            return "# highball-env HighballKit 0.10.15\nwined3d\ndxmt\n"
        }
        #expect(asked == [Self.highball.bundleVersion])
        #expect(try String(contentsOf: file, encoding: .utf8) == "\(Self.highball.tools[0].name)\twined3d,dxmt\n")
    }

    @Test("Without the helper nothing is written")
    func noHelper() throws {
        let work = try scratchDirectory("renderers-none")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "renderers")
        try RendererList.sync(tools: [], builds: [Self.highball], helper: nil, file: file) { _, _ in "" }
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test("Helper comments and blank lines are not renderers")
    func parsesHelperOutput() {
        #expect(RendererList.lines(fromHelperOutput: "# note\n\ndxmt\n d3dmetal \n") == ["dxmt", "d3dmetal"])
    }
}
