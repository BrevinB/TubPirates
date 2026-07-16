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
        .onAppear {
            if CommandLine.arguments.contains("-autoBattle") {
                path = [.match(MatchConfig(mode: .ai, loadout: Set(ShotType.allCases)))]
            }
        }
    }
}

#Preview {
    RootView()
}
