import StoreKit
import SwiftUI
import SpriteKit
import UIKit

struct ContentView: View {
    @State private var motion = MotionManager.shared
    @State private var gameCenter = GameCenter.shared
    /// Menu / results theme. The fight scene owns its own AudioSystem.
    @State private var menuAudio = AudioSystem()
    @State private var gameState: GameState = .menu
    @State private var finalScore: Int = 0
    @State private var lastFightWon = false
    @State private var highScore: Int = UserDefaults.standard.integer(forKey: "boxerHighScore")
    @State private var settingsPresented = false
    @State private var unlockPresented = false
    @State private var howToPresented = false
    @State private var store = UnlockStore.shared
    @State private var isPaused = false
    /// Tracks whether we just came back from background — triggers motion.restart()
    /// to recover from CoreMotion suspension. See scenePhase handler below.
    @State private var wasBackgrounded = false
    /// Currently selected opponent. Defaults to Sandbag for first-time users —
    /// per the CEO plan, the tutorial is opponent #1 in the roster.
    @State private var selectedOpponent: OpponentDefinition = .sandbag
    /// Players without head-tracking headphones can opt into touch controls.
    @AppStorage(SettingsKey.touchControls) private var touchOptIn = false
    /// Opponents knocked out at least once — drives the ladder locks.
    @State private var beaten: Set<String> = LadderStore().beaten
    /// Control mode locked in when the fight starts.
    @State private var fightMode: ControlMode = .headTracking
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    enum GameState { case menu, playing, gameOver }

    /// Head tracking when it's live, touch when the player opted in, or nil
    /// (the fight is gated and the setup card explains why).
    private var controlMode: ControlMode? {
        ControlMode.resolve(headTrackingLive: motion.status.isLive, touchOptIn: touchOptIn)
    }

    private var canStart: Bool { controlMode != nil }

