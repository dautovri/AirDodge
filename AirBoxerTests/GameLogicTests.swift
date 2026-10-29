import Foundation
import Testing
@testable import AirpodsGame

// MARK: - Dodge resolution

@Suite struct DodgeResolverTests {
    let roll = 14.0, duck = 22.0

    @Test(arguments: [
        (0.0, 0.0, DodgeZone.center),
        (-14.0, 0.0, .center),       // exactly on the threshold is not a dodge
        (-14.1, 0.0, .left),
        (14.1, 0.0, .right),
        (0.0, -22.1, .duck),
        (20.0, -30.0, .duck),        // duck wins over a sideways tilt
        (0.0, 30.0, .center),        // looking up is not a dodge
    ])
    func zone(roll r: Double, pitch p: Double, expected: DodgeZone) {
        #expect(DodgeResolver.zone(roll: r, pitch: p, rollThreshold: roll, duckThreshold: duck) == expected)
    }

    @Test func hooksNeedTheOppositeSlip() {
        #expect(DodgeResolver.isDodged(.leftHook, in: .right))
        #expect(!DodgeResolver.isDodged(.leftHook, in: .left))
        #expect(DodgeResolver.isDodged(.rightHook, in: .left))
        #expect(!DodgeResolver.isDodged(.rightHook, in: .center))
    }

    @Test func jabAcceptsEitherSlipButNotDuck() {
        #expect(DodgeResolver.isDodged(.jab, in: .left))
        #expect(DodgeResolver.isDodged(.jab, in: .right))
        #expect(!DodgeResolver.isDodged(.jab, in: .duck))
        #expect(!DodgeResolver.isDodged(.jab, in: .center))
    }

    @Test func uppercutNeedsDuck() {
        #expect(DodgeResolver.isDodged(.uppercut, in: .duck))
        #expect(!DodgeResolver.isDodged(.uppercut, in: .left))
    }

    @Test func touchColumns() {
        #expect(DodgeResolver.touchZone(x: 10, width: 390) == .left)
        #expect(DodgeResolver.touchZone(x: 195, width: 390) == .duck)
        #expect(DodgeResolver.touchZone(x: 380, width: 390) == .right)
        #expect(DodgeResolver.touchZone(x: 10, width: 0) == .center)
    }

    @Test func sensitivityLevelsAreOrdered() {
        let levels = MotionSensitivityLevel.allCases
        for (a, b) in zip(levels, levels.dropFirst()) {
            #expect(a.rollThreshold > b.rollThreshold)
            #expect(a.duckThreshold > b.duckThreshold)
        }
    }
}

// MARK: - Calibration

@Suite struct HeadCalibrationTests {
    @Test func acceptsNaturalPosture() {
        let n = HeadCalibration.neutral(current: .init(pitch: -18, roll: 4), previous: .init(pitch: 0, roll: 0))
        #expect(n == .init(pitch: -18, roll: 4))
    }

    @Test func rejectsAPoseThatLooksLikeADodge() {
        let previous = HeadCalibration.Pose(pitch: -5, roll: 1)
        #expect(HeadCalibration.neutral(current: .init(pitch: -45, roll: 0), previous: previous) == previous)
        #expect(HeadCalibration.neutral(current: .init(pitch: 0, roll: 41), previous: previous) == previous)
    }
}

// MARK: - Control mode

@Suite struct ControlModeTests {
    @Test func headTrackingWinsWhenLive() {
        #expect(ControlMode.resolve(headTrackingLive: true, touchOptIn: true) == .headTracking)
        #expect(ControlMode.resolve(headTrackingLive: true, touchOptIn: false) == .headTracking)
    }

    @Test func touchOnlyWhenOptedIn() {
        #expect(ControlMode.resolve(headTrackingLive: false, touchOptIn: true) == .touch)
        #expect(ControlMode.resolve(headTrackingLive: false, touchOptIn: false) == nil)
    }

    @Test func onlyHeadTrackingPostsToLeaderboards() {
        #expect(ControlMode.headTracking.postsToLeaderboards)
        #expect(!ControlMode.touch.postsToLeaderboards)
    }
}

// MARK: - Ladder

@Suite struct OpponentLadderTests {
    @Test func firstTwoAreAlwaysOpen() {
        #expect(OpponentLadder.isOpen(.sandbag, beaten: []))
        #expect(OpponentLadder.isOpen(.vitrineBloom, beaten: []))
    }

