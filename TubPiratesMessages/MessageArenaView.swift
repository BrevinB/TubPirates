import BathtubArena
import BathtubEngine
import BathtubUI
import SpriteKit
import SwiftUI

/// The app's arena, hosted in Messages.
///
/// This is the same `ArenaScene` the main game runs — tub backdrop, the big
/// enemy diamond in the water, your own board beached in the suds, your cannon
/// below. The extension previously drew its own flat SwiftUI grid, which is
/// why it never looked like the game and could only show one board at a time.
struct MessageArenaView: View {
    let model: MessagesExtensionModel
    /// Called when a tap lands on a square that makes a legal move — the tap
    /// *is* the shot, exactly as it is in the app.
    let fire: () -> Void

    @State private var scene = MessageArenaScene()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .onAppear { sync(animate: false) }
            .onChange(of: model.displayRevision) { sync(animate: true) }
            .onChange(of: model.isLocalTurn) { scene.isAiming = model.isLocalTurn }
            .onDisappear { ArenaTextures.purge() }
            .accessibilityHidden(true)
    }

    private func sync(animate: Bool) {
        scene.model = model
        scene.onFire = fire
        scene.isAiming = model.isLocalTurn
        scene.apply(
            enemy: model.attackerView,
            own: model.ownBoard,
            // Each captain's toys are their own: the payload carries both
            // fleet ids, so a rival who bought the Ducky Squadron sinks in
            // rubber ducks here exactly as they would in the app.
            enemySkin: FleetSkin.withID(model.rivalAppearance.fleetID),
            ownSkin: FleetSkin.withID(model.localAppearance.fleetID),
            resolution: model.latestResolution,
            resolutionWasLocal: model.resolutionWasLocal,
            revision: model.displayRevision,
            animate: animate
        )
    }
}

@MainActor
final class MessageArenaScene: ArenaScene {
    weak var model: MessagesExtensionModel?
    /// Gates the drag preview without a full re-render.
    var isAiming = false
    /// Hands a committed shot to Messages.
    var onFire: (() -> Void)?

    /// Revision of the last payload whose move has been played, so reopening a
    /// thread doesn't replay a shot the captain already watched.
    private var playedRevision = -1
    private var isPlaying = false
    /// A turn that arrived while the previous one was still animating.
    private var pending: (MoveResolution?, Bool, Int, Bool)?

    /// Configured in `didMove(to:)`, not in an initializer — deliberately.
    ///
    /// `SKScene.init()` is an Objective-C initializer that dispatches back
    /// through `-initWithSize:`. A Swift subclass that overrides `init()`
    /// therefore stops inheriting `init(size:)`, and the compiler leaves a
    /// trapping stub in its place, which `super.init()` then walks straight
    /// into: `fatal error: use of unimplemented initializer 'init(size:)'`.
    /// That killed the extension the instant the battle screen was built — the
    /// grey Messages sheet was this crash. `BattleScene` in the app has always
    /// configured itself here for the same reason; this now matches it.
    private var didConfigure = false

    override func didMove(to view: SKView) {
        configureIfNeeded()
        super.didMove(to: view)
    }

    private func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        scaleMode = .resizeFill
        // ~1024x1371 instead of 1792x2400: 5.6MB of texture rather than 17MB.
        backdropMaxPixelDimension = 1024
        // The largest ship spans five cells — a few hundred points at most.
        enemyBoard.spriteMaxPixelDimension = 512
        ownBoard.spriteMaxPixelDimension = 512
        propMaxPixelDimension = 512
        targetingPreview = { [weak self] cell in
            guard let self, let model, isAiming, !model.isSending,
                  model.selectedShot.spec.needsTarget
            else { return nil }
            let footprint = model.footprint(at: cell)
            return (footprint, model.isValidTarget(cell))
        }
        onSelectCell = { [weak self] cell in
            guard let self, let model else { return }
            // Aiming and firing are one gesture: lifting your finger on a legal
            // square sends the turn.
            if model.selectTarget(cell) {
                TubHaptics.impact(.medium)
                onFire?()
            } else {
                TubHaptics.notify(.warning)
            }
        }
    }

    override func sceneDidBecomeReady() {
        configureIfNeeded()
        super.sceneDidBecomeReady()
        model.map { model in
            if let enemy = model.attackerView, let own = model.ownBoard {
                render(
                    enemy: enemy,
                    own: own,
                    enemySkin: FleetSkin.withID(model.rivalAppearance.fleetID),
                    ownSkin: FleetSkin.withID(model.localAppearance.fleetID)
                )
            }
        }
    }

    func apply(
        enemy: AttackerView?,
        own: Board?,
        enemySkin: FleetSkin,
        ownSkin: FleetSkin,
        resolution: MoveResolution?,
        resolutionWasLocal: Bool,
        revision: Int,
        animate: Bool
    ) {
        // `SpriteView`'s `onAppear` can beat the scene's `didMove(to:)`, and
        // rendering before the pixel ceilings are set would decode the toy art
        // at full size — the one thing this extension's memory budget cannot
        // survive, and `ArenaTextures` would then cache it.
        configureIfNeeded()
        guard let enemy, let own else { return }

        // Never repaint while a shot is in the air. Drawing the resolved board
        // mid-flight put the ✕ on the square before the cannonball reached it.
        // Park the update and replay it once the volley lands.
        guard !isPlaying else {
            pending = (resolution, resolutionWasLocal, revision, animate)
            return
        }

        let willPlay = animate
            && isPresented
            && resolution != nil
            && revision > playedRevision

        // When the shot is about to be animated, draw the board as it looked
        // before it: `playResolution` is what reveals the marks.
        render(
            enemy: enemy,
            own: own,
            enemySkin: enemySkin,
            ownSkin: ownSkin,
            withholding: willPlay ? resolution : nil,
            withheldOnEnemyBoard: resolutionWasLocal
        )

        guard willPlay, let resolution else {
            playedRevision = max(playedRevision, revision)
            return
        }
        playedRevision = revision

        isPlaying = true
        Task { @MainActor in
            await playResolution(resolution, onEnemyBoard: resolutionWasLocal)
            isPlaying = false
            if let pending, let model {
                self.pending = nil
                apply(
                    enemy: model.attackerView,
                    own: model.ownBoard,
                    enemySkin: FleetSkin.withID(model.rivalAppearance.fleetID),
                    ownSkin: FleetSkin.withID(model.localAppearance.fleetID),
                    resolution: pending.0,
                    resolutionWasLocal: pending.1,
                    revision: pending.2,
                    animate: pending.3
                )
            }
        }
    }
}
