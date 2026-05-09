import SpriteKit
import UIKit

// MARK: - Types

enum DodgeZone: Equatable {
    case center, left, right, duck

    var label: String {
        switch self {
        case .center: return "CENTER"
        case .left:   return "LEFT"
        case .right:  return "RIGHT"
        case .duck:   return "DUCK"
        }
    }
}

enum PunchType: CaseIterable {
    case leftHook   // opponent throws from their left  → dodge RIGHT
    case rightHook  // opponent throws from their right → dodge LEFT
    case jab        // straight punch                  → dodge LEFT or RIGHT
    case uppercut   // rising punch                    → DUCK

    var requiredZone: DodgeZone {
        switch self {
        case .leftHook:  return .right
        case .rightHook: return .left
        case .jab:       return .left   // left OR right, handled in logic
        case .uppercut:  return .duck
        }
    }

    var warningText: String {
        switch self {
        case .leftHook:  return "DODGE RIGHT  →"
        case .rightHook: return "←  DODGE LEFT"
        case .jab:       return "SLIP ASIDE!"
        case .uppercut:  return "↓  DUCK!"
        }
    }

    var warningColor: UIColor {
        switch self {
        case .leftHook, .rightHook:
            return UIColor(red: 1.0, green: 0.65, blue: 0.10, alpha: 1)
        case .jab:
            return UIColor(red: 1.0, green: 0.30, blue: 0.30, alpha: 1)
        case .uppercut:
            return UIColor(red: 0.65, green: 0.40, blue: 1.00, alpha: 1)
        }
    }
}

// MARK: - GameScene

class GameScene: SKScene {

