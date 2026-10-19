// The prefix-changing steps of a highball-db recipe, applied to a Steam prefix the way Highball
// applies them to its own bottles: registry values through one .reg file the run script imports
// under the game's environment, files and engine copies written here. Highball's RecipeRunner
// runs `wine reg add` itself; a Steam launch has one Wine environment, the game's, so the
// import happens there instead.

import Foundation
import HighballKit

public enum PrefixRecipe {

    static let steamCommon = "Program Files (x86)/Steam/steamapps/common/"

    // Where a file or copy step's target goes. Highball's bottles hold the Steam library under
    // drive C; a Steam game on the Mac lives in its library folder and reaches the prefix
    // through a drive letter, so a target in the game's folder goes there.
    public static func target(of path: String, driveC: URL, installPath: URL?) -> URL? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.hasPrefix("/"), !parts.contains(".."), !parts.contains("") else { return nil }
        if let installPath, path.hasPrefix(steamCommon) {
            let inside = path.dropFirst(steamCommon.count).split(separator: "/", maxSplits: 1).map(String.init)
            if inside.count == 2, inside[0].caseInsensitiveCompare(installPath.lastPathComponent) == .orderedSame {
                return installPath.appending(path: inside[1])
            }
        }
        return driveC.appending(path: path)
    }

    public enum EngineDecision: Equatable, Sendable {
        case apply
        case applyWithNote(verifiedOn: String)
        case skip(verifiedOn: String)
    }

    // "x64-crossover26.3-r25" -> "x64-crossover26.3": revisions of one line are cumulative
    public static func engineLine(of id: String) -> String {
        guard let range = id.range(of: "-r[0-9]+$", options: .regularExpression) else { return id }
        return String(id[..<range.lowerBound])
    }

    // A recipe verified on another Wine line still usually works; the user decides whether to
    // trust it, by the switch or per game
    public static func engineDecision(recipeEngine: String?, running: String, otherEngines: Bool) -> EngineDecision {
        guard let recipeEngine, engineLine(of: recipeEngine) != engineLine(of: running) else { return .apply }
        return otherEngines ? .applyWithNote(verifiedOn: recipeEngine) : .skip(verifiedOn: recipeEngine)
    }

    // The switch file holds "apply" or "skip" (missing is apply); the game's launch option
    // PROTONISH_RECIPE_OTHER_ENGINES=0|1 wins
    public static func otherEnginesAllowed(switchValue: String?, launchOption: String?) -> Bool {
        switch launchOption {
        case "0": false
        case "1": true
        default: switchValue?.trimmingCharacters(in: .whitespacesAndNewlines) != "skip"
        }
    }

    // What the run script records after a successful import, as one "# recipe:" line
    public static func record(recipeID: String, commit: String, engine: String) -> String {
        "\(recipeID) \(commit) \(engine)"
    }

    // The marker is the record as three lines. A copy target that went missing counts as not
    // applied, HighballKit's artifactsPresent rule: the game was reinstalled under it.
    public static func isApplied(marker: String?, recipeID: String, commit: String, engine: String, copyTargetsPresent: Bool) -> Bool {
        guard copyTargetsPresent, let marker else { return false }
        let lines = marker.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.count >= 3 && lines[0] == recipeID && lines[1] == commit && lines[2] == engine
    }

    // One .reg file for every registry step, in the format `reg import` reads
    static func registryText(_ steps: [Recipe.Step]) -> (text: String?, notes: [String]) {
        var notes: [String] = []
        var lines: [String] = []
        var lastKey: String?
        for case let .registry(key, name, type, data) in steps {
            guard let expanded = expandRoot(key) else {
                notes.append("registry value \(name) not applied: key root \(key.split(separator: "\\").first.map(String.init) ?? key) is not supported")
                continue
            }
            guard !data.contains(where: \.isNewline) else {
                notes.append("registry value \(name) not applied: data has a line break")
                continue
            }
            guard let value = registryValue(type: type, data: data, name: name, notes: &notes) else { continue }
            if expanded != lastKey {
                if lastKey != nil { lines.append("") }
                lines.append("[\(expanded)]")
                lastKey = expanded
            }
            lines.append((name.isEmpty ? "@" : "\"\(name)\"") + "=" + value)
        }
        guard !lines.isEmpty else { return (nil, notes) }
        return ((["Windows Registry Editor Version 5.00", ""] + lines).joined(separator: "\r\n") + "\r\n", notes)
    }

    private static func expandRoot(_ key: String) -> String? {
        let parts = key.split(separator: "\\", maxSplits: 1).map(String.init)
        let root: String? = switch parts.first {
        case "HKCU", "HKEY_CURRENT_USER": "HKEY_CURRENT_USER"
        case "HKLM", "HKEY_LOCAL_MACHINE": "HKEY_LOCAL_MACHINE"
        default: nil
        }
        guard let root else { return nil }
        return parts.count == 2 ? root + "\\" + parts[1] : root
    }

    private static func registryValue(type: String, data: String, name: String, notes: inout [String]) -> String? {
        switch type {
        case "REG_SZ":
            return "\"" + data.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        case "REG_DWORD":
            guard let number = UInt32(data) else {
                notes.append("registry value \(name) not applied: '\(data)' is not a number")
                return nil
            }
            return String(format: "dword:%08x", number)
        default:
            notes.append("registry value \(name) not applied: \(type) is not supported yet")
            return nil
        }
    }
}
