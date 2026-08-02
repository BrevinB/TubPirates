import SwiftUI

/// Sheet for choosing the captain's portrait.
struct AvatarPickerView: View {
    /// Post-tutorial framing: celebrate the fresh doubloons and hint that
    /// they're spendable (here and in the Armory).
    var isOnboarding = false

    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingPurchase: Avatar?
    @State private var trophyMessage: String?
    @State private var showShop = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground(imageName: "tile_background")
                RisingBubblesView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollView {
                    HStack {
                        Button {
                            SoundService.shared.play(.tap)
                            showShop = true
                        } label: {
                            DoubloonLabel(amount: profileStore.coins, fontSize: 15)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.35), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal)
                    Text("Choose Your Captain")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.52))
                        .shadow(color: .white.opacity(0.9), radius: 2)
                        .padding(.top, 2)
                    if isOnboarding {
                        Text("Ye've earned yer first doubloons, captain! Spend 'em on a new face — or save 'em for cannons in the Armory.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(Avatar.all) { avatar in
                            avatarCell(avatar)
                        }
                    }
                    .padding()
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
            .sheet(isPresented: $showShop) {
                DoubloonShopView()
            }
            .alert(
                trophyMessage ?? "",
                isPresented: Binding(
                    get: { trophyMessage != nil },
                    set: { if !$0 { trophyMessage = nil } }
                )
            ) {
                Button("Aye!", role: .cancel) { trophyMessage = nil }
            }
            .confirmationDialog(
                pendingPurchase.map { "Buy \($0.name) for \($0.price) doubloons?" } ?? "",
                isPresented: Binding(
                    get: { pendingPurchase != nil },
                    set: { if !$0 { pendingPurchase = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let avatar = pendingPurchase {
                    if profileStore.coins >= avatar.price {
                        Button("Buy & Equip") {
                            if profileStore.buyAvatar(avatar) {
                                SoundService.shared.play(.chest)
                            }
                            pendingPurchase = nil
                        }
                    }
                    Button("Cancel", role: .cancel) { pendingPurchase = nil }
                }
            } message: {
                if let avatar = pendingPurchase, profileStore.coins < avatar.price {
                    Text("Ye need \(avatar.price - profileStore.coins) more doubloons. Win battles to earn them!")
                }
            }
        }
    }

    private func avatarCell(_ avatar: Avatar) -> some View {
        let selected = profileStore.avatarID == avatar.id
        let owned = profileStore.owns(avatar)
        let affordable = profileStore.coins >= avatar.price

        return Button {
            if owned {
                SoundService.shared.play(.pop)
                profileStore.setAvatar(avatar.id)
            } else if let earnedBy = avatar.earnedBy {
                trophyMessage = "\(avatar.name) can't be bought — \(earnedBy.lowercased()) to earn it!"
            } else {
                pendingPurchase = avatar
            }
        } label: {
            VStack(spacing: 6) {
                Image(avatar.id)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? Color.orange : .white.opacity(0.9),
                                          lineWidth: selected ? 4 : 3)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
                    .saturation(owned ? 1 : 0.55)
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .orange)
                                .offset(x: 6, y: 6)
                        }
                    }
                    .overlay(alignment: .top) {
                        if !owned, avatar.earnedBy != nil {
                            Label("Trophy", systemImage: "trophy.fill")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.75, green: 0.55, blue: 0.1), in: Capsule())
                                .offset(y: -8)
                        } else if !owned {
                            HStack(spacing: 3) {
                                Image("coin_doubloon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 13, height: 13)
                                Text("\(avatar.price)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(affordable ? Color.orange : .gray, in: Capsule())
                            .offset(y: -8)
                        }
                    }
                Text(avatar.name)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.32, blue: 0.5))
                    .shadow(color: .white.opacity(0.8), radius: 1.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 104)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(owned ? avatar.name : "\(avatar.name), \(avatar.price) doubloons")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    AvatarPickerView()
        .environment(ProfileStore())
}
