// Which renderers each Highball compatibility tool can offer, for the options panel inside
// Steam. Written at Set Up and after Enable D3DMetal; the dylib reads it when it patches the panel.

import Foundation

enum RendererList {
    static let step = String(localized: "List the engine's renderers")

    static var file: URL { SupportPaths.support.appending(path: "renderers") }

    // "<tool>\t<renderer>,<renderer>" per Highball tool
    static func contents(_ renderers: [(tool: String, renderers: [String])]) -> String {
        renderers.map { "\($0.tool)\t\($0.renderers.joined(separator: ","))\n" }.joined()
    }

    static func lines(fromHelperOutput output: String) -> [String] {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Asks highball-env about every installed Highball build and rewrites the list.
    static func sync(
        tools: [InstalledTool] = CompatToolList.installed(),
        builds: [RunnerBuild] = RunnerStore.installedBuilds(),
        helper: URL? = try? InstallPayload.locate().highballEnv,
        file: URL = file,
        query: (URL, String) throws -> String = { helper, engine in
            try Shell.check(helper.path(percentEncoded: false), ["renderers", "--engine", engine])
        }
    ) throws {
        guard let helper else { return }
        var entries: [(tool: String, renderers: [String])] = []
        for build in builds where build.runtime == .highball {
            let renderers = lines(fromHelperOutput: try query(helper, build.bundleVersion))
            for tool in tools where tool.build == build.id {
                entries.append((tool.name, renderers))
            }
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents(entries).utf8).write(to: file, options: .atomic)
    }
}
