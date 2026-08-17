import SwiftUI
import SpriteKit
import StoreKit
import GameKit
import BathtubEngine

struct MatchView: View {
    let config: MatchConfig
    @Binding var path: [Route]
    /// Changing this identity tears down and rebuilds the whole match (rematch).
    @State private var matchID = UUID()

    var body: some View {
        MatchContentView(config: config, path: $path) {
            // AI rematches go back through placement (pre-seeded with the
            // previous layout) so the fleet can be repositioned.
            if case .ai = config.mode {
                var next = config
                next.resume = false
                next.tutorial = false
                path = [.placement(next)]
                return
            }
            // Online: a real Game Center rematch — new match, same rivals.
            // Rebuilding the old (ended) match just replayed the end screen.
            if case .gameCenter(let oldMatchID) = config.mode {
                Task {
                    let service = GameCenterService.shared
                    guard let old = service.matches[oldMatchID],
                          let new = try? await old.rematch() else {
                        path = [.harbor] // rematch declined/failed: back to port
                        return
                    }
                    service.releaseController(for: oldMatchID)
                    let route = await service.destination(for: new)
                    path = Array(path.dropLast()) + [route]
                }
                return
            }
            matchID = UUID()
        }
        .id(matchID)
    }
}

private struct MatchContentView: View {
    let config: MatchConfig
    @Binding var path: [Route]
    let onRematch: () -> Void
    @Environment(\.requestReview) private var requestReview
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: MatchViewModel?
    /// Online match failed to load — explain before bailing to the menu.
    @State private var loadFailed = false
    @State private var scene: BattleScene?
    @State private var showEndScreen = false
    @State private var rewardApplied = false
    @State private var waitingForOpponent = false
    @State private var showHandoff = false
    @State private var confirmLeave = false
    @State private var finalReward = 0
    @State private var firstWinBonusApplied = false
    @State private var showBattleTips = false
    @State private var unlockBanners: [UnlockBanner] = []
    /// Post-game peek at the rival's true board, entered from the end screen.
    @State private var showingFleetPeek = false
    /// Canned-taunt picker (online matches).
    @State private var showChatSheet = false

