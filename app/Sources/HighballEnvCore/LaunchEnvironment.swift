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
        public var exe: URL?
        public var paths: HighballPaths

        public init(prefix: URL, engineID: String, appID: Int?, environment: [String: String],
                    gameData: GameData? = nil, exe: URL? = nil, paths: HighballPaths = HighballPaths()) {
            self.prefix = prefix
            self.engineID = engineID
            self.appID = appID
            self.environment = environment
            self.gameData = gameData
            self.exe = exe
            self.paths = paths
        }
    }

    public static func lines(for request: Request) -> [String] {
        do {
            let engine = try EngineStore(paths: request.paths).engine(request.engineID)
            var settings = PanelSettings.bottleSettings(environment: request.environment, engineID: request.engineID)
            var notes: [String] = []
            var gameEnvironment: [String: String] = [:]
            var row: GameDBEntry?
            if let appID = request.appID, let entry = request.gameData?.entry(appID: appID) {
                row = entry
                let tuning = GameTuning.apply(
                    entry: entry, recipe: request.gameData?.recipe(for: entry), to: &settings,
                    userEnvironment: request.environment,
                    isAvailable: { $0.unavailableReason(in: engine) == nil })
                notes += tuning.notes
                gameEnvironment = tuning.environment
            }
            let bottle = Bottle(url: request.prefix, settings: settings)
            var resolved = try bottle.effectiveRenderer(requested: nil, engine: engine)
            if let note = resolved.note { notes.append(note) }
            // Highball's rule for a program that only has Direct3D 12: a Graphics choice the user
            // made for the game stands, a database row's mode stands, otherwise D3DMetal (or vkd3d)
            if let exe = request.exe,
               let takeOver = Renderer.direct3D12TakeOver(
                   chosen: resolved.renderer, requested: nil,
                   gameOverride: settings.rendererExplicit ? settings.renderer : nil,
                   row: row?.effectiveRenderer(), environmentExplicit: settings.rendererExplicit,
                   nativeVulkan: row?.nativeVulkan ?? false, engine: engine,
                   programNeedsDirect3D12: { ProgramNeeds.direct3D12Only(program: exe) }) {
                // Highball would ask for Apple's licence here; a Steam launch cannot, so it stays as it is
                if let why = takeOver.unavailableReason(in: engine) {
                    notes.append("\(exe.lastPathComponent) only has Direct3D 12, but \(why) Use Enable D3DMetal in Proton-ish.")
                } else {
                    notes.append("\(exe.lastPathComponent) only has Direct3D 12, running with \(Renderer.displayName(takeOver))")
                    resolved = (takeOver, nil)
                }
            }
            notes.append("renderer \(resolved.renderer.rawValue)")
            // The same steps WineRunner takes before every launch
            do { try bottle.prepareDLSSBridge(engine: engine, renderer: resolved.renderer) } catch {
                notes.append("DLSS left off: \(error)")
            }
            if resolved.renderer != .wined3d {
                do { try bottle.writeDxvkConfig() } catch { notes.append("dxvk.conf not written: \(error)") }
            }
            let highball = try bottle.environment(engine: engine, renderer: resolved.renderer, extra: gameEnvironment)
            return HighballEnvironment.lines(highball: highball, user: request.environment, notes: notes)
        } catch {
            return ["# error: " + HighballEnvironment.oneLine("\(error)")]
        }
    }
}
