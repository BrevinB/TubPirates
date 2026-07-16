import Testing
@testable import BathtubEngine

@Suite("Shot patterns")
struct ShotPatternTests {
    func cells(_ shot: ShotType, at target: Coordinate, orientation: Orientation? = nil) -> Set<Coordinate> {
        Set(shot.spec.pattern(target, orientation))
    }

    @Test func cannonIsSingleCell() {
        #expect(cells(.cannon, at: Coordinate(row: 5, col: 5)) == [Coordinate(row: 5, col: 5)])
    }

    @Test func parrotScoutIsThreeByThree() {
        let result = cells(.parrotScout, at: Coordinate(row: 5, col: 5))
        #expect(result.count == 9)
        #expect(result.contains(Coordinate(row: 4, col: 4)))
        #expect(result.contains(Coordinate(row: 6, col: 6)))
    }

    @Test func parrotScoutClampsAtCorner() {
        // 3x3 centered on (0,0) keeps only the 2x2 in-bounds quadrant.
        #expect(cells(.parrotScout, at: Coordinate(row: 0, col: 0)).count == 4)
    }

    @Test func bigShotIsTwoByTwo() {
        let result = cells(.bigShot, at: Coordinate(row: 3, col: 7))
        #expect(result == [
            Coordinate(row: 3, col: 7), Coordinate(row: 3, col: 8),
            Coordinate(row: 4, col: 7), Coordinate(row: 4, col: 8),
        ])
    }

    @Test func bigShotClampsAtCorner() {
        #expect(cells(.bigShot, at: Coordinate(row: 9, col: 9)) == [Coordinate(row: 9, col: 9)])
    }

    @Test func fireworksIsXPattern() {
        let result = cells(.fireworks, at: Coordinate(row: 5, col: 5))
        #expect(result == [
            Coordinate(row: 5, col: 5),
            Coordinate(row: 4, col: 4), Coordinate(row: 4, col: 6),
            Coordinate(row: 6, col: 4), Coordinate(row: 6, col: 6),
        ])
    }

    @Test func fireworksClampsAtCorner() {
        // At (0,0) only the center and the (1,1) diagonal survive.
        #expect(cells(.fireworks, at: Coordinate(row: 0, col: 0)) == [
            Coordinate(row: 0, col: 0), Coordinate(row: 1, col: 1),
        ])
    }

    @Test func chainShotFollowsOrientation() {
        #expect(cells(.chainShot, at: Coordinate(row: 2, col: 2), orientation: .horizontal) == [
            Coordinate(row: 2, col: 2), Coordinate(row: 2, col: 3), Coordinate(row: 2, col: 4),
        ])
        #expect(cells(.chainShot, at: Coordinate(row: 2, col: 2), orientation: .vertical) == [
            Coordinate(row: 2, col: 2), Coordinate(row: 3, col: 2), Coordinate(row: 4, col: 2),
        ])
    }

    @Test func chainShotClampsAtEdge() {
        #expect(cells(.chainShot, at: Coordinate(row: 0, col: 8), orientation: .horizontal) == [
            Coordinate(row: 0, col: 8), Coordinate(row: 0, col: 9),
        ])
    }

    @Test func flareHasNoPattern() {
        #expect(cells(.flare, at: Coordinate(row: 5, col: 5)).isEmpty)
        #expect(!ShotType.flare.spec.needsTarget)
    }

    @Test func specCatalogIsCoherent() {
        for shot in ShotType.allCases {
            let spec = shot.spec
            if shot == .cannon {
                #expect(spec.usesPerMatch == nil)
                #expect(spec.coinCost == 0)
            } else {
                #expect(spec.usesPerMatch == 1)
                #expect(spec.coinCost > 0)
            }
        }
        #expect(ShotType.purchasable.count == 5)
    }
}
