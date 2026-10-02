import SwiftUI

// User-tunable game settings. Backed by UserDefaults via @AppStorage so the
// values survive across launches. Read from GameScene + ContentView.
//
// iOS 16 compatible (no @Observable). When the project bumps to iOS 17 (see
// TODOS.md), this can migrate to @Observable for cleaner ergonomics.

enum SettingsKey {
    static let motionSensitivity = "settings.motionSensitivity"   // 0..4 (0=lenient, 4=strict)
    static let soundEnabled      = "settings.soundEnabled"
    static let hapticsEnabled    = "settings.hapticsEnabled"
    static let scanlineEnabled   = "settings.scanlineEnabled"
}

enum MotionSensitivityLevel: Int, CaseIterable {
    case verylenient = 0   // ±20° roll, ±28° duck — easier dodges, less neck strain
    case lenient     = 1   // ±17°, ±25°
    case standard    = 2   // ±14°, ±22° — current defaults from GameScene
    case strict      = 3   // ±11°, ±19°
    case verystrict  = 4   // ±8°, ±16° — ESPORTS

    var rollThreshold: Double {
        switch self {
        case .verylenient: return 20.0
        case .lenient:     return 17.0
        case .standard:    return 14.0
        case .strict:      return 11.0
        case .verystrict:  return  8.0
        }
    }

    var duckThreshold: Double {
        switch self {
        case .verylenient: return 28.0
        case .lenient:     return 25.0
        case .standard:    return 22.0
        case .strict:      return 19.0
        case .verystrict:  return 16.0
        }
    }

    var label: String {
        switch self {
        case .verylenient: return "Very Lenient"
        case .lenient:     return "Lenient"
        case .standard:    return "Standard"
        case .strict:      return "Strict"
        case .verystrict:  return "Esports"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage(SettingsKey.motionSensitivity) private var sensitivityRaw: Int = MotionSensitivityLevel.standard.rawValue
    @AppStorage(SettingsKey.soundEnabled)      private var soundEnabled: Bool   = true
    @AppStorage(SettingsKey.hapticsEnabled)    private var hapticsEnabled: Bool = true
    @AppStorage(SettingsKey.scanlineEnabled)   private var scanlineEnabled: Bool = true

    @Environment(\.dismiss) private var dismiss

    var sensitivity: MotionSensitivityLevel {
        MotionSensitivityLevel(rawValue: sensitivityRaw) ?? .standard
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Motion Sensitivity")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(sensitivity.label)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(sensitivityRaw) },
                                set: { sensitivityRaw = Int($0.rounded()) }
                            ),
                            in: 0...Double(MotionSensitivityLevel.allCases.count - 1),
                            step: 1
                        )
                        Text("Lower = larger head movements needed (gentler on the neck). Higher = smaller movements register (faster reactions, more strain).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Earbud Motion")
                }

                Section {
                    Toggle("Sound effects", isOn: $soundEnabled)
                    Toggle("Haptics", isOn: $hapticsEnabled)
                    Toggle("CRT scanline overlay", isOn: $scanlineEnabled)
                } header: {
                    Text("Feedback")
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await UnlockStore.shared.restore() }
                    }
                } header: {
                    Text("Full Fight Card")
                }

                Section {
                    Button {
                        UIApplication.shared.open(UnlockStore.privacyURL)
                    } label: {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink("Credits") {
                        CreditsView()
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("AirBoxer — head-tracking boxing dodge for iPhone with motion earbuds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            // The game is a dark, neon menu; a bright system sheet on top of it
            // broke visual continuity hard. Pin the sheet to dark.
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }
}

private struct CreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AirBoxer")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                Text("A head-tracking boxing dodge game.")
                    .font(.body)

                Divider().padding(.vertical, 4)

                Text("How to play")
                    .font(.headline)
                Text("Pair compatible motion earbuds and put them on. Tilt your head LEFT or RIGHT to slip hooks. NOD DOWN to duck uppercuts. Don't move into a punch — the opponent telegraphs every swing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider().padding(.vertical, 4)

                Text("Inspired by")
                    .font(.headline)
                Text("The 1987 8-bit boxing arcades. All characters are original.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider().padding(.vertical, 4)

                Text("Built with")
                    .font(.headline)
                Text("SwiftUI · SpriteKit · CoreMotion · GameKit · Apple's Icon Composer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}
