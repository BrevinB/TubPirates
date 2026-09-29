// The arena is a UIKit/SpriteKit surface; the package also builds for macOS
// so the engine's tests can run there, where this target has nothing to offer.
#if canImport(UIKit)
import SpriteKit
import BathtubEngine
/// A 10x10 grid of tiles plus a ship-sprite layer. Tiles are laid out in plain grid
/// coordinates in this node's local space; the node itself is rotated 45° so the board
/// reads as a diamond — `convert(_:from:)` keeps the tap math simple.
public final class BoardNode: SKNode {
    /// Base tile size in local units; the whole node is scaled to fit its slot on screen.
    public static let baseTileSize: CGFloat = 40
    /// Diamond diagonal at scale 1 — used by the scene to compute the fit scale.
    public static let baseDiagonal: CGFloat = baseTileSize * 10 * sqrt(2)

    public let tileSize: CGFloat = BoardNode.baseTileSize
    private var tiles: [Coordinate: TileNode] = [:]
    private let shipLayer = SKNode()
    private let previewLayer = SKNode()
    private var shipSprites: [Ship.ID: SKSpriteNode] = [:]

    public override init() {
        super.init()
        zRotation = .pi / 4
        for cell in Coordinate.allBoardCells {
            let tile = TileNode(cell: cell, size: tileSize)
            tile.position = position(of: cell)
            addChild(tile)
            tiles[cell] = tile
        }
        shipLayer.zPosition = 1
        addChild(shipLayer)
        previewLayer.zPosition = 8
        addChild(previewLayer)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("unused") }

    // MARK: - Coordinate mapping (local, un-rotated space)

    public func position(of cell: Coordinate) -> CGPoint {
        CGPoint(
            x: (CGFloat(cell.col) - 4.5) * tileSize,
            y: (4.5 - CGFloat(cell.row)) * tileSize
        )
    }

    /// Cell under a point given in this node's local space, or nil when off-board.
    public func cell(atLocal point: CGPoint) -> Coordinate? {
        let col = Int((point.x / tileSize + 5).rounded(.down))
        let row = Int((5 - point.y / tileSize).rounded(.down))
        let cell = Coordinate(row: row, col: col)
        return cell.isValid ? cell : nil
    }

    public func tile(at cell: Coordinate) -> TileNode? {
        tiles[cell]
    }

    /// Scene-space position of a cell (for effects layered on the scene).
    public func scenePosition(of cell: Coordinate, in scene: SKScene) -> CGPoint {
        convert(position(of: cell), to: scene)
    }

    // MARK: - Tile state sync

    /// Renders the enemy board from the attacker's legal knowledge only.
    ///
    /// `withholding` names cells and ships that a shot is *about* to reveal.
    /// A Messages payload always arrives with the turn already resolved, so
    /// drawing it wholesale would put the ✕ on the square before the cannonball
    /// that earned it had left the barrel. Those are held at their previous
    /// appearance until `playResolution` reveals them.
    public func update(
        enemy view: AttackerView,
        withholding cells: Set<Coordinate> = [],
        withholdingShips ships: Set<Ship.ID> = []
    ) {
        let visibleSunk = view.sunkShips.filter { !ships.contains($0.id) }
        let sunkCells = Set(visibleSunk.flatMap(\.cells)).subtracting(cells)
        for (cell, tile) in tiles {
            if cells.contains(cell) {
                tile.setMark(.none)
            } else if let outcome = view.shotResults[cell] {
                tile.setMark(outcome == .hit ? .hit : .miss)
            } else if sunkCells.contains(cell) {
                tile.setMark(.hit)
            } else if view.revealedShipCells.contains(cell) {
                tile.setMark(.revealedShip)
            } else if view.revealedWaterCells.contains(cell) {
                tile.setMark(.revealedWater)
            } else {
                tile.setMark(.none)
            }
        }
        syncShips(
            sunk: visibleSunk,
            revealed: view.revealedShips.filter { !ships.contains($0.id) }
        )
    }

    /// Renders the player's own board: ships visible, enemy shots marked.
    ///
    /// Withheld ships stay drawn as afloat rather than vanishing — this is your
    /// own fleet, and you can always see it; only the sunk *styling* waits for
    /// the shot to land.
    public func update(
        own board: Board,
        withholding cells: Set<Coordinate> = [],
        withholdingShips ships: Set<Ship.ID> = []
    ) {
        for (cell, tile) in tiles {
            if cells.contains(cell) {
                tile.setMark(.none)
            } else if board.hitCells.contains(cell) {
                tile.setMark(.hit)
            } else if board.shotCells.contains(cell) {
                tile.setMark(.miss)
            } else {
                tile.setMark(.none)
            }
        }
        let sunk = board.sunkShips.filter { !ships.contains($0.id) }
        let sunkIDs = Set(sunk.map(\.id))
        syncShips(
            sunk: sunk,
            revealed: board.ships.filter { !sunkIDs.contains($0.id) },
            revealedAlpha: 1.0
        )
    }