    @Test func wardenOpensAfterBeatingVitrine() {
        #expect(!OpponentLadder.isOpen(.theWarden, beaten: []))
        #expect(!OpponentLadder.isOpen(.theWarden, beaten: ["sandbag"]))
        #expect(OpponentLadder.isOpen(.theWarden, beaten: ["vitrine_bloom"]))
        #expect(OpponentLadder.gatekeeper(for: .theWarden, beaten: [])?.id == "vitrine_bloom")
        #expect(OpponentLadder.gatekeeper(for: .theWarden, beaten: ["vitrine_bloom"]) == nil)
    }

    @Test func storePersistsWins() throws {
        let defaults = try #require(UserDefaults(suiteName: "ladder-\(UUID())"))
        let store = LadderStore(defaults: defaults)
        #expect(store.beaten.isEmpty)
        store.recordWin(over: "vitrine_bloom")
        store.recordWin(over: "vitrine_bloom")
        #expect(store.beaten == ["vitrine_bloom"])
    }
}

// MARK: - Review prompt gating

@Suite struct ReviewPromptPolicyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let realWin = ReviewPromptPolicy.Moment.fightEnded(won: true, againstTutorial: false, newBestScore: false)
    let ready = ReviewPromptPolicy.State(sessions: 2, completedFights: 3)

    @Test func asksAfterARealWinOnceEstablished() {
        #expect(ReviewPromptPolicy.shouldPrompt(state: ready, moment: realWin, now: now, appVersion: "1.1"))
    }

    @Test func neverOnTheFirstSession() {
        var s = ready; s.sessions = 1
        #expect(!ReviewPromptPolicy.shouldPrompt(state: s, moment: realWin, now: now, appVersion: "1.1"))
    }

    @Test func needsAFewFightsFirst() {
        var s = ready; s.completedFights = 2
        #expect(!ReviewPromptPolicy.shouldPrompt(state: s, moment: realWin, now: now, appVersion: "1.1"))
    }

    @Test func tutorialWinsAndPlainLossesDontCount() {
        let tutorial = ReviewPromptPolicy.Moment.fightEnded(won: true, againstTutorial: true, newBestScore: false)
        let loss = ReviewPromptPolicy.Moment.fightEnded(won: false, againstTutorial: false, newBestScore: false)
        #expect(!ReviewPromptPolicy.shouldPrompt(state: ready, moment: tutorial, now: now, appVersion: "1.1"))
        #expect(!ReviewPromptPolicy.shouldPrompt(state: ready, moment: loss, now: now, appVersion: "1.1"))
    }

    @Test func aNewBestCountsEvenOnALoss() {
        let best = ReviewPromptPolicy.Moment.fightEnded(won: false, againstTutorial: false, newBestScore: true)
        #expect(ReviewPromptPolicy.shouldPrompt(state: ready, moment: best, now: now, appVersion: "1.1"))
    }

    @Test func onceperVersionAndSpaced() {
        var s = ready
        s.lastPromptVersion = "1.1"; s.lastPromptDate = now.addingTimeInterval(-400 * 86_400)
        #expect(!ReviewPromptPolicy.shouldPrompt(state: s, moment: realWin, now: now, appVersion: "1.1"))
        s.lastPromptVersion = "1.0"; s.lastPromptDate = now.addingTimeInterval(-119 * 86_400)
        #expect(!ReviewPromptPolicy.shouldPrompt(state: s, moment: realWin, now: now, appVersion: "1.1"))
        s.lastPromptDate = now.addingTimeInterval(-121 * 86_400)
        #expect(ReviewPromptPolicy.shouldPrompt(state: s, moment: realWin, now: now, appVersion: "1.1"))
    }

    @Test func storeCountsFightsAndRecordsThePrompt() throws {
        let defaults = try #require(UserDefaults(suiteName: "review-\(UUID())"))
        let store = ReviewPromptStore(defaults: defaults)
        store.recordSession(); store.recordSession()
        #expect(!store.registerFightAndCheck(realWin, now: now, appVersion: "1.1"))  // fight 1
        #expect(!store.registerFightAndCheck(realWin, now: now, appVersion: "1.1"))  // fight 2
        #expect(store.registerFightAndCheck(realWin, now: now, appVersion: "1.1"))   // fight 3 → ask
        // Not shown (player left the results screen): the chance is kept.
        #expect(store.registerFightAndCheck(realWin, now: now, appVersion: "1.1"))
        store.recordPromptShown(now: now, appVersion: "1.1")
        #expect(!store.registerFightAndCheck(realWin, now: now, appVersion: "1.1"))  // same version
        #expect(store.state.lastPromptVersion == "1.1")
        #expect(store.state.completedFights == 5)
    }
}
