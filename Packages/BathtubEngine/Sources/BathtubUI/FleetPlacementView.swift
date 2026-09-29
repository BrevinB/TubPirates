#if canImport(UIKit)
import BathtubEngine
import SwiftUI

/// Column headings, so a spoken square reads "C7" the way players say it.
let boardColumnLabels = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]

/// Pre-battle fleet placement: a straight (un-rotated) grid over the tub water.
/// Drag ships from the caddy shelf onto the board — a ghost ship floats above
/// your finger so you can see exactly where it lands — tap a placed ship to
/// rotate it, drag it off the board to shelve it, or just Randomize.
///
/// One implementation for both hosts. The Messages extension used to offer a
/// completely different interaction here (pick a chip, set Across/Down, tap a
/// cell), which is the single biggest reason the sheet didn't feel like the
/// game. The host supplies only the buttons under the board.
public struct FleetPlacementView<Actions: View>: View {
    @Binding var board: Board
    let title: String
    let subtitle: String
    /// The equipped cosmetic fleet's sprite for a ship kind.
    let shipImageName: (ShipKind) -> String
    /// Buttons under the board (Randomize + Battle!, or + Challenge a Friend).
    let actions: Actions
    /// Placement is frozen once a Messages update has been staged.
    var isInteractive: Bool

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

