// The arena is a UIKit/SpriteKit surface; the package also builds for macOS
// so the engine's tests can run there, where this target has nothing to offer.
#if canImport(UIKit)
import SpriteKit
import UIKit

/// The tub art is authored at 1792x2400 — about 17MB once decompressed. The app
/// can afford that; a Messages extension cannot, and the sheet was being killed
/// on launch. Backdrops are downsampled to the surface that will show them,
/// under a host-set ceiling, and cached.
@MainActor
public enum ArenaTextures {
    private static var cache: [String: SKTexture] = [:]

    /// Aspect-fill texture for `name`.
    ///
    /// - Parameters:
    ///   - pixelSize: the surface being covered, in pixels.
    ///   - maxDimension: hard ceiling on the longest edge. A backdrop is soft
    ///     art behind the boards, so a host that is tight on memory can cap it
    ///     well below the screen's true pixel density with no visible cost.
    public static func backdrop(
        _ name: String,
        covering pixelSize: CGSize,
        maxDimension: CGFloat = .greatestFiniteMagnitude
    ) -> SKTexture? {
        guard pixelSize.width > 0, pixelSize.height > 0,
              let image = UIImage(named: name) else { return nil }

        let source = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        guard source.width > 0, source.height > 0 else { return nil }

        // Smallest scale that still covers the surface, never upscaling past
        // the source, then pulled down further by the host's ceiling.
        var scale = min(max(pixelSize.width / source.width, pixelSize.height / source.height), 1)
        let longestEdge = max(source.width, source.height) * scale
        if longestEdge > maxDimension {
            scale *= maxDimension / longestEdge
        }

        // Round up to a stable step so small resizes reuse the cached texture
        // instead of re-decoding the art.
        let step = min((scale * 8).rounded(.up) / 8, 1)
        let key = "\(name)@\(step)"
        if let cached = cache[key] { return cached }

        let texture: SKTexture
        if step >= 1 {
            texture = SKTexture(image: image)
        } else {
            let target = CGSize(
                width: (source.width * step).rounded(),
                height: (source.height * step).rounded()
            )
            if let thumbnail = image.preparingThumbnail(of: target) {
                texture = SKTexture(image: thumbnail)
            } else {
                texture = SKTexture(image: image)
            }
        }
        cache[key] = texture
        return texture
    }

    /// Ship and prop art, capped on the longest edge.
    ///
    /// The toy sprites are authored around 1300-1900px wide but never drawn
    /// larger than a few hundred points, so an uncapped host pays 15MB for the
    /// five-ship fleet it draws at thumbnail size.
    public static func sprite(
        _ name: String,
        maxDimension: CGFloat = .greatestFiniteMagnitude
    ) -> SKTexture {
        guard maxDimension < .greatestFiniteMagnitude,
              let image = UIImage(named: name) else {
            return SKTexture(imageNamed: name)
        }
        let source = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longestEdge = max(source.width, source.height)
        guard longestEdge > maxDimension, longestEdge > 0 else {
            return SKTexture(imageNamed: name)
        }

        let step = min(((maxDimension / longestEdge) * 8).rounded(.up) / 8, 1)
        let key = "sprite:\(name)@\(step)"
        if let cached = cache[key] { return cached }

        let target = CGSize(
            width: (source.width * step).rounded(),
            height: (source.height * step).rounded()
        )
        let texture = image.preparingThumbnail(of: target).map(SKTexture.init(image:))
            ?? SKTexture(imageNamed: name)
        cache[key] = texture
        return texture
    }

    /// Frees cached art. The Messages host calls this when the sheet closes.
    public static func purge() {
        cache.removeAll()
    }
}
#endif