    // MARK: - Ship sprites

    /// Cosmetic fleet skin for the ships this board renders (own board gets
    /// the player's equipped skin; enemy boards stay classic).
    public var fleetSkin: FleetSkin = .classic

    /// Ceiling on ship-sprite resolution. Left open by the app; pinned low by
    /// the Messages extension, whose memory budget the full-size toy art alone
    /// would exhaust.
    public var spriteMaxPixelDimension: CGFloat = .greatestFiniteMagnitude

    /// Reconciles the ship sprite layer. `revealed` ships render at `revealedAlpha`
    /// (ghostly for enemy intel, solid for the player's own fleet); sunk ships render dark.
    private func syncShips(sunk: [Ship], revealed: [Ship], revealedAlpha: CGFloat = 0.55) {
        var wanted: [Ship.ID: (Ship, CGFloat, Bool)] = [:]
        for ship in sunk { wanted[ship.id] = (ship, 0.9, true) }
        for ship in revealed where wanted[ship.id] == nil { wanted[ship.id] = (ship, revealedAlpha, false) }

        for (id, sprite) in shipSprites where wanted[id] == nil {
            sprite.removeFromParent()
            shipSprites[id] = nil
        }

        for (id, (ship, alpha, isSunk)) in wanted {
            let sprite: SKSpriteNode
            if let existing = shipSprites[id] {
                sprite = existing
            } else {
                sprite = makeShipSprite(for: ship)
                shipLayer.addChild(sprite)
                shipSprites[id] = sprite
            }
            sprite.alpha = alpha
            // A light char, not a blackout: the red cells and X marks already
            // say "destroyed", and heavier blends grey out showpiece skins
            // (sunk gold should still gleam).
            sprite.color = .black
            sprite.colorBlendFactor = isSunk ? 0.25 : 0
        }
    }

    private func makeShipSprite(for ship: Ship) -> SKSpriteNode {
        let texture = ArenaTextures.sprite(
            fleetSkin.textureName(for: ship.kind),
            maxDimension: spriteMaxPixelDimension
        )
        let sprite = SKSpriteNode(texture: texture)

        // Fit inside the footprint box (N cells long, ~1.25 cells of breadth)
        // WITHOUT distorting: squat toys sit centered on their cells instead
        // of being stretched to span them.
        let maxLength = CGFloat(ship.kind.length) * tileSize * 0.98
        let maxBreadth = tileSize * 1.25
        let scale = min(maxLength / texture.size().width, maxBreadth / texture.size().height)
        sprite.size = CGSize(
            width: texture.size().width * scale,
            height: texture.size().height * scale
        )

        // Midpoint of first and last occupied cell.
        let first = position(of: ship.cells.first!)
        let last = position(of: ship.cells.last!)
        sprite.position = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        // Art points right (+x). Vertical ships extend downward in rows (-y locally).
        sprite.zRotation = ship.orientation == .horizontal ? 0 : -.pi / 2
        return sprite
    }

    // MARK: - Targeting preview

    public func showPreview(cells: [Coordinate], valid: Bool) {
        previewLayer.removeAllChildren()
        for cell in cells {
            let highlight = SKSpriteNode(
                color: valid
                    ? SKColor(red: 0.3, green: 1, blue: 0.4, alpha: 0.45)
                    : SKColor(red: 1, green: 0.25, blue: 0.2, alpha: 0.45),
                size: CGSize(width: tileSize - 1.5, height: tileSize - 1.5)
            )
            highlight.position = position(of: cell)
            let border = SKShapeNode(rectOf: highlight.size)
            border.strokeColor = valid ? .green : .red
            border.lineWidth = 2
            highlight.addChild(border)
            previewLayer.addChild(highlight)
        }
    }

    public func clearPreview() {
        previewLayer.removeAllChildren()
    }

    // MARK: - Per-cell animation

    /// Applies one cell result with a small pop animation.
    public func animate(result: CellResult) async {
        guard let tile = tiles[result.coordinate] else { return }
        switch result.outcome {
        case .hit: tile.setMark(.hit)
        case .miss: tile.setMark(.miss)
        case .revealedShip: tile.setMark(.revealedShip)
        case .revealedWater: tile.setMark(.revealedWater)
        }
        await tile.pulse()
    }
}
#endif
