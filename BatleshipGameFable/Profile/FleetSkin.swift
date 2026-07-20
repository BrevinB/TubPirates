import BathtubEngine

/// A cosmetic fleet set: five alternate ship sprites bought as a bundle.
/// Purely visual — footprints and rules are identical, so online stays fair.
struct FleetSkin: Identifiable, Equatable {
    let id: String
    let name: String
    let blurb: String
    let price: Int
    /// Asset-name infix ("duck" → ship_duck_5); nil uses the classic ship_N set.
    private let assetInfix: String?

    func textureName(for kind: ShipKind) -> String {
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
    var previewTextures: [String] {
        [ShipKind.galleon, .frigate, .duckSub, .tugboat, .dinghy].map(textureName(for:))
    }

    static let classic = FleetSkin(
        id: "classic",
        name: "Classic Toy Fleet",
        blurb: "The trusty originals. Every captain's first flotilla.",
        price: 0,
        assetInfix: nil
    )

    static let ducky = FleetSkin(
        id: "ducky",
        name: "Ducky Squadron",
        blurb: "An armada of rubber ducks, from walnut-shell duckling to armored flagship.",
        price: 1200,
        assetInfix: "duck"
    )

    static let seaMonster = FleetSkin(
        id: "seaMonster",
        name: "Sea Monster Crew",
        blurb: "Crab, seahorse, turtle, narwhal, kraken — the deep end's finest.",
        price: 2000,
        assetInfix: "sea"
    )

    static let all: [FleetSkin] = [.classic, .ducky, .seaMonster]

    static func withID(_ id: String) -> FleetSkin {
        all.first { $0.id == id } ?? .classic
    }
}
