import BathtubArena
import BathtubEngine
import SpriteKit

/// The app's arena. Everything about how the tub is composed and drawn now
/// lives in `ArenaScene`, shared with the Messages extension so both surfaces
/// show the identical board; this subclass only binds it to `MatchViewModel`
/// and the app's audio.
final class BattleScene: ArenaScene, BattleSceneRendering {
    weak var viewModel: MatchViewModel? {
        didSet { installInputHandlers() }
    }

    override func didMove(to view: SKView) {
        ArenaAudio.handler = { SoundService.shared.play(GameSound(arena: $0)) }
        installInputHandlers()
        super.didMove(to: view)
    }

    /// Pulls fresh state rather than redrawing the last snapshot — the view
    /// model is the source of truth while a match is live.
    override func refreshBoards() {
        guard let viewModel else { return }
        render(
            enemy: viewModel.enemyView,
            own: viewModel.ownBoard,
            enemySkin: FleetSkin.withID(viewModel.enemyFleetID),
            ownSkin: FleetSkin.withID(viewModel.playerFleetID)
        )
    }

    /// Post-game reveal: draw the rival's board with every ship visible.
    func revealEnemyFleet() {
        guard let viewModel else { return }
        revealEnemyFleet(viewModel.enemyFullBoard, skin: FleetSkin.withID(viewModel.enemyFleetID))
    }

    private func installInputHandlers() {
        targetingPreview = { [weak self] cell in
            guard let viewModel = self?.viewModel,
                  viewModel.turnState == .playerTargeting,
                  viewModel.selectedShot.spec.needsTarget
            else { return nil }
            return (viewModel.previewFootprint(at: cell), viewModel.isValidTarget(cell))
        }
        onSelectCell = { [weak self] cell in
            self?.viewModel?.handleTap(at: cell)
        }
    }
}

private extension GameSound {
    /// Maps the arena module's host-neutral effects onto the app's sound bank.
    init(arena: ArenaSound) {
        switch arena {
        case .cannon: self = .cannon
        case .explosion: self = .explosion
        case .splash: self = .splash
        case .reveal: self = .reveal
        case .parrot: self = .parrot
        case .sunk: self = .sunk
        }
    }
}
