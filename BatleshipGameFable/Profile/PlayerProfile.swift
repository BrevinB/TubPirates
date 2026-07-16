import BathtubEngine

/// Everything that persists between sessions: the coin purse, unlocked arsenal,
/// and the captain's record.
struct PlayerProfile: Codable, Equatable {
    var coins: Int = 0
    var unlockedShots: Set<ShotType> = PlayerProfile.starterShots
    var wins: Int = 0
    var losses: Int = 0

    /// Free from the first battle so new captains learn how special shots work:
    /// one intel shot (Parrot Scout) and one damage shot (Big Shot Cannon).
    static let starterShots: Set<ShotType> = [.cannon, .parrotScout, .bigShot]

    static let saveKey = "playerProfile.v1"
}