    var body: some View {
        ZStack {
            Color(red: 0.13, green: 0.35, blue: 0.55).ignoresSafeArea()

            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            }

            if let viewModel {
                hud(viewModel)

                // Pass-and-play privacy cover (opaque; boards already swapped beneath it).
                if showHandoff, case .awaitingHandoff(let next) = viewModel.turnState {
                    PassDeviceView(incomingName: viewModel.displayName(for: next)) {
                        viewModel.confirmHandoff()
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }

                // Online send failure: the shot is applied locally but never
                // reached the rival — offer a retry, don't lose the move.
                if viewModel.turnState == .submitFailed {
                    submitFailedBanner(viewModel)
                        .zIndex(12)
                }
            }

            // Post-game fleet peek: rival's board revealed behind this bar.
            if showingFleetPeek {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("Their fleet, revealed!")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.45), in: Capsule())
                        Button {
                            showingFleetPeek = false
                            showEndScreen = true
                        } label: {
                            Label("Back to Results", systemImage: "chevron.backward")
                                .font(.headline.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(.bottom, 24)
                }
                .zIndex(15)
            }

            // One-time first-battle coach marks (blocks input until tapped through).
            if showBattleTips {
                BattleTipsView {
                    profileStore.markBattleTipsSeen()
                    Analytics.battleTipsFinished()
                    withAnimation { showBattleTips = false }
                }
                .zIndex(20)
            }

            if waitingForOpponent {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Waiting for your rival to place their fleet...")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Back to Menu") { path.removeAll() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
                .padding()
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear(perform: startMatchIfNeeded)
        // Leaving the screen by ANY route (swipe-back, Leave, notification
        // navigation, end-screen exit): stop waits and release the match
        // controller. An orphaned controller swallows the next turn event,
        // which kills notification taps for this match until a force-quit.
        .onDisappear {
            guard case .gameCenter(let matchID) = config.mode else { return }
            let service = GameCenterService.shared
            if service.activeMatchID == matchID { service.activeMatchID = nil }
            viewModel?.abandon()
            guard let controller = service.controller(for: matchID) else { return }
            controller.cancelWaiting()
            controller.onStateReady = nil // don't attach into a dead view
            // A parked fleet must outlive the screen — the controller submits
            // it when the turn event arrives. Anything else gets released.
            if controller.pendingSetupBoard == nil {
                service.releaseController(for: matchID)
            }
        }
        // Foregrounding without a turn event (notifications declined, event
        // dropped): re-pull the match so a rival's move still lands — it flows
        // through handleTurnEvent, so it animates like a live turn.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, case .gameCenter(let matchID) = config.mode,
                  viewModel != nil else { return }
            Task {
                guard let updated = try? await GKTurnBasedMatch.load(withID: matchID) else { return }
                GameCenterService.shared.register(updated)
                GameCenterService.shared.controller(for: matchID)?.handleTurnEvent(updated)
            }
        }
        .alert("Couldn't reach the harbor", isPresented: $loadFailed) {
            Button("Back to Port") { path.removeAll() }
        } message: {
            Text("The battle couldn't be loaded — check yer connection and try again from Online Battle.")
        }
        .onChange(of: viewModel?.turnState) { _, newState in
            // Animate only the handoff cover — a whole-ZStack animation would
            // crossfade the status banner text into a ghosting mess.
            withAnimation(.easeInOut(duration: 0.25)) {
                if case .awaitingHandoff = newState {
                    showHandoff = true
                } else {
                    showHandoff = false
                }
            }
            if case .finished = newState {
                if let viewModel, !rewardApplied, !viewModel.arrivedFinished {
                    rewardApplied = true
                    var reward = viewModel.coinReward
                    // First AI-battle win each day pays double — but the
                    // onboarding battle doesn't burn it; save the 2x moment
                    // for the player's first real victory.
                    if viewModel.mode == .ai, viewModel.didWin, reward > 0,
                       !viewModel.isTutorial,
                       profileStore.claimFirstWinBonus() {
                        reward *= 2
                        firstWinBonusApplied = true
                    }
                    finalReward = reward
                    profileStore.award(coins: reward)
                    // Snapshot progression gates so this win's threshold
                    // crossings can be announced on the victory screen.
                    let captainsBefore = Captain.roster.filter { profileStore.isUnlocked($0) }
                    let stockBefore = ShotType.purchasable.filter { profileStore.isShotInStock($0) }
                    let championBefore = profileStore.isLadderChampion
                    let fleetsBefore = profileStore.profile.ownedFleets
                    let avatarsBefore = profileStore.profile.ownedAvatars
                    profileStore.recordResult(
                        won: viewModel.didWin,
                        againstCaptainID: viewModel.mode == .ai ? viewModel.captain.id : nil
                    )
                    Analytics.battleFinished(
                        mode: analyticsModeName(viewModel.mode),
                        captainID: viewModel.mode == .ai ? viewModel.captain.id : nil,
                        won: viewModel.didWin,
                        reward: reward,
                        isTutorial: viewModel.isTutorial
                    )
                    var banners: [UnlockBanner] = []
                    for captain in Captain.roster
                    where profileStore.isUnlocked(captain) && !captainsBefore.contains(captain) {
                        banners.append(UnlockBanner(
                            icon: captain.portrait,
                            kicker: "NEW RIVAL UNLOCKED",
                            title: captain.name
                        ))
                    }
                    for shot in ShotType.purchasable
                    where profileStore.isShotInStock(shot) && !stockBefore.contains(shot) {
                        banners.append(UnlockBanner(
                            icon: ShotPanelView.iconName(for: shot),
                            kicker: "NEW IN THE ARMORY",
                            title: shot.spec.displayName
                        ))
                    }
                    for fleet in FleetSkin.all
                    where fleet.earnedBy != nil && profileStore.owns(fleet) && !fleetsBefore.contains(fleet.id) {
                        banners.append(UnlockBanner(
                            icon: fleet.previewTextures.first ?? "ship_5",
                            kicker: "TROPHY EARNED",
                            title: fleet.name
                        ))
                    }
                    for avatar in Avatar.all
                    where avatar.earnedBy != nil && profileStore.owns(avatar) && !avatarsBefore.contains(avatar.id) {
                        banners.append(UnlockBanner(
                            icon: avatar.id,
                            kicker: "TROPHY EARNED",
                            title: avatar.name
                        ))
                    }
                    if !championBefore, profileStore.isLadderChampion {
                        // The final Bubbles win: every rung cleared.
                        banners.append(UnlockBanner(
                            icon: "treasure_chest",
                            kicker: "LADDER CONQUERED",
                            title: "The tub is yours, Captain!"
                        ))
                    }
                    unlockBanners = banners
                    profileStore.recordSpecialsFired(viewModel.localSpecialsFired)
                    AchievementReporter.reportProgress(
                        profile: profileStore.profile,
                        flawlessWin: viewModel.wasFlawlessVictory && !viewModel.isTutorial
                    )
                }
                showEndScreen = true
            }
        }
        .sheet(isPresented: $showChatSheet) {
            quickChatSheet
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showEndScreen) {
            if let viewModel {
                let duo = endPortraits(viewModel)
                MatchEndView(
                    didWin: viewModel.didWin,
                    winner: duo.winner,
                    loser: duo.loser,
                    title: viewModel.endTitle,
                    message: viewModel.endMessage,
                    coinReward: finalReward,
                    firstWinBonus: firstWinBonusApplied,
                    unlocks: unlockBanners,
                    // Replaying the nearly-won onboarding battle would farm
                    // free coins — one gift per captain.
                    showRematch: !viewModel.isTutorial,
                    onArmory: armoryOffer(viewModel),
                    onViewFleet: viewModel.mode == .passAndPlay || viewModel.isTutorial ? nil : {
                        showEndScreen = false
                        showingFleetPeek = true
                        scene?.revealEnemyFleet()
                    },
                    onRematch: {
                        showEndScreen = false
                        maybeRequestReview()
                        onRematch()
                    },
                    onExit: {
                        showEndScreen = false
                        maybeRequestReview()
                        path.removeAll()
                    }
                )
            }
        }
    }

