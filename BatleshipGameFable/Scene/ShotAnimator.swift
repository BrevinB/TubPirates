import SpriteKit
import BathtubEngine

/// Cannonballs, flares, and the scout parrot — effects that fly across the scene
/// and gate the turn machine until they land.
@MainActor
enum ShotAnimator {
    /// Lobs a cannonball along an arc and finishes with the impact effect.
    static func cannonball(
        from start: CGPoint,
        to target: CGPoint,
        in scene: SKScene,
        outcome: CellOutcome
    ) async {
        let ball = SKShapeNode(circleOfRadius: 9)
        ball.fillColor = SKColor(white: 0.12, alpha: 1)
        ball.strokeColor = SKColor(white: 0.35, alpha: 1)
        ball.lineWidth = 2
        ball.position = start
        ball.zPosition = 60
        scene.addChild(ball)

        let path = CGMutablePath()
        path.move(to: start)
        let mid = CGPoint(x: (start.x + target.x) / 2, y: max(start.y, target.y) + 170)
        path.addQuadCurve(to: target, control: mid)

        let flight = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 0.55)
        flight.timingMode = .easeIn
        let heightIllusion = SKAction.sequence([
            SKAction.scale(to: 1.5, duration: 0.27),
            SKAction.scale(to: 0.8, duration: 0.28),
        ])
        await ball.run(.group([flight, heightIllusion]))
        ball.removeFromParent()

        let effect = outcome == .hit ? ParticleFactory.explosion() : ParticleFactory.splash()
        effect.position = target
        scene.addChild(effect)
        if outcome == .hit {
            let smoke = ParticleFactory.smoke()
            smoke.position = target
            scene.addChild(smoke)
        }
    }

    /// Flare: a glowing shell rockets up and bursts above the target ship.
    static func flare(from start: CGPoint, to target: CGPoint, in scene: SKScene) async {
        let shell = SKSpriteNode(texture: ParticleFactory.softDot)
        shell.color = SKColor(red: 1, green: 0.45, blue: 0.2, alpha: 1)
        shell.colorBlendFactor = 1
        shell.size = CGSize(width: 26, height: 26)
        shell.position = start
        shell.zPosition = 60
        shell.blendMode = .add
        scene.addChild(shell)

        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: target, control: CGPoint(x: (start.x + target.x) / 2, y: max(start.y, target.y) + 260))
        let flight = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 0.8)
        flight.timingMode = .easeOut
        await shell.run(flight)
        shell.removeFromParent()

        let burst = ParticleFactory.sparkle()
        burst.numParticlesToEmit = 40
        burst.particleSpeed = 120
        burst.position = target
        burst.particleColor = SKColor(red: 1, green: 0.55, blue: 0.25, alpha: 1)
        scene.addChild(burst)
        try? await Task.sleep(for: .milliseconds(350))
    }

    /// Parrot scout: flies across the scouted area.
    static func parrot(over target: CGPoint, in scene: SKScene) async {
        let parrot = SKSpriteNode(texture: SKTexture(imageNamed: "parrot_scout"))
        let aspect = parrot.texture.map { $0.size().width / $0.size().height } ?? 1
        parrot.size = CGSize(width: 90 * aspect, height: 90)
        parrot.position = CGPoint(x: -80, y: target.y + 50)
        parrot.zPosition = 70
        scene.addChild(parrot)

        let swoop = CGMutablePath()
        swoop.move(to: parrot.position)
        swoop.addQuadCurve(
            to: CGPoint(x: scene.size.width + 90, y: target.y + 70),
            control: CGPoint(x: target.x, y: target.y - 40)
        )
        let flight = SKAction.follow(swoop, asOffset: false, orientToPath: false, duration: 1.3)
        flight.timingMode = .easeInEaseOut

        let sparkleDrop = SKAction.sequence([
            SKAction.wait(forDuration: 0.55),
            SKAction.run {
                let sparkle = ParticleFactory.sparkle()
                sparkle.numParticlesToEmit = 30
                sparkle.position = target
                scene.addChild(sparkle)
            },
        ])
        await parrot.run(.group([flight, sparkleDrop]))
        parrot.removeFromParent()
    }
}
