import BathtubEngine
import BathtubUI
import SwiftUI

/// The battle, laid out by the very same view the app's match screen uses.
///
/// `BathtubUI.BattleHUDView` owns the arrangement — rival name-plate and fleet
/// bar top-left with a quit control under them, yours top-right, the parchment
/// banner between, the arsenal bottom-right — so there is no second layout here
/// that could drift from the app's. What this file supplies is only what
/// Messages genuinely does differently: Forfeit instead of Leave, and a rematch
/// button once the battle is over. There is no Fire button — a tap on the board
/// fires and sends the turn, the way the app fires on a tap.
struct BattleScreenView: View {
    let model: MessagesExtensionModel
    let fire: () -> Void
    let forfeit: () -> Void
    let rematch: () -> Void

    /// The flare is the one shot with no square to tap, so — exactly as in the
    /// app's shot panel — arming it asks first and then fires.
    @State private var confirmFlare = false

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleHUDMetrics(size: geometry.size)

            ZStack {
                MessageArenaView(model: model, fire: fire)

                BattleHUDView(
                    rival: .init(
                        imageName: model.rivalAppearance.avatarID,
                        name: model.rivalName,
                        highlighted: model.highlightedSeat == model.localSeat?.opponent
                    ),
                    local: .init(
                        imageName: model.localAppearance.avatarID,
                        name: model.localName,
                        highlighted: model.highlightedSeat == model.localSeat
                    ),
                    rivalFleet: model.attackerView.map(FleetBarView.enemy) ?? [],
                    localFleet: model.ownBoard.map(FleetBarView.own) ?? [],
                    metrics: metrics,
                    centerWidth: metrics.statusWidth,
                    reservesArsenalGap: !model.battleIsFinished
                ) {
                    StatusBannerView(model.statusMessage, fontSize: metrics.bannerFontSize)
                } rivalFooter: {
                    TubCapsuleButton(
                        title: String(localized: "Forfeit"),
                        systemImage: "flag.fill",
                        fontSize: metrics.capsuleFontSize,
                        action: forfeit
                    )
                    .disabled(model.isSending || model.battleIsFinished)
                } arsenal: {
                    arsenal(metrics)
                } commit: {
                    commit
                        .animation(.easeInOut(duration: 0.28), value: model.battleIsFinished)
                }
            }
            .confirmationDialog(
                String(localized: "Fire the Flare Cannon?"),
                isPresented: $confirmFlare,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Fire!")) {
                    model.selectShot(.flare)
                    // `selectShot` refuses a spent cannon, and firing anyway
                    // would loose whichever shot was armed before.
                    guard model.selectedShot == .flare else { return }
                    fire()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text(ShotType.flare.localizedBlurb)
            }
        }
    }

    /// Whether the cannons are yours to use right now.
    private var arsenalIsArmed: Bool {
        model.isLocalTurn && !model.battleIsFinished && !model.isSending
    }

    /// The rail is always mounted and simply stows itself off the edge when it
    /// is not your move.
    ///
    /// It used to be wrapped in an `if`, so every turn tore it out of the view
    /// hierarchy and built it again — which is what made it flit away and back
    /// while you sat watching the battle. The app never removes its shot panel
    /// either; it just stops responding.
    private func arsenal(_ metrics: BattleHUDMetrics) -> some View {
        let vertical = metrics.arsenalIsVertical
        let stow = vertical ? metrics.arsenalRailWidth + 12 : metrics.arsenalIconSide + 24

        return ArsenalPanelView(
            slots: model.arsenalSlots,
            selected: model.selectedShot,
            showsOrientation: model.selectedShot.spec.needsOrientation,
            orientation: model.shotOrientation,
            iconSide: metrics.arsenalIconSide,
            axis: vertical ? .vertical : .horizontal,
            onSelect: { slot in
                guard slot.state == .ready else { return }
                if slot.shot == .flare {
                    confirmFlare = true
                } else {
                    model.selectShot(slot.shot)
                }
            },
            onToggleOrientation: model.rotateShot
        )
        .opacity(arsenalIsArmed ? 1 : 0)
        .offset(
            x: arsenalIsArmed || !vertical ? 0 : stow,
            y: arsenalIsArmed || vertical ? 0 : stow
        )
        .allowsHitTesting(arsenalIsArmed)
        .animation(.easeInOut(duration: 0.28), value: arsenalIsArmed)
    }

    /// The only button left in a battle: once it is over there is nothing to
    /// tap on the board.
    @ViewBuilder
    private var commit: some View {
        if model.battleIsFinished {
            // Just "Send Rematch": the status banner above already says
            // whether you won, and the longer label would not fit the width
            // left beside your fleet on a small sheet.
            TubPrimaryButton(
                title: String(localized: "Send Rematch"),
                systemImage: "arrow.clockwise",
                action: rematch
            )
            .disabled(model.isSending)
            .frame(maxWidth: 320)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}
