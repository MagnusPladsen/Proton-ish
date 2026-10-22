import Foundation

// A pre-filled highball-db report for a game last run on a Highball engine, the way the Highball app's
// PlayReport links to the form. The player rates and submits it in the browser; nothing is posted from here.
struct GameReport: Sendable, Equatable {
    let title: String
    let appID: String
    let engine: String
    let renderer: String?
    let kitVersion: String?
    let appVersion: String
    let chip: String
    let macOS: String

    // The form's renderer options, by their field values
    static let renderers: Set<String> = ["dxmt", "d3dmetal", "dxvk", "wined3d"]

    // Long-lived prefixes keep every launch in one log; the last launch is near its end
    static let logTailBytes: UInt64 = 1 << 20

    var url: URL {
        var components = URLComponents(string: "https://github.com/gauthierpiarrette/highball-db/issues/new")!
        var items = [
            URLQueryItem(name: "template", value: "report.yml"),
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "steam_appid", value: appID),
            URLQueryItem(name: "chip", value: chip),
            URLQueryItem(name: "macos", value: macOS),
            URLQueryItem(name: "engine", value: engine),
            URLQueryItem(name: "version", value: version),
            // Highball's ingest copies Session into the notes when the player leaves Notes empty,
            // so this is how its maintainer tells a Proton-ish report apart
            URLQueryItem(name: "session", value: "Played through Proton-ish (macOS Steam), Highball engine \(engine)."),
        ]
        if let renderer { items.append(URLQueryItem(name: "renderer", value: renderer)) }
        components.queryItems = items
        // URLComponents leaves "+" alone, which a query decodes as a space
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    private var version: String {
        guard let kitVersion else { return "Proton-ish \(appVersion)" }
        return "Proton-ish \(appVersion), HighballKit \(kitVersion)"
    }

    // Engine ids are <arch>-<line>-r<N>; CrossOver builds are dotted numbers
    static func isHighballEngine(_ build: String) -> Bool {
        build.wholeMatch(of: #/[a-z0-9_]+-[a-z0-9._]+-r[0-9]+/#) != nil
    }

    struct LaunchFacts: Equatable {
        var renderer: String?
        var kitVersion: String?
    }

    static func lastLaunch(inLog text: String) -> LaunchFacts {
        var facts = LaunchFacts()
        let rendererLine = "highball-env: note: renderer ", kitLine = "highball-env: highball-env HighballKit "
        for line in text.split(separator: "\n") {
            // Each launch starts over: one that fell back to the engine defaults names no renderer
            if line.hasPrefix("=== notproton run ") {
                facts = LaunchFacts()
            } else if line.hasPrefix(rendererLine) {
                let renderer = line.dropFirst(rendererLine.count).trimmingCharacters(in: .whitespaces)
                facts.renderer = renderers.contains(renderer) ? renderer : nil
            } else if line.hasPrefix(kitLine) {
                facts.kitVersion = line.dropFirst(kitLine.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return facts
    }

    static func make(
        for prefix: WinePrefix, record: PrefixBuildRecord?, appVersion: String,
        chip: String = Machine.chip, macOS: String = Machine.macOS, log: URL? = nil
    ) -> GameReport? {
        guard let record, isHighballEngine(record.build) else { return nil }
        let facts = lastLaunch(inLog: tail(of: log ?? PrefixLog.launch.url(for: prefix)))
        return GameReport(
            title: prefix.title, appID: prefix.appID, engine: record.build, renderer: facts.renderer,
            kitVersion: facts.kitVersion, appVersion: appVersion, chip: chip, macOS: macOS)
    }

    private static func tail(of file: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "" }
        let start = size > logTailBytes ? size - logTailBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return "" }
        let text = String(decoding: data, as: UTF8.self)
        // A tail cut mid-line would read a partial line as a whole one
        guard start > 0, let newline = text.firstIndex(of: "\n") else { return text }
        return String(text[text.index(after: newline)...])
    }

    enum Machine {
        static var chip: String {
            var size = 0
            guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "unknown chip" }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "unknown chip" }
            let chip = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return chip.isEmpty ? "unknown chip" : chip
        }

        static var macOS: String {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let base = "\(version.majorVersion).\(version.minorVersion)"
            return version.patchVersion == 0 ? base : "\(base).\(version.patchVersion)"
        }
    }
}
