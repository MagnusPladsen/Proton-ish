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
        public var gameData: GameData?
        public var paths: HighballPaths

        public init(prefix: URL, engineID: String, appID: Int?, environment: [String: String],
                    gameData: GameData? = nil, paths: HighballPaths = HighballPaths()) {
            self.prefix = prefix
            self.engineID = engineID
            self.appID = appID
            self.environment = environment
            self.gameData = gameData
            self.paths = paths
        }
    }

    public static func lines(for request: Request) -> [String] {
        do {
            let engine = try EngineStore(paths: request.paths).engine(request.engineID)
            var settings = PanelSettings.bottleSettings(environment: request.environment, engineID: request.engineID)
            var notes: [String] = []
            var gameEnvironment: [String: String] = [:]
            if let appID = request.appID, let entry = request.gameData?.entry(appID: appID) {
                let tuning = GameTuning.apply(
                    entry: entry, recipe: request.gameData?.recipe(for: entry), to: &settings,
                    userEnvironment: request.environment,
                    isAvailable: { $0.unavailableReason(in: engine) == nil })
                notes += tuning.notes
                gameEnvironment = tuning.environment
            }
            let bottle = Bottle(url: request.prefix, settings: settings)
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
            let highball = try bottle.environment(engine: engine, extra: gameEnvironment)
            return HighballEnvironment.lines(highball: highball, user: request.environment, notes: notes)
        } catch {
            return ["# error: " + HighballEnvironment.oneLine("\(error)")]
        }
    }
}
