import SwiftUI

/// One side of the end-screen duo. Captains have dedicated sad/gloat art;
/// player avatars get a rendered "soggy loser" treatment instead.
struct EndPortrait: Equatable {
    let imageName: String
    var renderSad: Bool = false
}

struct MatchEndView: View {
    let didWin: Bool
    var winner: EndPortrait = EndPortrait(imageName: "portrait_player")
    var loser: EndPortrait = EndPortrait(imageName: "portrait_dogbeard_sad")
    let title: String
    let message: String
    let coinReward: Int
    var firstWinBonus: Bool = false
    var showRematch: Bool = true
    let onRematch: () -> Void
    let onExit: () -> Void

    @State private var displayedCoins = 0
    @State private var winnerBounce = false

    /// Ink colors that read on each background's palette.
    private var titleColor: Color {
        didWin ? Color(red: 0.75, green: 0.5, blue: 0.08) : Color(red: 0.88, green: 0.92, blue: 1)
    }
    private var messageColor: Color {
        didWin ? Color(red: 0.45, green: 0.35, blue: 0.15) : Color(red: 0.8, green: 0.85, blue: 0.95)
    }

    var body: some View {
        ZStack {
            ScreenBackground(imageName: didWin ? "victory_background" : "defeat_background")

            if didWin {
                FallingConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else {
                RisingBubblesView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(0.4)
            }

            VStack(spacing: 28) {
                Spacer()

                // The gloat-and-sulk duo: victor front and center, loser
                // tucked in behind, tilted and (if no dedicated art) in tears.
                HStack(alignment: .bottom, spacing: -16) {
                    portraitCard(winner, size: 134, cornerRadius: 20)
                        .rotationEffect(.degrees(-3))
                        .scaleEffect(winnerBounce ? 1.0 : 0.92)
                        .zIndex(1)
                    portraitCard(loser, size: 94, cornerRadius: 15)
                        .rotationEffect(.degrees(9))
                        .offset(y: 10)
                }
                .onAppear {
                    withAnimation(.spring(duration: 0.5, bounce: 0.55).delay(0.15)) {
                        winnerBounce = true
                    }
                }

                Text(title)
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(titleColor)
                    .shadow(color: didWin ? .white.opacity(0.9) : .black.opacity(0.55), radius: 3, y: 1)
                Text(message)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(messageColor)
                    .shadow(color: didWin ? .white.opacity(0.8) : .black.opacity(0.5), radius: 2, y: 1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if coinReward > 0 {
                    VStack(spacing: 10) {
                        if didWin {
                            Image("treasure_chest")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 96)
                                .shadow(radius: 6, y: 3)
                        }
                        if firstWinBonus {
                            Label("First win of the day — 2× loot!", systemImage: "sunrise.fill")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.9), in: Capsule())
                        }
                        DoubloonLabel(amount: displayedCoins, fontSize: 32, prefix: "+")
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.3, green: 0.18, blue: 0.05).opacity(didWin ? 0.85 : 0.6))
                                    .strokeBorder(Color.yellow.opacity(0.5), lineWidth: 1.5)
                            )
                    }
                }

                Spacer()

                VStack(spacing: 14) {
                    if showRematch {
                        Button(action: onRematch) {
                            Label("Rematch", systemImage: "arrow.clockwise")
                                .font(.title3.weight(.bold))
                                .frame(maxWidth: 300)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button(action: onExit) {
                            Text("Main Menu")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: 300)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(didWin ? Color(red: 0.45, green: 0.3, blue: 0.1) : .white)
                    } else {
                        // Tutorial: onward to the real adventure.
                        Button(action: onExit) {
                            Label("Set Sail!", systemImage: "flag.checkered")
                                .font(.title3.weight(.bold))
                                .frame(maxWidth: 300)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .task {
            SoundService.shared.play(didWin ? .victory : .defeat)
            // Count the reward up in steps.
            try? await Task.sleep(for: .milliseconds(250))
            if coinReward > 0 {
                SoundService.shared.play(.coin)
            }
            let steps = 24
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(38))
                withAnimation(.linear(duration: 0.04)) {
                    displayedCoins = coinReward * i / steps
                }
            }
        }
    }

    /// A portrait card; `renderSad` applies the soggy-loser treatment for
    /// images that don't have dedicated sad art (player avatars).
    private func portraitCard(_ portrait: EndPortrait, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(portrait.imageName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .saturation(portrait.renderSad ? 0.25 : 1)
            .overlay {
                if portrait.renderSad {
                    Color(red: 0.25, green: 0.4, blue: 0.7).opacity(0.25)
                }
            }
            .overlay(alignment: .bottom) {
                if portrait.renderSad {
                    // A pair of cartoon tears rolling down.
                    HStack(spacing: size * 0.3) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: size * 0.14))
                            .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
                        Image(systemName: "drop.fill")
                            .font(.system(size: size * 0.11))
                            .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
                            .offset(y: -size * 0.08)
                    }
                    .offset(y: -size * 0.28)
                    .shadow(radius: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        portrait.renderSad ? Color(white: 0.7) : .white.opacity(0.85),
                        lineWidth: size > 100 ? 4 : 3
                    )
            )
            .shadow(radius: size > 100 ? 8 : 4, y: 3)
    }
}

#Preview("Win") {
    MatchEndView(didWin: true, title: "Victory!",
                 message: "Captain Pugbeard's fleet rests at the bottom of the tub.",
                 coinReward: 280, onRematch: {}, onExit: {})
}

#Preview("Loss") {
    MatchEndView(didWin: false, title: "Sunk!",
                 message: "Captain Pugbeard cackles as your last ship goes under.",
                 coinReward: 25, onRematch: {}, onExit: {})
}
