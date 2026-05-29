import GameKit
import SwiftUI
import os

private let log = Logger(subsystem: "com.airdodge.AirpodsGame", category: "AirBoxer.gamecenter")

// GameKit integration. Authenticate at app launch; submit scores after KO.
//
// Leaderboards are configured in App Store Connect via the bundle ID's
// Game Center settings. The IDs below match what we'll create in ASC:
//
//   com.airdodge.AirpodsGame.leaderboard.streak    — longest dodge streak
//   com.airdodge.AirpodsGame.leaderboard.totalkos  — cumulative knockouts
//
// If GKLocalPlayer isn't authenticated (offline / declined), submission is a
// silent no-op — never block gameplay on Game Center availability.

// NOTE: ObservableObject + @Published rather than @Observable — deployment
// target is iOS 16 (@Observable requires iOS 17+). See MotionManager note.
final class GameCenter: ObservableObject {

    static let shared = GameCenter()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var displayName: String = ""

    enum LeaderboardID {
        static let streak    = "com.airdodge.AirpodsGame.leaderboard.streak"
        static let totalKOs  = "com.airdodge.AirpodsGame.leaderboard.totalkos"
    }

    private init() {}

    // Call once at app launch.
    func authenticate() {
        let player = GKLocalPlayer.local
        // GameKit invokes the handler on an arbitrary queue — hop to the main
        // actor before touching observable state.
        player.authenticateHandler = { viewController, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    log.error("auth error: \(error.localizedDescription, privacy: .public)")
                    self.isAuthenticated = false
                    return
                }
                if viewController != nil {
                    // Auth UI required. We don't auto-present — leaving it to the
                    // user to sign in via Settings → "Sign in to Game Center".
                    self.isAuthenticated = false
                    return
                }
                self.isAuthenticated = player.isAuthenticated
                self.displayName = player.alias
            }
        }
    }

    // Submit longest streak (per-fight max consecutive dodges).
    func submitStreak(_ value: Int) {
        guard isAuthenticated, value > 0 else { return }
        Task {
            try? await GKLeaderboard.submitScore(
                value,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [LeaderboardID.streak]
            )
        }
    }

    // Submit a knockout (delta — Game Center handles cumulative on the dashboard).
    func submitKnockout() {
        guard isAuthenticated else { return }
        Task {
            try? await GKLeaderboard.submitScore(
                1,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [LeaderboardID.totalKOs]
            )
        }
    }
}
