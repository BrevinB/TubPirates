import Foundation

/// How many moves of each online match's log this device has actually WATCHED
/// (live or via the catch-up replay) — not just received. Reopening a match
/// replays anything beyond this count so a rival's overnight shot is seen
/// landing, not discovered as a stale mark on the board.
enum SeenMovesStore {
    private static let key = "onlineSeenMoves.v1"

    private static var counts: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func seenCount(for matchID: String) -> Int? {
        counts[matchID]
    }

    static func record(_ count: Int, for matchID: String) {
        var all = counts
        // A stale turn event can carry fewer moves than we've already watched.
        all[matchID] = max(count, all[matchID] ?? 0)
        counts = all
    }

    /// Drops records for matches Game Center no longer lists.
    static func prune(keeping matchIDs: [String]) {
        counts = counts.filter { matchIDs.contains($0.key) }
    }
}
