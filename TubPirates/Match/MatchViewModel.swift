import Foundation
import GameKit
import Observation
import UIKit
import BathtubEngine

/// What the scene must be able to render on the view model's behalf.
/// Async methods complete when their animations finish — they gate the turn machine.
@MainActor
protocol BattleSceneRendering: AnyObject {
    /// True once the scene is in a view and laid out — animations before this
    /// would aim at unpositioned boards.
    var isPresented: Bool { get }
    func playResolution(_ resolution: MoveResolution, onEnemyBoard: Bool) async
    func refreshBoards()
}

@Observable @MainActor
final class MatchViewModel {
    enum TurnState: Equatable {
        case playerTargeting
        case resolvingPlayerShot
        case opponentThinking
        case resolvingOpponentShot
        /// Online: the move is applied and animated locally but Game Center
        /// rejected/failed the send — parked until the player retries.
        case submitFailed
        case awaitingHandoff(next: PlayerID)
        case finished(winner: PlayerID)
    }

    let mode: MatchConfig.Mode
    /// The rival being fought in AI battles (Dogbeard elsewhere, unused).
    let captain: Captain
    private(set) var state: GameState
    private(set) var turnState: TurnState = .playerTargeting
    /// Whose perspective the boards render from. Fixed in AI mode; swaps in pass-and-play.
    private(set) var activePlayer: PlayerID = .one
    /// The local seat: .one for AI matches, assigned by Game Center online.
    private let fixedLocalPlayer: PlayerID
    var localPlayer: PlayerID { mode == .passAndPlay ? activePlayer : fixedLocalPlayer }
    var selectedShot: ShotType = .cannon
    var selectedOrientation: Orientation = .horizontal

    private let opponent: OpponentController?
    weak var renderer: BattleSceneRendering?
    /// Fired when the local player uses a special (consumable accounting).
    var onLocalSpecialFired: ((ShotType) -> Void)?
    private let consumesInventory: Bool

    /// Debug/demo: an AI plays the local side too (`-autoBattle` launch argument).
    #if DEBUG
    private static let debugAutoBattle = CommandLine.arguments.contains("-autoBattle")
    #else
    private static let debugAutoBattle = false
    #endif
    private let autoPlay = MatchViewModel.debugAutoBattle
    private var playerAI = BattleAI()

    /// The rival captain's current speech-bubble line (AI matches only).
    private(set) var captainLine: String?
    private var dialogRNG = SystemRandomNumberGenerator()
    private var dialogDismissTask: Task<Void, Never>?

    /// Drives the end screen's celebratory vs somber styling.
    var didWin: Bool {
        guard case .finished(let winner) = turnState else { return false }
        // Compare against the LOCAL seat — online, the joiner is seat two,
        // and the old hardcoded `.one` made both clients claim the win.
        return mode == .passAndPlay || winner == localPlayer
    }

    /// Which portrait to spotlight in the HUD right now.
    var highlightedPlayer: PlayerID? {
        switch turnState {
        case .finished, .awaitingHandoff: nil
        case .playerTargeting, .resolvingPlayerShot, .submitFailed: localPlayer
        case .opponentThinking, .resolvingOpponentShot: localPlayer.opponent
        }
    }

    /// The enemy board as the local player is allowed to see it.
    var enemyView: AttackerView {
        state.attackerView(of: localPlayer.opponent)
    }

    var ownBoard: Board {
        state.boards[localPlayer] ?? Board()
    }

    /// The rival's true board — only meaningful once the match is over
    /// (the post-game "where WERE those ships?" reveal).
    var enemyFullBoard: Board {
        state.boards[localPlayer.opponent] ?? Board()
    }

    /// Online rival identity: Game Center display name + the avatar they
    /// chose in-game (carried inside the match data).
    var onlineOpponentName: String?
    var onlineOpponentAvatarID: String?

    // MARK: - Quick chat (online canned taunts)

    struct ChatLine: Equatable {
        let text: String
        let mine: Bool
    }

    /// The bubble currently on screen (yours trailing, rival's leading).
    var chatLine: ChatLine?
    /// Queued taunt; rides along with your next submitted turn.
    private(set) var pendingTaunt: String?
    private var chatDismissTask: Task<Void, Never>?

