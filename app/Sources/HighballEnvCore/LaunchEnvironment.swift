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
        // The prefix steps of the game's recipe (M2c): the game's folder, the marker of the last
        // applied recipe, where the .reg file goes, and whether another engine line's recipe applies
        public var installPath: URL?
        public var recipeMarker: URL?
        public var registryFile: URL?
        public var otherEngines: Bool

        public init(prefix: URL, engineID: String, appID: Int?, environment: [String: String],
                    gameData: GameData? = nil, exe: URL? = nil, paths: HighballPaths = HighballPaths(),
                    installPath: URL? = nil, recipeMarker: URL? = nil, registryFile: URL? = nil, otherEngines: Bool = true) {
            self.prefix = prefix
            self.engineID = engineID
            self.appID = appID
            self.environment = environment
            self.gameData = gameData
            self.exe = exe
            self.paths = paths
            self.installPath = installPath
            self.recipeMarker = recipeMarker
            self.registryFile = registryFile
            self.otherEngines = otherEngines
        }
    }

    public static func lines(for request: Request) -> [String] {
        do {
            let engine = try EngineStore(paths: request.paths).engine(request.engineID)
            var settings = PanelSettings.bottleSettings(environment: request.environment, engineID: request.engineID)
            var notes: [String] = []
            var record: String?
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
                if let recipe = request.gameData?.recipe(for: entry) {
                    let outcome = PrefixRecipe.run(recipe: recipe, context: .init(
                        driveC: request.prefix.appending(path: "drive_c"), engineRoot: engine.root, engineID: request.engineID,
                        dbCommit: request.gameData?.commit ?? "", installPath: request.installPath, marker: request.recipeMarker,
                        registryFile: request.registryFile, otherEngines: request.otherEngines))
                    notes += outcome.notes
                    // "partial": the run script imports the registry file but records nothing
                    record = outcome.record.map { outcome.complete ? $0 : $0 + " partial" }
                }
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
            var output = HighballEnvironment.lines(highball: highball, user: request.environment, notes: notes)
            if let record { output.insert("# recipe: " + record, at: 0) }
            return output
        } catch {
            return ["# error: " + HighballEnvironment.oneLine("\(error)")]
        }
    }
}
