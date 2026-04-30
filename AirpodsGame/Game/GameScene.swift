import SpriteKit

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
        case .leftHook:  return "DODGE RIGHT →"
        case .rightHook: return "← DODGE LEFT"
        case .jab:       return "MOVE ASIDE!"
        case .uppercut:  return "DUCK! ↓"
        }
    }

    var warningColor: UIColor {
        switch self {
        case .leftHook:  return UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        case .rightHook: return UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        case .jab:       return UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)
        case .uppercut:  return UIColor(red: 0.6, green: 0.3, blue: 1.0, alpha: 1)
        }
    }
}

// MARK: - GameScene

class GameScene: SKScene {

    // MARK: Head zone thresholds (degrees)
    private let rollThreshold:  Double = 14.0
    private let duckThreshold:  Double = 22.0

    // MARK: State
    private var hp: Int = 5                     { didSet { updateHearts() } }
    private var score: Int = 0                  { didSet { scoreLabel.text = "Score  \(score)" } }
    private var combo: Int = 0                  { didSet { updateCombo() } }
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
    private var scoreLabel:         SKLabelNode!
    private var roundLabel:         SKLabelNode!
    private var warningLabel:       SKLabelNode!
    private var comboLabel:         SKLabelNode!
    private var heartNodes:         [SKNode] = []
    private var zoneIndicator:      SKShapeNode!
    private var dodgeHint:          SKLabelNode!

    // MARK: Glove resting positions (in scene coords)
    private var leftGloveRest  = CGPoint.zero
    private var rightGloveRest = CGPoint.zero

