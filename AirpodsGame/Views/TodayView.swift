import SwiftUI

struct TodayView: View {
    @State private var motion = MotionManager.shared
    @State private var progress = ProgressStore.shared
    @State private var pro = ProStore.shared

    @State private var showSession = false
    @State private var activeRoutine: Routine?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MotionStatusChip(motion: motion)

                    hero

                    HStack(spacing: 12) {
                        StatTile(value: "\(progress.streak)",
                                 label: String(localized: "day streak"),
                                 symbol: "flame.fill")
                        StatTile(value: progress.today.sessionSeconds > 0
                                     ? Format.percent(progress.today.uprightFraction) : "—",
                                 label: String(localized: "upright today"),
                                 symbol: "figure.stand")
                        StatTile(value: "\(progress.today.routines)",
                                 label: String(localized: "routines today"),
                                 symbol: "checkmark.circle")
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if !motion.status.isLive {
                        setupCard
                    }

                    routineCard
                }
                .padding(20)
            }
            .navigationTitle("Today")
            .fullScreenCover(isPresented: $showSession) {
                PostureSessionView()
            }
            .fullScreenCover(item: $activeRoutine) { routine in
                RoutinePlayerView(routine: routine)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Posture session")
                .font(.title2.weight(.bold))
            Text("Keep Neckline open while you work. When your head drops toward the screen, a quiet voice in your earbuds reminds you to sit tall.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
            Button {
                showSession = true
            } label: {
                Label(pro.isPro ? String(localized: "Start session")
                                : String(localized: "Start 10-minute session"),
                      systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.accentFill)
            }
            .disabled(!motion.status.isLive)
            .opacity(motion.status.isLive ? 1 : 0.6)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 24))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connect your earbuds", systemImage: "headphones")
                .font(.headline)
            Text(motion.status.nextStep)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }

    private var routineCard: some View {
        let routine = Routine.deskReset
        return Button {
            activeRoutine = routine
        } label: {
            HStack(spacing: 14) {
                Image(systemName: routine.symbol)
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today's reset")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(routine.title)
                        .font(.headline)
                    Text(String(localized: "\(routine.estimatedMinutes) min · \(routine.subtitle)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}
