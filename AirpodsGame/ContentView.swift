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
    /// Tracks whether we just came back from background — triggers motion.restart()
    /// to recover from CoreMotion suspension. See scenePhase handler below.
    @State private var wasBackgrounded = false
    /// Currently selected opponent. Defaults to Sandbag for first-time users —
    /// per the CEO plan, the tutorial is opponent #1 in the roster.
    @State private var selectedOpponent: OpponentDefinition = .sandbag
    @Environment(\.scenePhase) private var scenePhase

    enum GameState { case menu, playing, gameOver }

    /// Allow entering the fight without live AirPods data ONLY in the iOS
    /// Simulator — head tracking can't deliver data there, but we still
    /// want to inspect the UI. On real hardware the motion gate stands.
    private var canStart: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return motion.status.isLive
        #endif
    }

    var body: some View {
        ZStack {
            BackgroundGradient()

            switch gameState {
            case .menu:
                MenuView(motionStatus: motion.status,
                         highScore: highScore,
                         canStart: canStart,
                         selectedOpponent: $selectedOpponent,
                         onStart: { startFight() },
                         onSettings: { settingsPresented = true })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))

            case .playing:
                GameView(isPaused: isPaused,
                         opponent: selectedOpponent,
                         onGameOver: handleGameOver)
                    .transition(.opacity)

            case .gameOver:
                GameOverView(score: finalScore, highScore: highScore,
                             canRestart: canStart,
                             motionStatus: motion.status,
                             onRestart: { startFight() },
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
                    wasBackgrounded = true
                    isPaused = true
                case .active:
                    // /autoplan eng review finding #14: CoreMotion suspends
                    // CMHeadphoneMotionManager on background. On return, the
                    // stream is dead but isStreaming is still true so a plain
                    // start() is a no-op. Force a restart from clean state.
                    if wasBackgrounded {
                        motion.restart()
                        wasBackgrounded = false
                    }
                @unknown default:
                    isPaused = true
                }
            } else if phase == .active && wasBackgrounded {
                // Even from the menu, if we came back from background, make
                // sure the motion peer is alive so the FIGHT button gates correctly.
                motion.restart()
                wasBackgrounded = false
            }
        }
        .sheet(isPresented: $settingsPresented) {
            SettingsView()
        }
    }

    /// Belt-and-suspenders gate. The buttons are disabled when AirPods aren't
    /// live, but if any path slips through (race on motion.start, returning
    /// from settings), this guards the actual state transition.
    private func startFight() {
        guard canStart else {
            Haptics.notify(.warning)
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            gameState = .playing
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
    let canStart: Bool
    @Binding var selectedOpponent: OpponentDefinition
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

            // `fixedSize` is required: without it this two-line tagline gets
            // squeezed to one truncated line ("Slip, duck & dodge punches…")
            // whenever the menu is vertically tight — which is exactly the
            // no-motion layout an App Review reviewer sees first.
            Text("Slip, duck & dodge punches\nwith head movements")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Motion status chip
            ConnectionChip(status: motionStatus)
                .padding(.top, 6)

            if motionStatus.isLive {
                // Roster picker — 3 cards, one per opponent. Replaces the static
                // 'HOW TO DODGE' guide that was redundant after the tutorial.
                // Required by Apple Guideline 4.2 (minimum functionality) — the
                // game ships with 3 opponents and the user must be able to pick.
                OpponentPicker(selected: $selectedOpponent)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            } else {
                // Guideline 2.1 (App Completeness): a reviewer on a bare device
                // has no motion earbuds. Previously they got a grey dead button
                // and one line of 12pt 40%-opacity grey text — indistinguishable
                // from a broken build. This card takes the roster's slot and
                // states the hardware requirement, the reason, and the next step
                // outright. No touch-control fallback by design (see TODOS C4).
                MotionRequirementCard(status: motionStatus)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }

            Spacer()

            // Start button — disabled until motion earbuds are connected and
            // delivering data. The fight is unplayable without head tracking,
            // so we don't let the user enter the scene.
            FightButton(isEnabled: canStart, action: {
                Haptics.impact(.medium)
                onStart()
            })

            if canStart && !motionStatus.isLive {
                // Simulator-only bypass is active. Say so, otherwise an enabled
                // FIGHT button sitting under a "no earbuds" chip reads as a bug.
                Text("SIMULATOR PREVIEW — head tracking is inactive")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.yellow.opacity(0.85))
                    .padding(.top, -4)
            }
            // No microcopy under the disabled button: the button now labels its
            // own gate and the card above carries the full explanation. Three
            // restatements of the same requirement read as unfinished.

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
    @State private var spinRetry = false

    /// Nothing here is an error, so nothing here is alarm-red. Red on launch
    /// made a documented hardware requirement look like a crash to App Review.
    /// Amber = "set something up", green = "ready".
    private var dotColor: Color {
        switch status {
        case .live:                                                        return .green
        case .waitingForData:                                              return .yellow
        case .waitingForAirPods, .unknown,
             .permissionDenied, .unavailable:                              return .orange
        }
    }

    private var label: String { status.label }

    /// Chip is tappable in any non-live state. Tap = restart motion stream
    /// (or open Settings when permission is the blocker).
    private var isTappable: Bool { !status.isLive }
    private var opensSettings: Bool { status == .permissionDenied }

    var body: some View {
        let chip = HStack(spacing: 10) {
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
            if isTappable {
                Image(systemName: opensSettings ? "arrow.up.right.square" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(dotColor)
                    .rotationEffect(.degrees(spinRetry ? 360 : 0))
            }
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

        if isTappable {
            Button {
                Haptics.impact(.light)
                if opensSettings {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    // Spin the retry icon for visual feedback while we restart
                    withAnimation(.easeInOut(duration: 0.6)) { spinRetry.toggle() }
                    MotionManager.shared.restart()
                }
            } label: { chip }
            .buttonStyle(.plain)
        } else {
            chip
        }
    }
}

/// Self-explanatory hardware-setup state, shown wherever the fight is gated on
/// head tracking. Deliberately reads as onboarding, not as an error: headline,
/// why the hardware is needed, the concrete next step, and what to expect once
/// it's connected. Never mentions a brand — the 5.2.1 resubmit scrubbed those.
struct MotionRequirementCard: View {
    let status: MotionManager.Status
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                Image(systemName: "airpods.gen3")
                    .font(.system(size: compact ? 20 : 26, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange],
                                       startPoint: .top, endPoint: .bottom)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    // Deliberately not the same string as the locked button —
                    // repeating it verbatim twice on one screen read as a bug.
                    Text("MOTION EARBUDS REQUIRED")
                        .font(.system(size: compact ? 11 : 12, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.yellow)
                    Text("This is a motion game — there are no touch controls.")
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !compact {
                Divider().overlay(Color.white.opacity(0.12))

                Text("You dodge punches by physically moving your head. AirBoxer reads that movement from earbuds that stream head-motion data to iPhone, so a pair must be connected and worn before a fight can start.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // The one thing to do next, driven by the live motion status.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.orange)
                Text(status.nextStep)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, compact ? 0 : 2)
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Head tracking required. \(status.label). \(status.nextStep)")
    }
}

struct OpponentPicker: View {
    @Binding var selected: OpponentDefinition

    var body: some View {
        VStack(spacing: 10) {
            Text("CHOOSE YOUR OPPONENT")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.45))

            HStack(spacing: 10) {
                ForEach(OpponentDefinition.allOpponents, id: \.id) { opponent in
                    OpponentCard(
                        opponent: opponent,
                        isSelected: opponent.id == selected.id,
                        onTap: {
                            Haptics.impact(.light)
                            selected = opponent
                        }
                    )
                }
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OpponentCard: View {
    let opponent: OpponentDefinition
    let isSelected: Bool
    let onTap: () -> Void

    /// Difficulty badge color matched to opponent identity from the data model.
    private var accent: Color {
        switch opponent.id {
        case "sandbag":       return Color(red: 0.95, green: 0.85, blue: 0.50)
        case "vitrine_bloom": return Color(red: 0.65, green: 0.45, blue: 0.85)
        case "the_warden":    return Color(red: 1.00, green: 0.30, blue: 0.20)
        default:              return .white
        }
    }

    private var difficulty: String {
        // Telegraph speed encodes difficulty: 2.2s = easy, 1.6s = medium, 1.0s = hard
        switch opponent.telegraphSec {
        case 1.8...:  return "TRAINING"
        case 1.3...:  return "REGULAR"
        default:      return "BOSS"
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(difficulty)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(accent.opacity(0.85))
                Text(opponent.name)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(opponent.country)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                Text(opponent.record)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)
            }
            .padding(.vertical, 12).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.18) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? accent : Color.white.opacity(0.10),
                            lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? accent.opacity(0.45) : .clear,
                    radius: isSelected ? 10 : 0)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

private struct FightButton: View {
    var isEnabled: Bool = true
    let action: () -> Void
    @State private var pressed = false
    @State private var glow = false

    var body: some View {
        Button(action: action) {
            // When gated, the button states its own reason instead of being a
            // mute grey slab — black-on-grey "FIGHT" both failed contrast and
            // told the player nothing.
            HStack(spacing: 10) {
                if isEnabled {
                    Text("🥊")
                    Text("FIGHT")
                        .tracking(2)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("HEAD TRACKING REQUIRED")
                        .tracking(1)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                }
            }
            .foregroundStyle(isEnabled ? .black : Color.white.opacity(0.85))
            .frame(width: 260, height: 62)
            .background(
                Group {
                    if isEnabled {
                        LinearGradient(colors: [.yellow, .orange, Color(red: 1, green: 0.35, blue: 0.2)],
                                       startPoint: .leading, endPoint: .trailing)
                    } else {
                        // Muted, but dark enough that the white lock + label
                        // clear AA contrast. Reads "locked", not "broken".
                        LinearGradient(colors: [Color.white.opacity(0.10),
                                                 Color.white.opacity(0.06),
                                                 Color.white.opacity(0.10)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(isEnabled ? 0.35 : 0.15), lineWidth: 1))
            .shadow(color: isEnabled ? .orange.opacity(glow ? 0.7 : 0.45) : .clear,
                    radius: isEnabled ? (glow ? 22 : 14) : 0)
            .scaleEffect(pressed ? 0.96 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.7)
        }
        .buttonStyle(PressActionStyle(pressed: $pressed))
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.25), value: isEnabled)
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
    let opponent: OpponentDefinition
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
                    s.opponent = opponent     // drive timings/HP/punch set/music
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
    let canRestart: Bool
    let motionStatus: MotionManager.Status
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
                // Same Guideline 2.1 reasoning as the menu: never strand the
                // user behind a grey button with no explanation. Compact
                // variant so the score card still owns the screen.
                if !canRestart {
                    MotionRequirementCard(status: motionStatus, compact: true)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 4)
                }

                FightAgainButton(isEnabled: canRestart, action: {
                    Haptics.impact(.medium)
                    onRestart()
                })

                // Always-live escape hatch — styled as a real button so the
                // screen is never a dead end, even when FIGHT AGAIN is gated.
                Button(action: {
                    Haptics.impact(.light)
                    onMenu()
                }) {
                    Text("MAIN MENU")
                        .tracking(1.5)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 220, height: 48)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
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
    var isEnabled: Bool = true
    let action: () -> Void
    @State private var pressed = false
    var body: some View {
        Button(action: action) {
            Group {
                if isEnabled {
                    Text("FIGHT AGAIN").tracking(2)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("HEAD TRACKING REQUIRED").tracking(1)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                }
            }
                .foregroundStyle(isEnabled ? .black : Color.white.opacity(0.85))
                .frame(width: 260, height: 56)
                .background(
                    Group {
                        if isEnabled {
                            LinearGradient(colors: [.yellow, .orange],
                                           startPoint: .leading, endPoint: .trailing)
                        } else {
                            LinearGradient(colors: [Color.white.opacity(0.10),
                                                     Color.white.opacity(0.06)],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(isEnabled ? 0.35 : 0.15), lineWidth: 1))
                .shadow(color: isEnabled ? .orange.opacity(0.5) : .clear, radius: isEnabled ? 14 : 0)
                .scaleEffect(pressed ? 0.96 : 1)
                .opacity(isEnabled ? 1.0 : 0.7)
        }
        .buttonStyle(PressActionStyle(pressed: $pressed))
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.25), value: isEnabled)
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
