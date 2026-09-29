import BathtubArena
import BathtubEngine
import BathtubUI
import Foundation
import UIKit
import MessageGameCore
import Observation

@Observable
@MainActor
final class MessagesExtensionModel {
    var isExpanded = false
    private(set) var statusMessage = String(localized: "Place your fleet, then challenge a friend.")
    /// Written straight by the shared placement view.
    var placementBoard: Board
    private(set) var selectedTarget: Coordinate?
    private(set) var selectedShot: ShotType = .cannon
    private(set) var shotOrientation: Orientation = .horizontal
    /// A turn handed to Messages but not yet confirmed sent.
    private(set) var isSending = false
    private(set) var screen = MessageScreen.newChallenge
    private(set) var loadedEnvelope: MessageGameEnvelope?
    private(set) var localSeat: PlayerID?
    /// The move being sent right now. The UI reads through it so the board
    /// plays the shot the instant you fire, rather than waiting on the network.
    private(set) var pendingEnvelope: MessageGameEnvelope?
    private let revisionStore = MessageRevisionStore()
    /// The challenge we've already dealt a starting fleet for, so reopening it
    /// never scrubs what the captain arranged.
    private var seededChallengeID: UUID?

    init() {
        var generator = SystemRandomNumberGenerator()
        placementBoard = Board.randomlyPlaced(using: &generator)
    }

    var isFleetComplete: Bool {
        placementBoard.ships.count == ShipKind.standardFleet.count
    }

    /// Everything the battle UI reads goes through here: the move in flight if
    /// there is one, otherwise the message that is actually on screen.
    var displayEnvelope: MessageGameEnvelope? { pendingEnvelope ?? loadedEnvelope }

    var battleState: GameState? {
        guard let displayEnvelope, case .battle(let state) = displayEnvelope.content else { return nil }
        return state
    }

    var isLocalTurn: Bool {
        guard let state = battleState, let localSeat, !battleIsFinished else { return false }
        return state.currentPlayer == localSeat
    }

    var attackerView: AttackerView? {
        guard let state = battleState, let localSeat else { return nil }
        return state.attackerView(of: localSeat.opponent)
    }

    var ownBoard: Board? {
        guard let state = battleState, let localSeat else { return nil }
        return state.boards[localSeat]
    }

    var availableShots: [ShotType] {
        guard let state = battleState, let localSeat else { return [] }
        return state.availableShots(for: localSeat)
    }

    // MARK: - Captains

    /// This device's captain, as the app knows them. Read through the App
    /// Group because the extension cannot see the app's own profile.
    var localAppearance: SharedAppGroup.Appearance { SharedAppGroup.appearance }

    /// The rival's captain, as their device published it into the payload.
    var rivalAppearance: SharedAppGroup.Appearance {
        guard let localSeat else { return .default }
        return displayEnvelope?.appearance(of: localSeat.opponent) ?? .default
    }

    /// Messages hands us opaque participant identifiers, never names — so the
    /// name-plates say the only two things that are true for both readers.
    var localName: String { String(localized: "You") }
    var rivalName: String { String(localized: "Yer Rival") }

    /// Which name-plate wears the orange ring, matching the app's HUD.
    var highlightedSeat: PlayerID? {
        guard !battleIsFinished else { return displayEnvelope?.winner }
        return battleState?.currentPlayer
    }

    /// The toys this captain's fleet is drawn from, for the placement board.
    func shipImageName(_ kind: ShipKind) -> String {
        FleetSkin.withID(localAppearance.fleetID).textureName(for: kind)
    }

    /// The arsenal in the app's fixed panel order. Every cannon is granted for
    /// a Messages battle, so a slot is either loaded or spent — there is no
    /// doubloon refill out here.
    var arsenalSlots: [ArsenalSlot] {
        guard let state = battleState, let localSeat else { return [] }
        let order: [ShotType] = [.cannon, .parrotScout, .bigShot, .flare, .chainShot, .fireworks]
        return order.map { shot in
            let remaining = state.remainingUses(of: shot, for: localSeat)
            return ArsenalSlot(
                shot: shot,
                remaining: remaining,
                state: (remaining ?? 1) > 0 ? .ready : .spent
            )
        }
    }

