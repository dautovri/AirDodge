import SwiftUI

struct RoutinesView: View {
    @State private var pro = ProStore.shared
    @State private var activeRoutine: Routine?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Routine.catalog) { routine in
                        Button {
                            if FreeTier.canStart(routine, isPro: pro.isPro) {
                                activeRoutine = routine
                            } else {
                                showPaywall = true
                            }
                        } label: {
                            row(routine)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("With earbuds, every rep is checked against your real head movement. Without them, routines run in guided mode with on-screen timing.")
                }
            }
            .navigationTitle("Routines")
            .fullScreenCover(item: $activeRoutine) { routine in
                RoutinePlayerView(routine: routine)
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private func row(_ routine: Routine) -> some View {
        let locked = !FreeTier.canStart(routine, isPro: pro.isPro)
        return HStack(spacing: 14) {
            Image(systemName: routine.symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                    .font(.headline)
                Text(String(localized: "\(routine.estimatedMinutes) min · \(routine.subtitle)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if locked {
                Label("Pro", systemImage: "lock.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.warm.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.warm)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