    func sendTaunt(_ line: String) {
        guard QuickChat.isValid(line) else { return }
        showChat(ChatLine(text: line, mine: true))
        if let controller = opponent as? GameCenterController {
            // Online: instant delivery via a turn-based exchange.
            Task { await controller.sendInstantTaunt(line) }
        } else {
            pendingTaunt = line // staged/debug frames only
        }
    }

    private func showChat(_ line: ChatLine) {
        chatLine = line
        chatDismissTask?.cancel()
        chatDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            chatLine = nil
        }
    }

    #if DEBUG
    /// Screenshot staging: -enemyName / -enemyAvatar override the rival's
    /// HUD identity (and mute captain table talk so the frame reads online).
    static let debugEnemyName: String? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-enemyName"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }()
    static let debugEnemyAvatar: String? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-enemyAvatar"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }()
    static let debugChatLine: String? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-chatLine"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }()
    #endif

    func displayName(for player: PlayerID) -> String {
        #if DEBUG
        if let name = Self.debugEnemyName, player != localPlayer { return name }
        #endif
        switch mode {
        case .ai: return player == localPlayer ? "You" : captain.name
        case .passAndPlay: return player == .one ? "Captain 1" : "Captain 2"
        case .gameCenter: return player == localPlayer ? "You" : (onlineOpponentName ?? "Opponent")
        }
    }

    /// Portrait asset for the enemy card in the HUD.
    var enemyPortrait: String {
        #if DEBUG
        if let avatar = Self.debugEnemyAvatar { return avatar }
        #endif
        switch mode {
        case .ai: return captain.portrait
        case .passAndPlay: return "portrait_player"
        case .gameCenter: return onlineOpponentAvatarID ?? "portrait_player"
        }
    }

    var statusText: String {
        switch turnState {
        case .playerTargeting:
            mode == .passAndPlay ? "\(displayName(for: activePlayer)) — fire!" : "Your turn — fire!"
        case .resolvingPlayerShot: isCatchingUp ? "While ye were away..." : "Firing..."
        case .opponentThinking:
            mode == .ai ? "\(captain.name) is aiming..." : "\(displayName(for: localPlayer.opponent)) is aiming..."
        case .resolvingOpponentShot: isCatchingUp ? "While ye were away..." : "Incoming!"
        case .submitFailed: "Yer shot couldn't reach the rival!"
        case .awaitingHandoff: "Pass the tub..."
        case .finished(let winner):
            mode == .passAndPlay
                ? "\(displayName(for: winner)) wins!"
                : (winner == localPlayer ? "Victory!" : "Defeat!")
        }
    }

    var endTitle: String {
        guard case .finished(let winner) = turnState else { return "" }
        return mode == .passAndPlay
            ? "\(displayName(for: winner)) Wins!"
            : (winner == localPlayer ? "Victory!" : "Sunk!")
    }

    var endMessage: String {
        guard case .finished(let winner) = turnState else { return "" }
        switch mode {
        case .ai:
            return winner == localPlayer
                ? "\(captain.name)'s fleet rests at the bottom of the tub."
                : "\(captain.name) cackles as your last ship goes under."
        case .passAndPlay:
            return "\(displayName(for: winner.opponent))'s fleet rests at the bottom of the tub."
        case .gameCenter:
            let rival = onlineOpponentName ?? "Yer rival"
            return winner == localPlayer
                ? "\(rival)'s fleet rests at the bottom of the tub."
                : "\(rival) sent yer last ship to the drain."
        }
    }

    /// Coins earned by the local player for this match's result (not pass-and-play).
    /// Wins scale with the captain's reward multiplier.
    var coinReward: Int {
        guard mode != .passAndPlay, case .finished(let winner) = turnState else { return 0 }
        guard winner == localPlayer else { return 25 }
        // The onboarding battle was a gift, not a fight — a fixed pocket of
        // starter coins (enough for a couple of cheap power-ups, not the
        // whole armory shelf) keeps the earn-them-back hook intact.
        if isTutorial { return 150 }
        let base = 200 + 10 * (state.boards[localPlayer]?.survivingShipCellCount ?? 0)
        let multiplier = mode == .ai ? captain.rewardMultiplier : 1.0
        return Int((Double(base) * multiplier).rounded())
    }

    let isTutorial: Bool
    /// Specials the local player fired this battle (achievement tracking).
    private(set) var localSpecialsFired: Set<ShotType> = []
    /// Won without a single enemy shot landing.
    var wasFlawlessVictory: Bool {
        didWin && state.boards[localPlayer]?.hitCells.isEmpty == true
    }
    /// Equipped cosmetic fleet for the local player's own board (set by the view).
    var playerFleetID: String = "classic"
    /// The rival's fleet skin: ladder captains show off premium sets.
    var enemyFleetID: String {
        mode == .ai ? captain.fleetID : "classic"
    }

    init(config: MatchConfig) {
        consumesInventory = config.consumesInventory
        isTutorial = config.tutorial

        // The onboarding battle: mostly-sunk Dogbeard, full arsenal, easy finish.
        if config.tutorial {
            mode = .ai
            captain = Captain.dogbeard.tuned(sloppiness: 0.55, specialUseChance: 0)
            fixedLocalPlayer = .one
            state = Self.tutorialState()
            opponent = AIOpponentController(captain: captain)
            return
        }

        // Resume a locally saved battle when asked (and one actually exists).
        if config.resume, let saved = MatchSaveStore.load() {
            let savedCaptain = Captain.withID(saved.captainID)
            mode = saved.mode == .ai ? .ai : .passAndPlay
            captain = savedCaptain
            fixedLocalPlayer = .one
            state = saved.state
            activePlayer = saved.state.currentPlayer
            opponent = saved.mode == .ai ? AIOpponentController(captain: savedCaptain) : nil
            if mode == .ai, config.consumesInventory {
                // The stash is live: specials bought since leaving arm on
                // return (the per-match cap still holds inside enableShot).
                for shot in config.loadout where shot != .cannon {
                    state.enableShot(shot, for: fixedLocalPlayer)
                }
            }
            return
        }

        mode = config.mode
        captain = Captain.withID(config.captainID)
        fixedLocalPlayer = .one
        var rng = SystemRandomNumberGenerator()
        let boards: [PlayerID: Board] = [
            .one: config.playerBoard ?? Board.randomlyPlaced(using: &rng),
            .two: Board.randomlyPlaced(using: &rng),
        ]
        switch config.mode {
        case .ai, .gameCenter:
            // The rival mirrors the player's arsenal so difficulty scales with
            // progression instead of outgunning fresh captains.
            // (.gameCenter never lands here — online matches use init(gameCenterState:...).)
            state = GameState(boards: boards, loadouts: [
                .one: config.loadout,
                .two: config.loadout,
            ])
            opponent = AIOpponentController(
                captain: captain,
                thinkDelay: Self.debugAutoBattle ? .milliseconds(80) : .milliseconds(900)
            )
        case .passAndPlay:
            // Both captains share the profile's unlocked arsenal — simple and fair.
            state = GameState(boards: boards, loadouts: [
                .one: config.loadout,
                .two: config.loadout,
            ])
            opponent = nil
        }

        #if DEBUG
        // Screenshot staging: -chatLine "Arr!" pins a rival quick-chat bubble
        // once the auto-battle has developed the board.
        if let line = Self.debugChatLine {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.chatLine = ChatLine(text: line, mine: false)
            }
        }
        #endif
    }

    /// Builds the onboarding battle: fixed fleets, with a scripted exchange of
    /// cannon fire already applied so three of Dogbeard's ships are sunk and
    /// only his duck sub and dinghy remain. The player holds every special.
    private static func tutorialState() -> GameState {
        var enemy = Board()
        try! enemy.place(.galleon, at: Coordinate(row: 0, col: 0), orientation: .horizontal)
        try! enemy.place(.frigate, at: Coordinate(row: 2, col: 0), orientation: .horizontal)
        try! enemy.place(.tugboat, at: Coordinate(row: 4, col: 0), orientation: .horizontal)
        try! enemy.place(.duckSub, at: Coordinate(row: 6, col: 6), orientation: .vertical)
        try! enemy.place(.dinghy, at: Coordinate(row: 9, col: 8), orientation: .horizontal)

        var mine = Board()
        try! mine.place(.galleon, at: Coordinate(row: 0, col: 0), orientation: .horizontal)
        try! mine.place(.frigate, at: Coordinate(row: 2, col: 0), orientation: .horizontal)
        try! mine.place(.tugboat, at: Coordinate(row: 4, col: 0), orientation: .horizontal)
        try! mine.place(.duckSub, at: Coordinate(row: 6, col: 0), orientation: .vertical)
        try! mine.place(.dinghy, at: Coordinate(row: 9, col: 4), orientation: .horizontal)

        var state = GameState(
            boards: [.one: mine, .two: enemy],
            loadouts: [.one: Set(ShotType.allCases), .two: []]
        )

        // The player's shots: sink the galleon, frigate, and tugboat.
        let playerShots: [Coordinate] = [
            Coordinate(row: 0, col: 0), Coordinate(row: 0, col: 1), Coordinate(row: 0, col: 2),
            Coordinate(row: 0, col: 3), Coordinate(row: 0, col: 4),
            Coordinate(row: 2, col: 0), Coordinate(row: 2, col: 1), Coordinate(row: 2, col: 2),
            Coordinate(row: 2, col: 3),
            Coordinate(row: 4, col: 0), Coordinate(row: 4, col: 1), Coordinate(row: 4, col: 2),
        ]
        // Dogbeard's shots: two hits on the galleon, the rest wide misses.
        let dogbeardShots: [Coordinate] = [
            Coordinate(row: 0, col: 0), Coordinate(row: 0, col: 1),
            Coordinate(row: 5, col: 5), Coordinate(row: 5, col: 6), Coordinate(row: 5, col: 7),
            Coordinate(row: 3, col: 4), Coordinate(row: 3, col: 5), Coordinate(row: 3, col: 6),
            Coordinate(row: 7, col: 7), Coordinate(row: 7, col: 8), Coordinate(row: 1, col: 7),
            Coordinate(row: 8, col: 8),
        ]
        for (playerShot, dogbeardShot) in zip(playerShots, dogbeardShots) {
            try! state.apply(Move(player: .one, shot: .cannon, target: playerShot))
            try! state.apply(Move(player: .two, shot: .cannon, target: dogbeardShot))
        }
        return state
    }

    /// True when the loaded match was already over — the end screen should
    /// show, but rewards were paid when it actually finished.
    private(set) var arrivedFinished = false

    /// Set when the local player leaves the match screen mid-game, so the
    /// unblocked opponent-wait can't masquerade as a forfeit win.
    private(set) var isAbandoned = false

    func abandon() {
        isAbandoned = true
    }

    /// Set when the player forfeits a local battle, so a move resolving
    /// mid-exit can't write the save back after it's cleared.
    private(set) var isForfeited = false

    /// Throws away a local (AI / pass-and-play) battle for good: no save,
    /// no "Resume Battle" on the menu. Online matches use abandon() instead.
    func forfeitLocalMatch() {
        isForfeited = true
        MatchSaveStore.clear()
    }

    /// Online matches arrive with a server-synced state and an assigned seat.
    /// When `initialBoards` (the untouched placement fleets) are provided, the
    /// state is rewound to just before any moves this device hasn't watched,
    /// and those moves are replayed with full animation once the scene is up —
    /// so a rival's overnight shot is seen landing, not found as a stale mark.
    init(
        gameCenterState: GameState,
        localPlayer: PlayerID,
        controller: GameCenterController,
        initialBoards: [PlayerID: Board]? = nil
    ) {
        consumesInventory = false
        isTutorial = false
        captain = .dogbeard // unused online; portraits come from Game Center identities
        mode = .gameCenter(matchID: controller.match.matchID)
        fixedLocalPlayer = localPlayer
        let replay = Self.catchUpReplay(
            finalState: gameCenterState,
            localPlayer: localPlayer,
            initialBoards: initialBoards,
            matchID: controller.match.matchID
        )
        state = replay.baseline
        pendingReplayMoves = replay.moves
        catchUpTargetState = gameCenterState
        opponent = controller
        controller.markKnown(state: gameCenterState)
        arrivedFinished = gameCenterState.phase != .active
        onlineOpponentName = controller.opponentDisplayName
        onlineOpponentAvatarID = controller.opponentAvatarID
        controller.onTaunt = { [weak self] message in
            self?.showChat(ChatLine(text: message, mine: false))
        }
    }

    // MARK: - Catch-up replay (online)

    /// Moves this device hasn't watched yet, animated when the match screen opens.
    private var pendingReplayMoves: [Move] = []
    /// The server-synced state the replay must land on (desync escape hatch).
    private var catchUpTargetState: GameState?
    /// True while the away-recap volley plays (drives the status banner).
    private(set) var isCatchingUp = false

    /// Bounds the recap when the seen record is stale (e.g. a device switch);
    /// alternating turns mean a fresh record only ever trails by one move.
    private static let maxReplayMoves = 6

    /// Rewinds to the last state this device watched by replaying the shared
    /// move log from the initial placement boards (`apply` is deterministic,
    /// so the rebuilt states match the server's exactly). Returns the final
    /// state untouched whenever a rewind isn't possible or needed.
    private static func catchUpReplay(
        finalState: GameState,
        localPlayer: PlayerID,
        initialBoards: [PlayerID: Board]?,
        matchID: String
    ) -> (baseline: GameState, moves: [Move]) {
        let log = finalState.moveLog
        guard let boards = initialBoards, boards[.one] != nil, boards[.two] != nil else {
            return (finalState, [])
        }
        // First unwatched move: the recorded count when available, otherwise
        // the rival's trailing run (their moves since our last shot).
        var firstUnseen: Int
        if let seen = SeenMovesStore.seenCount(for: matchID) {
            firstUnseen = min(seen, log.count)
        } else {
            firstUnseen = log.count
            while firstUnseen > 0, log[firstUnseen - 1].player != localPlayer {
                firstUnseen -= 1
            }
        }
        firstUnseen = max(firstUnseen, log.count - maxReplayMoves)
        guard firstUnseen < log.count else { return (finalState, []) }

        // Everyone gets the full arsenal online (mirrors submitSetup).
        let arsenal = Set(ShotType.allCases)
        var baseline = GameState(boards: boards, loadouts: [.one: arsenal, .two: arsenal])
        for move in log.prefix(firstUnseen) {
            guard (try? baseline.apply(move)) != nil else { return (finalState, []) }
        }
        return (baseline, Array(log.suffix(from: firstUnseen)))
    }

    private func playCatchUpReplay() async {
        let moves = pendingReplayMoves
        pendingReplayMoves = []
        // Wait out scene presentation, then a beat so the player reorients
        // before the volley lands.
        var waited = 0
        while renderer?.isPresented != true, waited < 40 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        try? await Task.sleep(for: .milliseconds(450))

        for move in moves {
            guard !isAbandoned else { return }
            guard let resolution = try? state.apply(move) else {
                // Deterministic replay shouldn't diverge; if it ever does,
                // snap to the server-synced state rather than desync.
                if let target = catchUpTargetState { state = target }
                renderer?.refreshBoards()
                break
            }
            let mine = move.player == localPlayer
            turnState = mine ? .resolvingPlayerShot : .resolvingOpponentShot
            await renderer?.playResolution(resolution, onEnemyBoard: mine)
            playHaptics(for: resolution)
        }
        isCatchingUp = false
        if case .gameCenter(let matchID) = mode {
            SeenMovesStore.record(state.moveLog.count, for: matchID)
        }

        if case .finished(let winner) = state.phase {
            turnState = .finished(winner: winner)
            finalizeOnlineMatchIfNeeded()
            return
        }
        if state.currentPlayer == localPlayer {
            turnState = .playerTargeting
            schedulePlayerAutoMoveIfNeeded()
        } else {
            await awaitOpponentMove()
        }
    }

    /// A finished game whose Game Center match is still live means the winning
    /// device died before endMatchInTurn landed — without this, the match
    /// says "your turn" forever. Safe to fire on every finished (re)entry;
    /// the controller no-ops when the match already ended server-side.
    private func finalizeOnlineMatchIfNeeded() {
        guard case .gameCenter = mode,
              let controller = opponent as? GameCenterController else { return }
        let finishedState = state
        Task { await controller.finalizeFinishedMatchIfNeeded(state: finishedState) }
    }

    /// Called once the scene is wired up; kicks off auto-play when enabled.
    func matchDidStart() {
        // Revisiting a match that already ended (e.g. from Game Center's
        // match list): straight to the end state, no listening for turns.
        if case .finished(let winner) = state.phase {
            turnState = .finished(winner: winner)
            finalizeOnlineMatchIfNeeded()
            return
        }
        saveIfNeeded()
        if mode == .ai, state.moveLog.isEmpty {
            speak(.matchStart)
        }
        schedulePlayerAutoMoveIfNeeded()
        switch mode {
        case .passAndPlay:
            // Resuming (or starting) pass-and-play opens on the privacy cover
            // so the right captain takes the device.
            if state.phase == .active, !state.moveLog.isEmpty {
                turnState = .awaitingHandoff(next: state.currentPlayer)
            }
        case .ai, .gameCenter:
            if !pendingReplayMoves.isEmpty {
                // Lock input and replay the rival's unseen shot(s) first.
                isCatchingUp = true
                turnState = .resolvingOpponentShot
                Task { await playCatchUpReplay() }
                return
            }
            if case .gameCenter(let matchID) = mode {
                // Nothing to recap — baseline the watched count for next time.
                SeenMovesStore.record(state.moveLog.count, for: matchID)
            }
            // Rejoining on the opponent's turn: start listening/thinking.
            if state.currentPlayer != localPlayer, state.phase == .active {
                Task { await awaitOpponentMove() }
            }
        }
    }

    /// Persists AI and pass-and-play battles so leaving mid-match isn't fatal.
    private func saveIfNeeded() {
        guard !isTutorial else { return } // the onboarding battle is disposable
        guard !isForfeited else { return } // forfeited: the save stays cleared
        let savedMode: SavedMatch.SavedMode
        switch mode {
        case .ai: savedMode = .ai
        case .passAndPlay: savedMode = .passAndPlay
        case .gameCenter: return // lives on Game Center's servers
        }
        guard state.phase == .active else {
            MatchSaveStore.clear()
            return
        }
        MatchSaveStore.save(SavedMatch(
            mode: savedMode,
            state: state,
            activePlayer: activePlayer,
            loadout: Set(state.availableShots(for: .one)),
            captainID: captain.id
        ))
    }

    // MARK: - Shot panel

    /// The panel's fixed display order with live remaining-use counts (nil = unlimited).
    var shotsForPanel: [(shot: ShotType, remaining: Int?)] {
        [.cannon, .parrotScout, .bigShot, .flare, .chainShot, .fireworks].map {
            ($0, state.remainingUses(of: $0, for: localPlayer))
        }
    }

    func select(_ shot: ShotType) {
        guard turnState == .playerTargeting else { return }
        guard state.remainingUses(of: shot, for: localPlayer) ?? 1 > 0 else { return }
        selectedShot = shot
    }

    /// Can this empty special slot be refilled with doubloons right now?
    /// (Real-economy AI battles only; the once-per-match cap still applies.)
    func canOfferPurchase(of shot: ShotType) -> Bool {
        guard mode == .ai, consumesInventory, shot != .cannon else { return false }
        guard (state.remainingUses(of: shot, for: localPlayer) ?? 1) == 0 else { return false }
        return !state.moveLog.contains { $0.player == localPlayer && $0.shot == shot }
    }

    /// Arms a special the player just bought mid-battle and selects it.
    func armPurchasedShot(_ shot: ShotType) {
        guard state.enableShot(shot, for: localPlayer) else { return }
        if turnState == .playerTargeting {
            selectedShot = shot
        }
    }

    func toggleOrientation() {
        selectedOrientation = selectedOrientation.toggled
    }

    /// Fires the untargeted flare (the view confirms before calling this).
    func fireFlare() {
        guard turnState == .playerTargeting else { return }
        selectedShot = .cannon // flare resolves immediately; drop back to the cannon
        let move = Move(player: localPlayer, shot: .flare)
        guard state.validate(move) == nil else { return }
        turnState = .resolvingPlayerShot
        Task { await resolveAndContinue(move) }
    }

    // MARK: - Input

    /// Footprint of the currently selected shot at a candidate target cell.
    func previewFootprint(at cell: Coordinate) -> [Coordinate] {
        selectedShot.spec.pattern(cell, selectedOrientation)
    }

    func isValidTarget(_ cell: Coordinate) -> Bool {
        let move = Move(
            player: localPlayer,
            shot: selectedShot,
            target: cell,
            orientation: selectedShot.spec.needsOrientation ? selectedOrientation : nil
        )
        return state.validate(move) == nil
    }

    /// Called by the scene when the player taps a cell on the enemy board.
    func handleTap(at cell: Coordinate) {
        guard turnState == .playerTargeting else { return }
        submitPlayerMove(target: cell)
    }

    func submitPlayerMove(target: Coordinate?) {
        guard turnState == .playerTargeting else { return }
        let move = Move(
            player: localPlayer,
            shot: selectedShot,
            target: target,
            orientation: selectedShot.spec.needsOrientation ? selectedOrientation : nil
        )
        guard state.validate(move) == nil else { return } // invalid taps are just ignored
        turnState = .resolvingPlayerShot
        Task { await resolveAndContinue(move) }
    }

    // MARK: - Turn machine

    private func resolveAndContinue(_ move: Move) async {
        guard let resolution = try? state.apply(move) else {
            turnState = state.currentPlayer == localPlayer ? .playerTargeting : .opponentThinking
            return
        }

        if move.player == localPlayer, move.shot != .cannon {
            // Lifetime record for achievements (any mode, consumed or comped).
            localSpecialsFired.insert(move.shot)
            // Consumable accounting: a fired special is spent when it resolves.
            if consumesInventory {
                onLocalSpecialFired?(move.shot)
            }
        }

        await renderer?.playResolution(resolution, onEnemyBoard: move.player == localPlayer)
        playHaptics(for: resolution)
        reactToResolution(resolution)

        // Online: our own applied move must reach Game Center before anything
        // else (submitLocalTurn also ends the match when this move won it).
        // A failed send parks the turn for an explicit retry — advancing (or
        // paying out a win) on an unsent move desyncs us from the server and
        // makes the reward repeatable.
        if case .gameCenter = mode, move.player == localPlayer {
            guard await submitTurnToGameCenter(resolution: resolution) else {
                pendingSubmitResolution = resolution
                turnState = .submitFailed
                return
            }
        }

        await advanceAfterResolution(resolution)
    }

    /// The resolution whose Game Center submit failed, held for retry.
    private var pendingSubmitResolution: MoveResolution?

    /// Sends the applied local move to Game Center. Returns false on failure.
    private func submitTurnToGameCenter(resolution: MoveResolution) async -> Bool {
        guard let controller = opponent as? GameCenterController else { return true }
        do {
            try await controller.submitLocalTurn(
                state: state,
                taunt: pendingTaunt,
                pushMessage: Self.turnPushMessage(for: resolution)
            )
            pendingTaunt = nil
            return true
        } catch {
            return false
        }
    }

    /// The rival's notification text for the move we just made — written from
    /// the RECEIVER's point of view (it lands on the defender's device).
    private static func turnPushMessage(for resolution: MoveResolution) -> String {
        let name = GKLocalPlayer.local.alias
        if resolution.winner != nil {
            return "☠️ \(name) sank your fleet — the battle is lost!"
        }
        if let sunk = resolution.sunkShips.first {
            return "🔥 \(name) sank your \(sunk.kind.displayName)! Your move, Captain."
        }
        if resolution.move.shot.spec.effect != .damage {
            return "🔭 \(name) scouted your waters — your move, Captain!"
        }
        if resolution.cellResults.contains(where: { $0.outcome == .hit }) {
            return "💥 \(name) hit your fleet — your move, Captain!"
        }
        return "🌊 \(name)'s shot splashed into the tub — your move, Captain!"
    }

    /// Retry a send that failed (the "no wind in the sails" banner's button).
    func retrySubmit() {
        guard turnState == .submitFailed, let resolution = pendingSubmitResolution else { return }
        turnState = .resolvingPlayerShot
        Task {
            guard await submitTurnToGameCenter(resolution: resolution) else {
                turnState = .submitFailed
                return
            }
            pendingSubmitResolution = nil
            await advanceAfterResolution(resolution)
        }
    }

    /// Everything that happens after a resolved move is safely persisted:
    /// bookkeeping, then the turn handoff.
    private func advanceAfterResolution(_ resolution: MoveResolution) async {
        saveIfNeeded()
        // This device just WATCHED the move land — don't recap it later. An
        // abandoned/detached view model doesn't count as watching (the scene
        // is gone), or the catch-up replay would skip a shot nobody saw.
        if case .gameCenter(let matchID) = mode, !isAbandoned, renderer?.isPresented == true {
            SeenMovesStore.record(state.moveLog.count, for: matchID)
        }

        if let winner = resolution.winner {
            turnState = .finished(winner: winner)
            return
        }

        switch mode {
        case .passAndPlay:
            // Swap perspective behind the privacy cover before the next captain looks.
            let next = state.currentPlayer
            turnState = .awaitingHandoff(next: next)
            activePlayer = next
            selectedShot = .cannon
            renderer?.refreshBoards()
        case .ai, .gameCenter:
            if state.currentPlayer == localPlayer {
                // A spent special can't stay selected.
                if state.remainingUses(of: selectedShot, for: localPlayer) == 0 {
                    selectedShot = .cannon
                }
                turnState = .playerTargeting
                schedulePlayerAutoMoveIfNeeded()
            } else {
                await awaitOpponentMove()
            }
        }
    }

    private func awaitOpponentMove() async {
        guard let opponent else { return }
        turnState = .opponentThinking
        guard let opponentMove = await opponent.nextMove(state: state) else {
            // nil means the wait ended without a move. If WE abandoned the
            // screen (Leave button unblocks the wait), just stop — declaring
            // a forfeit win here flashed the victory screen on the way out.
            guard !isAbandoned else { return }
            // Otherwise the opponent forfeited (online quit/timeout).
            turnState = .finished(winner: localPlayer)
            return
        }
        turnState = .resolvingOpponentShot
        await resolveAndContinue(opponentMove)
    }

    /// The incoming captain confirmed they have the device (pass-and-play).
    func confirmHandoff() {
        guard case .awaitingHandoff = turnState else { return }
        turnState = .playerTargeting
    }

    // MARK: - Captain table talk

    /// Picks the rival captain's reaction to a resolved move (AI matches only).
    private func reactToResolution(_ resolution: MoveResolution) {
        guard mode == .ai else { return }
        let isPlayerMove = resolution.move.player == localPlayer
        let hit = resolution.cellResults.contains { $0.outcome == .hit }
        let sunk = !resolution.sunkShips.isEmpty

        let event: DialogEvent
        if isPlayerMove {
            if sunk { event = .playerSunkShip }
            else if resolution.move.shot != .cannon { event = .playerSpecial }
            else if hit { event = .playerHit }
            else { event = .playerMiss }
        } else {
            if sunk { event = .captainSunkShip }
            else if hit { event = .captainHit }
            else { event = .captainMiss }
        }
        speak(event)
    }

    private func speak(_ event: DialogEvent) {
        #if DEBUG
        if Self.debugEnemyName != nil { return } // staged online frame: no captain banter
        #endif
        guard let line = CaptainDialog.line(for: event, from: captain, using: &dialogRNG) else { return }
        captainLine = line
        dialogDismissTask?.cancel()
        dialogDismissTask = Task {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            captainLine = nil
        }
    }

    private func playHaptics(for resolution: MoveResolution) {
        if !resolution.sunkShips.isEmpty {
            Haptics.notify(.success)
        } else if resolution.cellResults.contains(where: { $0.outcome == .hit }) {
            Haptics.impact(.medium)
        }
    }

    private func schedulePlayerAutoMoveIfNeeded() {
        guard autoPlay, turnState == .playerTargeting else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard turnState == .playerTargeting else { return }
            let move = playerAI.chooseMove(
                as: localPlayer,
                observing: enemyView,
                remainingUses: state.remainingUses[localPlayer] ?? [:]
            )
            turnState = .resolvingPlayerShot
            await resolveAndContinue(move)
        }
    }
}
