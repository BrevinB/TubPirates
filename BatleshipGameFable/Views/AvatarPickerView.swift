import SwiftUI

/// Sheet for choosing the captain's portrait.
struct AvatarPickerView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingPurchase: Avatar?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Avatar.all) { avatar in
                        avatarCell(avatar)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Your Captain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DoubloonLabel(amount: profileStore.coins, fontSize: 15)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
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
                profileStore.setAvatar(avatar.id)
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
                            .strokeBorder(selected ? Color.orange : .secondary.opacity(0.3),
                                          lineWidth: selected ? 4 : 1.5)
                    )
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
                        if !owned {
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
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
