import SwiftUI

enum Route: Hashable {
    case match(MatchConfig)
}

struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            MainMenuView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .match(let config):
                        MatchView(config: config, path: $path)
                    }
                }
        }
        .onAppear {
            if CommandLine.arguments.contains("-autoBattle") {
                path = [.match(MatchConfig(mode: .ai))]
            }
        }
    }
}

#Preview {
    RootView()
}
