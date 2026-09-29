import BathtubUI
import SwiftUI

struct MessagesRootView: View {
    @Bindable var model: MessagesExtensionModel
    let requestExpanded: () -> Void
    let startChallenge: () -> Void
    let joinChallenge: () -> Void
    let fire: () -> Void
    let forfeit: () -> Void
    let rematch: () -> Void

    var body: some View {
        ZStack {
            // The arena paints its own tub backdrop, so drawing the same
            // full-size art underneath it decoded ~17MB twice inside an
            // extension that cannot afford it once.
            if !isShowingArena {
                background
            }

            if model.isExpanded, model.screen == .battle {
                // The arena owns the whole sheet, exactly as it owns the whole
                // screen in the app — the HUD floats over it.
                BattleScreenView(
                    model: model,
                    fire: fire,
                    forfeit: forfeit,
                    rematch: rematch
                )
            } else if model.isExpanded {
                // Placement sizes itself off the real sheet; it must not go in
                // a ScrollView or the board can never measure a stable height.
                ExpandedMessageContentView(
                    model: model,
                    startChallenge: startChallenge,
                    joinChallenge: joinChallenge
                )
            } else {
                compact
            }
        }
    }

    /// The battle screen is a full-bleed SpriteKit surface that covers
    /// everything behind it.
    private var isShowingArena: Bool { model.isExpanded && model.screen == .battle }

    private var background: some View {
        GeometryReader { geo in
            ZStack {
                ArtworkImage(
                    name: model.backgroundArtworkName,
                    width: geo.size.width,
                    height: geo.size.height,
                    contentMode: .fill,
                    maxPixelDimension: 1400
                )
                // The app's placement screen puts its controls straight onto
                // the key art, so this stays a light scrim rather than the
                // heavy navy wash the sheet used to carry.
                LinearGradient(
                    colors: [.white.opacity(0.12), .clear, .black.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
        }
        .ignoresSafeArea()
    }

    /// The drawer strip: short, always fits, and never wrapped in a ScrollView
    /// (that pushed it up behind the message field).
    private var compact: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ArtworkImage(name: "ship_5", width: 66, height: 44)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Tub Pirates")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(TubPalette.deepSea)
                        .shadow(color: .white.opacity(0.8), radius: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(model.statusMessage)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(TubPalette.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TubPrimaryButton(
                title: model.compactActionTitle,
                systemImage: "arrow.up.left.and.arrow.down.right",
                action: requestExpanded
            )
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
