import SwiftUI
import BathtubEngine

enum Route: Hashable {
    case placement(MatchConfig)
    case match(MatchConfig)
    case armory
    case settings
}

struct RootView: View {
    @State private var path: [Route] = []
    @State private var profileStore = ProfileStore()
    @State private var gameCenter = GameCenterService.shared

    var body: some View {
        NavigationStack(path: $path) {
            MainMenuView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .placement(let config):
                        PlacementView(config: config, path: $path)
                    case .match(let config):
                        MatchView(config: config, path: $path)
                    case .armory:
                        ArmoryView()
                    case .settings:
                        SettingsView(path: $path)
                    }
                }
        }
        .environment(profileStore)
        .onChange(of: gameCenter.pendingMatchID) { _, matchID in
            // User tapped a Game Center turn notification — jump into that match.
            guard let matchID else { return }
            gameCenter.pendingMatchID = nil
            path = [.match(MatchConfig(mode: .gameCenter(matchID: matchID), loadout: Set(ShotType.allCases)))]
        }
        .onAppear {
            gameCenter.authenticate()
            let args = CommandLine.arguments
            // Debug: -avatar <assetID> pre-selects a captain portrait for testing.
            if let index = args.firstIndex(of: "-avatar"), index + 1 < args.count {
                profileStore.setAvatar(args[index + 1])
            }
            if args.contains("-autoBattle") {
                let mode: MatchConfig.Mode = args.contains("-pnp") ? .passAndPlay : .ai
                path = [.match(MatchConfig(mode: mode, loadout: Set(ShotType.allCases)))]
            } else if let index = args.firstIndex(of: "-screen"), index + 1 < args.count {
                // Debug deep links for testing: -screen placement|armory|settings
                switch args[index + 1] {
                case "placement": path = [.placement(MatchConfig(mode: .ai))]
                case "armory": path = [.armory]
                case "settings": path = [.settings]
                case "resume": path = [.match(MatchConfig(mode: .ai, resume: true))]
                default: break
                }
            }
        }
    }
}

#Preview {
    RootView()
}
