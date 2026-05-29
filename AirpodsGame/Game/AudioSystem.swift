import AVFoundation
import os

private let log = Logger(subsystem: "com.airdodge.AirpodsGame", category: "AirBoxer.audio")

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
    private var musicWasPlayingBeforeInterruption: Bool = false
    /// Incremented on every startMusic/stopMusic. A fade-out closure captures
    /// the generation it was scheduled under and bails if it no longer matches,
    /// so a fade in flight can't step down or stop a track that startMusic
    /// swapped in after the fade began.
    private var musicGeneration: Int = 0

    // Read fresh each call so toggling Sound in Settings takes effect.
    private var soundEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.soundEnabled)
    }

    init(bundle: Bundle = .main) {
        configureAudioSession()
        preloadSamples(in: bundle)
        registerInterruptionObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Interruption + route-change handling
    // Fixes /autoplan eng review consensus finding #13: phone call / Siri /
    // AirPods route change would silently kill music with no recovery path.

    private func registerInterruptionObserver() {
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification,
                       object: nil)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            musicWasPlayingBeforeInterruption = music?.isPlaying ?? false
            music?.pause()
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
            if options?.contains(.shouldResume) == true && musicWasPlayingBeforeInterruption {
                try? AVAudioSession.sharedInstance().setActive(true, options: [])
                music?.play()
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard
            let info = note.userInfo,
            let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
        else { return }

        // When AirPods are pulled mid-game (oldDeviceUnavailable), pause music
        // so audio doesn't suddenly blast through the phone speaker mid-fight.
        if reason == .oldDeviceUnavailable {
            music?.pause()
        }
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
            log.error("session setup failed: \(error.localizedDescription, privacy: .public)")
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
                log.error("failed to load \(id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
            musicGeneration &+= 1
        } catch {
            log.error("failed to start music \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopMusic(fadeOver duration: TimeInterval = 0.5) {
        guard let m = music else { return }
        musicGeneration &+= 1
        let generation = musicGeneration
        guard duration > 0 else {
            m.stop()
            music = nil
            return
        }
        // Manual fade-out via timer because AVAudioPlayer.setVolume(_:fadeDuration:)
        // is iOS 10+ but we want explicit control over the curve. Capture the
        // specific player + generation so a startMusic swap mid-fade can't have
        // its fresh track stepped down or stopped by this fade.
        let steps = 10
        let stepDuration = duration / Double(steps)
        let startVolume = m.volume
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) { [weak self, weak m] in
                guard let self, let player = m,
                      self.musicGeneration == generation,
                      self.music === player else { return }
                player.volume = startVolume * Float(steps - i) / Float(steps)
                if i == steps {
                    player.stop()
                    self.music = nil
                }
            }
        }
    }

}