    /// Ask for an App Store rating when leaving the victory screen at a win
    /// milestone — after the celebration, never during it. Tutorial wins are
    /// scripted and pass-and-play "wins" are meaningless (didWin is always
    /// true there), so neither counts. Apple may still suppress the prompt;
    /// we record the ask either way so milestones aren't burned twice.
    private func maybeRequestReview() {
        guard let viewModel, viewModel.didWin, !viewModel.isTutorial,
              viewModel.mode != .passAndPlay,
              profileStore.isReviewPromptDue else { return }
        profileStore.markReviewPrompted()
        requestReview()
    }

    /// After a real-economy AI defeat with a drained stash, the end screen
    /// offers the Armory door — the moment the player best understands what
    /// a special cannon is worth.
    private func armoryOffer(_ viewModel: MatchViewModel) -> (() -> Void)? {
        guard !viewModel.didWin, viewModel.mode == .ai, config.consumesInventory else { return nil }
        let stash = ShotType.purchasable.reduce(0) { $0 + profileStore.inventory(of: $1) }
        guard stash <= 1 else { return nil }
        return {
            showEndScreen = false
            path = [.armory]
        }
    }

    /// Who gloats and who sulks on the end screen. Captains use their
    /// dedicated sad/gloat art; player avatars get the rendered treatment.
    private func endPortraits(_ viewModel: MatchViewModel) -> (winner: EndPortrait, loser: EndPortrait) {
        let playerImage = viewModel.mode == .passAndPlay ? "portrait_player" : profileStore.avatarID
        if viewModel.mode == .passAndPlay {
            // Both captains are humans sharing the generic portrait.
            return (EndPortrait(imageName: playerImage),
                    EndPortrait(imageName: playerImage, renderSad: true))
        }
        if case .gameCenter = viewModel.mode {
            // Online: the duo is you and your actual rival, names attached.
            let rival = EndPortrait(
                imageName: viewModel.enemyPortrait,
                renderSad: viewModel.didWin,
                caption: viewModel.onlineOpponentName ?? "Rival"
            )
            let you = EndPortrait(
                imageName: playerImage,
                renderSad: !viewModel.didWin,
                caption: "You"
            )
            return viewModel.didWin ? (you, rival) : (rival, you)
        }
        if viewModel.didWin {
            return (EndPortrait(imageName: playerImage),
                    EndPortrait(imageName: viewModel.captain.sadPortrait))
        }
        return (EndPortrait(imageName: viewModel.captain.gloatPortrait),
                EndPortrait(imageName: playerImage, renderSad: true))
    }

