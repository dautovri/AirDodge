import GameKit
import SwiftUI

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
//
// iOS 16 compatible: ObservableObject + @Published. Migrates to @Observable
// when the deployment target bumps (see TODOS.md).

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
        player.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let error {
                print("[GameCenter] auth error: \(error.localizedDescription)")
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
