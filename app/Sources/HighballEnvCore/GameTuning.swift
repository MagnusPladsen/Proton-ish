// Applies a game's highball-db row and the launch-environment steps of its recipe, the parts of
// Highball's per-game fixes that need no Wine run. Steps that change the prefix come later (M2c).

import HighballKit

public enum GameTuning {

    public struct Result: Sendable {
        public var environment: [String: String] = [:]
        public var notes: [String] = []
    }

    public static func apply(entry: GameDBEntry, recipe: Recipe?, to settings: inout BottleSettings,
                             userEnvironment: [String: String], isAvailable: (Renderer) -> Bool) -> Result {
        var result = Result()
        result.notes.append("highball-db: \(entry.id) (\(entry.status))")

        let steps = recipe?.steps ?? []
        let stepRenderer = steps.compactMap { step -> Renderer? in
            if case .renderer(let renderer) = step { return renderer }
            return nil
        }.last
        let wanted = entry.effectiveRenderer() ?? recipe?.renderer ?? stepRenderer
        if let wanted {
            if let renderer = RecipeRunner.rendererToApply(recipeRenderer: wanted, settings: settings,
                                                           available: isAvailable(wanted)) {
                settings.renderer = renderer
                result.notes.append("highball-db renderer \(renderer.rawValue)")
            } else if settings.rendererExplicit {
                result.notes.append("highball-db suggests \(wanted.rawValue); your Graphics choice stands")
            } else {
                result.notes.append("highball-db suggests \(wanted.rawValue), which this engine can't run")
            }
        }

        var overrides: [String] = []
        for step in steps {
            switch step {
            case .environment(let name, let value):
                // Launch options and the run script's own variables win
                if userEnvironment[name] == nil { result.environment[name] = value }
            case .sync(let mode):
                if userEnvironment["WINEMSYNC"] == nil { settings.sync = mode }
            case .dllOverride(let entry):
                overrides.append(entry)
            case .dxvkConfig(let exe, let options):
                settings.dxvkAppConfig[exe, default: [:]].merge(options) { $1 }
            case .renderer, .note, .pin:
                break
            case .installer, .registry, .winetricks, .winver, .file, .copy:
                result.notes.append("highball-db step not applied yet: \(name(of: step))")
            }
        }
        if !overrides.isEmpty {
            // The user's own overrides stay last, so they win
            settings.dllOverrides = (overrides + [settings.dllOverrides]).filter { !$0.isEmpty }.joined(separator: ";")
        }
        return result
    }

    static func name(of step: Recipe.Step) -> String {
        switch step {
        case .installer: "installer"
        case .registry: "registry"
        case .winetricks: "winetricks"
        case .environment: "environment"
        case .renderer: "renderer"
        case .sync: "sync"
        case .winver: "winver"
        case .file: "file"
        case .copy: "copy"
        case .pin: "pin"
        case .note: "note"
        case .dllOverride: "dlloverride"
        case .dxvkConfig: "dxvkconfig"
        }
    }
}
