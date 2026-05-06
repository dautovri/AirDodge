import SwiftUI
import SpriteKit
import UIKit

struct ContentView: View {
    @StateObject private var motion = MotionManager.shared
    @StateObject private var gameCenter = GameCenter.shared
    @State private var gameState: GameState = .menu
    @State private var finalScore: Int = 0
    @State private var highScore: Int = UserDefaults.standard.integer(forKey: "boxerHighScore")
    @State private var settingsPresented = false
    @State private var isPaused = false
    @Environment(\.scenePhase) private var scenePhase

    enum GameState { case menu, playing, gameOver }

    var body: some View {
        ZStack {
            BackgroundGradient()

            switch gameState {
            case .menu:
                MenuView(motionStatus: motion.status,
                         highScore: highScore,
                         onStart: { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { gameState = .playing } },
                         onSettings: { settingsPresented = true })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))

            case .playing:
                GameView(isPaused: isPaused, onGameOver: handleGameOver)
                    .transition(.opacity)

            case .gameOver:
                GameOverView(score: finalScore, highScore: highScore,
                             onRestart: { withAnimation(.spring) { gameState = .playing } },
                             onMenu:    { withAnimation(.spring) { gameState = .menu } })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            // Pause overlay — visible only when in fight AND user backgrounded the app.
            if gameState == .playing && isPaused {
                PauseOverlay(onResume: {
                    Haptics.impact(.light)
                    withAnimation(.easeOut(duration: 0.2)) { isPaused = false }
                })
                .transition(.opacity)
            }
        }
        .onAppear {
            motion.start()
            gameCenter.authenticate()
        }
        .onDisappear { motion.stop() }
        .onChange(of: scenePhase) { phase in
            // Pause whenever the app is no longer the active foreground app.
            // Don't auto-resume on .active — show "Tap to resume" so the player
            // is ready (AirPods reseated, eyes back on screen).
            if gameState == .playing {
                switch phase {
                case .background, .inactive:
                    isPaused = true
                case .active:
                    break  // wait for user tap
                @unknown default:
                    isPaused = true
                }
            }
        }
        .sheet(isPresented: $settingsPresented) {
            SettingsView()
        }
    }

    private func handleGameOver(_ score: Int) {
        finalScore = score
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(score, forKey: "boxerHighScore")
        }
        gameCenter.submitKnockout()
        Haptics.notify(.warning)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { gameState = .gameOver }
    }
}

// MARK: - Pause Overlay

private struct PauseOverlay: View {
    let onResume: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("PAUSED")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white)
                Text("The fight stopped when you switched away.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button(action: onResume) {
                    Text("TAP TO RESUME")
                        .tracking(2)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 240, height: 54)
                        .background(
                            LinearGradient(colors: [.yellow, .orange],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .shadow(color: .orange.opacity(0.5), radius: 14)
                }
                .padding(.top, 8)
            }
            .padding(40)
        }
    }
}

// MARK: - Background

private struct BackgroundGradient: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.04, blue: 0.10),
                    Color(red: 0.10, green: 0.04, blue: 0.06),
                    Color(red: 0.04, green: 0.04, blue: 0.10)
                ],
                startPoint: animate ? .topLeading : .bottomLeading,
                endPoint: animate ? .bottomTrailing : .topTrailing
            )
            .ignoresSafeArea()

            // Soft radial glow accent
            RadialGradient(
                colors: [Color.orange.opacity(0.18), .clear],
                center: .top, startRadius: 20, endRadius: 380
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - Menu

struct MenuView: View {
    let motionStatus: MotionManager.Status
    let highScore: Int
    let onStart: () -> Void
    let onSettings: () -> Void

    @State private var titlePulse = false
    @State private var glovePulse = false

    var body: some View {
        VStack(spacing: 24) {
            // Top bar with best score + settings
            HStack {
                if highScore > 0 {
                    BestBadge(score: highScore)
                }
                Spacer()
                Button(action: { Haptics.impact(.light); onSettings() }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer(minLength: 8)

            // Animated glove
            Text("🥊")
                .font(.system(size: 80))
                .scaleEffect(glovePulse ? 1.06 : 1.0)
                .rotationEffect(.degrees(glovePulse ? -4 : 4))
                .shadow(color: .orange.opacity(0.55), radius: 30)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        glovePulse.toggle()
                    }
                }

            // Title
            Text("AirBoxer")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.yellow, .orange, Color(red: 1, green: 0.35, blue: 0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .orange.opacity(0.4), radius: 12, y: 2)
                .scaleEffect(titlePulse ? 1.02 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        titlePulse.toggle()
                    }
                }

            Text("Slip, duck & dodge punches\nwith head movements")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            // AirPods status chip
            ConnectionChip(status: motionStatus)
                .padding(.top, 6)

            // Dodge guide
            DodgeGuideView()
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Spacer()

            // Start button
            FightButton(action: {
                Haptics.impact(.medium)
                onStart()
            })

            Spacer(minLength: 24)
        }
    }
}

private struct BestBadge: View {
    let score: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.yellow)
            Text("BEST  \(score)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.yellow.opacity(0.35), lineWidth: 1))
    }
}

private struct ConnectionChip: View {
    let status: MotionManager.Status
    @State private var pulse = false

    private var dotColor: Color {
        switch status {
        case .live:                                  return .green
        case .waitingForData:                        return .yellow
        case .waitingForAirPods, .unknown:           return .orange
        case .unavailable:                           return .red
        }
    }

