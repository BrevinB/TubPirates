#if canImport(UIKit)
import SwiftUI
import UIKit

/// `Image("icon_cannon")` decodes the asset at its authored size no matter how
/// small the frame is. The arsenal icons are 1024x1024 (4MB each, six of them)
/// and the toy sprites run to 1900px wide, so the battle sheet was holding tens
/// of megabytes of artwork to draw thumbnails — enough to get a Messages
/// extension killed on launch. This decodes to the size actually drawn.
public struct ArtworkImage: View {
    let name: String
    let width: CGFloat
    let height: CGFloat
    var contentMode: ContentMode = .fit
    /// Ceiling on the decoded longest edge. Full-sheet key art sits behind a
    /// gradient and the content, so it does not need true 3x density.
    var maxPixelDimension: CGFloat = .greatestFiniteMagnitude

    public init(
        name: String,
        width: CGFloat,
        height: CGFloat,
        contentMode: ContentMode = .fit,
        maxPixelDimension: CGFloat = .greatestFiniteMagnitude
    ) {
        self.name = name
        self.width = width
        self.height = height
        self.contentMode = contentMode
        self.maxPixelDimension = maxPixelDimension
    }

    public var body: some View {
        Group {
            if let image = ArtworkCache.image(
                name,
                fitting: CGSize(width: width, height: height),
                maxPixelDimension: maxPixelDimension
            ) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
    }
}

@MainActor
public enum ArtworkCache {
    private static var cache: [String: UIImage] = [:]

    /// Display scale is read once — the sheet never moves between screens.
    private static let screenScale: CGFloat = UIScreen.main.scale

    public static func image(
        _ name: String,
        fitting pointSize: CGSize,
        maxPixelDimension: CGFloat = .greatestFiniteMagnitude
    ) -> UIImage? {
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }

        // Round the request up so a handful of nearby sizes share one decode.
        let longestPoints = max(pointSize.width, pointSize.height)
        let bucket = (longestPoints / 16).rounded(.up) * 16
        let key = "\(name)@\(bucket)@\(maxPixelDimension)"
        if let cached = cache[key] { return cached }

        guard let original = UIImage(named: name) else { return nil }
        let source = CGSize(
            width: original.size.width * original.scale,
            height: original.size.height * original.scale
        )
        let longestSource = max(source.width, source.height)
        guard longestSource > 0 else { return nil }

        let targetPixels = min(bucket * screenScale, maxPixelDimension)
        guard targetPixels < longestSource else {
            cache[key] = original
            return original
        }

        let scale = targetPixels / longestSource
        let target = CGSize(
            width: (source.width * scale).rounded(),
            height: (source.height * scale).rounded()
        )
        let prepared = original.preparingThumbnail(of: target) ?? original
        cache[key] = prepared
        return prepared
    }

    public static func purge() { cache.removeAll() }
}
#endif
