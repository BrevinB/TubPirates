import Foundation
import BathtubEngine

/// What rides inside GKTurnBasedMatch.matchData (JSON, a few KB — far under the 64KB cap).
///
/// Two phases:
/// 1. Setup — each participant contributes their board ("0" = participants[0] = PlayerID.one).
/// 2. Play — once both boards exist, `state` is initialized and moves append to its log.
struct OnlineMatchData: Codable {
    /// Schema version, bumped on any non-additive payload change so old
    /// clients can tell "newer schema" apart from "new match". Optional so
    /// pre-version payloads still decode.
    static let currentVersion = 1
    var version: Int? = currentVersion
    var boards: [String: Board] = [:]
    var state: GameState?
    /// Each seat's chosen in-game avatar ("0"/"1" → avatarID), so rivals see
    /// your duck, not a placeholder. Optional for pre-existing match data.
    var avatars: [String: String]?
    /// Each seat's latest canned taunt ("0"/"1" → Taunt). Optional for
    /// pre-existing match data.
    var taunts: [String: Taunt]?

    var isReadyForBattle: Bool {
        state != nil
    }
}

enum MatchDataCodec {
    /// The payload couldn't be decoded (truncated, or written by a newer
    /// schema). Distinct from a NEW match, whose data is simply empty.
    struct CorruptMatchData: Error {}

    /// nil means the payload exists but couldn't be decoded — callers must
    /// treat that as read-only and NEVER write over it: encoding an
    /// empty-decoded struct back would wipe both players' boards and log.
    static func decode(_ data: Data?) -> OnlineMatchData? {
        guard let data, !data.isEmpty else { return OnlineMatchData() }
        return try? JSONDecoder().decode(OnlineMatchData.self, from: data)
    }

    static func encode(_ matchData: OnlineMatchData) throws -> Data {
        var stamped = matchData
        stamped.version = OnlineMatchData.currentVersion
        return try JSONEncoder().encode(stamped)
    }

    /// Maps a participant index to an engine player.
    static func player(forParticipantIndex index: Int) -> PlayerID {
        index == 0 ? .one : .two
    }
}