    public init(
        board: Binding<Board>,
        title: String,
        subtitle: String,
        isInteractive: Bool = true,
        shipImageName: @escaping (ShipKind) -> String,
        @ViewBuilder actions: () -> Actions
    ) {
        self._board = board
        self.title = title
        self.subtitle = subtitle
        self.isInteractive = isInteractive
        self.shipImageName = shipImageName
        self.actions = actions()
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

    public var body: some View {
        // One measurement of the real surface. The app's placement screen gets
        // a whole phone; the Messages sheet gets less, and on an SE-class phone
        // the app's 30pt title plus a 64pt shelf would squeeze the board below
        // usable. Everything that can shrink is driven from here, and at full
        // height every number is the app's own.
        GeometryReader { geometry in
            let metrics = PlacementMetrics(size: geometry.size)

            VStack(spacing: metrics.stackSpacing) {
                Text(title)
                    .font(.system(size: metrics.titleSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(TubPalette.deepSea)
                    .shadow(color: .white.opacity(0.9), radius: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if metrics.showsSubtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                        .shadow(color: .white.opacity(0.8), radius: 2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                // The board is sized, not stretched. Left to fill a VStack it
                // took every spare point and pushed the buttons and the shelf
                // off the bottom of the screen.
                boardGrid
                    .frame(width: metrics.boardSide, height: metrics.boardSide)

                actions
                    .padding(.horizontal, 20)
                    .contentColumn()

                // A square board can never be wider than the gutters allow, so
                // on a tall screen there is slack underneath. It goes here, and
                // the shelf settles onto the wood plank the key art draws along
                // the bottom instead of floating in the middle of it.
                Spacer(minLength: 0)

                tray(metrics)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .padding(.vertical, metrics.verticalPadding)
            .disabled(!isInteractive)
        }
    }

    // MARK: - Board

    private var boardGrid: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cellSize = side / CGFloat(Board.size)
            ZStack(alignment: .topLeading) {
                // Water tiles
                ForEach(Coordinate.allBoardCells, id: \.self) { cell in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TubPalette.water.opacity(0.85))
                        .padding(1)
                        .frame(width: cellSize, height: cellSize)
                        .position(center(of: cell, cellSize: cellSize))
                }

                // Drop preview under the ghost
                if let kind = draggingKind,
                   let target = dropTarget(for: kind, cellSize: cellSize) {
                    let valid = boardWithoutLifted.canPlace(kind, at: target.cell, orientation: target.orientation)
                    ForEach(
                        Ship(kind: kind, origin: target.cell, orientation: target.orientation)
                            .cells.filter(\.isValid),
                        id: \.self
                    ) { cell in
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
                    ArtworkImage(
                        name: shipImageName(ship.kind),
                        // preserve the toy's aspect inside its footprint
                        width: cellSize * CGFloat(ship.kind.length) * 0.98,
                        height: cellSize * 1.2
                    )
                    .rotationEffect(ship.orientation == .horizontal ? .zero : .degrees(90))
                    .position(shipCenter(ship, cellSize: cellSize))
                    .opacity(liftedShip?.id == ship.id ? 0.25 : 1)
                    .onTapGesture { rotate(ship) }
                    .gesture(shipDrag(ship, cellSize: cellSize))
                    .accessibilityHidden(true)
                }

                // The ghost ship floating above the finger
                if let kind = draggingKind {
                    ArtworkImage(
                        name: shipImageName(kind),
                        width: cellSize * CGFloat(kind.length),
                        height: cellSize * 1.2
                    )
                    .rotationEffect(dragOrientation == .horizontal ? .zero : .degrees(90))
                    .position(ghostCenter(cellSize: cellSize))
                    .opacity(0.85)
                    .scaleEffect(1.06)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 5)
                    .overlay {
                        // Green vs. red was the only signal that a drop would
                        // take — useless with Differentiate Without Color on,
                        // so badge the ghost with a symbol too.
                        if let target = dropTarget(for: kind, cellSize: cellSize) {
                            let valid = boardWithoutLifted.canPlace(
                                kind, at: target.cell, orientation: target.orientation
                            )
                            Image(systemName: valid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(.system(size: cellSize * 0.62, weight: .black))
                                .foregroundStyle(.white, valid ? Color.green : Color.red)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }
                    }
                    .allowsHitTesting(false)
                }

                // VoiceOver can't drag a ghost ship, so the grid is also a
                // plain tap surface underneath: pick a ship in the shelf, then
                // tap the square to drop it there.
                accessibilityGrid(cellSize: cellSize)
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

    /// An invisible, fully-labeled cell per square. Sighted players never see
    /// it (it sits under the art and takes no hits); VoiceOver walks it.
    private func accessibilityGrid(cellSize: CGFloat) -> some View {
        ForEach(Coordinate.allBoardCells, id: \.self) { cell in
            Color.clear
                .frame(width: cellSize, height: cellSize)
                .position(center(of: cell, cellSize: cellSize))
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel(for: cell))
                .accessibilityHint(
                    board.ship(at: cell) == nil
                        ? String(localized: "Places the next ship here", bundle: .module)
                        : String(localized: "Rotates this ship", bundle: .module)
                )
                .accessibilityAction {
                    if let ship = board.ship(at: cell) {
                        rotate(ship)
                    } else if let kind = trayKinds.first {
                        placeByTap(kind, at: cell)
                    }
                }
        }
    }

    private func accessibilityLabel(for cell: Coordinate) -> String {
        let square = "\(boardColumnLabels[cell.col])\(cell.row + 1)"
        guard let ship = board.ship(at: cell) else {
            return String(localized: "\(square), empty water", bundle: .module)
        }
        return String(localized: "\(square), holds your \(ship.kind.localizedDisplayName)", bundle: .module)
    }

    /// The VoiceOver path onto the board: drop the next shelf ship on this
    /// square, trying both orientations before giving up.
    private func placeByTap(_ kind: ShipKind, at cell: Coordinate) {
        var copy = board
        for orientation in [Orientation.horizontal, .vertical]
        where copy.canPlace(kind, at: cell, orientation: orientation) {
            try? copy.place(kind, at: cell, orientation: orientation)
            board = copy
            TubHaptics.notify(.success)
            return
        }
        TubHaptics.notify(.warning)
    }

    /// Board-local point for a globally-reported drag location.
    private func boardLocal(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - boardFrame.minX, y: global.y - boardFrame.minY)
    }

    private var cellSizeFromFrame: CGFloat? {
        boardFrame.width > 0 ? boardFrame.width / CGFloat(Board.size) : nil
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
        let side = cellSize * CGFloat(Board.size)
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
            TubHaptics.impact(.light)
        } else {
            TubHaptics.notify(.warning)
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
                TubHaptics.impact(.light, intensity: 0.6)
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
                TubHaptics.notify(.success)
            } else if liftedShip != nil {
                // Invalid spot for a board ship: keep its original placement.
                TubHaptics.notify(.warning)
            }
        } else if liftedShip != nil {
            // Dragged clear off the board: back to the shelf.
            board = copy
            TubHaptics.impact(.medium)
        }
    }

    private func shipDrag(_ ship: Ship, cellSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                updateDrag(
                    kind: ship.kind,
                    lifted: ship,
                    location: boardLocal(value.location),
                    cellSize: cellSize
                )
            }
            .onEnded { value in
                dragLocation = boardLocal(value.location)
                finishDrag(kind: ship.kind, cellSize: cellSize)
            }
    }

    private func trayDrag(_ kind: ShipKind) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                updateDrag(
                    kind: kind,
                    lifted: nil,
                    location: boardLocal(value.location),
                    cellSize: cellSizeFromFrame
                )
            }
            .onEnded { value in
                dragLocation = boardLocal(value.location)
                finishDrag(kind: kind, cellSize: cellSizeFromFrame)
            }
    }

