import SpriteKit
import BathtubEngine

/// The bathtub arena. Fixed design size; SwiftUI overlays supply the HUD.
final class BattleScene: SKScene, BattleSceneRendering {
    static let designSize = CGSize(width: 768, height: 1024)

    weak var viewModel: MatchViewModel?

    private let enemyBoard = BoardNode(tileSize: 40)
    private let ownBoard = BoardNode(tileSize: 19)

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.13, green: 0.35, blue: 0.55, alpha: 1)
        setupTub()

        enemyBoard.position = CGPoint(x: 384, y: 640)
        addChild(enemyBoard)

        ownBoard.position = CGPoint(x: 384, y: 215)
        addChild(ownBoard)

        refreshBoards()
    }

    private func setupTub() {
        // Placeholder tub: a sudsy ellipse. Replaced by generated art later.
        let tub = SKShapeNode(ellipseOf: CGSize(width: 730, height: 950))
        tub.position = CGPoint(x: 384, y: 490)
        tub.fillColor = SKColor(red: 0.55, green: 0.82, blue: 0.95, alpha: 1)
        tub.strokeColor = SKColor(red: 0.9, green: 0.93, blue: 0.96, alpha: 1)
        tub.lineWidth = 14
        tub.zPosition = -1
        addChild(tub)
    }

    // MARK: - BattleSceneRendering

    func refreshBoards() {
        guard let viewModel else { return }
        enemyBoard.update(enemy: viewModel.enemyView)
        ownBoard.update(own: viewModel.ownBoard)
    }

    func playResolution(_ resolution: MoveResolution, onEnemyBoard: Bool) async {
        let board = onEnemyBoard ? enemyBoard : ownBoard
        for result in resolution.cellResults {
            await board.animate(result: result, ownBoard: !onEnemyBoard)
        }
        // Sunk-ship flourish: shake the board container.
        if !resolution.sunkShips.isEmpty {
            let shake = SKAction.sequence([
                SKAction.moveBy(x: 6, y: 0, duration: 0.05),
                SKAction.moveBy(x: -12, y: 0, duration: 0.08),
                SKAction.moveBy(x: 6, y: 0, duration: 0.05),
            ])
            await board.run(shake)
        }
        refreshBoards()
    }

    // MARK: - Input

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let viewModel else { return }
        let localPoint = touch.location(in: enemyBoard)
        if let cell = enemyBoard.cell(atLocal: localPoint) {
            viewModel.handleTap(at: cell)
        }
    }
}
