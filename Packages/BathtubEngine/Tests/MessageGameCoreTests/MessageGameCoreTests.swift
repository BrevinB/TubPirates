import BathtubEngine
import Foundation
import MessageGameCore
import Testing

@Suite("Messages battle protocol")
struct MessageGameCoreTests {
    @Test("A challenge joins into a complete battle")
    func joinsChallenge() throws {
        let challenge = MessageGameEnvelope.newChallenge(board: board(seed: 1))
        let joined = try MessageGameFlow.join(challenge, with: board(seed: 2))

        #expect(joined.gameID == challenge.gameID)
        #expect(joined.revision == 1)
        #expect(joined.senderSeat == .two)
        guard case .battle(let state) = joined.content else {
            Issue.record("Expected battle state")
            return
        }
        #expect(state.currentPlayer == .one)
        #expect(state.availableShots(for: .one) == ShotType.allCases)
    }

    @Test("Every weapon round-trips and advances the revision", arguments: ShotType.allCases)
    func weaponRoundTrip(shot: ShotType) throws {
        let challenge = MessageGameEnvelope.newChallenge(board: board(seed: 3))
        let joined = try MessageGameFlow.join(challenge, with: board(seed: 4))
        let target = shot.spec.needsTarget ? Coordinate(row: 4, col: 4) : nil
        let orientation: Orientation? = shot.spec.needsOrientation ? .horizontal : nil
        let played = try MessageGameFlow.play(
            shot,
            target: target,
            orientation: orientation,
            by: .one,
            in: joined
        )
        let decoded = try MessagePayloadURLCodec.decode(MessagePayloadURLCodec.encode(played))

        #expect(decoded.revision == 2)
        #expect(decoded.latestResolution?.move.shot == shot)
        #expect(decoded.latestResolution?.move.target == target)
    }

    @Test("Forfeiting ends the battle for the opponent")
    func forfeits() throws {
        let joined = try MessageGameFlow.join(
            .newChallenge(board: board(seed: 5)),
            with: board(seed: 6)
        )
        let result = try MessageGameFlow.forfeit(joined, by: .one)

        #expect(result.isFinished)
        #expect(result.winner == .two)
        #expect(result.revision == 2)
    }

    @Test("Malformed links and invalid fleets are rejected")
    func rejectsInvalidData() throws {
        #expect(throws: MessagePayloadURLCodec.URLCodecError.unsupportedURL) {
            try MessagePayloadURLCodec.decode(#require(URL(string: "https://example.com")))
        }
        let invalid = MessageGameEnvelope.newChallenge(board: Board())
        #expect(throws: MessageGameCodec.CodecError.invalidSetup) {
            try MessageGameCodec.encode(invalid)
        }
    }

    @Test("A long battle stays well inside the iMessage payload budget")
    func payloadSizeStaysBounded() throws {
        var envelope = try MessageGameFlow.join(
            .newChallenge(board: board(seed: 11)),
            with: board(seed: 12)
        )
        var largestURL = 0
        var turns = 0

        outer: for col in 0..<10 {
            for row in 0..<10 {
                guard case .battle(let state) = envelope.content, !envelope.isFinished else { break outer }
                envelope = try MessageGameFlow.play(
                    .cannon,
                    target: Coordinate(row: row, col: col),
                    orientation: nil,
                    by: state.currentPlayer,
                    in: envelope
                )
                turns += 1
                largestURL = max(largestURL, try MessagePayloadURLCodec.encode(envelope).absoluteString.count)
            }
        }

        print("PAYLOAD turns=\(turns) largestURLChars=\(largestURL)")
        #expect(turns > 20, "The battle should run long enough to be a real worst case")
        // MSMessage.url is the transport; keep a wide margin under the codec cap.
        #expect(largestURL < MessageGameCodec.maximumPayloadSize)
    }

    @Test("Both captains' looks ride along and survive the wire")
    func carriesAppearances() throws {
        let challenger = SharedAppGroup.Appearance(avatarID: "portrait_sal", fleetID: "ducky")
        let joiner = SharedAppGroup.Appearance(avatarID: "portrait_bubbles", fleetID: "gilded")

        let challenge = MessageGameEnvelope.newChallenge(board: board(seed: 21), appearance: challenger)
        let joined = try MessageGameFlow.join(challenge, with: board(seed: 22), appearance: joiner)
        let played = try MessageGameFlow.play(
            .cannon,
            target: Coordinate(row: 1, col: 1),
            orientation: nil,
            by: .one,
            in: joined,
            appearance: challenger
        )
        let decoded = try MessagePayloadURLCodec.decode(MessagePayloadURLCodec.encode(played))

        #expect(decoded.appearance(of: .one) == challenger)
        #expect(decoded.appearance(of: .two) == joiner)

        // A forfeit carries them too, so the end screen still shows both.
        let forfeited = try MessageGameFlow.forfeit(joined, by: .two)
        #expect(forfeited.appearance(of: .one) == challenger)
    }

    @Test("A rival's fleet survives every hop of a battle")
    func fleetIDSurvivesTheWholeBattle() throws {
        let ducky = SharedAppGroup.Appearance(avatarID: "portrait_sal", fleetID: "ducky")
        let gilded = SharedAppGroup.Appearance(avatarID: "portrait_bubbles", fleetID: "gilded")

        // Challenge -> join -> several turns, re-encoded at every hop the way
        // Messages actually carries it.
        var envelope = MessageGameEnvelope.newChallenge(board: board(seed: 41), appearance: ducky)
        envelope = try MessagePayloadURLCodec.decode(MessagePayloadURLCodec.encode(envelope))
        envelope = try MessageGameFlow.join(envelope, with: board(seed: 42), appearance: gilded)

        for turn in 0..<4 {
            envelope = try MessagePayloadURLCodec.decode(MessagePayloadURLCodec.encode(envelope))
            guard case .battle(let state) = envelope.content else {
                Issue.record("Expected a battle")
                return
            }
            let mover = state.currentPlayer
            envelope = try MessageGameFlow.play(
                .cannon,
                target: Coordinate(row: turn, col: turn),
                orientation: nil,
                by: mover,
                in: envelope,
                appearance: mover == .one ? ducky : gilded
            )
        }

        let decoded = try MessagePayloadURLCodec.decode(MessagePayloadURLCodec.encode(envelope))
        #expect(decoded.appearance(of: .one).fleetID == "ducky")
        #expect(decoded.appearance(of: .two).fleetID == "gilded")
        #expect(decoded.appearance(of: .one).avatarID == "portrait_sal")
        #expect(decoded.appearance(of: .two).avatarID == "portrait_bubbles")
    }

    @Test("A battle sent before appearances existed still opens")
    func decodesPayloadWithoutAppearances() throws {
        let joined = try MessageGameFlow.join(.newChallenge(board: board(seed: 31)), with: board(seed: 32))
        var json = try JSONSerialization.jsonObject(
            with: MessageGameCodec.encode(joined)
        ) as! [String: Any]
        // Exactly what a payload written by the shipped version looks like.
        json.removeValue(forKey: "appearances")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try MessageGameCodec.decode(data)
        #expect(decoded.appearances.isEmpty)
        // And falls back to the stock captain rather than throwing.
        #expect(decoded.appearance(of: .one) == .default)
        #expect(decoded.revision == joined.revision)
    }

    private func board(seed: UInt64) -> Board {
        var generator = SeededGenerator(state: seed)
        return Board.randomlyPlaced(using: &generator)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
