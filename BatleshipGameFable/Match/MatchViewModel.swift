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

    /// Debug/demo: an AI plays the local side too (`-autoBattle` launch argument).
    private let autoPlay = CommandLine.arguments.contains("-autoBattle")
    private var playerAI = BattleAI()

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
        case .ai: player == localPlayer ? "You" : "Dogbeard"
        case .passAndPlay: player == .one ? "Captain 1" : "Captain 2"
        case .gameCenter: player == localPlayer ? "You" : "Opponent"
        }
    }

    var statusText: String {
        switch turnState {
        case .playerTargeting:
            mode == .passAndPlay ? "\(displayName(for: activePlayer)) — fire!" : "Your turn — fire!"
        case .resolvingPlayerShot: "Firing..."
        case .opponentThinking: "\(displayName(for: localPlayer.opponent)) is aiming..."
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
                ? "Dogbeard's fleet rests at the bottom of the tub."
                : "Dogbeard cackles as your last ship goes under."
        case .passAndPlay:
            return "\(displayName(for: winner.opponent))'s fleet rests at the bottom of the tub."
        case .gameCenter:
            return winner == localPlayer
                ? "Your rival's fleet rests at the bottom of the tub."
                : "Your last ship gurgles to the bottom of the tub."
        }
    }

    /// Coins earned by the local player for this match's result (not pass-and-play).
    var coinReward: Int {
        guard mode != .passAndPlay, case .finished(let winner) = turnState else { return 0 }
        return winner == localPlayer
            ? 200 + 10 * (state.boards[localPlayer]?.survivingShipCellCount ?? 0)
            : 25
    }

    init(config: MatchConfig) {
        // Resume a locally saved battle when asked (and one actually exists).
        if config.resume, let saved = MatchSaveStore.load() {
            mode = saved.mode == .ai ? .ai : .passAndPlay
            fixedLocalPlayer = .one
            state = saved.state
            activePlayer = saved.state.currentPlayer
            opponent = saved.mode == .ai ? AIOpponentController() : nil
            return
        }

        mode = config.mode
        fixedLocalPlayer = .one
        var rng = SystemRandomNumberGenerator()
        let boards: [PlayerID: Board] = [
            .one: config.playerBoard ?? Board.randomlyPlaced(using: &rng),
            .two: Board.randomlyPlaced(using: &rng),
        ]
        switch config.mode {
        case .ai, .gameCenter:
            // Dogbeard always sails fully armed; the player brings their unlocked arsenal.
            // (.gameCenter never lands here — online matches use init(gameCenterState:...).)
            state = GameState(boards: boards, loadouts: [
                .one: config.loadout,
                .two: Set(ShotType.allCases),
            ])
            opponent = AIOpponentController(
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

    /// Online matches arrive with a server-synced state and an assigned seat.
    init(gameCenterState: GameState, localPlayer: PlayerID, controller: GameCenterController) {
        mode = .gameCenter(matchID: controller.match.matchID)
        fixedLocalPlayer = localPlayer
        state = gameCenterState
        opponent = controller
        controller.markKnown(state: gameCenterState)
    }

    /// Called once the scene is wired up; kicks off auto-play when enabled.
    func matchDidStart() {
        saveIfNeeded()
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
            loadout: Set(state.availableShots(for: .one))
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

        await renderer?.playResolution(resolution, onEnemyBoard: move.player == localPlayer)
        playHaptics(for: resolution)

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