    // MARK: Head zone thresholds (degrees) — read from user settings each frame
    // so changing sensitivity in Settings affects the next dodge resolution.
    private var rollThreshold: Double  { sensitivity.rollThreshold }
    private var duckThreshold: Double  { sensitivity.duckThreshold }
    private var sensitivity: MotionSensitivityLevel {
        let raw = UserDefaults.standard.integer(forKey: SettingsKey.motionSensitivity)
        return MotionSensitivityLevel(rawValue: raw) ?? .standard
    }
    private var hapticsEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.hapticsEnabled)
    }
    private var maxStreak: Int = 0   // for GameKit leaderboard submission

    // MARK: State
    private let maxHp: Int = 5
    private var hp: Int = 5                     { didSet { updateHpBar() } }
    private var score: Int = 0                  { didSet { scoreLabel.text = "\(score)" } }
    private var combo: Int = 0                  { didSet { updateCombo(); maxStreak = max(maxStreak, combo) } }
    private var round: Int = 1
    private var gameOver = false
    private var waitingForDodge = false
    private var currentPunch: PunchType?
    private var punchLanded = false

    /// The opponent driving this fight. Defaults to Vitrine Bloom — set
    /// before `didMove(to:)` to use a different opponent.
    var opponent: OpponentDefinition = .vitrineBloom

    /// Owned audio playback. Silent no-op when files are missing.
    private lazy var audio = AudioSystem()

    // MARK: Fight phase — locked in /plan-eng-review Issue 3
    //
    // Single SKScene + state machine instead of separate SKScenes. Cards are
    // SKNode groups that show/hide based on `phase`. The dramatic beats
    // (opponent intro, between-rounds pep talk, KO sequence) are co-located
    // with the fight logic that triggers them.

    enum FightPhase {
        case intro                  // opponent name card, drumroll → bell → fighting
        case fighting               // active dodge gameplay
        case roundBreak(round: Int) // pep talk card between rounds
        case ko                     // KO sequence, then onGameOver callback
    }

    private var phase: FightPhase = .intro { didSet { updatePhase() } }

    // Card groups — populated in setupCards(), hidden by default
    private var introCard:      SKNode!
    private var roundBreakCard: SKNode!
    private var koCard:         SKNode!
    private var roundBreakText: SKLabelNode!  // updated per round break
    private var koScoreText:    SKLabelNode!  // updated on KO with final score

    // Timing (seconds) — initialized from the opponent in didMove(to:).
    private var telegraphDuration: TimeInterval = 1.6
    private var restDuration:      TimeInterval = 1.2

    // MARK: Nodes — opponent
    private var opponentHead:       SKShapeNode!
    private var opponentBody:       SKShapeNode!
    private var leftGlove:          SKShapeNode!
    private var rightGlove:         SKShapeNode!

    // MARK: Nodes — HUD
    private var scoreChip:          SKNode!
    private var scoreLabel:         SKLabelNode!
    private var roundChip:          SKNode!
    private var roundLabel:         SKLabelNode!
    private var hpBarBg:            SKShapeNode!
    private var hpBarFill:          SKShapeNode!
    private var hpLabel:            SKLabelNode!
    private var warningLabel:       SKLabelNode!
    private var warningBanner:      SKShapeNode!
    private var comboLabel:         SKLabelNode!

    // Three-zone targets
    private var leftZoneRing:       SKShapeNode!
    private var rightZoneRing:      SKShapeNode!
    private var duckZoneRing:       SKShapeNode!
    private var headDot:            SKShapeNode!

    // MARK: Glove resting positions (in scene coords)
    private var leftGloveRest  = CGPoint.zero
    private var rightGloveRest = CGPoint.zero

    var onGameOver: ((Int) -> Void)?

    // Haptic generators (kept alive for low-latency)
    private let lightImpact  = UIImpactFeedbackGenerator(style: .light)
    private let heavyImpact  = UIImpactFeedbackGenerator(style: .heavy)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let notify       = UINotificationFeedbackGenerator()

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.06, green: 0.05, blue: 0.09, alpha: 1)

        // Pull timings from the chosen opponent definition. Lets the
        // 3-opponent roster (Sandbag / Vitrine Bloom / The Warden) all share
        // this scene with no per-opponent code branching.
        // HP assignment is deferred until AFTER setupHUD() because the didSet
        // observer on `hp` calls updateHpBar() which references hpBarFill —
        // which doesn't exist yet at this point. Assigning here would crash
        // with "Fatal error: Unexpectedly found nil while implicitly
        // unwrapping an Optional value" on the SKShapeNode! property.
        telegraphDuration = opponent.telegraphSec
        restDuration      = opponent.restSec

        setupBackground()
        // setupVignette() removed — the 70px black strips were darkening the
        // SCORE/ROUND chips and the dodge hint, hurting readability for a
        // cinematic flourish that the rest of the design didn't need.
        setupOpponent()
        setupHUD()
        setupZoneIndicator()
        setupCards()

        // Now that the HUD nodes exist, assign HP — didSet → updateHpBar()
        // will paint the bar green for the full-HP frac.
        hp = min(opponent.initialHP, maxHp)
        // updateHpBar() also runs explicitly here in case `hp` happens to
        // already equal the default 5 (no didSet fires on no-change).
        updateHpBar()

        // Start opponent music (silent no-op if file missing — see AudioSystem
        // contract). Bell rings on first punch telegraph.
        if let track = opponent.musicTrack {
            audio.startMusic(named: track)
        }

        [lightImpact, heavyImpact, mediumImpact].forEach { $0.prepare() }
        notify.prepare()

        // Phase transitions handle drumroll/bell/intro card. Setting phase
        // triggers updatePhase() which kicks off the intro animation +
        // schedules the transition to .fighting.
        phase = .intro
    }

    // MARK: Background — boxing ring canvas

    private func setupBackground() {
        // Ring floor
        let floor = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height * 0.4))
        floor.fillColor   = SKColor(red: 0.13, green: 0.09, blue: 0.05, alpha: 1)
        floor.strokeColor = .clear
        floor.position    = CGPoint(x: size.width / 2, y: size.height * 0.18)
        floor.zPosition   = -5
        addChild(floor)

        // Spotlight glow on opponent
        let spotlight = SKShapeNode(circleOfRadius: 180)
        spotlight.fillColor   = SKColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 0.10)
        spotlight.strokeColor = .clear
        spotlight.position    = CGPoint(x: size.width / 2, y: size.height * 0.55)
        spotlight.zPosition   = -4
        spotlight.blendMode   = .add
        addChild(spotlight)

        // Corner posts
        for x in [size.width * 0.05, size.width * 0.95] {
            let post = SKShapeNode(rectOf: CGSize(width: 8, height: size.height * 0.55), cornerRadius: 2)
            post.fillColor   = SKColor(red: 0.85, green: 0.72, blue: 0.10, alpha: 0.55)
            post.strokeColor = .clear
            post.position    = CGPoint(x: x, y: size.height * 0.5)
            post.zPosition   = -3
            addChild(post)
        }

        // Ropes
        for frac in [0.55, 0.62, 0.69] as [CGFloat] {
            let rope = SKShapeNode(rectOf: CGSize(width: size.width, height: 3))
            rope.fillColor   = SKColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 0.7)
            rope.strokeColor = .clear
            rope.position    = CGPoint(x: size.width / 2, y: size.height * frac)
            rope.zPosition   = -2
            addChild(rope)
        }
    }

    // MARK: Opponent

    private func setupOpponent() {
        let cx = size.width / 2
        let headY: CGFloat = size.height * 0.60
        let bodyY: CGFloat = size.height * 0.44

        // Body
        opponentBody = SKShapeNode(rectOf: CGSize(width: 110, height: 120), cornerRadius: 14)
        opponentBody.fillColor   = SKColor(red: 0.27, green: 0.20, blue: 0.32, alpha: 1)
        opponentBody.strokeColor = SKColor(red: 0.55, green: 0.35, blue: 0.65, alpha: 1)
        opponentBody.lineWidth   = 2
        opponentBody.position    = CGPoint(x: cx, y: bodyY)
        opponentBody.zPosition   = 5
        addChild(opponentBody)

        // Idle breathing
        opponentBody.run(.repeatForever(.sequence([
            .scale(to: 1.02, duration: 1.1),
            .scale(to: 1.0,  duration: 1.1)
        ])))

        // Head
        opponentHead = SKShapeNode(circleOfRadius: 44)
        opponentHead.fillColor   = SKColor(red: 0.32, green: 0.24, blue: 0.37, alpha: 1)
        opponentHead.strokeColor = SKColor(red: 0.70, green: 0.50, blue: 0.80, alpha: 1)
        opponentHead.lineWidth   = 2.5
        opponentHead.glowWidth   = 4
        opponentHead.position    = CGPoint(x: cx, y: headY)
        opponentHead.zPosition   = 6
        addChild(opponentHead)

        // Eyes — angry
        for dx: CGFloat in [-14, 14] {
            let eye = SKShapeNode(circleOfRadius: 7)
            eye.fillColor   = SKColor(red: 1.0, green: 0.30, blue: 0.30, alpha: 1)
            eye.strokeColor = .clear
            eye.position    = CGPoint(x: opponentHead.position.x + dx,
                                     y: opponentHead.position.y + 8)
            eye.zPosition   = 7
            eye.glowWidth   = 2
            addChild(eye)
        }

        // Mouth
        let mouth = SKShapeNode(rectOf: CGSize(width: 28, height: 5), cornerRadius: 3)
        mouth.fillColor   = SKColor(red: 0.6, green: 0.2, blue: 0.2, alpha: 1)
        mouth.strokeColor = .clear
        mouth.position    = CGPoint(x: cx, y: headY - 18)
        mouth.zPosition   = 7
        addChild(mouth)

        // Idle head bob
        opponentHead.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 3, duration: 1.1),
            .moveBy(x: 0, y: -3, duration: 1.1)
        ])))

        // Gloves
        let gloveY: CGFloat = bodyY + 20
        leftGloveRest  = CGPoint(x: cx - 90, y: gloveY)
        rightGloveRest = CGPoint(x: cx + 90, y: gloveY)

        leftGlove  = makeGlove(at: leftGloveRest)
        rightGlove = makeGlove(at: rightGloveRest)
    }

    private func makeGlove(at pos: CGPoint) -> SKShapeNode {
        // Neon yellow glove with a hard white inner core. Per Gemini design
        // review: red gloves visually merged into the red hit-flash + red
        // ring ropes, killing threat readability. Yellow makes them the
        // ONLY bright element on screen, so the player's eye locks onto
        // them whenever they move.
        let g = SKShapeNode(circleOfRadius: 28)
        g.fillColor   = SKColor(red: 1.00, green: 0.86, blue: 0.20, alpha: 1)   // bright yellow
        g.strokeColor = SKColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.95) // hard white rim
        g.lineWidth   = 2.5
        g.glowWidth   = 6
        g.position    = pos
        g.zPosition   = 8
        addChild(g)

        // Inner white core — the "hard inner core" Gemini called out, makes
        // the glove read at a glance even during a screen-flash event.
        let core = SKShapeNode(circleOfRadius: 14)
        core.fillColor   = SKColor(red: 1, green: 1, blue: 1, alpha: 0.85)
        core.strokeColor = .clear
        core.position    = CGPoint(x: 0, y: 0)
        g.addChild(core)

        // Subtle dark stripe across the knuckles for shape recognition.
        let detail = SKShapeNode(rectOf: CGSize(width: 36, height: 6), cornerRadius: 3)
        detail.fillColor   = SKColor(red: 0.30, green: 0.20, blue: 0.10, alpha: 0.55)
        detail.strokeColor = .clear
        detail.position    = CGPoint(x: 0, y: 6)
        g.addChild(detail)

        return g
    }

    // MARK: HUD

    private func setupHUD() {
        let topInset: CGFloat = 60

        // Score chip — top-left
        scoreChip = makeChip(width: 110, height: 46)
        scoreChip.position = CGPoint(x: 18 + 55, y: size.height - topInset)
        addChild(scoreChip)

        let scoreCaption = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        scoreCaption.text = "SCORE"
        scoreCaption.fontSize  = 9
        scoreCaption.fontColor = SKColor(white: 1, alpha: 0.45)
        scoreCaption.position  = CGPoint(x: 0, y: 11)
        scoreCaption.zPosition = 1
        scoreChip.addChild(scoreCaption)

        scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        scoreLabel.text = "0"
        scoreLabel.fontSize  = 22
        scoreLabel.fontColor = .white
        scoreLabel.position  = CGPoint(x: 0, y: -8)
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.zPosition = 1
        scoreChip.addChild(scoreLabel)

        // Round chip — top-right
        roundChip = makeChip(width: 110, height: 46)
        roundChip.position = CGPoint(x: size.width - 18 - 55, y: size.height - topInset)
        addChild(roundChip)

        let roundCaption = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        roundCaption.text = "ROUND"
        roundCaption.fontSize  = 9
        roundCaption.fontColor = SKColor(white: 1, alpha: 0.45)
        roundCaption.position  = CGPoint(x: 0, y: 11)
        roundCaption.zPosition = 1
        roundChip.addChild(roundCaption)

        roundLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        roundLabel.text = "1"
        roundLabel.fontSize  = 22
        roundLabel.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1)
        roundLabel.position  = CGPoint(x: 0, y: -8)
        roundLabel.verticalAlignmentMode = .center
        roundLabel.zPosition = 1
        roundChip.addChild(roundLabel)

        // HP bar — under chips, centered
        let barWidth:  CGFloat = size.width - 60
        let barHeight: CGFloat = 12
        let barY: CGFloat = size.height - topInset - 44

        hpBarBg = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: barHeight / 2)
        hpBarBg.fillColor   = SKColor(white: 1, alpha: 0.08)
        hpBarBg.strokeColor = SKColor(white: 1, alpha: 0.18)
        hpBarBg.lineWidth   = 1
        hpBarBg.position    = CGPoint(x: size.width / 2, y: barY)
        hpBarBg.zPosition   = 14
        addChild(hpBarBg)

        hpBarFill = SKShapeNode(rectOf: CGSize(width: barWidth - 4, height: barHeight - 4),
                                cornerRadius: (barHeight - 4) / 2)
        hpBarFill.fillColor   = SKColor(red: 0.30, green: 1.0, blue: 0.45, alpha: 1)
        hpBarFill.strokeColor = .clear
        hpBarFill.position    = CGPoint(x: size.width / 2, y: barY)
        hpBarFill.zPosition   = 15
        addChild(hpBarFill)
        hpBarFill.xScale = 1.0

        hpLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        hpLabel.text = "HP"
        hpLabel.fontSize  = 9
        hpLabel.fontColor = SKColor(white: 1, alpha: 0.5)
        hpLabel.position  = CGPoint(x: 30 + 10, y: barY + 14)
        hpLabel.horizontalAlignmentMode = .left
        hpLabel.zPosition = 16
        addChild(hpLabel)

        // Warning banner (full-width)
        warningBanner = SKShapeNode(rectOf: CGSize(width: size.width, height: 56))
        warningBanner.fillColor   = SKColor(white: 0, alpha: 0.55)
        warningBanner.strokeColor = .clear
        warningBanner.position    = CGPoint(x: size.width / 2, y: size.height * 0.78)
        warningBanner.zPosition   = 19
        warningBanner.alpha       = 0
        addChild(warningBanner)

        warningLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        warningLabel.text = ""
        warningLabel.fontSize  = 24
        warningLabel.fontColor = .white
        warningLabel.verticalAlignmentMode = .center
        warningLabel.position  = CGPoint(x: size.width / 2, y: size.height * 0.78)
        warningLabel.zPosition = 20
        addChild(warningLabel)

        // Combo label
        comboLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        comboLabel.text = ""
        comboLabel.fontSize  = 22
        comboLabel.fontColor = SKColor(red: 0.30, green: 1, blue: 0.55, alpha: 1)
        comboLabel.verticalAlignmentMode = .center
        comboLabel.position  = CGPoint(x: size.width / 2, y: size.height * 0.85)
        comboLabel.zPosition = 20
        addChild(comboLabel)

        // Note: removed the persistent "Tilt your head to dodge" hint and the
        // p=… r=… debug readout — Gemini design review flagged both as visual
        // clutter that hurt aesthetic identity and information density. The
        // mechanic is taught in the menu's HOW TO DODGE card; in-fight
        // feedback should be reserved for state changes (telegraphs, hits,
        // dodges) rather than persistent instructions.
    }

    private func makeChip(width: CGFloat, height: CGFloat) -> SKNode {
        let parent = SKNode()
        parent.zPosition = 14

        let bg = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: height / 2)
        bg.fillColor   = SKColor(white: 1, alpha: 0.08)
        bg.strokeColor = SKColor(white: 1, alpha: 0.18)
        bg.lineWidth   = 1
        bg.zPosition   = 0
        parent.addChild(bg)
        return parent
    }

    private func updateHpBar() {
        let frac = CGFloat(max(hp, 0)) / CGFloat(maxHp)
        hpBarFill.run(.scaleX(to: frac, y: 1.0, duration: 0.25))

        let color: SKColor
        if frac > 0.6      { color = SKColor(red: 0.30, green: 1.0, blue: 0.45, alpha: 1) }
        else if frac > 0.3 { color = SKColor(red: 1.0,  green: 0.75, blue: 0.20, alpha: 1) }
        else               { color = SKColor(red: 1.0,  green: 0.30, blue: 0.30, alpha: 1) }
        hpBarFill.run(.colorize(with: color, colorBlendFactor: 0, duration: 0.2))
        hpBarFill.fillColor = color

        // Pulse on damage
        hpBarFill.run(.sequence([
            .fadeAlpha(to: 0.4, duration: 0.05),
            .fadeAlpha(to: 1.0, duration: 0.15)
        ]))
    }

    private func updateCombo() {
        if combo >= 2 {
            comboLabel.text = "🔥  \(combo)x  COMBO"
            comboLabel.alpha = 1
            comboLabel.run(.sequence([
                .scale(to: 1.18, duration: 0.1),
                .scale(to: 1.0, duration: 0.1),
                .wait(forDuration: 0.9),
                .fadeOut(withDuration: 0.3)
            ]))
        } else {
            comboLabel.alpha = 0
        }
    }

    // MARK: Zone Indicator

    private func setupZoneIndicator() {
        let baseY: CGFloat = size.height * 0.18
        let ringRadius: CGFloat = 32

        leftZoneRing  = makeZoneRing(at: CGPoint(x: size.width * 0.22, y: baseY),
                                     radius: ringRadius, label: "← LEFT")
        rightZoneRing = makeZoneRing(at: CGPoint(x: size.width * 0.78, y: baseY),
                                     radius: ringRadius, label: "RIGHT →")
        duckZoneRing  = makeZoneRing(at: CGPoint(x: size.width * 0.50, y: baseY - 50),
                                     radius: ringRadius, label: "↓ DUCK")

        // Player's head dot
        headDot = SKShapeNode(circleOfRadius: 14)
        headDot.fillColor   = SKColor(red: 0.30, green: 0.90, blue: 1.0, alpha: 0.95)
        headDot.strokeColor = .white
        headDot.lineWidth   = 1.5
        headDot.glowWidth   = 8
        headDot.zPosition   = 25
        headDot.position    = CGPoint(x: size.width / 2, y: baseY)
        addChild(headDot)
    }

    private func makeZoneRing(at pos: CGPoint, radius: CGFloat, label: String) -> SKShapeNode {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.fillColor   = SKColor(white: 1, alpha: 0.04)
        ring.strokeColor = SKColor(white: 1, alpha: 0.22)
        ring.lineWidth   = 1.5
        ring.position    = pos
        ring.zPosition   = 22
        addChild(ring)

        let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        l.text = label
        l.fontSize  = 10
        l.fontColor = SKColor(white: 1, alpha: 0.45)
        l.position  = CGPoint(x: pos.x, y: pos.y - radius - 14)
        l.zPosition = 22
        l.verticalAlignmentMode = .center
        addChild(l)

        return ring
    }

    // MARK: - Cards (FightPhase visuals)

    private func setupCards() {
        introCard      = makeIntroCard()
        roundBreakCard = makeRoundBreakCard()
        koCard         = makeKOCard()

        introCard.isHidden      = true
        roundBreakCard.isHidden = true
        koCard.isHidden         = true

        addChild(introCard)
        addChild(roundBreakCard)
        addChild(koCard)
    }

    /// Center-screen card showing opponent name / country / record. Mimics
    /// the 1987 NES "VS" splash that introduces each fight.
    ///
    /// IMPORTANT: SpriteView is created with `ignoresSiblingOrder: true`,
    /// which means child zPositions are ABSOLUTE in the scene, not relative
    /// to the parent. Every child needs a zPosition explicitly above the
    /// rest of the scene's content (zPos 0-50 range) for the card to appear
    /// in front. Earlier defaults of 0 and -1 silently rendered the card
    /// behind the opponent and HUD.
    private func makeIntroCard() -> SKNode {
        let group = SKNode()
        group.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        // Per SKNode docs: a child's effective zPosition is parent.zPosition +
        // child.zPosition. With parent at 0, our zPos 90 children should render
        // at absolute 90 — but they didn't. Setting parent zPosition explicitly
        // forces children's absolute zPos far above the rest of the scene
        // regardless of any odd composition rules.
        group.zPosition = 100

        let backdrop = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        backdrop.fillColor   = SKColor(white: 0, alpha: 0.78)
        backdrop.strokeColor = .clear
        backdrop.position    = CGPoint(x: 0, y: -(size.height * 0.05))
        backdrop.zPosition   = 90
        group.addChild(backdrop)

        let vs = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        vs.text      = "—  VS  —"
        vs.fontSize  = 16
        vs.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1)
        vs.position  = CGPoint(x: 0, y: 90)
        vs.zPosition = 91
        group.addChild(vs)

        let name = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        name.text      = opponent.name
        name.fontSize  = 42
        name.fontColor = SKColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)
        name.position  = CGPoint(x: 0, y: 30)
        name.zPosition = 91
        group.addChild(name)

        let country = SKLabelNode(fontNamed: "AvenirNext-Bold")
        country.text      = opponent.country
        country.fontSize  = 18
        country.fontColor = SKColor(white: 1, alpha: 0.6)
        country.position  = CGPoint(x: 0, y: -10)
        country.zPosition = 91
        group.addChild(country)

        let record = SKLabelNode(fontNamed: "Menlo-Bold")
        record.text      = "RECORD  \(opponent.record)"
        record.fontSize  = 14
        record.fontColor = SKColor(red: 1.0, green: 0.65, blue: 0.10, alpha: 1)
        record.position  = CGPoint(x: 0, y: -38)
        record.zPosition = 91
        group.addChild(record)

        let hint = SKLabelNode(fontNamed: "AvenirNext-Medium")
        hint.text      = opponent.isTutorial
            ? "Take your time. You can't lose."
            : "Slip the hooks. Duck the uppercut."
        hint.fontSize  = 12
        hint.fontColor = SKColor(white: 1, alpha: 0.55)
        hint.position  = CGPoint(x: 0, y: -68)
        hint.zPosition = 91
        group.addChild(hint)

        return group
    }

    private func makeRoundBreakCard() -> SKNode {
        let group = SKNode()
        group.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        group.zPosition = 100

        let backdrop = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        backdrop.fillColor   = SKColor(white: 0, alpha: 0.7)
        backdrop.strokeColor = .clear
        backdrop.position    = CGPoint(x: 0, y: -(size.height * 0.05))
        backdrop.zPosition   = 90
        group.addChild(backdrop)

        let header = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        header.text      = "BREAK"
        header.fontSize  = 28
        header.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1)
        header.position  = CGPoint(x: 0, y: 60)
        header.zPosition = 91
        group.addChild(header)

        roundBreakText = SKLabelNode(fontNamed: "AvenirNext-Medium")
        roundBreakText.text                    = ""
        roundBreakText.fontSize                = 16
        roundBreakText.fontColor               = SKColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)
        roundBreakText.numberOfLines           = 3
        roundBreakText.preferredMaxLayoutWidth = size.width * 0.78
        roundBreakText.horizontalAlignmentMode = .center
        roundBreakText.position                = CGPoint(x: 0, y: 0)
        roundBreakText.zPosition               = 91
        group.addChild(roundBreakText)

        let hint = SKLabelNode(fontNamed: "AvenirNext-Bold")
        hint.text      = "BELL IN 3…"
        hint.fontSize  = 12
        hint.fontColor = SKColor(white: 1, alpha: 0.55)
        hint.position  = CGPoint(x: 0, y: -56)
        hint.zPosition = 91
        group.addChild(hint)

        return group
    }

    private func makeKOCard() -> SKNode {
        let group = SKNode()
        group.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        group.zPosition = 110

        let backdrop = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        backdrop.fillColor   = SKColor(red: 0.12, green: 0.02, blue: 0.02, alpha: 0.86)
        backdrop.strokeColor = .clear
        backdrop.position    = CGPoint(x: 0, y: -(size.height * 0.05))
        backdrop.zPosition   = 95
        group.addChild(backdrop)

        let ko = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        ko.text      = "K.O."
        ko.fontSize  = 96
        ko.fontColor = SKColor(red: 1.0, green: 0.20, blue: 0.20, alpha: 1)
        ko.position  = CGPoint(x: 0, y: 60)
        ko.zPosition = 96
        group.addChild(ko)

        let dlc = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        dlc.text      = "DOWN FOR THE COUNT"
        dlc.fontSize  = 14
        dlc.fontColor = SKColor(white: 1, alpha: 0.65)
        dlc.position  = CGPoint(x: 0, y: -10)
        dlc.zPosition = 96
        group.addChild(dlc)

        koScoreText = SKLabelNode(fontNamed: "Menlo-Bold")
        koScoreText.text      = "FINAL  0"
        koScoreText.fontSize  = 18
        koScoreText.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1)
        koScoreText.position  = CGPoint(x: 0, y: -42)
        koScoreText.zPosition = 96
        group.addChild(koScoreText)

        return group
    }

    // MARK: Phase transitions

    private func updatePhase() {
        introCard.isHidden      = true
        roundBreakCard.isHidden = true
        koCard.isHidden         = true

        switch phase {
        case .intro:
            // Show intro card with a brief animation, then auto-advance to fighting
            // after the bell rings.
            introCard.isHidden = false
            introCard.alpha    = 0
            introCard.setScale(0.92)
            introCard.run(.group([
                .fadeIn(withDuration: 0.25),
                .scale(to: 1.0, duration: 0.25),
            ]))
            audio.play(.drumRoll)

            // Use wall-clock dispatch for phase transitions instead of
            // SKAction.run(.wait...) — SpriteKit's action time can fast-forward
            // when a freshly-created scene attaches to its view, causing the
            // intro to "skip" entirely. asyncAfter ticks at the system timer
            // regardless of scene state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.audio.play(.bell)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                guard case .intro = self.phase else { return }   // skip if already advanced
                self.introCard.run(.fadeOut(withDuration: 0.25))
                self.phase = .fighting
            }

        case .fighting:
            // Resume normal play. nextPunch only fires on first transition into
            // .fighting (from intro or roundBreak); subsequent punches are
            // scheduled by resetGlovesAndContinue() which calls nextPunch via
            // run(.wait...).
            nextPunch()

        case .roundBreak(let nextRound):
            roundBreakCard.isHidden = false
            roundBreakCard.alpha    = 0
            roundBreakText.text     = opponent.pepTalks.randomElement() ?? ""
            roundBreakCard.run(.fadeIn(withDuration: 0.25))

            // Auto-advance back to fighting after a 2.5s read time + bell.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                self?.audio.play(.bell)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self else { return }
                guard case .roundBreak = self.phase else { return }
                self.roundBreakCard.run(.fadeOut(withDuration: 0.25))
                self.round = nextRound
                self.roundLabel.text = "\(nextRound)"
                self.telegraphDuration = max(0.65, self.telegraphDuration - 0.12)
                self.restDuration      = max(0.55, self.restDuration  - 0.08)
                self.phase = .fighting
            }

        case .ko:
            koScoreText.text  = "FINAL  \(score)"
            koCard.isHidden   = false
            koCard.alpha      = 0
            koCard.setScale(0.7)
            koCard.run(.group([
                .fadeIn(withDuration: 0.35),
                .scale(to: 1.0, duration: 0.35),
            ]))
            audio.stopMusic(fadeOver: 0.6)
            audio.play(.knockoutSting)
        }
    }

    // MARK: - Game Loop

    override func update(_ currentTime: TimeInterval) {
        guard !gameOver else { return }
        updatePlayerZoneIndicator()
    }

    private func updatePlayerZoneIndicator() {
        let motion = MotionManager.shared
        let roll  = motion.roll
        let pitch = motion.pitch

        let cx = size.width / 2
        let baseY: CGFloat = size.height * 0.18

        let maxH: CGFloat = size.width * 0.32
        let maxV: CGFloat = size.height * 0.07

        // Sign convention with the zone detection (currentHeadZone):
        //   - looking down → pitch is NEGATIVE → triggers .duck
        //   - the duck zone ring is positioned BELOW baseY (lower on screen)
        //   - SpriteKit Y is up, so to move the dot DOWN toward the duck ring,
        //     dy must be NEGATIVE when pitch is negative.
        // Earlier code negated pitch here, which moved the dot UP when looking
        // down — visually contradicting the zone state. Fixed by removing the
        // negation so the dot tracks head direction directly.
        let dx = CGFloat(roll / 30.0) * maxH
        let dy = CGFloat(pitch / 40.0) * maxV

        let targetX = (cx + dx).clamped(to: cx - maxH ... cx + maxH)
        let targetY = (baseY + dy).clamped(to: baseY - maxV * 1.6 ... baseY + maxV * 0.5)

        let cur = headDot.position
        headDot.position = CGPoint(
            x: cur.x + (targetX - cur.x) * 0.25,
            y: cur.y + (targetY - cur.y) * 0.25
        )

        // Highlight ring under active zone
        let zone = currentHeadZone()
        highlight(ring: leftZoneRing,  active: zone == .left,  color: SKColor(red: 0.30, green: 0.95, blue: 0.55, alpha: 1))
        highlight(ring: rightZoneRing, active: zone == .right, color: SKColor(red: 0.30, green: 0.95, blue: 0.55, alpha: 1))
        highlight(ring: duckZoneRing,  active: zone == .duck,  color: SKColor(red: 0.70, green: 0.45, blue: 1.0,  alpha: 1))

        // Color the dot to match active zone
        switch zone {
        case .left, .right:
            headDot.fillColor = SKColor(red: 0.30, green: 0.95, blue: 0.55, alpha: 0.95)
        case .duck:
            headDot.fillColor = SKColor(red: 0.70, green: 0.45, blue: 1.0,  alpha: 0.95)
        case .center:
            headDot.fillColor = SKColor(red: 0.30, green: 0.90, blue: 1.0,  alpha: 0.95)
        }
    }

    private func highlight(ring: SKShapeNode, active: Bool, color: SKColor) {
        if active {
            ring.fillColor   = color.withAlphaComponent(0.22)
            ring.strokeColor = color
            ring.lineWidth   = 2.5
            ring.glowWidth   = 6
        } else {
            ring.fillColor   = SKColor(white: 1, alpha: 0.04)
            ring.strokeColor = SKColor(white: 1, alpha: 0.22)
            ring.lineWidth   = 1.5
            ring.glowWidth   = 0
        }
    }

    private func currentHeadZone() -> DodgeZone {
        let motion = MotionManager.shared
        guard motion.isConnected else { return .center }

        let roll  = motion.roll
        let pitch = motion.pitch

        if pitch < -duckThreshold { return .duck }
        if roll < -rollThreshold  { return .left }
        if roll >  rollThreshold  { return .right }
        return .center
    }

    // MARK: - Punch Sequence

    private func nextPunch() {
        guard !gameOver else { return }
        // Phase gate — punches only fire during .fighting. Stale scheduled
        // calls from resetGlovesAndContinue's run(.wait...) early-return
        // when the phase has flipped to .roundBreak / .ko / .intro since.
        guard case .fighting = phase else { return }

        // Pick from the opponent's allowed punch set. Sandbag throws all 4;
        // Vitrine skips uppercut early on; The Warden throws everything fast.
        let punch = opponent.punches.randomElement() ?? .jab
        currentPunch    = punch
        punchLanded     = false
        waitingForDodge = true

        telegraphPunch(punch)
    }

    private func telegraphPunch(_ punch: PunchType) {
        warningLabel.text      = punch.warningText
        warningLabel.fontColor = SKColor(cgColor: punch.warningColor.cgColor)
        warningLabel.setScale(1)
        warningLabel.alpha = 1

        warningBanner.fillColor = SKColor(cgColor: punch.warningColor.cgColor).withAlphaComponent(0.18)
        warningBanner.run(.fadeAlpha(to: 1, duration: 0.12))

        warningLabel.run(.sequence([
            .group([.scale(to: 1.18, duration: 0.12), .fadeIn(withDuration: 0.1)]),
            .scale(to: 1.0, duration: 0.1)
        ]))

        if hapticsEnabled { lightImpact.impactOccurred(intensity: 0.6) }

        windUpGlove(for: punch)

        run(.wait(forDuration: telegraphDuration)) { [weak self] in
            self?.throwPunch(punch)
        }
    }

    private func windUpGlove(for punch: PunchType) {
        switch punch {
        case .leftHook:
            leftGlove.run(.move(to: CGPoint(x: leftGloveRest.x - 25, y: leftGloveRest.y + 10),
                                duration: 0.3))
        case .rightHook:
            rightGlove.run(.move(to: CGPoint(x: rightGloveRest.x + 25, y: rightGloveRest.y + 10),
                                 duration: 0.3))
        case .jab:
            leftGlove.run(.move(to: CGPoint(x: leftGloveRest.x + 10, y: leftGloveRest.y - 5), duration: 0.25))
            rightGlove.run(.move(to: CGPoint(x: rightGloveRest.x - 10, y: rightGloveRest.y - 5), duration: 0.25))
        case .uppercut:
            leftGlove.run(.move(to: CGPoint(x: leftGloveRest.x, y: leftGloveRest.y - 30), duration: 0.3))
        }
    }

    private func throwPunch(_ punch: PunchType) {
        guard !gameOver else { return }
        waitingForDodge = false

        let center = CGPoint(x: size.width / 2, y: size.height * 0.35)
        let moveTime: TimeInterval = 0.22

        switch punch {
        case .leftHook:
            leftGlove.run(.sequence([
                .group([.move(to: center, duration: moveTime), .scale(to: 1.6, duration: moveTime)]),
                .wait(forDuration: 0.05)
            ])) { [weak self] in self?.resolvePunch(punch) }

        case .rightHook:
            rightGlove.run(.sequence([
                .group([.move(to: center, duration: moveTime), .scale(to: 1.6, duration: moveTime)]),
                .wait(forDuration: 0.05)
            ])) { [weak self] in self?.resolvePunch(punch) }

        case .jab:
            rightGlove.run(.sequence([
                .group([.move(to: center, duration: moveTime), .scale(to: 1.8, duration: moveTime)])
            ])) { [weak self] in self?.resolvePunch(punch) }

        case .uppercut:
            leftGlove.run(.sequence([
                .group([
                    .move(to: CGPoint(x: center.x - 20, y: center.y + 40), duration: moveTime),
                    .scale(to: 1.7, duration: moveTime)
                ])
            ])) { [weak self] in self?.resolvePunch(punch) }
        }
    }

    private func resolvePunch(_ punch: PunchType) {
        let zone = currentHeadZone()
        let dodged: Bool

        switch punch {
        case .jab: dodged = (zone == .left || zone == .right)
        default:   dodged = (zone == punch.requiredZone)
        }

        if dodged { onDodgeSuccess(punch) } else { onHit(punch) }
    }

    // MARK: - Results

    private func onDodgeSuccess(_ punch: PunchType) {
        combo += 1
        score += 10 * max(combo, 1)

        audio.play(.dodgeCheer)

        // Haptic
        if hapticsEnabled {
            if combo >= 3 {
                notify.notificationOccurred(.success)
            } else {
                mediumImpact.impactOccurred(intensity: 0.8)
            }
        }

        // Flash green
        let flash = SKShapeNode(rectOf: size)
        flash.fillColor   = SKColor(red: 0.20, green: 1, blue: 0.35, alpha: 0.16)
        flash.strokeColor = .clear
        flash.position    = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition   = 30
        flash.blendMode   = .add
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))

        // Positive feedback text — moved above opponent + black-outlined for
        // consistency with hit text. Stays green since "SLIPPED!" doesn't
        // collide with a red flash, but the outline reads better against
        // the spotlight glow than flat green-on-grey did.
        let dodgeText = combo >= 3 ? "PERFECT SLIP! 🥊" : "SLIPPED!"
        let dodgePosition = CGPoint(x: size.width / 2, y: size.height * 0.78)
        let dodgeGroup = SKNode()
        dodgeGroup.position = dodgePosition
        dodgeGroup.zPosition = 30
        for offset in [CGPoint(x: -3, y: 0), CGPoint(x: 3, y: 0),
                       CGPoint(x: 0, y: -3), CGPoint(x: 0, y: 3),
                       CGPoint(x: -2, y: -2), CGPoint(x: 2, y: 2),
                       CGPoint(x: -2, y: 2), CGPoint(x: 2, y: -2)] {
            let outline = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            outline.text = dodgeText
            outline.fontSize = 32
            outline.fontColor = .black
            outline.position = offset
            dodgeGroup.addChild(outline)
        }
        let dodge = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        dodge.text      = dodgeText
        dodge.fontSize  = 32
        dodge.fontColor = SKColor(red: 0.30, green: 1, blue: 0.55, alpha: 1)
        dodge.position  = .zero
        dodgeGroup.addChild(dodge)
        addChild(dodgeGroup)
        dodgeGroup.run(.sequence([
            .group([.moveBy(x: 0, y: 30, duration: 0.55), .fadeOut(withDuration: 0.55)]),
            .removeFromParent()
        ]))

        opponentHead.run(.sequence([
            .moveBy(x: 0, y: -8, duration: 0.1),
            .moveBy(x: 0, y: 8, duration: 0.1)
        ]))

        resetGlovesAndContinue()
    }

    private func onHit(_ punch: PunchType) {
        combo = 0
        // Tutorial fights (Sandbag) are immortal — player feels every hit
        // visually + audibly but can't actually lose. Per CEO plan: the
        // tutorial teaches the rhythm without punishing failure.
        if !opponent.isTutorial {
            hp -= 1
        }

        audio.play(.hitImpact)
        audio.play(.buzzBuzz)

        if hapticsEnabled { heavyImpact.impactOccurred() }

        // Screen shake
        let dx: CGFloat = 14
        run(.sequence([
            .moveBy(x: -dx, y: 0, duration: 0.05),
            .moveBy(x:  dx, y: 0, duration: 0.05),
            .moveBy(x: -dx * 0.6, y: 0, duration: 0.05),
            .moveBy(x:  dx * 0.6, y: 0, duration: 0.05)
        ]))

        // Flash red
        let flash = SKShapeNode(rectOf: size)
        flash.fillColor   = SKColor(red: 1, green: 0, blue: 0, alpha: 0.30)
        flash.strokeColor = .clear
        flash.position    = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition   = 30
        flash.blendMode   = .add
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))

        // Hit text — moved ABOVE opponent (was at 0.46, now 0.78) so it
        // doesn't occlude the incoming punch animation. Restyled as white
        // with a thick black outline (black SKLabelNode behind, white in
        // front with a 4px offset for the outline) — readable against the
        // red hit-flash that the previous red text drowned in.
        let hitText = ["OUCH!", "TOOK A HIT!", "MOVE FASTER!"].randomElement()!
        let hitPosition = CGPoint(x: size.width / 2, y: size.height * 0.78)
        let hitGroup = SKNode()
        hitGroup.position = hitPosition
        hitGroup.zPosition = 30
        // Black outline rendered as 4 offset copies — a poor man's stroke
        // for SKLabelNode which doesn't natively support text outlines.
        for offset in [CGPoint(x: -3, y: 0), CGPoint(x: 3, y: 0),
                       CGPoint(x: 0, y: -3), CGPoint(x: 0, y: 3),
                       CGPoint(x: -2, y: -2), CGPoint(x: 2, y: 2),
                       CGPoint(x: -2, y: 2), CGPoint(x: 2, y: -2)] {
            let outline = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            outline.text      = hitText
            outline.fontSize  = 32
            outline.fontColor = .black
            outline.position  = offset
            hitGroup.addChild(outline)
        }
        let hit = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        hit.text      = hitText
        hit.fontSize  = 32
        hit.fontColor = .white
        hit.position  = .zero
        hitGroup.addChild(hit)
        addChild(hitGroup)
        hitGroup.run(.sequence([
            .group([.moveBy(x: 0, y: 30, duration: 0.55), .fadeOut(withDuration: 0.55)]),
            .removeFromParent()
        ]))

        warningLabel.text = ""
        warningBanner.run(.fadeOut(withDuration: 0.2))

        if hp <= 0 {
            triggerKO()
        } else {
            resetGlovesAndContinue()
        }
    }

    private func resetGlovesAndContinue() {
        warningLabel.run(.fadeOut(withDuration: 0.2))
        warningBanner.run(.fadeOut(withDuration: 0.2))

        let resetTime: TimeInterval = 0.3
        leftGlove.run(.group([
            .move(to: leftGloveRest, duration: resetTime),
            .scale(to: 1.0, duration: resetTime)
        ]))
        rightGlove.run(.group([
            .move(to: rightGloveRest, duration: resetTime),
            .scale(to: 1.0, duration: resetTime)
        ]))

        if score > 0 && score % 60 == 0 {
            advanceRound()
        }

        run(.wait(forDuration: restDuration)) { [weak self] in
            self?.nextPunch()
        }
    }

    private func advanceRound() {
        // Round increment happens inside the .roundBreak phase transition
        // so the label updates right when the bell rings, not while the
        // pep-talk card is still on screen. This function just triggers
        // the transition — visuals are owned by updatePhase().
        audio.play(.roundUp)
        if hapticsEnabled { notify.notificationOccurred(.success) }
        phase = .roundBreak(round: round + 1)
    }

    // MARK: - KO

    private func triggerKO() {
        gameOver = true

        if hapticsEnabled { notify.notificationOccurred(.error) }
        // Submit best dodge streak from this fight to GameKit (silent if not authed)
        GameCenter.shared.submitStreak(maxStreak)

        // Strong shake under the KO card
        run(.sequence([
            .moveBy(x: -22, y: 0, duration: 0.05),
            .moveBy(x:  22, y: 0, duration: 0.05),
            .moveBy(x: -16, y: 0, duration: 0.05),
            .moveBy(x:  16, y: 0, duration: 0.05),
            .moveBy(x:  -8, y: 0, duration: 0.05),
            .moveBy(x:   8, y: 0, duration: 0.05)
        ]))

        // Slow-motion glove lingering
        leftGlove.run(.scale(to: 0.8, duration: 0.4))
        rightGlove.run(.scale(to: 0.8, duration: 0.4))

        // updatePhase() handles the K.O. card animation + audio sting.
        phase = .ko

        // Hold the KO card for ~1.6s so the player can read the score, then
        // hand off to the SwiftUI game-over view.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            self.onGameOver?(self.score)
        }
    }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
