import Foundation
import BathtubEngine

/// What rides inside GKTurnBasedMatch.matchData (JSON, a few KB — far under the 64KB cap).
///
/// Two phases:
/// 1. Setup — each participant contributes their board ("0" = participants[0] = PlayerID.one).
/// 2. Play — once both boards exist, `state` is initialized and moves append to its log.
struct OnlineMatchData: Codable {
    var boards: [String: Board] = [:]
    var state: GameState?
    /// Each seat's chosen in-game avatar ("0"/"1" → avatarID), so rivals see
    /// your duck, not a placeholder. Optional for pre-existing match data.
    var avatars: [String: String]?

    var isReadyForBattle: Bool {
        state != nil
    }
}

enum MatchDataCodec {
    static func decode(_ data: Data?) -> OnlineMatchData {
        guard let data, !data.isEmpty else { return OnlineMatchData() }
        return (try? JSONDecoder().decode(OnlineMatchData.self, from: data)) ?? OnlineMatchData()
    }

    static func encode(_ matchData: OnlineMatchData) throws -> Data {
        try JSONEncoder().encode(matchData)
    }

    /// Maps a participant index to an engine player.
    static func player(forParticipantIndex index: Int) -> PlayerID {
        index == 0 ? .one : .two
    }
}