    // MARK: - Shelf tray

    private func tray(_ metrics: PlacementMetrics) -> some View {
        HStack(spacing: 10) {
            if trayKinds.isEmpty {
                Text("Fleet ready, Captain! ⚓️", tableName: nil, bundle: .module)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(TubPalette.timber)
                    .shadow(color: .white.opacity(0.4), radius: 1)
            }
            ForEach(trayKinds, id: \.self) { kind in
                trayShip(kind, metrics: metrics)
            }
        }
        .frame(height: metrics.trayHeight)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func trayShip(_ kind: ShipKind, metrics: PlacementMetrics) -> some View {
        ArtworkImage(
            name: shipImageName(kind),
            width: CGFloat(kind.length) * metrics.trayUnit,
            height: metrics.trayShipHeight
        )
        .opacity(draggingKind == kind && liftedShip == nil ? 0.3 : 1)
        // Generous invisible hit area — little toys are hard to pinch.
        .frame(minWidth: HIG.minimumHitTarget, minHeight: metrics.trayHeight - 8)
        .contentShape(Rectangle())
        .gesture(trayDrag(kind))
        .accessibilityLabel(kind.localizedDisplayName)
        .accessibilityHint(String(localized: "Drag onto the board to place", bundle: .module))
    }
}

/// Placement sizing for the surface it actually got.
///
/// At full height every value is the app's own literal, so the app's screen is
/// unchanged; below that the header and shelf give ground before the board
/// does, because the board is the thing you came to use.
public struct PlacementMetrics: Equatable, Sendable {
    public var size: CGSize

    public init(size: CGSize) { self.size = size }

    /// An expanded Messages sheet on an SE-class phone is roughly 430pt tall.
    var isCompact: Bool { size.height < 560 }
    var isVeryCompact: Bool { size.height < 460 }

    var titleSize: CGFloat { isVeryCompact ? 20 : (isCompact ? 24 : 30) }
    var showsSubtitle: Bool { !isVeryCompact }
    var stackSpacing: CGFloat { isCompact ? 6 : 10 }
    var verticalPadding: CGFloat { isCompact ? 6 : 16 }
    var boardGutter: CGFloat { isCompact ? 10 : 14 }
    var trayHeight: CGFloat { isVeryCompact ? 46 : (isCompact ? 56 : 64) }
    var trayShipHeight: CGFloat { isVeryCompact ? 22 : 30 }
    var trayUnit: CGFloat { isVeryCompact ? 14 : 19 }

    /// Height the action row needs — two `.borderedProminent` buttons at
    /// headline size with 6pt of vertical padding.
    private var actionsHeight: CGFloat { 48 }

    /// The square board edge: as wide as the gutters allow, but never wider
    /// than the height left after the header, the buttons and the shelf have
    /// taken theirs.
    var boardSide: CGFloat {
        let rows: CGFloat = showsSubtitle ? 5 : 4
        let chrome = verticalPadding * 2
            + titleSize * 1.3
            + (showsSubtitle ? 20 : 0)
            + actionsHeight
            + trayHeight
            + stackSpacing * (rows - 1)
        let byHeight = size.height - chrome
        let byWidth = size.width - boardGutter * 2
        // Never collapse to nothing on an absurdly short surface — below this
        // the sheet is unusable anyway and the board should still be visible.
        return max(150, min(byWidth, byHeight))
    }
}

#endif
