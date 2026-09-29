#if canImport(UIKit)
import BathtubEngine
import SwiftUI

/// What an arsenal slot is currently offering.
public enum ArsenalSlotState: Equatable, Sendable {
    /// Has charges (or is unlimited).
    case ready
    /// Out of charges and nothing to do about it.
    case spent
    /// Out of charges, but the captain can buy another for doubloons.
    case buyable
    /// Out of charges and still behind the captain ladder.
    case locked
}

/// One cannon in the panel. Free of the panel's generic so hosts can build
/// the array without naming a tooltip type.
public struct ArsenalSlot: Identifiable, Equatable, Sendable {
    public let shot: ShotType
    /// `nil` means unlimited (the basic cannon).
    public let remaining: Int?
    public let state: ArsenalSlotState

    public var id: ShotType { shot }

    public init(shot: ShotType, remaining: Int?, state: ArsenalSlotState = .ready) {
        self.shot = shot
        self.remaining = remaining
        self.state = state
    }
}

/// The arsenal panel: the game's cannon list, planked in timber with a gold
/// hairline, armed slot ringed in red, charges badged in blue.
///
/// This is the app's match-screen panel, lifted out so the Messages battle
/// draws the identical object in the identical place instead of a second set
/// of buttons. The host supplies the slots and handles taps, which is what
/// keeps the app's doubloon refills out of the extension without forking the
/// look.
public struct ArsenalPanelView<Tooltip: View>: View {
    let slots: [ArsenalSlot]
    let selected: ShotType
    let showsOrientation: Bool
    let orientation: Orientation
    let onSelect: (ArsenalSlot) -> Void
    let onToggleOrientation: () -> Void
    let onLongPress: (ShotType) -> Void
    /// Leading tooltip, shown by the host when a slot is held down.
    let tooltip: Tooltip
    /// Icon edge, in points. The app draws 48; the Messages sheet steps this
    /// down on a short screen so the panel never crowds the board.
    var iconSide: CGFloat
    /// A rail on the trailing edge (the app) or a bar along the bottom (a
    /// Messages sheet too short to stand it up). Same panel either way.
    var axis: Axis

    public init(
        slots: [ArsenalSlot],
        selected: ShotType,
        showsOrientation: Bool,
        orientation: Orientation,
        iconSide: CGFloat = 48,
        axis: Axis = .vertical,
        onSelect: @escaping (ArsenalSlot) -> Void,
        onToggleOrientation: @escaping () -> Void,
        onLongPress: @escaping (ShotType) -> Void = { _ in },
        @ViewBuilder tooltip: () -> Tooltip
    ) {
        self.slots = slots
        self.selected = selected
        self.showsOrientation = showsOrientation
        self.orientation = orientation
        self.iconSide = iconSide
        self.axis = axis
        self.onSelect = onSelect
        self.onToggleOrientation = onToggleOrientation
        self.onLongPress = onLongPress
        self.tooltip = tooltip()
    }

