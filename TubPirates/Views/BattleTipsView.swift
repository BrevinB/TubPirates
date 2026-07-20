import SwiftUI

/// One-time coach marks for the first battle: three tap-through parchment
/// cards pointing at the enemy board, your fleet, and the shot panel.
struct BattleTipsView: View {
    let onFinish: () -> Void
    @State private var step = 0

    private struct Tip {
        let text: String
        /// Where the card sits vertically (0 = top, 1 = bottom).
        let anchor: CGFloat
        /// Which way the little arrow points.
        let arrow: String
    }

    private static let tips: [Tip] = [
        Tip(
            text: "That big diamond be MY water, matey! Tap any tile to fire yer cannon at me hidden fleet.",
            anchor: 0.18,
            arrow: "arrow.down"
        ),
        Tip(
            text: "Yer own toys hide in the suds down there — I'll be firin' back after every shot o' yers!",
            anchor: 0.62,
            arrow: "arrow.down.left"
        ),
        Tip(
            text: "Special cannons! Tap one to arm it, then tap me water. Hold yer finger on one to read what it does. Stock more in the Armory!",
            anchor: 0.45,
            arrow: "arrow.down.right"
        ),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dim the battle; also swallows taps so the scene can't fire.
                Color.black.opacity(0.45)
                    .ignoresSafeArea()

                let tip = Self.tips[step]
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image("portrait_dogbeard")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange, lineWidth: 2.5))

                        Text(tip.text)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.05))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Image(systemName: tip.arrow)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color(red: 0.6, green: 0.42, blue: 0.22))
                        Spacer()
                        Text(step < Self.tips.count - 1 ? "Tap to continue (\(step + 1)/\(Self.tips.count))" : "Tap to battle!")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.6, green: 0.42, blue: 0.22))
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 1, green: 0.96, blue: 0.85))
                        .strokeBorder(Color(red: 0.6, green: 0.42, blue: 0.22), lineWidth: 2.5)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                )
                .padding(.horizontal, 24)
                .position(x: geo.size.width / 2, y: geo.size.height * tip.anchor)
                .id(step) // fresh card per step so transitions don't crossfade text
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if step < Self.tips.count - 1 {
                    withAnimation(.spring(duration: 0.3)) { step += 1 }
                } else {
                    onFinish()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tutorial: \(Self.tips[step].text)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ZStack {
        Color.blue
        BattleTipsView(onFinish: {})
    }
}
