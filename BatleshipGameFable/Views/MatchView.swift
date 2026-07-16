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
                VStack {
                    statusBanner(viewModel)
                    Spacer()
                }
                .padding(.top, 8)
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

    private func statusBanner(_ viewModel: MatchViewModel) -> some View {
        Text(viewModel.statusText)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.black.opacity(0.35), in: Capsule())
            .animation(.default, value: viewModel.turnState)
    }

    private func startMatchIfNeeded() {
        guard viewModel == nil else { return }
        let newViewModel = MatchViewModel(config: config)
        let newScene = BattleScene(size: BattleScene.designSize)
        newScene.scaleMode = .aspectFill
        newScene.viewModel = newViewModel
        newViewModel.renderer = newScene
        viewModel = newViewModel
        scene = newScene
        newViewModel.matchDidStart()
    }
}
