import AVFoundation

// AudioSystem — owns every sound in the game.
//
// Per /plan-eng-review Issue 2 (locked decision): all sounds are AVAudioPlayer
// instances preloaded at scene init with prepareToPlay() called on each. This
// eliminates the first-play hitch you'd get with SKAction.playSoundFileNamed
// (which lazily allocates audio resources on first call — ~30-100ms latency).
//
// Behavior contract:
//  - Missing assets are silent no-ops (game continues, no crash).
//  - All playback is gated on Settings.soundEnabled — flipping the toggle in
//    Settings stops new sounds immediately.
//  - Music loops via numberOfLoops = -1.
//  - One-shots can overlap (e.g., bell ringing while crowd cheer fires).

@MainActor
final class AudioSystem {

    enum SoundID: String, CaseIterable {
        case bell           // intro / round-end / round-break dismiss
        case drumRoll       // intro card transition
        case dodgeCheer     // successful slip / duck
        case hitImpact      // got hit
        case knockoutSting  // KO sequence
        case buzzBuzz       // hit-flash text appearance
        case roundUp        // advance round banner

        var filename: String {
            // Files live at AirpodsGame/Audio/<name>.caf or .mp3
            // Lookup is case-insensitive at the bundle level.
            return rawValue
        }
    }

    private var music: AVAudioPlayer?
    private var samples: [SoundID: AVAudioPlayer] = [:]

    // Read fresh each call so toggling Sound in Settings takes effect.
    private var soundEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.soundEnabled)
    }

    init(bundle: Bundle = .main) {
        configureAudioSession()
        preloadSamples(in: bundle)
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        // .ambient = our audio mixes with anything else playing (Music app,
        // podcasts). The user's choice of background audio is sacred.
        // .mixWithOthers = explicit duck-not-stop behavior.
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            // Session config failure is non-fatal — game keeps running silent.
            print("[AudioSystem] session setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Preloading

    private func preloadSamples(in bundle: Bundle) {
        for id in SoundID.allCases {
            // Try .caf first (Apple's preferred format), fall back to .mp3.
            let url = bundle.url(forResource: id.filename, withExtension: "caf") ??
                      bundle.url(forResource: id.filename, withExtension: "mp3") ??
                      bundle.url(forResource: id.filename, withExtension: "wav")
            guard let url else {
                // Asset missing — silent no-op when played.
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                samples[id] = player
            } catch {
                print("[AudioSystem] failed to load \(id.rawValue): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Playback

    /// Play a one-shot. Multiple calls overlap (e.g., bell + cheer simultaneously).
    /// Auto-rewinds the player so the same sound can fire repeatedly.
    func play(_ id: SoundID) {
        guard soundEnabled else { return }
        guard let player = samples[id] else { return }
        player.currentTime = 0
        player.play()
    }

    /// Start the background music loop. Call from FightPhase intro / fighting.
    /// Loops forever until stopMusic() or the AudioSystem is deinitialized.
    func startMusic(named name: String, volume: Float = 0.6) {
        guard soundEnabled else { return }
        let bundle = Bundle.main
        let url = bundle.url(forResource: name, withExtension: "caf") ??
                  bundle.url(forResource: name, withExtension: "mp3") ??
                  bundle.url(forResource: name, withExtension: "wav")
        guard let url else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.prepareToPlay()
            player.play()
            music = player
        } catch {
            print("[AudioSystem] failed to start music \(name): \(error.localizedDescription)")
        }
    }

    func stopMusic(fadeOver duration: TimeInterval = 0.5) {
        guard let m = music else { return }
        guard duration > 0 else {
            m.stop()
            music = nil
            return
        }
        // Manual fade-out via timer because AVAudioPlayer.setVolume(_:fadeDuration:)
        // is iOS 10+ but we want explicit control over the curve.
        let steps = 10
        let stepDuration = duration / Double(steps)
        let startVolume = m.volume
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) { [weak self] in
                guard let self, let player = self.music else { return }
                player.volume = startVolume * Float(steps - i) / Float(steps)
                if i == steps {
                    player.stop()
                    self.music = nil
                }
            }
        }
    }

    /// Duck volume to a fraction of current (for round-break voice clarity).
    /// Call .restoreMusicVolume() to bring it back.
    func duckMusic(to fraction: Float = 0.3) {
        music?.volume = (music?.volume ?? 0.6) * fraction
    }

    func restoreMusicVolume(to volume: Float = 0.6) {
        music?.volume = volume
    }
}
