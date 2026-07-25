import Foundation

/// Canned taunts for online matches. Canned-only keeps chat 4+-safe (no
/// user-generated text to moderate) — and doubles as validation: clients
/// only display messages that appear in this list.
enum QuickChat {
    static let lines: [String] = [
        "Ahoy, matey! 👋",
        "Nice shot!",
        "Lucky splash...",
        "Ye'll pay for that!",
        "My toys are unsinkable!",
        "Glub glub... 😱",
        "Har har HAR!",
        "Well played, captain.",
    ]

    static func isValid(_ message: String) -> Bool {
        lines.contains(message)
    }
}

/// A taunt carried inside the online match data, stamped with the move
/// count at send time so receivers can tell new from already-seen.
struct Taunt: Codable, Hashable {
    var message: String
    var atMove: Int
}
