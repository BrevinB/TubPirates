/// SplitMix64 — a tiny, seedable, Codable RNG so AI behavior can persist in saves
/// and replay deterministically in tests.
public struct SeededRNG: RandomNumberGenerator, Codable, Sendable, Equatable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Dogbeard's brain: parity hunting, line-following targeting, intel exploitation,
/// and the occasional special shot for flavor.
public struct BattleAI: Codable, Sendable {
    private var rng: SeededRNG
    /// Chance per hunt-mode turn to spend an available special shot.
    public var specialUseChance: Double

    public init(seed: UInt64? = nil, specialUseChance: Double = 0.2) {
        self.rng = SeededRNG(seed: seed ?? UInt64.random(in: UInt64.min...UInt64.max))
        self.specialUseChance = specialUseChance
    }

    public mutating func chooseMove(
        as player: PlayerID,
        observing enemy: AttackerView,
        remainingUses: [ShotType: Int]
    ) -> Move {
        let untried = Coordinate.allBoardCells.filter { !enemy.isTried($0) }

        // 1. Revealed ship cells we haven't shot yet are free hits.
        if let intel = pick(enemy.revealedShipCells.filter { !enemy.isTried($0) }.sorted()) {
            return Move(player: player, shot: .cannon, target: intel)
        }

        // 2. Target mode: finish off partially hit ships.
        if let target = targetModeCell(enemy: enemy) {
            return Move(player: player, shot: .cannon, target: target)
        }

        // 3. Hunt mode: sometimes fire a special for flavor.
        let specials = remainingUses.filter { $0.value > 0 }.keys.sorted { $0.rawValue < $1.rawValue }
        if !specials.isEmpty, Double.random(in: 0..<1, using: &rng) < specialUseChance,
           let special = pick(specials),
           let move = specialMove(special, player: player, untried: untried, enemy: enemy) {
            return move
        }

        // 4. Hunt mode cannon: parity cells first, skipping known water.
        let unknownUntried = untried.filter { !enemy.revealedWaterCells.contains($0) }
        let parity = unknownUntried.filter { ($0.row + $0.col) % 2 == 0 }
        let candidates = !parity.isEmpty ? parity : (!unknownUntried.isEmpty ? unknownUntried : untried)
        let target = pick(candidates) ?? Coordinate(row: 0, col: 0)
        return Move(player: player, shot: .cannon, target: target)
    }

    // MARK: - Target mode

    private mutating func targetModeCell(enemy: AttackerView) -> Coordinate? {
        let hits = enemy.unexplainedHits.sorted()
        guard !hits.isEmpty else { return nil }

        let isGoodCandidate: (Coordinate) -> Bool = {
            $0.isValid && !enemy.isTried($0) && !enemy.revealedWaterCells.contains($0)
        }

        // Extend lines: for each pair of adjacent collinear hits, walk out past both ends.
        var lineCandidates: [Coordinate] = []
        for hit in hits {
            for (dr, dc) in [(0, 1), (1, 0)] {
                let next = hit.offset(dr, dc)
                guard enemy.unexplainedHits.contains(next) else { continue }
                // Found a run — walk to both ends.
                var back = hit
                while enemy.unexplainedHits.contains(back.offset(-dr, -dc)) { back = back.offset(-dr, -dc) }
                var front = next
                while enemy.unexplainedHits.contains(front.offset(dr, dc)) { front = front.offset(dr, dc) }
                let beyondBack = back.offset(-dr, -dc)
                let beyondFront = front.offset(dr, dc)
                if isGoodCandidate(beyondBack) { lineCandidates.append(beyondBack) }
                if isGoodCandidate(beyondFront) { lineCandidates.append(beyondFront) }
            }
        }
        if let cell = pick(lineCandidates.sorted()) { return cell }

        // Single hit (or blocked line): probe orthogonal neighbors.
        let neighborCandidates = hits.flatMap(\.orthogonalNeighbors).filter(isGoodCandidate)
        return pick(Array(Set(neighborCandidates)).sorted())
    }

    // MARK: - Specials

    private mutating func specialMove(
        _ shot: ShotType,
        player: PlayerID,
        untried: [Coordinate],
        enemy: AttackerView
    ) -> Move? {
        switch shot {
        case .flare:
            return Move(player: player, shot: .flare)
        case .parrotScout:
            // Aim the 3x3 at an inner cell with no intel yet.
            let centers = untried.filter {
                (1...8).contains($0.row) && (1...8).contains($0.col)
                    && !enemy.revealedWaterCells.contains($0) && !enemy.revealedShipCells.contains($0)
            }
            guard let center = pick(centers) else { return nil }
            return Move(player: player, shot: .parrotScout, target: center)
        case .bigShot, .fireworks:
            guard let target = pick(untried.filter { !enemy.revealedWaterCells.contains($0) }) else { return nil }
            return Move(player: player, shot: shot, target: target)
        case .chainShot:
            guard let target = pick(untried.filter { !enemy.revealedWaterCells.contains($0) }) else { return nil }
            let orientation = Bool.random(using: &rng) ? Orientation.horizontal : .vertical
            return Move(player: player, shot: .chainShot, target: target, orientation: orientation)
        case .cannon:
            return nil
        }
    }

    private mutating func pick<T>(_ array: [T]) -> T? {
        array.randomElement(using: &rng)
    }
}
