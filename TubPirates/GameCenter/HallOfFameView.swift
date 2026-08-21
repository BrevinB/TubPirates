import GameKit
import Observation
import SwiftUI

// MARK: - Data

/// One row of a leaderboard, ready to render.
struct LegendRow: Identifiable {
    let id: String
    let rank: Int
    let name: String
    let score: String
    let isLocalPlayer: Bool
    var photo: UIImage?
}

/// One achievement with live progress, ready to render.
struct Trophy: Identifiable {
    let id: String
    let title: String
    let detail: String
    let points: Int
    let percent: Double
    /// Hidden-and-unstarted: shown as an undiscovered mystery.
    let isSecret: Bool
    var image: UIImage?

    var isEarned: Bool { percent >= 100 }
}

/// Loads leaderboard entries and achievement progress for the custom
/// Hall of Fame (replacing the stock Game Center dashboard sheet).
@MainActor
@Observable
final class GameCenterBoards {
    enum Phase {
        case loading
        /// No Game Center sign-in — records live on the server, so there's
        /// nothing to show; the view explains instead of erroring.
        case unauthenticated
        case failed
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var wins: [LegendRow] = []
    private(set) var doubloons: [LegendRow] = []
    private(set) var trophies: [Trophy] = []

    /// Achievements in ladder-story order (matches App Store Connect).
    private static let achievementOrder = [
        GameCenterID.firstWin, GameCenterID.wins10, GameCenterID.wins25,
        GameCenterID.pugbeardCleared, GameCenterID.salCleared, GameCenterID.bessCleared,
        GameCenterID.champion, GameCenterID.flawless, GameCenterID.fullBroadside,
        GameCenterID.fleetAdmiral,
    ]

    func load() async {
        #if DEBUG
        // Screenshot staging: -sampleGC renders a populated hall without auth.
        if CommandLine.arguments.contains("-sampleGC") {
            loadSampleData()
            return
        }
        #endif
        guard GKLocalPlayer.local.isAuthenticated else {
            phase = .unauthenticated
            return
        }
        phase = .loading

        async let winRows = loadBoard(GameCenterID.winsLeaderboard)
        async let coinRows = loadBoard(GameCenterID.doubloonsLeaderboard)
        async let trophyRows = loadTrophies()
        let (win, coin, trophy) = await (winRows, coinRows, trophyRows)

        wins = win ?? []
        doubloons = coin ?? []
        trophies = trophy ?? []
        phase = (win == nil && coin == nil && trophy == nil) ? .failed : .ready

        await loadPhotos()
    }

    private func loadBoard(_ boardID: String) async -> [LegendRow]? {
        guard let board = try? await GKLeaderboard.loadLeaderboards(IDs: [boardID]).first,
              let (local, entries, _) = try? await board.loadEntries(
                  for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 25)
              )
        else { return nil }

        let localID = GKLocalPlayer.local.gamePlayerID
        var rows = entries.map { entry in
            LegendRow(
                id: "\(boardID)-\(entry.rank)",
                rank: entry.rank,
                name: entry.player.displayName,
                score: entry.formattedScore,
                isLocalPlayer: entry.player.gamePlayerID == localID
            )
        }
        // The local captain always sees themselves, even below the top 25.
        if let local, !rows.contains(where: \.isLocalPlayer) {
            rows.append(LegendRow(
                id: "\(boardID)-me",
                rank: local.rank,
                name: local.player.displayName,
                score: local.formattedScore,
                isLocalPlayer: true
            ))
        }
        return rows
    }

    private func loadTrophies() async -> [Trophy]? {
        guard let descriptions = try? await GKAchievementDescription.loadAchievementDescriptions() else {
            return nil
        }
        let progress = (try? await GKAchievement.loadAchievements()) ?? []
        let percentByID = Dictionary(
            progress.map { ($0.identifier, $0.percentComplete) },
            uniquingKeysWith: { max($0, $1) }
        )

        return descriptions
            .sorted {
                (Self.achievementOrder.firstIndex(of: $0.identifier) ?? .max)
                    < (Self.achievementOrder.firstIndex(of: $1.identifier) ?? .max)
            }
            .map { description in
                let percent = percentByID[description.identifier] ?? 0
                let secret = description.isHidden && percent <= 0
                return Trophy(
                    id: description.identifier,
                    title: secret ? "???" : description.title,
                    detail: secret
                        ? "A secret exploit. Keep sailing to uncover it."
                        : (percent >= 100 ? description.achievedDescription : description.unachievedDescription),
                    points: description.maximumPoints,
                    percent: percent,
                    isSecret: secret
                )
            }
    }

