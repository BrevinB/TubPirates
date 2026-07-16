import Testing
@testable import BathtubEngine

@Suite("Battle AI")
struct BattleAITests {
    /// Runs a full seeded AI-vs-AI match and returns the move count and winner.
    @discardableResult
    func playFullGame(seed: UInt64, specials: Bool = false) throws -> (moves: Int, winner: PlayerID) {
        var rng = SeededRNG(seed: seed)
        let loadout: Set<ShotType> = specials ? [.parrotScout, .bigShot, .flare, .chainShot, .fireworks] : []
        var state = GameState(
            boards: [
                .one: Board.randomlyPlaced(using: &rng),
                .two: Board.randomlyPlaced(using: &rng),
            ],
            loadouts: [.one: loadout, .two: loadout]
        )
        var ais: [PlayerID: BattleAI] = [
            .one: BattleAI(seed: seed &+ 1),
            .two: BattleAI(seed: seed &+ 2),
        ]

        var moves = 0
        while state.phase == .active {
            let player = state.currentPlayer
            let move = ais[player]!.chooseMove(
                as: player,
                observing: state.attackerView(of: player.opponent),
                remainingUses: state.remainingUses[player] ?? [:]
            )
            try state.apply(move) // throwing = AI produced an illegal move = test failure
            moves += 1
            #expect(moves < 250, "game should terminate")
            if moves >= 250 { break }
        }
        guard case .finished(let winner) = state.phase else {
            throw TestFailure.gameDidNotFinish
        }
        return (moves, winner)
    }

    enum TestFailure: Error { case gameDidNotFinish }

    @Test("AI vs AI always finishes, cannon only", arguments: UInt64(1)...20)
    func aiFinishesCannonOnly(seed: UInt64) throws {
        let result = try playFullGame(seed: seed)
        #expect(result.moves < 200)
    }

    @Test("AI vs AI always finishes with specials", arguments: UInt64(100)...120)
    func aiFinishesWithSpecials(seed: UInt64) throws {
        let result = try playFullGame(seed: seed, specials: true)
        #expect(result.moves < 200)
    }

    @Test func aiIsDeterministicUnderSeed() {
        var rng = SeededRNG(seed: 7)
        let enemyBoard = Board.randomlyPlaced(using: &rng)

        func moveSequence() -> [Move] {
            var ai = BattleAI(seed: 42)
            var localState = GameState(
                boards: [.one: enemyBoard, .two: enemyBoard],
                loadouts: [:]
            )
            var moves: [Move] = []
            for _ in 0..<30 where localState.phase == .active {
                let player = localState.currentPlayer
                let move = ai.chooseMove(
                    as: player,
                    observing: localState.attackerView(of: player.opponent),
                    remainingUses: localState.remainingUses[player] ?? [:]
                )
                try! localState.apply(move)
                moves.append(move)
            }
            return moves
        }

        #expect(moveSequence() == moveSequence())
    }

    @Test func aiNeverRepeatsACannonTarget() throws {
        var rng = SeededRNG(seed: 99)
        var state = GameState(
            boards: [.one: Board.randomlyPlaced(using: &rng), .two: Board.randomlyPlaced(using: &rng)],
            loadouts: [:]
        )
        var ais: [PlayerID: BattleAI] = [.one: BattleAI(seed: 5), .two: BattleAI(seed: 6)]
        var targets: [PlayerID: Set<Coordinate>] = [.one: [], .two: []]

        var moves = 0
        while state.phase == .active && moves < 250 {
            let player = state.currentPlayer
            let move = ais[player]!.chooseMove(
                as: player,
                observing: state.attackerView(of: player.opponent),
                remainingUses: [:]
            )
            let target = try #require(move.target)
            #expect(!targets[player]!.contains(target), "AI repeated target \(target)")
            targets[player]!.insert(target)
            try state.apply(move)
            moves += 1
        }
    }

    @Test func aiExploitsRevealedShipCells() throws {
        // Give the AI intel: reveal part of the enemy galleon, expect it to shoot there.
        var enemyBoard = Board()
        try enemyBoard.place(.galleon, at: Coordinate(row: 4, col: 2), orientation: .horizontal)
        var state = GameState(
            boards: [.one: enemyBoard, .two: enemyBoard],
            loadouts: [.one: [.parrotScout], .two: []]
        )
        try state.apply(Move(player: .one, shot: .parrotScout, target: Coordinate(row: 4, col: 3)))

        var ai = BattleAI(seed: 1)
        let view = state.attackerView(of: .two) // player one scouted player two's board
        let move = ai.chooseMove(as: .one, observing: view, remainingUses: [:])
        let target = try #require(move.target)
        #expect(view.revealedShipCells.contains(target))
        #expect(move.shot == .cannon)
    }

    @Test func aiFollowsUpOnHits() throws {
        var enemyBoard = Board()
        try enemyBoard.place(.galleon, at: Coordinate(row: 5, col: 2), orientation: .horizontal)
        var state = GameState(boards: [.one: Board(), .two: enemyBoard], loadouts: [:])
        try! state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 5, col: 4)))

        var ai = BattleAI(seed: 3)
        let view = state.attackerView(of: .two)
        let move = ai.chooseMove(as: .one, observing: view, remainingUses: [:])
        let target = try #require(move.target)
        #expect(Coordinate(row: 5, col: 4).orthogonalNeighbors.contains(target),
                "after a lone hit the AI should probe a neighbor, got \(target)")
    }

    @Test func aiExtendsHitLines() throws {
        var enemyBoard = Board()
        try enemyBoard.place(.galleon, at: Coordinate(row: 5, col: 2), orientation: .horizontal)
        var state = GameState(boards: [.one: enemyBoard, .two: enemyBoard], loadouts: [:])
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 5, col: 3)))
        try state.apply(Move(player: .two, shot: .cannon, target: Coordinate(row: 0, col: 0)))
        try state.apply(Move(player: .one, shot: .cannon, target: Coordinate(row: 5, col: 4)))

        var ai = BattleAI(seed: 11)
        let view = state.attackerView(of: .two)
        let move = ai.chooseMove(as: .one, observing: view, remainingUses: [:])
        let target = try #require(move.target)
        #expect(target == Coordinate(row: 5, col: 2) || target == Coordinate(row: 5, col: 5),
                "with two collinear hits the AI should extend the line, got \(target)")
    }
}
