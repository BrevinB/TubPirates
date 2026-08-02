import GameKit
import Observation
import OSLog
import SwiftUI
import BathtubEngine

/// Shared diagnostics channel for Game Center plumbing (visible in Console
/// during support triage; `print` vanishes in release).
let gameCenterLog = Logger(subsystem: "co.brevinb.TubPirates", category: "GameCenter")

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
    /// The match currently on the match screen (nil when none is).
    /// Turn events for it animate in place; events for any OTHER match may
    /// navigate — even when a stale controller for it still exists.
    var activeMatchID: String?
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
                gameCenterLog.error("Auth failed: \(error.localizedDescription, privacy: .public)")
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
    /// nil means the load failed (offline) — callers keep what they have.
    func loadAllMatches() async -> [GKTurnBasedMatch]? {
        guard isAuthenticated else { return nil }
        guard let matches = try? await GKTurnBasedMatch.loadMatches() else { return nil }
        for match in matches {
            register(match)
        }
        // A successful load is the full truth — drop watched-move records
        // for matches that no longer exist.
        SeenMovesStore.prune(keeping: matches.map(\.matchID))
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
        let config = MatchConfig(mode: .gameCenter(matchID: match.matchID), loadout: Set(ShotType.allCases))
        guard let data = try? await GameCenterController.loadGame(from: match) else {
            // Load failed or the payload is unreadable: NEVER route to
            // placement (re-placing overwrites a live match) — the match
            // screen surfaces the failure and bails safely.
            return .match(config)
        }
        let seatKey = seat == .one ? "0" : "1"
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
            controllers[match.matchID]?.handleTurnEvent(match)
            // User tapped a Game Center notification for a match that isn't
            // on screen — surface it. (A lingering controller, e.g. one
            // holding a parked setup, must not swallow the navigation.)
            if didBecomeActive, activeMatchID != match.matchID {
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

    /// Instant chat: a rival's canned-taunt exchange arrived.
    nonisolated func player(_ player: GKPlayer, receivedExchangeRequest exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        Task { @MainActor in
            register(match)
            controllers[match.matchID]?.handleExchange(exchange)
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
            gameCenterLog.error("Matchmaker failed: \(error.localizedDescription, privacy: .public)")
            viewController.dismiss(animated: true)
            onCancel()
        }
    }
}