    /// Avatars and trophy art arrive after the text so the list feels instant.
    private func loadPhotos() async {
        for index in wins.indices {
            wins[index].photo = await Self.photo(forRankedRow: wins[index])
        }
        for index in doubloons.indices {
            if let cached = wins.first(where: { $0.name == doubloons[index].name })?.photo {
                doubloons[index].photo = cached
            } else {
                doubloons[index].photo = await Self.photo(forRankedRow: doubloons[index])
            }
        }
        guard let descriptions = try? await GKAchievementDescription.loadAchievementDescriptions() else { return }
        let byID = Dictionary(descriptions.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for index in trophies.indices {
            guard !trophies[index].isSecret, let description = byID[trophies[index].id] else { continue }
            trophies[index].image = await Self.loadImage(for: description)
        }
    }

    private static func photo(forRankedRow row: LegendRow) async -> UIImage? {
        // Row IDs don't carry the GKPlayer, so re-resolve via the entry list
        // would be heavy; photos only load for the local player cheaply.
        guard row.isLocalPlayer else { return nil }
        return try? await GKLocalPlayer.local.loadPhoto(for: .small)
    }

    private static func loadImage(for description: GKAchievementDescription) async -> UIImage? {
        await withCheckedContinuation { continuation in
            description.loadImage { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    #if DEBUG
    private func loadSampleData() {
        func rows(_ boardID: String, scores: [Int], suffix: String) -> [LegendRow] {
            let names = ["Capt. Sudsbeard", "BrinyBetty", "You", "DuckCommander", "SirScrubsalot",
                         "MopWater Mike", "The Loofah", "RubberRuth"]
            return names.enumerated().map { index, name in
                LegendRow(
                    id: "\(boardID)-\(index)", rank: index + 1, name: name,
                    score: "\(scores[index])\(suffix)", isLocalPlayer: name == "You"
                )
            }
        }
        wins = rows(GameCenterID.winsLeaderboard, scores: [212, 178, 103, 96, 71, 44, 28, 12], suffix: "")
        doubloons = rows(GameCenterID.doubloonsLeaderboard,
                         scores: [48210, 3175, 22040, 18930, 12410, 9800, 4210, 950], suffix: "")
        let sample: [(String, String, String, Int, Double)] = [
            (GameCenterID.firstWin, "First Splash", "Win your first battle.", 25, 100),
            (GameCenterID.wins10, "Seasoned Sailor", "Win 10 battles.", 50, 100),
            (GameCenterID.wins25, "The Tub King", "Win 25 battles and claim the crown.", 100, 60),
            (GameCenterID.pugbeardCleared, "Pugbeard's Bane", "Sink Captain Pugbeard's fleet 3 times.", 50, 100),
            (GameCenterID.salCleared, "Cat Overboard", "Sink Soapy Sal's fleet 4 times.", 75, 75),
            (GameCenterID.bessCleared, "Eight Arms Undone", "Sink Barnacle Bess's fleet 5 times.", 100, 40),
            (GameCenterID.champion, "Tub Champion", "Conquer the entire captain ladder.", 200, 25),
            (GameCenterID.flawless, "Squeaky Clean", "Win a battle without losing a single ship cell.", 100, 0),
            (GameCenterID.fullBroadside, "Full Broadside", "Fire every special cannon at least once.", 100, 80),
            (GameCenterID.fleetAdmiral, "Fleet Admiral", "Own every fleet in the Shipyard.", 200, 50),
        ]
        trophies = sample.map {
            Trophy(id: $0.0, title: $0.1, detail: $0.2, points: $0.3, percent: $0.4, isSecret: false)
        }
        phase = .ready
    }
    #endif
}

// MARK: - View

/// Custom, pirate-themed replacement for the stock Game Center dashboard:
/// leaderboards ("Legends of the Tub") and achievements ("Trophy Cabin").
struct HallOfFameView: View {
    private enum Tab: String, CaseIterable {
        case legends = "Legends"
        case trophies = "Trophies"
    }

    private enum BoardKind: String, CaseIterable {
        case wins = "Battles Won"
        case doubloons = "Doubloons"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var boards = GameCenterBoards()
    @State private var tab: Tab = {
        #if DEBUG
        // Screenshot staging: -trophies opens on the trophy tab.
        if CommandLine.arguments.contains("-trophies") { return .trophies }
        #endif
        return .legends
    }()
    @State private var boardKind: BoardKind = .wins

    private let ink = Color(red: 0.12, green: 0.3, blue: 0.52)
    private let brown = Color(red: 0.35, green: 0.2, blue: 0.05)
    private let brownSoft = Color(red: 0.45, green: 0.3, blue: 0.15)
    private let parchment = Color(red: 1, green: 0.96, blue: 0.85)
    private let gold = Color(red: 0.75, green: 0.55, blue: 0.2)

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground(imageName: "tile_background")
                RisingBubblesView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 14) {
                    Text("Hall o' Fame")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                        .shadow(color: .white.opacity(0.9), radius: 2)
                        .padding(.top, 4)

                    tabPicker

                    ScrollView {
                        VStack(spacing: 10) {
                            switch boards.phase {
                            case .loading:
                                ProgressView().padding(.top, 60)
                            case .unauthenticated:
                                emptyState(
                                    emoji: "🏴‍☠️",
                                    title: "No name on the register!",
                                    message: "Sign in to Game Center in the Settings app and yer scores will fly the flag here."
                                )
                            case .failed:
                                emptyState(
                                    emoji: "🌊",
                                    title: "The record book be soaked!",
                                    message: "Couldn't fetch the standings. Check yer connection and try again."
                                )
                            case .ready:
                                if tab == .legends {
                                    legendsSection
                                } else {
                                    trophiesSection
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                        .contentColumn()
                    }
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
            .task { await boards.load() }
        }
    }

    // MARK: Sections

    private var legendsSection: some View {
        VStack(spacing: 10) {
            boardPicker
            let rows = boardKind == .wins ? boards.wins : boards.doubloons
            if rows.isEmpty {
                emptyState(
                    emoji: "🗺️",
                    title: "Uncharted waters!",
                    message: "No captains on this board yet — win a battle and stake yer claim."
                )
            } else {
                ForEach(rows) { row in
                    legendRow(row)
                }
            }
        }
    }

    private var trophiesSection: some View {
        VStack(spacing: 10) {
            let earned = boards.trophies.filter(\.isEarned)
            Text("\(earned.count) of \(boards.trophies.count) trophies claimed — \(earned.reduce(0) { $0 + $1.points }) points")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(ink.opacity(0.8))
            ForEach(boards.trophies) { trophy in
                trophyCard(trophy)
            }
        }
    }

    // MARK: Rows

    private func legendRow(_ row: LegendRow) -> some View {
        HStack(spacing: 10) {
            rankBadge(row.rank)
            if let photo = row.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(gold.opacity(0.7))
                    .frame(width: 34, height: 34)
            }
            Text(row.name)
                .font(.system(size: 15, weight: row.isLocalPlayer ? .heavy : .bold, design: .rounded))
                .foregroundStyle(brown)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                if boardKind == .doubloons {
                    Image("coin_doubloon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(brownSoft)
                }
                Text(row.score)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(brown)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(parchment.opacity(row.isLocalPlayer ? 1 : 0.9))
                .strokeBorder(row.isLocalPlayer ? Color.orange : gold.opacity(0.55),
                              lineWidth: row.isLocalPlayer ? 2.5 : 1.5)
        )
    }

    private func rankBadge(_ rank: Int) -> some View {
        let fill: Color = switch rank {
        case 1: Color(red: 0.95, green: 0.75, blue: 0.2)
        case 2: Color(red: 0.75, green: 0.75, blue: 0.78)
        case 3: Color(red: 0.8, green: 0.5, blue: 0.25)
        default: Color(red: 0.35, green: 0.2, blue: 0.08)
        }
        return Text("\(rank)")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(fill))
    }

    private func trophyCard(_ trophy: Trophy) -> some View {
        HStack(spacing: 12) {
            Group {
                if let image = trophy.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(gold.opacity(trophy.isEarned ? 0.9 : 0.35))
                        Image(systemName: trophy.isSecret ? "questionmark" : "trophy.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .saturation(trophy.isEarned ? 1 : 0.25)
            .opacity(trophy.isEarned ? 1 : 0.75)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(trophy.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(brown)
                    if trophy.isEarned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.green)
                    }
                }
                Text(trophy.detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(brownSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if !trophy.isEarned, trophy.percent > 0 {
                    ProgressView(value: trophy.percent, total: 100)
                        .tint(.orange)
                        .scaleEffect(y: 1.4)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Text("+\(trophy.points)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(trophy.isEarned ? .yellow : Color.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0.35, green: 0.2, blue: 0.08).opacity(trophy.isEarned ? 1 : 0.55), in: Capsule())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(parchment.opacity(trophy.isEarned ? 1 : 0.82))
                .strokeBorder(trophy.isEarned ? gold : gold.opacity(0.4), lineWidth: trophy.isEarned ? 2 : 1.5)
        )
    }

    // MARK: Pickers & states

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { candidate in
                Button {
                    SoundService.shared.play(.tap)
                    tab = candidate
                } label: {
                    Text(candidate.rawValue)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(tab == candidate ? .white : brown)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(tab == candidate ? Color.orange : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(parchment)
                .strokeBorder(gold, lineWidth: 2)
        )
        .frame(maxWidth: 280)
    }

    private var boardPicker: some View {
        HStack(spacing: 6) {
            ForEach(BoardKind.allCases, id: \.self) { candidate in
                Button {
                    SoundService.shared.play(.tap)
                    boardKind = candidate
                } label: {
                    Text(candidate.rawValue)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(boardKind == candidate ? .white : brownSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(boardKind == candidate
                                           ? Color(red: 0.35, green: 0.2, blue: 0.08)
                                           : parchment.opacity(0.85))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }

    private func emptyState(emoji: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Text(emoji).font(.system(size: 40))
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.top, 40)
    }
}

#Preview {
    HallOfFameView()
}
