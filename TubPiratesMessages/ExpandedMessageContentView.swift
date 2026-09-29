import BathtubEngine
import BathtubUI
import SwiftUI

/// Everything the expanded sheet shows that isn't the battle itself.
struct ExpandedMessageContentView: View {
    @Bindable var model: MessagesExtensionModel
    let startChallenge: () -> Void
    let joinChallenge: () -> Void

    var body: some View {
        switch model.screen {
        case .newChallenge:
            MessagesFleetPlacementView(
                model: model,
                primaryButtonTitle: String(localized: "Challenge!"),
                primaryButtonSystemImage: "paperplane.fill",
                submit: startChallenge
            )
        case .challengeReceived:
            MessagesFleetPlacementView(
                model: model,
                primaryButtonTitle: String(localized: "Battle!"),
                primaryButtonSystemImage: "flag.checkered",
                submit: joinChallenge
            )
        case .waitingForOpponent:
            // The fleet you committed, on the same board you placed it on —
            // read-only until the rival answers.
            waiting
        case .battle:
            // Handled full-bleed by MessagesRootView; never reached here.
            EmptyView()
        case .invalidMessage:
            centered(
                MessageStatusView(
                    title: String(localized: "Unable to open this battle"),
                    systemImage: "exclamationmark.triangle.fill",
                    showsProgress: false
                )
            )
        case .staleMessage:
            centered(
                MessageStatusView(
                    title: String(localized: "Open the newest battle message"),
                    systemImage: "clock.arrow.circlepath",
                    showsProgress: false
                )
            )
        }
    }

    private var waiting: some View {
        FleetPlacementView(
            board: $model.placementBoard,
            title: String(localized: "Fleet Away!"),
            subtitle: String(localized: "Waiting for yer rival to place theirs"),
            isInteractive: false,
            shipImageName: model.shipImageName
        ) {
            MessageStatusView(
                title: String(localized: "Waiting for your rival to place their fleet"),
                systemImage: "hourglass",
                showsProgress: true
            )
        }
    }

    private func centered(_ content: some View) -> some View {
        content
            .padding(.horizontal, 16)
            .contentColumn()
            .frame(maxHeight: .infinity)
    }
}
