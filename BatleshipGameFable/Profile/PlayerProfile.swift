import BathtubEngine

/// Everything that persists between sessions: the coin purse, unlocked arsenal,
/// and the captain's record.
struct PlayerProfile: Codable, Equatable {
    var coins: Int = 0
    var unlockedShots: Set<ShotType> = [.cannon]
    var wins: Int = 0
    var losses: Int = 0

    static let saveKey = "playerProfile.v1"
}
