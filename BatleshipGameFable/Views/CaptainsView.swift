import SwiftUI
import BathtubEngine

/// The captain ladder: pick a rival to battle. Beat each captain enough
/// times to unlock the next, tougher one — with richer rewards.
struct CaptainsView: View {
    let baseConfig: MatchConfig
    @Binding var path: [Route]
    @Environment(ProfileStore.self) private var profileStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.35, blue: 0.6), Color(red: 0.05, green: 0.2, blue: 0.4)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text("Choose Your Rival")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Sink a captain's fleet 3 times to face the next!")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))

                    ForEach(Captain.roster) { captain in
                        captainCard(captain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func captainCard(_ captain: Captain) -> some View {
        let unlocked = profileStore.isUnlocked(captain)
        let wins = profileStore.wins(against: captain)

        return Button {
            guard unlocked else { return }
            var config = baseConfig
            config.captainID = captain.id
            path.append(.placement(config))
        } label: {
            HStack(spacing: 14) {
                Image(captain.portrait)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(unlocked ? Color.orange : .gray, lineWidth: 3)
                    )
                    .saturation(unlocked ? 1 : 0)
                    .overlay {
                        if !unlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                        }
                    }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(captain.name)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        difficultyStars(captain.tier)
                    }
                    Text(captain.blurb)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    if unlocked {
                        HStack(spacing: 10) {
                            winPips(wins: wins, needed: captain.winsToAdvance, hasNext: captain.next != nil)
                            Spacer()
                            HStack(spacing: 3) {
                                Image("coin_doubloon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 13, height: 13)
                                Text(captain.rewardMultiplier == 1
                                     ? "×1"
                                     : String(format: "×%.1f", captain.rewardMultiplier))
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.yellow)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.3), in: Capsule())
                        }
                    } else if let index = Captain.roster.firstIndex(of: captain), index > 0 {
                        let previous = Captain.roster[index - 1]
                        Text("Defeat \(previous.name) ×\(previous.winsToAdvance) to unlock")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 0)

                if unlocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 1, opacity: unlocked ? 0.12 : 0.05))
                    .strokeBorder(Color(white: 1, opacity: 0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(unlocked
            ? "\(captain.name), \(wins) wins"
            : "\(captain.name), locked")
    }

    private func difficultyStars(_ tier: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<Captain.roster.count, id: \.self) { index in
                Image(systemName: index < tier ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }
        }
    }

    /// Progress toward unlocking the next rung (or a lifetime tally at the top).
    private func winPips(wins: Int, needed: Int, hasNext: Bool) -> some View {
        HStack(spacing: 4) {
            if hasNext {
                ForEach(0..<needed, id: \.self) { index in
                    Image(systemName: index < wins ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(index < wins ? .green : .white.opacity(0.4))
                }
                if wins >= needed {
                    Text("Next rival unlocked!")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
            } else {
                Text("\(wins) wins")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

#Preview {
    NavigationStack {
        CaptainsView(baseConfig: MatchConfig(), path: .constant([]))
            .environment(ProfileStore())
    }
}
