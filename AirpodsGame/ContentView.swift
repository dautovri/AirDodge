import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var motion = MotionManager.shared
    @State private var gameState: GameState = .menu
    @State private var finalScore: Int = 0
    @State private var highScore: Int = UserDefaults.standard.integer(forKey: "boxerHighScore")

    enum GameState { case menu, playing, gameOver }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch gameState {
            case .menu:    MenuView(isConnected: motion.isConnected, onStart: { gameState = .playing })
            case .playing: GameView(onGameOver: handleGameOver)
            case .gameOver:
                GameOverView(score: finalScore, highScore: highScore,
                             onRestart: { gameState = .playing },
                             onMenu:    { gameState = .menu })
            }
        }
        .onAppear  { motion.start() }
        .onDisappear { motion.stop() }
    }

    private func handleGameOver(_ score: Int) {
        finalScore = score
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(score, forKey: "boxerHighScore")
        }
        withAnimation { gameState = .gameOver }
    }
}

// MARK: - Menu

struct MenuView: View {
    let isConnected: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Title glove icon
            Text("🥊")
                .font(.system(size: 72))

            Text("AirBoxer")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.yellow, .orange],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("Slip, duck & dodge punches\nwith your head movements")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            // AirPods status
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(isConnected ? "AirPods connected — head tracking ON"
                                 : "AirPods not detected — demo mode")
                    .font(.system(size: 14))
                    .foregroundColor(isConnected ? .green : .orange)
            }
            .padding(.vertical, 4)

            // Dodge guide
            DodgeGuideView()

            Button(action: onStart) {
                HStack(spacing: 10) {
                    Text("🥊")
                    Text("Fight!")
                }
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 180, height: 58)
                .background(
                    LinearGradient(colors: [.yellow, .orange],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
                .shadow(color: .orange.opacity(0.5), radius: 14)
            }

            Spacer()
        }
        .padding()
    }
}

struct DodgeGuideView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("HOW TO DODGE").font(.caption).foregroundColor(.gray).textCase(.uppercase)
            HStack(spacing: 16) {
                DodgeItem(icon: "arrow.left", label: "Tilt left", color: .cyan)
                DodgeItem(icon: "arrow.right", label: "Tilt right", color: .cyan)
                DodgeItem(icon: "arrow.down", label: "Nod down", color: .purple)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }
}

struct DodgeItem: View {
    let icon: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(width: 70)
    }
}

// MARK: - Game

struct GameView: View {
    let onGameOver: (Int) -> Void

    var scene: GameScene {
        let s = GameScene()
        s.size = UIScreen.main.bounds.size
        s.scaleMode = .aspectFill
        s.onGameOver = onGameOver
        return s
    }

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
}

// MARK: - Game Over

struct GameOverView: View {
    let score: Int
    let highScore: Int
    let onRestart: () -> Void
    let onMenu: () -> Void

    var isNewRecord: Bool { score == highScore && score > 0 }

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Text("🥊 KO 🥊")
                .font(.system(size: 44))

            Text(isNewRecord ? "New Record!" : "Down for the Count")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(isNewRecord ? .yellow : .white)

            VStack(spacing: 6) {
                Text("\(score)")
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                Text("points").font(.headline).foregroundColor(.gray)
            }

            if !isNewRecord {
                Text("Best: \(highScore)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            VStack(spacing: 14) {
                Button(action: onRestart) {
                    Text("Fight Again")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(width: 200, height: 54)
                        .background(LinearGradient(colors: [.yellow, .orange],
                                                   startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                        .shadow(color: .orange.opacity(0.5), radius: 10)
                }

                Button(action: onMenu) {
                    Text("Main Menu")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
    }
}
