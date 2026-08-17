import BathtubEngine

struct MatchConfig: Hashable {
    enum Mode: Hashable {
        case ai
        case passAndPlay
        /// Route-friendly reference; the live GKTurnBasedMatch lives in GameCenterService.
        case gameCenter(matchID: String)
    }

    var mode: Mode = .ai
    /// Which rival captain an AI battle is against.
    var captainID: String = Captain.dogbeard.id
    /// The player's placed fleet; nil = random placement.
    var playerBoard: Board?
    /// Shot types the player brings into battle (from the profile's stash).
    var loadout: Set<ShotType> = [.cannon]
    /// Shot types an AI rival brings. nil mirrors `loadout` (tutorial, debug,
    /// pass-and-play); ladder battles pass the armory's in-stock set so
    /// rivals wield specials whether or not the player bought any.
    var rivalLoadout: Set<ShotType>?
    /// Firing a special deducts a use from the profile stash (AI battles;
    /// off for pass-and-play, online, and the debug all-shots override).
    var consumesInventory: Bool = false
    /// Restore the match saved in MatchSaveStore instead of starting fresh.
    var resume: Bool = false
    /// The onboarding battle: starts nearly won with a full comped arsenal.
    var tutorial: Bool = false

    /// The onboarding battle config: every special comped, nothing consumed.
    static var tutorialBattle: MatchConfig {
        MatchConfig(
            mode: .ai,
            loadout: Set(ShotType.allCases),
            consumesInventory: false,
            tutorial: true
        )
    }
}

/// Supplies the non-local player's moves (AI locally, Game Center online).
/// Returning nil means the opponent forfeited — the local player wins.
protocol OpponentController: AnyObject {
    func nextMove(state: GameState) async -> Move?
}
