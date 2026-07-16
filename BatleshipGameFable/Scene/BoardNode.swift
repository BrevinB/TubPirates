import SpriteKit
import BathtubEngine

/// A 10x10 grid of tiles. Tiles are laid out in plain grid coordinates in this node's
/// local space; the node itself is rotated 45° so the board reads as a diamond —
/// `convert(_:from:)` keeps the tap math simple.
final class BoardNode: SKNode {
    let tileSize: CGFloat
    private var tiles: [Coordinate: TileNode] = [:]

    init(tileSize: CGFloat) {
        self.tileSize = tileSize
        super.init()
        zRotation = .pi / 4
        for cell in Coordinate.allBoardCells {
            let tile = TileNode(cell: cell, size: tileSize)
            tile.position = position(of: cell)
            addChild(tile)
        }
        tiles = Dictionary(uniqueKeysWithValues: children.compactMap { node in
            (node as? TileNode).map { ($0.cell, $0) }
        })
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

    // MARK: - State sync

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
    }

    /// Renders the player's own board: ships visible, enemy shots marked.
    func update(own board: Board) {
        let shipCells = Set(board.ships.flatMap(\.cells))
        for (cell, tile) in tiles {
            if board.hitCells.contains(cell) {
                tile.setMark(.ownShipHit)
            } else if board.shotCells.contains(cell) {
                tile.setMark(.miss)
            } else if shipCells.contains(cell) {
                tile.setMark(.ownShip)
            } else {
                tile.setMark(.none)
            }
        }
    }

    /// Applies one cell result with a small pop animation.
    func animate(result: CellResult, ownBoard: Bool) async {
        guard let tile = tiles[result.coordinate] else { return }
        switch result.outcome {
        case .hit: tile.setMark(ownBoard ? .ownShipHit : .hit)
        case .miss: tile.setMark(.miss)
        case .revealedShip: tile.setMark(.revealedShip)
        case .revealedWater: tile.setMark(.revealedWater)
        }
        await tile.pulse()
    }
}
