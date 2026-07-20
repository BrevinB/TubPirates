import Foundation
import Testing
@testable import BathtubEngine

/// Known layout used across resolution tests:
/// - Player two's board: galleon at row 0 cols 0-4, dinghy at row 9 cols 8-9.
/// - Player one's board: dinghy at row 5 cols 0-1 (just enough to be a valid game).
private func makeState(loadouts: [PlayerID: Set<ShotType>] = [:]) -> GameState {
    var boardOne = Board()
    try! boardOne.place(.dinghy, at: Coordinate(row: 5, col: 0), orientation: .horizontal)

    var boardTwo = Board()
    try! boardTwo.place(.galleon, at: Coordinate(row: 0, col: 0), orientation: .horizontal)
    try! boardTwo.place(.dinghy, at: Coordinate(row: 9, col: 8), orientation: .horizontal)

    return GameState(boards: [.one: boardOne, .two: boardTwo], loadouts: loadouts)
}

@Suite("Turn resolution")
struct TurnResolutionTests {
    @Test func cannonHitAndMiss() throws {
        var state = makeState()
        let hit = try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 0, col: 0)))
        #expect(hit.cellResults == [CellResult(coordinate: Coordinate(row: 0, col: 0), outcome: .hit)])
        #expect(hit.sunkShips.isEmpty)
        #expect(hit.winner == nil)
        #expect(state.currentPlayer == .two)

        let miss = try state.apply(Move(player: .two, shot: .cannon, target: Coordinate(row: 9, col: 9)))
        #expect(miss.cellResults.first?.outcome == .miss)
        #expect(state.currentPlayer == .one)
    }

    @Test func turnAlternatesEvenAfterHit() throws {
        var state = makeState()
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 0, col: 0)))
        #expect(state.currentPlayer == .two)
        #expect(state.validate(Move(player: .one, shot: .cannon, target: Coordinate(row: 0, col: 1))) == .notYourTurn)
    }

    @Test func sinkingReportsShip() throws {
        var state = makeState()
        // Sink two's dinghy (2 cells) while two shoots water.
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 9, col: 8)))
        try state.apply(Move(player: .two, shot: .cannon, target: Coordinate(row: 0, col: 9)))
        let sink = try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 9, col: 9)))
        #expect(sink.sunkShips.count == 1)
        #expect(sink.sunkShips.first?.kind == .dinghy)
        #expect(sink.winner == nil) // galleon still afloat
    }

    @Test func winDetection() throws {
        var state = makeState()
        // Player two sinks player one's only ship (dinghy at (5,0)-(5,1)).
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 8, col: 8)))
        try state.apply(Move(player: .two, shot: .cannon, target: Coordinate(row: 5, col: 0)))
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 8, col: 9)))
        let final = try state.apply(Move(player: .two, shot: .cannon, target: Coordinate(row: 5, col: 1)))
        #expect(final.winner == .two)
        #expect(state.phase == .finished(winner: .two))
        #expect(state.validate(Move(player: .one, shot: .cannon, target: Coordinate(row: 0, col: 0))) == .gameOver)
    }

    @Test func repeatCannonShotRejected() throws {
        var state = makeState()
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 4, col: 4)))
        try state.apply(Move(player: .two, shot: .cannon, target: Coordinate(row: 4, col: 4)))
        #expect(state.validate(Move(player: .one, shot: .cannon, target: Coordinate(row: 4, col: 4))) == .allCellsAlreadyTried)
    }

    @Test func areaShotAllowedWithPartialOverlap() throws {
        var state = makeState(loadouts: [.one: [.bigShot], .two: []])
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 4, col: 4)))
        try state.apply(Move(player: .two, shot: .cannon, target: Coordinate(row: 9, col: 0)))
        // 2x2 at (4,4) overlaps the earlier shot but has 3 new cells.
        let res = try state.apply(Move(player: .one, shot: .bigShot, target: Coordinate(row: 4, col: 4)))
        #expect(res.cellResults.count == 3)
        #expect(!res.cellResults.contains { $0.coordinate == Coordinate(row: 4, col: 4) })
    }

    @Test func useCountsDeplete() throws {
        var state = makeState(loadouts: [.one: [.fireworks], .two: []])
        #expect(state.remainingUses(of: .fireworks, for: .one) == 1)
        try state.apply(Move(player: .one, shot: .fireworks, target: Coordinate(row: 5, col: 5)))
        #expect(state.remainingUses(of: .fireworks, for: .one) == 0)
        try state.apply(Move(player: .two, shot: .cannon, target: Coordinate(row: 9, col: 0)))
        #expect(state.validate(Move(player: .one, shot: .fireworks, target: Coordinate(row: 2, col: 2))) == .shotNotAvailable)
    }

    @Test func lockedShotUnavailable() {
        let state = makeState() // empty loadouts
        #expect(state.validate(Move(player: .one, shot: .bigShot, target: Coordinate(row: 2, col: 2))) == .shotNotAvailable)
        #expect(state.availableShots(for: .one) == [.cannon])
    }

    @Test func scoutRevealsWithoutDamage() throws {
        var state = makeState(loadouts: [.one: [.parrotScout], .two: []])
        let res = try state.apply(Move(player: .one, shot: .parrotScout, target: Coordinate(row: 1, col: 1)))
        #expect(res.cellResults.count == 9)
        // Row 0 cols 0-2 are galleon cells.
        let shipReveals = res.cellResults.filter { $0.outcome == .revealedShip }
        #expect(Set(shipReveals.map(\.coordinate)) == [
            Coordinate(row: 0, col: 0), Coordinate(row: 0, col: 1), Coordinate(row: 0, col: 2),
        ])
        // No damage was dealt.
        let two = state.boards[.two]!
        #expect(two.hitCells.isEmpty && two.shotCells.isEmpty)
        #expect(two.revealedCells.count == 9)
        // Attacker view separates ship intel from water intel.
        let view = state.attackerView(of: .two)
        #expect(view.revealedShipCells.count == 3)
        #expect(view.revealedWaterCells.count == 6)
    }

    @Test func flareRevealsExactlyOneUnsunkShip() throws {
        var state = makeState(loadouts: [.one: [.flare], .two: []])
        let res = try state.apply(Move(player: .one, shot: .flare))
        let ship = try #require(res.revealedShip)
        #expect(res.cellResults.count == ship.kind.length)
        #expect(res.cellResults.allSatisfy { $0.outcome == .revealedShip })
        // Deterministic: least-known ship, tie by origin — both ships unknown,
        // galleon origin (0,0) < dinghy origin (9,8).
        #expect(ship.kind == .galleon)
        // The fully revealed ship is exposed through the attacker view.
        let view = state.attackerView(of: .two)
        #expect(view.revealedShips.map(\.id) == [ship.id])
    }

    @Test func validationErrors() {
        let state = makeState(loadouts: [.one: [.chainShot], .two: []])
        #expect(state.validate(Move(player: .one, shot: .cannon)) == .targetRequired)
        #expect(state.validate(Move(player: .one, shot: .cannon, target: Coordinate(row: -1, col: 3))) == .outOfBounds)
        #expect(state.validate(Move(player: .one, shot: .chainShot, target: Coordinate(row: 3, col: 3))) == .orientationRequired)
    }

    @Test func gameStateRoundTripsThroughJSON() throws {
        var state = makeState(loadouts: [.one: [.flare, .bigShot], .two: [.fireworks]])
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 0, col: 0)))
        try state.apply(Move(player: .two, shot: .fireworks, target: Coordinate(row: 5, col: 1)))

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)

        #expect(decoded.currentPlayer == state.currentPlayer)
        #expect(decoded.moveLog == state.moveLog)
        #expect(decoded.boards[.one] == state.boards[.one])
        #expect(decoded.boards[.two] == state.boards[.two])
        #expect(decoded.remainingUses == state.remainingUses)
    }

    @Test func moveLogReplayReconstructsState() throws {
        // The Game Center invariant: initial boards + move log = final state.
        var state = makeState(loadouts: [.one: [.flare], .two: [.bigShot]])
        let initial = state
        try state.apply(Move(player: .one, shot: .flare))
        try state.apply(Move(player: .two, shot: .bigShot, target: Coordinate(row: 7, col: 4)))
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 0, col: 3)))

        var replayed = initial
        for move in state.moveLog {
            try replayed.apply(move)
        }
        #expect(replayed.boards[.one] == state.boards[.one])
        #expect(replayed.boards[.two] == state.boards[.two])
        #expect(replayed.currentPlayer == state.currentPlayer)
    }
}

