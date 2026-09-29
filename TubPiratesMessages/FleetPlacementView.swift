import BathtubEngine
import BathtubUI
import SwiftUI

/// Fleet placement in Messages — the app's screen, unchanged.
///
/// The board, the ghost ship that floats above your finger, tap-to-rotate,
/// drag-off-to-shelve and the caddy shelf all come from
/// `BathtubUI.FleetPlacementView`, which is the same view `PlacementView`
/// draws in the app. This file only supplies the two buttons underneath and
/// the fleet of toys the captain has equipped.
struct MessagesFleetPlacementView: View {
    @Bindable var model: MessagesExtensionModel
    let primaryButtonTitle: String
    let primaryButtonSystemImage: String
    let submit: () -> Void

    var body: some View {
        FleetPlacementView(
            board: $model.placementBoard,
            title: String(localized: "Place Your Fleet"),
            subtitle: String(localized: "Drag toys from the shelf • Tap a ship to rotate"),
            isInteractive: !model.isSending,
            shipImageName: model.shipImageName
        ) {
            // The game's own buttons rather than `.borderedProminent`: a
            // system button style follows the OS of the day — on recent
            // releases it renders as translucent glass — and the sheet needs
            // the same solid timber-and-gold it has in the app.
            HStack(spacing: 14) {
                TubPrimaryButton(
                    title: String(localized: "Randomize"),
                    systemImage: "dice.fill",
                    fill: TubPrimaryButton.actionBlue,
                    action: model.randomizePlacement
                )
                .disabled(model.isSending)

                TubPrimaryButton(
                    title: model.isSending
                        ? String(localized: "Sending…")
                        : primaryButtonTitle,
                    systemImage: model.isSending ? "paperplane.fill" : primaryButtonSystemImage,
                    action: submit
                )
                .disabled(!model.isFleetComplete || model.isSending)
            }
        }
    }
}
