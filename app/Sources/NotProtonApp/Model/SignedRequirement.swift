// The designated requirement Proton-ish last signed Steam with. macOS keys Steam's Accessibility
// grant on it. Repair Steam puts Valve's signature back, and the next Install signs with the same
// local identity again, so the grant macOS holds still fits and must not be reset.

import Foundation

enum SignedRequirement {
    static var file: URL { SupportPaths.support.appending(path: "signed-requirement") }

    static func read(at url: URL = file) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return line.isEmpty ? nil : String(line)
    }

    static func record(_ requirement: String, at url: URL = file) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((requirement + "\n").utf8).write(to: url, options: .atomic)
    }

    // The grant is reset unless the new signature is the one Steam already had or the one
    // Proton-ish recorded at its last signing
    static func needsReset(prior: String?, recorded: String?, signed: String?) -> Bool {
        guard let signed else { return true }
        return signed != prior && signed != recorded
    }
}
