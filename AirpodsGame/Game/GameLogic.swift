import Foundation

// Pure, UI-free game rules. Everything here is unit-tested in AirBoxerTests —
// keep it free of SpriteKit, SwiftUI and singletons.

// MARK: - Dodge resolution

enum DodgeResolver {
    /// Maps a head pose (degrees) to the dodge zone it occupies.
    /// Looking down makes pitch negative; tilting left makes roll negative.
    static func zone(roll: Double, pitch: Double,
                     rollThreshold: Double, duckThreshold: Double) -> DodgeZone {
        if pitch < -duckThreshold { return .duck }
        if roll < -rollThreshold  { return .left }
        if roll >  rollThreshold  { return .right }
        return .center
    }

    /// Whether standing in `zone` when `punch` lands counts as a dodge.
    /// Jabs are straight punches, so either slip works.
    static func isDodged(_ punch: PunchType, in zone: DodgeZone) -> Bool {
        switch punch {
        case .jab: return zone == .left || zone == .right
        default:   return zone == punch.requiredZone
        }
    }

    /// Touch controls: the screen is split into three columns. Left column
    /// slips left, right column slips right, the middle column ducks.
    /// `x` is the touch position, `width` the scene width (same units).
    static func touchZone(x: Double, width: Double) -> DodgeZone {
        guard width > 0 else { return .center }
        let fraction = x / width
        if fraction < 1.0 / 3.0 { return .left }
        if fraction > 2.0 / 3.0 { return .right }
        return .duck
    }
}

// MARK: - Head calibration

enum HeadCalibration {
    struct Pose: Equatable { var pitch: Double; var roll: Double }

    /// A neutral pose further than this from the motion reference frame is
    /// treated as a dodge in progress, not a posture, and ignored.
    static let maxNeutralOffset = 40.0

    static func neutral(current: Pose, previous: Pose) -> Pose {
        guard abs(current.pitch) <= maxNeutralOffset,
              abs(current.roll) <= maxNeutralOffset else { return previous }
        return current
    }
}

// MARK: - Control mode

/// How the player dodges in a fight.
enum ControlMode: String, Equatable {
    /// The real game: head motion from headphones that support head tracking.
    case headTracking
    /// Fallback for players without compatible headphones: hold a pad.
    case touch

    /// Head tracking always wins when it's live. Touch is used only when the
    /// player opted in and head tracking isn't streaming. `nil` = can't fight.
    static func resolve(headTrackingLive: Bool, touchOptIn: Bool) -> ControlMode? {
        if headTrackingLive { return .headTracking }
        if touchOptIn { return .touch }
        return nil
    }

    /// Leaderboards stay head-tracking-only so touch scores (easier) don't
    /// compete with the motion game.
    var postsToLeaderboards: Bool { self == .headTracking }
}

// MARK: - Opponent ladder

/// Punch-Out-style ladder: the first two fights are always open; every later
/// opponent opens once the opponent before them in the roster is beaten.
enum OpponentLadder {
    static func isOpen(_ opponent: OpponentDefinition,
                       roster: [OpponentDefinition] = OpponentDefinition.allOpponents,
                       beaten: Set<String>) -> Bool {
        guard opponent.bossRank > 1,
              let index = roster.firstIndex(where: { $0.id == opponent.id }),
              index > 0 else { return true }
        return beaten.contains(roster[index - 1].id)
    }

    /// The opponent that must be beaten to open `opponent`, if it's closed.
    static func gatekeeper(for opponent: OpponentDefinition,
                           roster: [OpponentDefinition] = OpponentDefinition.allOpponents,
                           beaten: Set<String>) -> OpponentDefinition? {
        guard !isOpen(opponent, roster: roster, beaten: beaten),
              let index = roster.firstIndex(where: { $0.id == opponent.id }) else { return nil }
        return roster[index - 1]
    }
}

/// Which opponents the player has knocked out at least once.
struct LadderStore {
    static let key = "ladder.beatenOpponents"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var beaten: Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func recordWin(over opponentID: String) {
        var set = beaten
        set.insert(opponentID)
        defaults.set(set.sorted(), forKey: Self.key)
    }
}

// MARK: - Review prompt

/// When to ask for an App Store rating. The prompt only follows a satisfying
/// moment, never on the first session, never twice for one app version, and
/// at most once every `minimumDaysBetweenPrompts` days. iOS itself caps the
/// sheet at three showings a year on top of this.
struct ReviewPromptPolicy {
    struct State: Equatable {
        var sessions = 0
        var completedFights = 0
        var lastPromptDate: Date?
        var lastPromptVersion: String?
    }

    enum Moment: Equatable {
        /// A fight ended. `won` is a knockout the player landed.
        case fightEnded(won: Bool, againstTutorial: Bool, newBestScore: Bool)
    }

    static let minimumSessions = 2
    static let minimumCompletedFights = 3
    static let minimumDaysBetweenPrompts = 120.0

    /// A real win (not the can't-lose tutorial) or a new personal best.
    static func isSatisfying(_ moment: Moment) -> Bool {
        switch moment {
        case let .fightEnded(won, againstTutorial, newBestScore):
            return (won && !againstTutorial) || newBestScore
        }
    }

    static func shouldPrompt(state: State, moment: Moment, now: Date, appVersion: String) -> Bool {
        guard isSatisfying(moment) else { return false }
        guard state.sessions >= minimumSessions else { return false }
        guard state.completedFights >= minimumCompletedFights else { return false }
        if state.lastPromptVersion == appVersion { return false }
        if let last = state.lastPromptDate,
           now.timeIntervalSince(last) < minimumDaysBetweenPrompts * 86_400 {
            return false
        }
        return true
    }
}

/// UserDefaults persistence for `ReviewPromptPolicy`.
struct ReviewPromptStore {
    private enum Key {
        static let sessions = "review.sessions"
        static let fights = "review.completedFights"
        static let lastDate = "review.lastPromptDate"
        static let lastVersion = "review.lastPromptVersion"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var state: ReviewPromptPolicy.State {
        ReviewPromptPolicy.State(
            sessions: defaults.integer(forKey: Key.sessions),
            completedFights: defaults.integer(forKey: Key.fights),
            lastPromptDate: defaults.object(forKey: Key.lastDate) as? Date,
            lastPromptVersion: defaults.string(forKey: Key.lastVersion)
        )
    }

    func recordSession() {
        defaults.set(defaults.integer(forKey: Key.sessions) + 1, forKey: Key.sessions)
    }

    /// Counts the fight, then decides. Call `recordPromptShown` only once
    /// the prompt was actually requested, so a skipped prompt isn't burned.
    func registerFightAndCheck(_ moment: ReviewPromptPolicy.Moment,
                               now: Date = Date(),
                               appVersion: String = Bundle.main.shortVersion) -> Bool {
        defaults.set(defaults.integer(forKey: Key.fights) + 1, forKey: Key.fights)
        return ReviewPromptPolicy.shouldPrompt(state: state, moment: moment,
                                               now: now, appVersion: appVersion)
    }

    func recordPromptShown(now: Date = Date(), appVersion: String = Bundle.main.shortVersion) {
        defaults.set(now, forKey: Key.lastDate)
        defaults.set(appVersion, forKey: Key.lastVersion)
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
