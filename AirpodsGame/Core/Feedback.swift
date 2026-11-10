import AVFoundation
import UIKit

/// Posture nudges and rep cues. Voice goes to the earbuds the user is
/// already wearing, which is what makes a nudge noticeable with the phone
/// face-down on the desk.
@MainActor
final class Feedback {
    static let shared = Feedback()

    private let synthesizer = AVSpeechSynthesizer()
    private var sessionConfigured = false

    private init() {}

    private var voiceEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.voiceCues) }
    private var hapticsEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.hapticsEnabled) }

    func postureNudge() {
        if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        speak(String(localized: "Chin up. Sit tall."))
    }

    func repComplete() {
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    func stepStarted(_ movement: Movement) {
        speak(movement.title)
    }

    func routineFinished() {
        if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        speak(String(localized: "Nice work. Routine complete."))
    }

    private func speak(_ text: String) {
        guard voiceEnabled else { return }
        if !sessionConfigured {
            // Mix with the user's music and duck it briefly instead of stopping it.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio,
                                                             options: [.duckOthers])
            sessionConfigured = true
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.speak(AVSpeechUtterance(string: text))
    }
}
