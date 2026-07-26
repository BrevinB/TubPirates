import SwiftUI
import GameKit
import BathtubEngine

/// The themed online hub — replaces the stock Game Center matchmaker sheet.
/// Lists your turn-based matches as parchment cards (rival's avatar + name +
/// whose turn), with programmatic auto-matchmaking and friend invites.
struct OnlineHarborView: View {
    @Binding var path: [Route]
    @State private var gameCenter = GameCenterService.shared
    @State private var matches: [HarborMatch] = []
    @State private var isLoading = true
    @State private var isFindingMatch = false
    @State private var showInviteSheet = false
    @State private var abandonTarget: HarborMatch?

    private let parchment = Color(red: 1, green: 0.96, blue: 0.85)
    private let ink = Color(red: 0.35, green: 0.2, blue: 0.08)
    private let inkSoft = Color(red: 0.45, green: 0.3, blue: 0.15)
    private let cream = Color(red: 1, green: 0.94, blue: 0.8)

    /// A match row, pre-digested for the card UI.
    struct HarborMatch: Identifiable {
        let id: String
        let match: GKTurnBasedMatch
        let opponentName: String?
        let opponentAvatarID: String?
        let isYourTurn: Bool
        let isSearching: Bool
        let isEnded: Bool
        let localWon: Bool
    }

    var body: some View {
        ZStack {
            ScreenBackground(imageName: "cabin_background")

            ScrollView {
                VStack(spacing: 16) {
                    Text("The Harbor")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(cream)
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
                    Text("Yer battles across the seven tubs")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(cream.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)

                    if !gameCenter.isAuthenticated {
                        signInCard
                    } else {
                        findBattleButton
                        inviteFriendButton

                        if isLoading {
                            ProgressView()
                                .tint(cream)
                                .padding(.top, 30)
                        } else if matches.isEmpty {
                            emptyStateCard
                        } else {
                            ForEach(matches) { entry in
                                matchCard(entry)
                            }
                        }
                    }
                }
                .padding()
                .padding(.top, 24)
                .contentColumn()
            }
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: gameCenter.matchListVersion) {
            await refresh()
        }
        .sheet(isPresented: $showInviteSheet) {
            MatchmakerSheet(
                onMatch: { match in
                    showInviteSheet = false
                    Task { await open(match) }
                },
                onCancel: { showInviteSheet = false }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Abandon this battle?",
            isPresented: Binding(
                get: { abandonTarget != nil },
                set: { if !$0 { abandonTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Abandon Ship", role: .destructive) {
                if let target = abandonTarget {
                    Task {
                        await gameCenter.forfeit(target.match)
                        await refresh()
                    }
                }
                abandonTarget = nil
            }
            Button("Keep Fighting", role: .cancel) { abandonTarget = nil }
        } message: {
            Text("Yer rival will be handed the win.")
        }
    }

    // MARK: - Cards

    private var signInCard: some View {
        VStack(spacing: 12) {
            Image("portrait_player")
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("Battle captains around the world!")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
            Text("Sign in to Game Center to set sail against real rivals.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(inkSoft)
                .multilineTextAlignment(.center)
            Button {
                gameCenter.authenticate()
            } label: {
                Label("Sign In", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(parchmentCard)
    }

    private var findBattleButton: some View {
        Button {
            guard !isFindingMatch else { return }
            isFindingMatch = true
            SoundService.shared.play(.tap)
            Task {
                defer { isFindingMatch = false }
                if let match = try? await gameCenter.findMatch() {
                    await open(match)
                }
            }
        } label: {
            Label(
                isFindingMatch ? "Scanning the seas..." : "Find a Battle!",
                systemImage: isFindingMatch ? "sailboat" : "flag.checkered"
            )
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(isFindingMatch)
    }

    private var inviteFriendButton: some View {
        Button {
            showInviteSheet = true
        } label: {
            Label("Invite a Friend", systemImage: "person.2.fill")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
        .tint(cream)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 8) {
            Text("⚓️")
                .font(.system(size: 40))
            Text("No battles underway")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
            Text("Find a rival and stake yer claim on the tub!")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(inkSoft)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(parchmentCard)
    }

    private func matchCard(_ entry: HarborMatch) -> some View {
        Button {
            Task { await open(entry.match) }
        } label: {
            HStack(spacing: 12) {
                Image(entry.opponentAvatarID ?? "portrait_player")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(entry.isYourTurn ? Color.orange : .white.opacity(0.7), lineWidth: 2.5)
                    )
                    .saturation(entry.isSearching ? 0.3 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.opponentName ?? "Searching for a rival...")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(statusLine(entry))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor(entry))
                }

                Spacer(minLength: 0)

                if entry.isYourTurn {
                    Text("YOUR TURN")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.orange, in: Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.55, green: 0.38, blue: 0.2))
                }
            }
            .padding(12)
            .background(parchmentCard)
            .opacity(entry.isEnded ? 0.8 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                abandonTarget = entry
            } label: {
                Label(entry.isEnded ? "Remove from Harbor" : "Abandon Ship", systemImage: "flag.slash")
            }
        }
    }

    private var parchmentCard: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(parchment)
            .strokeBorder(Color(red: 0.6, green: 0.42, blue: 0.22), lineWidth: 2.5)
            .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
    }

    private func statusLine(_ entry: HarborMatch) -> String {
        if entry.isEnded { return entry.localWon ? "Victory! Their fleet sleeps below." : "Sunk. Revenge awaits..." }
        if entry.isSearching { return "An open challenge drifts at sea" }
        if entry.isYourTurn { return "The cannon's loaded — fire away!" }
        return "Waiting on their move..."
    }

    private func statusColor(_ entry: HarborMatch) -> Color {
        if entry.isEnded { return entry.localWon ? .green : .red }
        if entry.isYourTurn { return Color(red: 0.7, green: 0.4, blue: 0.1) }
        return inkSoft
    }

    // MARK: - Data

    private func refresh() async {
        guard gameCenter.isAuthenticated else {
            isLoading = false
            return
        }
        let loaded = await gameCenter.loadAllMatches()
        let localID = GKLocalPlayer.local.gamePlayerID
        var rows: [HarborMatch] = []
        for match in loaded {
            let opponent = match.participants.first { $0.player?.gamePlayerID != localID }
            let localParticipant = match.participants.first { $0.player?.gamePlayerID == localID }
            let seat = gameCenter.localSeat(in: match)
            let opponentKey = seat == .one ? "1" : "0"
            let data = MatchDataCodec.decode(match.matchData)
            rows.append(HarborMatch(
                id: match.matchID,
                match: match,
                opponentName: opponent?.player?.displayName,
                opponentAvatarID: data.avatars?[opponentKey],
                isYourTurn: match.status == .open
                    && match.currentParticipant?.player?.gamePlayerID == localID,
                isSearching: opponent?.player == nil,
                isEnded: match.status == .ended,
                localWon: localParticipant?.matchOutcome == .won
            ))
        }
        // Your-turn matches surface first, then live ones, then history.
        matches = rows.sorted { a, b in
            if a.isEnded != b.isEnded { return !a.isEnded }
            if a.isYourTurn != b.isYourTurn { return a.isYourTurn }
            return a.id < b.id
        }
        isLoading = false
    }

    private func open(_ match: GKTurnBasedMatch) async {
        let route = await gameCenter.destination(for: match)
        path.append(route)
    }
}

#Preview {
    NavigationStack {
        OnlineHarborView(path: .constant([]))
    }
}
