#if DEBUG
import BathtubArena
import BathtubEngine
import BathtubUI
import SwiftUI
import UIKit

/// Renders the shared battle and placement chrome at the exact surface sizes
/// the app and the Messages sheet get on real devices, and writes a PNG per
/// size into the app container.
///
/// The Messages extension cannot be driven in the simulator — the host refuses
/// to deliver a payload to a fake recipient — so device sizing used to be
/// checked by eye on hardware, one phone at a time. Everything the sheet draws
/// now comes from `BathtubUI`, which is an ordinary SwiftUI view that this app
/// can render offscreen at any size. Run with `-layoutProbe`.
@MainActor
enum LayoutProbe {
    /// Surfaces worth checking: the app's full screen on the smallest and
    /// largest phones, and the expanded Messages sheet on the same devices.
    /// The sheet is roughly the screen minus the navigation and input bars.
    struct Surface {
        let name: String
        let size: CGSize
    }

    static let surfaces: [Surface] = [
        // Full-screen app, for the 1-to-1 comparison.
        Surface(name: "app-se", size: CGSize(width: 375, height: 667)),
        Surface(name: "app-15", size: CGSize(width: 393, height: 852)),
        Surface(name: "app-ipad", size: CGSize(width: 834, height: 1112)),
        // Expanded Messages sheets.
        Surface(name: "sheet-se", size: CGSize(width: 375, height: 438)),
        Surface(name: "sheet-15", size: CGSize(width: 393, height: 590)),
        Surface(name: "sheet-max", size: CGSize(width: 430, height: 650)),
        Surface(name: "sheet-ipad", size: CGSize(width: 834, height: 720)),
    ]

