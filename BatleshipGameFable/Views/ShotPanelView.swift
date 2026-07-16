import SwiftUI
import BathtubEngine

/// Vertical arsenal panel on the right edge of the match screen —
/// mirrors the original game's cannon list with tooltips.
struct ShotPanelView: View {
    @Bindable var viewModel: MatchViewModel
    @State private var tooltipShot: ShotType?
    @State private var confirmFlare = false

    private static let iconNames: [ShotType: String] = [
        .cannon: "icon_cannon", .parrotScout: "icon_parrot", .bigShot: "icon_bigshot",
        .flare: "icon_flare", .chainShot: "icon_chain", .fireworks: "icon_fireworks",
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let tooltipShot {
                tooltip(for: tooltipShot)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            VStack(spacing: 8) {
                ForEach(viewModel.shotsForPanel, id: \.shot) { entry in
                    shotButton(entry.shot, remaining: entry.remaining)
                }
                if viewModel.selectedShot.spec.needsOrientation {
                    orientationButton
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.45, green: 0.29, blue: 0.14).opacity(0.92))
                    .strokeBorder(Color(red: 0.85, green: 0.65, blue: 0.3), lineWidth: 2)
            )
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
            Text(ShotType.flare.spec.blurb)
        }
    }

    private func shotButton(_ shot: ShotType, remaining: Int?) -> some View {
        let spent = (remaining ?? 1) <= 0
        let selected = viewModel.selectedShot == shot && !shot.spec.needsTarget == false

        return Button {
            if spent { return }
            if shot == .flare {
                confirmFlare = true
            } else {
                viewModel.select(shot)
            }
            tooltipShot = nil
        } label: {
            Image(Self.iconNames[shot] ?? "icon_cannon")
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(
                            viewModel.selectedShot == shot ? Color.red : .black.opacity(0.35),
                            lineWidth: viewModel.selectedShot == shot ? 3 : 1.5
                        )
                )
                .saturation(spent ? 0.1 : 1)
                .opacity(spent ? 0.5 : 1)
                .overlay(alignment: .topTrailing) {
                    if let remaining {
                        Text("\(remaining)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(remaining > 0 ? Color.blue : .gray, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                tooltipShot = tooltipShot == shot ? nil : shot
            }
        )
        .accessibilityLabel(shot.spec.displayName)
    }

    private var orientationButton: some View {
        Button {
            viewModel.toggleOrientation()
        } label: {
            Image(systemName: viewModel.selectedOrientation == .horizontal
                  ? "arrow.left.and.right" : "arrow.up.and.down")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 36)
                .background(Color.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rotate chain shot")
    }

    private func tooltip(for shot: ShotType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shot.spec.displayName)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.5, green: 0.15, blue: 0.1))
            Text(shot.spec.blurb)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.05))
        }
        .padding(10)
        .frame(maxWidth: 190)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 1, green: 0.96, blue: 0.75))
                .strokeBorder(Color(red: 0.75, green: 0.55, blue: 0.2), lineWidth: 2)
        )
        .onTapGesture { tooltipShot = nil }
    }
}