    private var label: String { status.label }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                if status.isLive {
                    Circle()
                        .stroke(Color.green.opacity(0.5), lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulse ? 1.6 : 1.0)
                        .opacity(pulse ? 0 : 1)
                }
            }
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(dotColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(dotColor.opacity(0.4), lineWidth: 1)
        )
        .onChange(of: status.isLive) { newValue in
            if newValue {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
        .onAppear {
            if status.isLive {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
    }
}

struct DodgeGuideView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("HOW TO DODGE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.45))

            HStack(spacing: 10) {
                DodgeItem(icon: "arrow.left", label: "Slip Left",  color: .cyan)
                DodgeItem(icon: "arrow.down", label: "Duck",       color: Color(red: 0.7, green: 0.45, blue: 1))
                DodgeItem(icon: "arrow.right", label: "Slip Right", color: .cyan)
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct DodgeItem: View {
    let icon: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FightButton: View {
    let action: () -> Void
    @State private var pressed = false
    @State private var glow = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("🥊")
                Text("FIGHT")
                    .tracking(2)
            }
            .font(.system(size: 22, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: 220, height: 62)
            .background(
                LinearGradient(colors: [.yellow, .orange, Color(red: 1, green: 0.35, blue: 0.2)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .orange.opacity(glow ? 0.7 : 0.45), radius: glow ? 22 : 14)
            .scaleEffect(pressed ? 0.96 : 1.0)
        }
        .buttonStyle(PressActionStyle(pressed: $pressed))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                glow.toggle()
            }
        }
    }
}

private struct PressActionStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { newValue in
                withAnimation(.easeOut(duration: 0.12)) { pressed = newValue }
            }
    }
}

// MARK: - Game

struct GameView: View {
    let isPaused: Bool
    let onGameOver: (Int) -> Void
    @State private var scene: GameScene?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let scene {
                    SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
            .onAppear {
                if scene == nil {
                    let s = GameScene()
                    s.size = geo.size
                    s.scaleMode = .resizeFill
                    s.onGameOver = onGameOver
                    scene = s
                }
            }
            .onChange(of: isPaused) { newValue in
                scene?.isPaused = newValue
            }
        }
    }
}

// MARK: - Game Over

struct GameOverView: View {
    let score: Int
    let highScore: Int
    let onRestart: () -> Void
    let onMenu: () -> Void

    @State private var displayedScore: Int = 0
    @State private var bannerVisible = false

    var isNewRecord: Bool { score == highScore && score > 0 }

    var rank: (label: String, icon: String, color: Color) {
        switch score {
        case 0..<50:    return ("Rookie",     "figure.boxing", .gray)
        case 50..<150:  return ("Contender",  "bolt.fill",     .orange)
        case 150..<300: return ("Slugger",    "flame.fill",    Color(red: 1, green: 0.5, blue: 0.2))
        case 300..<500: return ("Champion",   "rosette",       .yellow)
        default:        return ("Legend",     "crown.fill",    Color(red: 1, green: 0.85, blue: 0.2))
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            // KO splash
            VStack(spacing: 6) {
                Text("🥊  K.O.  🥊")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.3))
                    .scaleEffect(bannerVisible ? 1 : 0.6)
                    .opacity(bannerVisible ? 1 : 0)

                Text(isNewRecord ? "NEW RECORD!" : "Down for the Count")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(isNewRecord ? .yellow : .white.opacity(0.85))
                    .opacity(bannerVisible ? 1 : 0)
            }

            // Score card
            VStack(spacing: 8) {
                Text("\(displayedScore)")
                    .font(.system(size: 84, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .contentTransition(.numericText())

                Text("POINTS")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 28)

            // Rank chip
            HStack(spacing: 10) {
                Image(systemName: rank.icon)
                    .font(.system(size: 18, weight: .bold))
                Text(rank.label.uppercased())
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(2)
            }
            .foregroundStyle(rank.color)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(rank.color.opacity(0.4), lineWidth: 1))

            if !isNewRecord && highScore > 0 {
                Text("Best  \(highScore)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            VStack(spacing: 14) {
                FightAgainButton(action: {
                    Haptics.impact(.medium)
                    onRestart()
                })

                Button(action: {
                    Haptics.impact(.light)
                    onMenu()
                }) {
                    Text("Main Menu")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.bottom, 32)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                bannerVisible = true
            }
            animateScoreCount()
        }
    }

    private func animateScoreCount() {
        let duration = 0.9
        let steps = 30
        guard score > 0 else { return }
        for i in 0...steps {
            let delay = duration * Double(i) / Double(steps)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let progress = Double(i) / Double(steps)
                let eased = 1 - pow(1 - progress, 3) // easeOutCubic
                displayedScore = Int(Double(score) * eased)
                if i == steps { displayedScore = score }
            }
        }
    }
}

private struct FightAgainButton: View {
    let action: () -> Void
    @State private var pressed = false
    var body: some View {
        Button(action: action) {
            Text("FIGHT AGAIN")
                .tracking(2)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 220, height: 56)
                .background(
                    LinearGradient(colors: [.yellow, .orange],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .orange.opacity(0.5), radius: 14)
                .scaleEffect(pressed ? 0.96 : 1)
        }
        .buttonStyle(PressActionStyle(pressed: $pressed))
    }
}

// MARK: - Haptics

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(type)
    }
}
