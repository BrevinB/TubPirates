// The arena is a UIKit/SpriteKit surface; the package also builds for macOS
// so the engine's tests can run there, where this target has nothing to offer.
#if canImport(UIKit)
import BathtubEngine
import BathtubUI
import SpriteKit
/// The bathtub arena: tub backdrop, the big enemy diamond in the water, your
/// own board beached in the suds bottom-left, and your cannon below.
///
/// This used to live entirely in the app's `BattleScene`, which is why the
/// Messages extension had to invent a second, worse-looking board. Everything
/// host-neutral now lives here so both surfaces render the identical arena;
/// the app subclasses it to wire up `MatchViewModel`, and the extension
/// subclasses it to drive turns from a message payload.
///
/// - Important: Subclasses must **not** declare initializers.
///
/// `SKScene.init()` is an Objective-C initializer that dispatches back through
/// `-initWithSize:`. A Swift subclass that declares any designated initializer
/// (including `override init()` or `required init?(coder:)`) stops inheriting
/// `init(size:)`, and the compiler puts a trapping stub in its place — so
/// `ArenaScene()` walks straight into `fatal error: use of unimplemented
/// initializer 'init(size:)'`. It costs a crash at construction time, before
/// anything is drawn, which in the Messages extension looked like a blank grey
/// sheet rather than a crash.
///
/// Configure in `didMove(to:)` before calling `super`, the way `BattleScene`
/// and `MessageArenaScene` both do. Anything that must be set before the first
/// layout (the pixel ceilings below) belongs there.
@MainActor
open class ArenaScene: SKScene {
    public let enemyBoard = BoardNode()
    public let ownBoard = BoardNode()

    private let background = SKSpriteNode()
    /// Pixel box the current backdrop texture was prepared for.
    private var backdropPixelSize: CGSize = .zero

    /// Ceiling on the backdrop texture's longest edge. The app leaves this
    /// open; the Messages extension pins it low because its memory budget is a
    /// fraction of an app's and the full-resolution tub alone blew past it.
    public var backdropMaxPixelDimension: CGFloat = .greatestFiniteMagnitude

    /// Same idea for the cannon and other props.
    public var propMaxPixelDimension: CGFloat = .greatestFiniteMagnitude
    private let suds = SKNode()
    private let cannon = SKSpriteNode()
    private var didSetUp = false

    /// Last state handed to `render` — lets `refreshBoards` redraw without the
    /// host having to hold onto it.
    private var lastEnemyView: AttackerView?
    private var lastOwnBoard: Board?

    // MARK: - Input hooks

    /// Footprint to highlight while a finger is down, or nil to show nothing.
    public var targetingPreview: ((Coordinate) -> (cells: [Coordinate], valid: Bool)?)?
    /// Called when a tap lifts inside the enemy board.
    public var onSelectCell: ((Coordinate) -> Void)?

    // MARK: - Lifecycle

