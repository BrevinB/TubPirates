import GameKit
import Observation
import SwiftUI
import BathtubEngine

/// Game Center glue: authentication, the matchmaker sheet, and routing of
/// turn events to the per-match controller.
@Observable @MainActor
final class GameCenterService: NSObject {
    static let shared = GameCenterService()

    private(set) var isAuthenticated = false
    /// Live matches by matchID (Route carries only the ID; GKTurnBasedMatch isn't Hashable-friendly).
    private(set) var matches: [String: GKTurnBasedMatch] = [:]
    /// Active turn controllers by matchID.
    private(set) var controllers: [String: GameCenterController] = [:]
    /// Set when a turn event arrives for a match the user isn't currently viewing.
    var pendingMatchID: String?
    /// Bumped whenever Game Center reports match changes — the Harbor list
    /// observes this to refresh.
    private(set) var matchListVersion = 0

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            isAuthenticated = GKLocalPlayer.local.isAuthenticated
            if isAuthenticated {
                GKLocalPlayer.local.register(self)
            }
            if let error {
                print("Game Center auth: \(error.localizedDescription)")
            }
        }
    }

    func register(_ match: GKTurnBasedMatch) {
        matches[match.matchID] = match
    }

    func controller(for matchID: String) -> GameCenterController? {
        controllers[matchID]
    }

    func makeController(for match: GKTurnBasedMatch, localPlayer: PlayerID) -> GameCenterController {
        let controller = GameCenterController(match: match, localPlayer: localPlayer)
        controllers[match.matchID] = controller
        return controller
    }

    func releaseController(for matchID: String) {
        controllers[matchID] = nil
    }

    /// Which engine seat the local player occupies in this match.
    func localSeat(in match: GKTurnBasedMatch) -> PlayerID {
        let index = match.participants.firstIndex {
            $0.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
        } ?? 0
        return MatchDataCodec.player(forParticipantIndex: index)
    }

    // MARK: - Harbor (custom online UI, no stock Game Center sheet)

    /// All of the local player's turn-based matches, newest activity first.
    func loadAllMatches() async -> [GKTurnBasedMatch] {
        guard isAuthenticated else { return [] }
        let matches = (try? await GKTurnBasedMatch.loadMatches()) ?? []
        for match in matches {
            register(match)
        }
        return matches
    }

    /// Programmatic auto-match: joins an open match or opens a fresh one that
    /// fills when the next captain queues up.
    func findMatch() async throws -> GKTurnBasedMatch {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        let match = try await GKTurnBasedMatch.find(for: request)
        register(match)
        return match
    }

    /// Where opening this match should land: placement if our fleet isn't in
    /// the match data yet, otherwise straight into the battle.
    func destination(for match: GKTurnBasedMatch) async -> Route {
        register(match)
        let seat = localSeat(in: match)
        _ = controller(for: match.matchID) ?? makeController(for: match, localPlayer: seat)
        let data = (try? await GameCenterController.loadGame(from: match)) ?? OnlineMatchData()
        let seatKey = seat == .one ? "0" : "1"
        let config = MatchConfig(mode: .gameCenter(matchID: match.matchID), loadout: Set(ShotType.allCases))
        return data.boards[seatKey] == nil ? .placement(config) : .match(config)
    }

    /// Resigns a match from the Harbor list ("Abandon Ship").
    func forfeit(_ match: GKTurnBasedMatch) async {
        let isOurTurn = match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
        if isOurTurn {
            let next = match.participants.filter {
                $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID
            }
            try? await match.participantQuitInTurn(
                with: .quit,
                nextParticipants: next,
                turnTimeout: GKTurnTimeoutDefault,
                match: match.matchData ?? Data()
            )
        } else if match.status == .ended {
            try? await match.remove()
        } else {
            try? await match.participantQuitOutOfTurn(with: .quit)
        }
        releaseController(for: match.matchID)
        matchListVersion += 1
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - Turn events

extension GameCenterService: GKLocalPlayerListener {
    nonisolated func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        Task { @MainActor in
            register(match)
            matchListVersion += 1
            if let controller = controllers[match.matchID] {
                controller.handleTurnEvent(match)
            } else if didBecomeActive {
                // User tapped a Game Center notification — surface the match.
                pendingMatchID = match.matchID
            }
        }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        Task { @MainActor in
            register(match)
            matchListVersion += 1
            controllers[match.matchID]?.handleTurnEvent(match)
        }
    }

    /// The user deleted/quit the match from Game Center's own UI — resign
    /// properly so the opponent is handed the win instead of a dead match.
    nonisolated func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        Task { @MainActor in
            let isOurTurn = match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
            if isOurTurn {
                let next = match.participants.filter {
                    $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID
                }
                try? await match.participantQuitInTurn(
                    with: .quit,
                    nextParticipants: next,
                    turnTimeout: GKTurnTimeoutDefault,
                    match: match.matchData ?? Data()
                )
            } else {
                try? await match.participantQuitOutOfTurn(with: .quit)
            }
            controllers[match.matchID] = nil
        }
    }
}

// MARK: - Matchmaker sheet

/// Wraps GKTurnBasedMatchmakerViewController; calls back with the chosen match.
struct MatchmakerSheet: UIViewControllerRepresentable {
    let onMatch: (GKTurnBasedMatch) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> GKTurnBasedMatchmakerViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: GKTurnBasedMatchmakerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onMatch: onMatch, onCancel: onCancel)
    }

    final class Coordinator: NSObject, GKTurnBasedMatchmakerViewControllerDelegate {
        let onMatch: (GKTurnBasedMatch) -> Void
        let onCancel: () -> Void

        init(onMatch: @escaping (GKTurnBasedMatch) -> Void, onCancel: @escaping () -> Void) {
            self.onMatch = onMatch
            self.onCancel = onCancel
        }

        func turnBasedMatchmakerViewController(
            _ viewController: GKTurnBasedMatchmakerViewController,
            didFind match: GKTurnBasedMatch
        ) {
            viewController.dismiss(animated: true)
            onMatch(match)
        }

        func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
            viewController.dismiss(animated: true)
            onCancel()
        }

        func turnBasedMatchmakerViewController(
            _ viewController: GKTurnBasedMatchmakerViewController,
            didFailWithError error: Error
        ) {
            print("Matchmaker error: \(error.localizedDescription)")
            viewController.dismiss(animated: true)
            onCancel()
        }
    }
}
