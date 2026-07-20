import SpriteKit
import BathtubEngine

/// The bathtub arena. Sized to the hosting view (`resizeFill`) with content laid out
/// proportionally; SwiftUI overlays supply the HUD.
final class BattleScene: SKScene, BattleSceneRendering {
    weak var viewModel: MatchViewModel?

    private let background = SKSpriteNode(texture: SKTexture(imageNamed: "tub_background"))
    private let enemyBoard = BoardNode()
    private let ownBoard = BoardNode()
    private let suds = SKNode()
    private let cannon = SKSpriteNode(texture: SKTexture(imageNamed: "player_cannon"))
    private var didSetUp = false

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.13, green: 0.35, blue: 0.55, alpha: 1)
        if !didSetUp {
            didSetUp = true
            background.zPosition = -10
            addChild(background)
            addChild(enemyBoard)
            suds.zPosition = -1
            addChild(suds)
            addChild(ownBoard)
            cannon.zPosition = 30
            addChild(cannon)
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

        // Enemy board: large diamond kept inside the tub's water circle —
        // sized and lowered toward the circle's center so the tips stay wet.
        enemyBoard.setScale(w * 0.82 / BoardNode.baseDiagonal)
        enemyBoard.position = CGPoint(x: w / 2, y: h * 0.575)

        // Own board: small diamond beached in the suds at the bottom-left,
        // off the tub's water so it reads as "your side of the bathroom".
        ownBoard.setScale(w * 0.34 / BoardNode.baseDiagonal)
        ownBoard.position = CGPoint(x: w * 0.235, y: h * 0.135)
        rebuildSuds(around: ownBoard.position, boardHalfDiagonal: w * 0.17)

        // Your cannon: bottom-center-right, barrel aimed up at the enemy board.
        let cannonAspect = cannon.texture.map { $0.size().width / $0.size().height } ?? 0.7
        let cannonHeight = w * 0.24
        cannon.size = CGSize(width: cannonHeight * cannonAspect, height: cannonHeight)
        cannon.position = CGPoint(x: w * 0.60, y: h * 0.075)
        cannon.zRotation = 0
    }

    /// A cartoon soap-foam blob the player's board sits in.
    private func rebuildSuds(around center: CGPoint, boardHalfDiagonal radius: CGFloat) {
        suds.removeAllChildren()
        var rng = SeededRNG(seed: 7) // stable layout across relayouts
        for _ in 0..<26 {
            let angle = CGFloat(Double.random(in: 0..<(2 * .pi), using: &rng))
            let distance = CGFloat(Double.random(in: 0.35...1.02, using: &rng)) * radius
            let bubbleRadius = CGFloat(Double.random(in: 0.16...0.34, using: &rng)) * radius
            let bubble = SKShapeNode(circleOfRadius: bubbleRadius)
            bubble.fillColor = SKColor(white: 1, alpha: 0.92)
            bubble.strokeColor = SKColor(red: 0.75, green: 0.88, blue: 0.97, alpha: 0.9)
            bubble.lineWidth = 2
            bubble.position = CGPoint(x: center.x + cos(angle) * distance,
                                      y: center.y + sin(angle) * distance * 0.8)
            suds.addChild(bubble)
        }
        // Filled core under the board itself.
        let core = SKShapeNode(circleOfRadius: radius * 0.95)
        core.fillColor = SKColor(white: 1, alpha: 0.92)
        core.strokeColor = .clear
        core.position = center
        suds.addChild(core)
    }

    /// Muzzle tip in scene coordinates for the cannon's current rotation.
    private var cannonMuzzle: CGPoint {
        let barrel = cannon.size.height * 0.5
        return CGPoint(
            x: cannon.position.x - sin(cannon.zRotation) * barrel,
            y: cannon.position.y + cos(cannon.zRotation) * barrel
        )
    }

    /// Swings the barrel toward a target, fires with recoil + smoke, and
    /// returns the muzzle point the projectile should launch from.
    private func fireCannon(at target: CGPoint) async -> CGPoint {
        // Art points up: rotation 0 = straight up.
        let dx = target.x - cannon.position.x
        let dy = target.y - cannon.position.y
        let aim = atan2(dy, dx) - .pi / 2
        await cannon.run(.rotate(toAngle: aim, duration: 0.15, shortestUnitArc: true))

        let smoke = ParticleFactory.smoke()
        smoke.numParticlesToEmit = 8
        smoke.particleLifetime = 0.5
        smoke.position = cannonMuzzle
        addChild(smoke)

        // Fire-and-forget recoil (completion form selects the sync SKNode.run,
        // so the cannonball launches while the carriage is still kicking back).
        let recoil = CGVector(dx: sin(aim) * 10, dy: -cos(aim) * 10)
        cannon.run(.sequence([
            .move(by: recoil, duration: 0.05),
            .move(by: CGVector(dx: -recoil.dx, dy: -recoil.dy), duration: 0.12),
        ]), completion: {})
        return cannonMuzzle
    }

    /// Rests the barrel back to straight up after the volley.
    private func restCannon() {
        cannon.run(.rotate(toAngle: 0, duration: 0.25, shortestUnitArc: true))
    }

    // MARK: - BattleSceneRendering

    func refreshBoards() {
        guard let viewModel else { return }
        ownBoard.fleetSkin = FleetSkin.withID(viewModel.playerFleetID)
        enemyBoard.fleetSkin = FleetSkin.withID(viewModel.enemyFleetID)
        enemyBoard.update(enemy: viewModel.enemyView)
        ownBoard.update(own: viewModel.ownBoard)
    }

    func playResolution(_ resolution: MoveResolution, onEnemyBoard: Bool) async {
        let board = onEnemyBoard ? enemyBoard : ownBoard
        // Dogbeard fires from off-screen above; the player's shots come from the cannon.
        let dogbeardLaunch = CGPoint(x: size.width / 2, y: size.height * 1.02)

        switch resolution.move.shot.spec.effect {
        case .damage:
            for result in resolution.cellResults {
                let target = board.scenePosition(of: result.coordinate, in: self)
                let launch = onEnemyBoard ? await fireCannon(at: target) : dogbeardLaunch
                await ShotAnimator.cannonball(from: launch, to: target, in: self, outcome: result.outcome)
                await board.animate(result: result)
            }
            if onEnemyBoard { restCannon() }
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
                let target = board.scenePosition(of: mid, in: self)
                let launch = onEnemyBoard ? await fireCannon(at: target) : dogbeardLaunch
                await ShotAnimator.flare(from: launch, to: target, in: self)
                if onEnemyBoard { restCannon() }
            }
            for result in resolution.cellResults {
                await board.animate(result: result)
            }
        }

        if !resolution.sunkShips.isEmpty {
            SoundService.shared.play(.sunk)
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
