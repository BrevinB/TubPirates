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
    /// Opponent moves that arrived before anyone awaited them, tagged with
    /// their absolute moveLog index so a rejoin can discard ones already
    /// baked into the freshly loaded state.
    private var queuedMoves: [(index: Int, move: Move)] = []
    /// Set when the opponent quit/lost via Game Center rather than gameplay.
    private(set) var opponentForfeited = false
    /// Invoked once when match data first carries an initialized GameState
    /// (the creator waits here while the opponent places their fleet).
    var onStateReady: ((GameState) -> Void)?
    /// Our placed fleet, parked when we tried to set up while the other
    /// participant still held the turn (only the current participant may
    /// write match data). Submitted from the turn event that makes us current.
    var pendingSetupBoard: Board?
    /// Avatar accompanying a parked setup.
    var pendingSetupAvatarID: String?

    /// The rival's identity for the HUD: their Game Center display name and
    /// the in-game avatar they carried in the match data.
    var opponentDisplayName: String? {
        let other = match.participants.first {
            $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID
        }
        return other?.player?.displayName
    }

    private(set) var opponentAvatarID: String?

    /// Fires when the rival's canned taunt arrives (validated against
    /// QuickChat.lines before this is called).
    var onTaunt: ((String) -> Void)?
    /// Move-stamp of the last rival taunt we've surfaced (or baselined at
    /// load, so stale taunts don't replay when reopening a match).
    private var lastSeenTauntMove = -1

    /// Pulls the rival's avatar out of decoded match data.
    func noteAvatars(from data: OnlineMatchData) {
        let opponentKey = localPlayer == .one ? "1" : "0"
        if let avatar = data.avatars?[opponentKey] {
            opponentAvatarID = avatar
        }
    }

    /// Baselines taunt state at match load so only NEW taunts fire later.
    func baselineTaunts(from data: OnlineMatchData) {
        let opponentKey = localPlayer == .one ? "1" : "0"
        lastSeenTauntMove = data.taunts?[opponentKey]?.atMove ?? -1
    }

    /// Surfaces a fresh, valid rival taunt exactly once.
    private func noteTaunts(from data: OnlineMatchData) {
        let opponentKey = localPlayer == .one ? "1" : "0"
        guard let taunt = data.taunts?[opponentKey],
              taunt.atMove > lastSeenTauntMove,
              QuickChat.isValid(taunt.message)
        else { return }
        lastSeenTauntMove = taunt.atMove
        onTaunt?(taunt.message)
    }

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

    /// Contributes the local board (and avatar); initializes the GameState when
    /// both boards are in. Ends the setup turn so the other participant proceeds.
    func submitSetup(board: Board, avatarID: String? = nil) async throws -> OnlineMatchData {
        var data = MatchDataCodec.decode(try await match.loadMatchData())
        let seatKey = localPlayer == .one ? "0" : "1"
        data.boards[seatKey] = board
        if let avatarID {
            var avatars = data.avatars ?? [:]
            avatars[seatKey] = avatarID
            data.avatars = avatars
        }
        noteAvatars(from: data)

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

    /// Sends the local player's applied move (and resulting state) to the
    /// opponent, with an optional canned taunt riding along.
    func submitLocalTurn(state: GameState, taunt: String? = nil) async throws {
        var data = MatchDataCodec.decode(try await match.loadMatchData())
        data.state = state
        if let taunt, QuickChat.isValid(taunt) {
            var taunts = data.taunts ?? [:]
            taunts[localPlayer == .one ? "0" : "1"] = Taunt(message: taunt, atMove: state.moveLog.count)
            data.taunts = taunts
        }
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
        // A rejoin loads a state that already contains previously queued
        // moves — replaying them would corrupt the turn machine.
        queuedMoves.removeAll { $0.index < state.moveLog.count }
        if !queuedMoves.isEmpty {
            return queuedMoves.removeFirst().move
        }
        if opponentForfeited {
            return nil
        }
        return await withCheckedContinuation { continuation in
            pendingMove = continuation
        }
    }

    /// Unblocks (and abandons) any pending wait — used when the local player
    /// backs out of the match screen so the awaiting task doesn't dangle.
    func cancelWaiting() {
        pendingMove?.resume(returning: nil)
        pendingMove = nil
    }

    /// Called by GameCenterService when Game Center delivers updated match data.
    func handleTurnEvent(_ updatedMatch: GKTurnBasedMatch) {
        // Opponent quit or timed out → hand the win to the local player.
        let localID: String = GKLocalPlayer.local.gamePlayerID
        var opponentQuit = false
        for participant in updatedMatch.participants {
            let participantID: String? = participant.player?.gamePlayerID
            if participantID == localID { continue }
            let outcome: GKTurnBasedMatch.Outcome = participant.matchOutcome
            if outcome == .quit || outcome == .timeExpired {
                opponentQuit = true
            }
        }

        let data = MatchDataCodec.decode(updatedMatch.matchData)
        noteAvatars(from: data)
        noteTaunts(from: data)

        // Deferred setup: we placed before the turn was ours; now that the
        // other captain has moved on, contribute our fleet.
        if data.state == nil, let board = pendingSetupBoard,
           updatedMatch.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID {
            pendingSetupBoard = nil
            let avatarID = pendingSetupAvatarID
            pendingSetupAvatarID = nil
            Task {
                guard let newData = try? await submitSetup(board: board, avatarID: avatarID),
                      let state = newData.state else { return }
                let callback = onStateReady
                onStateReady = nil
                callback?(state)
            }
            return
        }

        if let state = data.state {
            // First sight of an initialized game (creator was waiting on opponent setup).
            if let onStateReady {
                self.onStateReady = nil
                markKnown(state: state)
                onStateReady(state)
            } else {
                let log = state.moveLog
                // A stale event can carry fewer moves than we've seen locally.
                let firstNew = min(knownMoveCount, log.count)
                knownMoveCount = max(knownMoveCount, log.count)
                for index in firstNew..<log.count {
                    let move = log[index]
                    guard move.player != localPlayer else { continue }
                    if let continuation = pendingMove {
                        pendingMove = nil
                        continuation.resume(returning: move)
                    } else {
                        queuedMoves.append((index: index, move: move))
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
