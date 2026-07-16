import SwiftUI

struct MainMenuView: View {
    @Binding var path: [Route]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.35, blue: 0.6), Color(red: 0.05, green: 0.2, blue: 0.4)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                VStack(spacing: 8) {
                    Text("🛁🏴‍☠️")
                        .font(.system(size: 72))
                    Text("Bathtub Battles")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Dogbeard awaits...")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        path.append(.match(MatchConfig(mode: .ai)))
                    } label: {
                        Label("Battle Dogbeard!", systemImage: "flag.checkered")
                            .font(.title2.weight(.bold))
                            .frame(maxWidth: 320)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                Spacer()
            }
            .padding()
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        MainMenuView(path: .constant([]))
    }
}
