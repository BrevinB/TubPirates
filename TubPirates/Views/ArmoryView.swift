import SwiftUI
import BathtubEngine

/// The shop: spend doubloons on consumable special-shot uses.
/// Each purchase adds one use to the stash; firing one in battle spends it.
struct ArmoryView: View {
    @Environment(ProfileStore.self) private var profileStore
    @State private var pendingFleet: FleetSkin?
    @State private var showShop = false

    private static let iconNames: [ShotType: String] = [
        .parrotScout: "icon_parrot", .bigShot: "icon_bigshot",
        .flare: "icon_flare", .chainShot: "icon_chain", .fireworks: "icon_fireworks",
    ]

    var body: some View {
        ZStack {
            ScreenBackground(imageName: "armory_background")

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    Text("Stock up before battle — every shot you fire is spent from your stash!")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.94, blue: 0.8).opacity(0.9))
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    cannonCard
                    ForEach(ShotType.purchasable) { shot in
                        shotCard(shot)
                    }

                    Text("⚓️ The Shipyard")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.94, blue: 0.8))
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .padding(.top, 14)
                        .id("shipyard")
                    Text("New looks for yer whole fleet — pure style, same firepower.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.94, blue: 0.8).opacity(0.9))
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    ForEach(FleetSkin.all) { fleet in
                        fleetCard(fleet)
                    }
                }
                .padding()
                .contentColumn()
            }
            .onAppear {
                #if DEBUG
                // Debug: land scrolled to the Shipyard (screenshot staging).
                if CommandLine.arguments.contains("-shipyard") {
                    proxy.scrollTo("shipyard", anchor: .top)
                }
                #endif
            }
            }
        }
        .confirmationDialog(
            pendingFleet.map { String(localized: "Buy the \($0.localizedName) for \($0.price) doubloons?") } ?? "",
            isPresented: Binding(
                get: { pendingFleet != nil },
                set: { if !$0 { pendingFleet = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let fleet = pendingFleet {
                if profileStore.coins >= fleet.price {
                    Button("Buy & Equip") {
                        if profileStore.buyFleet(fleet) {
                            SoundService.shared.play(.chest)
                        }
                        pendingFleet = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingFleet = nil }
            }
        } message: {
            if let fleet = pendingFleet, profileStore.coins < fleet.price {
                Text("Ye need \(fleet.price - profileStore.coins) more doubloons. Win battles to earn them!")
            }
        }
        .navigationTitle("Armory")
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // The coin chip opens the shop everywhere it's shown — this
                // is THE spending screen, where a short purse matters most.
                Button {
                    SoundService.shared.play(.tap)
                    showShop = true
                } label: {
                    DoubloonLabel(amount: profileStore.coins, fontSize: 16)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showShop) {
            DoubloonShopView()
        }
    }

    /// The trusty basic cannon — not for sale, never runs out. Shown so the
    /// arsenal list reads complete and new captains know what they always have.
    private var cannonCard: some View {
        HStack(spacing: 14) {
            Image("icon_cannon")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "infinity")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.blue, in: Circle())
                        .offset(x: 8, y: -8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(ShotType.cannon.localizedDisplayName)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.08))
                Text(ShotType.cannon.localizedBlurb)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.45, green: 0.3, blue: 0.15))
            }

            Spacer()

            Label("Always armed", systemImage: "infinity")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.35, green: 0.45, blue: 0.25))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.78, green: 0.88, blue: 0.7), in: Capsule())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 1, green: 0.96, blue: 0.85))
                .strokeBorder(Color(red: 0.6, green: 0.42, blue: 0.22), lineWidth: 2.5)
                .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
        )
    }

    /// A Shipyard card: fleet preview strip + name + buy/equip state.
    private func fleetCard(_ fleet: FleetSkin) -> some View {
        let owned = profileStore.owns(fleet)
        let equipped = profileStore.fleet == fleet
        let affordable = profileStore.coins >= fleet.price

        return Button {
            if equipped { return }
            if owned {
                SoundService.shared.play(.pop)
                profileStore.setFleet(fleet)
            } else if fleet.earnedBy == nil {
                pendingFleet = fleet
            }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(fleet.localizedName)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.08))
                    Spacer()
                    if equipped {
                        Label("Equipped", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green, in: Capsule())
                    } else if owned {
                        Text("Tap to equip")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.55, green: 0.38, blue: 0.2))
                    } else if let earnedBy = fleet.localizedEarnedBy {
                        Label(earnedBy, systemImage: "trophy.fill")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.75, green: 0.55, blue: 0.1), in: Capsule())
                    } else {
                        HStack(spacing: 4) {
                            DoubloonLabel(amount: fleet.price, fontSize: 13)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(affordable ? Color.orange : .gray, in: Capsule())
                    }
                }

                // The five toys, largest to smallest, bobbing on one shelf.
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(fleet.previewTextures, id: \.self) { texture in
                        Image(texture)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 34)
                    }
                }
                .frame(maxWidth: .infinity)
                .saturation(owned ? 1 : 0.7)

                Text(fleet.localizedBlurb)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.45, green: 0.3, blue: 0.15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 1, green: 0.96, blue: 0.85))
                    .strokeBorder(
                        equipped ? Color.green : Color(red: 0.6, green: 0.42, blue: 0.22),
                        lineWidth: 2.5
                    )
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(owned ? fleet.localizedName : String(localized: "\(fleet.localizedName), \(fleet.price) doubloons"))
    }

    private func shotCard(_ shot: ShotType) -> some View {
        let owned = profileStore.inventory(of: shot)
        let affordable = profileStore.coins >= shot.spec.coinCost
        let inStock = profileStore.isShotInStock(shot)

        return HStack(spacing: 14) {
            Image(Self.iconNames[shot] ?? "icon_cannon")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .saturation(inStock ? 1 : 0)
                .overlay(alignment: .topTrailing) {
                    if inStock {
                        Text("×\(owned)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(owned > 0 ? Color.blue : .gray, in: Capsule())
                            .offset(x: 8, y: -8)
                    }
                }
                .overlay {
                    if !inStock {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(shot.localizedDisplayName)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.08))
                if inStock {
                    Text(shot.localizedBlurb)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.45, green: 0.3, blue: 0.15))
                } else if let requirement = profileStore.armoryRequirement(for: shot) {
                    Label(
                        "Defeat \(requirement.localizedName) ×\(requirement.winsToAdvance) to stock this",
                        systemImage: "lock.fill"
                    )
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.7, green: 0.4, blue: 0.1))
                }
            }

            Spacer()

            if inStock {
                Button {
                    withAnimation {
                        if profileStore.buyUse(of: shot) {
                            SoundService.shared.play(.coin)
                        }
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
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 1, green: 0.96, blue: 0.85).opacity(inStock ? 1 : 0.75))
                .strokeBorder(Color(red: 0.6, green: 0.42, blue: 0.22), lineWidth: 2.5)
                .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
        )
    }
}

#Preview {
    NavigationStack {
        ArmoryView()
            .environment(ProfileStore())
    }
}
