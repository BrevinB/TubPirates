import BathtubUI
import SwiftUI

/// A waiting or error state, on the app's parchment.
struct MessageStatusView: View {
    let title: String
    let systemImage: String
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .tint(TubPalette.ink)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(TubPalette.bannerEdge)
            }

            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(TubPalette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(TubPalette.banner)
                .strokeBorder(TubPalette.bannerEdge, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        .accessibilityElement(children: .combine)
    }
}
