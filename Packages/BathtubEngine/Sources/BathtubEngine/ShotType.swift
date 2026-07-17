/// Every cannon in the armory. Adding a shot type = one case + one spec entry.
public enum ShotType: String, Codable, CaseIterable, Sendable, Identifiable {
    case cannon
    case parrotScout
    case bigShot
    case flare
    case chainShot
    case fireworks

    public var id: String { rawValue }
}

public struct ShotSpec: Sendable {
    public enum Effect: Sendable, Equatable {
        /// Fires at cells, producing hits and misses.
        case damage
        /// Reveals what occupies each cell in the pattern. No damage.
        case revealArea
        /// Reveals the full location of one enemy ship. No damage, no target.
        case revealShip
    }

    public let effect: Effect
    /// `nil` means unlimited (the basic cannon).
    public let usesPerMatch: Int?
    /// Price per single use in the Armory; 0 = not purchasable (the basic cannon).
    public let coinCost: Int
    public let needsTarget: Bool
    public let needsOrientation: Bool
    public let displayName: String
    public let blurb: String
    /// Affected cells for a target; out-of-bounds cells are clamped away.
    public let pattern: @Sendable (Coordinate, Orientation?) -> [Coordinate]
}

public extension ShotType {
    var spec: ShotSpec {
        switch self {
        case .cannon:
            ShotSpec(
                effect: .damage, usesPerMatch: nil, coinCost: 0,
                needsTarget: true, needsOrientation: false,
                displayName: "Cannon",
                blurb: "Your trusty cannon. Fires a single shot.",
                pattern: { target, _ in [target].filter(\.isValid) }
            )
        case .parrotScout:
            ShotSpec(
                effect: .revealArea, usesPerMatch: 1, coinCost: 60,
                needsTarget: true, needsOrientation: false,
                displayName: "Parrot Scout",
                blurb: "Use this shot to 'see' all of the ships in a certain area. Causes no damage.",
                pattern: { target, _ in
                    (-1...1).flatMap { dr in
                        (-1...1).map { dc in target.offset(dr, dc) }
                    }.filter(\.isValid)
                }
            )
        case .bigShot:
            ShotSpec(
                effect: .damage, usesPerMatch: 1, coinCost: 75,
                needsTarget: true, needsOrientation: false,
                displayName: "Big Shot Cannon",
                blurb: "This monster cannon targets four tiles at once.",
                pattern: { target, _ in
                    [target, target.offset(0, 1), target.offset(1, 0), target.offset(1, 1)]
                        .filter(\.isValid)
                }
            )
        case .flare:
            ShotSpec(
                effect: .revealShip, usesPerMatch: 1, coinCost: 90,
                needsTarget: false, needsOrientation: false,
                displayName: "Flare Cannon",
                blurb: "Use this special cannon shot to reveal your opponent's ship's location.",
                pattern: { _, _ in [] }
            )
        case .chainShot:
            ShotSpec(
                effect: .damage, usesPerMatch: 1, coinCost: 100,
                needsTarget: true, needsOrientation: true,
                displayName: "Chain Shot",
                blurb: "Linked cannonballs rake three tiles in a row.",
                pattern: { target, orientation in
                    let dir = orientation ?? .horizontal
                    return (0..<3).map { i in
                        switch dir {
                        case .horizontal: target.offset(0, i)
                        case .vertical: target.offset(i, 0)
                        }
                    }.filter(\.isValid)
                }
            )
        case .fireworks:
            ShotSpec(
                effect: .damage, usesPerMatch: 1, coinCost: 125,
                needsTarget: true, needsOrientation: false,
                displayName: "Fireworks Cannon",
                blurb: "This cannon will shoot 5 shots in an X pattern.",
                pattern: { target, _ in
                    [target,
                     target.offset(-1, -1), target.offset(-1, 1),
                     target.offset(1, -1), target.offset(1, 1)]
                        .filter(\.isValid)
                }
            )
        }
    }

    /// Shot types purchasable as consumable uses in the Armory, cheapest first.
    static var purchasable: [ShotType] {
        allCases.filter { $0.spec.coinCost > 0 }.sorted { $0.spec.coinCost < $1.spec.coinCost }
    }
}
