import SwiftUI

/// The doubloon merchant: coin packs bought with real money via RevenueCat.
/// Shows a friendly closed-shop state until the store is configured.
struct DoubloonShopView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreService.shared
    @State private var purchasing: String?
    @State private var celebrationAmount: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground(imageName: "tile_background")
                RisingBubblesView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            DoubloonLabel(amount: profileStore.coins, fontSize: 15)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.35), in: Capsule())
                            Spacer()
                        }
                        .padding(.horizontal)

                        Image("treasure_chest")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                            .shadow(radius: 6, y: 3)

                        Text("Doubloon Merchant")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.52))
                            .shadow(color: .white.opacity(0.9), radius: 2)

                        if let amount = celebrationAmount {
                            Label("+\(amount) doubloons — welcome aboard!", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.green, in: Capsule())
                                .transition(.scale.combined(with: .opacity))
                        }

                        if store.isConfigured, !store.packs.isEmpty {
                            ForEach(store.packs) { pack in
                                packCard(pack)
                            }
                            Text("Doubloons are spent on special cannons, avatars, and fleets. Purchases add to your balance instantly.")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.25, green: 0.4, blue: 0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        } else if store.isConfigured, store.isLoading {
                            ProgressView()
                                .padding(.top, 30)
                        } else {
                            closedShop
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Pre-launch / no-API-key state: honest and in character.
    private var closedShop: some View {
        VStack(spacing: 10) {
            Text("🏴‍☠️")
                .font(.system(size: 44))
            Text("The merchant be asleep!")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.52))
            Text("Doubloon packs arrive with a future update. Until then — win battles and claim yer daily treasure!")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.25, green: 0.4, blue: 0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(.top, 20)
    }

    private func packCard(_ pack: CoinPack) -> some View {
        Button {
            guard purchasing == nil else { return }
            purchasing = pack.id
            Task {
                if let coins = await StoreService.shared.purchase(pack) {
                    profileStore.award(coins: coins)
                    SoundService.shared.play(.chest)
                    withAnimation(.spring(duration: 0.4)) {
                        celebrationAmount = coins
                    }
                }
                purchasing = nil
            }
        } label: {
            HStack(spacing: 12) {
                Image("coin_doubloon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.08))
                    DoubloonLabel(amount: pack.coins, fontSize: 13)
                        .foregroundStyle(Color(red: 0.55, green: 0.38, blue: 0.2))
                }
                Spacer()
                if purchasing == pack.id {
                    ProgressView()
                        .padding(.horizontal, 14)
                } else {
                    Text(pack.priceString)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.orange, in: Capsule())
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(.white.opacity(0.88))
                    .strokeBorder(Color.orange.opacity(0.6), lineWidth: 2)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .disabled(purchasing != nil)
    }
}

#Preview {
    DoubloonShopView()
        .environment(ProfileStore())
}
