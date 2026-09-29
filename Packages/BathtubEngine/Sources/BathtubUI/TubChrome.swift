#if canImport(UIKit)
import SwiftUI

/// The top band's state pill.
///
/// Same parchment family as the speech pill, so the top band reads as one
/// object that alternates between game state and table talk (a translucent
/// black capsule looked like system chrome in a pirate tub).
public struct StatusBannerView: View {
    let text: String
    /// The app draws 14.5; the Messages sheet shrinks it on a short screen.
    var fontSize: CGFloat

    public init(_ text: String, fontSize: CGFloat = 14.5) {
        self.text = text
        self.fontSize = fontSize
    }

    public var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(TubPalette.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(TubPalette.banner)
                    .strokeBorder(TubPalette.bannerEdge, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

/// The small parchment capsule the match screen uses for Leave and Chat.
/// The Messages battle uses it for Forfeit, so the two screens' secondary
/// controls are the same object rather than a stock button and a custom one.
public struct TubCapsuleButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var fontSize: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    public init(
        title: String,
        systemImage: String,
        fontSize: CGFloat = 13,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.fontSize = fontSize
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(TubPalette.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(TubPalette.banner)
                        .strokeBorder(TubPalette.bannerEdge, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .opacity(isEnabled ? 1 : 0.45)
                .hitTarget()
        }
        .buttonStyle(.plain)
    }
}

/// The match screen's primary action, in the game's own lettering.
///
/// The app spells this as `.borderedProminent` tinted orange; this is that
/// button with the pirate rounding, used for "Battle!", "Fire", "Challenge a
/// Friend" and "Rematch" so every commit button in the game is one shape.
public struct TubPrimaryButton: View {
    public enum Kind {
        case primary
        case secondary
    }

    let title: String
    var systemImage: String?
    var kind: Kind = .primary
    /// Overrides the fill, for a row of buttons that the game colour-codes —
    /// the blue Randomize beside the orange Battle!, as the app does.
    var fill: Color?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    public init(
        title: String,
        systemImage: String? = nil,
        kind: Kind = .primary,
        fill: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.fill = fill
        self.action = action
    }

    /// The app's secondary action blue.
    public static let actionBlue = Color(red: 0.25, green: 0.5, blue: 0.75)

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(fill != nil || kind == .primary ? TubPalette.cream : TubPalette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: HIG.minimumHitTarget)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fill ?? (kind == .primary ? TubPalette.accent : TubPalette.banner))
                    .strokeBorder(
                        kind == .primary ? TubPalette.gold : TubPalette.bannerEdge,
                        lineWidth: 2
                    )
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}
#endif
