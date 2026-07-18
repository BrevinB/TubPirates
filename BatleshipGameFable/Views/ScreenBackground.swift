import SwiftUI

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
