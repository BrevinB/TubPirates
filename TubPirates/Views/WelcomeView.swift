import SwiftUI

/// First-launch story: three quick pages that set the scene, teach the goal,
/// and point at the loot loop. Skippable from any page.
struct WelcomeView: View {
    let onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack {
            ScreenBackground(imageName: "tile_background")
            RisingBubblesView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < 2 {
                        Button("Skip") {
                            Analytics.onboardingFinished(skipped: true)
                            onFinish()
                        }
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
                            .padding(.horizontal, 18)
                    }
                }
                .frame(height: 44)

                TabView(selection: $page) {
                    welcomePage(
                        image: "portrait_dogbeard_gloat",
                        title: "Ahoy, Captain!",
                        text: "Captain Pugbeard the pirate pug has seized the bathtub — and he's daring YOU to take it back!"
                    )
                    .tag(0)

                    welcomePage(
                        image: "ship_3b",
                        secondaryImage: "ship_2",
                        title: "Sink His Fleet!",
                        text: "Hide your five bath toys in the suds, then take turns firing cannonballs into his water. Sink all five of his toys before he sinks yours!"
                    )
                    .tag(1)

                    welcomePage(
                        image: "treasure_chest",
                        title: "Plunder & Glory!",
                        text: "Win doubloons every battle! Stock special cannons in the Armory, collect captain portraits, and climb the ladder to face the tub's mightiest rivals."
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        Analytics.onboardingFinished(skipped: false)
                        onFinish()
                    }
                } label: {
                    Label(
                        page < 2 ? "Next" : "Set Sail!",
                        systemImage: page < 2 ? "arrow.right" : "flag.checkered"
                    )
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: 320)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.bottom, 30)
            }
        }
        .interactiveDismissDisabled()
    }

    private func welcomePage(
        image: String,
        secondaryImage: String? = nil,
        title: String,
        text: String
    ) -> some View {
        VStack(spacing: 22) {
            Spacer()

            if let secondaryImage {
                // Toy-fleet spread for the battle page.
                VStack(spacing: 10) {
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 64)
                        .rotationEffect(.degrees(-4))
                    Image(secondaryImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 52)
                        .rotationEffect(.degrees(3))
                }
                .shadow(radius: 5, y: 3)
            } else {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 170, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(radius: 8, y: 4)
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.52))
                    .shadow(color: .white.opacity(0.9), radius: 2)
                Text(text)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.35, blue: 0.45))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            )
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    WelcomeView(onFinish: {})
}