    open override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.13, green: 0.35, blue: 0.55, alpha: 1)
        if !didSetUp {
            didSetUp = true
            background.zPosition = -10
            addChild(background)
            addChild(enemyBoard)
            suds.zPosition = -1
            addChild(suds)
            addChild(ownBoard)
            cannon.zPosition = 30
            addChild(cannon)
        }
        layout()
        sceneDidBecomeReady()
    }

    open override func didChangeSize(_ oldSize: CGSize) {
        guard didSetUp else { return }
        layout()
    }

    /// Called once the scene is laid out and ready to be filled with state.
    open func sceneDidBecomeReady() {
        refreshBoards()
    }

    public var isPresented: Bool {
        didSetUp && view != nil && size.width > 0 && size.height > 0
    }

    // MARK: - Layout

    /// Widest the arena composition is allowed to get, as a fraction of the
    /// window's height. The layout is portrait by design — the enemy diamond
    /// on top, your board beached bottom-left, cannon below — so in a wide
    /// window (iPad landscape, a Split View pane) the stage letterboxes and
    /// centers instead of stretching the diamond off the top and bottom.
    /// Every portrait phone and iPad is narrower than this, so they are
    /// unaffected.
    ///
    /// Defined in `ArenaStageGeometry` so the battle HUD can keep its controls
    /// off the boards this places.
    public static let maxStageAspect = ArenaStageGeometry.maxStageAspect

    private func layout() {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }

        updateBackdrop(for: CGSize(width: w, height: h))
        if cannon.texture == nil {
            cannon.texture = ArenaTextures.sprite("player_cannon", maxDimension: propMaxPixelDimension)
        }

        // Tub art still fills the whole window (crops as needed) — only the
        // playable composition is letterboxed.
        if let texture = background.texture {
            let scale = max(w / texture.size().width, h / texture.size().height)
            background.size = CGSize(width: texture.size().width * scale, height: texture.size().height * scale)
        }
        background.position = CGPoint(x: w / 2, y: h / 2)

        let surface = CGSize(width: w, height: h)
        let stage = ArenaStageGeometry.stage(in: surface)
        // Left edge of the centered stage; everything below is placed inside it.
        let x0 = ArenaStageGeometry.stageOriginX(in: surface)

        // Enemy board: large diamond kept inside the tub's water circle —
        // sized and lowered toward the circle's center so the tips stay wet.
        enemyBoard.setScale(stage * ArenaStageGeometry.enemyBoardDiagonalFraction / BoardNode.baseDiagonal)
        enemyBoard.position = CGPoint(
            x: x0 + stage / 2,
            y: h * ArenaStageGeometry.enemyBoardCenterYFraction
        )

        // Own board: small diamond beached in the suds at the bottom-left,
        // off the tub's water so it reads as "your side of the bathroom".
        ownBoard.setScale(stage * ArenaStageGeometry.ownBoardDiagonalFraction / BoardNode.baseDiagonal)
        ownBoard.position = CGPoint(
            x: x0 + stage * ArenaStageGeometry.ownBoardCenterXFraction,
            y: h * ArenaStageGeometry.ownBoardCenterYFraction
        )
        rebuildSuds(
            around: ownBoard.position,
            boardHalfDiagonal: stage * ArenaStageGeometry.ownBoardHalfDiagonalFraction
        )

        // Your cannon: bottom-center-right, barrel aimed up at the enemy board.
        let cannonAspect = cannon.texture.map { $0.size().width / $0.size().height } ?? 0.7
        let cannonHeight = stage * 0.24
        cannon.size = CGSize(width: cannonHeight * cannonAspect, height: cannonHeight)
        cannon.position = CGPoint(x: x0 + stage * 0.60, y: h * 0.075)
        cannon.zRotation = 0
    }

    /// Loads the backdrop at the resolution this surface actually needs.
    private func updateBackdrop(for size: CGSize) {
        let scale = view?.window?.screen.scale ?? view?.contentScaleFactor ?? 2
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        guard pixels != backdropPixelSize else { return }
        if let texture = ArenaTextures.backdrop(
            "tub_background",
            covering: pixels,
            maxDimension: backdropMaxPixelDimension
        ) {
            backdropPixelSize = pixels
            background.texture = texture
        }
    }

    /// A cartoon soap-foam blob the player's board sits in.
    private func rebuildSuds(around center: CGPoint, boardHalfDiagonal radius: CGFloat) {
        suds.removeAllChildren()
        var rng = SeededRNG(seed: 7) // stable layout across relayouts
        for _ in 0..<26 {
            let angle = CGFloat(Double.random(in: 0..<(2 * .pi), using: &rng))
            let distance = CGFloat(Double.random(in: 0.35...1.02, using: &rng)) * radius
            let bubbleRadius = CGFloat(Double.random(in: 0.16...0.34, using: &rng)) * radius
            let bubble = SKShapeNode(circleOfRadius: bubbleRadius)
            bubble.fillColor = SKColor(white: 1, alpha: 0.92)
            bubble.strokeColor = SKColor(red: 0.75, green: 0.88, blue: 0.97, alpha: 0.9)
            bubble.lineWidth = 2
            bubble.position = CGPoint(x: center.x + cos(angle) * distance,
                                      y: center.y + sin(angle) * distance * 0.8)
            suds.addChild(bubble)
        }
        // Filled core under the board itself.
        let core = SKShapeNode(circleOfRadius: radius * 0.95)
        core.fillColor = SKColor(white: 1, alpha: 0.92)
        core.strokeColor = .clear
        core.position = center
        suds.addChild(core)
    }

    // MARK: - Cannon

    /// Muzzle tip in scene coordinates for the cannon's current rotation.
    private var cannonMuzzle: CGPoint {
        let barrel = cannon.size.height * 0.5
        return CGPoint(
            x: cannon.position.x - sin(cannon.zRotation) * barrel,
            y: cannon.position.y + cos(cannon.zRotation) * barrel
        )
    }

    /// Swings the barrel toward a target, fires with recoil + smoke, and
    /// returns the muzzle point the projectile should launch from.
    private func fireCannon(at target: CGPoint) async -> CGPoint {
        // Art points up: rotation 0 = straight up.
        let dx = target.x - cannon.position.x
        let dy = target.y - cannon.position.y
        let aim = atan2(dy, dx) - .pi / 2
        await cannon.run(.rotate(toAngle: aim, duration: 0.15, shortestUnitArc: true))

        let smoke = ParticleFactory.smoke()
        smoke.numParticlesToEmit = 8
        smoke.particleLifetime = 0.5
        smoke.position = cannonMuzzle
        addChild(smoke)

        // Fire-and-forget recoil (completion form selects the sync SKNode.run,
        // so the cannonball launches while the carriage is still kicking back).
        let recoil = CGVector(dx: sin(aim) * 10, dy: -cos(aim) * 10)
        cannon.run(.sequence([
            .move(by: recoil, duration: 0.05),
            .move(by: CGVector(dx: -recoil.dx, dy: -recoil.dy), duration: 0.12),
        ]), completion: {})
        return cannonMuzzle
    }

    /// Rests the barrel back to straight up after the volley.
    private func restCannon() {
        cannon.run(.rotate(toAngle: 0, duration: 0.25, shortestUnitArc: true))
    }

    // MARK: - Rendering

    /// Draws both halves of the battle from the seat of the local player.
    public func render(
        enemy view: AttackerView,
        own board: Board,
        enemySkin: FleetSkin = .classic,
        ownSkin: FleetSkin = .classic,
        withholding pending: MoveResolution? = nil,
        withheldOnEnemyBoard: Bool = true
    ) {
        lastEnemyView = view
        lastOwnBoard = board
        enemyBoard.fleetSkin = enemySkin
        ownBoard.fleetSkin = ownSkin

        // A host that receives already-resolved turns (Messages) hands us the
        // move it is about to play, so the board can be drawn as it looked
        // *before* that move and the animation can reveal it.
        let cells = Set(pending?.cellResults.map(\.coordinate) ?? [])
        var ships = Set((pending?.sunkShips ?? []).map(\.id))
        if let revealed = pending?.revealedShip { ships.insert(revealed.id) }

        enemyBoard.update(
            enemy: view,
            withholding: withheldOnEnemyBoard ? cells : [],
            withholdingShips: withheldOnEnemyBoard ? ships : []
        )
        ownBoard.update(
            own: board,
            withholding: withheldOnEnemyBoard ? [] : cells,
            withholdingShips: withheldOnEnemyBoard ? [] : ships
        )
    }

    /// Post-game reveal: draw the rival's board with every ship visible
    /// (own-board rendering shows hulls plus the shot marks already made).
    public func revealEnemyFleet(_ board: Board, skin: FleetSkin = .classic) {
        enemyBoard.fleetSkin = skin
        enemyBoard.update(own: board)
    }

    /// Redraws from whatever was last rendered. Hosts that own live state
    /// override this to pull fresh values instead.
    open func refreshBoards() {
        if let lastEnemyView { enemyBoard.update(enemy: lastEnemyView) }
        if let lastOwnBoard { ownBoard.update(own: lastOwnBoard) }
    }

    // MARK: - Turn playback

    public func playResolution(_ resolution: MoveResolution, onEnemyBoard: Bool) async {
        let board = onEnemyBoard ? enemyBoard : ownBoard
        // The rival fires from off-screen above; the player's shots come from the cannon.
        let rivalLaunch = CGPoint(x: size.width / 2, y: size.height * 1.02)

        switch resolution.move.shot.spec.effect {
        case .damage:
            for result in resolution.cellResults {
                let target = board.scenePosition(of: result.coordinate, in: self)
                let launch = onEnemyBoard ? await fireCannon(at: target) : rivalLaunch
                await ShotAnimator.cannonball(from: launch, to: target, in: self, outcome: result.outcome)
                await board.animate(result: result)
            }
            if onEnemyBoard { restCannon() }
        case .revealArea:
            if let center = resolution.move.target {
                await ShotAnimator.parrot(over: board.scenePosition(of: center, in: self), in: self)
            }
            for result in resolution.cellResults {
                await board.animate(result: result)
            }
        case .revealShip:
            if let ship = resolution.revealedShip {
                let mid = ship.cells[ship.cells.count / 2]
                let target = board.scenePosition(of: mid, in: self)
                let launch = onEnemyBoard ? await fireCannon(at: target) : rivalLaunch
                await ShotAnimator.flare(from: launch, to: target, in: self)
                if onEnemyBoard { restCannon() }
            }
            for result in resolution.cellResults {
                await board.animate(result: result)
            }
        }

        if !resolution.sunkShips.isEmpty {
            ArenaAudio.play(.sunk)
            for ship in resolution.sunkShips {
                let mid = ship.cells[ship.cells.count / 2]
                let smoke = ParticleFactory.smoke()
                smoke.numParticlesToEmit = 30
                smoke.position = board.scenePosition(of: mid, in: self)
                addChild(smoke)
            }
            let shake = SKAction.sequence([
                SKAction.moveBy(x: 7, y: 0, duration: 0.05),
                SKAction.moveBy(x: -14, y: 0, duration: 0.08),
                SKAction.moveBy(x: 7, y: 0, duration: 0.05),
            ])
            await board.run(shake)
        }
        refreshBoards()
    }

    // MARK: - Input (targeting with drag preview)

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePreview(touches)
    }

    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePreview(touches)
    }

    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        enemyBoard.clearPreview()
        guard let touch = touches.first else { return }
        if let cell = enemyBoard.cell(atLocal: touch.location(in: enemyBoard)) {
            onSelectCell?(cell)
        }
    }

    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        enemyBoard.clearPreview()
    }

    private func updatePreview(_ touches: Set<UITouch>) {
        guard let touch = touches.first,
              let cell = enemyBoard.cell(atLocal: touch.location(in: enemyBoard)),
              let preview = targetingPreview?(cell)
        else {
            enemyBoard.clearPreview()
            return
        }
        enemyBoard.showPreview(cells: preview.cells, valid: preview.valid)
    }
}
#endif
