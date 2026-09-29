import Foundation

/// The friend-to-friend loop's signal taxonomy, defined once so the app and
/// the iMessage extension can't drift into two spellings of the same event.
/// Each target renders these through its own analytics sender.
public enum MessageAnalyticsEvent: Sendable {
    /// Someone opened the game inside a conversation; `screen` separates
    /// "started a challenge" from "answered one".
    case opened(screen: String)
    /// A challenge was handed to Messages. `source` is "extension" or "app",
    /// so both ends of the invite funnel land in one chart.
    case challengeSent(source: String)
    /// The invited pirate placed a fleet and joined — the conversion that
    /// actually matters for the loop.
    case challengeJoined
    case turnSent(shot: String)
    case battleFinished(won: Bool, byForfeit: Bool)
    case rematchSent
    /// A staged update never made it out, or a payload wouldn't decode.
    case flowFailed(stage: String)

    public var name: String {
        switch self {
        case .opened: "Messages.opened"
        case .challengeSent: "Messages.challengeSent"
        case .challengeJoined: "Messages.challengeJoined"
        case .turnSent: "Messages.turnSent"
        case .battleFinished: "Messages.battleFinished"
        case .rematchSent: "Messages.rematchSent"
        case .flowFailed: "Messages.flowFailed"
        }
    }

    public var parameters: [String: String] {
        switch self {
        case .opened(let screen): ["screen": screen]
        case .challengeSent(let source): ["source": source]
        case .challengeJoined, .rematchSent: [:]
        case .turnSent(let shot): ["shot": shot]
        case .battleFinished(let won, let byForfeit):
            ["won": String(won), "forfeit": String(byForfeit)]
        case .flowFailed(let stage): ["stage": stage]
        }
    }
}
