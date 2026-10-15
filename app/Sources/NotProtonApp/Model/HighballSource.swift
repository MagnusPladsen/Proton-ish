// Finds Highball's installed engines. Highball keeps them outside its app bundle.

import Foundation

enum HighballSupport: Sendable, Equatable {
    case supported(RunnerBuild)
    case unsupported
    case unreadable
}

struct HighballEngine: Sendable, Identifiable {
    let id: String
    let directory: URL
    let displayName: String
    let support: HighballSupport
    var d3dmetalAccepted = false
    var isUsable: Bool { if case .supported = support { true } else { false } }
    var engineRoot: URL { directory.appending(path: "engine") }
}

enum HighballSource {
    static func home(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultHome: URL = SupportPaths.applicationSupport.appending(path: "Highball")
    ) -> URL {
        if let override = environment["HIGHBALL_HOME"], !override.isEmpty { return URL(filePath: override) }
        let config = defaultHome.appending(path: "config.json")
        if let data = try? Data(contentsOf: config),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let home = object["home"] as? String, !home.isEmpty {
            return URL(filePath: home)
        }
        return defaultHome
    }

    static func discover(home: URL = HighballSource.home()) -> [HighballEngine] {
        let engines = home.appending(path: "engines")
        let entries = (try? FileManager.default.contentsOfDirectory(at: engines, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap(inspect).sorted { $0.id < $1.id }
    }

    static func inspect(_ directory: URL) -> HighballEngine? {
        let manifest = directory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path(percentEncoded: false)) else { return nil }
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return HighballEngine(id: directory.lastPathComponent, directory: directory,
                                  displayName: directory.lastPathComponent, support: .unreadable)
        }
        let id = (object["id"] as? String) ?? directory.lastPathComponent
        let name = (object["displayName"] as? String) ?? id
        let loader = directory.appending(path: "engine/bin/wine")
        let support: HighballSupport
        if let hash = Digest.sha256IfPresent(loader),
           let build = SupportedRunners.build(loaderSHA256: hash), build.runtime == .highball,
           // Revisions can share launcher bytes, so the manifest id has to name the build too
           build.bundleVersion == id {
            support = .supported(build)
        } else {
            support = .unsupported
        }
        let accepted = (object["acceptedLicenses"] as? [String] ?? []).contains { $0.hasPrefix("apple-gptk-license-") }
        return HighballEngine(id: id, directory: directory, displayName: name, support: support,
                              d3dmetalAccepted: accepted)
    }
}
