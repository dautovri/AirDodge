import Foundation
import Observation

/// Per-day activity history, persisted as JSON in UserDefaults. Small by
/// design: one record per active day.
@MainActor
@Observable
final class ProgressStore {
    static let shared = ProgressStore()

    private static let recordsKey = "progress.records"
    private static let totalRoutinesKey = "progress.totalRoutines"
    private static let reviewVersionKey = "progress.reviewPromptVersion"

    private(set) var records: [String: DailyRecord] = [:]
    private(set) var totalRoutines = 0

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.recordsKey),
           let decoded = try? JSONDecoder().decode([String: DailyRecord].self, from: data) {
            records = decoded
        }
        totalRoutines = defaults.integer(forKey: Self.totalRoutinesKey)
    }

    var today: DailyRecord {
        let key = DayKey.of(Date())
        return records[key] ?? DailyRecord(day: key)
    }

    var streak: Int {
        Streak.current(activeDays: Set(records.values.filter(\.keepsStreak).map(\.day)), today: Date())
    }

    /// The last `days` calendar days, oldest first, including empty days.
    func recent(days: Int, calendar: Calendar = .current) -> [(date: Date, record: DailyRecord)] {
        let start = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset -> (date: Date, record: DailyRecord)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let key = DayKey.of(date, calendar: calendar)
            return (date, records[key] ?? DailyRecord(day: key))
        }
    }

    func addSession(_ stats: SessionStats) {
        guard stats.trackedSeconds > 0 else { return }
        update { record in
            record.sessionSeconds += stats.trackedSeconds
            record.uprightSeconds += stats.uprightSeconds
            record.nudges += stats.nudges
        }
    }

    /// Records a finished routine. Returns `true` when this is a good moment
    /// to ask for an App Store rating.
    func addRoutine() -> Bool {
        update { $0.routines += 1 }
        totalRoutines += 1
        defaults.set(totalRoutines, forKey: Self.totalRoutinesKey)
        let version = Bundle.main.shortVersion
        guard ReviewGate.shouldAsk(totalRoutines: totalRoutines,
                                   lastPromptVersion: defaults.string(forKey: Self.reviewVersionKey),
                                   appVersion: version) else { return false }
        defaults.set(version, forKey: Self.reviewVersionKey)
        return true
    }

    private func update(_ change: (inout DailyRecord) -> Void) {
        let key = DayKey.of(Date())
        var record = records[key] ?? DailyRecord(day: key)
        change(&record)
        records[key] = record
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.recordsKey)
        }
    }
}
