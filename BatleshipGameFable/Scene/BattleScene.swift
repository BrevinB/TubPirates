import SpriteKit
import BathtubEngine

/// The bathtub arena. Sized to the hosting view (`resizeFill`) with content laid out
/// proportionally; SwiftUI overlays supply the HUD.
final class BattleScene: SKScene, BattleSceneRendering {
    weak var viewModel: MatchViewModel?

    private let background = SKSpriteNode(texture: SKTexture(imageNamed: "tub_background"))
    private let enemyBoard = BoardNode()
    private let ownBoard = BoardNode()
    private var didSetUp = false

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.13, green: 0.35, blue: 0.55, alpha: 1)
        if !didSetUp {
            didSetUp = true
            background.zPosition = -10
            addChild(background)
            addChild(enemyBoard)
            addChild(ownBoard)
        }
        layout()
        refreshBoards()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetUp else { return }
        layout()
    }

    private func layout() {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }

        // Tub art fills the scene (crops as needed).
        if let texture = background.texture {
            let scale = max(w / texture.size().width, h / texture.size().height)
            background.size = CGSize(width: texture.size().width * scale, height: texture.size().height * scale)
        }
        background.position = CGPoint(x: w / 2, y: h / 2)

        // Enemy board: large diamond in the upper water.
        enemyBoard.setScale(w * 0.98 / BoardNode.baseDiagonal)
        enemyBoard.position = CGPoint(x: w / 2, y: h * 0.615)

        // Own board: small diamond at the bottom of the tub, nudged left of the shot panel.
        ownBoard.setScale(w * 0.40 / BoardNode.baseDiagonal)
        ownBoard.position = CGPoint(x: w * 0.42, y: h * 0.175)
    }

    // MARK: - BattleSceneRendering

    func refreshBoards() {
        guard let viewModel else { return }
        enemyBoard.update(enemy: viewModel.enemyView)
        ownBoard.update(own: viewModel.ownBoard)
    }

    func playResolution(_ resolution: MoveResolution, onEnemyBoard: Bool) async {
        let board = onEnemyBoard ? enemyBoard : ownBoard
        let launchPoint = onEnemyBoard
            ? CGPoint(x: size.width / 2, y: size.height * 0.04)   // player fires from the bottom
            : CGPoint(x: size.width / 2, y: size.height * 1.02)   // Dogbeard fires from above

        switch resolution.move.shot.spec.effect {
        case .damage:
            for result in resolution.cellResults {
                let target = board.scenePosition(of: result.coordinate, in: self)
                await ShotAnimator.cannonball(from: launchPoint, to: target, in: self, outcome: result.outcome)
                await board.animate(result: result)
            }
        case .revealArea:
            if let center = resolution.move.target {
                await ShotAnimator.parrot(over: board.scenePosition(of: center, in: self), in: self)
            }
            for result in resolution.cellResults {
                await board.animate(result: result)
            }
        case .revealShip:
            if let ship = resolution.revealedShip {
                let mid = ship.cells[ship.cells.count / 2]
                await ShotAnimator.flare(from: launchPoint, to: board.scenePosition(of: mid, in: self), in: self)
            }
            for result in resolution.cellResults {
                await board.animate(result: result)
            }
        }

        if !resolution.sunkShips.isEmpty {
            for ship in resolution.sunkShips {
                let mid = ship.cells[ship.cells.count / 2]
                let smoke = ParticleFactory.smoke()
                smoke.numParticlesToEmit = 30
                smoke.position = board.scenePosition(of: mid, in: self)
                addChild(smoke)
            }
            let shake = SKAction.sequence([
                SKAction.moveBy(x: 7, y: 0, duration: 0.05),
                SKAction.moveBy(x: -14, y: 0, duration: 0.08),
                SKAction.moveBy(x: 7, y: 0, duration: 0.05),
            ])
            await board.run(shake)
        }
        refreshBoards()
    }

    // MARK: - Input (targeting with drag preview)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePreview(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePreview(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        enemyBoard.clearPreview()
        guard let viewModel, let touch = touches.first else { return }
        if let cell = enemyBoard.cell(atLocal: touch.location(in: enemyBoard)) {
            viewModel.handleTap(at: cell)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        enemyBoard.clearPreview()
    }

    private func updatePreview(_ touches: Set<UITouch>) {
        guard let viewModel, let touch = touches.first,
              viewModel.turnState == .playerTargeting,
              viewModel.selectedShot.spec.needsTarget
        else {
            enemyBoard.clearPreview()
            return
        }
        guard let cell = enemyBoard.cell(atLocal: touch.location(in: enemyBoard)) else {
            enemyBoard.clearPreview()
            return
        }
        enemyBoard.showPreview(
            cells: viewModel.previewFootprint(at: cell),
            valid: viewModel.isValidTarget(cell)
        )
    }
}
