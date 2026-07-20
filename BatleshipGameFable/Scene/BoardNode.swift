import SpriteKit
import BathtubEngine

/// A 10x10 grid of tiles plus a ship-sprite layer. Tiles are laid out in plain grid
/// coordinates in this node's local space; the node itself is rotated 45° so the board
/// reads as a diamond — `convert(_:from:)` keeps the tap math simple.
final class BoardNode: SKNode {
    /// Base tile size in local units; the whole node is scaled to fit its slot on screen.
    static let baseTileSize: CGFloat = 40
    /// Diamond diagonal at scale 1 — used by the scene to compute the fit scale.
    static let baseDiagonal: CGFloat = baseTileSize * 10 * sqrt(2)

    let tileSize: CGFloat = BoardNode.baseTileSize
    private var tiles: [Coordinate: TileNode] = [:]
    private let shipLayer = SKNode()
    private let previewLayer = SKNode()
    private var shipSprites: [Ship.ID: SKSpriteNode] = [:]

    override init() {
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
    required init?(coder: NSCoder) { fatalError("unused") }

    // MARK: - Coordinate mapping (local, un-rotated space)

    func position(of cell: Coordinate) -> CGPoint {
        CGPoint(
            x: (CGFloat(cell.col) - 4.5) * tileSize,
            y: (4.5 - CGFloat(cell.row)) * tileSize
        )
    }

    /// Cell under a point given in this node's local space, or nil when off-board.
    func cell(atLocal point: CGPoint) -> Coordinate? {
        let col = Int((point.x / tileSize + 5).rounded(.down))
        let row = Int((5 - point.y / tileSize).rounded(.down))
        let cell = Coordinate(row: row, col: col)
        return cell.isValid ? cell : nil
    }

    func tile(at cell: Coordinate) -> TileNode? {
        tiles[cell]
    }

    /// Scene-space position of a cell (for effects layered on the scene).
    func scenePosition(of cell: Coordinate, in scene: SKScene) -> CGPoint {
        convert(position(of: cell), to: scene)
    }

    // MARK: - Tile state sync

    /// Renders the enemy board from the attacker's legal knowledge only.
    func update(enemy view: AttackerView) {
        let sunkCells = Set(view.sunkShips.flatMap(\.cells))
        for (cell, tile) in tiles {
            if let outcome = view.shotResults[cell] {
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
        syncShips(sunk: view.sunkShips, revealed: view.revealedShips)
    }

    /// Renders the player's own board: ships visible, enemy shots marked.
    func update(own board: Board) {
        for (cell, tile) in tiles {
            if board.hitCells.contains(cell) {
                tile.setMark(.hit)
            } else if board.shotCells.contains(cell) {
                tile.setMark(.miss)
            } else {
                tile.setMark(.none)
            }
        }
        syncShips(
            sunk: board.sunkShips,
            revealed: board.ships.filter { !board.isSunk($0) },
            revealedAlpha: 1.0
        )
    }

    // MARK: - Ship sprites

    /// Cosmetic fleet skin for the ships this board renders (own board gets
    /// the player's equipped skin; enemy boards stay classic).
    var fleetSkin: FleetSkin = .classic

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
            sprite.color = .black
            sprite.colorBlendFactor = isSunk ? 0.6 : 0
        }
    }

    private func makeShipSprite(for ship: Ship) -> SKSpriteNode {
        let texture = SKTexture(imageNamed: fleetSkin.textureName(for: ship.kind))
        let sprite = SKSpriteNode(texture: texture)

        // Span the full footprint so ships honestly read as N cells long;
        // breadth keeps the art's aspect, capped just past one cell.
        let targetLength = CGFloat(ship.kind.length) * tileSize * 0.98
        let naturalBreadth = texture.size().height * (targetLength / texture.size().width)
        sprite.size = CGSize(width: targetLength, height: min(naturalBreadth, tileSize * 1.2))

        // Midpoint of first and last occupied cell.
        let first = position(of: ship.cells.first!)
        let last = position(of: ship.cells.last!)
        sprite.position = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        // Art points right (+x). Vertical ships extend downward in rows (-y locally).
        sprite.zRotation = ship.orientation == .horizontal ? 0 : -.pi / 2
        return sprite
    }

    // MARK: - Targeting preview

    func showPreview(cells: [Coordinate], valid: Bool) {
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

    func clearPreview() {
        previewLayer.removeAllChildren()
    }

    // MARK: - Per-cell animation

    /// Applies one cell result with a small pop animation.
    func animate(result: CellResult) async {
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
