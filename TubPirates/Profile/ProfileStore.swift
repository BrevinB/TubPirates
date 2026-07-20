import Foundation
import Observation
import BathtubEngine

/// UserDefaults-backed profile store; saved on every mutation.
@Observable @MainActor
final class ProfileStore {
    private(set) var profile: PlayerProfile

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: PlayerProfile.saveKey),
           let decoded = try? JSONDecoder().decode(PlayerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = PlayerProfile()
        }
    }

    var coins: Int { profile.coins }
    var avatarID: String { profile.avatarID }

    /// Shots that can go into a battle loadout right now (cannon + stocked specials).
    var loadoutShots: Set<ShotType> {
        var shots: Set<ShotType> = [.cannon]
        for (shot, count) in profile.shotInventory where count > 0 {
            shots.insert(shot)
        }
        return shots
    }

    func inventory(of shot: ShotType) -> Int {
        profile.shotInventory[shot] ?? 0
    }

    func setAvatar(_ id: String) {
        profile.avatarID = id
        save()
    }

    // MARK: - Avatars

    func owns(_ avatar: Avatar) -> Bool {
        avatar.price == 0 || profile.ownedAvatars.contains(avatar.id)
    }

    /// Buys a premium avatar. Returns false when unaffordable or already owned.
    @discardableResult
    func buyAvatar(_ avatar: Avatar) -> Bool {
        guard !owns(avatar), profile.coins >= avatar.price else { return false }
        profile.coins -= avatar.price
        profile.ownedAvatars.insert(avatar.id)
        profile.avatarID = avatar.id // equipping your new treasure immediately feels right
        save()
        return true
    }

    // MARK: - Captain ladder

    // MARK: - Fleet skins

    var fleet: FleetSkin { FleetSkin.withID(profile.fleetID) }

    func owns(_ fleet: FleetSkin) -> Bool {
        profile.ownedFleets.contains(fleet.id)
    }

    func setFleet(_ fleet: FleetSkin) {
        guard owns(fleet) else { return }
        profile.fleetID = fleet.id
        save()
    }

    /// Debug launch arg: grant + equip without cost.
    func debugGrantFleet(_ fleet: FleetSkin) {
        profile.ownedFleets.insert(fleet.id)
        profile.fleetID = fleet.id
        save()
    }

    /// Debug: own every avatar and fleet skin at once.
    func debugUnlockAllCosmetics() {
        profile.ownedAvatars = Set(Avatar.all.map(\.id))
        profile.ownedFleets = Set(FleetSkin.all.map(\.id))
        save()
    }

    /// Buys and equips in one step (like avatars).
    @discardableResult
    func buyFleet(_ fleet: FleetSkin) -> Bool {
        guard !owns(fleet), profile.coins >= fleet.price else { return false }
        profile.coins -= fleet.price
        profile.ownedFleets.insert(fleet.id)
        profile.fleetID = fleet.id
        save()
        return true
    }

    /// Ladder-gated armory stock: the big booms arrive as captains fall,
    /// so beating a rival also unlocks new toys to buy.
    func armoryRequirement(for shot: ShotType) -> Captain? {
        switch shot {
        case .chainShot: .dogbeard
        case .fireworks: .soapySal
        default: nil
        }
    }

    func isShotInStock(_ shot: ShotType) -> Bool {
        guard let requirement = armoryRequirement(for: shot) else { return true }
        return wins(against: requirement) >= requirement.winsToAdvance
    }

    func wins(against captain: Captain) -> Int {
        profile.captainWins[captain.id] ?? 0
    }

    /// A captain is battle-able when every earlier rung has been cleared.
    func isUnlocked(_ captain: Captain) -> Bool {
        guard let index = Captain.roster.firstIndex(of: captain) else { return false }
        return Captain.roster[..<index].allSatisfy {
            wins(against: $0) >= $0.winsToAdvance
        }
    }

    // MARK: - Onboarding

    var hasSeenWelcome: Bool { profile.hasSeenWelcome }
    var hasSeenBattleTips: Bool { profile.hasSeenBattleTips }

    func markWelcomeSeen() {
        profile.hasSeenWelcome = true
        save()
    }

    func markBattleTipsSeen() {
        profile.hasSeenBattleTips = true
        save()
    }

    /// Settings: replay the welcome + first-battle tips.
    func resetOnboarding() {
        profile.hasSeenWelcome = false
        profile.hasSeenBattleTips = false
        save()
    }

    // MARK: - Daily rewards

    var isDailyChestAvailable: Bool {
        guard let last = profile.lastDailyChestClaim else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    /// Claims the daily chest. Returns the doubloons awarded (0 if already claimed).
    func claimDailyChest() -> Int {
        guard isDailyChestAvailable else { return 0 }
        let reward = Int.random(in: 15...30) * 5 // 75...150 in doubloon-y steps
        profile.lastDailyChestClaim = Date()
        profile.coins += reward
        save()
        return reward
    }

    /// True when the next AI-battle win doubles its reward.
    var isFirstWinBonusAvailable: Bool {
        guard let last = profile.lastFirstWinBonus else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    /// Consumes today's first-win bonus. Returns whether it applied.
    func claimFirstWinBonus() -> Bool {
        guard isFirstWinBonusAvailable else { return false }
        profile.lastFirstWinBonus = Date()
        save()
        return true
    }

    func award(coins amount: Int) {
        profile.coins += amount
        save()
    }

    func recordResult(won: Bool, againstCaptainID: String? = nil) {
        if won {
            profile.wins += 1
            if let id = againstCaptainID {
                profile.captainWins[id, default: 0] += 1
            }
        } else {
            profile.losses += 1
        }
        save()
    }

    /// Buys one use of a shot. Returns false when it can't be afforded.
    @discardableResult
    func buyUse(of shot: ShotType) -> Bool {
        guard shot.spec.coinCost > 0, profile.coins >= shot.spec.coinCost else { return false }
        profile.coins -= shot.spec.coinCost
        profile.shotInventory[shot, default: 0] += 1
        save()
        return true
    }

    /// Consumes one use after the shot is actually fired in battle.
    func consumeUse(of shot: ShotType) {
        guard shot != .cannon, inventory(of: shot) > 0 else { return }
        profile.shotInventory[shot, default: 0] -= 1
        save()
    }

    func resetProfile() {
        profile = PlayerProfile()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: PlayerProfile.saveKey)
        }
    }
}
