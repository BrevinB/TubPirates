/// Everything a shooter legitimately knows about the enemy board.
/// The AI and the enemy-board UI both read this — never the enemy `Board` directly —
/// so hidden ship positions can't leak.
public struct AttackerView: Codable, Sendable {
    /// Outcome of every damage shot fired so far.
    public let shotResults: [Coordinate: CellOutcome]
    /// Intel-revealed cells that contain a ship.
    public let revealedShipCells: Set<Coordinate>
    /// Intel-revealed cells known to be empty water.
    public let revealedWaterCells: Set<Coordinate>
    /// Fully sunk enemy ships (their kind and position are public once sunk).
    public let sunkShips: [Ship]

    public init(
        shotResults: [Coordinate: CellOutcome],
        revealedShipCells: Set<Coordinate>,
        revealedWaterCells: Set<Coordinate>,
        sunkShips: [Ship]
    ) {
        self.shotResults = shotResults
        self.revealedShipCells = revealedShipCells
        self.revealedWaterCells = revealedWaterCells
        self.sunkShips = sunkShips
    }

    public func isTried(_ coordinate: Coordinate) -> Bool {
        shotResults[coordinate] != nil
    }

    /// Hit cells not yet accounted for by a sunk ship — the AI's target-mode fuel.
    public var unexplainedHits: Set<Coordinate> {
        let hits = Set(shotResults.filter { $0.value == .hit }.keys)
        let sunkCells = Set(sunkShips.flatMap(\.cells))
        return hits.subtracting(sunkCells)
    }
}
