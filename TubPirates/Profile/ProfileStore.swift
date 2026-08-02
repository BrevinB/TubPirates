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
        // Trophies added in updates reach veterans who already qualify.
        syncEarnedCosmetics()
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
        if profile.ownedAvatars.contains(avatar.id) { return true }
        // Free starters — but trophies must be earned, never assumed.
        return avatar.price == 0 && avatar.earnedBy == nil
    }

    /// Buys a premium avatar. Returns false when unaffordable, already owned,
    /// or a trophy (earned-only, no price can touch it).
    @discardableResult
    func buyAvatar(_ avatar: Avatar) -> Bool {
        guard avatar.earnedBy == nil else { return false }
        guard !owns(avatar), profile.coins >= avatar.price else { return false }
        profile.coins -= avatar.price
        profile.ownedAvatars.insert(avatar.id)
        profile.avatarID = avatar.id // equipping your new treasure immediately feels right
        save()
        Analytics.purchase(kind: "avatar", itemID: avatar.id, price: avatar.price)
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

    #if DEBUG
    /// Debug launch arg: grant + equip without cost.
    func debugGrantFleet(_ fleet: FleetSkin) {
        profile.ownedFleets.insert(fleet.id)
        profile.fleetID = fleet.id
        save()
    }

    /// Debug: clear every ladder rung (champion state).
    /// Debug: "-wins dogbeard=3,soapySal=2" sets exact per-captain win counts.
    func debugSetWins(_ spec: String) {
        var wins: [String: Int] = [:]
        for pair in spec.split(separator: ",") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let count = Int(parts[1]) {
                wins[String(parts[0])] = count
            }
        }
        profile.captainWins = wins
        save()
    }

    func debugConquerLadder() {
        for captain in Captain.roster {
            profile.captainWins[captain.id] = max(
                profile.captainWins[captain.id] ?? 0, captain.winsToAdvance
            )
        }
        save()
        syncEarnedCosmetics()
    }

    /// Debug: own every avatar and fleet skin at once.
    func debugUnlockAllCosmetics() {
        profile.ownedAvatars = Set(Avatar.all.map(\.id))
        profile.ownedFleets = Set(FleetSkin.all.map(\.id))
        save()
    }
    #endif

    /// Grants any trophy cosmetics whose criteria are now met. Idempotent;
    /// called after results are recorded and at load.
    func syncEarnedCosmetics() {
        var changed = false
        if isLadderChampion, !profile.ownedFleets.contains(FleetSkin.gilded.id) {
            profile.ownedFleets.insert(FleetSkin.gilded.id)
            changed = true
        }
        if profile.wins >= 25, !profile.ownedAvatars.contains("avatar_duck_king") {
            profile.ownedAvatars.insert("avatar_duck_king")
            changed = true
        }
        if changed { save() }
    }

    /// Buys and equips in one step (like avatars). Trophy fleets refuse money.
    @discardableResult
    func buyFleet(_ fleet: FleetSkin) -> Bool {
        guard fleet.earnedBy == nil else { return false }
        guard !owns(fleet), profile.coins >= fleet.price else { return false }
        profile.coins -= fleet.price
        profile.ownedFleets.insert(fleet.id)
        profile.fleetID = fleet.id
        save()
        Analytics.purchase(kind: "fleet", itemID: fleet.id, price: fleet.price)
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

    /// The furthest rival the player has unlocked — the face of the menu.
    var currentRival: Captain {
        Captain.roster.last { isUnlocked($0) } ?? .dogbeard
    }

    /// Every rung of the ladder cleared — the tub is conquered.
    var isLadderChampion: Bool {
        Captain.roster.allSatisfy { wins(against: $0) >= $0.winsToAdvance }
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
    var hasPickedCaptain: Bool { profile.hasPickedCaptain }

    func markWelcomeSeen() {
        profile.hasSeenWelcome = true
        save()
    }

    func markBattleTipsSeen() {
        profile.hasSeenBattleTips = true
        save()
    }

    func markCaptainPicked() {
        profile.hasPickedCaptain = true
        save()
    }

    /// Settings: replay the welcome + first-battle tips (and the
    /// pick-yer-captain moment that follows them).
    func resetOnboarding() {
        profile.hasSeenWelcome = false
        profile.hasSeenBattleTips = false
        profile.hasPickedCaptain = false
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
        profile.lifetimeDoubloons += reward
        save()
        Analytics.dailyChestClaimed(amount: reward)
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
        if amount > 0 {
            profile.lifetimeDoubloons += amount
        }
        save()
    }

    /// Merges the specials fired this battle into the lifetime record.
    func recordSpecialsFired(_ shots: Set<ShotType>) {
        let new = shots.subtracting(profile.firedSpecials)
        guard !new.isEmpty else { return }
        profile.firedSpecials.formUnion(new)
        save()
    }

    func recordResult(won: Bool, againstCaptainID: String? = nil) {
        if won {
            profile.wins += 1
            if let id = againstCaptainID {
                profile.captainWins[id, default: 0] += 1
                Analytics.captainDefeated(id, totalWins: profile.captainWins[id, default: 0])
            }
        } else {
            profile.losses += 1
        }
        save()
        syncEarnedCosmetics()
    }

    /// Buys one use of a shot. Returns false when it can't be afforded.
    @discardableResult
    func buyUse(of shot: ShotType) -> Bool {
        guard shot.spec.coinCost > 0, profile.coins >= shot.spec.coinCost else { return false }
        profile.coins -= shot.spec.coinCost
        profile.shotInventory[shot, default: 0] += 1
        save()
        Analytics.purchase(kind: "shot", itemID: String(describing: shot), price: shot.spec.coinCost)
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
