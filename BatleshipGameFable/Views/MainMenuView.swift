import SwiftUI
import GameKit
import BathtubEngine

struct MainMenuView: View {
    @Binding var path: [Route]
    @Environment(ProfileStore.self) private var profileStore
    @State private var gameCenter = GameCenterService.shared
    @State private var showMatchmaker = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.35, blue: 0.6), Color(red: 0.05, green: 0.2, blue: 0.4)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                HStack {
                    coinChip
                    Spacer()
                    recordChip
                }

                Spacer()

                VStack(spacing: 8) {
                    Image("portrait_dogbeard")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 130, height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.orange, lineWidth: 4))
                        .shadow(radius: 8)
                    Text("Bathtub Battles")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Dogbeard awaits...")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                VStack(spacing: 14) {
                    menuButton("Battle Dogbeard!", icon: "flag.checkered", tint: .orange) {
                        path.append(.placement(MatchConfig(
                            mode: .ai,
                            loadout: profileStore.unlockedShots
                        )))
                    }
                    menuButton("Pass & Play", icon: "person.2.fill", tint: .teal) {
                        path.append(.match(MatchConfig(
                            mode: .passAndPlay,
                            loadout: profileStore.unlockedShots
                        )))
                    }
                    menuButton("Online Battle", icon: "globe.americas.fill", tint: .indigo) {
                        if gameCenter.isAuthenticated {
                            showMatchmaker = true
                        } else {
                            gameCenter.authenticate()
                        }
                    }
                    menuButton("Armory", icon: "shield.lefthalf.filled", tint: .blue) {
                        path.append(.armory)
                    }
                    menuButton("Settings", icon: "gearshape.fill", tint: .gray) {
                        path.append(.settings)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $showMatchmaker) {
            MatchmakerSheet(
                onMatch: { match in
                    showMatchmaker = false
                    Task { await routeToOnlineMatch(match) }
                },
                onCancel: { showMatchmaker = false }
            )
            .ignoresSafeArea()
        }
    }

    /// New matches go to placement first; rejoining a match with our fleet already
    /// placed goes straight to the battle.
    private func routeToOnlineMatch(_ match: GKTurnBasedMatch) async {
        let service = GameCenterService.shared
        service.register(match)
        let seat = service.localSeat(in: match)
        _ = service.controller(for: match.matchID) ?? service.makeController(for: match, localPlayer: seat)

        let data = (try? await GameCenterController.loadGame(from: match)) ?? OnlineMatchData()
        let seatKey = seat == .one ? "0" : "1"
        let config = MatchConfig(mode: .gameCenter(matchID: match.matchID), loadout: Set(ShotType.allCases))
        if data.boards[seatKey] == nil {
            path.append(.placement(config))
        } else {
            path.append(.match(config))
        }
    }

    private var coinChip: some View {
        HStack(spacing: 6) {
            Text("🪙")
            Text("\(profileStore.coins)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.3), in: Capsule())
    }

    private var recordChip: some View {
        Text("\(profileStore.profile.wins)W – \(profileStore.profile.losses)L")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.3), in: Capsule())
    }

    private func menuButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.bold))
                .frame(maxWidth: 300)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }
}

#Preview {
    NavigationStack {
        MainMenuView(path: .constant([]))
            .environment(ProfileStore())
    }
}
