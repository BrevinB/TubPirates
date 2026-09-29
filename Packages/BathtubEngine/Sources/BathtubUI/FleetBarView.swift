#if canImport(UIKit)
import BathtubEngine
import SwiftUI

/// Five tiny segment rows, one per ship, largest on top — fleet health at a
/// glance without squinting at the mini board. Own bar fills damaged segments
/// red; the rival's rows only flip when a ship actually sinks.
///
/// Shared, so the Messages battle shows the identical bar rather than the text
/// table it used to. The two constructors are the only place that decides what
/// each side is allowed to know.
public struct FleetBarView: View {
    public struct ShipStatus: Identifiable, Equatable, Sendable {
        public let id: String
        public let length: Int
        public let hitCount: Int
        public let isSunk: Bool

        public init(id: String, length: Int, hitCount: Int, isSunk: Bool) {
            self.id = id
            self.length = length
            self.hitCount = hitCount
            self.isSunk = isSunk
        }
    }

    let fleet: [ShipStatus]
    let alignment: HorizontalAlignment
    /// Height of one hull segment. The app draws 5.5; the Messages sheet
    /// shrinks it with the rest of the top band on a short screen.
    var segmentHeight: CGFloat

    public init(
        fleet: [ShipStatus],
        alignment: HorizontalAlignment,
        segmentHeight: CGFloat = 5.5
    ) {
        self.fleet = fleet
        self.alignment = alignment
        self.segmentHeight = segmentHeight
    }

    /// Your own tub: exact damage is known, so partial hits show.
    public static func own(_ board: Board) -> [ShipStatus] {
        board.ships
            .sorted { $0.kind.length > $1.kind.length }
            .map { ship in
                ShipStatus(
                    id: ship.kind.rawValue,
                    length: ship.kind.length,
                    hitCount: ship.cells.filter(board.hitCells.contains).count,
                    isSunk: board.isSunk(ship)
                )
            }
    }

    /// Enemy waters: only a sinking is public knowledge, so rows stay full
    /// until the ship goes down.
    public static func enemy(_ view: AttackerView) -> [ShipStatus] {
        let sunkKinds = Set(view.sunkShips.map(\.kind))
        return ShipKind.standardFleet
            .sorted { $0.length > $1.length }
            .map { kind in
                ShipStatus(
                    id: kind.rawValue,
                    length: kind.length,
                    hitCount: 0,
                    isSunk: sunkKinds.contains(kind)
                )
            }
    }

    private var segmentWidth: CGFloat { segmentHeight * 8 / 5.5 }

    public var body: some View {
        VStack(alignment: alignment, spacing: 2.5) {
            ForEach(fleet) { ship in
                HStack(spacing: 1.5) {
                    ForEach(0..<ship.length, id: \.self) { segment in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(segmentColor(ship, segment: segment))
                            .frame(width: segmentWidth, height: segmentHeight)
                    }
                }
                .overlay {
                    if ship.isSunk {
                        Image(systemName: "xmark")
                            .font(.system(size: segmentHeight * 8 / 5.5 - 0.5, weight: .black))
                            .foregroundStyle(TubPalette.sunkMark)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(for: ship))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        // Solid ship's-timber brown (the reward chips' color) instead of
        // translucent black; the cream segments stay high-contrast on it.
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(TubPalette.timber.opacity(0.88))
        )
        .animation(.easeInOut(duration: 0.3), value: fleet.map(\.hitCount))
    }

    private func segmentColor(_ ship: ShipStatus, segment: Int) -> Color {
        if ship.isSunk { return TubPalette.sunkGray }
        if segment < ship.hitCount { return TubPalette.hit }
        return TubPalette.cream
    }

    private func label(for ship: ShipStatus) -> String {
        let name = ShipKind(rawValue: ship.id)?.displayName ?? ship.id
        if ship.isSunk {
            return String(localized: "\(name), sunk", bundle: .module)
        }
        return String(
            localized: "\(name), \(ship.length - ship.hitCount) of \(ship.length) afloat",
            bundle: .module
        )
    }
}
#endif
