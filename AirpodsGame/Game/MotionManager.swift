import CoreMotion
import Observation
import os

/// Subsystem visible via `idevicesyslog | grep AirBoxer.motion`
private let log = Logger(subsystem: "com.airdodge.AirpodsGame", category: "AirBoxer.motion")

// CMHeadphoneMotionManager wrapper.
//
// Why CMHeadphoneMotionManager only "sometimes" delivers data:
//   1. Hardware: ONLY AirPods Pro, AirPods Max, AirPods 3rd gen, and AirPods 4
//      with ANC support motion. Original AirPods (1st/2nd gen) and AirPods 4
//      (no ANC) do NOT — they have no H1/H2 motion chip. No software fix.
//   2. Permission: NSMotionUsageDescription must be in Info.plist (it is),
//      AND the user must allow Motion & Fitness when prompted on first
//      startDeviceMotionUpdates call.
//   3. Wear detection: AirPods must be IN the user's ears. In-ear detection
//      gates motion data — pods on the desk = no data.
//   4. Active connection: AirPods must be currently routed to THIS iPhone,
//      not a paired Mac/iPad/Watch.
//
// The delegate (CMHeadphoneMotionManagerDidConnect / DidDisconnect) fires on
// physical pairing/route changes — independent of whether data is flowing.
// We expose both a status enum (what level of trouble we're in) and a
// human-readable hint so the UI can give the user actionable feedback.

// Main-actor isolated: all observable state is mutated on the main actor.
// CoreMotion delivers its delegate callbacks on an arbitrary queue, so those
// hop over with `Task { @MainActor in … }` before touching state.
@MainActor
@Observable
final class MotionManager: NSObject, CMHeadphoneMotionManagerDelegate {

    enum Status {
        case unknown                      // not started yet
        case unavailable                  // hardware/OS does not support headphone motion
        case permissionDenied             // user denied Motion & Fitness — must open Settings
        case waitingForAirPods            // available; pods not connected/paired
        case waitingForData               // pods connected; no motion frames yet (likely not in ears)
        case live                         // motion data flowing

        /// Short chip copy. Deliberately phrased as a *setup step*, never as an
        /// error — a reviewer opening the app on a bare device must read this as
        /// "here's what to connect", not "this app crashed". See the requirement
        /// card in ContentView for the full explanation.
        /// Headphones whose head tracking iOS exposes to apps
        /// (CMHeadphoneMotionManager).
        static let supportedHeadphones = "AirPods Pro, AirPods Max, AirPods (3rd generation), AirPods 4 or Beats Fit Pro"

        var label: String {
            switch self {
            case .unknown:            return "Looking for motion earbuds…"
            case .unavailable:        return "No motion hardware detected"
            case .permissionDenied:   return "Tap to allow Motion & Fitness"
            case .waitingForAirPods:  return "No motion earbuds connected"
            case .waitingForData:     return "Earbuds paired — put them in your ears"
            case .live:               return "Motion earbuds connected"
            }
        }

        /// The single next action the player should take, shown on the setup
        /// card. Always actionable — never a dead end.
        var nextStep: String {
            switch self {
            case .unknown:
                return "Searching for motion earbuds. This takes a moment after launch."
            case .unavailable:
                return "This device can't report head motion. AirBoxer needs an iPhone paired with \(Self.supportedHeadphones)."
            case .permissionDenied:
                return "Motion & Fitness access is off, so head motion can't reach the game. Tap the status chip above to open Settings and turn it on."
            case .waitingForAirPods:
                return "Connect \(Self.supportedHeadphones) to this iPhone, then tap the status chip to retry."
            case .waitingForData:
                return "Your earbuds are connected. Put them in your ears — head motion only streams while they're worn."
            case .live:
                return "You're ready. Tap FIGHT."
            }
        }

        var isLive: Bool { if case .live = self { return true }; return false }
    }

    private let manager = CMHeadphoneMotionManager()
    private let smoothing: Double = 0.85

    var pitch: Double = 0  // nod up/down, degrees
    var roll: Double = 0   // tilt left/right, degrees
    var yaw: Double = 0    // turn left/right, degrees
    var status: Status = .unknown

    /// Backwards-compat: the old chip in ContentView reads this. True only when motion frames are arriving.
    var isConnected: Bool { status.isLive }

    @ObservationIgnored private var smoothedPitch: Double = 0
    @ObservationIgnored private var smoothedRoll: Double = 0
    @ObservationIgnored private var lastDataAt: Date?
    @ObservationIgnored private var watchdog: Timer?
    /// True between a successful `startDeviceMotionUpdates` call and the
    /// next `stop()`/`restart()`. Used to make `start()` idempotent so
    /// SwiftUI lifecycle re-firing (`.onAppear` triggered by view recycling
    /// or state changes) doesn't kill the in-flight motion stream.
    @ObservationIgnored private var isStreaming = false