    private var spacing: CGFloat { iconSide / 6 }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            tooltip
            plank
        }
    }

    @ViewBuilder
    private var plank: some View {
        let cannons = ForEach(slots) { slot in button(for: slot) }
        Group {
            if axis == .vertical {
                VStack(spacing: spacing) {
                    cannons
                    if showsOrientation { orientationButton }
                }
            } else {
                HStack(spacing: spacing) {
                    cannons
                    if showsOrientation { orientationButton }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(TubPalette.timberLight.opacity(0.92))
                .strokeBorder(TubPalette.gold, lineWidth: 2)
        )
    }

    private func button(for slot: ArsenalSlot) -> some View {
        let isArmed = selected == slot.shot
        let spent = slot.state != .ready

        return Button {
            onSelect(slot)
        } label: {
            ArtworkImage(
                name: slot.shot.iconName,
                width: iconSide,
                height: iconSide,
                contentMode: .fill
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        isArmed ? Color.red : .black.opacity(0.35),
                        lineWidth: isArmed ? 3 : 1.5
                    )
            )
            .saturation(spent ? 0.1 : 1)
            .opacity(spent ? 0.5 : 1)
            .overlay {
                if slot.state == .locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: iconSide * 0.375, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 2)
                }
            }
            .overlay(alignment: .topTrailing) { badge(for: slot) }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                onLongPress(slot.shot)
            }
        )
        .accessibilityLabel(slot.shot.localizedDisplayName)
        // The panel signals "armed" with a red border and "spent" by draining
        // the color — neither of which reaches VoiceOver, so say it out loud.
        .accessibilityValue(accessibilityValue(for: slot, isArmed: isArmed))
        .accessibilityAddTraits(isArmed ? [.isSelected] : [])
        .accessibilityHint(slot.shot.localizedBlurb)
    }

    @ViewBuilder
    private func badge(for slot: ArsenalSlot) -> some View {
        if slot.state == .buyable {
            // Buyable refill: coin badge instead of the gray zero.
            ArtworkImage(name: "coin_doubloon", width: iconSide * 0.354, height: iconSide * 0.354)
                .padding(3)
                .background(TubPalette.accent, in: Circle())
                .offset(x: 5, y: -5)
        } else if let remaining = slot.remaining {
            Text("\(remaining)")
                .font(.system(size: iconSide * 0.23, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(4)
                .background(remaining > 0 ? Color.blue : .gray, in: Circle())
                .offset(x: 5, y: -5)
        }
    }

    /// Spoken state for a cannon slot: how many are left, and whether it's
    /// armed, empty, buyable, or still locked behind the captain ladder.
    private func accessibilityValue(for slot: ArsenalSlot, isArmed: Bool) -> String {
        switch slot.state {
        case .locked:
            return String(localized: "Locked", bundle: .module)
        case .buyable:
            return String(localized: "None left. Tap to buy another.", bundle: .module)
        case .spent:
            return String(localized: "None left", bundle: .module)
        case .ready:
            guard let remaining = slot.remaining else {
                return isArmed ? String(localized: "Armed", bundle: .module) : ""
            }
            return isArmed
                ? String(localized: "Armed. \(remaining) left.", bundle: .module)
                : String(localized: "\(remaining) left", bundle: .module)
        }
    }

    private var orientationButton: some View {
        Button(action: onToggleOrientation) {
            Image(systemName: orientation == .horizontal
                  ? "arrow.left.and.right" : "arrow.up.and.down")
                .font(.system(size: iconSide * 0.417, weight: .bold))
                .foregroundStyle(.white)
                .frame(
                    width: iconSide,
                    height: axis == .vertical ? iconSide * 0.75 : iconSide
                )
                .background(Color.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
                .hitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Rotate chain shot", bundle: .module))
        .accessibilityValue(
            orientation == .horizontal
                ? String(localized: "Horizontal", bundle: .module)
                : String(localized: "Vertical", bundle: .module)
        )
    }
}

extension ArsenalPanelView where Tooltip == EmptyView {
    public init(
        slots: [ArsenalSlot],
        selected: ShotType,
        showsOrientation: Bool,
        orientation: Orientation,
        iconSide: CGFloat = 48,
        axis: Axis = .vertical,
        onSelect: @escaping (ArsenalSlot) -> Void,
        onToggleOrientation: @escaping () -> Void,
        onLongPress: @escaping (ShotType) -> Void = { _ in }
    ) {
        self.init(
            slots: slots,
            selected: selected,
            showsOrientation: showsOrientation,
            orientation: orientation,
            iconSide: iconSide,
            axis: axis,
            onSelect: onSelect,
            onToggleOrientation: onToggleOrientation,
            onLongPress: onLongPress,
            tooltip: { EmptyView() }
        )
    }
}

/// The parchment card the panel shows when a slot is held down. The app adds
/// an unlock requirement line below it; the Messages battle shows just the
/// name and blurb, which is all it has to say.
public struct ArsenalTooltipView<Footer: View>: View {
    let shot: ShotType
    let footer: Footer
    let onTap: () -> Void

    public init(
        shot: ShotType,
        onTap: @escaping () -> Void,
        @ViewBuilder footer: () -> Footer
    ) {
        self.shot = shot
        self.onTap = onTap
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shot.localizedDisplayName)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.5, green: 0.15, blue: 0.1))
            Text(shot.localizedBlurb)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(TubPalette.ink)
            footer
        }
        .padding(10)
        .frame(maxWidth: 190)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(TubPalette.parchment)
                .strokeBorder(TubPalette.bannerEdge, lineWidth: 2)
        )
        .onTapGesture(perform: onTap)
    }
}

extension ArsenalTooltipView where Footer == EmptyView {
    public init(shot: ShotType, onTap: @escaping () -> Void) {
        self.init(shot: shot, onTap: onTap, footer: { EmptyView() })
    }
}
#endif
