import GameKit
import BathtubEngine

/// Drives one online match: submits local turns as encoded match data and
/// surfaces the opponent's moves from turn events — the third OpponentController.
@MainActor
final class GameCenterController: OpponentController {
    let match: GKTurnBasedMatch
    let localPlayer: PlayerID

    /// How many moves of the shared log we've already seen/applied locally.
    private var knownMoveCount = 0
    private var pendingMove: CheckedContinuation<Move?, Never>?
    /// Moves that arrived before anyone awaited them.
    private var queuedMoves: [Move] = []
    /// Set when the opponent quit/lost via Game Center rather than gameplay.
    private(set) var opponentForfeited = false
    /// Invoked once when match data first carries an initialized GameState
    /// (the creator waits here while the opponent places their fleet).
    var onStateReady: ((GameState) -> Void)?

    init(match: GKTurnBasedMatch, localPlayer: PlayerID) {
        self.match = match
        self.localPlayer = localPlayer
    }

    func markKnown(state: GameState) {
        knownMoveCount = state.moveLog.count
    }

    // MARK: - Loading / setup

    /// Loads (or bootstraps) the game from match data. Returns nil when the local
    /// player still needs to place their fleet.
    static func loadGame(from match: GKTurnBasedMatch) async throws -> OnlineMatchData {
        let data = try await match.loadMatchData()
        return MatchDataCodec.decode(data)
    }

    /// Contributes the local board; initializes the GameState when both boards are in.
    /// Ends the setup turn so the other participant proceeds.
    func submitSetup(board: Board) async throws -> OnlineMatchData {
        var data = MatchDataCodec.decode(try await match.loadMatchData())
        let seatKey = localPlayer == .one ? "0" : "1"
        data.boards[seatKey] = board

        if data.state == nil, let one = data.boards["0"], let two = data.boards["1"] {
            // Both fleets placed — battle begins; everyone gets the full arsenal online.
            let arsenal = Set(ShotType.allCases)
            data.state = GameState(boards: [.one: one, .two: two], loadouts: [.one: arsenal, .two: arsenal])
        }

        try await endTurn(with: data)
        if let state = data.state { markKnown(state: state) }
        return data
    }

    // MARK: - Turn submission

    /// Sends the local player's applied move (and resulting state) to the opponent.
    func submitLocalTurn(state: GameState) async throws {
        var data = MatchDataCodec.decode(try await match.loadMatchData())
        data.state = state
        markKnown(state: state)

        if case .finished(let winner) = state.phase {
            for (index, participant) in match.participants.enumerated() {
                let seat = MatchDataCodec.player(forParticipantIndex: index)
                participant.matchOutcome = seat == winner ? .won : .lost
            }
            try await match.endMatchInTurn(withMatch: MatchDataCodec.encode(data))
        } else {
            try await endTurn(with: data)
        }
    }

    private func endTurn(with data: OnlineMatchData) async throws {
        let next = match.participants.filter {
            $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID
        }
        try await match.endTurn(
            withNextParticipants: next,
            turnTimeout: GKTurnTimeoutDefault,
            match: MatchDataCodec.encode(data)
        )
    }

    // MARK: - OpponentController

    /// Resolves when the opponent's move arrives via a turn event.
    /// Returns nil when the opponent forfeits.
    func nextMove(state: GameState) async -> Move? {
        markKnown(state: state)
        if !queuedMoves.isEmpty {
            return queuedMoves.removeFirst()
        }
        if opponentForfeited {
            return nil
        }
        return await withCheckedContinuation { continuation in
            pendingMove = continuation
        }
    }

    /// Called by GameCenterService when Game Center delivers updated match data.
    func handleTurnEvent(_ updatedMatch: GKTurnBasedMatch) {
        // Opponent quit → hand the win to the local player.
        let opponentQuit = updatedMatch.participants.contains {
            $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID && $0.matchOutcome == .quit
        }

        let data = MatchDataCodec.decode(updatedMatch.matchData)
        if let state = data.state {
            // First sight of an initialized game (creator was waiting on opponent setup).
            if let onStateReady {
                self.onStateReady = nil
                markKnown(state: state)
                onStateReady(state)
            } else {
                let newMoves = Array(state.moveLog.dropFirst(knownMoveCount))
                knownMoveCount = state.moveLog.count
                for move in newMoves where move.player != localPlayer {
                    if let continuation = pendingMove {
                        pendingMove = nil
                        continuation.resume(returning: move)
                    } else {
                        queuedMoves.append(move)
                    }
                }
            }
        }

        if opponentQuit {
            opponentForfeited = true
            if let continuation = pendingMove {
                pendingMove = nil
                continuation.resume(returning: nil)
            }
        }
    }
}
