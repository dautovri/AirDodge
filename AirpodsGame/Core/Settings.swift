import StoreKit
import SwiftUI

// User-tunable settings, backed by UserDefaults via @AppStorage.

enum SettingsKey {
    static let postureSensitivity = "settings.postureSensitivity"
    static let nudgeDelay         = "settings.nudgeDelay"
    static let stretchRange       = "settings.stretchRange"
    static let voiceCues          = "settings.voiceCues"
    static let hapticsEnabled     = "settings.hapticsEnabled"
    static let onboarded          = "settings.onboarded"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            postureSensitivity: PostureSensitivity.standard.rawValue,
            nudgeDelay:         NudgeDelay.ten.rawValue,
            stretchRange:       StretchRange.normal.rawValue,
            voiceCues:          true,
            hapticsEnabled:     true,
        ])
    }
}

/// How far the head may drop before it counts as slouching.
enum PostureSensitivity: Int, CaseIterable, Identifiable {
    case relaxed, standard, strict
    var id: Int { rawValue }

    var threshold: Double {
        switch self {
        case .relaxed:  return 20
        case .standard: return 15
        case .strict:   return 10
        }
    }

    var label: String {
        switch self {
        case .relaxed:  return String(localized: "Relaxed")
        case .standard: return String(localized: "Standard")
        case .strict:   return String(localized: "Strict")
        }
    }
}

enum NudgeDelay: Int, CaseIterable, Identifiable {
    case five = 5, ten = 10, twenty = 20, forty = 40
    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String { String(localized: "\(rawValue) s") }
}

/// Scales every stretch target, for stiffer or more mobile necks.
enum StretchRange: Int, CaseIterable, Identifiable {
    case gentle, normal, deep
    var id: Int { rawValue }

    var scale: Double {
        switch self {
        case .gentle: return 0.7
        case .normal: return 1.0
        case .deep:   return 1.25
        }
    }

    var label: String {
        switch self {
        case .gentle: return String(localized: "Gentle")
        case .normal: return String(localized: "Normal")
        case .deep:   return String(localized: "Deep")
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage(SettingsKey.postureSensitivity) private var sensitivityRaw = PostureSensitivity.standard.rawValue
    @AppStorage(SettingsKey.nudgeDelay)         private var nudgeDelayRaw = NudgeDelay.ten.rawValue
    @AppStorage(SettingsKey.stretchRange)       private var rangeRaw = StretchRange.normal.rawValue
    @AppStorage(SettingsKey.voiceCues)          private var voiceCues = true
    @AppStorage(SettingsKey.hapticsEnabled)     private var haptics = true

    @State private var pro = ProStore.shared
    @State private var showPaywall = false
    @State private var showManage = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if pro.isPro {
                        Label("Neckline Pro is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.accent)
                        Button("Manage Subscription") { showManage = true }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Upgrade to Neckline Pro", systemImage: "sparkles")
                        }
                    }
                    Button("Restore Purchases") {
                        Task { await pro.restore() }
                    }
                } header: {
                    Text("Subscription")
                }

                Section {
                    Picker("Sensitivity", selection: $sensitivityRaw) {
                        ForEach(PostureSensitivity.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Nudge after", selection: $nudgeDelayRaw) {
                        ForEach(NudgeDelay.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text("Posture Alerts")
                } footer: {
                    Text("Strict alerts on smaller head drops. Nudge after sets how long your head can stay down before you're reminded.")
                }

                Section {
                    Picker("Stretch range", selection: $rangeRaw) {
                        ForEach(StretchRange.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text("Routines")
                } footer: {
                    Text("Gentle lowers every target angle. Never push into pain.")
                }

                Section {
                    Toggle("Voice cues in earbuds", isOn: $voiceCues)
                    Toggle("Haptics", isOn: $haptics)
                } header: {
                    Text("Feedback")
                }

                Section {
                    Link("Privacy Policy", destination: ProStore.privacyURL)
                    Link("Terms of Use", destination: ProStore.termsURL)
                } header: {
                    Text("About")
                } footer: {
                    Text("Neckline is a wellness tool, not a medical device, and doesn't diagnose or treat any condition. Stop if a movement hurts and talk to a clinician about persistent neck pain. Head motion is processed on your iPhone and never leaves it.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .manageSubscriptionsSheet(isPresented: $showManage)
        }
    }
}