    private func isLadderOpen(_ opponent: OpponentDefinition) -> Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ABUnlocked") { return true }
        #endif
        return OpponentLadder.isOpen(opponent, beaten: beaten)
    }

    var body: some View {
        ZStack {
            BackgroundGradient()

            switch gameState {
            case .menu:
                MenuView(motionStatus: motion.status,
                         highScore: highScore,
                         controlMode: controlMode,
                         selectedOpponent: $selectedOpponent,
                         isLocked: { store.isLocked($0) },
                         ladderGatekeeper: { opponent in
                             isLadderOpen(opponent) ? nil
                                 : OpponentLadder.gatekeeper(for: opponent, beaten: beaten)
                         },
                         onLockedTap: { unlockPresented = true },
                         onTouchMode: { setTouchMode($0) },
                         onStart: { startFight() },
                         onHowTo: { howToPresented = true },
                         onSettings: { settingsPresented = true })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))

            case .playing:
                GameView(isPaused: isPaused,
                         opponent: selectedOpponent,
                         controlMode: fightMode,
                         onGameOver: handleGameOver)
                    .transition(.opacity)

            case .gameOver:
                GameOverView(score: finalScore, highScore: highScore,
                             won: lastFightWon,
                             opponentName: selectedOpponent.name,
                             canRestart: canStart,
                             motionStatus: motion.status,
                             wasTouchFight: fightMode == .touch,
                             onTouchMode: { setTouchMode(true) },
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
            menuAudio.startMusic(named: "menu_loop", volume: 0.45)
            #if DEBUG
            // Screenshot fixtures: -ABFight <opponent id> / -ABScreen howto|unlock
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-ABFight"), i + 1 < args.count,
               let opponent = OpponentDefinition.allOpponents.first(where: { $0.id == args[i + 1] }) {
                selectedOpponent = opponent
                Task {
                    await store.refreshEntitlement()
                    try? await Task.sleep(for: .seconds(1))
                    startFight()
                }
            }
            if let i = args.firstIndex(of: "-ABScreen"), i + 1 < args.count {
                switch args[i + 1] {
                case "howto": howToPresented = true
                case "unlock": unlockPresented = true
                case "settings": settingsPresented = true
                default: break
                }
            }
            #endif
        }
        .onChange(of: gameState) { old, new in
            if new == .playing {
                menuAudio.stopMusic(fadeOver: 0.4)
            } else if old == .playing {
                menuAudio.startMusic(named: "menu_loop", volume: 0.45)
            }
        }
        .onDisappear { motion.stop() }
        .onChange(of: scenePhase) { _, phase in
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
        .sheet(isPresented: $unlockPresented) {
            UnlockView()
        }
        .sheet(isPresented: $howToPresented) {
            HowToPlayView()
        }
        .sheet(isPresented: $settingsPresented, onDismiss: {
            // Apply the Sound toggle to the theme that's already playing.
            if UserDefaults.standard.bool(forKey: SettingsKey.soundEnabled) {
                if gameState != .playing { menuAudio.startMusic(named: "menu_loop", volume: 0.45) }
            } else {
                menuAudio.stopMusic(fadeOver: 0)
            }
        }) {
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
        guard !store.isLocked(selectedOpponent) else {
            unlockPresented = true
            return
        }
        guard isLadderOpen(selectedOpponent), let mode = controlMode else {
            Haptics.notify(.warning)
            return
        }
        fightMode = mode
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            gameState = .playing
        }
    }

    private func handleGameOver(_ result: FightResult) {
        let score = result.score
        finalScore = score
        lastFightWon = result.won
        let isNewBest = score > highScore && score > 0
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(score, forKey: "boxerHighScore")
        }
        if result.won {
            LadderStore().recordWin(over: result.opponentID)
            beaten = LadderStore().beaten
            // The knockouts leaderboard counts knockouts the player lands,
            // not the ones they take — and only head-tracking fights.
            if result.controlMode.postsToLeaderboards { gameCenter.submitKnockout() }
        }
        Haptics.notify(result.won ? .success : .warning)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { gameState = .gameOver }

        // Ask for a rating only right after a satisfying moment, and let the
        // results screen land first. Gating lives in ReviewPromptPolicy.
        let opponent = OpponentDefinition.allOpponents.first { $0.id == result.opponentID }
        let moment = ReviewPromptPolicy.Moment.fightEnded(
            won: result.won, againstTutorial: opponent?.isTutorial ?? false, newBestScore: isNewBest)
        let reviewStore = ReviewPromptStore()
        if reviewStore.registerFightAndCheck(moment) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                // Skip (and keep the chance) if the player already moved on.
                guard gameState == .gameOver else { return }
                reviewStore.recordPromptShown()
                requestReview()
            }
        }
    }

    private func setTouchMode(_ on: Bool) {
        Haptics.impact(.light)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { touchOptIn = on }
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
    let controlMode: ControlMode?
    @Binding var selectedOpponent: OpponentDefinition
    let isLocked: (OpponentDefinition) -> Bool
    var ladderGatekeeper: (OpponentDefinition) -> OpponentDefinition? = { _ in nil }
    let onLockedTap: () -> Void
    var onTouchMode: (Bool) -> Void = { _ in }
    let onStart: () -> Void
    let onHowTo: () -> Void
    let onSettings: () -> Void

    @State private var titlePulse = false
    @State private var glovePulse = false

    private var canStart: Bool { controlMode != nil }

    var body: some View {
        VStack(spacing: 24) {
            // Top bar with best score + settings
            HStack {
                if highScore > 0 {
                    BestBadge(score: highScore)
                }
                Spacer()
                Button(action: { Haptics.impact(.light); onHowTo() }) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .accessibilityLabel("How to Play")
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

            if controlMode == .touch {
                TouchModeBanner(onTurnOff: { onTouchMode(false) })
                    .padding(.horizontal, 24)
            }

            if canStart {
                // Roster picker — 3 cards, one per opponent. Replaces the static
                // 'HOW TO DODGE' guide that was redundant after the tutorial.
                // Required by Apple Guideline 4.2 (minimum functionality) — the
                // game ships with 3 opponents and the user must be able to pick.
                OpponentPicker(selected: $selectedOpponent, isLocked: isLocked,
                               ladderGatekeeper: ladderGatekeeper, onLockedTap: onLockedTap)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            } else {
                // Guideline 2.1 (App Completeness): a reviewer on a bare device
                // has no motion earbuds. Previously they got a grey dead button
                // and one line of 12pt 40%-opacity grey text — indistinguishable
                // from a broken build. This card takes the roster's slot and
                // states the hardware requirement, the reason, and the next step
                // outright, and offers touch controls so nobody is stranded.
                MotionRequirementCard(status: motionStatus, onTouchMode: { onTouchMode(true) })
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
        .onChange(of: status.isLive) { _, newValue in
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
    /// Switches the game to touch controls. Shown for every state except
    /// `.waitingForData` (headphones connected, just not worn yet).
    var onTouchMode: (() -> Void)?

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                Image(systemName: "headphones")
                    .font(.system(size: compact ? 20 : 26, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange],
                                       startPoint: .top, endPoint: .bottom)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    // Deliberately not the same string as the locked button —
                    // repeating it verbatim twice on one screen read as a bug.
                    Text("HEAD-TRACKING HEADPHONES REQUIRED")
                        .font(.system(size: compact ? 11 : 12, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.yellow)
                    Text("Your head is the controller. No compatible headphones? Play with touch.")
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !compact {
                // Shows the mechanic instead of describing it: you dodge by
                // physically moving your head, read from earbuds that stream
                // head-motion data to iPhone.
                DodgeDemoView()
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(minHeight: 130)
                    .clipShape(.rect(cornerRadius: 12))
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

            if let onTouchMode, status != .waitingForData {
                Button(action: onTouchMode) {
                    Label("PLAY WITH TOUCH", systemImage: "hand.tap.fill")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.yellow, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Hold the left or right side of the screen to slip, the middle to duck."))
            }
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Shown on the menu while the touch fallback is active. Head tracking takes
/// over automatically as soon as compatible headphones stream motion.
private struct TouchModeBanner: View {
    let onTurnOff: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("TOUCH MODE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.yellow)
                Text("Connect headphones that support head tracking for the full motion game.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Turn off", action: onTurnOff)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10).frame(minHeight: 32)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.yellow.opacity(0.35), lineWidth: 1))
    }
}

struct OpponentPicker: View {
    @Binding var selected: OpponentDefinition
    var isLocked: (OpponentDefinition) -> Bool = { _ in false }
    /// Non-nil when the opponent is closed on the ladder: who to beat first.
    var ladderGatekeeper: (OpponentDefinition) -> OpponentDefinition? = { _ in nil }
    var onLockedTap: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Text("CHOOSE YOUR OPPONENT")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.45))

            HStack(spacing: 10) {
                ForEach(OpponentDefinition.allOpponents, id: \.id) { opponent in
                    let gatekeeper = ladderGatekeeper(opponent)
                    OpponentCard(
                        opponent: opponent,
                        isSelected: opponent.id == selected.id,
                        isLocked: isLocked(opponent),
                        gatekeeper: gatekeeper,
                        onTap: {
                            if gatekeeper != nil {
                                Haptics.notify(.warning)
                            } else if isLocked(opponent) {
                                Haptics.impact(.light)
                                onLockedTap()
                            } else {
                                Haptics.impact(.light)
                                selected = opponent
                            }
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
    var isLocked = false
    var gatekeeper: OpponentDefinition?
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
        case 1.8...:  return String(localized: "TRAINING")
        case 1.3...:  return String(localized: "REGULAR")
        default:      return String(localized: "BOSS")
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
                if let gatekeeper {
                    Label {
                        Text("BEAT \(gatekeeper.name)")
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)
                } else if isLocked {
                    Label("UNLOCK", systemImage: "lock.fill")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                } else {
                    Text(opponent.record)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 2)
                }
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
            .opacity(gatekeeper == nil ? 1 : 0.8)
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
            .onChange(of: configuration.isPressed) { _, newValue in
                withAnimation(.easeOut(duration: 0.12)) { pressed = newValue }
            }
    }
}

// MARK: - Game

struct GameView: View {
    let isPaused: Bool
    let opponent: OpponentDefinition
    var controlMode: ControlMode = .headTracking
    let onGameOver: (FightResult) -> Void
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
                    s.controlMode = controlMode
                    s.onGameOver = onGameOver
                    scene = s
                }
            }
            .onChange(of: isPaused) { _, newValue in
                scene?.isPaused = newValue
            }
        }
    }
}

// MARK: - Game Over

struct GameOverView: View {
    let score: Int
    let highScore: Int
    var won = false
    var opponentName = ""
    let canRestart: Bool
    let motionStatus: MotionManager.Status
    var wasTouchFight = false
    var onTouchMode: () -> Void = {}
    let onRestart: () -> Void
    let onMenu: () -> Void

    @State private var displayedScore: Int = 0
    @State private var bannerVisible = false

    var isNewRecord: Bool { score == highScore && score > 0 }

    var rank: (label: String, icon: String, color: Color) {
        switch score {
        case 0..<50:    return (String(localized: "Rookie"),     "figure.boxing", .gray)
        case 50..<150:  return (String(localized: "Contender"),  "bolt.fill",     .orange)
        case 150..<300: return (String(localized: "Slugger"),    "flame.fill",    Color(red: 1, green: 0.5, blue: 0.2))
        case 300..<500: return (String(localized: "Champion"),   "rosette",       .yellow)
        default:        return (String(localized: "Legend"),     "crown.fill",    Color(red: 1, green: 0.85, blue: 0.2))
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            // KO splash
            VStack(spacing: 6) {
                Text(won ? String(localized: "🏆  YOU WIN  🏆") : "🥊  K.O.  🥊")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(won ? Color(red: 0.3, green: 1, blue: 0.55) : Color(red: 1, green: 0.3, blue: 0.3))
                    .scaleEffect(bannerVisible ? 1 : 0.6)
                    .opacity(bannerVisible ? 1 : 0)

                Text(isNewRecord ? String(localized: "NEW RECORD!") : (won ? String(localized: "\(opponentName) is down") : "Down for the Count"))
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

            if wasTouchFight {
                Text("Touch fight · not posted to Game Center")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

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
                    MotionRequirementCard(status: motionStatus, compact: true, onTouchMode: onTouchMode)
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
            Task {
                try? await Task.sleep(for: .seconds(delay))
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
