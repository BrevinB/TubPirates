import BathtubEngine
import Foundation

public enum MessageGameCodec {
    public static let maximumPayloadSize = 64 * 1_024

    public enum CodecError: LocalizedError, Equatable {
        case payloadTooLarge
        case malformedPayload
        case unsupportedVersion(Int)
        case invalidRevision
        case invalidSetup
        case invalidBattle

        public var errorDescription: String? {
            switch self {
            case .payloadTooLarge: "The game payload is too large."
            case .malformedPayload: "The game payload could not be decoded."
            case .unsupportedVersion(let version): "This battle uses unsupported version \(version)."
            case .invalidRevision: "The battle revision is invalid."
            case .invalidSetup: "The fleet setup is invalid."
            case .invalidBattle: "The battle state is invalid."
            }
        }
    }

    public static func encode(_ envelope: MessageGameEnvelope) throws -> Data {
        try validate(envelope)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= maximumPayloadSize else { throw CodecError.payloadTooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> MessageGameEnvelope {
        guard data.count <= maximumPayloadSize else { throw CodecError.payloadTooLarge }
        let envelope: MessageGameEnvelope
        do {
            envelope = try JSONDecoder().decode(MessageGameEnvelope.self, from: data)
        } catch {
            throw CodecError.malformedPayload
        }
        try validate(envelope)
        return envelope
    }

    public static func validate(_ envelope: MessageGameEnvelope) throws {
        guard envelope.version == MessageGameEnvelope.currentVersion else {
            throw CodecError.unsupportedVersion(envelope.version)
        }
        guard envelope.revision >= 0 else { throw CodecError.invalidRevision }

        switch envelope.content {
        case .setup(let boards):
            guard envelope.revision == 0,
                  envelope.senderSeat == .one,
                  envelope.latestResolution == nil,
                  envelope.forfeitedBy == nil,
                  boards.count == 1,
                  let board = boards[.one],
                  isValidSetupBoard(board) else { throw CodecError.invalidSetup }
        case .battle(let state):
            guard envelope.revision > 0,
                  state.boards.count == 2,
                  state.boards[.one] != nil,
                  state.boards[.two] != nil,
                  state.boards.values.allSatisfy(isValidBattleBoard),
                  envelope.forfeitedBy == nil || envelope.latestResolution == nil
            else { throw CodecError.invalidBattle }
        }
    }

    private static func isValidSetupBoard(_ board: Board) -> Bool {
        isValidFleet(board) && board.shotCells.isEmpty && board.hitCells.isEmpty && board.revealedCells.isEmpty
    }

    private static func isValidBattleBoard(_ board: Board) -> Bool {
        isValidFleet(board)
            && board.hitCells.isSubset(of: board.shotCells)
            && board.shotCells.allSatisfy(\.isValid)
            && board.revealedCells.allSatisfy(\.isValid)
    }

    private static func isValidFleet(_ board: Board) -> Bool {
        guard board.ships.count == ShipKind.standardFleet.count,
              ShipKind.standardFleet.allSatisfy({ kind in
                  board.ships.count(where: { $0.kind == kind }) == 1
              }) else { return false }
        let occupied = board.ships.flatMap(\.cells)
        return occupied.allSatisfy(\.isValid) && Set(occupied).count == occupied.count
    }
}
