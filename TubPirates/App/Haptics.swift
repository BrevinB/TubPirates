import BathtubUI
import UIKit

/// The app's spelling of the shared haptics switch.
///
/// The implementation lives in `BathtubUI.TubHaptics` so the Messages
/// extension buzzes on exactly the same rules; this stays as the name the
/// app's own call sites already use.
enum Haptics {
    static var isEnabled: Bool { TubHaptics.isEnabled }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, intensity: CGFloat? = nil) {
        TubHaptics.impact(style, intensity: intensity)
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        TubHaptics.notify(type)
    }
}
