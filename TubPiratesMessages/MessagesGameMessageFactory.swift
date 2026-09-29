//
//  MessagesGameMessageFactory.swift
//  TubPirates
//
//  Created by Brevin Blalock on 8/30/26.
//

import BathtubArena
import BathtubEngine
import BathtubUI
import MessageGameCore
import Messages
import SwiftUI
import UIKit

@MainActor
enum MessagesGameMessageFactory {
    static func makeMessage(
        for envelope: MessageGameEnvelope,
        session: MSSession? = nil
    ) throws -> MSMessage {
        let message: MSMessage

        if let session {
            message = MSMessage(session: session)
        } else {
            message = MSMessage(session: MSSession())
        }

        message.url = try MessagePayloadURLCodec.encode(envelope)
        message.layout = makeLayout(for: envelope)
        message.summaryText = "Tub Pirates battle"
        message.accessibilityLabel = accessibilityLabel(for: envelope)
        message.shouldExpire = false

        return message
    }

    private static func makeLayout(for envelope: MessageGameEnvelope) -> MSMessageTemplateLayout {
        let layout = MSMessageTemplateLayout()

        let renderer = ImageRenderer(content: MessageBubbleArtworkView(envelope: envelope))
        renderer.scale = 2
        layout.image = renderer.uiImage

        switch envelope.content {
        case .setup(let boards):
            layout.caption = "Tub Pirates Challenge"

            if boards.count == 1 {
                layout.subcaption = "Tap to place your fleet"
            } else {
                layout.subcaption = "Both fleets are ready"
            }
        case .battle(let state):
            layout.caption = "Tub Pirates Battle"
            if envelope.forfeitedBy != nil {
                layout.subcaption = "A pirate forfeited — tap for the result"
            } else {
                switch state.phase {
                case .active:
                    if let resolution = envelope.latestResolution {
                        layout.subcaption = resultCaption(resolution)
                    } else {
                        layout.subcaption = "Tap to continue the battle"
                    }
                case .finished:
                    layout.subcaption = "The battle is over"
                }
            }
        }

        return layout
    }

    private static func accessibilityLabel(for envelope: MessageGameEnvelope) -> String {
        switch envelope.content {
        case .setup(let boards):
            if boards.count == 1 {
                return "Tub Pirates challenge. Tap to place your fleet."
            }

            return "Tub Pirates battle. Both fleets are ready."

        case .battle(let state):
            if envelope.forfeitedBy != nil {
                return "Tub Pirates battle completed by forfeit."
            }
            switch state.phase {
            case .active: return "Tub Pirates battle. Tap to continue."
            case .finished:
                return "Tub Pirates battle completed."
            }
        }
    }

    private static func resultCaption(_ resolution: MoveResolution) -> String {
        if let ship = resolution.sunkShips.first {
            return String(localized: "Sunk: \(ship.kind.localizedDisplayName)")
        }
        if resolution.cellResults.contains(where: { $0.outcome == .hit }) { return "Hit! Tap for the next turn" }
        if resolution.revealedShip != nil { return "A ship was revealed" }
        if resolution.move.shot.spec.effect == .revealArea { return "Scout report ready" }
        return "Miss — tap for the next turn"
    }
}

/// The artwork baked into the message bubble. Both pirates see this same
/// image, and so does anyone scrolling the thread who doesn't have the game —
/// it's the most-seen surface we own, so it carries the brand, not an
/// SF Symbol. Wording stays neutral ("DIRECT HIT", never "you hit"), and it
/// never shows a board: the bubble is visible to both sides.
private struct MessageBubbleArtworkView: View {
    let envelope: MessageGameEnvelope

    private static let navy = Color(red: 0.07, green: 0.23, blue: 0.36)
    private static let pink = Color(red: 0.91, green: 0.38, blue: 0.55)

    var body: some View {
        ZStack {
            // The same aqua/suds backdrop as the App Store screenshots, so a
            // bubble in a thread and the store listing read as one product.
            ArtworkImage(name: "message_bubble_backdrop", width: 300, height: 180, contentMode: .fill)
            LinearGradient(
                colors: [.white.opacity(0.18), .white.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 14) {
                artwork

                VStack(alignment: .leading, spacing: 3) {
                    Text("TUB PIRATES")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(Self.pink)
                    Text(headline)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Self.navy)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    Text(subline)
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

    @ViewBuilder
    private var artwork: some View {
        switch artworkKind {
        case .asset(let name):
            ArtworkImage(name: name, width: 72, height: 72)
        case .symbol(let name, let tint):
            Image(systemName: name)
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(tint)
        }
    }

    private enum ArtworkKind {
        case asset(String)
        case symbol(String, Color)
    }

    private var artworkKind: ArtworkKind {
        if envelope.forfeitedBy != nil { return .symbol("flag.fill", Self.pink) }
        if envelope.isFinished { return .asset("treasure_chest") }

        switch envelope.content {
        case .setup:
            return .asset(challengerFlagship)
        case .battle:
            guard let resolution = envelope.latestResolution else { return .asset(challengerFlagship) }
            if let sunk = resolution.sunkShips.first {
                // The wreck belongs to whoever was fired *at*, so it wears
                // their fleet's skin — a ducky flagship should go down as a
                // duck in the bubble too.
                let defender = resolution.move.player.opponent
                let skin = FleetSkin.withID(envelope.appearance(of: defender).fleetID)
                return .asset(skin.textureName(for: sunk.kind))
            }
            return .asset(resolution.move.shot.iconName)
        }
    }

    /// The challenger's own galleon, so the invite shows the fleet they play.
    private var challengerFlagship: String {
        FleetSkin.withID(envelope.appearance(of: .one).fleetID).textureName(for: .galleon)
    }

    private var headline: String {
        if envelope.forfeitedBy != nil { return "FORFEIT" }
        if envelope.isFinished { return "BATTLE OVER" }

        switch envelope.content {
        case .setup:
            return "YE BE CHALLENGED"
        case .battle:
            guard let resolution = envelope.latestResolution else { return "BATTLE ON" }
            if let sunk = resolution.sunkShips.first { return "\(sunk.kind.displayName.uppercased()) SUNK" }
            if resolution.cellResults.contains(where: { $0.outcome == .hit }) { return "DIRECT HIT" }
            if resolution.revealedShip != nil || resolution.move.shot.spec.effect == .revealArea {
                return "SCOUT REPORT"
            }
            return "MISS"
        }
    }

    private var subline: String {
        if envelope.forfeitedBy != nil { return "A pirate struck their colors." }
        if envelope.isFinished { return "Tap for the spoils." }

        switch envelope.content {
        case .setup:
            return "Place yer fleet and fight back."
        case .battle:
            return envelope.latestResolution == nil
                ? "Both fleets are in the water."
                : "Yer move, captain."
        }
    }
}
