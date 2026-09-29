#if canImport(UIKit)
import BathtubEngine
import UIKit

/// One switch for every buzz: all haptic feedback routes through the app's
/// Settings toggle (on by default, key `hapticsEnabled`).
///
/// The toggle is read through `SharedAppGroup` so the Messages extension —
/// which has its own `UserDefaults` domain and would otherwise never see the
/// switch — honors it too. Placement in the extension buzzes exactly as it
/// does in the app, which is half of why the two feel like one game.
public enum TubHaptics {
    public static var isEnabled: Bool {
        // The app writes to both domains; prefer the shared one, and fall back
        // to the local domain so the app keeps working unprovisioned.
        if let shared = SharedAppGroup.defaults?.object(forKey: SharedAppGroup.hapticsEnabledKey) as? Bool {
            return shared
        }
        let defaults = UserDefaults.standard
        return defaults.object(forKey: SharedAppGroup.hapticsEnabledKey) == nil
            || defaults.bool(forKey: SharedAppGroup.hapticsEnabledKey)
    }

    public static func impact(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium,
        intensity: CGFloat? = nil
    ) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        if let intensity {
            generator.impactOccurred(intensity: intensity)
        } else {
            generator.impactOccurred()
        }
    }

    public static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
#endif
