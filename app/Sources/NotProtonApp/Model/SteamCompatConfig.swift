// Steam keeps the default compatibility tool in config/config.vdf, under CompatToolMapping as app "0".
// Remove Everything takes the Proton-ish tool out of it, so Steam does not keep pointing at a tool
// that no longer exists. Edited as text while Steam is stopped; everything else stays byte for byte.

import Foundation

enum SteamCompatConfig {
    static let step = String(localized: "Clear Steam's default tool")

    static func defaultTool(in text: String) -> String? {
        guard let block = defaultBlock(in: text.components(separatedBy: "\n")) else { return nil }
        return block.name
    }

    // nil when the file is missing or names no default
    static func defaultTool(at file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return defaultTool(in: text)
    }

    /// The text without the default-tool block when that tool is ours; nil when there is nothing to do.
    static func removingDefaultTool(from text: String, isOurs: (String) -> Bool = DefaultTool.isOurs) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let block = defaultBlock(in: lines), let name = block.name, isOurs(name) else { return nil }
        lines.removeSubrange(block.range)
        return lines.joined(separator: "\n")
    }

    @discardableResult
    static func clearDefaultTool(in file: URL, isOurs: (String) -> Bool = DefaultTool.isOurs) throws -> Bool {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let updated = removingDefaultTool(from: text, isOurs: isOurs) else { return false }
        do {
            try Data(updated.utf8).write(to: file, options: .atomic)
        } catch {
            throw StepFailure(step: step, detail: error.localizedDescription)
        }
        return true
    }

    // The lines of the "0" block inside "CompatToolMapping", and the tool it names
    private static func defaultBlock(in lines: [String]) -> (range: Range<Int>, name: String?)? {
        guard let section = blockRange(in: lines, key: "\"CompatToolMapping\"", from: 0, upTo: lines.count, depth: nil) else { return nil }
        // Directly inside the section, one brace deep, never a game's own entry
        guard let zero = blockRange(in: lines, key: "\"0\"", from: section.lowerBound, upTo: section.upperBound, depth: 1) else { return nil }
        let name = lines[zero].lazy.compactMap(nameValue).first
        return (zero, name)
    }

    // From the key line through its matching closing brace; `depth` counts braces from `start`
    private static func blockRange(in lines: [String], key: String, from start: Int, upTo end: Int, depth wanted: Int?) -> Range<Int>? {
        var depth = 0
        var index = start
        while index < end {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line == "{" { depth += 1 } else if line == "}" { depth -= 1 }
            if line == key, wanted == nil || depth == wanted, index + 1 < end,
               lines[index + 1].trimmingCharacters(in: .whitespaces) == "{" {
                var inner = 0
                for close in (index + 1)..<end {
                    let candidate = lines[close].trimmingCharacters(in: .whitespaces)
                    if candidate == "{" { inner += 1 } else if candidate == "}" { inner -= 1; if inner == 0 { return index..<(close + 1) } }
                }
                return nil
            }
            index += 1
        }
        return nil
    }

    private static func nameValue(_ line: String) -> String? {
        let fields = line.split(whereSeparator: { $0 == "\t" }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        guard fields.count == 2, fields[0] == "name" else { return nil }
        return fields[1]
    }
}
