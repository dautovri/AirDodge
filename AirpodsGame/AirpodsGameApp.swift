import SwiftUI

@main
struct NecklineApp: App {
    init() {
        SettingsKey.registerDefaults()
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
