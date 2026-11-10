import CoreMotion
import Observation
import os

/// Subsystem visible via `idevicesyslog | grep Neckline.motion`
private let log = Logger(subsystem: "com.airdodge.AirpodsGame", category: "Neckline.motion")

// CMHeadphoneMotionManager wrapper.
//
// Why head motion only "sometimes" arrives:
//   1. Hardware: only headphones with a motion chip report head tracking.
//   2. Permission: NSMotionUsageDescription is in Info.plist, and the user
//      must allow Motion & Fitness on the first startDeviceMotionUpdates call.
//   3. Wear detection: earbuds must be IN the ears; on the desk = no data.
//   4. Route: earbuds must be connected to THIS iPhone.
//
// The delegate fires on route changes, independent of whether frames flow, so
// we expose a status enum and an actionable hint for the UI.

@MainActor
@Observable
final class MotionManager: NSObject, CMHeadphoneMotionManagerDelegate {

    enum Status {
        case unknown
        case unavailable
        case permissionDenied
        case waitingForHeadphones
        case waitingForData
        case live

        static let supportedHeadphones = String(localized: "headphones that support head tracking")

        var label: String {
            switch self {
            case .unknown:              return String(localized: "Looking for earbuds…")
            case .unavailable:          return String(localized: "Head tracking unavailable")
            case .permissionDenied:     return String(localized: "Tap to allow Motion & Fitness")
            case .waitingForHeadphones: return String(localized: "No earbuds connected")
            case .waitingForData:       return String(localized: "Put your earbuds in")
            case .live:                 return String(localized: "Head tracking on")
            }
        }

        var nextStep: String {
            switch self {
            case .unknown:
                return String(localized: "Searching for earbuds. This takes a moment after launch.")
            case .unavailable:
                return String(localized: "This iPhone can't read head motion. Routines still run in guided mode with on-screen timing.")
            case .permissionDenied:
                return String(localized: "Motion & Fitness access is off. Tap the status chip to open Settings and turn it on.")
            case .waitingForHeadphones:
                return String(localized: "Connect \(Self.supportedHeadphones) for posture alerts and motion-checked reps. Routines also run in guided mode without them.")
            case .waitingForData:
                return String(localized: "Your earbuds are connected. Put them in your ears — head motion only streams while they're worn.")
            case .live:
                return String(localized: "Head tracking is on. Sit tall and start a session.")
            }
        }

        var isLive: Bool { if case .live = self { return true }; return false }
    }

    private let manager = CMHeadphoneMotionManager()
    private let smoothing: Double = 0.8

    /// Head pose relative to the last `recenter()`.
    private(set) var pose: HeadPose = .zero
    var status: Status = .unknown

    @ObservationIgnored private var neutral: HeadPose = .zero
    @ObservationIgnored private var smoothed: HeadPose = .zero
    @ObservationIgnored private var lastDataAt: Date?
    @ObservationIgnored private var watchdog: Timer?
    /// Makes `start()` idempotent so SwiftUI re-firing `.onAppear` doesn't
    /// tear down an in-flight motion stream.
    @ObservationIgnored private var isStreaming = false

    static let shared = MotionManager()

    private override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ABFakeMotion") {
            status = .live
            return
        }
        #endif
        let available = manager.isDeviceMotionAvailable
        let auth = CMMotionActivityManager.authorizationStatus()
        log.notice("start(): available=\(available), auth=\(auth.rawValue)")

        if auth == .denied || auth == .restricted {
            status = .permissionDenied
            return
        }
        guard available else {
            status = .unavailable
            return
        }
        if isStreaming { return }

        if status == .unknown || status == .unavailable {
            status = .waitingForHeadphones
        }

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let error {
                log.notice("data error: \(error.localizedDescription)")
                return
            }
            guard let motion else { return }
            // Extract plain Doubles before hopping — CMDeviceMotion isn't Sendable.
            let p = motion.attitude.pitch * 180 / .pi
            let r = motion.attitude.roll * 180 / .pi
            let y = motion.attitude.yaw * 180 / .pi
            Task { @MainActor [weak self] in
                self?.ingest(pitch: p, roll: r, yaw: y)
            }
        }
        isStreaming = true

        // No frames for 2s while "live" = earbuds probably out of the ears.
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .live = self.status,
                   let last = self.lastDataAt,
                   Date().timeIntervalSince(last) > 2.0 {
                    self.status = .waitingForData
                }
            }
        }
    }

    private func ingest(pitch: Double, roll: Double, yaw: Double) {
        lastDataAt = Date()
        if !status.isLive { status = .live }
        let a = smoothing, b = 1 - smoothing
        smoothed.pitch = a * smoothed.pitch + b * pitch
        smoothed.roll = a * smoothed.roll + b * roll
        // Smooth yaw on the unwrapped delta so the ±180° seam doesn't spike.
        smoothed.yaw = HeadCalibration.wrap(smoothed.yaw + b * HeadCalibration.wrap(yaw - smoothed.yaw))
        publishPose()
    }

    private func publishPose() {
        pose = HeadPose(pitch: smoothed.pitch - neutral.pitch,
                        roll: smoothed.roll - neutral.roll,
                        yaw: HeadCalibration.wrap(smoothed.yaw - neutral.yaw))
    }

    /// Treats the current head pose as neutral. Ignored unless data is live;
    /// a pose far off-center is rejected so a held stretch can't become
    /// the new "upright". Yaw always re-zeroes, since headphone yaw drifts.
    func recenter() {
        guard status.isLive, lastDataAt != nil else { return }
        neutral = HeadCalibration.neutral(current: smoothed, previous: neutral)
        neutral.yaw = smoothed.yaw
        publishPose()
        log.notice("recenter: pitch=\(self.neutral.pitch) roll=\(self.neutral.roll)")
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        watchdog?.invalidate()
        watchdog = nil
        isStreaming = false
        if status.isLive || status == .waitingForData {
            status = .waitingForHeadphones
        }
    }

    /// User-initiated retry from a clean slate.
    func restart() {
        manager.stopDeviceMotionUpdates()
        watchdog?.invalidate()
        watchdog = nil
        lastDataAt = nil
        isStreaming = false
        status = .unknown
        start()
    }

    #if DEBUG
    /// Screenshot fixture hook: drives the pose without hardware.
    func setFakePose(_ fake: HeadPose) { pose = fake }
    #endif

    // MARK: - CMHeadphoneMotionManagerDelegate

    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.status.isLive { self.status = .waitingForData }
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            self?.status = .waitingForHeadphones
        }
    }
}
