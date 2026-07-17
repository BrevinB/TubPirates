import BathtubEngine

/// Dogbeard: wraps the engine's BattleAI with a small think delay so his
/// turns feel deliberate rather than instantaneous.
final class AIOpponentController: OpponentController {
    private var ai: BattleAI
    private let player: PlayerID
    private let thinkDelay: Duration

    init(player: PlayerID = .two, seed: UInt64? = nil, thinkDelay: Duration = .milliseconds(900)) {
        // Dogbeard is beatable: sometimes distracted mid-hunt, a bit stingier
        // with specials than a perfect player would be.
        self.ai = BattleAI(seed: seed, specialUseChance: 0.15, sloppiness: 0.18)
        self.player = player
        self.thinkDelay = thinkDelay
    }

    func nextMove(state: GameState) async -> Move? {
        try? await Task.sleep(for: thinkDelay)
        return ai.chooseMove(
            as: player,
            observing: state.attackerView(of: player.opponent),
            remainingUses: state.remainingUses[player] ?? [:]
        )
    }
}
