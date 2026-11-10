import Observation
import StoreKit
import SwiftUI
import UIKit

/// Plays a routine step by step. With live head tracking every rep is
/// verified by `HoldTracker`; otherwise it runs in guided (timer) mode,
/// feeding the same tracker synthetic progress.
@MainActor
@Observable
final class RoutinePlayerModel {
    let routine: Routine
    let guided: Bool
    let rangeScale: Double

    private(set) var stepIndex = 0
    private(set) var tracker: HoldTracker
    private(set) var progress: Double = 0
    private(set) var isFinished = false
    private(set) var shouldAskForReview = false

    @ObservationIgnored private let motion: MotionManager
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var stepStartedAt: TimeInterval = 0

    init(routine: Routine, motion: MotionManager, rangeScale: Double) {
        self.routine = routine
        self.motion = motion
        self.rangeScale = rangeScale
        self.guided = !motion.status.isLive
        let first = routine.steps[0]
        self.tracker = HoldTracker(reps: first.reps, holdSeconds: first.hold)
    }

    var step: RoutineStep { routine.steps[stepIndex] }
    var stepCount: Int { routine.steps.count }

    /// 0...1 across the whole routine.
    var overallProgress: Double {
        let total = routine.steps.reduce(0) { $0 + $1.reps }
        let done = routine.steps.prefix(stepIndex).reduce(0) { $0 + $1.reps } + tracker.completedReps
        return total > 0 ? Double(done) / Double(total) : 0
    }

    var instruction: String {
        switch tracker.phase {
        case .reach:   return guided ? step.movement.cue : String(localized: "Move into the stretch")
        case .hold:    return String(localized: "Hold it. Breathe out slowly.")
        case .release: return String(localized: "Come back to center")
        case .done:    return String(localized: "Nice")
        }
    }

    func start() {
        guard loop == nil else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        beginStep()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                self?.tick()
            }
        }
    }

    func skipStep() { advance() }

    func stop() {
        loop?.cancel()
        loop = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func beginStep() {
        tracker = HoldTracker(reps: step.reps, holdSeconds: step.hold)
        stepStartedAt = ProcessInfo.processInfo.systemUptime
        if !guided { motion.recenter() }
        Feedback.shared.stepStarted(step.movement)
    }

    private func tick() {
        guard !isFinished else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if guided {
            progress = GuidedPace.progress(elapsed: now - stepStartedAt, hold: step.hold)
        } else {
            progress = step.movement.progress(motion.pose, rangeScale: rangeScale)
        }
        if tracker.ingest(progress: progress, at: now) {
            Feedback.shared.repComplete()
        }
        if tracker.isDone { advance() }
    }

    private func advance() {
        if stepIndex + 1 < routine.steps.count {
            stepIndex += 1
            beginStep()
        } else {
            finish()
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        stop()
        Feedback.shared.routineFinished()
        shouldAskForReview = ProgressStore.shared.addRoutine()
    }
}

struct RoutinePlayerView: View {
    let routine: Routine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @AppStorage(SettingsKey.stretchRange) private var rangeRaw = StretchRange.normal.rawValue

    @State private var motion = MotionManager.shared
    @State private var model: RoutinePlayerModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    if model.isFinished { finished(model) } else { player(model) }
                } else {
                    Color.clear
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(routine.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        model?.stop()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard model == nil else { return }
            let m = RoutinePlayerModel(routine: routine, motion: motion,
                                       rangeScale: (StretchRange(rawValue: rangeRaw) ?? .normal).scale)
            model = m
            m.start()
        }
        .onDisappear { model?.stop() }
    }

    private func player(_ model: RoutinePlayerModel) -> some View {
        VStack(spacing: 20) {
            ProgressView(value: model.overallProgress)
                .tint(Theme.accent)

            HStack {
                Text(String(localized: "Step \(model.stepIndex + 1) of \(model.stepCount)"))
                Spacer()
                if model.guided {
                    Label("Guided mode", systemImage: "timer")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(model.step.movement.title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            ZStack {
                Ring(progress: model.tracker.phase == .hold ? model.tracker.holdFraction : min(1, model.progress),
                     tint: model.tracker.phase == .hold ? Theme.accent : Theme.warm,
                     lineWidth: 12)
                    .frame(width: 250, height: 250)
                if model.guided {
                    Image(systemName: "figure.mind.and.body")
                        .font(.system(size: 80))
                        .foregroundStyle(Theme.accent)
                } else {
                    HeadFigure(pose: motion.pose, size: 130)
                }
            }

            Text(model.instruction)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(minHeight: 50)

            HStack(spacing: 8) {
                ForEach(0..<model.tracker.reps, id: \.self) { i in
                    Circle()
                        .fill(i < model.tracker.completedReps ? Theme.accent : Color.secondary.opacity(0.25))
                        .frame(width: 12, height: 12)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(model.tracker.completedReps) of \(model.tracker.reps) reps"))

            Spacer(minLength: 0)

            Button("Skip this stretch") { model.skipStep() }
                .buttonStyle(.bordered)
        }
    }

    private func finished(_ model: RoutinePlayerModel) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 90))
                .foregroundStyle(Theme.accent)
            Text("Routine complete")
                .font(.largeTitle.weight(.bold))
            Text(String(localized: "Streak: \(ProgressStore.shared.streak) days"))
                .font(.title3)
                .foregroundStyle(.secondary)
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
        .task {
            if model.shouldAskForReview {
                try? await Task.sleep(for: .seconds(1))
                requestReview()
            }
        }
    }
}
