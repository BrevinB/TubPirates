import BathtubEngine
import BathtubUI
import SwiftUI

/// Vertical arsenal panel on the right edge of the match screen —
/// mirrors the original game's cannon list with tooltips.
struct ShotPanelView: View {
    @Bindable var viewModel: MatchViewModel
    @Environment(ProfileStore.self) private var profileStore
    @State private var tooltipShot: ShotType?
    @State private var confirmFlare = false
    @State private var pendingPurchase: ShotType?
    @State private var showShop = false
    /// The shot the captain was trying to buy when they ran short — the
    /// purchase prompt comes back on its own if the merchant fills the purse.
    @State private var shopReturnShot: ShotType?

    /// Shared lookup for other views (end-screen unlock banners). The map
    /// itself lives in BathtubUI so the Messages arsenal shows the same art.
    static func iconName(for shot: ShotType) -> String { shot.iconName }

    var body: some View {
        ArsenalPanelView(
            slots: slots,
            selected: viewModel.selectedShot,
            showsOrientation: viewModel.selectedShot.spec.needsOrientation,
            orientation: viewModel.selectedOrientation,
            onSelect: handleTap,
            onToggleOrientation: viewModel.toggleOrientation,
            onLongPress: { shot in tooltipShot = tooltipShot == shot ? nil : shot }
        ) {
            if let tooltipShot {
                ArsenalTooltipView(shot: tooltipShot, onTap: { self.tooltipShot = nil }) {
                    if !profileStore.isShotInStock(tooltipShot),
                       let requirement = profileStore.armoryRequirement(for: tooltipShot) {
                        Label(
                            "Defeat \(requirement.localizedName) ×\(requirement.winsToAdvance) to unlock",
                            systemImage: "lock.fill"
                        )
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        // Was (0.7, 0.4, 0.1) — 4.0:1 on parchment, under the
                        // 4.5:1 floor for this size.
                        .foregroundStyle(Color(red: 0.6, green: 0.33, blue: 0.06))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: tooltipShot)
        .confirmationDialog(
            "Fire the Flare Cannon?",
            isPresented: $confirmFlare,
            titleVisibility: .visible
        ) {
            Button("Fire!") { viewModel.fireFlare() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ShotType.flare.localizedBlurb)
        }
        .confirmationDialog(
            pendingPurchase.map { String(localized: "Buy \($0.localizedDisplayName) for \($0.spec.coinCost) doubloons?") } ?? "",
            isPresented: Binding(
                get: { pendingPurchase != nil },
                set: { if !$0 { pendingPurchase = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let shot = pendingPurchase {
                if profileStore.coins >= shot.spec.coinCost {
                    Button("Buy & Arm") {
                        if profileStore.buyUse(of: shot) {
                            viewModel.armPurchasedShot(shot)
                            SoundService.shared.play(.coin)
                        }
                        pendingPurchase = nil
                    }
                } else {
                    // Short purse mid-battle: send them to the merchant
                    // instead of dead-ending on a Cancel button.
                    Button("Get Doubloons") { openShop(for: shot) }
                }
                Button("Cancel", role: .cancel) { pendingPurchase = nil }
            }
        } message: {
            if let shot = pendingPurchase {
                if profileStore.coins >= shot.spec.coinCost {
                    Text("It arms immediately for this battle.")
                } else {
                    Text("Ye need \(shot.spec.coinCost - profileStore.coins) more doubloons, matey. Visit the merchant to top up without leavin' the battle.")
                }
            }
        }
        .sheet(isPresented: $showShop, onDismiss: reofferAfterShop) {
            DoubloonShopView()
        }
    }

    /// The panel's slots, with this app's economy folded into each state:
    /// an empty special is `buyable` when doubloons can refill it, `locked`
    /// while the captain ladder still gates it, and plain `spent` otherwise.
    private var slots: [ArsenalSlot] {
        viewModel.shotsForPanel.map { entry in
            let spent = (entry.remaining ?? 1) <= 0
            let state: ArsenalSlotState
            if !spent {
                state = .ready
            } else if viewModel.canOfferPurchase(of: entry.shot) {
                state = profileStore.isShotInStock(entry.shot) ? .buyable : .locked
            } else {
                state = .spent
            }
            return .init(shot: entry.shot, remaining: entry.remaining, state: state)
        }
    }

    private func handleTap(_ slot: ArsenalSlot) {
        switch slot.state {
        case .buyable:
            SoundService.shared.play(.tap)
            pendingPurchase = slot.shot
        case .locked:
            // Behind the captain ladder: explain why instead of no-op.
            SoundService.shared.play(.tap)
            tooltipShot = tooltipShot == slot.shot ? nil : slot.shot
        case .spent:
            break
        case .ready:
            SoundService.shared.play(.tap)
            if slot.shot == .flare {
                confirmFlare = true
            } else {
                viewModel.select(slot.shot)
            }
            tooltipShot = nil
        }
    }

    /// Closes the purchase prompt and opens the merchant, remembering what
    /// the captain came for.
    private func openShop(for shot: ShotType) {
        pendingPurchase = nil
        shopReturnShot = shot
        openDoubloonShop($showShop)
    }

    /// Back from the merchant: if the purse now covers the shot they came
    /// for, put the buy prompt straight back up so the trip completes.
    private func reofferAfterShop() {
        defer { shopReturnShot = nil }
        guard let shot = shopReturnShot,
              profileStore.coins >= shot.spec.coinCost,
              viewModel.canOfferPurchase(of: shot) else { return }
        pendingPurchase = shot
    }
}
