import SpriteKit
import BathtubEngine

/// One grid tile. Placeholder vector look for now — real textures arrive with the art pass.
final class TileNode: SKSpriteNode {
    enum Mark {
        case none
        case miss
        case hit
        case revealedShip
        case revealedWater
        case ownShip
        case ownShipHit
    }

    static let waterColor = SKColor(red: 0.45, green: 0.75, blue: 0.95, alpha: 1)
    static let shipColor = SKColor(red: 0.55, green: 0.38, blue: 0.23, alpha: 1)

    let cell: Coordinate
    private(set) var mark: Mark = .none
    private var markNode: SKNode?

    init(cell: Coordinate, size: CGFloat) {
        self.cell = cell
        super.init(texture: nil, color: Self.waterColor, size: CGSize(width: size - 1.5, height: size - 1.5))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }

    func setMark(_ newMark: Mark) {
        guard newMark != mark || markNode == nil else { return }
        mark = newMark
        markNode?.removeFromParent()
        markNode = nil

        switch newMark {
        case .none:
            color = Self.waterColor
        case .miss:
            color = SKColor(red: 0.85, green: 0.93, blue: 1, alpha: 1)
            addMarkLabel("•", color: .white, scale: 1.4)
        case .hit:
            color = SKColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 1)
            addMarkLabel("✕", color: .black)
        case .revealedShip:
            color = SKColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1)
        case .revealedWater:
            color = SKColor(red: 0.6, green: 0.85, blue: 0.98, alpha: 1)
        case .ownShip:
            color = Self.shipColor
        case .ownShipHit:
            color = SKColor(red: 0.6, green: 0.15, blue: 0.1, alpha: 1)
            addMarkLabel("✕", color: .black)
        }
    }

    private func addMarkLabel(_ text: String, color: SKColor, scale: CGFloat = 1.0) {
        let label = SKLabelNode(text: text)
        label.fontName = "Helvetica-Bold"
        label.fontSize = size.height * 0.7 * scale
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        // Counter-rotate so the mark reads upright inside the 45°-rotated board.
        label.zRotation = -.pi / 4
        addChild(label)
        markNode = label
    }

    /// Brief pop used when a shot lands on this tile.
    func pulse() async {
        let pop = SKAction.sequence([
            SKAction.scale(to: 1.35, duration: 0.12),
            SKAction.scale(to: 1.0, duration: 0.15),
        ])
        await run(pop)
    }
}

extension SKNode {
    /// Async wrapper so SKAction animations can gate the turn state machine.
    func run(_ action: SKAction) async {
        await withCheckedContinuation { continuation in
            run(action) { continuation.resume() }
        }
    }
}
