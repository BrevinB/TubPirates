import SwiftUI

/// Sheet for choosing the captain's portrait.
struct AvatarPickerView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func avatarCell(_ avatar: Avatar) -> some View {
        let selected = profileStore.avatarID == avatar.id
        return Button {
            profileStore.setAvatar(avatar.id)
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
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .orange)
                                .offset(x: 6, y: 6)
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
        .accessibilityLabel(avatar.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    AvatarPickerView()
        .environment(ProfileStore())
}
