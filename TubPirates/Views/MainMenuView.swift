import SwiftUI
import GameKit
import BathtubEngine

struct MainMenuView: View {
    @Binding var path: [Route]
    @Environment(ProfileStore.self) private var profileStore
    @State private var gameCenter = GameCenterService.shared
    @State private var showMatchmaker = false
    @State private var showAvatarPicker = false
    @State private var hasSavedMatch = MatchSaveStore.hasSave
    @State private var claimedChestAmount: Int?

    private var debugAllShots: Bool {
        UserDefaults.standard.bool(forKey: "debugAllShots")
    }

    /// Debug builds can force-arm every cannon from Settings (no consumption).
    private var battleLoadout: Set<ShotType> {
        debugAllShots ? Set(ShotType.allCases) : profileStore.loadoutShots
    }

    /// Drives the gentle floating rock of the title.
    @State private var titleBob = false

    var body: some View {
        ZStack {
            // The tub: your current rival peeks over the far rim — the menu
            // itself is a progression trophy that changes as you climb.
            GeometryReader { geo in
                Image(profileStore.isLadderChampion
                      ? "menu_champion"
                      : profileStore.currentRival.menuBackground)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            RisingBubblesView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                HStack {
                    coinChip
                    Spacer()
                    avatarChip
                    recordChip
                }

                Spacer(minLength: 40)

                VStack(spacing: 4) {
                    Text("Tub Pirates")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.52))
                        .shadow(color: .white.opacity(0.9), radius: 2)
                        .shadow(color: .white.opacity(0.7), radius: 8)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(profileStore.isLadderChampion
                         ? "The tub is yours, Captain!"
                         : "\(profileStore.currentRival.name) awaits...")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                        .shadow(color: .white.opacity(0.8), radius: 3)
                }
                // Bob like a toy on the water.
                .rotationEffect(.degrees(titleBob ? 1.6 : -1.6))
                .offset(y: titleBob ? -3 : 3)
                .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: titleBob)
                .onAppear { titleBob = true }

                Spacer(minLength: 8)

                dailyChestCard

                VStack(spacing: 11) {
                    if hasSavedMatch {
                        menuButton("Resume Battle", icon: "play.fill", tint: .green) {
                            path.append(.match(MatchConfig(
                                mode: .ai,
                                loadout: battleLoadout,
                                consumesInventory: !debugAllShots,
                                resume: true
                            )))
                        }
                    }
                    menuButton("Battle!", icon: "flag.checkered", tint: .orange) {
                        path.append(.captains(MatchConfig(
                            mode: .ai,
                            loadout: battleLoadout,
                            consumesInventory: !debugAllShots
                        )))
                    }
                    menuButton("Pass & Play", icon: "person.2.fill", tint: .teal) {
                        path.append(.match(MatchConfig(
                            mode: .passAndPlay,
                            loadout: battleLoadout
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

                Spacer(minLength: 8)
            }
            .padding()
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            hasSavedMatch = MatchSaveStore.hasSave
            if CommandLine.arguments.contains("-showAvatars") {
                showAvatarPicker = true
            }
        }
        .sheet(isPresented: $showAvatarPicker) {
            AvatarPickerView()
                .presentationDetents([.medium, .large])
        }
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
        DoubloonLabel(amount: profileStore.coins)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.3), in: Capsule())
    }

    /// Once-a-day free treasure. Shows a claim card when available,
    /// a burst of doubloons right after claiming, nothing otherwise.
    @ViewBuilder
    private var dailyChestCard: some View {
        if let amount = claimedChestAmount {
            HStack(spacing: 10) {
                Image("treasure_chest")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 44)
                DoubloonLabel(amount: amount, fontSize: 22, prefix: "+")
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(.black.opacity(0.3), in: Capsule())
            .transition(.scale.combined(with: .opacity))
        } else if profileStore.isDailyChestAvailable {
            Button {
                withAnimation(.spring(duration: 0.4)) {
                    let amount = profileStore.claimDailyChest()
                    if amount > 0 {
                        claimedChestAmount = amount
                        SoundService.shared.play(.chest)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image("treasure_chest")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Daily Treasure!")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Tap to claim yer loot")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(red: 0.55, green: 0.35, blue: 0.12))
                        .strokeBorder(Color.yellow.opacity(0.7), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var avatarChip: some View {
        Button {
            showAvatarPicker = true
        } label: {
            Image(profileStore.avatarID)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .orange)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change captain avatar")
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
        Button {
            SoundService.shared.play(.tap)
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.headline.weight(.bold))
                .frame(maxWidth: 300)
                .padding(.vertical, 5)
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
