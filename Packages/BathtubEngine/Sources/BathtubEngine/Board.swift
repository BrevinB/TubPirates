/// One player's side of the tub: their fleet plus everything the enemy has done to it.
public struct Board: Codable, Sendable, Hashable {
    public static let size = 10

    public private(set) var ships: [Ship]
    /// Cells the enemy has fired damage shots at.
    public private(set) var shotCells: Set<Coordinate>
    /// Subset of `shotCells` that landed on a ship.
    public private(set) var hitCells: Set<Coordinate>
    /// Cells revealed by intel shots (scout/flare). No damage implied.
    public private(set) var revealedCells: Set<Coordinate>

    public init() {
        ships = []
        shotCells = []
        hitCells = []
        revealedCells = []
    }

    // MARK: - Queries

    public func ship(at coordinate: Coordinate) -> Ship? {
        ships.first { $0.cells.contains(coordinate) }
    }

    public func isSunk(_ ship: Ship) -> Bool {
        ship.cells.allSatisfy(hitCells.contains)
    }

    public var sunkShips: [Ship] {
        ships.filter(isSunk)
    }

    public var allShipsSunk: Bool {
        !ships.isEmpty && ships.allSatisfy(isSunk)
    }

    /// Count of own ship cells that have not been hit (used for coin bonuses).
    public var survivingShipCellCount: Int {
        ships.flatMap(\.cells).filter { !hitCells.contains($0) }.count
    }

    // MARK: - Placement

    public enum PlacementError: Error, Sendable, Equatable {
        case invalidPlacement
    }

    /// In-bounds and non-overlapping. Adjacent ships are allowed, matching the original game.
    public func canPlace(_ kind: ShipKind, at origin: Coordinate, orientation: Orientation) -> Bool {
        let candidate = Ship(kind: kind, origin: origin, orientation: orientation)
        let occupied = Set(ships.flatMap(\.cells))
        return candidate.cells.allSatisfy { $0.isValid && !occupied.contains($0) }
    }

    public mutating func place(_ kind: ShipKind, at origin: Coordinate, orientation: Orientation) throws(PlacementError) {
        guard canPlace(kind, at: origin, orientation: orientation) else {
            throw .invalidPlacement
        }
        ships.append(Ship(kind: kind, origin: origin, orientation: orientation))
    }

    public mutating func removeShip(id: Ship.ID) {
        ships.removeAll { $0.id == id }
    }

    /// Random valid fleet layout. Places longest ships first with a bounded retry loop;
    /// restarts from scratch in the (rare) case a layout paints itself into a corner.
    public static func randomlyPlaced(
        fleet: [ShipKind] = ShipKind.standardFleet,
        using rng: inout some RandomNumberGenerator
    ) -> Board {
        let ordered = fleet.sorted { $0.length > $1.length }
        while true {
            var board = Board()
            var failed = false
            for kind in ordered {
                var attempts = 0
                while attempts < 200 {
                    let origin = Coordinate(
                        row: Int.random(in: 0..<size, using: &rng),
                        col: Int.random(in: 0..<size, using: &rng)
                    )
                    let orientation = Orientation.allCases.randomElement(using: &rng)!
                    if board.canPlace(kind, at: origin, orientation: orientation) {
                        try! board.place(kind, at: origin, orientation: orientation)
                        break
                    }
                    attempts += 1
                }
                if attempts >= 200 { failed = true; break }
            }
            if !failed { return board }
        }
    }

    // MARK: - Resolution (module-internal; driven by GameState)

    /// Marks a damage shot at a cell that has not been shot before.
    mutating func markShot(_ coordinate: Coordinate) -> CellOutcome {
        shotCells.insert(coordinate)
        if ship(at: coordinate) != nil {
            hitCells.insert(coordinate)
            return .hit
        }
        return .miss
    }

    /// Marks an intel reveal at a cell.
    mutating func reveal(_ coordinate: Coordinate) -> CellOutcome {
        revealedCells.insert(coordinate)
        return ship(at: coordinate) != nil ? .revealedShip : .revealedWater
    }
}
