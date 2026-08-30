import SwiftUI
import UIKit
import BathtubEngine

/// Pre-battle fleet placement: a straight (un-rotated) grid over the tub water.
/// Drag ships from the caddy shelf onto the board — a ghost ship floats above
/// your finger so you can see exactly where it lands — tap a placed ship to
/// rotate it, drag it off the board to shelve it, or just Randomize.
struct PlacementView: View {
    let config: MatchConfig
    @Binding var path: [Route]

    @State private var board = Board()
    /// Kind being dragged (from shelf or board) and the finger's board-space location.
    @State private var draggingKind: ShipKind?
    @State private var dragLocation: CGPoint = .zero
    /// The placed ship a drag started from (so an invalid re-place restores it).
    @State private var liftedShip: Ship?
    /// The board grid's frame in global coordinates. Drags from the shelf and
    /// the board both report globally and convert through this — a named
    /// coordinate space can't be resolved from the shelf (it's not a descendant
    /// of the board), which pinned shelf drags to the top rows.
    @State private var boardFrame: CGRect = .zero
    /// Last previewed origin, for haptic ticks as the ghost snaps cell to cell.
    @State private var lastTickedOrigin: Coordinate?

    @Environment(ProfileStore.self) private var profileStore

    /// The equipped cosmetic fleet's sprite for a ship kind.
    private func shipImage(_ kind: ShipKind) -> String {
        profileStore.fleet.textureName(for: kind)
    }

    /// How far the ghost floats above the finger, in cells — keeps the ship
    /// visible instead of hidden under your thumb.
    private let fingerLift: CGFloat = 1.15

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
            ScreenBackground(imageName: "placement_background")
                .onAppear {
                    guard board.ships.isEmpty else { return }
                    #if DEBUG
                    // Debug: pre-place a random fleet for screenshots.
                    if CommandLine.arguments.contains("-randomize") {
                        var rng = SystemRandomNumberGenerator()
                        board = Board.randomlyPlaced(using: &rng)
                        return
                    }
                    #endif
                    if let previous = config.playerBoard {
                        // Rematch: start from last game's layout — one tap to
                        // re-battle, or drag to reposition.
                        board = previous
                    }
                }

