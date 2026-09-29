import BathtubUI
import SwiftUI

// `contentColumn`, `hitTarget` and `decorativeMotion` moved to BathtubUI so
// the Messages extension lays out on the same rules; import brings them in.

/// Full-bleed key-art backdrop used by menu-adjacent screens.
struct ScreenBackground: View {
    let imageName: String

    var body: some View {
        GeometryReader { geo in
            ArtworkImage(
                name: imageName,
                width: geo.size.width,
                height: geo.size.height,
                contentMode: .fill,
                // Key art sits behind a gradient and the content; true 3x
                // density on a 1536x2752 source is megabytes for nothing.
                maxPixelDimension: 1600
            )
            .clipped()
        }
        .ignoresSafeArea()
    }
}
