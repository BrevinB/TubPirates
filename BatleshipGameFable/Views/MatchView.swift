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

    @State private var viewModel: MatchViewModel?
    @State private var scene: BattleScene?
    @State private var showEndScreen = false

    var body: some View {
        ZStack {
            Color(red: 0.13, green: 0.35, blue: 0.55).ignoresSafeArea()

            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            }

            if let viewModel {
                hud(viewModel)
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear(perform: startMatchIfNeeded)
        .onChange(of: viewModel?.turnState) { _, newState in
            if case .finished = newState {
                showEndScreen = true
            }
        }
        .fullScreenCover(isPresented: $showEndScreen) {
            if let viewModel {
                MatchEndView(
                    didWin: viewModel.didWin,
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
                    name: "Dogbeard",
                    highlighted: viewModel.turnState == .opponentThinking
                        || viewModel.turnState == .resolvingOpponentShot
                )
                Spacer()
                statusBanner(viewModel)
                Spacer()
                PlayerHUDView(
                    imageName: "portrait_player",
                    name: "You",
                    highlighted: viewModel.turnState == .playerTargeting
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
        guard viewModel == nil else { return }
        let newViewModel = MatchViewModel(config: config)
        let newScene = BattleScene()
        newScene.scaleMode = .resizeFill
        newScene.viewModel = newViewModel
        newViewModel.renderer = newScene
        viewModel = newViewModel
        scene = newScene
        newViewModel.matchDidStart()
    }
}
