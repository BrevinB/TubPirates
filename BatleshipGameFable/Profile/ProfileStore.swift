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
    var unlockedShots: Set<ShotType> { profile.unlockedShots }

    func isUnlocked(_ shot: ShotType) -> Bool {
        profile.unlockedShots.contains(shot)
    }

    func award(coins amount: Int) {
        profile.coins += amount
        save()
    }

    func recordResult(won: Bool) {
        if won { profile.wins += 1 } else { profile.losses += 1 }
        save()
    }

    /// Spends coins to unlock a shot. Returns false when it can't be afforded.
    @discardableResult
    func unlock(_ shot: ShotType) -> Bool {
        guard !isUnlocked(shot), profile.coins >= shot.spec.coinCost else { return false }
        profile.coins -= shot.spec.coinCost
        profile.unlockedShots.insert(shot)
        save()
        return true
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
