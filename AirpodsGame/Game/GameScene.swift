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

    // Timing (seconds)
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
    private var dodgeHint:          SKLabelNode!
    private var debugReadout:       SKLabelNode!

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
        setupBackground()
        setupVignette()
        setupOpponent()
        setupHUD()
        setupZoneIndicator()

        [lightImpact, heavyImpact, mediumImpact].forEach { $0.prepare() }
        notify.prepare()

        run(.wait(forDuration: 1.0)) { [weak self] in self?.nextPunch() }
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

    private func setupVignette() {
        // Soft dark edges via 4 thin gradient strips around the screen
        let stripColor = SKColor(white: 0, alpha: 0.55)
        let edge: CGFloat = 70

        let top = SKShapeNode(rectOf: CGSize(width: size.width, height: edge))
        top.fillColor = stripColor; top.strokeColor = .clear
        top.position  = CGPoint(x: size.width / 2, y: size.height - edge / 2)
        top.alpha = 0.55; top.zPosition = 50
        addChild(top)

        let bottom = SKShapeNode(rectOf: CGSize(width: size.width, height: edge))
        bottom.fillColor = stripColor; bottom.strokeColor = .clear
        bottom.position  = CGPoint(x: size.width / 2, y: edge / 2)
        bottom.alpha = 0.55; bottom.zPosition = 50
        addChild(bottom)
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
        let g = SKShapeNode(circleOfRadius: 28)
        g.fillColor   = SKColor(red: 0.92, green: 0.18, blue: 0.18, alpha: 1)
        g.strokeColor = SKColor(red: 1, green: 0.55, blue: 0.55, alpha: 0.85)
        g.lineWidth   = 2
        g.glowWidth   = 6
        g.position    = pos
        g.zPosition   = 8
        addChild(g)

        let detail = SKShapeNode(rectOf: CGSize(width: 36, height: 14), cornerRadius: 7)
        detail.fillColor   = SKColor(red: 1, green: 0.45, blue: 0.45, alpha: 0.55)
        detail.strokeColor = .clear
        detail.position    = CGPoint(x: 0, y: 4)
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

        // Dodge hint at bottom
        dodgeHint = SKLabelNode(fontNamed: "AvenirNext-Medium")
        dodgeHint.text = "Tilt your head to dodge"
        dodgeHint.fontSize  = 12
        dodgeHint.fontColor = SKColor(white: 1, alpha: 0.32)
        dodgeHint.position  = CGPoint(x: size.width / 2, y: 30)
        dodgeHint.zPosition = 15
        addChild(dodgeHint)

        // Debug readout — small text in bottom-left showing live pitch/roll
        // values. Validates sign conventions match the zone logic. Tiny enough
        // not to interfere with gameplay; can be hidden via UserDefaults flag
        // later if shipping to App Store with this on.
        debugReadout = SKLabelNode(fontNamed: "Menlo")
        debugReadout.text = "p=0  r=0"
        debugReadout.fontSize  = 9
        debugReadout.fontColor = SKColor(white: 1, alpha: 0.22)
        debugReadout.horizontalAlignmentMode = .left
        debugReadout.position  = CGPoint(x: 12, y: 12)
        debugReadout.zPosition = 15
        addChild(debugReadout)
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

        // Live debug readout — corner text showing raw sensor values
        debugReadout.text = String(format: "p=%+5.1f  r=%+5.1f  z=%@",
                                    pitch, roll, zone.label)
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

        let punch = PunchType.allCases.randomElement()!
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

        let dodge = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        dodge.text      = combo >= 3 ? "PERFECT SLIP! 🥊" : "SLIPPED!"
        dodge.fontSize  = 30
        dodge.fontColor = SKColor(red: 0.30, green: 1, blue: 0.55, alpha: 1)
        dodge.position  = CGPoint(x: size.width / 2, y: size.height * 0.46)
        dodge.zPosition = 30
        addChild(dodge)
        dodge.run(.sequence([
            .group([.moveBy(x: 0, y: 30, duration: 0.5), .fadeOut(withDuration: 0.5)]),
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
        hp -= 1

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

        let hit = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        hit.text      = ["OUCH!", "TOOK A HIT!", "MOVE FASTER!"].randomElement()!
        hit.fontSize  = 28
        hit.fontColor = SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
        hit.position  = CGPoint(x: size.width / 2, y: size.height * 0.46)
        hit.zPosition = 30
        addChild(hit)
        hit.run(.sequence([
            .group([.moveBy(x: 0, y: 25, duration: 0.5), .fadeOut(withDuration: 0.5)]),
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
        round += 1
        roundLabel.text = "\(round)"
        telegraphDuration = max(0.65, telegraphDuration - 0.12)
        restDuration      = max(0.55, restDuration - 0.08)

        if hapticsEnabled { notify.notificationOccurred(.success) }

        let banner = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        banner.text      = "ROUND \(round)!"
        banner.fontSize  = 42
        banner.fontColor = SKColor(red: 1, green: 0.85, blue: 0.20, alpha: 1)
        banner.position  = CGPoint(x: size.width / 2, y: size.height / 2)
        banner.zPosition = 35
        banner.setScale(0.5)
        banner.alpha = 0
        addChild(banner)
        banner.run(.sequence([
            .group([.scale(to: 1.0, duration: 0.25), .fadeIn(withDuration: 0.2)]),
            .wait(forDuration: 0.4),
            .group([.moveBy(x: 0, y: 20, duration: 0.6), .fadeOut(withDuration: 0.6)]),
            .removeFromParent()
        ]))
    }

    // MARK: - KO

    private func triggerKO() {
        gameOver = true

        if hapticsEnabled { notify.notificationOccurred(.error) }
        // Submit best dodge streak from this fight to GameKit (silent if not authed)
        GameCenter.shared.submitStreak(maxStreak)

        // Big KO text
        let ko = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        ko.text      = "K.O."
        ko.fontSize  = 100
        ko.fontColor = SKColor(red: 1, green: 0.20, blue: 0.20, alpha: 1)
        ko.position  = CGPoint(x: size.width / 2, y: size.height / 2)
        ko.zPosition = 40
        ko.setScale(0.3)
        ko.alpha     = 0
        addChild(ko)
        ko.run(.group([
            .scale(to: 1.0, duration: 0.3),
            .fadeIn(withDuration: 0.3)
        ]))

        // Strong shake
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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
