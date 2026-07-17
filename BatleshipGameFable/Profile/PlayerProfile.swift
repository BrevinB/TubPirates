import BathtubEngine

/// Everything that persists between sessions: the coin purse, unlocked arsenal,
/// chosen avatar, and the captain's record.
struct PlayerProfile: Codable, Equatable {
    var coins: Int = 0
    var unlockedShots: Set<ShotType> = PlayerProfile.starterShots
    var wins: Int = 0
    var losses: Int = 0
    var avatarID: String = Avatar.defaultID

    /// Free from the first battle so new captains learn how special shots work:
    /// one intel shot (Parrot Scout) and one damage shot (Big Shot Cannon).
    static let starterShots: Set<ShotType> = [.cannon, .parrotScout, .bigShot]

    static let saveKey = "playerProfile.v1"

    init() {}

    // Manual decoding so profiles saved before a field existed still load
    // (synthesized Codable throws on any missing key).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coins = try container.decodeIfPresent(Int.self, forKey: .coins) ?? 0
        unlockedShots = try container.decodeIfPresent(Set<ShotType>.self, forKey: .unlockedShots)
            ?? PlayerProfile.starterShots
        wins = try container.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        losses = try container.decodeIfPresent(Int.self, forKey: .losses) ?? 0
        avatarID = try container.decodeIfPresent(String.self, forKey: .avatarID) ?? Avatar.defaultID
    }
}
