# TODOS

Captured during /plan-eng-review (2026-05-02) and /plan-ceo-review (2026-05-03)
for the AirBoxer Polished Vertical Slice and App Store launch. All items are
explicitly OUT of scope for v1.0 — recorded here so they don't get lost.

## Bump deployment target to iOS 17 + migrate MotionManager to @Observable

**Why:** global preference (use `@Observable` over `ObservableObject`). Blocked currently by iOS 16 deployment target set in `project.yml`.

**Where:**
- `project.yml` — `deploymentTarget.iOS: "17.0"`
- `AirpodsGame/Game/MotionManager.swift` — replace `ObservableObject` + `@Published` with `@Observable`, mark class `@MainActor final`
- `AirpodsGame/ContentView.swift` — replace `@StateObject private var motion` with `@State private var motion`

**Effort:** ~30 min. Do after the polish slice ships and the friend playtest is done.

**Risk:** zero — iPhone 17 Pro test device runs iOS 26.4.2; deployment-target bump only affects which devices can install.

---

## Unit tests for currentHeadZone() and telegraph timing math

**Why:** the dodge resolution math has clear input → output contracts (roll/pitch in degrees → DodgeZone enum, telegraph duration → minimum reaction time). Worth pinning with tests once the behavior is stable, so future changes can't silently regress the dodge feel.

