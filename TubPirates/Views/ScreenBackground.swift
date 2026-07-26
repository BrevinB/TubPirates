import SwiftUI

extension View {
    /// Caps a content column at a readable width and centers it — cards on
    /// iPad stretched into full-width planks without this.
    func contentColumn(_ maxWidth: CGFloat = 600) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

/// Full-bleed key-art backdrop used by menu-adjacent screens.
struct ScreenBackground: View {
    let imageName: String

    var body: some View {
        GeometryReader { geo in
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}
