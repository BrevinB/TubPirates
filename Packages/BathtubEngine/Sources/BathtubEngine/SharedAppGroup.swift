import Foundation

/// The container the app and its iMessage extension both read.
///
/// Extensions get their own `UserDefaults.standard`, so without this the
/// extension could not see the player's analytics opt-out and would keep
/// reporting after they switched it off. Every shared preference goes here.
///
/// Lives in the engine package because both targets already link it — the
/// extension's sources are a synchronized folder, so shared code has to
/// arrive through a package rather than a stray file membership.
public enum SharedAppGroup {
    public static let identifier = "group.co.brevinb.TubPirates"

    /// Non-nil only when this target is actually entitled to the group.
    /// `UserDefaults(suiteName:)` hands back an object either way, so the
    /// container URL is what really answers the question.
    ///
    /// Computed rather than cached: `UserDefaults` isn't `Sendable`, and this
    /// is read a handful of times per session, so the lookup is not worth
    /// smuggling shared mutable state past the concurrency checker.
    public static var defaults: UserDefaults? {
        guard FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
        else { return nil }
        return UserDefaults(suiteName: identifier)
    }

    public static var isAvailable: Bool { defaults != nil }

    // MARK: - Analytics opt-out

    public static let analyticsEnabledKey = "analyticsEnabled"

    /// The player's choice as the *extension* must read it: opted in only when
    /// the app has positively written so. An unprovisioned App Group, or a
    /// profile that has never launched the app, both read as "do not report".
    public static var analyticsEnabledForExtension: Bool {
        defaults?.object(forKey: analyticsEnabledKey) as? Bool ?? false
    }

    /// Called by the app whenever the toggle is set, and once at launch, so the
    /// extension's view of the setting never goes stale.
    public static func publishAnalyticsEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: analyticsEnabledKey)
    }

    // MARK: - Appearance

    /// What the player looks like across the whole game: the avatar on their
    /// name-plate and the cosmetic fleet their toys are drawn from.
    ///
    /// The profile itself lives in the app's own `UserDefaults`, which the
    /// extension cannot read — so a Messages battle used to show a stock ship
    /// and no portrait at all while the app showed the captain they'd bought.
    /// The app mirrors just these two ids here.
    public struct Appearance: Codable, Hashable, Sendable {
        public var avatarID: String
        public var fleetID: String

        public init(avatarID: String, fleetID: String) {
            self.avatarID = avatarID
            self.fleetID = fleetID
        }

        /// What a player with no published profile looks like.
        public static let `default` = Appearance(avatarID: "portrait_player", fleetID: "classic")
    }

    public static let appearanceKey = "playerAppearance"

    public static var appearance: Appearance {
        guard let data = defaults?.data(forKey: appearanceKey),
              let decoded = try? JSONDecoder().decode(Appearance.self, from: data)
        else { return .default }
        return decoded
    }

    /// Called by the app on every profile save.
    public static func publishAppearance(_ appearance: Appearance) {
        guard let data = try? JSONEncoder().encode(appearance) else { return }
        defaults?.set(data, forKey: appearanceKey)
    }

    // MARK: - Haptics

    public static let hapticsEnabledKey = "hapticsEnabled"

    /// Mirrored for the extension the same way the analytics opt-out is.
    /// Unlike analytics this fails *open* — haptics are a comfort setting,
    /// not consent, and the shipped default is on.
    public static func publishHapticsEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: hapticsEnabledKey)
    }
}
