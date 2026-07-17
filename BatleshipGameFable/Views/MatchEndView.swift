import SwiftUI

struct MatchEndView: View {
    let didWin: Bool
    var winnerImageName: String = "portrait_player"
    let title: String
    let message: String
    let coinReward: Int
    let onRematch: () -> Void
    let onExit: () -> Void

    @State private var displayedCoins = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: didWin
                    ? [Color(red: 0.1, green: 0.5, blue: 0.3), Color(red: 0.05, green: 0.3, blue: 0.2)]
                    : [Color(red: 0.5, green: 0.15, blue: 0.15), Color(red: 0.3, green: 0.08, blue: 0.1)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(didWin ? winnerImageName : "portrait_dogbeard")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.8), lineWidth: 4))
                    .shadow(radius: 8)

                Text(title)
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                if coinReward > 0 {
                    VStack(spacing: 10) {
                        if didWin {
                            Image("treasure_chest")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 96)
                                .shadow(radius: 6, y: 3)
                        }
                        DoubloonLabel(amount: displayedCoins, fontSize: 32, prefix: "+")
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.3), in: Capsule())
                    }
                }

                Spacer()

                VStack(spacing: 14) {
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
                    .tint(.white)
                }

                Spacer()
            }
            .padding()
        }
        .task {
            // Count the reward up in steps.
            let steps = 24
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(38))
                withAnimation(.linear(duration: 0.04)) {
                    displayedCoins = coinReward * i / steps
                }
            }
        }
    }
}

#Preview("Win") {
    MatchEndView(didWin: true, title: "Victory!",
                 message: "Dogbeard's fleet rests at the bottom of the tub.",
                 coinReward: 280, onRematch: {}, onExit: {})
}

#Preview("Loss") {
    MatchEndView(didWin: false, title: "Sunk!",
                 message: "Dogbeard cackles as your last ship goes under.",
                 coinReward: 25, onRematch: {}, onExit: {})
}
