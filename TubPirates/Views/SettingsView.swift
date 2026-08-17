import SwiftUI

struct SettingsView: View {
    @Binding var path: [Route]
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.openURL) private var openURL
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("musicEnabled") private var musicEnabled = true
    @AppStorage("debugAllShots") private var debugAllShots = false
    @AppStorage("debugAllOpponents") private var debugAllOpponents = false
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true
    @State private var confirmReset = false
    @State private var showShop = false

    /// Where "Contact the Captain" lands.
    private static let supportEmail = "brevbot2@gmail.com"
    /// Hosted from this repo's docs/ folder via GitHub Pages. App Store
    /// Connect needs the same URL on the listing.
    private static let privacyPolicyURL: URL? = URL(string: "https://brevinb.github.io/TubPirates/privacy.html")
    /// App Store write-review deep link (numeric Apple ID from App Store
    /// Connect). Unlike the automatic prompt, this one always works.
    private static let writeReviewURL: URL? = URL(string: "https://apps.apple.com/app/id6792769794?action=write-review")

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private let ink = Color(red: 0.12, green: 0.3, blue: 0.52)
    private let inkSoft = Color(red: 0.25, green: 0.4, blue: 0.55)

    var body: some View {
        ZStack {
            ScreenBackground(imageName: "tile_background")
            RisingBubblesView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 18) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                        .shadow(color: .white.opacity(0.9), radius: 2)
                        .padding(.top, 6)

                    card("Feel", icon: "speaker.wave.2.fill") {
                        toggleRow("Music", icon: "music.note", isOn: $musicEnabled)
                            .onChange(of: musicEnabled) { _, on in
                                SoundService.shared.musicSettingChanged(enabled: on)
                            }
                        divider
                        toggleRow("Sound Effects", icon: "speaker.wave.2.fill", isOn: $soundEnabled)
                            .onChange(of: soundEnabled) { _, on in
                                if on { SoundService.shared.play(.pop) }
                            }
                        divider
                        toggleRow("Haptics", icon: "iphone.radiowaves.left.and.right", isOn: $hapticsEnabled)
                    }

                    card("Privacy", icon: "hand.raised.fill") {
                        toggleRow("Anonymous Analytics", icon: "chart.bar.fill", isOn: $analyticsEnabled)
                            .onChange(of: analyticsEnabled) { _, on in
                                if on { Analytics.start() }
                            }
                        footnote("Anonymous gameplay statistics (battles played, features used) help improve the game. No personal data, no tracking, ever.")
                    }

                    #if DEBUG
                    card("Developer", icon: "wrench.and.screwdriver.fill") {
                        toggleRow("Unlock every cannon", icon: "flame.fill", isOn: $debugAllShots)
                        divider
                        toggleRow("Unlock every opponent", icon: "person.3.fill", isOn: $debugAllOpponents)
                        divider
                        buttonRow("Add 1,000 Doubloons", icon: "plus.circle.fill") {
                            profileStore.award(coins: 1000)
                            SoundService.shared.play(.coin)
                        }
                        divider
                        buttonRow("Unlock All Cosmetics", icon: "gift.fill") {
                            profileStore.debugUnlockAllCosmetics()
                            SoundService.shared.play(.chest)
                        }
                        footnote("Cannons: battles start with every special shot armed and nothing is spent from your stash. Opponents: every captain is battle-able without touching ladder progress. Debug builds only.")
                    }
                    #endif

                    card("Yer Record", icon: "trophy.fill") {
                        valueRow("Wins", icon: "flag.checkered", value: "\(profileStore.profile.wins)")
                        divider
                        valueRow("Losses", icon: "xmark.circle", value: "\(profileStore.profile.losses)")
                        divider
                        HStack(spacing: 10) {
                            rowIcon("circle.grid.2x1.fill")
                            Text("Doubloons")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(ink)
                            Spacer()
                            DoubloonLabel(amount: profileStore.coins, fontSize: 15)
                                .foregroundStyle(Color(red: 0.55, green: 0.38, blue: 0.2))
                        }
                        .padding(.vertical, 10)
                    }

                    card("The Merchant", icon: "cart.fill") {
                        buttonRow("Doubloon Shop", icon: "circle.grid.2x1.fill") {
                            showShop = true
                        }
                        footnote("Top up yer doubloons with real-world treasure.")
                    }

                    card("About", icon: "info.circle.fill") {
                        valueRow("Version", icon: "number", value: appVersion)
                        divider
                        buttonRow("Contact the Captain", icon: "envelope.fill") {
                            if let url = URL(string: "mailto:\(Self.supportEmail)?subject=Tub%20Pirates%20Support") {
                                openURL(url)
                            }
                        }
                        if let reviewURL = Self.writeReviewURL {
                            divider
                            buttonRow("Rate Tub Pirates", icon: "star.fill") {
                                openURL(reviewURL)
                            }
                        }
                        if let policyURL = Self.privacyPolicyURL {
                            divider
                            buttonRow("Privacy Policy", icon: "hand.raised.fill") {
                                openURL(policyURL)
                            }
                        }
                        footnote("Trouble aboard? Send a message and include yer app version.")
                    }

                    card("The Ship's Log", icon: "book.fill") {
                        buttonRow("Replay Tutorial", icon: "arrow.counterclockwise") {
                            profileStore.resetOnboarding()
                            path.removeAll()
                        }
                        footnote("Shows the welcome story and first-battle tips again.")
                        divider
                        buttonRow("Reset Profile", icon: "trash.fill", tint: .red) {
                            confirmReset = true
                        }
                        footnote("Clears doubloons, your shot stash, and your battle record.")
                    }
                }
                .padding()
                .contentColumn()
            }
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showShop) {
            DoubloonShopView()
        }
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

    // MARK: - Themed building blocks

    /// A soapy white card with a navy header chip, holding a stack of rows.
    private func card(
        _ title: String, icon: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(inkSoft, in: Capsule())
                .offset(x: 8, y: 12)
                .zIndex(1)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.86))
                    .shadow(color: .black.opacity(0.12), radius: 7, y: 4)
            )
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(inkSoft.opacity(0.15))
            .frame(height: 1)
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Color(red: 0.45, green: 0.72, blue: 0.85), in: RoundedRectangle(cornerRadius: 8))
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            rowIcon(icon)
            Toggle(title, isOn: isOn)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .tint(.orange)
        }
        .padding(.vertical, 8)
    }

    private func buttonRow(
        _ title: String, icon: String, tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            SoundService.shared.play(.tap)
            action()
        } label: {
            HStack(spacing: 10) {
                rowIcon(icon)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(tint ?? ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(inkSoft.opacity(0.5))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func valueRow(_ title: String, icon: String, value: String) -> some View {
        HStack(spacing: 10) {
            rowIcon(icon)
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(inkSoft)
        }
        .padding(.vertical, 10)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(inkSoft.opacity(0.8))
            .padding(.bottom, 8)
            .padding(.leading, 38)
    }
}

#Preview {
    NavigationStack {
        SettingsView(path: .constant([]))
            .environment(ProfileStore())
    }
}
