// The prefix-changing steps of a highball-db recipe, applied to a Steam prefix the way Highball
// applies them to its own bottles: registry values through one .reg file the run script imports
// under the game's environment, files and engine copies written here. Highball's RecipeRunner
// runs `wine reg add` itself; a Steam launch has one Wine environment, the game's, so the
// import happens there instead.

import Foundation
import HighballKit

public enum PrefixRecipe {

    public struct Context: Sendable {
        public var driveC: URL
        public var engineRoot: URL
        public var engineID: String
        public var dbCommit: String
        public var installPath: URL?
        public var marker: URL?
        public var registryFile: URL?
        public var otherEngines: Bool

        public init(driveC: URL, engineRoot: URL, engineID: String, dbCommit: String, installPath: URL?,
                    marker: URL?, registryFile: URL?, otherEngines: Bool) {
            self.driveC = driveC
            self.engineRoot = engineRoot
            self.engineID = engineID
            self.dbCommit = dbCommit
            self.installPath = installPath
            self.marker = marker
            self.registryFile = registryFile
            self.otherEngines = otherEngines
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var notes: [String]
        // The "# recipe:" payload; nil when there is nothing to import or record
        public var record: String?
        // False when a step failed: the run script imports the registry file but writes no
        // marker, so the next launch tries the failed step again
        public var complete: Bool

        public init(notes: [String] = [], record: String? = nil, complete: Bool = true) {
            self.notes = notes
            self.record = record
            self.complete = complete
        }
    }

    public static func run(recipe: Recipe, context: Context) -> Outcome {
        let steps = recipe.steps.filter(isPrefixStep)
        guard !steps.isEmpty else { return Outcome() }
        guard !context.dbCommit.isEmpty else {
            removeRegistryFile(context)
            return Outcome(notes: ["recipe \(recipe.id) not applied: highball-db names no commit"], complete: false)
        }
        var outcome = Outcome()
        switch engineDecision(recipeEngine: recipe.engine, running: context.engineID, otherEngines: context.otherEngines) {
        case .skip(let verifiedOn):
            removeRegistryFile(context)
            outcome.notes.append("recipe \(recipe.id) skipped: verified on \(verifiedOn), this engine is \(context.engineID); turn on Apply game fixes verified on other engines in Proton-ish, or set the launch option PROTONISH_RECIPE_OTHER_ENGINES=1")
            return outcome
        case .applyWithNote(let verifiedOn):
            outcome.notes.append("recipe \(recipe.id) was verified on \(verifiedOn), this engine is \(context.engineID); applying anyway")
        case .apply:
            break
        }
        let marker = context.marker.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        if isApplied(marker: marker, recipeID: recipe.id, commit: context.dbCommit, engine: context.engineID,
                     copyTargetsPresent: copyTargetsPresent(steps, context)) {
            removeRegistryFile(context)
            outcome.notes.append("recipe \(recipe.id) already applied (highball-db \(context.dbCommit.prefix(8)))")
            return outcome
        }
        var applier = Applier(recipe: recipe, context: context)
        applier.apply(steps)
        outcome.notes += applier.notes
        outcome.record = record(recipeID: recipe.id, commit: context.dbCommit, engine: context.engineID)
        outcome.complete = !applier.failed
        return outcome
    }

    static func isPrefixStep(_ step: Recipe.Step) -> Bool {
        switch step {
        case .registry, .file, .copy: true
        default: false
        }
    }

