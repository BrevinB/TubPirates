import SwiftUI

/// Opaque privacy cover between pass-and-play turns so the incoming captain
/// can't peek at the outgoing captain's fleet.
struct PassDeviceView: View {
    let incomingName: String
    let onReady: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.3, blue: 0.5), Color(red: 0.04, green: 0.15, blue: 0.3)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text("🛁")
                    .font(.system(size: 80))
                Text("Pass the tub!")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Hand the device to \(incomingName).\nNo peeking at the other fleet!")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                Spacer()

                Button(action: onReady) {
                    Label("\(incomingName) is ready!", systemImage: "hand.raised.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: 320)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    PassDeviceView(incomingName: "Captain 2", onReady: {})
}