    /// Identity of the state on screen — the arena replays a move exactly once.
    var displayRevision: Int { displayEnvelope?.revision ?? -1 }

    /// Cells the selected shot would cover if aimed here, for the drag preview.
    func footprint(at coordinate: Coordinate) -> [Coordinate] {
        selectedShot.spec.pattern(coordinate, shotOrientation).filter(\.isValid)
    }

    /// Whether firing the selected shot here would be a legal move.
    func isValidTarget(_ coordinate: Coordinate) -> Bool {
        guard let state = battleState, let localSeat else { return false }
        let move = Move(
            player: localSeat,
            shot: selectedShot,
            target: selectedShot.spec.needsTarget ? coordinate : nil,
            orientation: selectedShot.spec.needsOrientation ? shotOrientation : nil
        )
        return state.validate(move) == nil
    }

    /// Charges left for a shot, or `nil` when it is unlimited.
    func remainingUses(of shot: ShotType) -> Int? {
        guard let state = battleState, let localSeat else { return nil }
        return state.remainingUses(of: shot, for: localSeat)
    }

    /// Whether the armed shot is a legal move right now — i.e. whether a tap
    /// should fire it.
    var canFire: Bool {
        guard !isSending, isLocalTurn, let state = battleState, let localSeat else { return false }
        return state.validate(pendingMove(for: localSeat)) == nil
    }

    var battleIsFinished: Bool { displayEnvelope?.isFinished == true }

    var didLocalPlayerWin: Bool {
        guard let localSeat else { return false }
        return displayEnvelope?.winner == localSeat
    }

    /// The move that produced the state now on screen, whoever made it — the
    /// arena replays it, on whichever board it landed on.
    var latestResolution: MoveResolution? { displayEnvelope?.latestResolution }

    var resolutionWasLocal: Bool {
        guard let localSeat, let latestResolution else { return false }
        return latestResolution.move.player == localSeat
    }

