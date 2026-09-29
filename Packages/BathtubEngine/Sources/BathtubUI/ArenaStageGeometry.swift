#if canImport(UIKit)
import CoreGraphics

/// Where the arena puts its pieces, as fractions of the surface.
///
/// `ArenaScene` lays the tub out from these, and the battle HUD keeps its
/// controls clear of them. They live here, in the one target both sides can
/// see, so a control can never drift on top of the board it is meant to sit
/// beside — which is exactly what happened when the Fire button and the staged
/// message hint were pinned to the bottom-left corner, directly over the
/// player's own beached fleet.
public enum ArenaStageGeometry {
    /// Widest the playable composition is allowed to get, as a fraction of
    /// height. The layout is portrait by design, so a wide window letterboxes
    /// and centers instead of stretching the diamond off the top and bottom.
    public static let maxStageAspect: CGFloat = 0.75

    /// Enemy diamond: centered, large, sitting in the tub's water.
    public static let enemyBoardDiagonalFraction: CGFloat = 0.96
    public static let enemyBoardCenterYFraction: CGFloat = 0.55

    /// Own board: a small diamond beached in the suds at the bottom-left.
    public static let ownBoardDiagonalFraction: CGFloat = 0.34
    public static let ownBoardHalfDiagonalFraction: CGFloat = 0.17
    public static let ownBoardCenterXFraction: CGFloat = 0.235
    public static let ownBoardCenterYFraction: CGFloat = 0.135

    /// The letterboxed stage width for a surface.
    public static func stage(in size: CGSize) -> CGFloat {
        min(size.width, size.height * maxStageAspect)
    }

    /// Left edge of the centered stage.
    public static func stageOriginX(in size: CGSize) -> CGFloat {
        (size.width - stage(in: size)) / 2
    }

    /// How far up from the bottom the player's own board reaches, plus a
    /// little air. A bottom-anchored control inset by at least this much
    /// clears the fleet instead of sitting on it.
    public static func ownBoardTopInset(in size: CGSize) -> CGFloat {
        let stage = stage(in: size)
        return size.height * ownBoardCenterYFraction
            + stage * ownBoardHalfDiagonalFraction
            + 10
    }

    /// The right edge of the player's own board, in points from the leading
    /// edge of the surface.
    public static func ownBoardTrailingEdge(in size: CGSize) -> CGFloat {
        stageOriginX(in: size)
            + stage(in: size) * (ownBoardCenterXFraction + ownBoardHalfDiagonalFraction)
    }
}
#endif
