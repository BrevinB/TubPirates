import GameKit
import BathtubEngine

/// Drives one online match: submits local turns as encoded match data and
/// surfaces the opponent's moves from turn events — the third OpponentController.
@MainActor
final class GameCenterController: OpponentController {
    private(set) var match: GKTurnBasedMatch
    let localPlayer: PlayerID

    /// The server says it's no longer our turn (a retried submit that already
    /// landed, or the turn moved on) — surfaced as a retryable send failure.
    struct TurnMovedOn: Error {}

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

    /// Sends a canned taunt INSTANTLY via a turn-based exchange (out-of-band,
    /// pushed to the rival immediately — no waiting for our next move).
    func sendInstantTaunt(_ message: String) async {
        guard QuickChat.isValid(message) else { return }
        let others = match.participants.filter {
            $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID
        }
        guard !others.isEmpty else { return }
        // Exchanges only take a localizable "key", and Game Center's push-side
        // lookup of it in the receiver's bundle proved unreliable (banners
        // showed the literal "TAUNT_PUSH"). A key that doesn't resolve is
        // displayed verbatim — so pass the finished text AS the key and the
        // banner always reads correctly. The receiver's in-app chat ignores
        // this and validates the raw `data` payload instead.
        try? await match.sendExchange(
            to: others,
            data: Data(message.utf8),
            localizableMessageKey: "💬 \(GKLocalPlayer.local.alias): \(message)",
            arguments: [],
            timeout: 60
        )
    }