    static func runIfRequested() {
        guard CommandLine.arguments.contains("-layoutProbe") else { return }
        let directory = URL.documentsDirectory
        for surface in surfaces {
            write(battle(surface.size), to: directory, named: "battle-\(surface.name)")
            write(battle(surface.size, finished: true), to: directory, named: "over-\(surface.name)")
            write(placement(surface.size), to: directory, named: "placement-\(surface.name)")
        }
        // The same chrome in both appearances. A Messages sheet follows the
        // system appearance whatever the app is set to, so anything that looks
        // right only in light mode is a bug the app itself never shows.
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            write(
                chrome().environment(\.colorScheme, scheme),
                to: directory,
                named: "chrome-\(name)"
            )
            write(
                compactStrip().environment(\.colorScheme, scheme),
                to: directory,
                named: "compact-\(name)"
            )
        }
        verifyWithholding()
        print("LAYOUT_PROBE_DIR \(directory.path)")
    }

    /// Checks that a board asked to withhold a shot really does draw the
    /// square as it was before it.
    ///
    /// The Messages sheet plays a turn that arrives already resolved, so the
    /// board must be drawn pre-shot and let the animation reveal it. Getting
    /// that backwards put the hit marker on the square the instant it was
    /// tapped, before the cannonball had left the barrel. `BoardNode` is
    /// UIKit-only so the package's own macOS tests cannot reach it; this runs
    /// on a simulator, where it can.
    private static func verifyWithholding() {
        var generator = SystemRandomNumberGenerator()
        let board = Board.randomlyPlaced(using: &generator)
        let ship = board.ships[0]
        let hit = ship.cells[0]
        let miss = Coordinate.allBoardCells.first { board.ship(at: $0) == nil }!

        // Fire through the engine so the board reaches its real post-shot
        // state. Player one moves first, and turns alternate, so the filler
        // shot in the middle is what hands the turn back.
        var state = GameState(
            boards: [.one: board, .two: board],
            loadouts: [.one: [.cannon], .two: [.cannon]]
        )
        try? state.apply(Move(player: .one, shot: .cannon, target: hit))
        try? state.apply(Move(player: .two, shot: .cannon, target: miss))
        try? state.apply(Move(player: .one, shot: .cannon, target: miss))
        // Player one's view of player two's board — the two boards share a
        // layout, so `hit` lands on a hull and `miss` on open water.
        let view = state.attackerView(of: .two)
        let node = BoardNode()

        node.update(enemy: view)
        let shownHit = node.tile(at: hit)?.mark
        let shownMiss = node.tile(at: miss)?.mark

        node.update(enemy: view, withholding: [hit, miss])
        let heldHit = node.tile(at: hit)?.mark
        let heldMiss = node.tile(at: miss)?.mark

        // And revealing it again afterwards, the way `refreshBoards` does.
        node.update(enemy: view)
        let restored = node.tile(at: hit)?.mark

        let passed = shownHit == .hit && shownMiss == .miss
            && heldHit == TileNode.Mark.none && heldMiss == TileNode.Mark.none
            && restored == .hit
        print("WITHHOLDING \(passed ? "PASS" : "FAIL") shown=\(shownHit as Any)/\(shownMiss as Any) held=\(heldHit as Any)/\(heldMiss as Any) restored=\(restored as Any)")
    }

    /// The Messages drawer strip, rebuilt from the same pieces the extension
    /// uses, so its dark-mode behaviour can be checked without the host.
    private static func compactStrip() -> some View {
        let size = CGSize(width: 390, height: 230)
        return ZStack {
            ArtworkImage(
                name: "tub_background",
                width: size.width,
                height: size.height,
                contentMode: .fill,
                maxPixelDimension: 1400
            )
            LinearGradient(
                colors: [.white.opacity(0.12), .clear, .black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ArtworkImage(name: "ship_5", width: 66, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tub Pirates")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(TubPalette.deepSea)
                        Text("Your turn — fire!")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(TubPalette.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                TubPrimaryButton(title: "Open Battle", systemImage: "arrow.up.left.and.arrow.down.right") {}
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 420)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Every shared control, on a neutral field.
    private static func chrome() -> some View {
        VStack(spacing: 14) {
            TubPrimaryButton(title: "Open Battle", systemImage: "arrow.up.left.and.arrow.down.right") {}
            TubPrimaryButton(title: "Send Rematch", systemImage: "arrow.clockwise") {}
            TubPrimaryButton(title: "Disabled", systemImage: "scope") {}
                .disabled(true)
            StatusBannerView("Your turn — fire!")
            TubCapsuleButton(title: "Forfeit", systemImage: "flag.fill") {}
            PlayerHUDView(imageName: "portrait_dogbeard", name: "Dogbeard", highlighted: true)
        }
        .padding(20)
        .frame(width: 360)
        .background(TubPalette.arenaBackdrop)
    }

    private static func write(_ view: some View, to directory: URL, named name: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else {
            print("LAYOUT_PROBE_FAIL \(name)")
            return
        }
        try? data.write(to: directory.appending(path: "\(name).png"))
    }

    // MARK: - Scenes

    /// The battle chrome over a flat tub, with one fleet damaged so the bars,
    /// the sunk marks and the arsenal badges are all exercised.
    /// `finished` swaps the live arsenal for the rematch button, which is the
    /// only pairing that actually occurs — firing is a tap on the board, so an
    /// active battle has no button at all.
    private static func battle(_ size: CGSize, finished: Bool = false) -> some View {
        let metrics = BattleHUDMetrics(size: size)
        return ZStack {
            TubPalette.arenaBackdrop
            // Stand-ins for the two boards the arena draws, at the arena's own
            // coordinates, so the probe shows whether a control is sitting on
            // top of a board rather than only whether it fits on screen.
            arenaBoardOutlines(size)
            BattleHUDView(
                rival: .init(imageName: "portrait_dogbeard", name: "Dogbeard", highlighted: true),
                local: .init(imageName: "portrait_player", name: "You", highlighted: false),
                rivalFleet: sampleFleet(hits: [0, 0, 0, 0, 0], sunk: [false, true, false, false, false]),
                localFleet: sampleFleet(hits: [3, 0, 2, 1, 0], sunk: [false, false, false, false, true]),
                metrics: metrics,
                centerWidth: metrics.statusWidth,
                reservesArsenalGap: !finished
            ) {
                StatusBannerView(
                    finished ? "Victory!" : "Yer turn to fire, Captain!",
                    fontSize: metrics.bannerFontSize
                )
            } rivalFooter: {
                TubCapsuleButton(
                    title: "Forfeit",
                    systemImage: "flag.fill",
                    fontSize: metrics.capsuleFontSize
                ) {}
            } arsenal: {
                ArsenalPanelView(
                    slots: sampleSlots,
                    selected: .chainShot,
                    showsOrientation: true,
                    orientation: .horizontal,
                    iconSide: metrics.arsenalIconSide,
                    axis: metrics.arsenalIsVertical ? .vertical : .horizontal,
                    onSelect: { _ in },
                    onToggleOrientation: {}
                )
                .opacity(finished ? 0 : 1)
            } commit: {
                // The only button the battle screen still shows — firing is a
                // tap on the board now.
                if finished {
                    TubPrimaryButton(title: "Send Rematch", systemImage: "arrow.clockwise") {}
                        .frame(maxWidth: 320)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private static func placement(_ size: CGSize) -> some View {
        var generator = SystemRandomNumberGenerator()
        var board = Board.randomlyPlaced(using: &generator)
        // Leave two toys on the shelf so the tray is exercised too.
        for ship in board.ships.prefix(2) { board.removeShip(id: ship.id) }

        return ZStack {
            ArtworkImage(
                name: "placement_background",
                width: size.width,
                height: size.height,
                contentMode: .fill,
                maxPixelDimension: 1400
            )
            FleetPlacementView(
                board: .constant(board),
                title: String(localized: "Place Your Fleet"),
                subtitle: String(localized: "Drag toys from the shelf • Tap a ship to rotate"),
                shipImageName: { FleetSkinNames.classic($0) }
            ) {
                HStack(spacing: 14) {
                    Button {} label: {
                        Label("Randomize", systemImage: "dice.fill")
                            .font(.headline).padding(.vertical, 6).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.25, green: 0.5, blue: 0.75))
                    Button {} label: {
                        Label("Battle!", systemImage: "flag.checkered")
                            .font(.headline.weight(.bold)).padding(.vertical, 6).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The enemy diamond and the player's beached fleet, where `ArenaScene`
    /// puts them.
    private static func arenaBoardOutlines(_ size: CGSize) -> some View {
        let stage = ArenaStageGeometry.stage(in: size)
        let x0 = ArenaStageGeometry.stageOriginX(in: size)
        let enemySide = stage * ArenaStageGeometry.enemyBoardDiagonalFraction / sqrt(2)
        let ownSide = stage * ArenaStageGeometry.ownBoardDiagonalFraction / sqrt(2)
        return ZStack {
            diamond(side: enemySide, tint: .cyan)
                .position(
                    x: x0 + stage / 2,
                    y: size.height * (1 - ArenaStageGeometry.enemyBoardCenterYFraction)
                )
            diamond(side: ownSide, tint: .green)
                .position(
                    x: x0 + stage * ArenaStageGeometry.ownBoardCenterXFraction,
                    y: size.height * (1 - ArenaStageGeometry.ownBoardCenterYFraction)
                )
        }
    }

    private static func diamond(side: CGFloat, tint: Color) -> some View {
        Rectangle()
            .fill(tint.opacity(0.35))
            .overlay(Rectangle().strokeBorder(tint, lineWidth: 2))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(45))
    }

    // MARK: - Sample data

    private static func sampleFleet(hits: [Int], sunk: [Bool]) -> [FleetBarView.ShipStatus] {
        ShipKind.standardFleet
            .sorted { $0.length > $1.length }
            .enumerated()
            .map { index, kind in
                FleetBarView.ShipStatus(
                    id: kind.rawValue,
                    length: kind.length,
                    hitCount: hits[index],
                    isSunk: sunk[index]
                )
            }
    }

    private static var sampleSlots: [ArsenalSlot] {
        [
            ArsenalSlot(shot: .cannon, remaining: nil),
            ArsenalSlot(shot: .parrotScout, remaining: 1),
            ArsenalSlot(shot: .bigShot, remaining: 0, state: .buyable),
            ArsenalSlot(shot: .flare, remaining: 0, state: .locked),
            ArsenalSlot(shot: .chainShot, remaining: 2),
            ArsenalSlot(shot: .fireworks, remaining: 0, state: .spent),
        ]
    }

    private enum FleetSkinNames {
        static func classic(_ kind: ShipKind) -> String {
            switch kind {
            case .galleon: "ship_5"
            case .frigate: "ship_4"
            case .tugboat: "ship_3a"
            case .duckSub: "ship_3b"
            case .dinghy: "ship_2"
            }
        }
    }
}
#endif
