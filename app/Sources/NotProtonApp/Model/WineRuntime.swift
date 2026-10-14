// The Wine distribution a runner is copied from

import Foundation

enum RuntimeKind: String, Sendable, CaseIterable {
    case crossover
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
    var runtime: any WineRuntime {
        switch self {
        case .crossover: CrossOverRuntime()
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