            VStack(spacing: 10) {
                Text("Place Your Fleet")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.52))
                    .shadow(color: .white.opacity(0.9), radius: 2)
                Text("Drag toys from the shelf • Tap a ship to rotate")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                    .shadow(color: .white.opacity(0.8), radius: 2)

                boardGrid
                    .padding(.horizontal, 14)

                HStack(spacing: 14) {
                    Button {
                        var rng = SystemRandomNumberGenerator()
                        board = Board.randomlyPlaced(using: &rng)
                        Haptics.impact(.medium)
                    } label: {
                        Label("Randomize", systemImage: "dice.fill")
                            .font(.headline)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.25, green: 0.5, blue: 0.75))

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

                tray
                    .padding(.bottom, 6)
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
                        .fill(Color(red: 0.42, green: 0.72, blue: 0.93).opacity(0.85))
                        .padding(1)
                        .frame(width: cellSize, height: cellSize)
                        .position(center(of: cell, cellSize: cellSize))
                }

                // Drop preview under the ghost
                if let kind = draggingKind,
                   let target = dropTarget(for: kind, cellSize: cellSize) {
                    let valid = boardWithoutLifted.canPlace(kind, at: target.cell, orientation: target.orientation)
                    ForEach(Ship(kind: kind, origin: target.cell, orientation: target.orientation).cells.filter(\.isValid), id: \.self) { cell in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(valid ? Color.green.opacity(0.55) : Color.red.opacity(0.55))
                            .padding(1)
                            .frame(width: cellSize, height: cellSize)
                            .position(center(of: cell, cellSize: cellSize))
                    }
                }

                // Placed ships: framed horizontally at their true footprint,
                // then rotated — so vertical ships lie along their cells.
                ForEach(board.ships) { ship in
                    Image(shipImage(ship.kind))
                        .resizable()
                        .scaledToFit() // preserve the toy's aspect inside its footprint
                        .frame(
                            width: cellSize * CGFloat(ship.kind.length) * 0.98,
                            height: cellSize * 1.2
                        )
                        .rotationEffect(ship.orientation == .horizontal ? .zero : .degrees(90))
                        .position(shipCenter(ship, cellSize: cellSize))
                        .opacity(liftedShip?.id == ship.id ? 0.25 : 1)
                        .onTapGesture { rotate(ship) }
                        .gesture(shipDrag(ship, cellSize: cellSize))
                }

                // The ghost ship floating above the finger
                if let kind = draggingKind {
                    Image(shipImage(kind))
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: cellSize * CGFloat(kind.length),
                            height: cellSize * 1.2
                        )
                        .rotationEffect(dragOrientation == .horizontal ? .zero : .degrees(90))
                        .position(ghostCenter(cellSize: cellSize))
                        .opacity(0.85)
                        .scaleEffect(1.06)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { value in
                boardFrame = value
            }
        }
    }

    /// Board-local point for a globally-reported drag location.
    private func boardLocal(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - boardFrame.minX, y: global.y - boardFrame.minY)
    }

    private var cellSizeFromFrame: CGFloat? {
        boardFrame.width > 0 ? boardFrame.width / 10 : nil
    }

    /// The board minus the ship currently lifted for re-dragging.
    private var boardWithoutLifted: Board {
        guard let liftedShip else { return board }
        var copy = board
        copy.removeShip(id: liftedShip.id)
        return copy
    }

    private var dragOrientation: Orientation {
        liftedShip?.orientation ?? .horizontal
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

    /// Where the ghost ship's center sits: lifted above the finger so the
    /// toy stays visible while dragging.
    private func ghostCenter(cellSize: CGFloat) -> CGPoint {
        CGPoint(x: dragLocation.x, y: dragLocation.y - cellSize * fingerLift)
    }

    /// Converts the ghost's center to a snapped origin cell, or nil when the
    /// ghost is too far off the board (= drop back onto the shelf).
    private func dropTarget(for kind: ShipKind, cellSize: CGFloat)
        -> (cell: Coordinate, orientation: Orientation)? {
        let side = cellSize * 10
        let ghost = ghostCenter(cellSize: cellSize)
        let margin = cellSize * 1.2
        guard ghost.x > -margin, ghost.x < side + margin,
              ghost.y > -margin, ghost.y < side + margin
        else { return nil }

        let orientation = dragOrientation
        let length = CGFloat(kind.length)
        var row: Int
        var col: Int
        // A ship spanning cells c..c+len-1 has center at (c + len/2) * cell.
        switch orientation {
        case .horizontal:
            col = Int((ghost.x / cellSize - length / 2).rounded())
            row = Int((ghost.y / cellSize - 0.5).rounded())
        case .vertical:
            col = Int((ghost.x / cellSize - 0.5).rounded())
            row = Int((ghost.y / cellSize - length / 2).rounded())
        }
        // Clamp fully onto the board.
        if orientation == .horizontal {
            col = max(0, min(col, Board.size - kind.length))
            row = max(0, min(row, Board.size - 1))
        } else {
            row = max(0, min(row, Board.size - kind.length))
            col = max(0, min(col, Board.size - 1))
        }
        return (Coordinate(row: row, col: col), orientation)
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
            Haptics.impact(.light)
        } else {
            Haptics.notify(.warning)
        }
    }

    private func updateDrag(kind: ShipKind, lifted: Ship?, location: CGPoint, cellSize: CGFloat?) {
        draggingKind = kind
        liftedShip = lifted
        dragLocation = location
        // Tick as the ghost snaps from cell to cell.
        if let cellSize, let target = dropTarget(for: kind, cellSize: cellSize) {
            if target.cell != lastTickedOrigin {
                lastTickedOrigin = target.cell
                Haptics.impact(.light, intensity: 0.6)
            }
        } else {
            lastTickedOrigin = nil
        }
    }

    private func finishDrag(kind: ShipKind, cellSize: CGFloat?) {
        defer {
            draggingKind = nil
            liftedShip = nil
            lastTickedOrigin = nil
        }
        guard let cellSize else { return }
        var copy = board
        if let liftedShip {
            copy.removeShip(id: liftedShip.id)
        }
        if let target = dropTarget(for: kind, cellSize: cellSize) {
            if copy.canPlace(kind, at: target.cell, orientation: target.orientation) {
                try? copy.place(kind, at: target.cell, orientation: target.orientation)
                board = copy
                Haptics.notify(.success)
            } else if liftedShip != nil {
                // Invalid spot for a board ship: keep its original placement.
                Haptics.notify(.warning)
            }
        } else if liftedShip != nil {
            // Dragged clear off the board: back to the shelf.
            board = copy
            Haptics.impact(.medium)
        }
    }

    private func shipDrag(_ ship: Ship, cellSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                updateDrag(kind: ship.kind, lifted: ship, location: boardLocal(value.location), cellSize: cellSize)
            }
            .onEnded { value in
                dragLocation = boardLocal(value.location)
                finishDrag(kind: ship.kind, cellSize: cellSize)
            }
    }

    private func trayDrag(_ kind: ShipKind) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                updateDrag(kind: kind, lifted: nil, location: boardLocal(value.location),
                           cellSize: cellSizeFromFrame)
            }
            .onEnded { value in
                dragLocation = boardLocal(value.location)
                finishDrag(kind: kind, cellSize: cellSizeFromFrame)
            }
    }

    // MARK: - Shelf tray

    private var tray: some View {
        HStack(spacing: 10) {
            if trayKinds.isEmpty {
                Text("Fleet ready, Captain! ⚓️")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.08))
                    .shadow(color: .white.opacity(0.4), radius: 1)
            }
            ForEach(trayKinds, id: \.self) { kind in
                trayShip(kind)
            }
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func trayShip(_ kind: ShipKind) -> some View {
        Image(shipImage(kind))
            .resizable()
            .scaledToFit()
            .frame(maxWidth: CGFloat(kind.length) * 19, maxHeight: 30)
            .opacity(draggingKind == kind && liftedShip == nil ? 0.3 : 1)
            // Generous invisible hit area — little toys are hard to pinch.
            .frame(minWidth: 44, minHeight: 56)
            .contentShape(Rectangle())
            .gesture(trayDrag(kind))
            .accessibilityLabel(kind.localizedDisplayName)
    }
}

#Preview {
    NavigationStack {
        PlacementView(config: MatchConfig(), path: .constant([]))
    }
}