**Where:**
- New `AirpodsGameTests/` target (XCTest)
- Tests for `GameScene.currentHeadZone()` — table-driven, edge cases at threshold boundaries (±14°, ±22°)
- Tests for `advanceRound()` telegraph-floor cap (must never go below 0.7s per design doc premise #3)

**Effort:** ~2 hrs (XCTest target setup + ~10 test cases).

**Wait until:** the polish slice ships and the dodge-feel contract is stable. Don't pin behavior that might still change.

---

## Split GameScene.swift

**Why:** file is 844 LoC today and will hit ~1100-1200 LoC after this slice (cards, audio hooks, sprite animation, FightPhase state machine). The real seams only emerge after the work lands — premature splits cost more than they save.

**Where (likely shape):**
- `GameScene.swift` — state, game loop, public API, ~300 LoC
- `GameScene+Setup.swift` — `setupBackground()`, `setupOpponent()`, `setupHUD()`, `setupCards()`, ~400 LoC
- `GameScene+Punch.swift` — `nextPunch()`, `telegraphPunch()`, `windUpGlove()`, `throwPunch()`, `resolvePunch()`, ~250 LoC
- `GameScene+Effects.swift` — flash, shake, particle, hit/dodge text, ~200 LoC

**Effort:** ~1 hr extension-based split with no behavior changes.

**Wait until:** you actually feel the pain. Real seams reveal themselves after working in the file for a weekend, not before.

---

## App Preview video (v1.1 highest-leverage post-launch lever)

**Why:** Apple's own data shows preview videos lift App Store conversion ~30% over screenshots alone. For AirBoxer specifically, the value is unusually high — the magic of head-tracking dodge is impossible to convey in a static screenshot but obvious in 5 seconds of video. Deferred from v1.0 per /plan-ceo-review decision; this is the single highest-leverage post-launch lever.

**Where:**
- Capture via Xcode > Devices > Take Screenshot/Recording on iPhone 17 Pro (or iOS Simulator if a real device recording isn't viable)
- Edit in iMovie or Final Cut: trim, add text overlays ("Tilt to slip" / "Nod to duck")
- Export 1080x1920 portrait, H.264, < 500MB
- Upload via App Store Connect Media Manager
- Required device classes: iPhone 6.7", iPhone 6.5"

**Effort:** ~2 hrs end-to-end.

**Wait until:** v1.0 has been live for at least a week and you've validated the gameplay loop with real feedback. Re-recording later means using the most polished version of the game.

---

## Opponents 4-8 (v1.1 / v1.2 content drops)

**Why:** v1.0 ships with 3 opponents (Sandbag tutorial + Vitrine Bloom + The Warden) per Apple's Guideline 4.2 minimum-functionality bar. More opponents = more retention, more screenshots, more App Store editorial appeal, more reasons to come back to the app.

**Where:**
- Add new entries via `OpponentDefinition` static factory (data-driven from /plan-eng-review Issue 1)
- Each opponent: original character, 3-frame sprite, chiptune track, telegraph pattern, pep-talk text, KO sequence
- Localize new strings into 5 languages (en + es + fr + de + ja)
- Suggested roster expansion: SUMOTORI ŌKAMI (Tokyo, slow + heavy), RING-O THE ROBOT (frame-perfect tells), LEFT-HOOK LOLA (lefty boxer flips telegraphs), MIDNIGHT (silhouette opponent that fights in low light), ICEBERG (final-final boss, multi-phase)

**Effort:** ~1 day per opponent once v1.0's slice is dialed (sprite art is the bottleneck).

**Wait until:** v1.0 ships and you have at least one round of real-user feedback to inform what kind of opponent the game actually wants more of.

---

## Daily Challenge mode

**Why:** classic retention mechanic. Single fight per day against a known opponent (cycles through the roster) with a fixed but rotating telegraph sequence. Players come back daily for the streak. GameKit leaderboard for "Daily Challenge streak" already configured. Free implementation since the engine is data-driven.

**Where:**
- New `DailyChallenge.swift` — uses current date as seed for deterministic telegraph sequence
- New menu entry: "Daily Challenge" with streak count
- New leaderboard: `com.airdodge.AirpodsGame.leaderboard.daily_streak`
- App badge count shows current streak (Apple permission: notifications)

**Effort:** ~1 weekend.

**Wait until:** v1.0 has retention metrics. If players are coming back even without a daily challenge, this just polishes the loop. If they're not, this is the right lever.

---

## iPad layout

**Why:** currently iPhone-only per `Info.plist` (`UIDeviceFamily` set to iPhone only). iPad has the same `CMHeadphoneMotionManager` support and the bigger screen makes the punch animations more dramatic. Trivially expands the addressable audience.

**Where:**
- `Info.plist` — change `UIDeviceFamily` to include `2` (iPad)
- `project.yml` — `TARGETED_DEVICE_FAMILY = "1,2"`
- `ContentView.swift` — verify `GeometryReader` adapts (it should already)
- `GameScene.swift` — verify HUD chip positioning works at iPad scale (probably needs minor adjustment)
- New screenshot set for iPad 12.9" (Apple requires)

**Effort:** ~half day (verify scaling) + ~2 hrs (iPad screenshot set).

**Wait until:** v1.0 has shipped on iPhone and you have data on iPad demand (App Store search shows "AirBoxer" + iPad searches even though you're not on iPad yet).

---

## Apple TV companion mode

**Why:** the canonical "wow demo" form factor — friend stands in living room with AirPods on, Apple TV displays the fight on the big screen, friends/family watch and yell DUCK. `CMHeadphoneMotionManager` doesn't exist on tvOS, so this requires an iPhone-as-motion-relay architecture (iPhone reads AirPods motion → streams to Apple TV via MultipeerConnectivity).

**Where:**
- New tvOS target in `project.yml` (`AirBoxerTV`)
- iPhone gains a "Cast to Apple TV" mode in Settings
- `MotionRelayService.swift` — uses `MCSession` over Bonjour/local network to stream `(roll, pitch)` 25Hz from iPhone to AppleTV
- AppleTV target reuses GameScene + AudioSystem + OpponentDefinition (engine portable)
- Requires both devices on same Wi-Fi; no internet
- Pairing UX: iPhone shows "Searching for Apple TV..." → "Connect" prompt on TV

**Effort:** ~2-3 weekends (a different project in the same family — networking layer, pairing UX, two app targets).

**Wait until:** v1.0 ships and any actual user requests it. This is the most-cool, longest-tail extension; don't gold-plate before validating demand.
