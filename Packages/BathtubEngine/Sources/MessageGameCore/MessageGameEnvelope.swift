import BathtubEngine
import Foundation

public struct MessageGameEnvelope: Codable, Sendable {
    public static let currentVersion = 1

    public enum Content: Codable, Sendable {
        case setup(boards: [PlayerID: Board])
        case battle(state: GameState)
    }

    public let version: Int
    public let gameID: UUID
    public let revision: Int
    public let senderSeat: PlayerID
    public let content: Content
    public let latestResolution: MoveResolution?
    public let forfeitedBy: PlayerID?
    /// What each captain looks like — the portrait on their name-plate and the
    /// cosmetic fleet their toys are drawn from. Accumulated as the battle goes
    /// (the challenger's rides along with the challenge, the joiner's is added
    /// when they answer) so both sheets can show both captains.
    ///
    /// Optional and defaulted: a payload written before this existed decodes
    /// with an empty map and falls back to the stock captain, so battles that
    /// were already in flight keep working without a version bump.
    public let appearances: [PlayerID: SharedAppGroup.Appearance]

    public init(
        version: Int,
        gameID: UUID,
        revision: Int,
        senderSeat: PlayerID,
        content: Content,
        latestResolution: MoveResolution?,
        forfeitedBy: PlayerID? = nil,
        appearances: [PlayerID: SharedAppGroup.Appearance] = [:]
    ) {
        self.version = version
        self.gameID = gameID
        self.revision = revision
        self.senderSeat = senderSeat
        self.content = content
        self.latestResolution = latestResolution
        self.forfeitedBy = forfeitedBy
        self.appearances = appearances
    }

    private enum CodingKeys: String, CodingKey {
        case version, gameID, revision, senderSeat, content, latestResolution
        case forfeitedBy, appearances
    }

    /// Hand-written so `appearances` can be absent.
    ///
    /// A synthesized decoder calls `decode` for a non-optional dictionary and
    /// throws on a missing key, which would have turned every battle that was
    /// mid-flight during the update into "this battle is damaged".
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        gameID = try container.decode(UUID.self, forKey: .gameID)
        revision = try container.decode(Int.self, forKey: .revision)
        senderSeat = try container.decode(PlayerID.self, forKey: .senderSeat)
        content = try container.decode(Content.self, forKey: .content)
        latestResolution = try container.decodeIfPresent(MoveResolution.self, forKey: .latestResolution)
        forfeitedBy = try container.decodeIfPresent(PlayerID.self, forKey: .forfeitedBy)
        appearances = try container.decodeIfPresent(
            [PlayerID: SharedAppGroup.Appearance].self,
            forKey: .appearances
        ) ?? [:]
    }

    /// The look for a seat, or the stock captain when that pirate's device
    /// never published one.
    public func appearance(of player: PlayerID) -> SharedAppGroup.Appearance {
        appearances[player] ?? .default
    }

    public static func newChallenge(
        board: Board,
        appearance: SharedAppGroup.Appearance = .default
    ) -> MessageGameEnvelope {
        MessageGameEnvelope(
            version: currentVersion,
            gameID: UUID(),
            revision: 0,
            senderSeat: .one,
            content: .setup(boards: [.one: board]),
            latestResolution: nil,
            appearances: [.one: appearance]
        )
    }

    public var winner: PlayerID? {
        if let forfeitedBy { return forfeitedBy.opponent }
        guard case .battle(let state) = content,
              case .finished(let winner) = state.phase else { return nil }
        return winner
    }

    public var isFinished: Bool { winner != nil }
}
