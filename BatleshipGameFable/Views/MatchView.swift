import SwiftUI
import SpriteKit
import BathtubEngine

struct MatchView: View {
    let config: MatchConfig
    @Binding var path: [Route]
    /// Changing this identity tears down and rebuilds the whole match (rematch).
    @State private var matchID = UUID()

    var body: some View {
        MatchContentView(config: config, path: $path) {
            matchID = UUID()
        }
        .id(matchID)
    }
}

private struct MatchContentView: View {
    let config: MatchConfig
    @Binding var path: [Route]
    let onRematch: () -> Void

    @Environment(ProfileStore.self) private var profileStore
    @State private var viewModel: MatchViewModel?
    @State private var scene: BattleScene?
    @State private var showEndScreen = false
    @State private var rewardApplied = false
    @State private var waitingForOpponent = false
    @State private var showHandoff = false
    @State private var confirmLeave = false
    @State private var finalReward = 0
    @State private var firstWinBonusApplied = false

    var body: some View {
        ZStack {
            Color(red: 0.13, green: 0.35, blue: 0.55).ignoresSafeArea()

            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            }

            if let viewModel {
                hud(viewModel)

                // Pass-and-play privacy cover (opaque; boards already swapped beneath it).
                if showHandoff, case .awaitingHandoff(let next) = viewModel.turnState {
                    PassDeviceView(incomingName: viewModel.displayName(for: next)) {
                        viewModel.confirmHandoff()
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }

            if waitingForOpponent {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Waiting for your rival to place their fleet...")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Back to Menu") { path.removeAll() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
                .padding()
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear(perform: startMatchIfNeeded)
        .onChange(of: viewModel?.turnState) { _, newState in
            // Animate only the handoff cover — a whole-ZStack animation would
            // crossfade the status banner text into a ghosting mess.
            withAnimation(.easeInOut(duration: 0.25)) {
                if case .awaitingHandoff = newState {
                    showHandoff = true
                } else {
                    showHandoff = false
                }
            }
            if case .finished = newState {
                if let viewModel, !rewardApplied {
                    rewardApplied = true
                    var reward = viewModel.coinReward
                    // First AI-battle win each day pays double.
                    if viewModel.mode == .ai, viewModel.didWin, reward > 0,
                       profileStore.claimFirstWinBonus() {
                        reward *= 2
                        firstWinBonusApplied = true
                    }
                    finalReward = reward
                    profileStore.award(coins: reward)
                    profileStore.recordResult(
                        won: viewModel.didWin,
                        againstCaptainID: viewModel.mode == .ai ? viewModel.captain.id : nil
                    )
                }
                showEndScreen = true
            }
        }
        .fullScreenCover(isPresented: $showEndScreen) {
            if let viewModel {
                let duo = endPortraits(viewModel)
                MatchEndView(
                    didWin: viewModel.didWin,
                    winner: duo.winner,
                    loser: duo.loser,
                    title: viewModel.endTitle,
                    message: viewModel.endMessage,
                    coinReward: finalReward,
                    firstWinBonus: firstWinBonusApplied,
                    onRematch: {
                        showEndScreen = false
                        onRematch()
                    },
                    onExit: {
                        showEndScreen = false
                        path.removeAll()
                    }
                )
            }
        }
    }

    /// Who gloats and who sulks on the end screen. Captains use their
    /// dedicated sad/gloat art; player avatars get the rendered treatment.
    private func endPortraits(_ viewModel: MatchViewModel) -> (winner: EndPortrait, loser: EndPortrait) {
        let playerImage = viewModel.mode == .passAndPlay ? "portrait_player" : profileStore.avatarID
        if viewModel.mode == .passAndPlay {
            // Both captains are humans sharing the generic portrait.
            return (EndPortrait(imageName: playerImage),
                    EndPortrait(imageName: playerImage, renderSad: true))
        }
        if viewModel.didWin {
            return (EndPortrait(imageName: playerImage),
                    EndPortrait(imageName: viewModel.captain.sadPortrait))
        }
        return (EndPortrait(imageName: viewModel.captain.gloatPortrait),
                EndPortrait(imageName: playerImage, renderSad: true))
    }

    private func hud(_ viewModel: MatchViewModel) -> some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    PlayerHUDView(
                        imageName: viewModel.enemyPortrait,
                        name: viewModel.displayName(for: .two),
                        highlighted: viewModel.highlightedPlayer == .two
                    )
                    leaveButton(viewModel)
                }
                Spacer()
                statusBanner(viewModel)
                Spacer()
                PlayerHUDView(
                    imageName: viewModel.mode == .passAndPlay ? "portrait_player" : profileStore.avatarID,
                    name: viewModel.displayName(for: .one),
                    highlighted: viewModel.highlightedPlayer == .one
                )
            }
            .padding(.horizontal, 12)

            // Dogbeard's bubble gets its own row under the HUD — over open water,
            // never covering the portrait, Leave button, or status banner.
            HStack {
                if let line = viewModel.captainLine {
                    speechBubble(line)
                        .id(line) // new line = new view, so texts never crossfade into each other
                        .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .animation(.spring(duration: 0.3), value: viewModel.captainLine)

            Spacer()

            HStack {
                Spacer()
                ShotPanelView(viewModel: viewModel)
                    .padding(.trailing, 6)
            }
            .padding(.bottom, 40)
        }
    }

    /// Comic-style speech bubble anchored under Dogbeard's portrait.
    private func speechBubble(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.05))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 190, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 1, green: 0.96, blue: 0.85))
                    .strokeBorder(Color(red: 0.75, green: 0.55, blue: 0.2), lineWidth: 2)
            )
            .overlay(alignment: .topLeading) {
                // Tail pointing up toward Dogbeard's card.
                Triangle()
                    .fill(Color(red: 1, green: 0.96, blue: 0.85))
                    .frame(width: 16, height: 9)
                    .offset(x: 24, y: -8)
            }
            .accessibilityLabel("Dogbeard says: \(line)")
    }

    private func leaveButton(_ viewModel: MatchViewModel) -> some View {
        Button {
            confirmLeave = true
        } label: {
            Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
        }
        .confirmationDialog(
            "Leave the battle?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button("Leave") { path.removeAll() }
            Button("Keep Fighting", role: .cancel) {}
        } message: {
            if case .gameCenter = viewModel.mode {
                Text("You can rejoin any time from Online Battle.")
            } else {
                Text("Your battle is saved — resume it from the main menu.")
            }
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    private func statusBanner(_ viewModel: MatchViewModel) -> some View {
        Text(viewModel.statusText)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.4), in: Capsule())
    }

    private func startMatchIfNeeded() {
        guard viewModel == nil, !waitingForOpponent else { return }
        if case .gameCenter(let matchID) = config.mode {
            startOnlineMatch(matchID)
        } else {
            var liveConfig = config
            if config.consumesInventory {
                // Re-read the stash at match start so rematches can't
                // resurrect specials that were spent last game.
                liveConfig.loadout = profileStore.loadoutShots
            }
            attach(MatchViewModel(config: liveConfig))
        }
    }

    private func attach(_ newViewModel: MatchViewModel) {
        newViewModel.onLocalSpecialFired = { shot in
            profileStore.consumeUse(of: shot)
        }
        let newScene = BattleScene()
        newScene.scaleMode = .resizeFill
        newScene.viewModel = newViewModel
        newViewModel.renderer = newScene
        viewModel = newViewModel
        scene = newScene
        newViewModel.matchDidStart()
    }

    private func startOnlineMatch(_ matchID: String) {
        let service = GameCenterService.shared
        guard let match = service.matches[matchID] else {
            path.removeAll()
            return
        }
        let seat = service.localSeat(in: match)
        let controller = service.controller(for: matchID) ?? service.makeController(for: match, localPlayer: seat)
        waitingForOpponent = true
        Task {
            do {
                var data = try await GameCenterController.loadGame(from: match)
                let seatKey = seat == .one ? "0" : "1"
                if data.boards[seatKey] == nil, let board = config.playerBoard {
                    data = try await controller.submitSetup(board: board)
                }
                if let state = data.state {
                    waitingForOpponent = false
                    attach(MatchViewModel(gameCenterState: state, localPlayer: seat, controller: controller))
                } else {
                    // Our board is in; the rival is still placing. Stay on the waiting screen.
                    controller.onStateReady = { state in
                        waitingForOpponent = false
                        attach(MatchViewModel(gameCenterState: state, localPlayer: seat, controller: controller))
                    }
                }
            } catch {
                print("Online match load failed: \(error.localizedDescription)")
                waitingForOpponent = false
                path.removeAll()
            }
        }
    }
}
