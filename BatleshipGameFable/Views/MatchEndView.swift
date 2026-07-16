import SwiftUI

struct MatchEndView: View {
    let didWin: Bool
    let onRematch: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: didWin
                    ? [Color(red: 0.1, green: 0.5, blue: 0.3), Color(red: 0.05, green: 0.3, blue: 0.2)]
                    : [Color(red: 0.5, green: 0.15, blue: 0.15), Color(red: 0.3, green: 0.08, blue: 0.1)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Text(didWin ? "🏆" : "💦")
                    .font(.system(size: 90))
                Text(didWin ? "Victory!" : "Sunk!")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(didWin
                     ? "Dogbeard's fleet rests at the bottom of the tub."
                     : "Dogbeard cackles as your last ship goes under.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

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
    }
}

#Preview("Win") {
    MatchEndView(didWin: true, onRematch: {}, onExit: {})
}

#Preview("Loss") {
    MatchEndView(didWin: false, onRematch: {}, onExit: {})
}