@Suite("Mid-match shot purchases")
struct EnableShotTests {
    @Test func grantsAnUnownedSpecial() throws {
        var state = makeState()
        #expect(state.remainingUses(of: .bigShot, for: .one) == 0)
        let granted = state.enableShot(.bigShot, for: .one)
        #expect(granted)
        #expect(state.remainingUses(of: .bigShot, for: .one) == 1)
        // And it actually fires.
        _ = try state.apply(Move(player: .one, shot: .bigShot, target: Coordinate(row: 4, col: 4)))
        #expect(state.remainingUses(of: .bigShot, for: .one) == 0)
    }

    @Test func refusesWhenAlreadyArmed() {
        var state = makeState(loadouts: [.one: [.bigShot]])
        let granted = state.enableShot(.bigShot, for: .one)
        #expect(!granted)
        #expect(state.remainingUses(of: .bigShot, for: .one) == 1)
    }

    @Test func refusesAfterFiringThisMatch() throws {
        var state = makeState(loadouts: [.one: [.bigShot]])
        _ = try state.apply(Move(player: .one, shot: .bigShot, target: Coordinate(row: 4, col: 4)))
        // The per-match cap holds: no re-buying a special already fired.
        let granted = state.enableShot(.bigShot, for: .one)
        #expect(!granted)
        #expect(state.remainingUses(of: .bigShot, for: .one) == 0)
    }

    @Test func refusesCannon() {
        var state = makeState()
        let granted = state.enableShot(.cannon, for: .one)
        #expect(!granted)
    }

    @Test func grantSurvivesCodableRoundTrip() throws {
        var state = makeState()
        state.enableShot(.flare, for: .one)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(decoded.remainingUses(of: .flare, for: .one) == 1)
    }
}
