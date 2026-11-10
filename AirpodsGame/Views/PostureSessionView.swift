import Observation
import SwiftUI
import UIKit

/// Drives one posture session: samples the head pose ten times a second,
/// runs the slouch detector and accumulates stats.
@MainActor
@Observable
final class PostureSessionModel {
    private(set) var stats = SessionStats()
    private(set) var state: PostureState = .upright
    private(set) var elapsed: TimeInterval = 0
    private(set) var isFinished = false
    /// Head tracking dropped mid-session; time isn't counted until it's back.
    private(set) var isPaused = false

    let limit: TimeInterval?

    @ObservationIgnored private var detector: SlouchDetector
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastTick: TimeInterval?
    @ObservationIgnored private let motion: MotionManager

    init(motion: MotionManager, isPro: Bool,
         sensitivity: PostureSensitivity, nudgeDelay: NudgeDelay) {
        self.motion = motion
        self.limit = isPro ? nil : FreeTier.sessionLimit
        self.detector = SlouchDetector(threshold: sensitivity.threshold, grace: nudgeDelay.seconds)
    }

    var remaining: TimeInterval? { limit.map { max(0, $0 - elapsed) } }

    func start() {
        guard loop == nil else { return }
        motion.recenter()
        UIApplication.shared.isIdleTimerDisabled = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    func recenter() { motion.recenter() }

    private func tick() {
        guard !isFinished else { return }
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastTick = now }
        guard motion.status.isLive else {
            isPaused = true
            return
        }
        isPaused = false
        let dt = lastTick.map { now - $0 } ?? 0

        if detector.ingest(pitch: motion.pose.pitch, at: now) {
            stats.nudges += 1
            Feedback.shared.postureNudge()
        }
        state = detector.state
        stats.add(seconds: dt, state: state)
        elapsed = stats.trackedSeconds

        if let limit, elapsed >= limit { finish() }
    }

    /// Ends the session and saves it. Safe to call more than once.
    func finish() {
        guard !isFinished else { return }
        isFinished = true
        loop?.cancel()
        loop = nil
        UIApplication.shared.isIdleTimerDisabled = false
        ProgressStore.shared.addSession(stats)
    }
}

struct PostureSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.postureSensitivity) private var sensitivityRaw = PostureSensitivity.standard.rawValue
    @AppStorage(SettingsKey.nudgeDelay) private var nudgeDelayRaw = NudgeDelay.ten.rawValue

    @State private var motion = MotionManager.shared
    @State private var model: PostureSessionModel?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    if model.isFinished {
                        summary(model)
                    } else {
                        live(model)
                    }
                } else {
                    Color.clear
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        model?.finish()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard model == nil else { return }
            let m = PostureSessionModel(
                motion: motion,
                isPro: ProStore.shared.isPro,
                sensitivity: PostureSensitivity(rawValue: sensitivityRaw) ?? .standard,
                nudgeDelay: NudgeDelay(rawValue: nudgeDelayRaw) ?? .ten)
            model = m
            m.start()
        }
        .onDisappear { model?.finish() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func live(_ model: PostureSessionModel) -> some View {
        let tint = Theme.color(for: model.state)
        return VStack(spacing: 24) {
            Spacer()
            Text(headline(model))
                .font(.title.weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: model.state)

            HeadFigure(pose: motion.pose, tint: tint, size: 170)

            HStack(spacing: 32) {
                metric(Format.percent(model.stats.uprightFraction), String(localized: "upright"))
                metric(Format.clock(model.remaining ?? model.elapsed),
                       model.remaining == nil ? String(localized: "elapsed") : String(localized: "left"))
                metric("\(model.stats.nudges)", String(localized: "nudges"))
            }

            Spacer()

            Button {
                model.recenter()
            } label: {
                Label("Sit tall, then tap to recalibrate", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Button {
                model.finish()
            } label: {
                Text("End session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func summary(_ model: PostureSessionModel) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Ring(progress: model.stats.uprightFraction, lineWidth: 18)
                VStack {
                    Text(Format.percent(model.stats.uprightFraction))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("upright")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)

            Text(String(localized: "\(Format.clock(model.stats.trackedSeconds)) tracked · \(model.stats.nudges) nudges"))
                .foregroundStyle(.secondary)

            if model.limit != nil {
                VStack(spacing: 10) {
                    Text("Free sessions stop at 10 minutes. Pro runs as long as your workday.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Unlock unlimited sessions") { showPaywall = true }
                        .buttonStyle(.bordered)
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func headline(_ model: PostureSessionModel) -> String {
        if model.isPaused { return String(localized: "Waiting for earbuds…") }
        switch model.state {
        case .upright:   return String(localized: "Looking good")
        case .drifting:  return String(localized: "Head's dropping…")
        case .slouching: return String(localized: "Chin up")
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
