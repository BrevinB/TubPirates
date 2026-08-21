import SwiftUI
import GameKit
import BathtubEngine

struct MainMenuView: View {
    @Binding var path: [Route]
    @Environment(ProfileStore.self) private var profileStore
    @State private var showAvatarPicker = false
    @State private var hasSavedMatch = MatchSaveStore.hasSave
    @State private var confirmDiscard = false
    @State private var claimedChestAmount: Int?
    @State private var showDoubloonShop = false
    @State private var showGameCenterDashboard = false
    /// The one-time post-tutorial "pick yer captain" framing of the picker.
    @State private var avatarPickerIsOnboarding = false

    private var debugAllShots: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "debugAllShots")
        #else
        false // never honor the cheat key in a shipping build
        #endif
    }

    /// Debug builds can force-arm every cannon from Settings (no consumption).
    private var battleLoadout: Set<ShotType> {
        debugAllShots ? Set(ShotType.allCases) : profileStore.loadoutShots
    }

    /// What the rival captain wields: everything the armory currently stocks
    /// for this player — what they COULD buy, not what they've bought — so
    /// battles showcase specials even for a player with an empty stash.
    private var rivalBattleLoadout: Set<ShotType> {
        Set(ShotType.allCases.filter { profileStore.isShotInStock($0) })
    }

    /// Drives the gentle floating rock of the title.

    var body: some View {
        ZStack {
            // The tub: your current rival peeks over the far rim — the menu
            // itself is a progression trophy that changes as you climb.
            GeometryReader { geo in
                Image(profileStore.isLadderChampion
                      ? "menu_champion"
                      : profileStore.currentRival.menuBackground)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            RisingBubblesView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                HStack {
                    coinChip
                    Spacer()
                    avatarChip
                    recordChip
                }

                Spacer(minLength: 40)

                VStack(spacing: 4) {
                    Text("Tub Pirates")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.52))
                        .shadow(color: .white.opacity(0.9), radius: 2)
                        .shadow(color: .white.opacity(0.7), radius: 8)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(profileStore.isLadderChampion
                         ? "The tub is yours, Captain!"
                         : "\(profileStore.currentRival.name) awaits...")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                        .shadow(color: .white.opacity(0.8), radius: 3)
                }
                // Bob like a toy on the water. phaseAnimator keeps the
                // animation scoped to these effects — a plain .animation +
                // onAppear toggle let the menu's first layout pass ride the
                // repeatForever curve, flying the title in from the corner.
                .phaseAnimator([false, true]) { content, bob in
                    content
                        .rotationEffect(.degrees(bob ? 1.6 : -1.6))
                        .offset(y: bob ? -3 : 3)
                } animation: { _ in
                    .easeInOut(duration: 2.6)
                }

                Spacer(minLength: 8)

                dailyChestCard

                VStack(spacing: 11) {
                    if hasSavedMatch {
                        HStack(spacing: 8) {
                            menuButton("Resume Battle", icon: "play.fill", tint: .green) {
                                path.append(.match(MatchConfig(
                                    mode: .ai,
                                    loadout: battleLoadout,
                                    consumesInventory: !debugAllShots,
                                    resume: true
                                )))
                            }
                            Button {
                                SoundService.shared.play(.tap)
                                confirmDiscard = true
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.headline.weight(.bold))
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        .frame(maxWidth: 300)
                        .confirmationDialog(
                            "Discard the saved battle?",
                            isPresented: $confirmDiscard,
                            titleVisibility: .visible
                        ) {
                            Button("Discard Battle", role: .destructive) {
                                MatchSaveStore.clear()
                                hasSavedMatch = false
                            }
                            Button("Keep It", role: .cancel) {}
                        } message: {
                            Text("The unfinished battle will be gone for good.")
                        }
                    }
                    menuButton("Battle!", icon: "flag.checkered", tint: .orange) {
                        path.append(.captains(MatchConfig(
                            mode: .ai,
                            loadout: battleLoadout,
                            rivalLoadout: rivalBattleLoadout,
                            consumesInventory: !debugAllShots
                        )))
                    }
                    menuButton("Pass & Play", icon: "person.2.fill", tint: .teal) {
                        path.append(.match(MatchConfig(
                            mode: .passAndPlay,
                            loadout: battleLoadout
                        )))
                    }
                    menuButton("Online Battle", icon: "globe.americas.fill", tint: .indigo) {
                        path.append(.harbor)
                    }
                    menuButton("Armory", icon: "shield.lefthalf.filled", tint: .blue) {
                        path.append(.armory)
                    }
                    menuButton("Settings", icon: "gearshape.fill", tint: .gray) {
                        path.append(.settings)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding()
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            hasSavedMatch = MatchSaveStore.hasSave
            // Fresh from the tutorial, prize purse in hand: offer the captain
            // portrait once — the first taste of spending doubloons.
            if profileStore.hasSeenBattleTips, !profileStore.hasPickedCaptain {
                avatarPickerIsOnboarding = true
                showAvatarPicker = true
            }
            #if DEBUG
            if CommandLine.arguments.contains("-showAvatars") {
                showAvatarPicker = true
            }
            if CommandLine.arguments.contains("-showShop") {
                showDoubloonShop = true
            }
            #endif
        }
        .sheet(isPresented: $showAvatarPicker, onDismiss: {
            // Offered exactly once — keeping the default duck is a choice too.
            if avatarPickerIsOnboarding {
                profileStore.markCaptainPicked()
                avatarPickerIsOnboarding = false
            }
        }) {
            AvatarPickerView(isOnboarding: avatarPickerIsOnboarding)
        }
        .sheet(isPresented: $showDoubloonShop) {
            DoubloonShopView()
        }
        .sheet(isPresented: $showGameCenterDashboard) {
            HallOfFameView()
        }
        .task {
            #if DEBUG
            // Screenshot staging: -records opens the Hall o' Fame sheet.
            if CommandLine.arguments.contains("-records") {
                showGameCenterDashboard = true
            }
            #endif
        }
    }

    private var coinChip: some View {
        Button {
            SoundService.shared.play(.tap)
            showDoubloonShop = true
        } label: {
            HStack(spacing: 5) {
                DoubloonLabel(amount: profileStore.coins)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.3), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Doubloons: \(profileStore.coins). Get more.")
    }

    /// Once-a-day free treasure. Shows a claim card when available,
    /// a burst of doubloons right after claiming, nothing otherwise.
    @ViewBuilder
    private var dailyChestCard: some View {
        if let amount = claimedChestAmount {
            HStack(spacing: 10) {
                Image("treasure_chest")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 44)
                DoubloonLabel(amount: amount, fontSize: 22, prefix: "+")
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(.black.opacity(0.3), in: Capsule())
            .transition(.scale.combined(with: .opacity))
        } else if profileStore.isDailyChestAvailable {
            Button {
                withAnimation(.spring(duration: 0.4)) {
                    let amount = profileStore.claimDailyChest()
                    if amount > 0 {
                        claimedChestAmount = amount
                        SoundService.shared.play(.chest)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image("treasure_chest")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Daily Treasure!")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Tap to claim yer loot")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(red: 0.55, green: 0.35, blue: 0.12))
                        .strokeBorder(Color.yellow.opacity(0.7), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var avatarChip: some View {
        Button {
            showAvatarPicker = true
        } label: {
            Image(profileStore.avatarID)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .orange)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change captain avatar")
    }

    private var recordChip: some View {
        Button {
            SoundService.shared.play(.tap)
            showGameCenterDashboard = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
                Text("\(profileStore.profile.wins)W – \(profileStore.profile.losses)L")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.3), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record and achievements")
    }

    private func menuButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            SoundService.shared.play(.tap)
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.headline.weight(.bold))
                .frame(maxWidth: 300)
                .padding(.vertical, 5)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }
}

#Preview {
    NavigationStack {
        MainMenuView(path: .constant([]))
            .environment(ProfileStore())
    }
}
