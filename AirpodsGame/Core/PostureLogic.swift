import Foundation

// Pure, UI-free posture and exercise rules. Everything here is unit-tested in
// AirBoxerTests — keep it free of SwiftUI, CoreMotion and singletons.

// MARK: - Head pose

/// Head orientation in degrees, relative to the calibrated neutral pose.
/// Looking down makes pitch negative, tilting left makes roll negative,
/// turning left makes yaw positive.
struct HeadPose: Equatable, Sendable {
    var pitch: Double
    var roll: Double
    var yaw: Double

    static let zero = HeadPose(pitch: 0, roll: 0, yaw: 0)
}

enum HeadCalibration {
    /// A "neutral" further than this from the motion reference frame is a
    /// held stretch, not a resting posture, and is ignored.
    static let maxNeutralOffset = 40.0

    static func neutral(current: HeadPose, previous: HeadPose) -> HeadPose {
        guard abs(current.pitch) <= maxNeutralOffset,
              abs(current.roll) <= maxNeutralOffset else { return previous }
        return current
    }

    /// Wraps an angle into -180...180 so yaw stays continuous across the seam.
    static func wrap(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

// MARK: - Posture monitoring

enum PostureState: Equatable, Sendable {
    /// Head is stacked over the shoulders.
    case upright
    /// Head has dropped past the threshold but the grace period hasn't run out.
    case drifting
    /// Head has been down long enough to count as tech-neck.
    case slouching
}

/// Detects sustained forward-head posture from pitch samples.
struct SlouchDetector: Sendable {
    /// Degrees of downward pitch that count as "head dropped".
    let threshold: Double
    /// Seconds the head may stay down before it counts as slouching.
    let grace: TimeInterval
    /// Minimum seconds between repeated nudges during one slouch.
    let repeatInterval: TimeInterval
    /// Recovery requires lifting this many degrees above the threshold, so
    /// hovering on the line doesn't flicker between states.
    let hysteresis: Double

    private(set) var state: PostureState = .upright
    private var downSince: TimeInterval?
    private var lastNudgeAt: TimeInterval?

    init(threshold: Double, grace: TimeInterval,
         repeatInterval: TimeInterval = 45, hysteresis: Double = 3) {
        self.threshold = threshold
        self.grace = grace
        self.repeatInterval = repeatInterval
        self.hysteresis = hysteresis
    }

    /// Feeds one pitch sample taken at time `t` (seconds, monotonic).
    /// Returns `true` when the user should be nudged.
    mutating func ingest(pitch: Double, at t: TimeInterval) -> Bool {
        let isDown = pitch < -threshold
        let isClearlyUp = pitch > -(threshold - hysteresis)

        if isClearlyUp || (!isDown && state == .upright) {
            state = .upright
            downSince = nil
            lastNudgeAt = nil
            return false
        }

        let since = downSince ?? t
        downSince = since
        guard t - since >= grace else {
            state = .drifting
            return false
        }
        state = .slouching
        if let last = lastNudgeAt, t - last < repeatInterval { return false }
        lastNudgeAt = t
        return true
    }
}

/// Running totals for one posture session.
struct SessionStats: Equatable, Sendable, Codable {
    var trackedSeconds: Double = 0
    var uprightSeconds: Double = 0
    var nudges = 0

    /// Seconds of a single sample gap that still count. Longer gaps (app
    /// suspended, earbuds out) are dropped instead of inflating the totals.
    static let maxStep: Double = 1.0

    mutating func add(seconds: Double, state: PostureState) {
        let dt = min(max(seconds, 0), Self.maxStep)
        trackedSeconds += dt
        if state != .slouching { uprightSeconds += dt }
    }

    var uprightFraction: Double {
        trackedSeconds > 0 ? uprightSeconds / trackedSeconds : 1
    }
}

// MARK: - Exercises

enum Movement: String, CaseIterable, Sendable, Codable {
    case lookDown, lookUp, tiltLeft, tiltRight, turnLeft, turnRight

    /// Degrees to reach at the "normal" range setting.
    var baseTarget: Double {
        switch self {
        case .lookDown:            return 25
        case .lookUp:              return 18
        case .tiltLeft, .tiltRight: return 20
        case .turnLeft, .turnRight: return 35
        }
    }

    /// How far along this movement the pose is, in degrees (negative = the
    /// opposite direction).
    func amount(_ pose: HeadPose) -> Double {
        switch self {
        case .lookDown:  return -pose.pitch
        case .lookUp:    return pose.pitch
        case .tiltLeft:  return -pose.roll
        case .tiltRight: return pose.roll
        case .turnLeft:  return pose.yaw
        case .turnRight: return -pose.yaw
        }
    }

    /// 0 at neutral, 1 at the target, above 1 past it.
    func progress(_ pose: HeadPose, rangeScale: Double = 1) -> Double {
        max(0, amount(pose) / (baseTarget * rangeScale))
    }

    var title: String {
        switch self {
        case .lookDown:  return String(localized: "Chin to chest")
        case .lookUp:    return String(localized: "Look up")
        case .tiltLeft:  return String(localized: "Ear to left shoulder")
        case .tiltRight: return String(localized: "Ear to right shoulder")
        case .turnLeft:  return String(localized: "Turn left")
        case .turnRight: return String(localized: "Turn right")
        }
    }

    var cue: String {
        switch self {
        case .lookDown:  return String(localized: "Slowly lower your chin toward your chest. Keep your shoulders relaxed.")
        case .lookUp:    return String(localized: "Lift your gaze to the ceiling. Move gently, no further than is comfortable.")
        case .tiltLeft:  return String(localized: "Let your left ear drop toward your left shoulder. Don't lift the shoulder.")
        case .tiltRight: return String(localized: "Let your right ear drop toward your right shoulder. Don't lift the shoulder.")
        case .turnLeft:  return String(localized: "Turn your head to look over your left shoulder. Keep your chin level.")
        case .turnRight: return String(localized: "Turn your head to look over your right shoulder. Keep your chin level.")
        }
    }
}

/// Counts motion-verified reps of one held stretch.
struct HoldTracker: Sendable {
    enum Phase: Equatable, Sendable {
        /// Moving toward the target.
        case reach
        /// At the target, hold timer running.
        case hold
        /// Rep done; return toward neutral before the next one.
        case release
        case done
    }

    let reps: Int
    let holdSeconds: Double
    /// Below this progress the hold timer pauses.
    let holdTolerance: Double
    /// Below this progress a released rep counts as back at neutral.
    let releaseLevel: Double

    private(set) var phase: Phase = .reach
    private(set) var completedReps = 0
    private(set) var heldFor: Double = 0
    private var lastT: TimeInterval?

    init(reps: Int, holdSeconds: Double, holdTolerance: Double = 0.8, releaseLevel: Double = 0.35) {
        self.reps = max(1, reps)
        self.holdSeconds = max(0.5, holdSeconds)
        self.holdTolerance = holdTolerance
        self.releaseLevel = releaseLevel
    }

    var holdFraction: Double { min(1, heldFor / holdSeconds) }
    var isDone: Bool { phase == .done }

    /// Feeds one progress sample (see `Movement.progress`). Returns `true`
    /// on the sample that completes a rep.
    @discardableResult
    mutating func ingest(progress: Double, at t: TimeInterval) -> Bool {
        let dt = lastT.map { min(max(t - $0, 0), SessionStats.maxStep) } ?? 0
        lastT = t

        switch phase {
        case .done:
            return false
        case .reach:
            if progress >= 1 { phase = .hold }
            return false
        case .hold:
            guard progress >= holdTolerance else {
                phase = .reach   // keep what was held; resume on the next reach
                return false
            }
            heldFor += dt
            guard heldFor >= holdSeconds else { return false }
            completedReps += 1
            heldFor = 0
            phase = completedReps >= reps ? .done : .release
            return true
        case .release:
            if progress <= releaseLevel { phase = .reach }
            return false
        }
    }
}

/// Synthetic progress for guided (timer-only) mode, used when no head
/// tracking is available: each rep is a reach ramp, a hold at the target and
/// a return to neutral.
enum GuidedPace {
    static let reachSeconds = 1.5
    static let releaseSeconds = 2.0
    /// Extra hold time so sampling jitter can't end the hold a tick short.
    static let holdMargin = 0.3

    static func cycleSeconds(hold: Double) -> Double { reachSeconds + hold + holdMargin + releaseSeconds }

    static func progress(elapsed: Double, hold: Double) -> Double {
        let t = elapsed.truncatingRemainder(dividingBy: cycleSeconds(hold: hold))
        if t < reachSeconds { return t / reachSeconds }
        if t < reachSeconds + hold + holdMargin { return 1 }
        return 0
    }
}

// MARK: - Routines

struct RoutineStep: Hashable, Sendable {
    let movement: Movement
    let reps: Int
    let hold: Double
}

struct Routine: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let isPro: Bool
    let steps: [RoutineStep]

    var estimatedSeconds: Double {
        steps.reduce(0) { $0 + Double($1.reps) * GuidedPace.cycleSeconds(hold: $1.hold) }
    }

    var estimatedMinutes: Int { max(1, Int((estimatedSeconds / 60).rounded())) }

    static let deskReset = Routine(
        id: "desk_reset",
        title: String(localized: "Desk Reset"),
        subtitle: String(localized: "Undo an hour of screen time"),
        symbol: "desktopcomputer",
        isPro: false,
        steps: [
            .init(movement: .lookUp, reps: 2, hold: 5),
            .init(movement: .tiltLeft, reps: 2, hold: 6),
            .init(movement: .tiltRight, reps: 2, hold: 6),
            .init(movement: .turnLeft, reps: 2, hold: 4),
            .init(movement: .turnRight, reps: 2, hold: 4),
        ])

    static let catalog: [Routine] = [
        deskReset,
        Routine(
            id: "morning_mobility",
            title: String(localized: "Morning Mobility"),
            subtitle: String(localized: "Wake up a stiff neck"),
            symbol: "sunrise",
            isPro: true,
            steps: [
                .init(movement: .lookDown, reps: 3, hold: 4),
                .init(movement: .lookUp, reps: 3, hold: 4),
                .init(movement: .turnLeft, reps: 3, hold: 3),
                .init(movement: .turnRight, reps: 3, hold: 3),
                .init(movement: .tiltLeft, reps: 2, hold: 5),
                .init(movement: .tiltRight, reps: 2, hold: 5),
            ]),
        Routine(
            id: "tech_neck",
            title: String(localized: "Tech-Neck Relief"),
            subtitle: String(localized: "Long holds for the upper back and sides"),
            symbol: "iphone.gen3",
            isPro: true,
            steps: [
                .init(movement: .lookUp, reps: 3, hold: 8),
                .init(movement: .tiltLeft, reps: 2, hold: 12),
                .init(movement: .tiltRight, reps: 2, hold: 12),
                .init(movement: .lookUp, reps: 2, hold: 8),
            ]),
        Routine(
            id: "wind_down",
            title: String(localized: "Wind Down"),
            subtitle: String(localized: "Slow, gentle range before bed"),
            symbol: "moon.stars",
            isPro: true,
            steps: [
                .init(movement: .lookDown, reps: 2, hold: 10),
                .init(movement: .tiltLeft, reps: 2, hold: 10),
                .init(movement: .tiltRight, reps: 2, hold: 10),
                .init(movement: .turnLeft, reps: 2, hold: 8),
                .init(movement: .turnRight, reps: 2, hold: 8),
            ]),
        Routine(
            id: "driver_reset",
            title: String(localized: "Commute Recovery"),
            subtitle: String(localized: "Rotation work after driving or flights"),
            symbol: "car",
            isPro: true,
            steps: [
                .init(movement: .turnLeft, reps: 4, hold: 3),
                .init(movement: .turnRight, reps: 4, hold: 3),
                .init(movement: .lookUp, reps: 3, hold: 5),
                .init(movement: .lookDown, reps: 3, hold: 5),
            ]),
    ]
}

// MARK: - Progress and streaks

/// One calendar day of activity.
struct DailyRecord: Equatable, Sendable, Codable {
    var day: String
    var sessionSeconds: Double = 0
    var uprightSeconds: Double = 0
    var nudges = 0
    var routines = 0