    private static let columnLabels = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]

    var compactActionTitle: String {
        switch screen {
        case .newChallenge: String(localized: "Set Up Battle")
        case .challengeReceived: String(localized: "Answer Challenge")
        case .waitingForOpponent: String(localized: "View Fleet")
        case .battle: battleIsFinished ? String(localized: "View Result") : String(localized: "Open Battle")
        case .invalidMessage, .staleMessage: String(localized: "View Details")
        }
    }

    var backgroundArtworkName: String {
        switch screen {
        case .newChallenge, .challengeReceived: "placement_background"
        case .battle where battleIsFinished: didLocalPlayerWin ? "victory_background" : "defeat_background"
        case .waitingForOpponent, .battle, .invalidMessage, .staleMessage: "tub_background"
        }
    }

    func randomizePlacement() {
        var generator = SystemRandomNumberGenerator()
        placementBoard = Board.randomlyPlaced(using: &generator)
        TubHaptics.impact(.medium)
        statusMessage = String(localized: "New fleet generated.")
    }

    func makeChallengeEnvelope() throws -> MessageGameEnvelope {
        guard isFleetComplete else { throw MessageGameFlowError.incompleteFleet }
        return .newChallenge(board: placementBoard, appearance: localAppearance)
    }

    func makeJoinedBattleEnvelope() throws -> MessageGameEnvelope {
        guard let challenge = loadedEnvelope else { throw MessageGameFlowError.missingChallenge }
        guard localSeat == .two else { throw MessageGameFlowError.notSecondPlayer }
        guard isFleetComplete else { throw MessageGameFlowError.incompleteFleet }
        return try MessageGameFlow.join(challenge, with: placementBoard, appearance: localAppearance)
    }

    func makeTurnEnvelope() throws -> MessageGameEnvelope {
        guard let envelope = loadedEnvelope, let localSeat else { throw MessageGameFlowError.missingBattle }
        return try MessageGameFlow.play(
            selectedShot,
            target: selectedShot.spec.needsTarget ? selectedTarget : nil,
            orientation: selectedShot.spec.needsOrientation ? shotOrientation : nil,
            by: localSeat,
            in: envelope,
            appearance: localAppearance
        )
    }

    func makeForfeitEnvelope() throws -> MessageGameEnvelope {
        guard let envelope = loadedEnvelope, let localSeat else { throw MessageGameFlowError.missingBattle }
        return try MessageGameFlow.forfeit(envelope, by: localSeat)
    }

    func makeRematchEnvelope() -> MessageGameEnvelope {
        randomizePlacement()
        return .newChallenge(board: placementBoard, appearance: localAppearance)
    }

    func showNewChallenge() {
        loadedEnvelope = nil
        localSeat = nil
        screen = .newChallenge
        resetBattleSelection()
        clearStaging()
        statusMessage = String(localized: "Place your fleet, then challenge a friend.")
        MessagesAnalytics.send(.opened(screen: "newChallenge"))
    }

    func load(envelope: MessageGameEnvelope, authoredLocally: Bool) throws {
        if revisionStore.isStale(envelope) { throw MessageGameFlowError.staleMessage }
        revisionStore.record(envelope)
        loadedEnvelope = envelope
        let seat = MessageGameFlow.localSeat(for: envelope, authoredLocally: authoredLocally)
        localSeat = seat
        resetBattleSelection()
        clearStaging()

        switch envelope.content {
        case .setup(let boards):
            if let localBoard = boards[seat] {
                placementBoard = localBoard
                screen = .waitingForOpponent
                statusMessage = String(localized: "Your fleet is ready. Waiting for your rival.")
            } else {
                // Seed a fleet the first time this challenge is opened, and
                // only then. `willBecomeActive` fires on every return to the
                // extension and `didSelect` on every tap of the bubble, so
                // randomizing here unconditionally scrubbed a hand-placed
                // fleet the moment the captain switched apps and came back.
                if seededChallengeID != envelope.gameID {
                    seededChallengeID = envelope.gameID
                    var generator = SystemRandomNumberGenerator()
                    placementBoard = Board.randomlyPlaced(using: &generator)
                }
                screen = .challengeReceived
                statusMessage = String(localized: "Challenge received. Place your fleet.")
            }
        case .battle(let state):
            screen = .battle
            if envelope.isFinished {
                statusMessage = didLocalPlayerWin ? String(localized: "Victory!") : String(localized: "The battle is over.")
            } else if state.currentPlayer == seat {
                statusMessage = String(localized: "Your turn — fire!")
            } else {
                statusMessage = String(localized: "Waiting for your rival's turn.")
            }
        }

        // Only a message someone else authored is a genuine open; reloading
        // our own just-sent update would double-count every turn.
        if !authoredLocally {
            MessagesAnalytics.send(.opened(screen: analyticsScreenName))
            if envelope.isFinished {
                MessagesAnalytics.send(.battleFinished(
                    won: didLocalPlayerWin,
                    byForfeit: envelope.forfeitedBy != nil
                ))
            }
        }
    }

    /// Stable, low-cardinality screen names for the analytics dashboard.
    private var analyticsScreenName: String {
        switch screen {
        case .newChallenge: "newChallenge"
        case .challengeReceived: "challengeReceived"
        case .waitingForOpponent: "waitingForOpponent"
        case .battle: battleIsFinished ? "battleFinished" : "battle"
        case .invalidMessage: "invalidMessage"
        case .staleMessage: "staleMessage"
        }
    }

    func selectShot(_ shot: ShotType) {
        guard availableShots.contains(shot), !isSending else { return }
        selectedShot = shot
        if !shot.spec.needsTarget { selectedTarget = nil }
        TubHaptics.impact(.light)
        statusMessage = shot.localizedBlurb
    }

    func rotateShot() { shotOrientation = shotOrientation.toggled }

    /// Takes aim at a square. Returns whether that makes a legal move, which
    /// is the caller's cue to fire it — a tap on the board commits the shot
    /// exactly as it does in the app.
    @discardableResult
    func selectTarget(_ coordinate: Coordinate) -> Bool {
        guard isLocalTurn, selectedShot.spec.needsTarget, !isSending else { return false }
        selectedTarget = coordinate
        return canFire
    }

    /// The turn is on its way. The board plays it immediately rather than
    /// sitting on the pre-shot state until the network answers.
    func sendingBegan(envelope: MessageGameEnvelope) {
        pendingEnvelope = envelope
        isSending = true
        selectedTarget = nil
        statusMessage = String(localized: "Firing…")
    }

    func sendingSucceeded() {
        guard let envelope = pendingEnvelope else { return }
        reportSent(envelope)
        revisionStore.record(envelope)
        do {
            // Load *before* dropping the pending envelope. Clearing first left
            // a window where `displayEnvelope` fell back to the pre-shot state
            // — the turn read as yours again and `isSending` was already false,
            // so the arsenal flashed back in and straight out. `load` sets the
            // new envelope and then calls `clearStaging` itself, and since the
            // pending envelope *is* the one being loaded it shadows nothing.
            try load(envelope: envelope, authoredLocally: true)
            statusMessage = envelope.isFinished
                ? String(localized: "Final result sent.")
                : String(localized: "Sent. Waiting for your rival.")
        } catch {
            reportFlowFailure(error)
        }
    }

    func sendingFailed(_ error: Error) {
        MessagesAnalytics.send(.flowFailed(stage: "send"))
        pendingEnvelope = nil
        isSending = false
        statusMessage = String(localized: "Couldn't send that turn. \(error.localizedDescription)")
    }

    func reportInvalidMessage(_ error: Error) {
        MessagesAnalytics.send(.flowFailed(stage: "decode"))
        loadedEnvelope = nil
        localSeat = nil
        screen = (error as? MessageGameFlowError) == .staleMessage ? .staleMessage : .invalidMessage
        clearStaging()
        statusMessage = error.localizedDescription
    }

    func reportFlowFailure(_ error: Error) {
        clearStaging()
        statusMessage = error.localizedDescription
    }

    func reportUnsupportedConversation() {
        statusMessage = String(localized: "Tub Pirates requires a one-on-one conversation.")
    }

    /// Classifies what just left the device. `revision == 0` is a brand-new
    /// challenge, `1` is the invited pirate joining, anything else is a turn —
    /// which the forfeit and finish cases take precedence over.
    private func reportSent(_ envelope: MessageGameEnvelope) {
        if envelope.forfeitedBy != nil {
            MessagesAnalytics.send(.battleFinished(won: false, byForfeit: true))
            return
        }
        switch envelope.revision {
        case 0:
            MessagesAnalytics.send(
                screen == .battle ? .rematchSent : .challengeSent(source: "extension")
            )
        case 1:
            MessagesAnalytics.send(.challengeJoined)
        default:
            if let shot = envelope.latestResolution?.move.shot {
                MessagesAnalytics.send(.turnSent(shot: String(describing: shot)))
            }
            if envelope.isFinished {
                MessagesAnalytics.send(.battleFinished(won: true, byForfeit: false))
            }
        }
    }

    private func pendingMove(for player: PlayerID) -> Move {
        Move(
            player: player,
            shot: selectedShot,
            target: selectedShot.spec.needsTarget ? selectedTarget : nil,
            orientation: selectedShot.spec.needsOrientation ? shotOrientation : nil
        )
    }

    private func resetBattleSelection() {
        selectedTarget = nil
        selectedShot = .cannon
        shotOrientation = .horizontal
    }

    private func clearStaging() {
        isSending = false
        pendingEnvelope = nil
    }
}

private struct MessageRevisionStore {
    private let defaults = UserDefaults.standard

    func isStale(_ envelope: MessageGameEnvelope) -> Bool {
        envelope.revision < defaults.integer(forKey: key(for: envelope.gameID))
    }

    func record(_ envelope: MessageGameEnvelope) {
        let storageKey = key(for: envelope.gameID)
        defaults.set(max(envelope.revision, defaults.integer(forKey: storageKey)), forKey: storageKey)
    }

    private func key(for gameID: UUID) -> String { "messageGameRevision.\(gameID.uuidString)" }
}
