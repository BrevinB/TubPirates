import SpriteKit
import UIKit

/// Programmatic one-shot particle emitters — no .sks files, textures generated at runtime.
enum ParticleFactory {
    /// Soft radial-gradient dot shared by all emitters.
    static let softDot: SKTexture = {
        let size = CGSize(width: 64, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                endCenter: CGPoint(x: 32, y: 32), endRadius: 32,
                options: []
            )
        }
        return SKTexture(image: image)
    }()

    /// White water droplets for a miss.
    static func splash() -> SKEmitterNode {
        let e = base(count: 22, lifetime: 0.6)
        e.particleBirthRate = 220
        e.particleSpeed = 130
        e.particleSpeedRange = 70
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = .pi * 0.9
        e.yAcceleration = -350
        e.particleScale = 0.16
        e.particleScaleRange = 0.10
        e.particleColor = SKColor(red: 0.92, green: 0.97, blue: 1, alpha: 1)
        return e
    }

    /// Orange/yellow burst for a hit.
    static func explosion() -> SKEmitterNode {
        let e = base(count: 30, lifetime: 0.5)
        e.particleBirthRate = 400
        e.particleSpeed = 170
        e.particleSpeedRange = 90
        e.emissionAngleRange = .pi * 2
        e.particleScale = 0.24
        e.particleScaleRange = 0.12
        e.particleScaleSpeed = -0.35
        e.particleColor = SKColor(red: 1, green: 0.62, blue: 0.15, alpha: 1)
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        return e
    }

    /// Slow gray plume for a sunk ship.
    static func smoke() -> SKEmitterNode {
        let e = base(count: 18, lifetime: 1.4)
        e.particleBirthRate = 40
        e.particleSpeed = 45
        e.particleSpeedRange = 20
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = .pi / 5
        e.particleScale = 0.5
        e.particleScaleSpeed = 0.5
        e.particleAlpha = 0.55
        e.particleAlphaSpeed = -0.4
        e.particleColor = SKColor(white: 0.45, alpha: 1)
        return e
    }

    /// Golden sparkle for reveals (scout/flare intel).
    static func sparkle() -> SKEmitterNode {
        let e = base(count: 14, lifetime: 0.55)
        e.particleBirthRate = 180
        e.particleSpeed = 55
        e.particleSpeedRange = 30
        e.emissionAngleRange = .pi * 2
        e.particleScale = 0.14
        e.particleScaleRange = 0.08
        e.particleColor = SKColor(red: 1, green: 0.88, blue: 0.35, alpha: 1)
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        return e
    }

    private static func base(count: Int, lifetime: CGFloat) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = softDot
        e.numParticlesToEmit = count
        e.particleLifetime = lifetime
        e.particleLifetimeRange = lifetime * 0.4
        e.particleAlphaSpeed = -1 / lifetime
        e.particleColorBlendFactor = 1
        e.zPosition = 50
        // Self-cleanup once every particle has expired.
        e.run(.sequence([.wait(forDuration: Double(lifetime) * 2 + 0.5), .removeFromParent()]))
        return e
    }
}
