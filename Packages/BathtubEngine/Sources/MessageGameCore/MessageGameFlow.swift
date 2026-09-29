import BathtubEngine
import Foundation

public enum MessageGameFlow {
    public enum FlowError: LocalizedError, Equatable {
        case invalidChallenge
        case invalidBattle
        case notYourTurn
        case missingTarget
        case gameOver

        public var errorDescription: String? {
            switch self {
            case .invalidChallenge: "This challenge cannot be joined."
            case .invalidBattle: "No active battle is loaded."
            case .notYourTurn: "It isn't your turn."
            case .missingTarget: "Choose a target before firing."
            case .gameOver: "This battle is already over."
            }
        }
    }

    public static func localSeat(for envelope: MessageGameEnvelope, authoredLocally: Bool) -> PlayerID {
        authoredLocally ? envelope.senderSeat : envelope.senderSeat.opponent
    }

    public static func join(
        _ challenge: MessageGameEnvelope,
        with board: Board,
        appearance: SharedAppGroup.Appearance = .default
    ) throws -> MessageGameEnvelope {
        try MessageGameCodec.validate(challenge)
        guard case .setup(let boards) = challenge.content,
              boards[.one] != nil else { throw FlowError.invalidChallenge }

        let arsenal = Set(ShotType.allCases)
        let state = GameState(
            boards: [.one: boards[.one]!, .two: board],
            loadouts: [.one: arsenal, .two: arsenal],
            firstPlayer: .one
        )
        var appearances = challenge.appearances
        appearances[.two] = appearance
        let result = MessageGameEnvelope(
            version: MessageGameEnvelope.currentVersion,
            gameID: challenge.gameID,
            revision: challenge.revision + 1,
            senderSeat: .two,
            content: .battle(state: state),
            latestResolution: nil,
            appearances: appearances
        )
        try MessageGameCodec.validate(result)
        return result
    }

    public static func play(
        _ shot: ShotType,
        target: Coordinate?,
        orientation: Orientation?,
        by player: PlayerID,
        in envelope: MessageGameEnvelope,
        appearance: SharedAppGroup.Appearance? = nil
    ) throws -> MessageGameEnvelope {
        guard !envelope.isFinished else { throw FlowError.gameOver }
        guard case .battle(var state) = envelope.content else { throw FlowError.invalidBattle }
        guard state.currentPlayer == player else { throw FlowError.notYourTurn }
        if shot.spec.needsTarget, target == nil { throw FlowError.missingTarget }

        let move = Move(player: player, shot: shot, target: target, orientation: orientation)
        let resolution = try state.apply(move)
        // Refresh our own entry each turn: a captain who changes avatar
        // mid-battle should show up as the captain they are now.
        var appearances = envelope.appearances
        if let appearance { appearances[player] = appearance }
        let result = MessageGameEnvelope(
            version: MessageGameEnvelope.currentVersion,
            gameID: envelope.gameID,
            revision: envelope.revision + 1,
            senderSeat: player,
            content: .battle(state: state),
            latestResolution: resolution,
            appearances: appearances
        )
        try MessageGameCodec.validate(result)
        return result
    }

    public static func forfeit(_ envelope: MessageGameEnvelope, by player: PlayerID) throws -> MessageGameEnvelope {
        guard !envelope.isFinished else { throw FlowError.gameOver }
        guard case .battle = envelope.content else { throw FlowError.invalidBattle }
        let result = MessageGameEnvelope(
            version: MessageGameEnvelope.currentVersion,
            gameID: envelope.gameID,
            revision: envelope.revision + 1,
            senderSeat: player,
            content: envelope.content,
            latestResolution: nil,
            forfeitedBy: player,
            appearances: envelope.appearances
        )
        try MessageGameCodec.validate(result)
        return result
    }
}
