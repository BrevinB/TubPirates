#if canImport(UIKit)
import SwiftUI

public enum HIG {
    /// Apple's floor for anything tappable.
    public static let minimumHitTarget: CGFloat = 44
}

/// How wide the battle chrome is allowed to spread.
///
/// `ArenaScene` letterboxes its composition in a wide window (see
/// `maxStageAspect`), so the HUD has to track the stage instead of flinging
/// the portraits into the far corners of an iPad. The app's match screen has
/// always capped at this; the Messages sheet now uses the same number, which
/// is what makes the two read as one layout on every device.
public enum TubStage {
    public static let hudMaxWidth: CGFloat = 520
    public static let contentMaxWidth: CGFloat = 600
}

extension View {
    /// Caps a content column at a readable width and centers it — cards on
    /// iPad stretched into full-width planks without this.
    public func contentColumn(_ maxWidth: CGFloat = TubStage.contentMaxWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// Caps the battle chrome to the letterboxed arena stage and centers it.
    public func stageColumn() -> some View {
        frame(maxWidth: TubStage.hudMaxWidth)
            .frame(maxWidth: .infinity)
    }

    /// Grows a control's hit region to the 44x44pt HIG minimum without
    /// changing how big it looks. Apply to the Button's *label*, so the
    /// padding lands inside the tappable area.
    public func hitTarget(
        minWidth: CGFloat = HIG.minimumHitTarget,
        minHeight: CGFloat = HIG.minimumHitTarget
    ) -> some View {
        frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(Rectangle())
    }

    /// Decorative, never-ending motion (bubbles, confetti, the bobbing
    /// title) that holds still when the player has asked the system to
    /// reduce motion. Gameplay feedback keeps animating — only the
    /// ambient flourish is suppressed.
    public func decorativeMotion() -> some View {
        modifier(DecorativeMotion())
    }
}

private struct DecorativeMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0 : 1)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
#endif
