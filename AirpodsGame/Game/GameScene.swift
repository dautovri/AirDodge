import SpriteKit
import CoreMotion

// MARK: - Collision categories
private struct Category {
    static let player:   UInt32 = 0b0001
    static let obstacle: UInt32 = 0b0010
    static let orb:      UInt32 = 0b0100
    static let wall:     UInt32 = 0b1000
}

class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: Nodes
    private var player: SKShapeNode!
    private var scoreLabel: SKLabelNode!
    private var multiplierLabel: SKLabelNode!
    private var trailEmitter: SKEmitterNode?

    // MARK: State
    private(set) var score: Int = 0 { didSet { scoreLabel?.text = "Score: \(score)" } }
    private var multiplier: Int = 1 { didSet { multiplierLabel?.text = "x\(multiplier)" } }
    private var gameOver = false
    private var spawnInterval: TimeInterval = 1.8
    private var speed: CGFloat = 220
    private var elapsed: TimeInterval = 0
    private var orbStreak: Int = 0

    // Control sensitivity (degrees → points/s scale factor)
    private let sensitivity: CGFloat = 6.0
    // Dead zone in degrees to ignore micro movements
    private let deadZone: Double = 2.0

    var onGameOver: ((Int) -> Void)?

    // MARK: Setup
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        setupWalls()
        setupStarfield()
        setupPlayer()
        setupHUD()
        scheduleSpawn()
    }

    private func setupWalls() {
        let wall = SKPhysicsBody(edgeLoopFrom: frame)
        wall.categoryBitMask    = Category.wall
        wall.collisionBitMask   = Category.player
        let node = SKNode()
        node.physicsBody = wall
        addChild(node)
    }

    private func setupStarfield() {
        guard let emitter = SKEmitterNode(fileNamed: "Starfield") else {
            // Fallback: manually scatter star dots
            for _ in 0..<80 {
                let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.5...2))
                star.fillColor = .white
                star.strokeColor = .clear
                star.alpha = CGFloat.random(in: 0.1...0.5)
                star.position = CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                )
                addChild(star)
            }
            return
        }
        emitter.position = CGPoint(x: size.width / 2, y: size.height)
        emitter.zPosition = -10
        addChild(emitter)
    }

    private func setupPlayer() {
        let r: CGFloat = 18
        player = SKShapeNode(circleOfRadius: r)
        player.fillColor   = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1)
        player.strokeColor = SKColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 1)
        player.lineWidth   = 2
        player.glowWidth   = 8
        player.position    = CGPoint(x: size.width * 0.2, y: size.height / 2)
        player.zPosition   = 10

        let body = SKPhysicsBody(circleOfRadius: r)
        body.isDynamic          = true
        body.allowsRotation     = false
        body.categoryBitMask    = Category.player
        body.contactTestBitMask = Category.obstacle | Category.orb
        body.collisionBitMask   = Category.wall
        body.linearDamping      = 8
        body.friction           = 0
        player.physicsBody = body

        addChild(player)
        addGlow(to: player, radius: r)
    }

    private func addGlow(to node: SKNode, radius: CGFloat) {
        let glow = SKShapeNode(circleOfRadius: radius * 1.6)
        glow.fillColor   = SKColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.15)
        glow.strokeColor = .clear
        glow.zPosition   = -1
        node.addChild(glow)
    }

    private func setupHUD() {
        scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        scoreLabel.fontSize  = 22
        scoreLabel.fontColor = .white
        scoreLabel.position  = CGPoint(x: size.width / 2, y: size.height - 50)
        scoreLabel.zPosition = 20
        scoreLabel.text      = "Score: 0"
        addChild(scoreLabel)

        multiplierLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        multiplierLabel.fontSize  = 16
        multiplierLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        multiplierLabel.position  = CGPoint(x: size.width / 2, y: size.height - 76)
        multiplierLabel.zPosition = 20
        multiplierLabel.text      = "x1"
        addChild(multiplierLabel)
    }

    // MARK: Spawning
    private func scheduleSpawn() {
        let spawn = SKAction.run { [weak self] in self?.spawnWave() }
        let wait  = SKAction.wait(forDuration: spawnInterval, withRange: 0.3)
        run(.repeatForever(.sequence([spawn, wait])), withKey: "spawn")
    }

    private func spawnWave() {
        let pattern = Int.random(in: 0...4)
        switch pattern {
        case 0: spawnSingleObstacle()
        case 1: spawnGap()
        case 2: spawnOrb()
        case 3: spawnSingleObstacle(); spawnOrb()
        default: spawnGap()
        }
    }

    private func spawnSingleObstacle() {
        let h = CGFloat.random(in: 40...120)
        let y = CGFloat.random(in: h / 2 + 20 ... size.height - h / 2 - 20)
        addObstacle(at: CGPoint(x: size.width + 30, y: y), size: CGSize(width: 20, height: h))
    }

    private func spawnGap() {
        // Two obstacles with a gap the player must fit through
        let gapSize: CGFloat = 110
        let gapY = CGFloat.random(in: gapSize / 2 + 40 ... size.height - gapSize / 2 - 40)
        let topH = size.height - gapY - gapSize / 2
        let botH = gapY - gapSize / 2
        if topH > 10 {
            addObstacle(at: CGPoint(x: size.width + 30, y: gapY + gapSize / 2 + topH / 2),
                        size: CGSize(width: 22, height: topH))
        }
        if botH > 10 {
            addObstacle(at: CGPoint(x: size.width + 30, y: gapY - gapSize / 2 - botH / 2),
                        size: CGSize(width: 22, height: botH))
        }
    }

    private func spawnOrb() {
        let y = CGFloat.random(in: 60...size.height - 60)
        let r: CGFloat = 12
        let orb = SKShapeNode(circleOfRadius: r)
        orb.fillColor   = SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
        orb.strokeColor = .white
        orb.lineWidth   = 1.5
        orb.glowWidth   = 6
        orb.position    = CGPoint(x: size.width + 30, y: y)
        orb.name        = "orb"

        let body = SKPhysicsBody(circleOfRadius: r)
        body.isDynamic          = false
        body.categoryBitMask    = Category.orb
        body.contactTestBitMask = Category.player
        body.collisionBitMask   = 0
        orb.physicsBody = body

        let pulse = SKAction.sequence([
            .scale(to: 1.2, duration: 0.4),
            .scale(to: 1.0, duration: 0.4)
        ])
        orb.run(.repeatForever(pulse))

        addChild(orb)
        moveAndRemove(orb)
    }

    private func addObstacle(at position: CGPoint, size: CGSize) {
        let obs = SKShapeNode(rectOf: size, cornerRadius: 4)
        obs.fillColor   = SKColor(red: 1.0, green: 0.25, blue: 0.35, alpha: 1)
        obs.strokeColor = SKColor(red: 1.0, green: 0.5, blue: 0.55, alpha: 1)
        obs.lineWidth   = 1.5
        obs.glowWidth   = 5
        obs.position    = position
        obs.name        = "obstacle"

        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic          = false
        body.categoryBitMask    = Category.obstacle
        body.contactTestBitMask = Category.player
        body.collisionBitMask   = 0
        obs.physicsBody = body

        addChild(obs)
        moveAndRemove(obs)
    }

    private func moveAndRemove(_ node: SKNode) {
        let dist = size.width + 80
        let duration = TimeInterval(dist / speed)
        node.run(.sequence([
            .moveBy(x: -dist, y: 0, duration: duration),
            .removeFromParent()
        ]))
    }

    // MARK: Update loop
    override func update(_ currentTime: TimeInterval) {
        guard !gameOver else { return }

        elapsed += 1.0 / 60.0

        // Ramp up difficulty every 10 s
        let rampLevel = Int(elapsed / 10)
        speed         = 220 + CGFloat(rampLevel) * 30
        spawnInterval = max(0.7, 1.8 - Double(rampLevel) * 0.12)

        // Score tick
        if Int(elapsed * 10) % 2 == 0 {
            score += multiplier
        }

        applyMotion()
    }

    private func applyMotion() {
        let motion = MotionManager.shared
        guard motion.isConnected else {
            // Demo mode: gentle drift so scene isn't empty without AirPods
            return
        }

        let pitchDeg = motion.pitch   // positive = nod forward (down)
        let rollDeg  = motion.roll    // positive = tilt right

        // Apply dead zone
        let dy = abs(pitchDeg) > deadZone ? -CGFloat(pitchDeg) * sensitivity : 0
        let dx = abs(rollDeg)  > deadZone ?  CGFloat(rollDeg)  * sensitivity : 0

        player.physicsBody?.velocity = CGVector(dx: dx, dy: dy)
    }

    // MARK: Contacts
    func didBegin(_ contact: SKPhysicsContact) {
        let masks = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if masks == Category.player | Category.obstacle {
            triggerGameOver()
        } else if masks == Category.player | Category.orb {
            let orbNode = contact.bodyA.categoryBitMask == Category.orb
                ? contact.bodyA.node
                : contact.bodyB.node
            collectOrb(orbNode)
        }
    }

    private func collectOrb(_ node: SKNode?) {
        node?.removeFromParent()
        orbStreak += 1
        multiplier = min(orbStreak, 5)

        let pop = SKShapeNode(circleOfRadius: 20)
        pop.fillColor   = SKColor(red: 1, green: 0.95, blue: 0.3, alpha: 0.7)
        pop.strokeColor = .clear
        pop.position    = player.position
        addChild(pop)
        pop.run(.sequence([
            .group([.scale(to: 2, duration: 0.2), .fadeOut(withDuration: 0.2)]),
            .removeFromParent()
        ]))
    }

    private func triggerGameOver() {
        guard !gameOver else { return }
        gameOver = true

        removeAction(forKey: "spawn")

        // Explosion burst
        let burst = SKEmitterNode()
        burst.particleBirthRate    = 0
        burst.numParticlesToEmit   = 60
        burst.particleLifetime     = 0.8
        burst.emissionAngleRange   = 360
        burst.particleSpeed        = 180
        burst.particleSpeedRange   = 100
        burst.particleAlpha        = 0.9
        burst.particleAlphaSpeed   = -1.2
        burst.particleScale        = 0.5
        burst.particleColor        = player.fillColor
        burst.position             = player.position
        burst.zPosition            = 15
        addChild(burst)
        burst.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))

        player.run(.sequence([.scale(to: 0, duration: 0.15), .removeFromParent()]))

        // Freeze obstacles
        enumerateChildNodes(withName: "obstacle") { n, _ in n.removeAllActions() }
        enumerateChildNodes(withName: "orb")      { n, _ in n.removeAllActions() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.onGameOver?(self.score)
        }
    }
}
