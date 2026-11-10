import Foundation
import Testing
@testable import AirpodsGame

// MARK: - Slouch detection

@Suite struct SlouchDetectorTests {
    @Test func uprightNeverNudges() {
        var d = SlouchDetector(threshold: 15, grace: 10)
        for t in stride(from: 0.0, to: 60, by: 0.1) {
            #expect(!d.ingest(pitch: -5, at: t))
        }
        #expect(d.state == .upright)
    }

    @Test func nudgesOnceGraceRunsOut() {
        var d = SlouchDetector(threshold: 15, grace: 10, repeatInterval: 45)
        #expect(!d.ingest(pitch: -20, at: 0))
        #expect(d.state == .drifting)
        #expect(!d.ingest(pitch: -20, at: 9.9))
        #expect(d.ingest(pitch: -20, at: 10))
        #expect(d.state == .slouching)
        // No repeat nudge inside the repeat interval.
        #expect(!d.ingest(pitch: -20, at: 30))
        #expect(d.ingest(pitch: -20, at: 55))
    }

    @Test func liftingHeadResetsTheTimer() {
        var d = SlouchDetector(threshold: 15, grace: 10)
        _ = d.ingest(pitch: -20, at: 0)
        _ = d.ingest(pitch: 0, at: 5)
        #expect(d.state == .upright)
        #expect(!d.ingest(pitch: -20, at: 6))
        #expect(!d.ingest(pitch: -20, at: 15))   // only 9s since it dropped again
        #expect(d.ingest(pitch: -20, at: 16))
    }

    @Test func hysteresisBandKeepsSlouchState() {
        var d = SlouchDetector(threshold: 15, grace: 1, hysteresis: 3)
        _ = d.ingest(pitch: -20, at: 0)
        _ = d.ingest(pitch: -20, at: 1)
        #expect(d.state == .slouching)
        _ = d.ingest(pitch: -13, at: 2)          // above threshold, inside the band
        #expect(d.state == .slouching)
        _ = d.ingest(pitch: -11, at: 3)          // clearly up
        #expect(d.state == .upright)
    }

    @Test func hysteresisBandDoesNotStartATimerFromUpright() {
        var d = SlouchDetector(threshold: 15, grace: 1, hysteresis: 3)
        _ = d.ingest(pitch: -13, at: 0)
        _ = d.ingest(pitch: -13, at: 5)
        #expect(d.state == .upright)
    }
}

@Suite struct SessionStatsTests {
    @Test func countsUprightAndSlouchedTime() {
        var s = SessionStats()
        s.add(seconds: 0.5, state: .upright)
        s.add(seconds: 0.5, state: .drifting)
        s.add(seconds: 1.0, state: .slouching)
        #expect(s.trackedSeconds == 2)
        #expect(s.uprightSeconds == 1)
        #expect(s.uprightFraction == 0.5)
    }

    @Test func dropsLongGaps() {
        var s = SessionStats()
        s.add(seconds: 300, state: .upright)
        #expect(s.trackedSeconds == SessionStats.maxStep)
    }

    @Test func emptySessionIsFullyUpright() {
        #expect(SessionStats().uprightFraction == 1)
    }
}

// MARK: - Exercises

@Suite struct MovementTests {
    @Test(arguments: [
        (Movement.lookDown, HeadPose(pitch: -25, roll: 0, yaw: 0), 1.0),
        (.lookUp, HeadPose(pitch: 9, roll: 0, yaw: 0), 0.5),
        (.tiltLeft, HeadPose(pitch: 0, roll: -20, yaw: 0), 1.0),
        (.tiltRight, HeadPose(pitch: 0, roll: -20, yaw: 0), 0.0),   // wrong way
        (.turnLeft, HeadPose(pitch: 0, roll: 0, yaw: 35), 1.0),
        (.turnRight, HeadPose(pitch: 0, roll: 0, yaw: -70), 2.0),
    ])
    func progress(movement: Movement, pose: HeadPose, expected: Double) {
        #expect(abs(movement.progress(pose) - expected) < 1e-9)
    }

    @Test func rangeScaleLowersTheTarget() {
        let pose = HeadPose(pitch: 0, roll: -14, yaw: 0)
        #expect(Movement.tiltLeft.progress(pose, rangeScale: 0.7) >= 1)
        #expect(Movement.tiltLeft.progress(pose, rangeScale: 1.0) < 1)
    }
}

@Suite struct HoldTrackerTests {
    /// Feeds `progress` from `from` to `to` in 0.1s steps; returns reps completed.
    @discardableResult
    func feed(_ t: inout HoldTracker, _ progress: Double, from: Double, to: Double) -> Int {
        var reps = 0
        for time in stride(from: from, to: to, by: 0.1) where t.ingest(progress: progress, at: time) {
            reps += 1
        }
        return reps
    }

    @Test func holdCompletesARep() {
        var t = HoldTracker(reps: 2, holdSeconds: 3)
        feed(&t, 0.5, from: 0, to: 1)
        #expect(t.phase == .reach)
        feed(&t, 1.0, from: 1, to: 4.2)
        #expect(t.completedReps == 1)
        #expect(t.phase == .release)
    }

