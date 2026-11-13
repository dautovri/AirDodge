import Charts
import SwiftUI

struct StatsView: View {
    @State private var progress = ProgressStore.shared
    @State private var pro = ProStore.shared
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        StatTile(value: "\(progress.streak)",
                                 label: String(localized: "day streak"),
                                 symbol: "flame.fill")
                        StatTile(value: "\(progress.totalRoutines)",
                                 label: String(localized: "routines done"),
                                 symbol: "checkmark.circle")
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    chartCard(title: String(localized: "Upright time, last 14 days")) {
                        Chart(progress.recent(days: 14), id: \.record.day) { item in
                            BarMark(x: .value("Day", item.date, unit: .day),
                                    y: .value("Minutes", item.record.uprightSeconds / 60))
                                .foregroundStyle(Theme.accent)
                                .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 3)) {
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            }
                        }
                    }

                    chartCard(title: String(localized: "Posture score, last 14 days")) {
                        Chart(progress.recent(days: 14).filter { $0.record.sessionSeconds > 0 },
                              id: \.record.day) { item in
                            LineMark(x: .value("Day", item.date, unit: .day),
                                     y: .value("Upright", item.record.uprightFraction * 100))
                                .foregroundStyle(Theme.accent)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Day", item.date, unit: .day),
                                      y: .value("Upright", item.record.uprightFraction * 100))
                                .foregroundStyle(Theme.accent)
                        }
                        .chartYScale(domain: 0...100)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Progress")
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    /// Charts are Pro. Free users see the shape of their data blurred behind
    /// an upgrade button — the free tracking keeps filling it in.
    /// No posture session in the chart window: both charts would be blank.
    private var hasRecentSessions: Bool {
        progress.recent(days: 14).contains { $0.record.sessionSeconds > 0 }
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ZStack {
                content()
                    .frame(height: 180)
                    .blur(radius: pro.isPro ? 0 : 6)
                    .allowsHitTesting(pro.isPro)
                if !pro.isPro {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("See your trends with Pro", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentFill)
                } else if !hasRecentSessions {
                    VStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        Text("No sessions yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Run a posture session and your trend shows up here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }
}
