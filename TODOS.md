# TODOS

Captured during /plan-eng-review for the AirBoxer Polished Vertical Slice (2026-05-02).
All three are explicitly OUT of scope for the current slice — recorded here so they don't get lost.

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
