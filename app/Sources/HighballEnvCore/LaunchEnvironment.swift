// The launch environment Highball would give a game in a Steam prefix, computed by Highball's own
// code from the user's Highball install.

import Foundation
import HighballKit

public enum LaunchEnvironment {

    public struct Request: Sendable {
        public var prefix: URL
        public var engineID: String
        public var appID: Int?
        public var environment: [String: String]
        public var paths: HighballPaths

        public init(prefix: URL, engineID: String, appID: Int?, environment: [String: String],
                    paths: HighballPaths = HighballPaths()) {
            self.prefix = prefix
            self.engineID = engineID
            self.appID = appID
            self.environment = environment
            self.paths = paths
        }
    }

    public static func lines(for request: Request) -> [String] {
        do {
            let engine = try EngineStore(paths: request.paths).engine(request.engineID)
            let settings = PanelSettings.bottleSettings(environment: request.environment, engineID: request.engineID)
            let bottle = Bottle(url: request.prefix, settings: settings)
            var notes: [String] = []
            let resolved = try bottle.effectiveRenderer(requested: nil, engine: engine)
            if let note = resolved.note { notes.append(note) }
            notes.append("renderer \(resolved.renderer.rawValue)")
            // The same steps WineRunner takes before every launch
            do { try bottle.prepareDLSSBridge(engine: engine, renderer: resolved.renderer) } catch {
                notes.append("DLSS left off: \(error)")
            }
            if resolved.renderer != .wined3d {
                do { try bottle.writeDxvkConfig() } catch { notes.append("dxvk.conf not written: \(error)") }
            }
            let highball = try bottle.environment(engine: engine)
            return HighballEnvironment.lines(highball: highball, user: request.environment, notes: notes)
        } catch {
            return ["# error: " + HighballEnvironment.oneLine("\(error)")]
        }
    }
}