    private static func copyTargetsPresent(_ steps: [Recipe.Step], _ context: Context) -> Bool {
        steps.allSatisfy { step in
            guard case let .copy(_, to, _) = step,
                  let url = target(of: to, driveC: context.driveC, installPath: context.installPath) else { return true }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    private static func removeRegistryFile(_ context: Context) {
        if let file = context.registryFile { try? FileManager.default.removeItem(at: file) }
    }

    // Writes the steps and counts them; one failed step means no record, the next launch tries again
    private struct Applier {
        let recipe: Recipe
        let context: Context
        var notes: [String] = []
        var failed = false
        private var counts = (registry: 0, files: 0, copies: 0)

        init(recipe: Recipe, context: Context) {
            self.recipe = recipe
            self.context = context
        }

        mutating func apply(_ steps: [Recipe.Step]) {
            writeRegistry(steps)
            for step in steps {
                switch step {
                case let .file(path, contents): writeFile(path, contents)
                case let .copy(from, to, asNative): copy(from, to, asNative)
                default: break
                }
            }
            notes.append("recipe \(recipe.id): \(counts.registry) registry value\(counts.registry == 1 ? "" : "s"), "
                + "\(counts.files) file\(counts.files == 1 ? "" : "s"), \(counts.copies) cop\(counts.copies == 1 ? "y" : "ies")")
        }

        private mutating func writeRegistry(_ steps: [Recipe.Step]) {
            let registry = registryText(steps)
            notes += registry.notes
            removeRegistryFile(context)
            guard let text = registry.text, let file = context.registryFile else { return }
            do {
                try text.write(to: file, atomically: true, encoding: .utf8)
                counts.registry = steps.filter { if case .registry = $0 { true } else { false } }.count - registry.notes.count
            } catch {
                fail("registry file not written: \(error.localizedDescription)")
            }
        }

        private mutating func writeFile(_ path: String, _ contents: String) {
            guard let url = target(of: path, driveC: context.driveC, installPath: context.installPath) else {
                return fail("file \(path) not applied: path refused")
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: url, atomically: true, encoding: .utf8)
                counts.files += 1
            } catch {
                fail("file \(path) not written: \(error.localizedDescription)")
            }
        }

        private mutating func copy(_ from: String, _ to: String, _ asNative: Bool) {
            guard let source = RecipeRunner.copySource(engineRoot: context.engineRoot, from) else {
                return fail("copy \(from) not applied: not a file inside the engine")
            }
            guard let dest = target(of: to, driveC: context.driveC, installPath: context.installPath) else {
                return fail("copy to \(to) not applied: path refused")
            }
            do {
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                var data = try Data(contentsOf: source)
                if asNative { data = withoutBuiltinMarker(data) }
                try data.write(to: dest, options: .atomic)
                counts.copies += 1
            } catch {
                fail("copy \(from) not written: \(error.localizedDescription)")
            }
        }

        private mutating func fail(_ what: String) {
            failed = true
            notes.append("recipe \(recipe.id): \(what)")
        }
    }

    // Wine stamps its builtin DLLs with "Wine builtin DLL" at 0x40; blank, the loader treats
    // the file as native (HighballKit's RecipeRunner.withoutBuiltinMarker, not public)
    static func withoutBuiltinMarker(_ data: Data) -> Data {
        let marker = Data("Wine builtin DLL\0".utf8)
        guard data.count >= 0x40 + marker.count, data[0x40..<0x40 + marker.count] == marker else { return data }
        var out = data
        out.replaceSubrange(0x40..<0x40 + marker.count, with: Data(count: marker.count))
        return out
    }

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
        for case let .registry(key, rawName, type, data) in steps {
            // The name goes into the note, so it must not break the note's line either
            let name = rawName.split(whereSeparator: \.isNewline).joined(separator: " ")
            guard let expanded = expandRoot(key) else {
                notes.append("registry value \(name) not applied: key root \(key.split(separator: "\\").first.map(String.init) ?? key) is not supported")
                continue
            }
            // Recipes are third-party data; a line break in any part would write its own lines
            if let part = [("key", key), ("name", rawName), ("data", data)].first(where: { $0.1.contains(where: \.isNewline) }) {
                notes.append("registry value \(name) not applied: \(part.0) has a line break")
                continue
            }
            guard let value = registryValue(type: type, data: data, name: name, notes: &notes) else { continue }
            if expanded != lastKey {
                if lastKey != nil { lines.append("") }
                lines.append("[\(expanded)]")
                lastKey = expanded
            }
            lines.append((name.isEmpty ? "@" : "\"\(escaped(name))\"") + "=" + value)
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

    // regedit reads \\ and \" inside a quoted name or value
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func registryValue(type: String, data: String, name: String, notes: inout [String]) -> String? {
        switch type {
        case "REG_SZ":
            return "\"" + escaped(data) + "\""
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
