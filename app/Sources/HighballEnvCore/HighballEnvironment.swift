// Turns the environment HighballKit builds into the lines the run script exports. Proton-ish keeps
// the variables that point at its own patched engine and the Steam prefix, and a value the user
// typed into the game's launch options wins over Highball's.

public enum HighballEnvironment {

    // The run script keeps WINEDEBUG's fuller default and its per-prefix MSync choice
    public static let ownedKeys: Set<String> = [
        "WINEPREFIX", "WINELOADER", "WINESERVER", "WINEDLLPATH", "PATH", "WINEUSERNAME", "CX_ROOT",
        "WINEDEBUG", "WINEMSYNC",
    ]

    static let userWinsPrefixes = ["DXMT_", "D3DM_", "DXVK_", "MTL_"]

    public static func lines(highball: [String: String], user: [String: String], notes: [String]) -> [String] {
        var output = notes.map { "# note: " + oneLine($0) }
        for key in highball.keys.sorted() {
            guard var value = highball[key] else { continue }
            guard isValidKey(key) else {
                output.append("# skipped: invalid name " + oneLine(key))
                continue
            }
            if ownedKeys.contains(key) { continue }
            if key == "DXMT_CONFIG", let typed = user[key], !typed.isEmpty {
                value = joinedConfig(value, typed)
            } else if userWins(key), user[key] != nil {
                continue
            }
            guard !value.contains("\n"), !value.contains("\0") else {
                output.append("# skipped: \(key) has a line break")
                continue
            }
            output.append("\(key)=\(value)")
        }
        return output
    }

    static func isValidKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, first == "_" || ("A"..."Z").contains(first) else { return false }
        return key.unicodeScalars.allSatisfy { $0 == "_" || ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
    }

    static func userWins(_ key: String) -> Bool {
        userWinsPrefixes.contains { key.hasPrefix($0) }
    }

    // DXMT reads ";"-separated settings and the last one wins, so the user's go last.
    static func joinedConfig(_ highball: String, _ typed: String) -> String {
        guard !highball.isEmpty else { return typed }
        return (highball.hasSuffix(";") ? highball : highball + ";") + typed
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
