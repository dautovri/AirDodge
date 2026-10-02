import SwiftUI

@main
struct AirpodsGameApp: App {
    init() {
        // Register defaults so first-launch reads return the right values
        // (UserDefaults integer/bool default to 0/false otherwise — would
        // give "Very Lenient" sensitivity and silent haptics on day one).
        UserDefaults.standard.register(defaults: [
            SettingsKey.motionSensitivity: MotionSensitivityLevel.standard.rawValue,
            SettingsKey.soundEnabled:      true,
            SettingsKey.hapticsEnabled:    true,
            SettingsKey.scanlineEnabled:   true,
        ])
        // Start listening for transactions at launch so Ask to Buy approvals
        // and refunds are always finished and applied.
        _ = UnlockStore.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBar(hidden: true)
        }
    }
}
