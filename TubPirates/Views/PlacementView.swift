import BathtubArena
import BathtubEngine
import BathtubUI
import SwiftUI
import UIKit

/// Pre-battle fleet placement.
///
/// The board, the ghost ship, the shelf and every drag rule live in
/// `BathtubUI.FleetPlacementView` so the Messages extension places a fleet the
/// exact same way. What's left here is the app's own framing: the key-art
/// backdrop, the equipped cosmetic fleet, and where "Battle!" leads.
struct PlacementView: View {
    let config: MatchConfig
    @Binding var path: [Route]

    @State private var board = Board()

    @Environment(ProfileStore.self) private var profileStore

    private var fleetComplete: Bool {
        board.ships.count == ShipKind.standardFleet.count
    }

    var body: some View {
        ZStack {
            ScreenBackground(imageName: "placement_background")
                .onAppear {
                    guard board.ships.isEmpty else { return }
                    #if DEBUG
                    // Debug: pre-place a random fleet for screenshots.
                    if CommandLine.arguments.contains("-randomize") {
                        var rng = SystemRandomNumberGenerator()
                        board = Board.randomlyPlaced(using: &rng)
                        return
                    }
                    #endif
                    if let previous = config.playerBoard {
                        // Rematch: start from last game's layout — one tap to
                        // re-battle, or drag to reposition.
                        board = previous
                    }
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
                        board = Board.randomlyPlaced(using: &rng)
                        Haptics.impact(.medium)
                    } label: {
                        Label("Randomize", systemImage: "dice.fill")
                            .font(.headline)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.25, green: 0.5, blue: 0.75))

                    Button {
                        var battleConfig = config
                        battleConfig.playerBoard = board
                        path.append(.match(battleConfig))
                    } label: {
                        Label("Battle!", systemImage: "flag.checkered")
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
        // Keep the bar transparent over the key art, but NOT hidden: hiding
        // it left this screen with no visible way back — the swipe gesture
        // was the only exit.
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        PlacementView(config: MatchConfig(), path: .constant([]))
    }
}