    static let shared = MotionManager()

    private override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        #if DEBUG
        // Screenshot fixture: pretend earbuds are streaming so the roster shows.
        if ProcessInfo.processInfo.arguments.contains("-ABFakeMotion") {
            status = .live
            return
        }
        #endif
        let available = manager.isDeviceMotionAvailable
        let auth = CMMotionActivityManager.authorizationStatus()
        let isActive = manager.isDeviceMotionActive
        log.notice("start(): available=\(available), auth=\(auth.rawValue), active=\(isActive)")

        // If the user previously denied Motion & Fitness, no data will ever
        // flow even with AirPods perfectly paired. Surface this immediately.
        if auth == .denied || auth == .restricted {
            status = .permissionDenied
            log.notice("-> .permissionDenied (auth=\(auth.rawValue))")
            return
        }

        guard available else {
            status = .unavailable
            log.notice("-> .unavailable")
            return
        }
        // Idempotency: if we already issued startDeviceMotionUpdates, reject
        // every subsequent start() until stop()/restart() is called explicitly.
        // SwiftUI re-fires .onAppear during view recycling and the second call
        // would tear down the in-flight motion stream just as data is about
        // to arrive (see device logs from 2026-05-06).
        if isStreaming {
            log.notice("start() called while already streaming — ignoring")
            return
        }

        // Until either the delegate fires or data starts flowing, we're hunting.
        if status == .unknown || status == .unavailable {
            status = .waitingForAirPods
        }

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let error {
                log.notice("data error: \(error.localizedDescription)")
                // CMHeadphoneMotionManager logs its own errors; we keep the
                // last known status. Don't downgrade live → waitingForData on
                // a single transient error.
                return
            }
            guard let motion else {
                log.notice("data callback fired with nil motion")
                return
            }
            // Extract plain Doubles before hopping — CMDeviceMotion isn't Sendable.
            let rawPitch = motion.attitude.pitch * 180 / .pi
            let rawRoll  = motion.attitude.roll  * 180 / .pi
            let rawYaw   = motion.attitude.yaw   * 180 / .pi
            Task { @MainActor [weak self] in
                self?.ingest(rawPitch: rawPitch, rawRoll: rawRoll, rawYaw: rawYaw)
            }
        }
        isStreaming = true
        log.notice("startDeviceMotionUpdates dispatched")

        // Watchdog: if we believe pods are connected but no frames arrived
        // for 2s, downgrade to waitingForData (covers "pods on desk").
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // If pods are connected (delegate fired) but data is stale,
                // user likely doesn't have them in their ears.
                if case .live = self.status,
                   let last = self.lastDataAt,
                   Date().timeIntervalSince(last) > 2.0 {
                    self.status = .waitingForData
                }
            }
        }
    }

    /// Applies one motion frame on the main actor.
    private func ingest(rawPitch: Double, rawRoll: Double, rawYaw: Double) {
        let firstFrame = lastDataAt == nil
        lastDataAt = Date()
        if !status.isLive {
            log.notice("data flowing -> .live (firstFrame=\(firstFrame))")
            status = .live
        }
        smoothedPitch = smoothing * smoothedPitch + (1 - smoothing) * rawPitch
        smoothedRoll  = smoothing * smoothedRoll  + (1 - smoothing) * rawRoll
        pitch = smoothedPitch
        roll  = smoothedRoll
        yaw   = rawYaw
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        watchdog?.invalidate()
        watchdog = nil
        isStreaming = false
        if status.isLive || status == .waitingForData {
            status = .waitingForAirPods
        }
    }

    /// User-initiated retry. Force-stops then re-starts the motion stream
    /// from a clean slate. Helps when AirPods connect AFTER the app launched
    /// or routing changed mid-session and CMHeadphoneMotionManager didn't
    /// auto-pick them up.
    func restart() {
        log.notice("restart() requested")
        manager.stopDeviceMotionUpdates()
        watchdog?.invalidate()
        watchdog = nil
        lastDataAt = nil
        isStreaming = false
        status = .unknown
        start()
    }

    // MARK: - CMHeadphoneMotionManagerDelegate

    // CoreMotion calls these on its own queue — hop to the main actor.

    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        // Pods are now routed to this iPhone. Data may not be flowing yet
        // (need them in the ears). Mark as waitingForData; the data callback
        // upgrades to .live as soon as a frame arrives.
        log.notice("delegate: didConnect -> .waitingForData")
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.status.isLive { self.status = .waitingForData }
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        log.notice("delegate: didDisconnect -> .waitingForAirPods")
        Task { @MainActor [weak self] in
            self?.status = .waitingForAirPods
        }
    }
}
