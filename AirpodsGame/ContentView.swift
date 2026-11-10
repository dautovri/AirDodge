import SwiftUI

struct ContentView: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Today", systemImage: "figure.stand") {
                TodayView()
            }
            Tab("Routines", systemImage: "list.bullet.rectangle") {
                RoutinesView()
            }
            Tab("Progress", systemImage: "chart.bar.xaxis") {
                StatsView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(Theme.accent)
        .onAppear { MotionManager.shared.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { MotionManager.shared.start() }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView { onboarded = true }
        }
    }
}
