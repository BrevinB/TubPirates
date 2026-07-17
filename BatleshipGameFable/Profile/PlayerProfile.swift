import Foundation
import BathtubEngine

/// Everything that persists between sessions: the doubloon purse, the
/// consumable shot stash, avatars, ladder progress, and daily-reward claims.
struct PlayerProfile: Codable, Equatable {
    var coins: Int = 0
    /// Consumable uses owned per special shot. The basic cannon isn't tracked (always free).
    var shotInventory: [ShotType: Int] = PlayerProfile.starterInventory
    var wins: Int = 0
    var losses: Int = 0
    var avatarID: String = Avatar.defaultID
    /// Purchased avatar IDs (free avatars aren't tracked — they're always owned).
    var ownedAvatars: Set<String> = []
    /// Wins against each rival captain, for ladder progression.
    var captainWins: [String: Int] = [:]
    /// When the daily treasure chest was last claimed.
    var lastDailyChestClaim: Date?
    /// When the first-win-of-the-day bonus was last granted.
    var lastFirstWinBonus: Date?

    /// A few free uses so new captains learn how special shots work:
    /// intel (Parrot Scout) and damage (Big Shot Cannon).
    static let starterInventory: [ShotType: Int] = [.parrotScout: 2, .bigShot: 2]

    static let saveKey = "playerProfile.v1"

    init() {}

    // Manual decoding so profiles saved before a field existed still load
    // (synthesized Codable throws on any missing key).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coins = try container.decodeIfPresent(Int.self, forKey: .coins) ?? 0
        wins = try container.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        losses = try container.decodeIfPresent(Int.self, forKey: .losses) ?? 0
        avatarID = try container.decodeIfPresent(String.self, forKey: .avatarID) ?? Avatar.defaultID
        ownedAvatars = try container.decodeIfPresent(Set<String>.self, forKey: .ownedAvatars) ?? []
        captainWins = try container.decodeIfPresent([String: Int].self, forKey: .captainWins)
            ?? [:]
        lastDailyChestClaim = try container.decodeIfPresent(Date.self, forKey: .lastDailyChestClaim)
        lastFirstWinBonus = try container.decodeIfPresent(Date.self, forKey: .lastFirstWinBonus)

        if let inventory = try container.decodeIfPresent([ShotType: Int].self, forKey: .shotInventory) {
            shotInventory = inventory
        } else {
            // Migration from the permanent-unlock era: every previously
            // unlocked special converts to 3 consumable uses.
            let legacyKey = LegacyKeys.unlockedShots
            let legacy = (try? decoder.container(keyedBy: LegacyKeys.self))
                .flatMap { try? $0.decodeIfPresent(Set<ShotType>.self, forKey: legacyKey) } ?? []
            var inventory = PlayerProfile.starterInventory
            for shot in legacy where shot != .cannon {
                inventory[shot] = max(inventory[shot] ?? 0, 3)
            }
            shotInventory = inventory
        }

        // Ladder migration: lifetime wins predate per-captain tracking —
        // credit them to Dogbeard so veterans aren't re-locked.
        if captainWins.isEmpty, wins > 0 {
            captainWins["dogbeard"] = wins
        }
    }

    private enum LegacyKeys: String, CodingKey {
        case unlockedShots
    }
}
