import BathtubEngine

/// Dogbeard's table talk — picked per game event and shown as a speech
/// bubble under his portrait. AI matches only.
enum DogbeardDialog {
    enum Event {
        case matchStart
        case playerHit          // the player hit one of Dogbeard's ships
        case playerMiss
        case playerSunkShip     // the player sank one of Dogbeard's ships
        case playerSpecial      // the player fired a special shot
        case dogbeardHit        // Dogbeard hit the player
        case dogbeardMiss
        case dogbeardSunkShip   // Dogbeard sank one of the player's ships
    }

    private static let lines: [Event: [String]] = [
        .matchStart: [
            "Arf arf! Prepare to be scrubbed, landlubber!",
            "Me tub, me rules. Fire when ready, pup!",
            "I smell fresh bilge water... and victory!",
        ],
        .playerHit: [
            "Yowch! Ye scratched me paint!",
            "Lucky splash, that's all it were!",
            "Grr... me poor toy boat!",
            "Belay that! That one stung!",
        ],
        .playerMiss: [
            "Har har! Not even close!",
            "Ye couldn't hit the broad side of a bathtub!",
            "That splash didn't even wet me whiskers!",
            "Keep firin' like that and I'll nap through it!",
        ],
        .playerSunkShip: [
            "NOOO! Not me favorite bath toy!",
            "Ye'll pay for that, scallywag!",
            "Blub blub... she was a fine vessel.",
        ],
        .playerSpecial: [
            "Hey! Where'd ye get fancy cannons?!",
            "That be cheatin'... I LOVE it!",
            "Fancy fireworks won't save ye!",
        ],
        .dogbeardHit: [
            "BOOM! Right in the rubber ducky!",
            "Har har! Direct hit!",
            "I could do this all bath time!",
            "That be how a TRUE pirate fires!",
        ],
        .dogbeardMiss: [
            "Blast! The suds be in me eyes!",
            "A warning shot! Aye... a warning shot.",
            "Hmph. The waves moved yer boat!",
        ],
        .dogbeardSunkShip: [
            "Down to Davy Jones' drain with ye!",
            "Har har HAR! Glub glub, little boat!",
            "One less toy in me tub!",
        ],
    ]

    /// A random line for the event, or nil to stay quiet — sinks always get
    /// a reaction, everything else only sometimes so he doesn't get annoying.
    static func line(for event: Event, using rng: inout some RandomNumberGenerator) -> String? {
        let chance: Double = switch event {
        case .matchStart, .playerSunkShip, .dogbeardSunkShip: 1.0
        case .playerSpecial: 0.8
        case .playerHit, .dogbeardHit: 0.45
        case .playerMiss, .dogbeardMiss: 0.3
        }
        guard Double.random(in: 0..<1, using: &rng) < chance else { return nil }
        return lines[event]?.randomElement(using: &rng)
    }
}