    private func hud(_ viewModel: MatchViewModel) -> some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    PlayerHUDView(
                        imageName: viewModel.enemyPortrait,
                        name: viewModel.displayName(for: viewModel.localPlayer.opponent),
                        highlighted: viewModel.highlightedPlayer == viewModel.localPlayer.opponent
                    )
                    leaveButton(viewModel)
                }
                Spacer()
                statusBanner(viewModel)
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    PlayerHUDView(
                        imageName: viewModel.mode == .passAndPlay ? "portrait_player" : profileStore.avatarID,
                        name: viewModel.displayName(for: viewModel.localPlayer),
                        highlighted: viewModel.highlightedPlayer == viewModel.localPlayer
                    )
                    if showsQuickChat(viewModel) {
                        Button {
                            SoundService.shared.play(.tap)
                            showChatSheet = true
                        } label: {
                            Label("Chat", systemImage: "bubble.left.fill")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.4), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)

            // Speech bubbles get their own row under the HUD — over open
            // water, never covering the portraits, Leave, or status banner.
            // Captain banter (AI) sits leading; online chat sits under its
            // sender (rival leading, yours trailing).
            HStack {
                if let line = viewModel.captainLine {
                    speechBubble(line)
                        .id(line) // new line = new view, so texts never crossfade into each other
                        .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity))
                } else if let chat = viewModel.chatLine, !chat.mine {
                    speechBubble(chat.text)
                        .id(chat.text)
                        .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity))
                }
                Spacer()
                if let chat = viewModel.chatLine, chat.mine {
                    speechBubble(chat.text, trailing: true)
                        .id(chat.text)
                        .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .animation(.spring(duration: 0.3), value: viewModel.captainLine)
            .animation(.spring(duration: 0.3), value: viewModel.chatLine)

            Spacer()

            HStack {
                Spacer()
                ShotPanelView(viewModel: viewModel)
                    .padding(.trailing, 6)
            }
            .padding(.bottom, 40)
        }
    }

    /// Canned taunts only — 4+-safe, nothing to moderate. The pick shows on
    /// your side immediately and sails to the rival with your next shot.
    private var quickChatSheet: some View {
        ZStack {
            ScreenBackground(imageName: "tile_background")
            VStack(spacing: 14) {
                Text("Send a Message")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.52))
                    .shadow(color: .white.opacity(0.9), radius: 2)
                    .padding(.top, 18)
                Text("It sails straight to yer rival")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(QuickChat.lines, id: \.self) { line in
                            Button {
                                SoundService.shared.play(.pop)
                                viewModel?.sendTaunt(line)
                                showChatSheet = false
                            } label: {
                                Text(line)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.05))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(red: 1, green: 0.96, blue: 0.85))
                                            .strokeBorder(Color(red: 0.75, green: 0.55, blue: 0.2), lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    /// Online matches (and staged frames) get the quick-chat button.
    private func showsQuickChat(_ viewModel: MatchViewModel) -> Bool {
        if case .gameCenter = viewModel.mode { return true }
        #if DEBUG
        if MatchViewModel.debugEnemyName != nil { return true }
        #endif
        return false
    }

    /// Comic-style speech bubble; tail points up toward the speaker's card
    /// (leading for the rival/captain, trailing for your own chat).
    private func speechBubble(_ line: String, trailing: Bool = false) -> some View {
        Text(line)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0.05))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 190, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 1, green: 0.96, blue: 0.85))
                    .strokeBorder(Color(red: 0.75, green: 0.55, blue: 0.2), lineWidth: 2)
            )
            .overlay(alignment: trailing ? .topTrailing : .topLeading) {
                // Tail pointing up toward the speaker's card.
                Triangle()
                    .fill(Color(red: 1, green: 0.96, blue: 0.85))
                    .frame(width: 16, height: 9)
                    .offset(x: trailing ? -24 : 24, y: -8)
            }
            .accessibilityLabel(trailing ? "You say: \(line)" : "\(viewModel?.displayName(for: viewModel?.localPlayer.opponent ?? .two) ?? "Captain") says: \(line)")
    }

    private func submitFailedBanner(_ viewModel: MatchViewModel) -> some View {
        VStack(spacing: 12) {
            Text("No wind in the sails!")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Yer shot couldn't reach the rival.\nCheck yer connection and try again.")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            Button {
                SoundService.shared.play(.tap)
                viewModel.retrySubmit()
            } label: {
                Label("Fire Again", systemImage: "arrow.clockwise")
                    .font(.headline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(20)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 40)
    }

    private func leaveButton(_ viewModel: MatchViewModel) -> some View {
        Button {
            confirmLeave = true
        } label: {
            Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
        }
        .confirmationDialog(
            "Leave the battle?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button("Leave") {
                if case .gameCenter(let matchID) = viewModel.mode {
                    // Mark the abandonment BEFORE unblocking the wait so the
                    // resumed task neither declares a forfeit win (which
                    // flashed the victory screen on exit) nor pays out.
                    viewModel.abandon()
                    rewardApplied = true
                    GameCenterService.shared.controller(for: matchID)?.cancelWaiting()
                    GameCenterService.shared.releaseController(for: matchID)
                }
                path.removeAll()
            }
            if case .gameCenter = viewModel.mode {} else if !viewModel.isTutorial {
                Button("Forfeit Battle", role: .destructive) {
                    viewModel.forfeitLocalMatch()
                    path.removeAll()
                }
            }
            Button("Keep Fighting", role: .cancel) {}
        } message: {
            if case .gameCenter = viewModel.mode {
                Text("You can rejoin any time from Online Battle.")
            } else if viewModel.isTutorial {
                Text("You can restart the tutorial from the main menu.")
            } else {
                Text("Leave saves your battle for later — forfeit throws it away.")
            }
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    private func statusBanner(_ viewModel: MatchViewModel) -> some View {
        Text(viewModel.statusText)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.4), in: Capsule())
    }

    private func analyticsModeName(_ mode: MatchConfig.Mode) -> String {
        switch mode {
        case .ai: "ai"
        case .passAndPlay: "passAndPlay"
        case .gameCenter: "online"
        }
    }

    private func startMatchIfNeeded() {
        guard viewModel == nil, !waitingForOpponent else { return }
        #if DEBUG
        let forceTips = CommandLine.arguments.contains("-battleTips")
        let suppressTips = CommandLine.arguments.contains("-autoBattle")
        #else
        let forceTips = false
        let suppressTips = false
        #endif
        if config.mode == .ai, !profileStore.hasSeenBattleTips || forceTips,
           forceTips || !suppressTips {
            showBattleTips = true
        }
        if case .gameCenter(let matchID) = config.mode {
            // Mark this match as on-screen so its turn events animate in place
            // instead of re-triggering navigation.
            GameCenterService.shared.activeMatchID = matchID
            startOnlineMatch(matchID)
        } else {
            var liveConfig = config
            if config.consumesInventory {
                // Re-read the stash at match start so rematches can't
                // resurrect specials that were spent last game.
                liveConfig.loadout = profileStore.loadoutShots
            }
            attach(MatchViewModel(config: liveConfig))
        }
    }

    private func attach(_ newViewModel: MatchViewModel) {
        Analytics.battleStarted(
            mode: analyticsModeName(newViewModel.mode),
            captainID: newViewModel.mode == .ai ? newViewModel.captain.id : nil,
            isTutorial: newViewModel.isTutorial
        )
        newViewModel.onLocalSpecialFired = { shot in
            profileStore.consumeUse(of: shot)
            Analytics.specialFired(String(describing: shot))
        }
        newViewModel.playerFleetID = profileStore.fleet.id
        let newScene = BattleScene()
        newScene.scaleMode = .resizeFill
        newScene.viewModel = newViewModel
        newViewModel.renderer = newScene
        viewModel = newViewModel
        scene = newScene
        newViewModel.matchDidStart()
    }

    /// Seat-keyed setup boards ("0"/"1") mapped to engine players.
    private func engineBoards(from data: OnlineMatchData) -> [PlayerID: Board]? {
        guard let one = data.boards["0"], let two = data.boards["1"] else { return nil }
        return [.one: one, .two: two]
    }

    private func startOnlineMatch(_ matchID: String) {
        let service = GameCenterService.shared
        guard let match = service.matches[matchID] else {
            path.removeAll()
            return
        }
        let seat = service.localSeat(in: match)
        let controller = service.controller(for: matchID) ?? service.makeController(for: match, localPlayer: seat)
        waitingForOpponent = true
        Task {
            do {
                var data = try await GameCenterController.loadGame(from: match)
                let seatKey = seat == .one ? "0" : "1"
                controller.noteAvatars(from: data)
                controller.baselineTaunts(from: data)
                if data.boards[seatKey] == nil, let board = config.playerBoard {
                    // Only the current participant may write match data. If the
                    // rival is still placing (simultaneous auto-match), park our
                    // fleet — the controller submits it when the turn arrives.
                    if match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID {
                        data = try await controller.submitSetup(board: board, avatarID: profileStore.avatarID)
                    } else {
                        controller.pendingSetupBoard = board
                        controller.pendingSetupAvatarID = profileStore.avatarID
                    }
                }
                // The untouched placement fleets, so the view model can rewind
                // and replay any moves this device hasn't watched land.
                let initialBoards = engineBoards(from: data)
                if let state = data.state {
                    waitingForOpponent = false
                    attach(MatchViewModel(
                        gameCenterState: state, localPlayer: seat,
                        controller: controller, initialBoards: initialBoards
                    ))
                } else {
                    // Our board is in; the rival is still placing. Stay on the waiting screen.
                    controller.onStateReady = { state in
                        waitingForOpponent = false
                        attach(MatchViewModel(gameCenterState: state, localPlayer: seat, controller: controller))
                    }
                }
            } catch {
                waitingForOpponent = false
                loadFailed = true
            }
        }
    }
}
