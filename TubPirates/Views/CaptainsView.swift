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
            ScreenBackground(imageName: "cabin_background")

            ScrollView {
                VStack(spacing: 18) {
                    Text("Choose Your Rival")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.94, blue: 0.8))
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
                    Text("Sink each captain's fleet to face the next rival!")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(red: 1, green: 0.94, blue: 0.8).opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)

                    // Wanted posters pinned to the cabin wall.
                    ForEach(Array(Captain.roster.enumerated()), id: \.element.id) { index, captain in
                        captainCard(captain)
                            .rotationEffect(.degrees(index.isMultiple(of: 2) ? -1.0 : 1.1))
                    }
                }
                .padding()
                .padding(.top, 30)
                .contentColumn()
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
                        Text(captain.localizedName)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.08))
                        difficultyStars(captain.tier)
                    }
                    Text(captain.localizedBlurb)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.45, green: 0.3, blue: 0.15))
                        .fixedSize(horizontal: false, vertical: true)

                    if unlocked {
                        HStack(spacing: 10) {
                            winPips(wins: wins, needed: captain.winsToAdvance)
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
                            .background(Color(red: 0.35, green: 0.2, blue: 0.08), in: Capsule())
                        }
                        // Status on its own full-width line: squeezed beside
                        // the pips and reward chip it truncated to "Nex t r…".
                        if let (caption, color) = progressCaption(for: captain, wins: wins) {
                            Text(caption)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if let index = Captain.roster.firstIndex(of: captain), index > 0 {
                        let previous = Captain.roster[index - 1]
                        Text("Defeat \(previous.localizedName) ×\(previous.winsToAdvance) to unlock")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 0)

                if unlocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(red: 0.55, green: 0.38, blue: 0.2))
                }
            }
            .padding(12)
            .background(
                // Parchment poster nailed to the wall.
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 1, green: 0.96, blue: 0.85).opacity(unlocked ? 1 : 0.72))
                    .strokeBorder(Color(red: 0.6, green: 0.42, blue: 0.22), lineWidth: 2.5)
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
            )
            .overlay(alignment: .top) {
                // The nail pinning the poster up.
                Circle()
                    .fill(Color(white: 0.45))
                    .strokeBorder(Color(white: 0.25), lineWidth: 1.5)
                    .frame(width: 11, height: 11)
                    .offset(y: -5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(unlocked
            ? String(localized: "\(captain.localizedName), \(wins) wins")
            : String(localized: "\(captain.localizedName), locked"))
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

    /// Progress toward this rung's goal: the next rival, or — on the final
    /// rung — the champion's trophy fleet. (The last captain used to show a
    /// bare lifetime tally, hiding the Gilded Armada's requirement.)
    private func winPips(wins: Int, needed: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<needed, id: \.self) { index in
                Image(systemName: index < wins ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(index < wins ? Color.green : Color(red: 0.6, green: 0.45, blue: 0.28))
            }
        }
    }

    /// The line under the pips saying what filling them earns.
    private func progressCaption(for captain: Captain, wins: Int) -> (String, Color)? {
        let done = wins >= captain.winsToAdvance
        if captain.next != nil {
            return done ? (String(localized: "Next rival unlocked!"), .green) : nil
        }
        // Final rung: the ladder-champion trophy.
        return done
            ? (String(localized: "The Gilded Armada is yours!"), .green)
            : (String(localized: "Win ×\(captain.winsToAdvance) to claim the Gilded Armada fleet"), Color(red: 0.72, green: 0.5, blue: 0.12))
    }
}

#Preview {
    NavigationStack {
        CaptainsView(baseConfig: MatchConfig(), path: .constant([]))
            .environment(ProfileStore())
    }
}
