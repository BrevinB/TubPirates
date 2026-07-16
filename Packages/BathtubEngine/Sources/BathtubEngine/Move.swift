public enum PlayerID: String, Codable, Sendable, CaseIterable, Hashable {
    case one
    case two

    public var opponent: PlayerID {
        self == .one ? .two : .one
    }
}

/// A single turn's action. Codable so it can ride inside Game Center match data.
public struct Move: Codable, Hashable, Sendable {
    public let player: PlayerID
    public let shot: ShotType
    /// Required unless the shot spec says otherwise (flare is untargeted).
    public let target: Coordinate?
    /// Required only for directional shots (chain shot).
    public let orientation: Orientation?

    public init(player: PlayerID, shot: ShotType, target: Coordinate? = nil, orientation: Orientation? = nil) {
        self.player = player
        self.shot = shot
        self.target = target
        self.orientation = orientation
    }
}

public enum CellOutcome: String, Codable, Sendable, Equatable {
    case miss
    case hit
    case revealedShip
    case revealedWater
}

public struct CellResult: Codable, Hashable, Sendable {
    public let coordinate: Coordinate
    public let outcome: CellOutcome

    public init(coordinate: Coordinate, outcome: CellOutcome) {
        self.coordinate = coordinate
        self.outcome = outcome
    }
}

/// Everything that happened when a move was applied — the scene animates straight off this.
public struct MoveResolution: Codable, Sendable {
    public let move: Move
    /// Results for cells newly affected this turn (already-shot cells are skipped).
    public let cellResults: [CellResult]
    /// Ships fully sunk by this move.
    public let sunkShips: [Ship]
    /// The ship exposed by a flare, if this was a flare move.
    public let revealedShip: Ship?
    public let winner: PlayerID?
}

public enum MoveError: Error, Codable, Sendable, Equatable {
    case notYourTurn
    case gameOver
    case outOfBounds
    case shotNotAvailable
    case targetRequired
    case orientationRequired
    case allCellsAlreadyTried
}
