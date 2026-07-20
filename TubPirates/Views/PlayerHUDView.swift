import SwiftUI

/// Portrait name-plate card, like the original's opponent/player frames.
struct PlayerHUDView: View {
    let imageName: String
    let name: String
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(name)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.05))
                .padding(.vertical, 3)
                .frame(width: 74)
                .background(Color(red: 1, green: 0.97, blue: 0.88))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    highlighted ? Color.orange : Color(red: 0.55, green: 0.38, blue: 0.16),
                    lineWidth: highlighted ? 4 : 3
                )
        )
        .shadow(radius: 3, y: 2)
        .animation(.easeInOut(duration: 0.25), value: highlighted)
    }
}

#Preview {
    HStack(spacing: 40) {
        PlayerHUDView(imageName: "portrait_dogbeard", name: "Dogbeard", highlighted: true)
        PlayerHUDView(imageName: "portrait_player", name: "You", highlighted: false)
    }
    .padding()
    .background(Color.blue)
}
