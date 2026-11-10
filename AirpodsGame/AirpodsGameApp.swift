import SwiftUI

@main
struct NecklineApp: App {
    init() {
        #if DEBUG
        // UI-test fixtures: start from a clean slate, optionally past onboarding.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-NLResetState"), let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        #endif
        SettingsKey.registerDefaults()
        #if DEBUG
        if arguments.contains("-NLSkipOnboarding") {
            UserDefaults.standard.set(true, forKey: SettingsKey.onboarded)
        }
        #endif
        // Start listening for transactions at launch so renewals, refunds and
        // Ask to Buy approvals are always finished and applied.
        _ = ProStore.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
