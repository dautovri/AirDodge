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

@MainActor
@Observable
final class GameCenter {

    static let shared = GameCenter()

    private(set) var isAuthenticated = false
    private(set) var displayName: String = ""

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
            // Only Sendable values cross into the main-actor hop: the
            // UIViewController and GKLocalPlayer stay on the caller's side.
            let needsAuthUI = viewController != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    log.error("auth error: \(error.localizedDescription, privacy: .public)")
                    self.isAuthenticated = false
                    return
                }
                if needsAuthUI {
                    // Auth UI required. We don't auto-present — leaving it to the
                    // user to sign in via Settings → "Sign in to Game Center".
                    self.isAuthenticated = false
                    return
                }
                let player = GKLocalPlayer.local
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

    /// Records a knockout and submits the player's running total. The
    /// leaderboard keeps each player's best score, so it must be sent the
    /// total, not a delta of 1.
    func submitKnockout() {
        let total = UserDefaults.standard.integer(forKey: Self.totalKnockoutsKey) + 1
        UserDefaults.standard.set(total, forKey: Self.totalKnockoutsKey)
        guard isAuthenticated else { return }
        Task {
            try? await GKLeaderboard.submitScore(
                total,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [LeaderboardID.totalKOs]
            )
        }
    }

    private static let totalKnockoutsKey = "boxerTotalKnockouts"
}
