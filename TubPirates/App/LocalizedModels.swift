import Foundation
import BathtubEngine

extension ShotType {
    var localizedDisplayName: String {
        switch self {
        case .cannon: String(localized: "Cannon")
        case .parrotScout: String(localized: "Parrot Scout")
        case .bigShot: String(localized: "Big Shot Cannon")
        case .flare: String(localized: "Flare Cannon")
        case .chainShot: String(localized: "Chain Shot")
        case .fireworks: String(localized: "Fireworks Cannon")
        }
    }

    var localizedBlurb: String {
        switch self {
        case .cannon:
            String(localized: "Your trusty cannon. Fires a single shot.")
        case .parrotScout:
            String(localized: "Use this shot to 'see' all of the ships in a certain area. Causes no damage.")
        case .bigShot:
            String(localized: "This monster cannon targets four tiles at once.")
        case .flare:
            String(localized: "Use this special cannon shot to reveal your opponent's ship's location.")
        case .chainShot:
            String(localized: "Linked cannonballs rake three tiles in a row.")
        case .fireworks:
            String(localized: "This cannon will shoot 5 shots in an X pattern.")
        }
    }
}

extension FleetSkin {
    var localizedName: String {
        switch id {
        case "ducky": String(localized: "Ducky Squadron")
        case "seaMonster": String(localized: "Sea Monster Crew")
        case "gilded": String(localized: "The Gilded Armada")
        default: String(localized: "Classic Toy Fleet")
        }
    }

    var localizedBlurb: String {
        switch id {
        case "ducky":
            String(localized: "An armada of rubber ducks, from walnut-shell duckling to armored flagship.")
        case "seaMonster":
            String(localized: "Crab, seahorse, turtle, narwhal, kraken — the deep end's finest.")
        case "gilded":
            String(localized: "Five toys of solid gold, forged for the ruler of the tub. Cannot be bought.")
        default:
            String(localized: "The trusty originals. Every captain's first flotilla.")
        }
    }

    var localizedEarnedBy: String? {
        guard earnedBy != nil else { return nil }
        switch id {
        case "gilded": return String(localized: "Become Tub Champion")
        default: return earnedBy
        }
    }
}

extension Captain {
    var localizedName: String {
        switch id {
        case "soapySal": String(localized: "Soapy Sal")
        case "barnacleBess": String(localized: "Barnacle Bess")
        case "admiralBubbles": String(localized: "Admiral Bubbles")
        default: String(localized: "Captain Pugbeard")
        }
    }

    var localizedBlurb: String {
        switch id {
        case "soapySal":
            String(localized: "Nine lives, zero mercy. She fights dirty for someone so clean.")
        case "barnacleBess":
            String(localized: "Eight arms, eight cannons, zero patience. The tub's toughest scrubber.")
        case "admiralBubbles":
            String(localized: "Decorated hero of the Great Soap Wars. The tub's final boss.")
        default:
            String(localized: "The scruffy scourge of the bathtub. All bark, some bite.")
        }
    }
}

extension ShipKind {
    var localizedDisplayName: String {
        switch self {
        case .dinghy: String(localized: "Dinghy")
        case .tugboat: String(localized: "Tugboat")
        case .duckSub: String(localized: "Duck Sub")
        case .frigate: String(localized: "Wind-Up Whale")
        case .galleon: String(localized: "Galleon")
        }
    }
}
