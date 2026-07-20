import SpriteKit
import BathtubEngine

/// One grid tile. Ship hulls are drawn by the board's sprite layer;
/// tiles carry the water color and shot/intel marks.
final class TileNode: SKSpriteNode {
    enum Mark: Equatable {
        case none
        case miss
        case hit
        case revealedShip
        case revealedWater
    }

    /// Alternating translucent water tints — checkered like the placement
    /// grid, and see-through enough that the tub art breathes underneath.
    static func waterColor(for cell: Coordinate) -> SKColor {
        (cell.row + cell.col).isMultiple(of: 2)
            ? SKColor(red: 0.45, green: 0.74, blue: 0.94, alpha: 0.62)
            : SKColor(red: 0.55, green: 0.8, blue: 0.96, alpha: 0.48)
    }

    private var waterColor: SKColor { Self.waterColor(for: cell) }

    let cell: Coordinate
    private(set) var mark: Mark = .none
    private var markNode: SKNode?

    init(cell: Coordinate, size: CGFloat) {
        self.cell = cell
        super.init(texture: nil, color: .clear, size: CGSize(width: size - 1.5, height: size - 1.5))
        color = waterColor
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
            color = waterColor
        case .miss:
            color = SKColor(red: 0.78, green: 0.89, blue: 0.98, alpha: 0.9)
            addSplashRing()
        case .hit:
            color = SKColor(red: 0.88, green: 0.22, blue: 0.15, alpha: 1)
            addMarkLabel("✕", color: SKColor(white: 0.1, alpha: 1))
        case .revealedShip:
            color = SKColor(red: 0.98, green: 0.82, blue: 0.3, alpha: 0.95)
        case .revealedWater:
            color = SKColor(red: 0.62, green: 0.87, blue: 0.99, alpha: 0.9)
        }
    }

    /// Miss mark: a splash ripple — ring + droplet dot — far more legible
    /// than the old faint dot, without competing with the red hit X.
    private func addSplashRing() {
        let container = SKNode()
        let ring = SKShapeNode(circleOfRadius: size.width * 0.26)
        ring.strokeColor = SKColor(white: 1, alpha: 0.95)
        ring.lineWidth = size.width * 0.09
        ring.fillColor = .clear
        container.addChild(ring)
        let drop = SKShapeNode(circleOfRadius: size.width * 0.07)
        drop.fillColor = SKColor(white: 1, alpha: 0.95)
        drop.strokeColor = .clear
        container.addChild(drop)
        container.zPosition = 5
        addChild(container)
        markNode = container
    }

    private func addMarkLabel(_ text: String, color: SKColor, scale: CGFloat = 1.0) {
        let label = SKLabelNode(text: text)
        label.fontName = "Helvetica-Bold"
        label.fontSize = size.height * 0.7 * scale
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        // Counter-rotate so the mark reads upright inside the 45°-rotated board,
        // and float above the ship sprite layer.
        label.zRotation = -.pi / 4
        label.zPosition = 5
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
