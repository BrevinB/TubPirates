#if canImport(UIKit)
import SwiftUI

/// Sizing for the battle chrome on the surface it actually got.
///
/// The app's match screen owns a whole phone and hard-codes 64pt portraits, a
/// 14.5pt banner and a 48pt arsenal. An expanded Messages sheet is nearly that
/// big — which is why the sheet should use the app's layout rather than a
/// bespoke one — but on an SE-class phone it is about 430pt tall, and at that
/// height the app's numbers push the arsenal over the board.
///
/// So: at full height every value here *is* the app's literal, and the two
/// screens are pixel-identical. Below that the chrome scales down together,
/// rather than pieces dropping out of the layout one at a time.
public struct BattleHUDMetrics: Equatable, Sendable {
    /// The whole surface — the width matters as much as the height, because
    /// the arena's own board is placed against the leading edge and the HUD
    /// has to stay off it.
    public var size: CGSize

    public var height: CGFloat { size.height }

    public init(size: CGSize) { self.size = size }

    public init(height: CGFloat) {
        self.init(size: CGSize(width: 393, height: height))
    }

    /// The app's own match screen, and any roomy Messages sheet.
    public static let standard = BattleHUDMetrics(size: CGSize(width: 393, height: 800))

    var isCompact: Bool { height < 560 }
    var isVeryCompact: Bool { height < 460 }

    /// Portrait edge. The app draws 64.
    public var portraitSide: CGFloat { isVeryCompact ? 44 : (isCompact ? 54 : 64) }
    /// Hull segment height. The app draws 5.5.
    public var fleetSegmentHeight: CGFloat { isVeryCompact ? 4 : (isCompact ? 4.75 : 5.5) }
    /// Status banner text. The app draws 14.5.
    public var bannerFontSize: CGFloat { isVeryCompact ? 12 : (isCompact ? 13 : 14.5) }
    /// Arsenal icon edge. The app draws 48.
    public var arsenalIconSide: CGFloat { isVeryCompact ? 30 : (isCompact ? 42 : 48) }
    /// Gap between the HUD's stacked pieces. The app draws 8.
    public var columnSpacing: CGFloat { isCompact ? 5 : 8 }
    /// Side gutter. The app draws 12.
    public var gutter: CGFloat { isVeryCompact ? 8 : 12 }
    /// How far the arsenal floats off the bottom. The app draws 40.
    public var bottomInset: CGFloat { isVeryCompact ? 10 : (isCompact ? 22 : 40) }
    /// Secondary-control lettering. The app draws 13.
    public var capsuleFontSize: CGFloat { isVeryCompact ? 11 : 13 }

    /// Width of a captain's column: the name-plate is the widest thing in it.
    public var captainColumnWidth: CGFloat { portraitSide * 1.156 }

    /// A fixed width for the status banner between the two captains.
    ///
    /// Left to size itself, the banner grows and shrinks with its own text —
    /// and that text changes the instant a turn is sent. The two `Spacer`s then
    /// redistribute and the fleet bars either side visibly jump. Pinning the
    /// width means the top band's layout no longer depends on what the banner
    /// happens to say.
    public var statusWidth: CGFloat {
        // A column is as wide as its widest member, and that is the Forfeit
        // capsule rather than the name-plate — budget for it, or the fixed
        // centre squeezes the very thing it was meant to hold still.
        let column = max(captainColumnWidth, 96)
        return max(120, min(200, size.width - (column * 2 + gutter * 2 + 16)))
    }

    /// Width the arsenal rail occupies on the trailing edge: the icons, the
    /// plank's padding and the gap to the screen edge.
    public var arsenalRailWidth: CGFloat { arsenalIconSide + 12 + 6 }

    /// How far a bottom-anchored control must be raised to clear the player's
    /// own beached fleet. The Fire button and the "tap send" hint used to sit
    /// under it, squarely on top of the board.
    public var ownFleetClearance: CGFloat {
        ArenaStageGeometry.ownBoardTopInset(in: size)
    }

    /// The letterboxed arena stage — what the bottom band aligns to.
    ///
    /// The top band tracks `stageColumn()`'s 520pt cap, which is what the app
    /// has always used. The bottom band has to agree with the *arena* instead,
    /// because it dodges boards the arena placed; on an iPad the two numbers
    /// differ enough for the Fire button and the rail to collide.
    /// Capped at the same width the top band uses, so the app's iPad layout is
    /// untouched: without the cap the rail would slide from the 520pt column
    /// out to the screen edge.
    public var stageWidth: CGFloat {
        min(ArenaStageGeometry.stage(in: size), TubStage.hudMaxWidth)
    }

    private var stageLeadingEdge: CGFloat { (size.width - stageWidth) / 2 }

    /// Leading inset that puts a bottom-anchored control to the *right* of the
    /// beached fleet instead of above it — which is where the arena leaves a
    /// genuine gap: below the enemy diamond's bottom tip, between the fleet and
    /// the arsenal rail. Only the decorative cannon lives there.
    /// Measured from the stage's own leading edge, not the screen's.
    public var ownFleetTrailingInset: CGFloat {
        max(0, ArenaStageGeometry.ownBoardTrailingEdge(in: size) - stageLeadingEdge) + 8
    }

    /// Whether that gap is wide enough to hold a real button.
    public var commitFitsBesideFleet: Bool {
        stageWidth - ownFleetTrailingInset - arsenalRailWidth >= 150
    }

    /// Whether the arsenal can stand up as a rail on the trailing edge, the
    /// way the app draws it.
    ///
    /// Six stacked icons plus the orientation button and the panel's own
    /// padding need roughly `7 * (icon + spacing) + 12`. That has to clear the
    /// top band and the commit button, and below about this height it cannot —
    /// so the rail lies down along the bottom instead of overlapping your own
    /// name-plate, which is what a purely proportional shrink would have done.
    public var arsenalIsVertical: Bool { height >= 540 }
}

extension EnvironmentValues {
    @Entry public var battleHUDMetrics = BattleHUDMetrics.standard
}
#endif