    var onGameOver: ((Int) -> Void)?

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.08, green: 0.06, blue: 0.10, alpha: 1)
        setupBackground()
        setupOpponent()
        setupHUD()
        setupZoneIndicator()

        // Kick off fight after brief delay
        run(.wait(forDuration: 1.0)) { [weak self] in self?.nextPunch() }
    }

    // MARK: Background — boxing ring canvas

    private func setupBackground() {
        // Ring floor gradient feel
        let floor = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height * 0.4))
        floor.fillColor  = SKColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1)
        floor.strokeColor = .clear
        floor.position   = CGPoint(x: size.width / 2, y: size.height * 0.18)
        floor.zPosition  = -5
        addChild(floor)

        // Corner posts (decorative)
        for x in [size.width * 0.05, size.width * 0.95] {
            let post = SKShapeNode(rectOf: CGSize(width: 8, height: size.height * 0.55))
            post.fillColor   = SKColor(red: 0.8, green: 0.7, blue: 0.1, alpha: 0.6)
            post.strokeColor = .clear
            post.position    = CGPoint(x: x, y: size.height * 0.5)
            post.zPosition   = -4
            addChild(post)
        }

        // Ropes
        for frac in [0.55, 0.62, 0.69] as [CGFloat] {
            let rope = SKShapeNode(rectOf: CGSize(width: size.width, height: 3))
            rope.fillColor   = SKColor(red: 0.8, green: 0.15, blue: 0.15, alpha: 0.7)
            rope.strokeColor = .clear
            rope.position    = CGPoint(x: size.width / 2, y: size.height * frac)
            rope.zPosition   = -3
            addChild(rope)
        }
    }

    // MARK: Opponent

    private func setupOpponent() {
        let cx = size.width / 2
        let headY: CGFloat = size.height * 0.60
        let bodyY: CGFloat = size.height * 0.44

        // Body
        opponentBody = SKShapeNode(rectOf: CGSize(width: 110, height: 120), cornerRadius: 12)
        opponentBody.fillColor   = SKColor(red: 0.25, green: 0.18, blue: 0.30, alpha: 1)
        opponentBody.strokeColor = SKColor(red: 0.55, green: 0.35, blue: 0.65, alpha: 1)
        opponentBody.lineWidth   = 2
        opponentBody.position    = CGPoint(x: cx, y: bodyY)
        opponentBody.zPosition   = 5
        addChild(opponentBody)

        // Head
        opponentHead = SKShapeNode(circleOfRadius: 44)
        opponentHead.fillColor   = SKColor(red: 0.30, green: 0.22, blue: 0.35, alpha: 1)
        opponentHead.strokeColor = SKColor(red: 0.65, green: 0.45, blue: 0.75, alpha: 1)
        opponentHead.lineWidth   = 2.5
        opponentHead.glowWidth   = 4
        opponentHead.position    = CGPoint(x: cx, y: headY)
        opponentHead.zPosition   = 6
        addChild(opponentHead)

        // Eyes
        for dx: CGFloat in [-14, 14] {
            let eye = SKShapeNode(circleOfRadius: 7)
            eye.fillColor   = SKColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1)
            eye.strokeColor = .clear
            eye.position    = CGPoint(x: opponentHead.position.x + dx,
                                     y: opponentHead.position.y + 8)
            eye.zPosition   = 7
            addChild(eye)
        }

        // Mouth / grimace
        let mouth = SKShapeNode(rectOf: CGSize(width: 28, height: 5), cornerRadius: 3)
        mouth.fillColor   = SKColor(red: 0.6, green: 0.2, blue: 0.2, alpha: 1)
        mouth.strokeColor = .clear
        mouth.position    = CGPoint(x: cx, y: headY - 18)
        mouth.zPosition   = 7
        addChild(mouth)

        // Gloves
        let gloveRadius: CGFloat = 28
        let gloveY: CGFloat = bodyY + 20
        leftGloveRest  = CGPoint(x: cx - 90, y: gloveY)
        rightGloveRest = CGPoint(x: cx + 90, y: gloveY)

        leftGlove  = makeGlove(at: leftGloveRest,  color: UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
        rightGlove = makeGlove(at: rightGloveRest, color: UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
    }

    private func makeGlove(at pos: CGPoint, color: UIColor) -> SKShapeNode {
        let g = SKShapeNode(circleOfRadius: 28)
        g.fillColor   = SKColor(cgColor: color.cgColor)
        g.strokeColor = SKColor(red: 1, green: 0.5, blue: 0.5, alpha: 0.8)
        g.lineWidth   = 2
        g.glowWidth   = 6
        g.position    = pos
        g.zPosition   = 8
        addChild(g)

        // Glove knuckle detail
        let detail = SKShapeNode(rectOf: CGSize(width: 36, height: 14), cornerRadius: 7)
        detail.fillColor   = SKColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.5)
        detail.strokeColor = .clear
        detail.position    = CGPoint(x: 0, y: 4)
        g.addChild(detail)

        return g
    }

    // MARK: HUD

    private func setupHUD() {
        let topY = size.height - 55

        // Score
        scoreLabel = label("Score  0", size: 20, weight: .bold, color: .white,
                           at: CGPoint(x: size.width / 2, y: topY))
        addChild(scoreLabel)

        // Round
        roundLabel = label("Round 1", size: 14, weight: .medium,
                           color: SKColor(red: 0.8, green: 0.8, blue: 0.4, alpha: 1),
                           at: CGPoint(x: size.width / 2, y: topY - 26))
        addChild(roundLabel)

        // Hearts
        rebuildHearts()

        // Warning label (punch telegraph)
        warningLabel = label("", size: 26, weight: .heavy, color: .white,
                             at: CGPoint(x: size.width / 2, y: size.height * 0.78))
        warningLabel.zPosition = 20
        addChild(warningLabel)

        // Combo label
        comboLabel = label("", size: 22, weight: .bold,
                           color: SKColor(red: 0.3, green: 1, blue: 0.5, alpha: 1),
                           at: CGPoint(x: size.width / 2, y: size.height * 0.84))
        comboLabel.zPosition = 20
        addChild(comboLabel)

        // Dodge hint at bottom
        dodgeHint = label("Put on AirPods & tilt your head to dodge",
                          size: 12, weight: .medium,
                          color: SKColor(white: 1, alpha: 0.35),
                          at: CGPoint(x: size.width / 2, y: 30))
        addChild(dodgeHint)
    }

    private func rebuildHearts() {
        heartNodes.forEach { $0.removeFromParent() }
        heartNodes = []
        let startX = size.width / 2 - CGFloat(hp - 1) * 22
        for i in 0..<hp {
            let h = SKLabelNode(text: "❤️")
            h.fontSize  = 22
            h.position  = CGPoint(x: startX + CGFloat(i) * 44, y: size.height - 100)
            h.zPosition = 15
            addChild(h)
            heartNodes.append(h)
        }
    }

    private func updateHearts() {
        rebuildHearts()
    }

    private func updateCombo() {
        if combo >= 2 {
            comboLabel.text = "🔥 \(combo)x COMBO!"
            comboLabel.run(.sequence([
                .scale(to: 1.2, duration: 0.1),
                .scale(to: 1.0, duration: 0.1),
                .wait(forDuration: 0.8),
                .fadeOut(withDuration: 0.3)
            ]))
        } else {
            comboLabel.alpha = 0
        }
    }

    private func label(_ text: String, size fontSize: CGFloat, weight: UIFont.Weight,
                       color: SKColor, at pos: CGPoint) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: fontName(for: weight))
        l.text      = text
        l.fontSize  = fontSize
        l.fontColor = color
        l.position  = pos
        l.zPosition = 15
        l.verticalAlignmentMode = .center
        return l
    }

    private func fontName(for weight: UIFont.Weight) -> String {
        switch weight {
        case .heavy:  return "AvenirNext-Heavy"
        case .bold:   return "AvenirNext-Bold"
        case .medium: return "AvenirNext-Medium"
        default:      return "AvenirNext"
        }
    }

    // MARK: Zone Indicator

    private func setupZoneIndicator() {
        // Player head dot — moves based on head tracking
        zoneIndicator = SKShapeNode(circleOfRadius: 22)
        zoneIndicator.fillColor   = SKColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 0.7)
        zoneIndicator.strokeColor = .white
        zoneIndicator.lineWidth   = 2
        zoneIndicator.glowWidth   = 10
        zoneIndicator.zPosition   = 25
        zoneIndicator.position    = CGPoint(x: size.width / 2, y: size.height * 0.17)
        addChild(zoneIndicator)

        // Zone labels
        let zY: CGFloat = size.height * 0.17
        for (text, x) in [("← LEFT", size.width * 0.18), ("RIGHT →", size.width * 0.82)] {
            let l = SKLabelNode(fontNamed: "AvenirNext-Bold")
            l.text      = text
            l.fontSize  = 13
            l.fontColor = SKColor(white: 1, alpha: 0.25)
            l.position  = CGPoint(x: x, y: zY)
            l.zPosition = 24
            l.verticalAlignmentMode = .center
            addChild(l)
        }
        let duckL = SKLabelNode(fontNamed: "AvenirNext-Bold")
        duckL.text      = "↓ DUCK"
        duckL.fontSize  = 13
        duckL.fontColor = SKColor(white: 1, alpha: 0.25)
        duckL.position  = CGPoint(x: size.width / 2, y: size.height * 0.09)
        duckL.zPosition = 24
        duckL.verticalAlignmentMode = .center
        addChild(duckL)
    }

    // MARK: - Game Loop

    override func update(_ currentTime: TimeInterval) {
        guard !gameOver else { return }
        updatePlayerZoneIndicator()
    }

    private func updatePlayerZoneIndicator() {
        let motion = MotionManager.shared
        let roll  = motion.roll   // + = tilt right, - = tilt left
        let pitch = motion.pitch  // + = tilt back (up), - = forward (down)

        // Map roll → horizontal, pitch → vertical offset
        let cx  = size.width / 2
        let baseY: CGFloat = size.height * 0.17

        let maxH: CGFloat = size.width * 0.32
        let maxV: CGFloat = size.height * 0.07

        let dx = CGFloat(roll / 30.0) * maxH     // 30° = full range
        let dy = CGFloat(-pitch / 40.0) * maxV    // 40° = full vertical range

        let targetX = (cx + dx).clamped(to: cx - maxH ... cx + maxH)
        let targetY = (baseY + dy).clamped(to: baseY - maxV * 1.5 ... baseY + maxV * 0.5)

        // Smooth follow
        let cur = zoneIndicator.position
        zoneIndicator.position = CGPoint(
            x: cur.x + (targetX - cur.x) * 0.25,
            y: cur.y + (targetY - cur.y) * 0.25
        )

        // Color based on active zone
        let zone = currentHeadZone()
        switch zone {
        case .left, .right:
            zoneIndicator.fillColor = SKColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.8)
        case .duck:
            zoneIndicator.fillColor = SKColor(red: 0.7, green: 0.4, blue: 1.0, alpha: 0.8)
        case .center:
            zoneIndicator.fillColor = SKColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 0.7)
        }
    }

    private func currentHeadZone() -> DodgeZone {
        let motion = MotionManager.shared
        guard motion.isConnected else { return .center }

        let roll  = motion.roll
        let pitch = motion.pitch  // negative = head forward/down

        if pitch < -duckThreshold { return .duck }
        if roll < -rollThreshold  { return .left }
        if roll >  rollThreshold  { return .right }
        return .center
    }

    // MARK: - Punch Sequence

    private func nextPunch() {
        guard !gameOver else { return }

        let punch = PunchType.allCases.randomElement()!
        currentPunch  = punch
        punchLanded   = false
        waitingForDodge = true

        telegraphPunch(punch)
    }

    private func telegraphPunch(_ punch: PunchType) {
        // Warning label flash
        warningLabel.text      = punch.warningText
        warningLabel.fontColor = SKColor(cgColor: punch.warningColor.cgColor)
        warningLabel.setScale(1)
        warningLabel.alpha = 1
        warningLabel.run(.sequence([
            .group([.scale(to: 1.15, duration: 0.15), .fadeIn(withDuration: 0.1)]),
            .scale(to: 1.0, duration: 0.1)
        ]))

        // Animate the telegraph glove (wind-up)
        windUpGlove(for: punch)

        // After telegraph duration → throw the punch
        run(.wait(forDuration: telegraphDuration)) { [weak self] in
            self?.throwPunch(punch)
        }
    }

    private func windUpGlove(for punch: PunchType) {
        switch punch {
        case .leftHook:
            // Opponent left glove pulls back
            leftGlove.run(.move(to: CGPoint(x: leftGloveRest.x - 25, y: leftGloveRest.y + 10),
                                duration: 0.3))
        case .rightHook:
            rightGlove.run(.move(to: CGPoint(x: rightGloveRest.x + 25, y: rightGloveRest.y + 10),
                                 duration: 0.3))
        case .jab:
            // Both gloves come forward slightly
            leftGlove.run(.move(to: CGPoint(x: leftGloveRest.x + 10, y: leftGloveRest.y - 5), duration: 0.25))
            rightGlove.run(.move(to: CGPoint(x: rightGloveRest.x - 10, y: rightGloveRest.y - 5), duration: 0.25))
        case .uppercut:
            // Glove drops for an uppercut wind-up
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
                .group([
                    .move(to: center, duration: moveTime),
                    .scale(to: 1.6, duration: moveTime)
                ]),
                .wait(forDuration: 0.05)
            ])) { [weak self] in self?.resolvePunch(punch) }

        case .rightHook:
            rightGlove.run(.sequence([
                .group([
                    .move(to: center, duration: moveTime),
                    .scale(to: 1.6, duration: moveTime)
                ]),
                .wait(forDuration: 0.05)
            ])) { [weak self] in self?.resolvePunch(punch) }

        case .jab:
            let jabGlove = rightGlove!
            jabGlove.run(.sequence([
                .group([
                    .move(to: center, duration: moveTime),
                    .scale(to: 1.8, duration: moveTime)
                ])
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
        case .jab:
            // Jab: any side dodge works
            dodged = (zone == .left || zone == .right)
        default:
            dodged = (zone == punch.requiredZone)
        }

        if dodged {
            onDodgeSuccess(punch)
        } else {
            onHit(punch)
        }
    }

    // MARK: - Results

    private func onDodgeSuccess(_ punch: PunchType) {
        combo += 1
        score += 10 * max(combo, 1)

        // Flash green
        let flash = SKShapeNode(rectOf: size)
        flash.fillColor   = SKColor(red: 0.2, green: 1, blue: 0.3, alpha: 0.18)
        flash.strokeColor = .clear
        flash.position    = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition   = 30
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))

        // "SLIPPED!" text
        let dodge = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        dodge.text      = combo >= 3 ? "PERFECT SLIP! 🥊" : "SLIPPED!"
        dodge.fontSize  = 30
        dodge.fontColor = SKColor(red: 0.3, green: 1, blue: 0.5, alpha: 1)
        dodge.position  = CGPoint(x: size.width / 2, y: size.height * 0.46)
        dodge.zPosition = 30
        addChild(dodge)
        dodge.run(.sequence([
            .group([.moveBy(x: 0, y: 30, duration: 0.5), .fadeOut(withDuration: 0.5)]),
            .removeFromParent()
        ]))

        // Opponent flinch
        opponentHead.run(.sequence([
            .moveBy(x: 0, y: -8, duration: 0.1),
            .moveBy(x: 0, y: 8, duration: 0.1)
        ]))

        resetGlovesAndContinue()
    }

    private func onHit(_ punch: PunchType) {
        combo = 0
        hp -= 1

        // Screen shake
        let dx: CGFloat = 12
        run(.sequence([
            .moveBy(x: -dx, y: 0, duration: 0.05),
            .moveBy(x:  dx, y: 0, duration: 0.05),
            .moveBy(x: -dx, y: 0, duration: 0.05),
            .moveBy(x:  dx, y: 0, duration: 0.05)
        ]))

        // Flash red
        let flash = SKShapeNode(rectOf: size)
        flash.fillColor   = SKColor(red: 1, green: 0, blue: 0, alpha: 0.28)
        flash.strokeColor = .clear
        flash.position    = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition   = 30
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))

        // "OUCH" text
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

        if hp <= 0 {
            triggerKO()
        } else {
            resetGlovesAndContinue()
        }
    }

    private func resetGlovesAndContinue() {
        warningLabel.run(.fadeOut(withDuration: 0.2))

        let resetTime: TimeInterval = 0.3
        leftGlove.run(.group([
            .move(to: leftGloveRest, duration: resetTime),
            .scale(to: 1.0, duration: resetTime)
        ]))
        rightGlove.run(.group([
            .move(to: rightGloveRest, duration: resetTime),
            .scale(to: 1.0, duration: resetTime)
        ]))

        // Every 5 dodges → new round, speed up
        if score > 0 && score % 60 == 0 {
            advanceRound()
        }

        run(.wait(forDuration: restDuration)) { [weak self] in
            self?.nextPunch()
        }
    }

    private func advanceRound() {
        round += 1
        roundLabel.text = "Round \(round)"
        telegraphDuration = max(0.65, telegraphDuration - 0.12)
        restDuration      = max(0.55, restDuration - 0.08)

        let banner = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        banner.text      = "ROUND \(round)!"
        banner.fontSize  = 38
        banner.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        banner.position  = CGPoint(x: size.width / 2, y: size.height / 2)
        banner.zPosition = 35
        addChild(banner)
        banner.run(.sequence([
            .wait(forDuration: 0.05),
            .group([.moveBy(x: 0, y: 20, duration: 0.8), .fadeOut(withDuration: 0.8)]),
            .removeFromParent()
        ]))
    }

    // MARK: - KO

    private func triggerKO() {
        gameOver = true

        // Big KO text
        let ko = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        ko.text      = "K  O"
        ko.fontSize  = 80
        ko.fontColor = SKColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        ko.position  = CGPoint(x: size.width / 2, y: size.height / 2)
        ko.zPosition = 40
        ko.setScale(0.3)
        ko.alpha = 0
        addChild(ko)
        ko.run(.group([
            .scale(to: 1.0, duration: 0.3),
            .fadeIn(withDuration: 0.3)
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
