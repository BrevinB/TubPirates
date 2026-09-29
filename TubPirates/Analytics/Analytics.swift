import BathtubEngine
import Foundation
import TelemetryDeck

/// Thin wrapper around TelemetryDeck: anonymized, privacy-first product
/// analytics (no PII, no device IDs we manage, no ATT prompt needed).
/// All call sites go through here so the SDK stays swappable and the
/// opt-out toggle is enforced in one place.
enum Analytics {
    /// TelemetryDeck App ID (dashboard.telemetrydeck.com → Tub Pirates).
    private static let appID = "6E6BA07C-F27F-466F-9DEA-8D968C74FFF3"

    private static var isConfigured = false

    /// Player-controlled opt-out (Settings → Privacy). Default: on.
    /// The app owns the setting; the extension reads it through the App Group.
    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: SharedAppGroup.analyticsEnabledKey) == nil
            || defaults.bool(forKey: SharedAppGroup.analyticsEnabledKey)
    }

    /// Call once at app start. Safe to call again after the toggle flips on.
    static func start() {
        // Mirror the setting where the extension can read it, including the
        // default-on case for players who never opened the privacy toggle.
        SharedAppGroup.publishAnalyticsEnabled(isEnabled)
        guard !isConfigured, isEnabled, !appID.hasPrefix("YOUR-") else { return }
        // In DEBUG the SDK auto-enters test mode, so dev signals stay out of
        // production charts.
        TelemetryDeck.initialize(config: .init(appID: appID))
        isConfigured = true
    }

    static func signal(_ name: String, _ parameters: [String: String] = [:]) {
        guard isConfigured, isEnabled else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }

    // MARK: - Game signals (the whole taxonomy lives here, greppable)

    static func battleStarted(mode: String, captainID: String?, isTutorial: Bool) {
        signal("Battle.started", [
            "mode": mode,
            "captain": captainID ?? "none",
            "tutorial": String(isTutorial),
        ])
    }

    static func battleFinished(mode: String, captainID: String?, won: Bool, reward: Int, isTutorial: Bool) {
        signal("Battle.finished", [
            "mode": mode,
            "captain": captainID ?? "none",
            "won": String(won),
            "reward": String(reward),
            "tutorial": String(isTutorial),
        ])
    }

    static func specialFired(_ shotName: String) {
        signal("Battle.specialFired", ["shot": shotName])
    }

    static func purchase(kind: String, itemID: String, price: Int) {
        signal("Economy.purchase", [
            "kind": kind, // shot | avatar | fleet
            "item": itemID,
            "price": String(price),
        ])
    }

    static func dailyChestClaimed(amount: Int) {
        signal("Economy.dailyChest", ["amount": String(amount)])
    }

    static func onboardingFinished(skipped: Bool) {
        signal("Onboarding.welcomeFinished", ["skipped": String(skipped)])
    }

    static func battleTipsFinished() {
        signal("Onboarding.tipsFinished")
    }

    static func reviewPrompted(milestone: Int) {
        signal("Review.prompted", ["milestone": String(milestone)])
    }

    // MARK: - iMessage extension (the friend-to-friend loop)

    /// Renders a shared `MessageAnalyticsEvent`. The extension sends the same
    /// cases through its own sender, so both ends report one taxonomy.
    static func messages(_ event: MessageAnalyticsEvent) {
        signal(event.name, event.parameters)
    }

    static func captainDefeated(_ captainID: String, totalWins: Int) {
        signal("Ladder.captainDefeated", [
            "captain": captainID,
            "winsAgainst": String(totalWins),
        ])
    }
}
