import BathtubArena
import BathtubEngine
import BathtubUI
import Foundation

// ShotType and ShipKind names moved to BathtubUI so the Messages extension
// gets the same translations; only the app-only models are left here.

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