    @Test func mustReturnToCenterBeforeNextRep() {
        var t = HoldTracker(reps: 2, holdSeconds: 1)
        feed(&t, 1.0, from: 0, to: 1.3)
        #expect(t.completedReps == 1)
        // Staying at the target doesn't start rep 2.
        feed(&t, 1.0, from: 1.3, to: 5)
        #expect(t.completedReps == 1)
        feed(&t, 0.1, from: 5, to: 5.3)
        #expect(t.phase == .reach)
        feed(&t, 1.0, from: 5.3, to: 6.6)
        #expect(t.isDone)
    }

    @Test func droppingOutPausesButKeepsHeldTime() {
        var t = HoldTracker(reps: 1, holdSeconds: 2)
        feed(&t, 1.0, from: 0, to: 1.05)
        let held = t.heldFor
        #expect(held > 0.8)
        feed(&t, 0.5, from: 1.05, to: 2)
        #expect(t.phase == .reach)
        #expect(t.heldFor == held)
        feed(&t, 1.0, from: 2, to: 3.5)
        #expect(t.isDone)
    }

    @Test func guidedPaceDrivesTheTrackerToCompletion() {
        let hold = 4.0
        var t = HoldTracker(reps: 3, holdSeconds: hold)
        var time = 0.0
        while !t.isDone && time < 60 {
            t.ingest(progress: GuidedPace.progress(elapsed: time, hold: hold), at: time)
            time += 0.05
        }
        #expect(t.isDone)
        #expect(time <= 3 * GuidedPace.cycleSeconds(hold: hold) + 1)
    }
}

@Suite struct CalibrationTests {
    @Test func rejectsFarOffNeutral() {
        let prev = HeadPose(pitch: 1, roll: 1, yaw: 0)
        #expect(HeadCalibration.neutral(current: HeadPose(pitch: -50, roll: 0, yaw: 0), previous: prev) == prev)
        let ok = HeadPose(pitch: -10, roll: 5, yaw: 0)
        #expect(HeadCalibration.neutral(current: ok, previous: prev) == ok)
    }

    @Test(arguments: [(190.0, -170.0), (-190.0, 170.0), (45.0, 45.0), (540.0, 180.0)])
    func wrap(input: Double, expected: Double) {
        #expect(HeadCalibration.wrap(input) == expected)
    }
}

// MARK: - Streaks

@Suite struct StreakTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func dayKeyFormat() {
        #expect(DayKey.of(date(2026, 3, 7), calendar: calendar) == "2026-03-07")
    }

    @Test func countsBackFromToday() {
        let days: Set = ["2026-03-05", "2026-03-06", "2026-03-07"]
        #expect(Streak.current(activeDays: days, today: date(2026, 3, 7), calendar: calendar) == 3)
    }

    @Test func aliveUntilMidnightWhenTodayIsEmpty() {
        let days: Set = ["2026-03-05", "2026-03-06"]
        #expect(Streak.current(activeDays: days, today: date(2026, 3, 7), calendar: calendar) == 2)
    }

    @Test func brokenByAMissedDay() {
        let days: Set = ["2026-03-04", "2026-03-05"]
        #expect(Streak.current(activeDays: days, today: date(2026, 3, 7), calendar: calendar) == 0)
    }

    @Test func crossesMonthBoundary() {
        let days: Set = ["2026-02-28", "2026-03-01"]
        #expect(Streak.current(activeDays: days, today: date(2026, 3, 1), calendar: calendar) == 2)
    }

    @Test func qualifyingDays() {
        #expect(DailyRecord(day: "x", routines: 1).keepsStreak)
        #expect(DailyRecord(day: "x", sessionSeconds: 300).keepsStreak)
        #expect(!DailyRecord(day: "x", sessionSeconds: 299).keepsStreak)
    }
}

// MARK: - Monetisation gates

@Suite struct GateTests {
    @Test func freeTierAllowsOnlyFreeRoutines() {
        let free = Routine.catalog.filter { FreeTier.canStart($0, isPro: false) }
        #expect(free.map(\.id) == [Routine.deskReset.id])
        #expect(Routine.catalog.allSatisfy { FreeTier.canStart($0, isPro: true) })
    }

    @Test func catalogIsWellFormed() {
        #expect(Set(Routine.catalog.map(\.id)).count == Routine.catalog.count)
        #expect(Routine.catalog.allSatisfy { !$0.steps.isEmpty })
    }

    @Test func reviewAskedAtMilestonesOncePerVersion() {
        #expect(ReviewGate.shouldAsk(totalRoutines: 3, lastPromptVersion: nil, appVersion: "2.0"))
        #expect(!ReviewGate.shouldAsk(totalRoutines: 3, lastPromptVersion: "2.0", appVersion: "2.0"))
        #expect(!ReviewGate.shouldAsk(totalRoutines: 4, lastPromptVersion: nil, appVersion: "2.0"))
        #expect(ReviewGate.shouldAsk(totalRoutines: 15, lastPromptVersion: "1.9", appVersion: "2.0"))
    }
}
