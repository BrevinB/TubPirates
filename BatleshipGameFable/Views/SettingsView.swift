import SwiftUI

struct SettingsView: View {
    @Binding var path: [Route]
    @Environment(ProfileStore.self) private var profileStore
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("debugAllShots") private var debugAllShots = false
    @State private var confirmReset = false

    var body: some View {
        List {
            Section("Feel") {
                Toggle("Haptics", isOn: $hapticsEnabled)
            }

            #if DEBUG
            Section {
                Toggle("Unlock every cannon", isOn: $debugAllShots)
            } header: {
                Text("Developer")
            } footer: {
                Text("Battles start with every special shot armed and nothing is spent from your stash. Debug builds only.")
            }
            #endif

            Section("Record") {
                LabeledContent("Wins", value: "\(profileStore.profile.wins)")
                LabeledContent("Losses", value: "\(profileStore.profile.losses)")
                LabeledContent("Doubloons", value: "\(profileStore.coins)")
            }

            Section {
                Button("Reset Profile", role: .destructive) {
                    confirmReset = true
                }
            } footer: {
                Text("Clears doubloons, your shot stash, and your battle record.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Reset your profile?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                profileStore.resetProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Coins, unlocks, and record will be wiped. This can't be undone.")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(path: .constant([]))
            .environment(ProfileStore())
    }
}
