import SwiftUI
import BathtubEngine

/// Pre-battle fleet placement: a straight (un-rotated) grid for usability.
/// Drag ships from the tray onto the board, tap a placed ship to rotate it,
/// drag a placed ship off the board to return it, or just Randomize.
struct PlacementView: View {
    let config: MatchConfig
    @Binding var path: [Route]

    @State private var board = Board()
    /// Kind being dragged (from tray or board) and its current finger location.
    @State private var draggingKind: ShipKind?
    @State private var dragLocation: CGPoint = .zero
    /// Where the drag started from the board (so a failed re-place restores it).
    @State private var liftedShip: Ship?

    private static let shipImages: [ShipKind: String] = [
        .galleon: "ship_5", .frigate: "ship_4", .tugboat: "ship_3a",
        .duckSub: "ship_3b", .dinghy: "ship_2",
    ]

    private var trayKinds: [ShipKind] {
        var remaining = ShipKind.standardFleet
        for ship in board.ships {
            if let index = remaining.firstIndex(of: ship.kind) {
                remaining.remove(at: index)
            }
        }
        return remaining
    }

    private var fleetComplete: Bool {
        board.ships.count == ShipKind.standardFleet.count
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.35, blue: 0.6), Color(red: 0.05, green: 0.2, blue: 0.4)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Place Your Fleet")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Drag ships to the board • Tap a ship to rotate")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))

                boardGrid
                    .padding(.horizontal, 14)

                tray

                HStack(spacing: 14) {
                    Button {
                        var rng = SystemRandomNumberGenerator()
                        board = Board.randomlyPlaced(using: &rng)
                    } label: {
                        Label("Randomize", systemImage: "dice.fill")
                            .font(.headline)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button {
                        var battleConfig = config
                        battleConfig.playerBoard = board
                        path.append(.match(battleConfig))
                    } label: {
                        Label("Battle!", systemImage: "flag.checkered")
                            .font(.headline.weight(.bold))
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!fleetComplete)
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical)
        }
        .navigationTitle("")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    // MARK: - Board

    private var boardGrid: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cellSize = side / 10
            ZStack(alignment: .topLeading) {
                // Water tiles
                ForEach(Coordinate.allBoardCells, id: \.self) { cell in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.42, green: 0.72, blue: 0.93))
                        .padding(1)
                        .frame(width: cellSize, height: cellSize)
                        .position(center(of: cell, cellSize: cellSize))
                }

                // Drop preview
                if let kind = draggingKind {
                    let origin = dropOrigin(for: kind, cellSize: cellSize, in: geo.size)
                    if let origin {
                        let valid = boardWithoutLifted.canPlace(kind, at: origin.cell, orientation: origin.orientation)
                        ForEach(Ship(kind: kind, origin: origin.cell, orientation: origin.orientation).cells.filter(\.isValid), id: \.self) { cell in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(valid ? Color.green.opacity(0.55) : Color.red.opacity(0.55))
                                .padding(1)
                                .frame(width: cellSize, height: cellSize)
                                .position(center(of: cell, cellSize: cellSize))
                        }
                    }
                }

                // Placed ships
                ForEach(board.ships) { ship in
                    shipImage(ship.kind)
                        .rotationEffect(ship.orientation == .horizontal ? .zero : .degrees(90))
                        .frame(
                            width: ship.orientation == .horizontal ? cellSize * CGFloat(ship.kind.length) : cellSize,
                            height: ship.orientation == .horizontal ? cellSize : cellSize * CGFloat(ship.kind.length)
                        )
                        .position(shipCenter(ship, cellSize: cellSize))
                        .opacity(liftedShip?.id == ship.id ? 0.25 : 1)
                        .onTapGesture { rotate(ship) }
                        .gesture(boardShipDrag(ship, cellSize: cellSize))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .coordinateSpace(name: "board")
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .onGeometryChange(for: CGFloat.self) { _ in
                side
            } action: { value in
                boardSideLength = value
            }
        }
    }

    /// The board minus the ship currently lifted for re-dragging.
    private var boardWithoutLifted: Board {
        guard let liftedShip else { return board }
        var copy = board
        copy.removeShip(id: liftedShip.id)
        return copy
    }

    private func center(of cell: Coordinate, cellSize: CGFloat) -> CGPoint {
        CGPoint(
            x: (CGFloat(cell.col) + 0.5) * cellSize,
            y: (CGFloat(cell.row) + 0.5) * cellSize
        )
    }

    private func shipCenter(_ ship: Ship, cellSize: CGFloat) -> CGPoint {
        let first = center(of: ship.cells.first!, cellSize: cellSize)
        let last = center(of: ship.cells.last!, cellSize: cellSize)
        return CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
    }

    /// Converts the current drag location to a candidate origin cell
    /// (finger anchors the ship's first cell, clamped into bounds).
    private func dropOrigin(for kind: ShipKind, cellSize: CGFloat, in size: CGSize)
        -> (cell: Coordinate, orientation: Orientation)? {
        guard dragLocation.x > -cellSize, dragLocation.y > -cellSize,
              dragLocation.x < size.width + cellSize, dragLocation.y < size.height + cellSize
        else { return nil }
        let orientation = liftedShip?.orientation ?? .horizontal
        var col = Int(dragLocation.x / cellSize)
        var row = Int(dragLocation.y / cellSize)
        if orientation == .horizontal {
            col = min(col, Board.size - kind.length)
        } else {
            row = min(row, Board.size - kind.length)
        }
        let cell = Coordinate(row: max(0, min(row, Board.size - 1)), col: max(0, min(col, Board.size - 1)))
        return (cell, orientation)
    }

    // MARK: - Interactions

    private func rotate(_ ship: Ship) {
        var copy = board
        copy.removeShip(id: ship.id)
        let rotated = ship.orientation.toggled
        // Try rotating in place; nudge the origin into bounds if needed.
        var origin = ship.origin
        if rotated == .horizontal { origin.col = min(origin.col, Board.size - ship.kind.length) }
        if rotated == .vertical { origin.row = min(origin.row, Board.size - ship.kind.length) }
        if copy.canPlace(ship.kind, at: origin, orientation: rotated) {
            try? copy.place(ship.kind, at: origin, orientation: rotated)
            board = copy
        }
    }

    private func boardShipDrag(_ ship: Ship, cellSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("board"))
            .onChanged { value in
                liftedShip = ship
                draggingKind = ship.kind
                dragLocation = value.location
            }
            .onEnded { value in
                dragLocation = value.location
                defer { draggingKind = nil; liftedShip = nil }
                var copy = board
                copy.removeShip(id: ship.id)
                // Dropped off-board = return to tray; otherwise try the new spot.
                let bounds = CGRect(x: 0, y: 0, width: cellSize * 10, height: cellSize * 10)
                if bounds.insetBy(dx: -cellSize, dy: -cellSize).contains(value.location) {
                    if let target = dropOrigin(for: ship.kind, cellSize: cellSize, in: bounds.size),
                       copy.canPlace(ship.kind, at: target.cell, orientation: target.orientation) {
                        try? copy.place(ship.kind, at: target.cell, orientation: target.orientation)
                    } else {
                        return // invalid spot: keep the original placement
                    }
                }
                board = copy
            }
    }

    // MARK: - Tray

    private var tray: some View {
        HStack(spacing: 8) {
            if trayKinds.isEmpty {
                Text("Fleet ready, Captain! ⚓️")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            ForEach(trayKinds, id: \.self) { kind in
                trayShip(kind)
            }
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
    }

    private func trayShip(_ kind: ShipKind) -> some View {
        shipImage(kind)
            .frame(maxWidth: CGFloat(kind.length) * 17, maxHeight: 24)
            .opacity(draggingKind == kind && liftedShip == nil ? 0.3 : 1)
            .gesture(trayDrag(kind))
            .accessibilityLabel(kind.displayName)
    }

    private func trayDrag(_ kind: ShipKind) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("board"))
            .onChanged { value in
                draggingKind = kind
                liftedShip = nil
                dragLocation = value.location
            }
            .onEnded { value in
                dragLocation = value.location
                defer { draggingKind = nil }
                // The tray sits below the board; board coordinates come from the named space.
                guard let boardSide = boardSideLength else { return }
                let size = CGSize(width: boardSide, height: boardSide)
                if let target = dropOrigin(for: kind, cellSize: boardSide / 10, in: size),
                   board.canPlace(kind, at: target.cell, orientation: target.orientation) {
                    try? board.place(kind, at: target.cell, orientation: target.orientation)
                }
            }
    }

    /// Board side length in the shared coordinate space (screen width minus padding).
    @State private var boardSideLength: CGFloat?

    private func shipImage(_ kind: ShipKind) -> some View {
        Image(Self.shipImages[kind] ?? "ship_2")
            .resizable()
            .scaledToFit()
    }
}

#Preview {
    NavigationStack {
        PlacementView(config: MatchConfig(), path: .constant([]))
    }
}
