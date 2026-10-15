// Downloads a Highball engine and records Apple's D3DMetal licence, with Highball's own EngineStore,
// into Highball's standard folder so the Highball app and Proton-ish share the engine.

import Foundation
import HighballKit

public enum EngineInstall {

    public static var d3dmetalLicence: String { EngineManifest.gatedRenderers["d3dmetal"] ?? "apple-gptk-license-2023-08-17" }

    /// The licence is passed only when the user accepted it; an acceptance the user already gave on
    /// another installed engine carries over, as in Highball.
    public static func install(manifest url: URL, acceptD3DMetal: Bool, paths: HighballPaths = HighballPaths(),
                               report: @escaping @Sendable (String) -> Void) async throws -> String {
        let manifest = try EngineManifest.load(from: url)
        guard manifest.runs(onMacOS: EngineManifest.currentMacOS) else {
            throw HighballError.invalid("\(manifest.id) needs macOS \(manifest.minMacOS) or newer")
        }
        let throttle = ProgressThrottle()
        let engine = try await EngineStore(paths: paths).install(
            manifest, accepted: acceptD3DMetal ? [d3dmetalLicence] : []
        ) { component, got, total in
            if let line = throttle.line(component: component, got: got, total: total) { report(line) }
        }
        return engine.id
    }

    public static func accept(engineID: String, paths: HighballPaths = HighballPaths()) throws {
        let store = EngineStore(paths: paths)
        _ = try store.accept(license: d3dmetalLicence, engine: try store.engine(engineID))
    }

    // One line per whole percent of a component, so the app's progress bar moves without a flood
    final class ProgressThrottle: @unchecked Sendable {
        private let lock = NSLock()
        private var printed: [String: Int64] = [:]

        func line(component: String, got: Int64, total: Int64?) -> String? {
            lock.lock()
            defer { lock.unlock() }
            let step = max((total ?? 0) / 100, 1 << 20)
            let last = printed[component] ?? -step
            guard got - last >= step || got == total else { return nil }
            printed[component] = got
            return "progress \(component) \(got) \(total ?? 0)"
        }
    }
}
