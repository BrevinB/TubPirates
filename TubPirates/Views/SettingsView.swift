import SwiftUI

struct SettingsView: View {
    @Binding var path: [Route]
    @Environment(ProfileStore.self) private var profileStore
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("musicEnabled") private var musicEnabled = true
    @AppStorage("debugAllShots") private var debugAllShots = false
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            ScreenBackground(imageName: "tile_background")
            RisingBubblesView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            settingsList
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(red: 0.1, green: 0.35, blue: 0.35))
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Color(red: 0.15, green: 0.38, blue: 0.38))
    }

    private var settingsList: some View {
        List {
            Section {
                Toggle("Music", isOn: $musicEnabled)
                    .onChange(of: musicEnabled) { _, on in
                        SoundService.shared.musicSettingChanged(enabled: on)
                    }
                Toggle("Sound Effects", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) { _, on in
                        if on { SoundService.shared.play(.pop) }
                    }
                Toggle("Haptics", isOn: $hapticsEnabled)
            } header: {
                sectionHeader("Feel")
            }

            #if DEBUG
            Section {
                Toggle("Unlock every cannon", isOn: $debugAllShots)
                Button("Add 1,000 Doubloons") {
                    profileStore.award(coins: 1000)
                    SoundService.shared.play(.coin)
                }
                Button("Unlock All Cosmetics") {
                    profileStore.debugUnlockAllCosmetics()
                    SoundService.shared.play(.chest)
                }
            } header: {
                sectionHeader("Developer")
            } footer: {
                sectionFooter("Battles start with every special shot armed and nothing is spent from your stash. Debug builds only.")
            }
            #endif

            Section {
                LabeledContent("Wins", value: "\(profileStore.profile.wins)")
                LabeledContent("Losses", value: "\(profileStore.profile.losses)")
                LabeledContent("Doubloons", value: "\(profileStore.coins)")
            } header: {
                sectionHeader("Record")
            }

            Section {
                Button("Replay Tutorial") {
                    profileStore.resetOnboarding()
                    path.removeAll()
                }
            } footer: {
                sectionFooter("Shows the welcome story and first-battle tips again.")
            }

            Section {
                Button("Reset Profile", role: .destructive) {
                    confirmReset = true
                }
            } footer: {
                sectionFooter("Clears doubloons, your shot stash, and your battle record.")
            }
        }
        .scrollContentBackground(.hidden)
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
