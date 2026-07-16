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

    static let waterColor = SKColor(red: 0.42, green: 0.72, blue: 0.93, alpha: 0.85)

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
            color = SKColor(red: 0.85, green: 0.93, blue: 1, alpha: 0.95)
            addMarkLabel("•", color: .white, scale: 1.4)
        case .hit:
            color = SKColor(red: 0.88, green: 0.22, blue: 0.15, alpha: 1)
            addMarkLabel("✕", color: SKColor(white: 0.1, alpha: 1))
        case .revealedShip:
            color = SKColor(red: 0.98, green: 0.82, blue: 0.3, alpha: 0.95)
        case .revealedWater:
            color = SKColor(red: 0.62, green: 0.87, blue: 0.99, alpha: 0.9)
        }
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
