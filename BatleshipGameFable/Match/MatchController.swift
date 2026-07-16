import BathtubEngine

struct MatchConfig: Hashable {
    enum Mode: Hashable {
        case ai
        case passAndPlay
        /// Route-friendly reference; the live GKTurnBasedMatch lives in GameCenterService.
        case gameCenter(matchID: String)
    }

    var mode: Mode = .ai
    /// The player's placed fleet; nil = random placement.
    var playerBoard: Board?
    /// Shot types the player brings into battle (from the profile's unlocks).
    var loadout: Set<ShotType> = [.cannon]
    /// Restore the match saved in MatchSaveStore instead of starting fresh.
    var resume: Bool = false
}

/// Supplies the non-local player's moves (AI locally, Game Center online).
/// Returning nil means the opponent forfeited — the local player wins.
protocol OpponentController: AnyObject {
    func nextMove(state: GameState) async -> Move?
}
