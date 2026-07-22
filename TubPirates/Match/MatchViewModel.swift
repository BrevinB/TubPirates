import Foundation
import GameKit
import Observation
import UIKit
import BathtubEngine

/// What the scene must be able to render on the view model's behalf.
/// Async methods complete when their animations finish — they gate the turn machine.
@MainActor
protocol BattleSceneRendering: AnyObject {
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
    private let autoPlay = CommandLine.arguments.contains("-autoBattle")
    private var playerAI = BattleAI()

    /// The rival captain's current speech-bubble line (AI matches only).
    private(set) var captainLine: String?
    private var dialogRNG = SystemRandomNumberGenerator()
    private var dialogDismissTask: Task<Void, Never>?

    /// Drives the end screen's celebratory vs somber styling.
    var didWin: Bool {
        guard case .finished(let winner) = turnState else { return false }
        return mode == .passAndPlay || winner == .one
    }

    /// Which portrait to spotlight in the HUD right now.
    var highlightedPlayer: PlayerID? {
        switch turnState {
        case .finished, .awaitingHandoff: nil
        case .playerTargeting, .resolvingPlayerShot: localPlayer
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

    func displayName(for player: PlayerID) -> String {
        switch mode {
        case .ai: player == localPlayer ? "You" : captain.name
        case .passAndPlay: player == .one ? "Captain 1" : "Captain 2"
        case .gameCenter: player == localPlayer ? "You" : "Opponent"
        }
    }

    /// Portrait asset for the enemy card in the HUD.
    var enemyPortrait: String {
        mode == .ai ? captain.portrait : "portrait_dogbeard"
    }

    var statusText: String {
        switch turnState {
        case .playerTargeting:
            mode == .passAndPlay ? "\(displayName(for: activePlayer)) — fire!" : "Your turn — fire!"
        case .resolvingPlayerShot: "Firing..."
        case .opponentThinking:
            mode == .ai ? "\(captain.name) is aiming..." : "\(displayName(for: localPlayer.opponent)) is aiming..."
        case .resolvingOpponentShot: "Incoming!"
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
            return winner == localPlayer
                ? "Your rival's fleet rests at the bottom of the tub."
                : "Your last ship gurgles to the bottom of the tub."
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
                thinkDelay: CommandLine.arguments.contains("-autoBattle") ? .milliseconds(80) : .milliseconds(900)
            )
        case .passAndPlay:
            // Both captains share the profile's unlocked arsenal — simple and fair.
            state = GameState(boards: boards, loadouts: [
                .one: config.loadout,
                .two: config.loadout,
            ])
            opponent = nil
        }
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

    /// Online matches arrive with a server-synced state and an assigned seat.
    init(gameCenterState: GameState, localPlayer: PlayerID, controller: GameCenterController) {
        consumesInventory = false
        isTutorial = false
        captain = .dogbeard // unused online; portraits come from Game Center identities
        mode = .gameCenter(matchID: controller.match.matchID)
        fixedLocalPlayer = localPlayer
        state = gameCenterState
        opponent = controller
        controller.markKnown(state: gameCenterState)
        arrivedFinished = state.phase != .active
    }

    /// Called once the scene is wired up; kicks off auto-play when enabled.
    func matchDidStart() {
        // Revisiting a match that already ended (e.g. from Game Center's
        // match list): straight to the end state, no listening for turns.
        if case .finished(let winner) = state.phase {
            turnState = .finished(winner: winner)
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
            // Rejoining on the opponent's turn: start listening/thinking.
            if state.currentPlayer != localPlayer, state.phase == .active {
                Task { await awaitOpponentMove() }
            }
        }
    }

    /// Persists AI and pass-and-play battles so leaving mid-match isn't fatal.
    private func saveIfNeeded() {
        guard !isTutorial else { return } // the onboarding battle is disposable
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

        // Online: our own applied move must reach Game Center before anything else
        // (submitLocalTurn also ends the match when this move won it).
        if case .gameCenter = mode, move.player == localPlayer,
           let controller = opponent as? GameCenterController {
            try? await controller.submitLocalTurn(state: state)
        }

        saveIfNeeded()

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
            // Opponent forfeited (online quit).
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
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "hapticsEnabled") == nil || defaults.bool(forKey: "hapticsEnabled")
        guard enabled else { return }
        if !resolution.sunkShips.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if resolution.cellResults.contains(where: { $0.outcome == .hit }) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
