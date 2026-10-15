import Foundation
import HighballKit
import Testing

@testable import HighballEnvCore

@Suite("Per-game fixes from highball-db")
struct GameTuningTests {

    static let snapshot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "third_party/highball-db/highball-db.json")

    private func data(games: [[String: Any]], recipes: [[String: Any]] = []) throws -> GameData {
        let json: [String: Any] = ["source": ["commit": "abc123"], "games": games, "recipes": recipes]
        return try GameData(json: JSONSerialization.data(withJSONObject: json))
    }

    private func row(_ id: String, appID: Int, renderer: String? = nil) -> [String: Any] {
        var row: [String: Any] = ["id": id, "title": id, "steam_appid": appID, "status": "community"]
        if let renderer { row["renderer"] = renderer }
        return row
    }

    private func tune(_ data: GameData, appID: Int, user: [String: String] = [:],
                      available: Set<Renderer> = [.dxmt, .d3dmetal, .dxvk, .wined3d]) throws -> (BottleSettings, GameTuning.Result) {
        var settings = PanelSettings.bottleSettings(environment: user, engineID: "x64-crossover26.3-r19")
        let entry = try #require(data.entry(appID: appID))
        let result = GameTuning.apply(entry: entry, recipe: data.recipe(for: entry), to: &settings,
                                      userEnvironment: user, isAvailable: { available.contains($0) })
        return (settings, result)
    }

    @Test("The bundled snapshot decodes, every row and recipe")
    func snapshotDecodes() throws {
        let data = try GameData(contentsOf: Self.snapshot)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.snapshot)) as? [String: Any]
        #expect(data.games.count == (raw?["games"] as? [Any])?.count)
        #expect(data.recipes.count == (raw?["recipes"] as? [Any])?.count)
        #expect(data.entry(appID: 1086940)?.id == "baldur-s-gate-3")
    }

    @Test("On Automatic the database's renderer for the game is used")
    func rowRenderer() throws {
        let (settings, result) = try tune(data(games: [row("bg3", appID: 1086940, renderer: "d3dmetal")]), appID: 1086940)
        #expect(settings.renderer == .d3dmetal)
        #expect(result.notes.contains("highball-db renderer d3dmetal"))
    }

    @Test("A Graphics choice the user made beats the database")
    func userRendererWins() throws {
        let (settings, _) = try tune(data(games: [row("bg3", appID: 1086940, renderer: "d3dmetal")]), appID: 1086940,
                                     user: ["CX_GRAPHICS_BACKEND": "dxvk"])
        #expect(settings.renderer == .dxvk)
    }

    @Test("A database renderer the engine can't run is not applied")
    func unavailableRenderer() throws {
        let (settings, result) = try tune(data(games: [row("bg3", appID: 1086940, renderer: "d3dmetal")]), appID: 1086940,
                                          available: [.dxmt, .wined3d])
        #expect(settings.renderer == .dxmt)
        #expect(result.notes.contains { $0.contains("can't run") })
    }

    @Test("A recipe's environment, overrides, sync and DXVK options apply; the user's overrides stay last")
    func recipeSteps() throws {
        let recipe: [String: Any] = ["id": "game", "kind": "game", "title": "Game", "steps": [
            ["type": "environment", "name": "D3DM_VENDOR_ID", "value": "0x10de"],
            ["type": "dlloverride", "value": "amd_ags_x64="],
            ["type": "sync", "sync": "none"],
            ["type": "dxvkconfig", "exe": "game.exe", "options": ["dxgi.maxFrameRate": "60"]],
        ]]
        let (settings, result) = try tune(data(games: [row("game", appID: 42)], recipes: [recipe]), appID: 42,
                                          user: ["WINEDLLOVERRIDES": "d3d11=b"])
        #expect(result.environment == ["D3DM_VENDOR_ID": "0x10de"])
        #expect(settings.dllOverrides == "amd_ags_x64=;d3d11=b")
        #expect(settings.sync == SyncMode.none)
        #expect(settings.dxvkAppConfig["game.exe"]?["dxgi.maxFrameRate"] == "60")
    }

    @Test("A variable the user or run script already set is not replaced by a recipe")
    func recipeEnvironmentYields() throws {
        let recipe: [String: Any] = ["id": "game", "kind": "game", "title": "Game", "steps": [
            ["type": "environment", "name": "D3DM_VENDOR_ID", "value": "0x10de"],
        ]]
        let (_, result) = try tune(data(games: [row("game", appID: 42)], recipes: [recipe]), appID: 42,
                                   user: ["D3DM_VENDOR_ID": "0x1002"])
        #expect(result.environment.isEmpty)
    }

    @Test("Steps that change the prefix are reported, not run")
    func prefixStepsSkipped() throws {
        let recipe: [String: Any] = ["id": "game", "kind": "game", "title": "Game", "steps": [
            ["type": "registry", "key": "HKCU\\Software\\Wine", "name": "x", "valueType": "REG_SZ", "data": "y"],
            ["type": "winetricks", "verbs": ["vcrun2019"]],
        ]]
        let (_, result) = try tune(data(games: [row("game", appID: 42)], recipes: [recipe]), appID: 42)
        #expect(result.notes.contains("highball-db step not applied yet: registry"))
        #expect(result.notes.contains("highball-db step not applied yet: winetricks"))
    }

    @Test("A game the database does not know gets nothing")
    func unknownGame() throws {
        #expect(try data(games: [row("bg3", appID: 1086940)]).entry(appID: 7) == nil)
    }
}
