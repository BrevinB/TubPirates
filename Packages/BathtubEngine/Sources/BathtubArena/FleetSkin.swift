// The arena is a UIKit/SpriteKit surface; the package also builds for macOS
// so the engine's tests can run there, where this target has nothing to offer.
#if canImport(UIKit)
import BathtubEngine
/// A cosmetic fleet set: five alternate ship sprites bought as a bundle.
/// Purely visual — footprints and rules are identical, so online stays fair.
public struct FleetSkin: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let blurb: String
    public let price: Int
    /// Trophy fleets: how to earn it. Set = can never be bought.
    public var earnedBy: String? = nil
    /// Asset-name infix ("duck" → ship_duck_5); nil uses the classic ship_N set.
    private let assetInfix: String?

    public func textureName(for kind: ShipKind) -> String {
        let size: String
        switch kind {
        case .galleon: size = "5"
        case .frigate: size = "4"
        case .tugboat: size = "3a"
        case .duckSub: size = "3b"
        case .dinghy: size = "2"
        }
        if let assetInfix {
            return "ship_\(assetInfix)_\(size)"
        }
        return "ship_\(size)"
    }

    /// Preview sprites, largest first (for shop cards).
    public var previewTextures: [String] {
        [ShipKind.galleon, .frigate, .duckSub, .tugboat, .dinghy].map(textureName(for:))
    }

    public static let classic = FleetSkin(
        id: "classic",
        name: "Classic Toy Fleet",
        blurb: "The trusty originals. Every captain's first flotilla.",
        price: 0,
        assetInfix: nil
    )

    public static let ducky = FleetSkin(
        id: "ducky",
        name: "Ducky Squadron",
        blurb: "An armada of rubber ducks, from walnut-shell duckling to armored flagship.",
        price: 1500,
        assetInfix: "duck"
    )

    public static let seaMonster = FleetSkin(
        id: "seaMonster",
        name: "Sea Monster Crew",
        blurb: "Crab, seahorse, turtle, narwhal, kraken — the deep end's finest.",
        price: 2500,
        assetInfix: "sea"
    )

    public static let gilded = FleetSkin(
        id: "gilded",
        name: "The Gilded Armada",
        blurb: "Five toys of solid gold, forged for the ruler of the tub. Cannot be bought.",
        price: 0,
        earnedBy: "Become Tub Champion",
        assetInfix: "gild"
    )

    public static let all: [FleetSkin] = [.classic, .ducky, .seaMonster, .gilded]

    public static func withID(_ id: String) -> FleetSkin {
        all.first { $0.id == id } ?? .classic
    }
}
#endif
