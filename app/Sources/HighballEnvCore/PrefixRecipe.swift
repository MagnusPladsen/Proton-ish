// The prefix-changing steps of a highball-db recipe, applied to a Steam prefix the way Highball
// applies them to its own bottles: registry values through one .reg file the run script imports
// under the game's environment, files and engine copies written here. Highball's RecipeRunner
// runs `wine reg add` itself; a Steam launch has one Wine environment, the game's, so the
// import happens there instead.

import Foundation
import HighballKit

public enum PrefixRecipe {

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
