import AVFoundation

/// All the game's sound effects. Raw values match the bundled WAV filenames.
enum GameSound: String, CaseIterable {
    case cannon = "sfx_cannon"
    case splash = "sfx_splash"
    case explosion = "sfx_explosion"
    case sunk = "sfx_sunk"
    case reveal = "sfx_reveal"
    case coin = "sfx_coin"
    case chest = "sfx_chest"
    case tap = "sfx_tap"
    case pop = "sfx_pop"
    case victory = "sfx_victory"
    case defeat = "sfx_defeat"
    case parrot = "sfx_parrot"

    /// Relative loudness so effects sit well together without re-rendering.
    var volume: Float {
        switch self {
        case .cannon: 0.8
        case .splash: 0.7
        case .explosion: 0.9
        case .sunk: 1.0
        case .reveal: 0.6
        case .coin: 0.55
        case .chest: 0.7
        case .tap: 0.35
        case .pop: 0.45
        case .victory: 0.9
        case .defeat: 0.8
        case .parrot: 0.65
        }
    }
}

/// Central SFX player: small AVAudioPlayer pools per sound so rapid volleys
/// (fireworks!) can overlap, an ambient audio session so the player's own
/// music keeps going, and a Settings-backed mute.
@MainActor
final class SoundService {
    static let shared = SoundService()

    private var pools: [GameSound: [AVAudioPlayer]] = [:]
    private nonisolated static let poolSize = 3

    private var musicPlayer: AVAudioPlayer?

    private var enabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "soundEnabled") == nil || defaults.bool(forKey: "soundEnabled")
    }

    private var musicEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "musicEnabled") == nil || defaults.bool(forKey: "musicEnabled")
    }

    private var warmed = false
    private var musicRequested = false

    /// All AVAudioPlayer control happens on this queue — play() can lazily
    /// (re)activate the audio session, which blocks, so it must stay off the
    /// main thread. High QoS keeps SFX latency imperceptible.
    private nonisolated static let audioQueue = DispatchQueue(
        label: "co.brevinb.bathtub.audio", qos: .userInteractive
    )

    private init() {}

    /// Wraps non-Sendable AVAudioPlayers for the one-shot hop back to the
    /// main actor after background preloading.
    private struct TransferBox<T>: @unchecked Sendable { let value: T }

    /// Configures the audio session and pre-warms the player pools off the
    /// main thread — session activation blocks and would hitch app launch.
    func warmUp() {
        guard !warmed else { return }
        warmed = true
        Task.detached(priority: .utility) {
            // .ambient respects the silent switch and mixes with Music/Podcasts.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, options: .mixWithOthers)
            try? session.setActive(true)

            var built: [GameSound: [AVAudioPlayer]] = [:]
            for sound in GameSound.allCases {
                guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else {
                    continue
                }
                built[sound] = (0..<Self.poolSize).compactMap { _ in
                    let player = try? AVAudioPlayer(contentsOf: url)
                    player?.volume = sound.volume
                    player?.prepareToPlay()
                    return player
                }
            }
            let box = TransferBox(value: built)
            await MainActor.run {
                let service = SoundService.shared
                service.pools = box.value
                // Music asked for before the session was ready starts now.
                if service.musicRequested { service.beginMusic() }
            }
        }
    }

    func play(_ sound: GameSound) {
        guard enabled, let pool = pools[sound] else { return }
        let box = TransferBox(value: pool)
        Self.audioQueue.async {
            // First idle player, or steal a voice for relentless volleys.
            let player = box.value.first { !$0.isPlaying } ?? box.value.first
            player?.currentTime = 0
            player?.play()
        }
    }

    // MARK: - Music

    /// Starts the looping background track. Stays silent if the player is
    /// already listening to their own music or podcast — their audio wins.
    /// Before the session finishes warming up, the request is queued and
    /// honored from warmUp()'s completion.
    func startMusic() {
        musicRequested = true
        guard !pools.isEmpty else { return }
        beginMusic()
    }

    private var musicStarting = false

    private func beginMusic() {
        guard musicEnabled, !musicStarting, musicPlayer?.isPlaying != true else { return }
        musicStarting = true
        let existing = musicPlayer.map { TransferBox(value: $0) }
        let url = Bundle.main.url(forResource: "music_main", withExtension: "m4a")
        // isOtherAudioPlaying and the first play() both talk to the media
        // server and can block — keep them off the main thread.
        Task.detached(priority: .utility) {
            defer {
                Task { @MainActor in SoundService.shared.musicStarting = false }
            }
            guard !AVAudioSession.sharedInstance().isOtherAudioPlaying else { return }
            let player: AVAudioPlayer?
            if let existing {
                player = existing.value
            } else if let url {
                player = try? AVAudioPlayer(contentsOf: url)
                player?.numberOfLoops = -1
                player?.volume = 0 // fades in below
            } else {
                player = nil
            }
            guard let player else { return }
            player.play()
            player.setVolume(0.32, fadeDuration: 1.5)
            let box = TransferBox(value: player)
            await MainActor.run {
                let service = SoundService.shared
                if service.musicEnabled {
                    service.musicPlayer = box.value
                } else {
                    // Toggled off while we were spinning up.
                    box.value.stop()
                }
            }
        }
    }

    func stopMusic() {
        guard let musicPlayer else { return }
        let box = TransferBox(value: musicPlayer)
        Self.audioQueue.async {
            guard box.value.isPlaying else { return }
            box.value.setVolume(0, fadeDuration: 0.6)
            Self.audioQueue.asyncAfter(deadline: .now() + 0.65) {
                box.value.pause()
            }
        }
    }

    /// Settings toggle hook.
    func musicSettingChanged(enabled: Bool) {
        if enabled { startMusic() } else { stopMusic() }
    }
}
