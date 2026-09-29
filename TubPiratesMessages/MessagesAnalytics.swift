import BathtubEngine
import Foundation
import TelemetryDeck

/// The extension's own analytics sender.
///
/// It cannot reuse the app's `Analytics` type: extension sources are a
/// synchronized folder, and more importantly the extension has a separate
/// `UserDefaults` domain, so the opt-out has to come through the App Group.
///
/// Fails closed. If the App Group isn't provisioned, or the player has never
/// launched the app, `analyticsEnabledForExtension` is false and nothing is
/// reported — a silent no-op is the right outcome, never a signal the player
/// didn't agree to.
enum MessagesAnalytics {
    private static let appID = "6E6BA07C-F27F-466F-9DEA-8D968C74FFF3"

    private static var isConfigured = false

    static func send(_ event: MessageAnalyticsEvent) {
        guard SharedAppGroup.analyticsEnabledForExtension else { return }
        if !isConfigured {
            TelemetryDeck.initialize(config: .init(appID: appID))
            isConfigured = true
        }
        TelemetryDeck.signal(event.name, parameters: event.parameters)
    }
}
