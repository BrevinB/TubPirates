/// A cell position on the 10x10 board. Row 0 is the top, column 0 is the left.
public struct Coordinate: Hashable, Codable, Sendable, Comparable {
    public var row: Int
    public var col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    public func offset(_ dr: Int, _ dc: Int) -> Coordinate {
        Coordinate(row: row + dr, col: col + dc)
    }

    public var isValid: Bool {
        (0..<Board.size).contains(row) && (0..<Board.size).contains(col)
    }

    public var orthogonalNeighbors: [Coordinate] {
        [offset(-1, 0), offset(1, 0), offset(0, -1), offset(0, 1)].filter(\.isValid)
    }

    /// Canonical ordering (row-major) so set-derived collections can be sorted deterministically.
    public static func < (lhs: Coordinate, rhs: Coordinate) -> Bool {
        (lhs.row, lhs.col) < (rhs.row, rhs.col)
    }

    public static var allBoardCells: [Coordinate] {
        (0..<Board.size).flatMap { row in
            (0..<Board.size).map { Coordinate(row: row, col: $0) }
        }
    }
}

public enum Orientation: String, Codable, Sendable, CaseIterable {
    case horizontal
    case vertical

    public var toggled: Orientation {
        self == .horizontal ? .vertical : .horizontal
    }
}
