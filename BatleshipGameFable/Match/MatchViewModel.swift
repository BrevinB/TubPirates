import Observation
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
        case finished(winner: PlayerID)
    }

    private(set) var state: GameState
    private(set) var turnState: TurnState = .playerTargeting
    let localPlayer: PlayerID = .one
    var selectedShot: ShotType = .cannon
    var selectedOrientation: Orientation = .horizontal

    private let opponent: OpponentController
    weak var renderer: BattleSceneRendering?

    /// Debug/demo: an AI plays the local side too (`-autoBattle` launch argument).
    private let autoPlay = CommandLine.arguments.contains("-autoBattle")
    private var playerAI = BattleAI()

    var didWin: Bool {
        turnState == .finished(winner: localPlayer)
    }

    /// The enemy board as the local player is allowed to see it.
    var enemyView: AttackerView {
        state.attackerView(of: localPlayer.opponent)
    }

    var ownBoard: Board {
        state.boards[localPlayer] ?? Board()
    }

    var statusText: String {
        switch turnState {
        case .playerTargeting: "Your turn — fire!"
        case .resolvingPlayerShot: "Firing..."
        case .opponentThinking: "Dogbeard is aiming..."
        case .resolvingOpponentShot: "Incoming!"
        case .finished(let winner): winner == localPlayer ? "Victory!" : "Defeat!"
        }
    }

    init(config: MatchConfig) {
        var rng = SystemRandomNumberGenerator()
        let boards: [PlayerID: Board] = [
            .one: Board.randomlyPlaced(using: &rng),
            .two: Board.randomlyPlaced(using: &rng),
        ]
        // M2: cannon-only loadouts. Unlocked specials arrive with the armory milestone.
        state = GameState(boards: boards, loadouts: [.one: [], .two: []])
        opponent = AIOpponentController(
            thinkDelay: CommandLine.arguments.contains("-autoBattle") ? .milliseconds(80) : .milliseconds(900)
        )
    }

    /// Called once the scene is wired up; kicks off auto-play when enabled.
    func matchDidStart() {
        schedulePlayerAutoMoveIfNeeded()
    }

    // MARK: - Input

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

        if let winner = resolution.winner {
            turnState = .finished(winner: winner)
            return
        }

        if state.currentPlayer == localPlayer {
            turnState = .playerTargeting
            schedulePlayerAutoMoveIfNeeded()
        } else {
            turnState = .opponentThinking
            let opponentMove = await opponent.nextMove(state: state)
            turnState = .resolvingOpponentShot
            await resolveAndContinue(opponentMove)
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
