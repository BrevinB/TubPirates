public enum GamePhase: Codable, Sendable, Equatable {
    case active
    case finished(winner: PlayerID)
}

/// The complete, serializable state of a match. `apply(_:)` is the single mutation point,
/// so replaying `moveLog` from the initial boards reconstructs any state — which is exactly
/// what Game Center turn sync needs.
public struct GameState: Codable, Sendable {
    /// Each player's own (defensive) board.
    public private(set) var boards: [PlayerID: Board]
    public private(set) var currentPlayer: PlayerID
    /// Remaining uses of limited shots, per player. The basic cannon is not tracked (unlimited).
    public private(set) var remainingUses: [PlayerID: [ShotType: Int]]
    public private(set) var phase: GamePhase
    public private(set) var moveLog: [Move]

    public init(
        boards: [PlayerID: Board],
        loadouts: [PlayerID: Set<ShotType>],
        firstPlayer: PlayerID = .one
    ) {
        self.boards = boards
        self.currentPlayer = firstPlayer
        self.phase = .active
        self.moveLog = []
        var uses: [PlayerID: [ShotType: Int]] = [:]
        for player in PlayerID.allCases {
            var playerUses: [ShotType: Int] = [:]
            for shot in loadouts[player] ?? [] {
                if let limit = shot.spec.usesPerMatch {
                    playerUses[shot] = limit
                }
            }
            uses[player] = playerUses
        }
        self.remainingUses = uses
    }

    // MARK: - Queries

    /// Arms a special mid-match (consumable bought from the stash). Keeps the
    /// one-use-per-special-per-match cap: refuses if the shot is already
    /// armed or was already fired by this player in this match.
    /// Returns true when the use was granted.
    @discardableResult
    public mutating func enableShot(_ shot: ShotType, for player: PlayerID) -> Bool {
        guard shot != .cannon, shot.spec.usesPerMatch != nil else { return false }
        guard (remainingUses[player]?[shot] ?? 0) == 0 else { return false }
        guard !moveLog.contains(where: { $0.player == player && $0.shot == shot }) else { return false }
        remainingUses[player, default: [:]][shot] = shot.spec.usesPerMatch ?? 1
        return true
    }

    public func remainingUses(of shot: ShotType, for player: PlayerID) -> Int? {
        if shot.spec.usesPerMatch == nil { return nil } // unlimited
        return remainingUses[player]?[shot] ?? 0
    }

    /// Shots the player can fire right now (cannon plus specials with uses left).
    public func availableShots(for player: PlayerID) -> [ShotType] {
        ShotType.allCases.filter { shot in
            shot.spec.usesPerMatch == nil || (remainingUses[player]?[shot] ?? 0) > 0
        }
    }

    /// What `attacker`'s opponent's board looks like from the attacker's side of the tub.
    public func attackerView(of defender: PlayerID) -> AttackerView {
        let board = boards[defender] ?? Board()
        var results: [Coordinate: CellOutcome] = [:]
        for cell in board.shotCells {
            results[cell] = board.hitCells.contains(cell) ? .hit : .miss
        }
        let shipCells = Set(board.ships.flatMap(\.cells))
        return AttackerView(
            shotResults: results,
            revealedShipCells: board.revealedCells.intersection(shipCells),
            revealedWaterCells: board.revealedCells.subtracting(shipCells),
            sunkShips: board.sunkShips,
            revealedShips: board.ships.filter { ship in
                !board.isSunk(ship) && ship.cells.allSatisfy(board.revealedCells.contains)
            }
        )
    }

    // MARK: - Validation

    public func validate(_ move: Move) -> MoveError? {
        guard phase == .active else { return .gameOver }
        guard move.player == currentPlayer else { return .notYourTurn }

        let spec = move.shot.spec
        if spec.usesPerMatch != nil, (remainingUses[move.player]?[move.shot] ?? 0) <= 0 {
            return .shotNotAvailable
        }
        if spec.needsTarget {
            guard let target = move.target else { return .targetRequired }
            guard target.isValid else { return .outOfBounds }
        }
        if spec.needsOrientation, move.orientation == nil {
            return .orientationRequired
        }
        if spec.effect == .damage {
            let defender = boards[move.player.opponent] ?? Board()
            let pattern = spec.pattern(move.target ?? Coordinate(row: 0, col: 0), move.orientation)
            let newCells = pattern.filter { !defender.shotCells.contains($0) }
            if newCells.isEmpty { return .allCellsAlreadyTried }
        }
        return nil
    }

    // MARK: - Resolution

    @discardableResult
    public mutating func apply(_ move: Move) throws(MoveError) -> MoveResolution {
        if let error = validate(move) { throw error }

        let defenderID = move.player.opponent
        var defender = boards[defenderID] ?? Board()
        let spec = move.shot.spec
        let previouslySunk = Set(defender.sunkShips.map(\.id))

        var cellResults: [CellResult] = []
        var revealedShip: Ship?

        switch spec.effect {
        case .damage:
            let pattern = spec.pattern(move.target!, move.orientation)
            for cell in pattern where !defender.shotCells.contains(cell) {
                let outcome = defender.markShot(cell)
                cellResults.append(CellResult(coordinate: cell, outcome: outcome))
            }
        case .revealArea:
            let pattern = spec.pattern(move.target!, move.orientation)
            for cell in pattern {
                let outcome = defender.reveal(cell)
                cellResults.append(CellResult(coordinate: cell, outcome: outcome))
            }
        case .revealShip:
            if let ship = Self.flareTarget(on: defender) {
                revealedShip = ship
                for cell in ship.cells {
                    let outcome = defender.reveal(cell)
                    cellResults.append(CellResult(coordinate: cell, outcome: outcome))
                }
            }
        }

        boards[defenderID] = defender

        if spec.usesPerMatch != nil {
            remainingUses[move.player]?[move.shot, default: 0] -= 1
        }

        let sunkNow = defender.sunkShips.filter { !previouslySunk.contains($0.id) }

        var winner: PlayerID?
        if defender.allShipsSunk {
            winner = move.player
            phase = .finished(winner: move.player)
        } else {
            // One shot per turn regardless of hits, matching the original game.
            currentPlayer = currentPlayer.opponent
        }

        moveLog.append(move)

        return MoveResolution(
            move: move,
            cellResults: cellResults,
            sunkShips: sunkNow,
            revealedShip: revealedShip,
            winner: winner
        )
    }

    /// Deterministic flare selection so replaying a move log yields identical state on
    /// every device: the un-sunk ship with the least intel against it, ties broken by origin.
    private static func flareTarget(on board: Board) -> Ship? {
        let known = board.revealedCells.union(board.hitCells)
        return board.ships
            .filter { !board.isSunk($0) }
            .min { a, b in
                let aKnown = a.cells.filter(known.contains).count
                let bKnown = b.cells.filter(known.contains).count
                if aKnown != bKnown { return aKnown < bKnown }
                return a.origin < b.origin
            }
    }
}
