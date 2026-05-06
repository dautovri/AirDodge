import CoreMotion
import Combine

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

final class MotionManager: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {

    enum Status {
        case unknown                      // not started yet
        case unavailable                  // hardware/OS does not support headphone motion
        case permissionDenied             // user denied Motion & Fitness — must open Settings
        case waitingForAirPods            // available; pods not connected/paired
        case waitingForData               // pods connected; no motion frames yet (likely not in ears)
        case live                         // motion data flowing

        var label: String {
            switch self {
            case .unknown:            return "Looking for AirPods…"
            case .unavailable:        return "Headphone motion not available"
            case .permissionDenied:   return "Tap to grant Motion & Fitness in Settings"
            case .waitingForAirPods:  return "AirPods not detected — pair Pro, Max, or 3rd gen"
            case .waitingForData:     return "AirPods paired — put them in your ears"
            case .live:               return "AirPods connected"
            }
        }

        var isLive: Bool { if case .live = self { return true }; return false }
    }

    private let manager = CMHeadphoneMotionManager()
    private let smoothing: Double = 0.85

    @Published var pitch: Double = 0  // nod up/down, degrees
    @Published var roll: Double = 0   // tilt left/right, degrees
    @Published var yaw: Double = 0    // turn left/right, degrees
    @Published var status: Status = .unknown

    /// Backwards-compat: the old chip in ContentView reads this. True only when motion frames are arriving.
    var isConnected: Bool { status.isLive }

    private var smoothedPitch: Double = 0
    private var smoothedRoll: Double = 0
    private var lastDataAt: Date?
    private var watchdog: Timer?

    static let shared = MotionManager()

    private override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        let available = manager.isDeviceMotionAvailable
        let auth = CMMotionActivityManager.authorizationStatus()
        print("[MotionManager] start(): isDeviceMotionAvailable=\(available), authStatus=\(auth.rawValue), delegate-isActive=\(manager.isDeviceMotionActive)")

        // If the user previously denied Motion & Fitness, no data will ever
        // flow even with AirPods perfectly paired. Surface this immediately.
        if auth == .denied || auth == .restricted {
            status = .permissionDenied
            print("[MotionManager] -> .permissionDenied (auth=\(auth.rawValue))")
            return
        }

        guard available else {
            status = .unavailable
            print("[MotionManager] -> .unavailable")
            return
        }
        // If we're already running and have a status, don't restart.
        if status.isLive || status == .waitingForData { return }

        // Until either the delegate fires or data starts flowing, we're hunting.
        if status == .unknown || status == .unavailable {
            status = .waitingForAirPods
        }

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                print("[MotionManager] data error: \(error.localizedDescription)")
                // CMHeadphoneMotionManager logs its own errors; we keep the
                // last known status. Don't downgrade live → waitingForData on
                // a single transient error.
                return
            }
            guard let motion else {
                print("[MotionManager] data callback fired with nil motion")
                return
            }
            let firstFrame = self.lastDataAt == nil
            self.lastDataAt = Date()
            if !self.status.isLive {
                print("[MotionManager] data flowing -> .live (firstFrame=\(firstFrame))")
                self.status = .live
            }
            let rawPitch = motion.attitude.pitch * 180 / .pi
            let rawRoll  = motion.attitude.roll  * 180 / .pi
            self.smoothedPitch = self.smoothing * self.smoothedPitch + (1 - self.smoothing) * rawPitch
            self.smoothedRoll  = self.smoothing * self.smoothedRoll  + (1 - self.smoothing) * rawRoll
            self.pitch = self.smoothedPitch
            self.roll  = self.smoothedRoll
            self.yaw   = motion.attitude.yaw * 180 / .pi
        }
        print("[MotionManager] startDeviceMotionUpdates dispatched")

        // Watchdog: if we believe pods are connected but no frames arrived
        // for 2s, downgrade to waitingForData (covers "pods on desk").
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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

    func stop() {
        manager.stopDeviceMotionUpdates()
        watchdog?.invalidate()
        watchdog = nil
        if status.isLive || status == .waitingForData {
            status = .waitingForAirPods
        }
    }

    /// User-initiated retry. Force-stops then re-starts the motion stream
    /// from a clean slate. Helps when AirPods connect AFTER the app launched
    /// or routing changed mid-session and CMHeadphoneMotionManager didn't
    /// auto-pick them up.
    func restart() {
        print("[MotionManager] restart() requested")
        manager.stopDeviceMotionUpdates()
        watchdog?.invalidate()
        watchdog = nil
        lastDataAt = nil
        status = .unknown
        start()
    }

    // MARK: - CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        // Pods are now routed to this iPhone. Data may not be flowing yet
        // (need them in the ears). Mark as waitingForData; the data callback
        // upgrades to .live as soon as a frame arrives.
        print("[MotionManager] delegate: didConnect -> .waitingForData")
        if !status.isLive { status = .waitingForData }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        print("[MotionManager] delegate: didDisconnect -> .waitingForAirPods")
        status = .waitingForAirPods
    }
}
