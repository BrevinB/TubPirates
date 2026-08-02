import GameKit
import OSLog
import SwiftUI
import BathtubEngine

/// Game Center IDs. Must match App Store Connect exactly
/// (see marketing/GameCenterSetup.md for the configuration table).
enum GameCenterID {
    static let winsLeaderboard = "tubpirates.leaderboard.wins"
    static let doubloonsLeaderboard = "tubpirates.leaderboard.doubloons"

    static let firstWin = "tubpirates.achievement.firstwin"
    static let wins10 = "tubpirates.achievement.wins10"
    static let wins25 = "tubpirates.achievement.wins25"
    static let pugbeardCleared = "tubpirates.achievement.pugbeard"
    static let salCleared = "tubpirates.achievement.sal"
    static let bessCleared = "tubpirates.achievement.bess"
    static let champion = "tubpirates.achievement.champion"
    static let flawless = "tubpirates.achievement.flawless"
    static let fullBroadside = "tubpirates.achievement.broadside"
    static let fleetAdmiral = "tubpirates.achievement.fleetadmiral"
}

/// Translates profile state into Game Center achievement progress and
/// leaderboard scores. Fire-and-forget: every call no-ops without auth,
/// and Game Center ignores regressions/re-reports of completed achievements.
@MainActor
enum AchievementReporter {
    /// Call after a battle's result is recorded (and cosmetics synced).
    static func reportProgress(profile: PlayerProfile, flawlessWin: Bool) {
        guard GKLocalPlayer.local.isAuthenticated else { return }

        func rungPercent(_ captainID: String, _ needed: Int) -> Double {
            let wins = profile.captainWins[captainID] ?? 0
            return min(100, Double(wins) / Double(needed) * 100)
        }

        var achievements: [GKAchievement] = []
        func add(_ id: String, _ percent: Double) {
            let achievement = GKAchievement(identifier: id)
            achievement.percentComplete = max(0, min(100, percent))
            achievement.showsCompletionBanner = true
            achievements.append(achievement)
        }

        add(GameCenterID.firstWin, profile.wins >= 1 ? 100 : 0)
        add(GameCenterID.wins10, Double(profile.wins) * 10)
        add(GameCenterID.wins25, Double(profile.wins) * 4)
        add(GameCenterID.pugbeardCleared, rungPercent("dogbeard", 3))
        add(GameCenterID.salCleared, rungPercent("soapySal", 4))
        add(GameCenterID.bessCleared, rungPercent("barnacleBess", 5))
        let laddersCleared = Captain.roster.allSatisfy {
            (profile.captainWins[$0.id] ?? 0) >= $0.winsToAdvance
        }
        add(GameCenterID.champion, laddersCleared ? 100 : 0)
        if flawlessWin {
            add(GameCenterID.flawless, 100)
        }
        let specialCount = profile.firedSpecials.subtracting([.cannon]).count
        add(GameCenterID.fullBroadside, Double(specialCount) / 5 * 100)
        add(GameCenterID.fleetAdmiral, Double(profile.ownedFleets.count) / Double(FleetSkin.all.count) * 100)

        GKAchievement.report(achievements) { error in
            if let error {
                Logger(subsystem: "co.brevinb.TubPirates", category: "GameCenter")
                    .error("Achievement report failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        Task {
            try? await GKLeaderboard.submitScore(
                profile.wins, context: 0, player: GKLocalPlayer.local,
                leaderboardIDs: [GameCenterID.winsLeaderboard]
            )
            try? await GKLeaderboard.submitScore(
                profile.lifetimeDoubloons, context: 0, player: GKLocalPlayer.local,
                leaderboardIDs: [GameCenterID.doubloonsLeaderboard]
            )
        }
    }
}

/// The native Game Center dashboard (achievements + leaderboards),
/// presented as a sheet from the menu's record chip.
struct GameCenterDashboardView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let controller = GKGameCenterViewController(state: .achievements)
        controller.gameCenterDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: GKGameCenterViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
            dismiss()
        }
    }
}
