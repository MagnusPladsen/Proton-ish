// The Wine distribution a runner is copied from

import Foundation

enum RuntimeKind: String, Sendable, CaseIterable {
    case crossover
    case highball
}

// What differs between Wine distributions: where things live, the environment they need,
// and whether the user may use them
protocol WineRuntime: Sendable {
    var kind: RuntimeKind { get }
    func unixLoader(inRoot root: URL) -> URL
    func layout(root: URL, flavor: CompatTool.Flavor) -> PrefixTools.WineLayout
    func baseEnvironment(root: URL) -> [String: String]
    func accessStatus(root: URL) -> CrossOverLicense.Status
}

extension RuntimeKind {
    // A runner root is runners/<runtime>-<build>/root, so its parent names the runtime
    static func of(runner root: URL) -> RuntimeKind {
        let parent = root.deletingLastPathComponent().lastPathComponent
        return allCases.first { parent.hasPrefix("\($0.rawValue)-") } ?? .crossover
    }

    var runtime: any WineRuntime {
        switch self {
        case .crossover: CrossOverRuntime()
        case .highball: HighballRuntime()
        }
    }
}

struct CrossOverRuntime: WineRuntime {
    var kind: RuntimeKind { .crossover }

    func unixLoader(inRoot root: URL) -> URL {
        root.appending(path: "lib/wine/x86_64-unix/wine")
    }

    func layout(root: URL, flavor: CompatTool.Flavor) -> PrefixTools.WineLayout {
        let fm = FileManager.default
        let bin = root.appending(path: "bin")
        func executable(_ url: URL) -> Bool {
            fm.isExecutableFile(atPath: url.path(percentEncoded: false))
        }

        let arm = root.appending(path: "lib/wine/aarch64-unix")
        let armLoader = arm.appending(path: "wine.app/Contents/MacOS/wine")
        let armServer = bin.appending(path: "wineserver-arm64")
        if flavor == .fex, executable(armLoader), executable(armServer) {
            return PrefixTools.WineLayout(loader: armLoader, server: armServer, unixDir: arm)
        }

        let unix = root.appending(path: "lib/wine/x86_64-unix")
        let server = bin.appending(path: "wineserver")
        return PrefixTools.WineLayout(
            loader: unix.appending(path: "wine"),
            server: executable(server) ? server : bin.appending(path: "wineserver-x86"),
            unixDir: unix
        )
    }

    func baseEnvironment(root: URL) -> [String: String] {
        [
            "CX_ROOT": root.path(percentEncoded: false),
            "CX_HOME": SupportPaths.applicationSupport.appending(path: "CrossOver").path(percentEncoded: false),
        ]
    }

    func accessStatus(root: URL) -> CrossOverLicense.Status {
        CrossOverLicense.check(crossOverRoot: root)
    }
}

// Highball's engine copied flat into root. bin/wine is its launcher and identifies the build;
// games run the real loader in lib/wine/x86_64-unix, as with CrossOver. No licence.
struct HighballRuntime: WineRuntime {
    var kind: RuntimeKind { .highball }

    func unixLoader(inRoot root: URL) -> URL { root.appending(path: "bin/wine") }

    func layout(root: URL, flavor: CompatTool.Flavor) -> PrefixTools.WineLayout {
        PrefixTools.WineLayout(
            loader: root.appending(path: "lib/wine/x86_64-unix/wine"),
            server: root.appending(path: "bin/wineserver"),
            unixDir: root.appending(path: "lib/wine/x86_64-unix")
        )
    }

    func baseEnvironment(root: URL) -> [String: String] {
        let file = (try? String(contentsOf: root.appending(path: "runtime.env"), encoding: .utf8)) ?? ""
        return Self.parseEnvFile(file).merging(["CX_FWD_COMPAT_GL_CTX": "1", "WINEUSERNAME": "steamuser"]) { _, fixed in fixed }
    }

    func accessStatus(root: URL) -> CrossOverLicense.Status {
        CrossOverLicense.Status(licensed: true, detail: "", diagnostic: "highball: no licence")
    }

    static func parseEnvFile(_ text: String) -> [String: String] {
        var env: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.wholeMatch(of: #/[A-Z_][A-Z0-9_]*=.*/#) != nil,
                  let eq = line.firstIndex(of: "=") else { continue }
            env[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return env
    }
}
