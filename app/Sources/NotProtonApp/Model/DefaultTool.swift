// Steam's default compatibility tool, the one every Windows game without its own choice uses.
// The app writes a request; the dylib applies it inside Steam at the next start and records
// what Steam had (see np_compat_apply_default_tool).

import Foundation

enum DefaultTool {
    static let step = String(localized: "Set Steam's default tool")

    static var requestFile: URL { SupportPaths.support.appending(path: "default-tool") }
    static var steamFile: URL { SupportPaths.support.appending(path: "steam-default-tool") }

    // nil: no request. "": clear. Otherwise the tool to make the default.
    static func request(at url: URL = requestFile) -> String? { firstLine(of: url) }

    // nil: Steam has not run with this build yet. "": no default. Otherwise Steam's default tool.
    static func steamDefault(at url: URL = steamFile) -> String? { firstLine(of: url) }

    static func isOurs(_ name: String) -> Bool { name.hasPrefix("protonish") }

    // The newest Highball compatibility tool that is set up
    static func highballTool(installed: [RunnerBuild]) -> String? {
        SupportedRunners.all.last { $0.runtime == .highball && installed.contains($0) }?.tools.first?.name
    }

    // A request for our Highball tool follows the newest Highball build that is set up
    static func shouldFollow(request: String?, newest: String) -> Bool {
        guard let request, isOurs(request), request.contains("-highball-") else { return false }
        return request != newest
    }

    static func display(of tool: String) -> String {
        SupportedRunners.all.flatMap(\.tools).first { $0.name == tool }?.display ?? tool
    }

    static func set(_ tool: String, at url: URL = requestFile) throws { try write(tool, to: url) }
    static func clear(at url: URL = requestFile) throws { try write("", to: url) }

    // Option C: after the engine is set up, Highball becomes the default only when Steam has
    // none, and only once (a request the user already made, on or off, stands)
    static func shouldAdopt(request: String?, steamDefault: String?) -> Bool {
        request == nil && steamDefault == ""
    }

    private static func firstLine(of url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func write(_ tool: String, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((tool + "\n").utf8).write(to: url, options: .atomic)
        } catch {
            throw StepFailure(step: step, detail: error.localizedDescription)
        }
    }
}
