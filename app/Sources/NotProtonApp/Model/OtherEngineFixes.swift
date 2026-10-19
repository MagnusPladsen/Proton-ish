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
