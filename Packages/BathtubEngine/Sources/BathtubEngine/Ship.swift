import Foundation

/// The bath-toy fleet, dinghy through galleon.
public enum ShipKind: String, Codable, CaseIterable, Sendable {
    case dinghy    // 2
    case tugboat   // 3
    case duckSub   // 3
    case frigate   // 4
    case galleon   // 5

    public var length: Int {
        switch self {
        case .dinghy: 2
        case .tugboat, .duckSub: 3
        case .frigate: 4
        case .galleon: 5
        }
    }

    public var displayName: String {
        switch self {
        case .dinghy: "Dinghy"
        case .tugboat: "Tugboat"
        case .duckSub: "Duck Sub"
        case .frigate: "Frigate"
        case .galleon: "Galleon"
        }
    }

    /// The standard five-ship fleet used in every match.
    public static let standardFleet: [ShipKind] = [.galleon, .frigate, .tugboat, .duckSub, .dinghy]
}

public struct Ship: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let kind: ShipKind
    public let origin: Coordinate
    public let orientation: Orientation

    public init(id: UUID = UUID(), kind: ShipKind, origin: Coordinate, orientation: Orientation) {
        self.id = id
        self.kind = kind
        self.origin = origin
        self.orientation = orientation
    }

    public var cells: [Coordinate] {
        (0..<kind.length).map { i in
            switch orientation {
            case .horizontal: origin.offset(0, i)
            case .vertical: origin.offset(i, 0)
            }
        }
    }
}
