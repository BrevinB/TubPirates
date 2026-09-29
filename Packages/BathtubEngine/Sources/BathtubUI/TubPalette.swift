// The shared game UI is a SwiftUI/UIKit surface; the package also builds for
// macOS so the engine's tests can run there, where this target has nothing
// to offer.
#if canImport(UIKit)
import SwiftUI

/// The one definition of the game's colors.
///
/// These literals used to live in three places — inline in `MatchView` and
/// `PlacementView`, again in `ShotPanelView`, and a third time as the
/// extension's `MessageTheme` — which is how the Messages sheet drifted into
/// stock `.orange`/`.cyan` while the app stayed in timber and gold. Anything
/// drawn in either target reads its color from here.
public enum TubPalette {
    /// Ship's timber: the fleet bars and quiet chrome.
    public static let timber = Color(red: 0.35, green: 0.2, blue: 0.08)
    /// The lighter timber the arsenal panel is planked with.
    public static let timberLight = Color(red: 0.45, green: 0.29, blue: 0.14)
    public static let gold = Color(red: 0.85, green: 0.65, blue: 0.3)
    /// Panel parchment (arsenal tooltips).
    public static let parchment = Color(red: 1, green: 0.96, blue: 0.75)
    /// Banner parchment — a touch warmer than the panel, and what every
    /// capsule in the top chrome band is filled with.
    public static let banner = Color(red: 1, green: 0.96, blue: 0.85)
    /// The parchment edge.
    public static let bannerEdge = Color(red: 0.75, green: 0.55, blue: 0.2)
    /// Lettering on parchment.
    public static let ink = Color(red: 0.35, green: 0.2, blue: 0.05)
    /// Lettering on timber.
    public static let cream = Color(red: 1, green: 0.94, blue: 0.8)
    /// Name-plate backing under a portrait.
    public static let nameplate = Color(red: 1, green: 0.97, blue: 0.88)
    public static let nameplateEdge = Color(red: 0.55, green: 0.38, blue: 0.16)
    /// Damage.
    public static let hit = Color(red: 0.9, green: 0.25, blue: 0.18)
    /// The brighter red the sunk ✕ is struck in.
    public static let sunkMark = Color(red: 1, green: 0.3, blue: 0.25)
    public static let sunkGray = Color(white: 0.35)
    /// Placement water.
    public static let water = Color(red: 0.42, green: 0.72, blue: 0.93)
    /// The tub behind the arena, and headings over key art.
    public static let deepSea = Color(red: 0.12, green: 0.3, blue: 0.52)
    /// The flat color the arena's own backdrop sits on.
    public static let arenaBackdrop = Color(red: 0.13, green: 0.35, blue: 0.55)
    /// The game's orange, as a fixed value.
    ///
    /// This was `Color.orange` — the one system colour in a palette that is
    /// otherwise all fixed sRGB. A system colour is dynamic: it resolves
    /// through the trait environment, and inside an extension hosted by
    /// another process that environment is not ours to rely on. Everything the
    /// game draws is fixed-colour art, so its orange should be too.
    public static let accent = Color(red: 1, green: 0.584, blue: 0)
}
#endif
