import SwiftUI
import BathtubEngine

/// The shop: spend hard-won coins to permanently unlock special cannons.
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
        let unlocked = profileStore.isUnlocked(shot)
        let affordable = profileStore.coins >= shot.spec.coinCost

        return HStack(spacing: 14) {
            Image(Self.iconNames[shot] ?? "icon_cannon")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(shot.spec.displayName)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(shot.spec.blurb)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            if unlocked {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            } else {
                Button {
                    withAnimation {
                        _ = profileStore.unlock(shot)
                    }
                } label: {
                    VStack(spacing: 2) {
                        DoubloonLabel(amount: shot.spec.coinCost, fontSize: 14)
                        Text("Unlock")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(affordable ? .orange : .gray)
                .disabled(!affordable)
            }
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
