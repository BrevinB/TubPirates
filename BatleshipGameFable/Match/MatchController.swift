import BathtubEngine

struct MatchConfig: Hashable {
    enum Mode: Hashable {
        case ai
        // .passAndPlay and .gameCenter arrive in later milestones.
    }

    var mode: Mode = .ai
}

/// Supplies the non-local player's moves. AI now; pass-and-play and
/// Game Center implement the same protocol later.
protocol OpponentController: AnyObject {
    func nextMove(state: GameState) async -> Move
}