    /// Minimum posture-session time that keeps a streak alive on its own.
    static let qualifyingSessionSeconds: Double = 300

    var keepsStreak: Bool { routines > 0 || sessionSeconds >= Self.qualifyingSessionSeconds }

    var uprightFraction: Double { sessionSeconds > 0 ? uprightSeconds / sessionSeconds : 0 }
}

enum DayKey {
    static func of(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum Streak {
    /// Consecutive active days ending today, or ending yesterday when today
    /// has no activity yet (the streak is still alive until midnight).
    static func current(activeDays: Set<String>, today: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if !activeDays.contains(DayKey.of(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while activeDays.contains(DayKey.of(day, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

// MARK: - Free tier

enum FreeTier {
    /// Longest posture session without Pro.
    static let sessionLimit: TimeInterval = 10 * 60

    static func canStart(_ routine: Routine, isPro: Bool) -> Bool { isPro || !routine.isPro }
}

// MARK: - Review prompt

enum ReviewGate {
    /// Asks after the 3rd and 15th completed routine, once per app version.
    static let milestones: Set<Int> = [3, 15]

    static func shouldAsk(totalRoutines: Int, lastPromptVersion: String?, appVersion: String) -> Bool {
        milestones.contains(totalRoutines) && lastPromptVersion != appVersion
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