    /// A rival's exchange arrived: validate, surface, and reply to resolve it
    /// (unresolved exchanges can block turn submission).
    func handleExchange(_ exchange: GKTurnBasedExchange) {
        if let data = exchange.data,
           let message = String(data: data, encoding: .utf8),
           QuickChat.isValid(message),
           exchange.sender.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID {
            onTaunt?(message)
        }
        Task {
            // Literal text, not a catalog key — see sendInstantTaunt.
            try? await exchange.reply(withLocalizableMessageKey: "Message delivered", arguments: [], data: Data())
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
        guard let decoded = MatchDataCodec.decode(data) else {
            throw MatchDataCodec.CorruptMatchData()
        }
        return decoded
    }

    /// Contributes the local board (and avatar); initializes the GameState when
    /// both boards are in. Ends the setup turn so the other participant proceeds.
    func submitSetup(board: Board, avatarID: String? = nil) async throws -> OnlineMatchData {
        // Refuse to write over data we can't read — overwriting would wipe
        // the whole match for both players.
        guard var data = MatchDataCodec.decode(try await match.loadMatchData()) else {
            throw MatchDataCodec.CorruptMatchData()
        }
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

        let name = GKLocalPlayer.local.alias
        try await endTurn(with: data, pushMessage: data.state == nil
            ? "⚓️ \(name) set their fleet — place yours to start the battle!"
            : "🏴‍☠️ \(name)'s fleet is in the tub — the battle begins!")
        if let state = data.state { markKnown(state: state) }
        return data
    }

    // MARK: - Turn submission

    /// Sends the local player's applied move (and resulting state) to the
    /// opponent, with an optional canned taunt riding along. `pushMessage` is
    /// the plain-text notification the rival receives (defaults to Game
    /// Center's generic "It's your turn" when nil).
    func submitLocalTurn(state: GameState, taunt: String? = nil, pushMessage: String? = nil) async throws {
        guard var data = MatchDataCodec.decode(try await match.loadMatchData()) else {
            throw MatchDataCodec.CorruptMatchData()
        }
        data.state = state
        if let taunt, QuickChat.isValid(taunt) {
            var taunts = data.taunts ?? [:]
            taunts[localPlayer == .one ? "0" : "1"] = Taunt(message: taunt, atMove: state.moveLog.count)
            data.taunts = taunts
        }
        markKnown(state: state)

        if case .finished(let winner) = state.phase {
            try await endMatchOnServer(with: try MatchDataCodec.encode(data), winner: winner, pushMessage: pushMessage)
        } else {
            try await endTurn(with: data, pushMessage: pushMessage)
        }
    }

    /// Ends the Game Center match after a winning move — shared by the live
    /// submit and the reopened-match recovery below.
    private func endMatchOnServer(with encoded: Data, winner: PlayerID, pushMessage: String? = nil) async throws {
        // endMatchInTurn raises an ObjC exception (uncatchable from Swift)
        // if the match already ended or the turn moved on — re-check the
        // authoritative server state first.
        match = try await GKTurnBasedMatch.load(withID: match.matchID)
        guard match.status != .ended else { return }
        guard match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID else {
            throw TurnMovedOn()
        }
        for (index, participant) in match.participants.enumerated() {
            let seat = MatchDataCodec.player(forParticipantIndex: index)
            participant.matchOutcome = seat == winner ? .won : .lost
        }
        // Plain text (not a localizable key) — set on the freshly reloaded
        // instance so it rides along with the ending.
        if let pushMessage { match.message = pushMessage }
        // A still-active taunt exchange blocks endMatchInTurn exactly like it
        // blocks endTurn. Unlike a mid-game turn (where we only cancel after a
        // failure, to keep the taunt's push alive), the match is over — clear
        // ours up front instead of failing into it. The taunt itself survives
        // in the match data.
        await cancelLocalActiveExchanges()
        await settleExchanges(with: encoded)
        do {
            try await match.endMatchInTurn(withMatch: encoded)
        } catch {
            // A rival exchange resolving (or arriving) in the window above can
            // still block — clear again and retry once.
            await cancelLocalActiveExchanges()
            try await match.endMatchInTurn(withMatch: encoded)
        }
    }

    /// Heals a match the server still thinks is live after the game itself
    /// finished: if the winning device died before endMatchInTurn landed, the
    /// match sits on "your turn" forever. Called whenever an already-finished
    /// online match is (re)opened; quietly re-runs the ending when this
    /// participant still holds the turn, and no-ops otherwise.
    func finalizeFinishedMatchIfNeeded(state: GameState) async {
        guard case .finished = state.phase else { return }
        guard match.status != .ended,
              match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
        else { return }
        // submitLocalTurn re-syncs the final state into the match data and
        // runs the end-match path above (which re-checks server truth).
        // Holding the turn of a finished game means the local player won.
        try? await submitLocalTurn(
            state: state,
            pushMessage: "☠️ \(GKLocalPlayer.local.alias) sank your fleet — the battle is lost!"
        )
    }

    private func endTurn(with data: OnlineMatchData, pushMessage: String? = nil) async throws {
        let encoded = try MatchDataCodec.encode(data)
        // Same uncatchable-exception hazard as endMatchInTurn: only the
        // current participant of a live match may end a turn.
        match = try await GKTurnBasedMatch.load(withID: match.matchID)
        guard match.status != .ended else { return }
        guard match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID else {
            throw TurnMovedOn()
        }
        // The rival's turn notification. Plain text sidesteps the loc-key
        // lookup that Game Center pushes resolve unreliably; nil keeps the
        // stock "It's your turn."
        if let pushMessage { match.message = pushMessage }
        let next = match.participants.filter {
            $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID
        }
        await settleExchanges(with: encoded)
        do {
            try await match.endTurn(
                withNextParticipants: next,
                turnTimeout: GKTurnTimeoutDefault,
                match: encoded
            )
        } catch {
            // A still-pending chat exchange (rival offline, not yet timed
            // out) can block the turn — cancel ours and retry once.
            await cancelLocalActiveExchanges()
            try await match.endTurn(
                withNextParticipants: next,
                turnTimeout: GKTurnTimeoutDefault,
                match: encoded
            )
        }
    }

    /// Cancels every still-active exchange the local player sent (the rival
    /// hasn't acknowledged the taunt yet) — GameKit refuses to end a turn or
    /// a match while they're pending.
    private func cancelLocalActiveExchanges() async {
        for exchange in match.activeExchanges ?? []
        where exchange.sender.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID {
            // Literal text, not a catalog key — see sendInstantTaunt.
            try? await exchange.cancel(withLocalizableMessageKey: "Message delivered", arguments: [])
        }
    }

    /// Game Center requires completed exchanges to be merged into match data
    /// before the turn can end.
    private func settleExchanges(with encoded: Data) async {
        if let completed = match.completedExchanges, !completed.isEmpty {
            try? await match.saveMergedMatch(encoded, withResolvedExchanges: completed)
        }
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
        // Keep our stored match current — the original instance goes stale
        // as turns advance.
        match = updatedMatch
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

        guard let data = MatchDataCodec.decode(updatedMatch.matchData) else { return }
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
