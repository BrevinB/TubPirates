// The arena is a UIKit/SpriteKit surface; the package also builds for macOS
// so the engine's tests can run there, where this target has nothing to offer.
#if canImport(UIKit)
/// The arena renders in two hosts — the app, which owns `SoundService`, and the
/// Messages extension, which has no audio stack at all. Effects call through
/// here instead of reaching for a singleton that only one host has.
public enum ArenaSound: String, Sendable {
    case cannon
    case explosion
    case splash
    case reveal
    case parrot
    case sunk
}

@MainActor
public enum ArenaAudio {
    /// No-op until a host installs a handler.
    public static var handler: (@MainActor (ArenaSound) -> Void)?

    public static func play(_ sound: ArenaSound) {
        handler?(sound)
    }
}
#endif
