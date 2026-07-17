import Foundation
import BathtubEngine

/// A local match frozen mid-battle so the player can leave and come back.
/// AI and pass-and-play only — online matches already live on Game Center's servers.
struct SavedMatch: Codable {
    enum SavedMode: String, Codable {
        case ai
        case passAndPlay
    }

    var mode: SavedMode
    var state: GameState
    var activePlayer: PlayerID
    var loadout: Set<ShotType>
    /// Which rival the battle is against (optional so pre-ladder saves decode).
    var captainID: String?
}

enum MatchSaveStore {
    private static let key = "savedMatch.v1"

    static var hasSave: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    static func load() -> SavedMatch? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedMatch.self, from: data)
    }

    static func save(_ match: SavedMatch) {
        guard let data = try? JSONEncoder().encode(match) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
