import BathtubArena
import BathtubEngine
import BathtubUI
import MessageUI
import SwiftUI

/// Place your fleet, then challenge a friend by message.
///
/// "Challenge by Message" used to hand the composer a `Board.randomlyPlaced`,
/// so the one flow in the app that can win a new player was also the only one
/// that never let you place your own ships — while the friend who received it
/// got the full placement screen. This is the same shared board the app and the
/// Messages sheet both use; only the button underneath differs.
struct MessageChallengePlacementView: View {
    @Binding var path: [Route]

    @State private var board = Board()
    @State private var sendFailed = false

    @Environment(ProfileStore.self) private var profileStore

    private var fleetComplete: Bool {
        board.ships.count == ShipKind.standardFleet.count
    }

    var body: some View {
        ZStack {
            ScreenBackground(imageName: "placement_background")
                .onAppear {
                    guard board.ships.isEmpty else { return }
                    var rng = SystemRandomNumberGenerator()
                    board = .randomlyPlaced(using: &rng)
                }

            FleetPlacementView(
                board: $board,
                title: String(localized: "Place Your Fleet"),
                subtitle: String(localized: "Drag toys from the shelf • Tap a ship to rotate"),
                shipImageName: { profileStore.fleet.textureName(for: $0) }
            ) {
                HStack(spacing: 14) {
                    Button {
                        var rng = SystemRandomNumberGenerator()
                        board = .randomlyPlaced(using: &rng)
                        Haptics.impact(.medium)
                    } label: {
                        Label("Randomize", systemImage: "dice.fill")
                            .font(.headline)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.25, green: 0.5, blue: 0.75))

                    Button(action: challenge) {
                        Label("Challenge!", systemImage: "paperplane.fill")
                            .font(.headline.weight(.bold))
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!fleetComplete)
                }
            }
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Couldn't open Messages", isPresented: $sendFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't send messages. Try again from the Messages app.")
        }
    }

    private func challenge() {
        SoundService.shared.play(.tap)
        guard MessageChallengeComposer.canSend else {
            sendFailed = true
            return
        }
        MessageChallengeComposer.present(
            board: board,
            appearance: SharedAppGroup.Appearance(
                avatarID: profileStore.avatarID,
                fleetID: profileStore.fleet.id
            )
        ) { result in
            switch result {
            case .sent:
                Analytics.messages(.challengeSent(source: "app"))
                path.removeAll()
            case .failed:
                sendFailed = true
            default:
                break
            }
        }
    }
}
