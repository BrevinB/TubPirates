import SwiftUI
import BathtubEngine

enum Route: Hashable {
    case captains(MatchConfig)
    case placement(MatchConfig)
    case match(MatchConfig)
    case armory
    case settings
}

struct RootView: View {
    @State private var path: [Route] = []
    @State private var profileStore = ProfileStore()
    @State private var gameCenter = GameCenterService.shared
    @State private var showWelcome = false

    var body: some View {
        NavigationStack(path: $path) {
            MainMenuView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .captains(let config):
                        CaptainsView(baseConfig: config, path: $path)
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
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView {
                profileStore.markWelcomeSeen()
                showWelcome = false
                // New captains sail straight into the nearly-won onboarding
                // battle: full arsenal to taste, coach marks overlaid.
                if !profileStore.hasSeenBattleTips {
                    path = [.match(.tutorialBattle)]
                }
            }
        }
        .onChange(of: profileStore.hasSeenWelcome) { _, seen in
            // Settings' "Replay Tutorial" clears the flag mid-session.
            if !seen { showWelcome = true }
        }
        .onChange(of: gameCenter.pendingMatchID) { _, matchID in
            // User tapped a Game Center turn notification — jump into that match.
            guard let matchID else { return }
            gameCenter.pendingMatchID = nil
            path = [.match(MatchConfig(mode: .gameCenter(matchID: matchID), loadout: Set(ShotType.allCases)))]
        }
        .onAppear {
            SoundService.shared.warmUp()
            SoundService.shared.startMusic()
            Analytics.start()
            StoreService.shared.configureIfPossible()
            gameCenter.authenticate()
            let args = CommandLine.arguments
            // -welcome forces the story for testing; otherwise first launch only.
            // Debug deep links (-autoBattle / -screen) suppress it so headless
            // runs land where they aimed.
            let debugLaunch = args.contains("-autoBattle") || args.contains("-screen") || args.contains("-noWelcome")
            if args.contains("-welcome") || (!profileStore.hasSeenWelcome && !debugLaunch) {
                showWelcome = true
            }
            // Debug: -avatar <assetID> pre-selects a captain portrait for testing.
            if let index = args.firstIndex(of: "-avatar"), index + 1 < args.count {
                profileStore.setAvatar(args[index + 1])
            }
            // Debug: -fleet <id> grants and equips a fleet skin for testing.
            if let index = args.firstIndex(of: "-fleet"), index + 1 < args.count {
                profileStore.debugGrantFleet(FleetSkin.withID(args[index + 1]))
            }
            // Debug: -champion clears the whole ladder.
            if args.contains("-champion") {
                profileStore.debugConquerLadder()
            }
            if args.contains("-autoBattle") {
                let mode: MatchConfig.Mode = args.contains("-pnp") ? .passAndPlay : .ai
                // -consume: use the real stash + consumable accounting (for testing).
                let consume = args.contains("-consume")
                var config = MatchConfig(
                    mode: mode,
                    loadout: consume ? profileStore.loadoutShots : Set(ShotType.allCases),
                    consumesInventory: consume
                )
                // -captain <id>: fight a specific ladder rival.
                if let index = args.firstIndex(of: "-captain"), index + 1 < args.count {
                    config.captainID = args[index + 1]
                }
                path = [.match(config)]
            } else if let index = args.firstIndex(of: "-screen"), index + 1 < args.count {
                // Debug deep links for testing: -screen placement|armory|settings
                switch args[index + 1] {
                case "placement": path = [.placement(MatchConfig(mode: .ai))]
                case "battle": path = [.match(MatchConfig(mode: .ai, loadout: Set(ShotType.allCases)))]
                case "tutorial": path = [.match(.tutorialBattle)]
                case "captains": path = [.captains(MatchConfig(mode: .ai))]
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
