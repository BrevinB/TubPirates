import SwiftUI
import BathtubEngine

/// The shop: spend doubloons on consumable special-shot uses.
/// Each purchase adds one use to the stash; firing one in battle spends it.
struct ArmoryView: View {
    @Environment(ProfileStore.self) private var profileStore

    private static let iconNames: [ShotType: String] = [
        .parrotScout: "icon_parrot", .bigShot: "icon_bigshot",
        .flare: "icon_flare", .chainShot: "icon_chain", .fireworks: "icon_fireworks",
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.32, green: 0.2, blue: 0.1), Color(red: 0.18, green: 0.1, blue: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    Text("Stock up before battle — every shot you fire is spent from your stash!")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    ForEach(ShotType.purchasable) { shot in
                        shotCard(shot)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Armory")
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DoubloonLabel(amount: profileStore.coins, fontSize: 16)
            }
        }
    }

    private func shotCard(_ shot: ShotType) -> some View {
        let owned = profileStore.inventory(of: shot)
        let affordable = profileStore.coins >= shot.spec.coinCost

        return HStack(spacing: 14) {
            Image(Self.iconNames[shot] ?? "icon_cannon")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    Text("×\(owned)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(owned > 0 ? Color.blue : .gray, in: Capsule())
                        .offset(x: 8, y: -8)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(shot.spec.displayName)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(shot.spec.blurb)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            Button {
                withAnimation {
                    _ = profileStore.buyUse(of: shot)
                }
            } label: {
                VStack(spacing: 2) {
                    DoubloonLabel(amount: shot.spec.coinCost, fontSize: 14)
                    Text("Buy 1")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(affordable ? .orange : .gray)
            .disabled(!affordable)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 1, opacity: 0.08))
                .strokeBorder(Color(red: 0.85, green: 0.65, blue: 0.3, opacity: 0.6), lineWidth: 1.5)
        )
    }
}

#Preview {
    NavigationStack {
        ArmoryView()
            .environment(ProfileStore())
    }
}
