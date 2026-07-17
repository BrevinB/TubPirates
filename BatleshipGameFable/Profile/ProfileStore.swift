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

    func award(coins amount: Int) {
        profile.coins += amount
        save()
    }

    func recordResult(won: Bool) {
        if won { profile.wins += 1 } else { profile.losses += 1 }
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
