import BathtubEngine

/// Table-talk events a captain can react to during battle.
enum DialogEvent: Hashable {
    case matchStart
    case playerHit          // the player hit one of the captain's ships
    case playerMiss
    case playerSunkShip     // the player sank one of the captain's ships
    case playerSpecial      // the player fired a special shot
    case captainHit         // the captain hit the player
    case captainMiss
    case captainSunkShip    // the captain sank one of the player's ships
}

/// A rival on the captain ladder: portrait, personality, AI difficulty dials,
/// and the reward for beating them.
struct Captain: Identifiable, Equatable {
    let id: String
    let name: String
    let portrait: String
    /// Flavor line on the ladder card.
    let blurb: String
    /// AI difficulty dials (lower sloppiness = sharper hunting).
    let sloppiness: Double
    let specialUseChance: Double
    /// Win rewards are multiplied by this.
    let rewardMultiplier: Double
    /// Wins against this captain needed to unlock the next rung.
    let winsToAdvance: Int
    let lines: [DialogEvent: [String]]

    static func == (lhs: Captain, rhs: Captain) -> Bool { lhs.id == rhs.id }

    /// The ladder, easiest to hardest.
    static let roster: [Captain] = [.dogbeard, .soapySal, .admiralBubbles]

    static func withID(_ id: String?) -> Captain {
        roster.first { $0.id == id } ?? .dogbeard
    }

    /// The captain after this one on the ladder, if any.
    var next: Captain? {
        guard let index = Self.roster.firstIndex(of: self) else { return nil }
        return Self.roster.indices.contains(index + 1) ? Self.roster[index + 1] : nil
    }

    /// 1-based difficulty tier (ladder position).
    var tier: Int {
        (Self.roster.firstIndex(of: self) ?? 0) + 1
    }

    /// Defeated-and-teary portrait variant (shown when the player wins).
    var sadPortrait: String { portrait + "_sad" }
    /// Smug victory portrait variant (shown when the captain wins).
    var gloatPortrait: String { portrait + "_gloat" }
}

// MARK: - The roster

extension Captain {
    static let dogbeard = Captain(
        id: "dogbeard",
        name: "Dogbeard",
        portrait: "portrait_dogbeard",
        blurb: "The scruffy scourge of the bathtub. All bark, some bite.",
        sloppiness: 0.18,
        specialUseChance: 0.15,
        rewardMultiplier: 1.0,
        winsToAdvance: 3,
        lines: [
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
            .captainHit: [
                "BOOM! Right in the rubber ducky!",
                "Har har! Direct hit!",
                "I could do this all bath time!",
                "That be how a TRUE pirate fires!",
            ],
            .captainMiss: [
                "Blast! The suds be in me eyes!",
                "A warning shot! Aye... a warning shot.",
                "Hmph. The waves moved yer boat!",
            ],
            .captainSunkShip: [
                "Down to Davy Jones' drain with ye!",
                "Har har HAR! Glub glub, little boat!",
                "One less toy in me tub!",
            ],
        ]
    )

    static let soapySal = Captain(
        id: "soapySal",
        name: "Soapy Sal",
        portrait: "portrait_sal",
        blurb: "Nine lives, zero mercy. She fights dirty for someone so clean.",
        sloppiness: 0.10,
        specialUseChance: 0.22,
        rewardMultiplier: 1.5,
        winsToAdvance: 3,
        lines: [
            .matchStart: [
                "Well well... fresh prey paddles into my tub~",
                "I've clawed up bigger boats than yours, kitten.",
                "Purrr... let's make this quick. I have a nap at three.",
            ],
            .playerHit: [
                "Hsss! You'll regret that scratch!",
                "My fur! MY FUR IS WET!",
                "Cute. My turn, kitten.",
            ],
            .playerMiss: [
                "Meowhahaha! Pathetic!",
                "I've seen hairballs with better aim.",
                "You're chasing the laser dot, sweetie.",
            ],
            .playerSunkShip: [
                "NO! That was my favorite scratching post!",
                "You... sank... my BOAT?! Claws out.",
                "That's one of my nine ships gone...",
            ],
            .playerSpecial: [
                "Fancy toys won't save you from my claws!",
                "Ooooh, sparkly. I want it.",
                "You brought gadgets to a cat fight?",
            ],
            .captainHit: [
                "Right on the whiskers! Purrrfect shot.",
                "Sliced through like warm tuna!",
                "That's how a cat plays with her food~",
            ],
            .captainMiss: [
                "Tsk. The bubbles betrayed me.",
                "I meant to miss. Building suspense.",
                "Even my misses look graceful.",
            ],
            .captainSunkShip: [
                "Sunk! Like a catnip mouse in the water bowl.",
                "Meowhahaha! Down it goes!",
                "Another one for my trophy shelf~",
            ],
        ]
    )

    static let admiralBubbles = Captain(
        id: "admiralBubbles",
        name: "Admiral Bubbles",
        portrait: "portrait_bubbles",
        blurb: "Decorated hero of the Great Soap Wars. The tub's final boss.",
        sloppiness: 0.03,
        specialUseChance: 0.3,
        rewardMultiplier: 2.0,
        winsToAdvance: 3,
        lines: [
            .matchStart: [
                "Harrumph! State your business in MY waters, sailor!",
                "I commanded fleets before you could hold a loofah!",
                "Observe, cadet: THIS is how a professional operates.",
            ],
            .playerHit: [
                "A palpable hit. Noted in the logbook.",
                "Harrumph! Structural damage. Minor. MINOR, I say!",
                "Bold move, cadet. It shall be your last.",
            ],
            .playerMiss: [
                "Wide by a nautical mile! Harrumph!",
                "I've seen better aim from a sea cucumber.",
                "Your gunnery officer should be demoted.",
            ],
            .playerSunkShip: [
                "MY FLAGSHIP! This means WAR, cadet!",
                "She served with honor... avenge her, lads!",
                "Impossible! That vessel was decorated TWICE!",
            ],
            .playerSpecial: [
                "Exotic ordnance? How delightfully desperate.",
                "I wrote the manual on that weapon, cadet.",
                "Harrumph! Gadgetry is no substitute for discipline!",
            ],
            .captainHit: [
                "Precision! Discipline! VICTORY!",
                "By the book, cadet. Chapter 7: destruction.",
                "My mustache twitched. That means a hit.",
            ],
            .captainMiss: [
                "A ranging shot. All part of the doctrine.",
                "Harrumph! My monocle fogged at the crucial moment.",
                "Recalibrating... you cannot hide forever.",
            ],
            .captainSunkShip: [
                "Another victory for the Admiralty!",
                "Down to the drain! Salute as she goes, lads.",
                "Textbook execution. Literally — read the textbook.",
            ],
        ]
    )
}

// MARK: - Dialog selection

enum CaptainDialog {
    /// A random line for the event, or nil to stay quiet — sinks always get
    /// a reaction, everything else only sometimes so captains stay charming.
    static func line(
        for event: DialogEvent,
        from captain: Captain,
        using rng: inout some RandomNumberGenerator
    ) -> String? {
        let chance: Double = switch event {
        case .matchStart, .playerSunkShip, .captainSunkShip: 1.0
        case .playerSpecial: 0.8
        case .playerHit, .captainHit: 0.45
        case .playerMiss, .captainMiss: 0.3
        }
        guard Double.random(in: 0..<1, using: &rng) < chance else { return nil }
        return captain.lines[event]?.randomElement(using: &rng)
    }
}
