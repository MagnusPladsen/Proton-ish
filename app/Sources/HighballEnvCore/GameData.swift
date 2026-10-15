// The bundled highball-db snapshot (CC0-1.0): Highball's per-game rows and game recipes.

import Foundation
import HighballKit

public struct GameData: Sendable {
    public let games: [GameDBEntry]
    public let recipes: [Recipe]
    public let commit: String

    public init(contentsOf url: URL) throws {
        try self.init(json: Data(contentsOf: url))
    }

    public init(json: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(Snapshot.self, from: json)
        games = file.games.compactMap(\.value)
        recipes = file.recipes.compactMap(\.value)
        commit = file.source.commit
    }

    public func entry(appID: Int) -> GameDBEntry? {
        games.first { $0.steam_appid == appID }
    }

    // Highball matches a game's recipe by the row's id
    public func recipe(for entry: GameDBEntry) -> Recipe? {
        recipes.first { $0.id == entry.id && $0.kind == .game }
    }

    private struct Snapshot: Decodable {
        struct Source: Decodable { let commit: String }
        let source: Source
        let games: [Lenient<GameDBEntry>]
        let recipes: [Lenient<Recipe>]
    }

    // One row Highball's model can't read must not cost every other game its fixes
    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }
}
