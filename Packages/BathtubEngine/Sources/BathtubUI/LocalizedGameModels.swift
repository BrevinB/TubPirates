#if canImport(UIKit)
import BathtubEngine
import Foundation

/// Player-facing names for engine values.
///
/// The engine keeps plain English literals so it stays free of a bundle; the
/// translations live here, in the shared UI target, so the app and the
/// Messages extension both read from one catalog. They used to live in the
/// app only, which is why every ship and cannon name in the Messages sheet
/// came out English no matter the device language.
extension ShotType {
    public var localizedDisplayName: String {
        switch self {
        case .cannon: String(localized: "Cannon", bundle: .module)
        case .parrotScout: String(localized: "Parrot Scout", bundle: .module)
        case .bigShot: String(localized: "Big Shot Cannon", bundle: .module)
        case .flare: String(localized: "Flare Cannon", bundle: .module)
        case .chainShot: String(localized: "Chain Shot", bundle: .module)
        case .fireworks: String(localized: "Fireworks Cannon", bundle: .module)
        }
    }

    public var localizedBlurb: String {
        switch self {
        case .cannon:
            String(localized: "Your trusty cannon. Fires a single shot.", bundle: .module)
        case .parrotScout:
            String(localized: "Use this shot to 'see' all of the ships in a certain area. Causes no damage.", bundle: .module)
        case .bigShot:
            String(localized: "This monster cannon targets four tiles at once.", bundle: .module)
        case .flare:
            String(localized: "Use this special cannon shot to reveal your opponent's ship's location.", bundle: .module)
        case .chainShot:
            String(localized: "Linked cannonballs rake three tiles in a row.", bundle: .module)
        case .fireworks:
            String(localized: "This cannon will shoot 5 shots in an X pattern.", bundle: .module)
        }
    }

    /// The arsenal icon for this cannon. Shared so the app's shot panel and
    /// the Messages arsenal can never drift onto different art.
    public var iconName: String {
        switch self {
        case .cannon: "icon_cannon"
        case .parrotScout: "icon_parrot"
        case .bigShot: "icon_bigshot"
        case .flare: "icon_flare"
        case .chainShot: "icon_chain"
        case .fireworks: "icon_fireworks"
        }
    }
}

extension ShipKind {
    public var localizedDisplayName: String {
        switch self {
        case .dinghy: String(localized: "Dinghy", bundle: .module)
        case .tugboat: String(localized: "Tugboat", bundle: .module)
        case .duckSub: String(localized: "Duck Sub", bundle: .module)
        case .frigate: String(localized: "Wind-Up Whale", bundle: .module)
        case .galleon: String(localized: "Galleon", bundle: .module)
        }
    }
}
#endif
