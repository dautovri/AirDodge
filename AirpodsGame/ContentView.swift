import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var motion = MotionManager.shared
    @State private var gameState: GameState = .menu
    @State private var finalScore: Int = 0
    @State private var highScore: Int = UserDefaults.standard.integer(forKey: "highScore")

    enum GameState { case menu, playing, gameOver }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch gameState {
            case .menu:    MenuView(isConnected: motion.isConnected, onStart: startGame)
            case .playing: GameView(onGameOver: handleGameOver)
            case .gameOver:
                GameOverView(score: finalScore, highScore: highScore, onRestart: startGame, onMenu: {
                    gameState = .menu
                })
            }
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private func startGame() {
        gameState = .playing
    }

    private func handleGameOver(score: Int) {
        finalScore = score
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(score, forKey: "highScore")
        }
        withAnimation { gameState = .gameOver }
    }
}

// MARK: - Menu

struct MenuView: View {
    let isConnected: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("AirDodge")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("Tilt your head to dodge obstacles\nand collect orbs to boost your score")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(isConnected ? "AirPods connected" : "AirPods not detected — demo mode")
                        .font(.system(size: 14))
                        .foregroundColor(isConnected ? .green : .orange)
                }

                if !isConnected {
                    Text("Put on your AirPods Pro for head tracking")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }

            ControlHintView()

            Button(action: onStart) {
                Text("Play")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(width: 160, height: 56)
                    .background(Color.cyan)
                    .clipShape(Capsule())
                    .shadow(color: .cyan.opacity(0.6), radius: 12)
            }

            Spacer()
        }
        .padding()
    }
}

struct ControlHintView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Controls").font(.caption).foregroundColor(.gray).textCase(.uppercase)
            HStack(spacing: 24) {
                HintItem(symbol: "arrow.up.arrow.down", label: "Pitch head\nup / down")
                HintItem(symbol: "arrow.left.arrow.right", label: "Tilt head\nleft / right")
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

struct HintItem: View {
    let symbol: String
    let label: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundColor(.cyan)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
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
        VStack(spacing: 28) {
            Spacer()

            Text(isNewRecord ? "New Record!" : "Game Over")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(isNewRecord ? .yellow : .white)

            VStack(spacing: 8) {
                Text("\(score)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
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
                    Text("Play Again")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(width: 200, height: 54)
                        .background(Color.cyan)
                        .clipShape(Capsule())
                        .shadow(color: .cyan.opacity(0.5), radius: 10)
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
