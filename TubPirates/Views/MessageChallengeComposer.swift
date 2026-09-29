import BathtubEngine
import BathtubUI
import MessageGameCore
import Messages
import MessageUI
import SwiftUI
import UIKit

/// Sends a Tub Pirates challenge straight from the app.
///
/// `MFMessageComposeViewController` accepts a real `MSMessage`, so the invite
/// that lands in the friend's thread is the same interactive bubble the
/// iMessage extension produces — not a link. A recipient who doesn't own the
/// game gets the App Store prompt from that bubble, which is the whole point:
/// this is the one flow in the app that can produce a new download.
///
/// Presented through UIKit rather than a SwiftUI `.sheet`: the compose screen
/// is a remote view controller hosted by another process, and wrapping it in
/// `UIViewControllerRepresentable` inside a sheet silently presents nothing.
@MainActor
enum MessageChallengeComposer {
    static var canSend: Bool { MFMessageComposeViewController.canSendText() }

    /// `MFMessageComposeViewController` holds its delegate weakly, so the
    /// coordinator has to outlive this call or the result never arrives.
    private static var retainedDelegate: Delegate?

    static func present(
        board: Board,
        appearance: SharedAppGroup.Appearance,
        onFinish: @escaping (MessageComposeResult) -> Void
    ) {
        guard canSend, let host = topViewController() else {
            onFinish(.failed)
            return
        }
        // No challenge means nothing worth opening the composer for.
        guard let message = try? makeChallengeMessage(board: board, appearance: appearance) else {
            onFinish(.failed)
            return
        }

        let controller = MFMessageComposeViewController()
        let delegate = Delegate { result in
            retainedDelegate = nil
            onFinish(result)
        }
        retainedDelegate = delegate
        controller.messageComposeDelegate = delegate
        controller.message = message
        host.present(controller, animated: true)
    }

    /// Builds the same envelope the extension would stage for a fresh
    /// challenge, wrapped in a session so the reply threads into one battle.
    static func makeChallengeMessage(
        board: Board,
        appearance: SharedAppGroup.Appearance = .default
    ) throws -> MSMessage {
        // Carry the captain's look, exactly as the extension does. Without it a
        // challenge started from the app arrived as the stock pirate with a
        // classic fleet, while the same challenge started from the Messages
        // sheet arrived correctly — the rival saw two different people.
        let envelope = MessageGameEnvelope.newChallenge(board: board, appearance: appearance)
        let message = MSMessage(session: MSSession())
        message.url = try MessagePayloadURLCodec.encode(envelope)
        message.summaryText = String(localized: "Tub Pirates battle")
        message.shouldExpire = false

        let layout = MSMessageTemplateLayout()
        layout.caption = String(localized: "Tub Pirates Challenge")
        layout.subcaption = String(localized: "Tap to place your fleet")
        layout.image = ChallengeBubbleArtwork.image()
        message.layout = layout
        message.accessibilityLabel = String(localized: "Tub Pirates challenge. Tap to place your fleet.")
        return message
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    private final class Delegate: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}

/// The bubble image for an app-sent challenge. Deliberately the same aqua
/// composition the extension bakes into its own bubbles so a thread reads
/// consistently no matter which end started the battle.
private enum ChallengeBubbleArtwork {
    @MainActor
    static func image() -> UIImage? {
        let renderer = ImageRenderer(content: ChallengeBubbleView())
        renderer.scale = 2
        return renderer.uiImage
    }
}

private struct ChallengeBubbleView: View {
    private static let navy = Color(red: 0.07, green: 0.23, blue: 0.36)
    private static let pink = Color(red: 0.91, green: 0.38, blue: 0.55)

    var body: some View {
        ZStack {
            Image("message_bubble_backdrop")
                .resizable()
                .scaledToFill()
            LinearGradient(
                colors: [.white.opacity(0.18), .white.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 14) {
                Image("ship_5")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 3) {
                    Text("TUB PIRATES")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(Self.pink)
                    Text("YE BE CHALLENGED")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Self.navy)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    Text("Place yer fleet and fight back.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.navy.opacity(0.75))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
        }
        .frame(width: 300, height: 180)
    }
}
