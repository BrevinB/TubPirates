import Testing
@testable import BathtubEngine

@Suite("Ship placement")
struct PlacementTests {
    @Test func shipCellsFollowOrientation() {
        let h = Ship(kind: .frigate, origin: Coordinate(row: 2, col: 3), orientation: .horizontal)
        #expect(h.cells == [
            Coordinate(row: 2, col: 3), Coordinate(row: 2, col: 4),
            Coordinate(row: 2, col: 5), Coordinate(row: 2, col: 6),
        ])
        let v = Ship(kind: .dinghy, origin: Coordinate(row: 8, col: 0), orientation: .vertical)
        #expect(v.cells == [Coordinate(row: 8, col: 0), Coordinate(row: 9, col: 0)])
    }

    @Test func placementRejectsOutOfBounds() {
        let board = Board()
        #expect(!board.canPlace(.galleon, at: Coordinate(row: 0, col: 6), orientation: .horizontal))
        #expect(!board.canPlace(.galleon, at: Coordinate(row: 6, col: 0), orientation: .vertical))
        #expect(board.canPlace(.galleon, at: Coordinate(row: 0, col: 5), orientation: .horizontal))
        #expect(board.canPlace(.galleon, at: Coordinate(row: 5, col: 0), orientation: .vertical))
    }

    @Test func placementRejectsOverlap() throws {
        var board = Board()
        try board.place(.frigate, at: Coordinate(row: 4, col: 2), orientation: .horizontal)
        // Crosses the frigate at (4,4).
        #expect(!board.canPlace(.tugboat, at: Coordinate(row: 3, col: 4), orientation: .vertical))
        // Adjacency is allowed.
        #expect(board.canPlace(.tugboat, at: Coordinate(row: 5, col: 2), orientation: .horizontal))
    }

    @Test func placeThrowsOnInvalid() {
        var board = Board()
        #expect(throws: Board.PlacementError.invalidPlacement) {
            try board.place(.dinghy, at: Coordinate(row: 9, col: 9), orientation: .horizontal)
        }
    }

    @Test("Random placement always yields a full valid fleet", arguments: [0])
    func randomPlacementAlwaysSucceeds(_ base: UInt64) {
        for seed in UInt64(1)...1000 {
            var rng = SeededRNG(seed: base &+ seed)
            let board = Board.randomlyPlaced(using: &rng)
            #expect(board.ships.count == 5)
            let allCells = board.ships.flatMap(\.cells)
            #expect(allCells.count == 17)                 // 5+4+3+3+2
            #expect(Set(allCells).count == 17)            // no overlaps
            #expect(allCells.allSatisfy { $0.isValid })   // in bounds
        }
    }
}
