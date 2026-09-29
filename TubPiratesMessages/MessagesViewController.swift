//
//  MessagesViewController.swift
//  TubPiratesMessages
//
//  Created by Brevin Blalock on 8/29/26.
//

import Messages
import MessageGameCore
import SwiftUI

final class MessagesViewController: MSMessagesAppViewController {
    private let model = MessagesExtensionModel()

    private var hostingController: UIHostingController<MessagesRootView>?
    private var selectedSession: MSSession?

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = MessagesRootView(
            model: model,
            requestExpanded: { [weak self] in self?.requestPresentationStyle(.expanded)},
            startChallenge: { [weak self] in self?.stageChallenge()},
            joinChallenge: { [weak self] in self?.stageJoinedBattle()},
            fire: { [weak self] in self?.stageTurn()},
            forfeit: { [weak self] in self?.confirmForfeit()},
            rematch: { [weak self] in self?.stageRematch()}
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        // The game has no dark-mode artwork — the tub, the toys and the whole
        // palette are fixed-colour, light-toned art. Letting the sheet follow
        // the system appearance only lets the host tint and flatten controls
        // drawn for a light surface, which is what turned the orange action
        // button translucent in dark mode.
        hostingController.overrideUserInterfaceStyle = .light

        addChild(hostingController)
        view.addSubview(hostingController.view)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
        self.hostingController = hostingController

        updatePresentationMode()
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        updatePresentationMode()

        if let selectedMessage = conversation.selectedMessage {
            load(selectedMessage, in: conversation)
        } else {
            selectedSession = nil
            model.showNewChallenge()
        }
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        updatePresentationMode()
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        load(message, in: conversation)
    }

    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        super.didReceive(message, conversation: conversation)
        load(message, in: conversation)
    }

    private func updatePresentationMode() {
        model.isExpanded = (presentationStyle == .expanded)
    }

    private func stageChallenge() {
        guard let conversation = validActiveConversation() else {
            return
        }

        do {
            try send(model.makeChallengeEnvelope(), session: nil, in: conversation)
        } catch {
            model.reportFlowFailure(error)
        }
    }

    private func stageJoinedBattle() {
        guard let conversation = validActiveConversation() else {
            return
        }

        guard let selectedSession else {
            model.reportFlowFailure(
                MessageGameFlowError.missingSession
            )
            return
        }

        do {
            let envelope = try model.makeJoinedBattleEnvelope()

            try send(
                envelope,
                session: selectedSession,
                in: conversation
            )
        } catch {
            model.reportFlowFailure(error)
        }
    }

    /// Sends a turn outright rather than dropping it in the input field.
    ///
    /// `insert(_:)` stages a message and waits for the player to tap the
    /// Messages send arrow, which meant every shot took two deliberate actions
    /// and a trip out of the game. `send(_:)` puts it in the thread the moment
    /// the move is made — the way the app fires on a tap.
    ///
    /// The sheet deliberately stays open afterwards: the turn is already gone,
    /// and the player should get to watch their own shot land and look over the
    /// board before deciding to leave. Dismissing is theirs to do.
    private func send(
        _ envelope: MessageGameEnvelope,
        session: MSSession?,
        in conversation: MSConversation
    ) throws {
        try MessageGameCodec.validate(envelope)
        model.sendingBegan(envelope: envelope)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let message = try MessagesGameMessageFactory.makeMessage(
                    for: envelope,
                    session: session
                )
                try await conversation.send(message)
                selectedSession = message.session
                model.sendingSucceeded()
            } catch {
                model.sendingFailed(error)
            }
        }
    }

    private func stageTurn() {
        guard let conversation = validActiveConversation() else {
            return
        }

        guard let selectedSession else {
            model.reportFlowFailure(
                MessageGameFlowError.missingSession
            )
            return
        }

        do {
            let envelope = try model.makeTurnEnvelope()

            try send(envelope, session: selectedSession, in: conversation)
        } catch {
            model.reportFlowFailure(error)
        }
    }

    private func confirmForfeit() {
        let alert = UIAlertController(
            title: String(localized: "Forfeit this battle?"),
            message: String(localized: "Your opponent will win immediately after you send the forfeit message."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Keep Fighting"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Forfeit"), style: .destructive) { [weak self] _ in
            self?.stageForfeit()
        })
        present(alert, animated: true)
    }

    private func stageForfeit() {
        guard let conversation = validActiveConversation(), let selectedSession else {
            model.reportFlowFailure(MessageGameFlowError.missingSession)
            return
        }
        do {
            try send(model.makeForfeitEnvelope(), session: selectedSession, in: conversation)
        } catch {
            model.reportFlowFailure(error)
        }
    }

    private func stageRematch() {
        guard let conversation = validActiveConversation() else { return }
        do {
            try send(model.makeRematchEnvelope(), session: nil, in: conversation)
        } catch {
            model.reportFlowFailure(error)
        }
    }

    private func validActiveConversation() -> MSConversation? {
        guard let conversation = activeConversation else {
            model.reportUnsupportedConversation()
            return nil
        }

        guard conversation.remoteParticipantIdentifiers.count == 1 else {
            model.reportUnsupportedConversation()
            return nil
        }

        return conversation
    }

    private func load(_ message: MSMessage, in conversation: MSConversation) {
        guard let url = message.url else {
            model.showNewChallenge()
            return
        }

        do {
            let envelope = try MessagePayloadURLCodec.decode(url)

            let authoredLocally = message.senderParticipantIdentifier == conversation.localParticipantIdentifier

            selectedSession = message.session

            try model.load(envelope: envelope, authoredLocally: authoredLocally)
        } catch {
            selectedSession = nil
            model.reportInvalidMessage(error)
        }
    }

}
