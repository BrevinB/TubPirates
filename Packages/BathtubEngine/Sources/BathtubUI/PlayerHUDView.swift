#if canImport(UIKit)
import SwiftUI

/// Portrait name-plate card, like the original's opponent/player frames.
///
/// Shared so the Messages battle shows the same two portraits the app does —
/// the rival top-left, you top-right, the active captain ringed in orange.
public struct PlayerHUDView: View {
    let imageName: String
    let name: String
    let highlighted: Bool
    /// Portrait edge, in points. The app draws it at 64; a Messages sheet on a
    /// small phone gives the arena less room, so the battle chrome scales the
    /// whole top band down rather than dropping pieces out of it.
    var side: CGFloat

    public init(imageName: String, name: String, highlighted: Bool, side: CGFloat = 64) {
        self.imageName = imageName
        self.name = name
        self.highlighted = highlighted
        self.side = side
    }

    public var body: some View {
        VStack(spacing: 0) {
            ArtworkImage(name: imageName, width: side, height: side, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(name)
                .font(.system(size: side * 0.203, weight: .heavy, design: .rounded))
                .foregroundStyle(TubPalette.ink)
                // A fixed plate that a long name wraps inside — the app's own
                // treatment, kept exactly. The scale floor is what a smaller
                // Messages portrait needs: forcing one line instead clipped
                // "Dogbeard" down to "ogbeard".
                .multilineTextAlignment(.center)
                .lineLimit(2)
                // A single long word ("Dogbeard") has nowhere to wrap, so the
                // plate has to be allowed to shrink it a long way — at the
                // smaller portrait a Messages sheet uses, a gentler floor left
                // the name overflowing and clipped to "ogbeard".
                .minimumScaleFactor(0.45)
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
                // Never let the strip squeeze the lettering vertically.
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: side * 1.156)
                .background(TubPalette.nameplate)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    highlighted ? TubPalette.accent : TubPalette.nameplateEdge,
                    lineWidth: highlighted ? 4 : 3
                )
        )
        .shadow(radius: 3, y: 2)
        .animation(.easeInOut(duration: 0.25), value: highlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(highlighted ? String(localized: "Their turn", bundle: .module) : "")
    }
}
#endif
