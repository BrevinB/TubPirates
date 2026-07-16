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
                    profileStore.award(coins: viewModel.coinReward)
                    profileStore.recordResult(won: viewModel.didWin)
                }
                showEndScreen = true
            }
        }
        .fullScreenCover(isPresented: $showEndScreen) {
            if let viewModel {
                MatchEndView(
                    didWin: viewModel.didWin,
                    title: viewModel.endTitle,
                    message: viewModel.endMessage,
                    coinReward: viewModel.coinReward,
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

    private func hud(_ viewModel: MatchViewModel) -> some View {
        VStack {
            HStack(alignment: .top) {
                PlayerHUDView(
                    imageName: "portrait_dogbeard",
                    name: viewModel.displayName(for: .two),
                    highlighted: viewModel.highlightedPlayer == .two
                )
                Spacer()
                statusBanner(viewModel)
                Spacer()
                PlayerHUDView(
                    imageName: "portrait_player",
                    name: viewModel.displayName(for: .one),
                    highlighted: viewModel.highlightedPlayer == .one
                )
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack {
                Spacer()
                ShotPanelView(viewModel: viewModel)
                    .padding(.trailing, 6)
            }
            .padding(.bottom, 40)
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
            attach(MatchViewModel(config: config))
        }
    }

    private func attach(_ newViewModel: MatchViewModel) {
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
