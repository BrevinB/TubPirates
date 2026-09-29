#if canImport(UIKit)
import BathtubEngine
import SwiftUI

/// The battle screen's chrome, floating over the arena.
///
/// The rival's name-plate and fleet bar top-left with a quit control beneath
/// them, yours top-right, a parchment banner between, the arsenal bottom-right.
/// Both hosts draw *this* view rather than each assembling the same pieces in
/// their own order, which is what makes the Messages battle and the app's match
/// screen identical by construction instead of by careful copying.
///
/// The slots are where the two genuinely differ: the app puts a Leave button
/// and a chat bubble in the footers and never needs a commit button, while
/// Messages puts Forfeit in the rival footer and a Fire button bottom-left,
/// because a turn there has to be staged before it is sent.
public struct BattleHUDView<
    Center: View,
    RivalFooter: View,
    LocalFooter: View,
    Below: View,
    Arsenal: View,
    Commit: View
>: View {
    public struct Captain {
        let imageName: String
        let name: String
        let highlighted: Bool

        public init(imageName: String, name: String, highlighted: Bool) {
            self.imageName = imageName
            self.name = name
            self.highlighted = highlighted
        }
    }

    let rival: Captain
    let local: Captain
    let rivalFleet: [FleetBarView.ShipStatus]
    let localFleet: [FleetBarView.ShipStatus]
    let metrics: BattleHUDMetrics

    /// Between the two name-plates: the status banner, or whoever is talking.
    let center: Center
    /// Pins the centre column's width. The app leaves this free so a speech
    /// pill can size to its line; a Messages sheet fixes it, because there the
    /// banner text changes on every turn and the fleet bars either side were
    /// jumping as it did.
    var centerWidth: CGFloat?
    /// Under the rival's fleet bar — Leave in the app, Forfeit in Messages.
    let rivalFooter: RivalFooter
    /// Under your own fleet bar — the chat bubble in the app.
    let localFooter: LocalFooter
    /// Under the whole top band, full width. Messages puts the turn read-back
    /// here; the app has nothing to say, because you watched it happen.
    let below: Below
    /// Bottom-right, at the app's own inset.
    let arsenal: Arsenal
    /// Bottom-left. Messages only.
    let commit: Commit
    /// Whether to keep the arsenal rail's width clear for the commit button.
    /// False once the battle is over and the rail has stowed itself, so the
    /// rematch button can use the whole width instead of truncating.
    var reservesArsenalGap: Bool

    public init(
        rival: Captain,
        local: Captain,
        rivalFleet: [FleetBarView.ShipStatus],
        localFleet: [FleetBarView.ShipStatus],
        metrics: BattleHUDMetrics = .standard,
        centerWidth: CGFloat? = nil,
        reservesArsenalGap: Bool = true,
        @ViewBuilder center: () -> Center,
        @ViewBuilder rivalFooter: () -> RivalFooter = { EmptyView() },
        @ViewBuilder localFooter: () -> LocalFooter = { EmptyView() },
        @ViewBuilder below: () -> Below = { EmptyView() },
        @ViewBuilder arsenal: () -> Arsenal = { EmptyView() },
        @ViewBuilder commit: () -> Commit = { EmptyView() }
    ) {
        self.rival = rival
        self.local = local
        self.rivalFleet = rivalFleet
        self.localFleet = localFleet
        self.metrics = metrics
        self.centerWidth = centerWidth
        self.reservesArsenalGap = reservesArsenalGap
        self.center = center()
        self.rivalFooter = rivalFooter()
        self.localFooter = localFooter()
        self.below = below()
        self.arsenal = arsenal()
        self.commit = commit()
    }

    public var body: some View {
        VStack(spacing: 6) {
            topBand
            below
            Spacer(minLength: 0)
        }
        // The arsenal and the commit button are bottom-anchored overlays, so
        // they never share vertical space with the top band: on a squat screen
        // the stacked total could exceed the height when a speech bubble
        // showed, and the squeeze truncated the HUD name labels to one line.
        .overlay(alignment: .bottom) {
            bottomBand
        }
    }

    /// The arsenal and the commit button.
    ///
    /// On a full screen the arsenal is a vertical rail hugging the trailing
    /// edge, exactly where the app puts it. A short Messages sheet cannot hold
    /// six stacked icons *and* the top band, so below `arsenalIsVertical` the
    /// rail lies down along the bottom — the same panel and the same icons,
    /// turned through ninety degrees rather than shrunk into illegibility.
    ///
    /// The commit button is raised clear of the player's own beached fleet and
    /// inset from the rail. Pinned to the bottom-leading corner, as it first
    /// was, it sat directly on top of that board.
    @ViewBuilder
    private var bottomBand: some View {
        if metrics.arsenalIsVertical {
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    arsenal
                }
                .stageRow(metrics)
                .padding(.trailing, 6)
                .padding(.bottom, metrics.bottomInset)

                // In the gap the arena leaves at the bottom: right of the
                // beached fleet, left of the rail, below the enemy diamond's
                // bottom tip. Raised above the fleet only when that gap is too
                // narrow to hold the button.
                HStack(spacing: 0) {
                    commit
                    Spacer(minLength: 0)
                }
                .padding(.leading, metrics.commitFitsBesideFleet ? metrics.ownFleetTrailingInset : metrics.gutter)
                .padding(.trailing, reservesArsenalGap ? metrics.arsenalRailWidth : metrics.gutter)
                .stageRow(metrics)
                .padding(.bottom, metrics.commitFitsBesideFleet ? metrics.bottomInset : metrics.ownFleetClearance)
            }
        } else {
            // Laid down, the rail owns the bottom strip. The band is inset past
            // the beached fleet so the strip sits beside it rather than on it.
            VStack(alignment: .trailing, spacing: 8) {
                // Trailing-aligned: at this height the enemy diamond has
                // narrowed to its bottom vertex around the stage's centre, so
                // the far side is clear. Centred, the button sat on the last
                // couple of rows and you could not aim at them.
                commit
                    .frame(maxWidth: reservesArsenalGap ? 150 : .infinity)
                arsenal
            }
            .padding(.leading, metrics.ownFleetTrailingInset)
            .padding(.trailing, metrics.gutter)
            .stageRow(metrics)
            .padding(.bottom, metrics.bottomInset)
        }
    }

    private var topBand: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: metrics.columnSpacing) {
                PlayerHUDView(
                    imageName: rival.imageName,
                    name: rival.name,
                    highlighted: rival.highlighted,
                    side: metrics.portraitSide
                )
                FleetBarView(
                    fleet: rivalFleet,
                    alignment: .leading,
                    segmentHeight: metrics.fleetSegmentHeight
                )
                rivalFooter
            }

            Spacer(minLength: 4)
            center
                .frame(width: centerWidth)
            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: metrics.columnSpacing) {
                PlayerHUDView(
                    imageName: local.imageName,
                    name: local.name,
                    highlighted: local.highlighted,
                    side: metrics.portraitSide
                )
                FleetBarView(
                    fleet: localFleet,
                    alignment: .trailing,
                    segmentHeight: metrics.fleetSegmentHeight
                )
                localFooter
            }
        }
        .padding(.horizontal, metrics.gutter)
        // In a wide window the arena letterboxes (see `ArenaScene.maxStageAspect`);
        // the HUD tracks it instead of flinging the portraits into the far
        // corners of an iPad.
        .stageColumn()
    }
}
extension View {
    /// Pins a row to the letterboxed arena stage and centers it, so bottom
    /// chrome lines up with the boards rather than with the screen edges.
    fileprivate func stageRow(_ metrics: BattleHUDMetrics) -> some View {
        frame(width: metrics.stageWidth)
            .frame(maxWidth: .infinity)
    }
}
#endif
