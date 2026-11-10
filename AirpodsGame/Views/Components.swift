import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 0.16, green: 0.72, blue: 0.64)
    static let warm = Color(red: 0.98, green: 0.62, blue: 0.29)
    static let alert = Color(red: 0.94, green: 0.36, blue: 0.36)

    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.36, blue: 0.42), Color(red: 0.16, green: 0.62, blue: 0.58)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func color(for state: PostureState) -> Color {
        switch state {
        case .upright:   return accent
        case .drifting:  return warm
        case .slouching: return alert
        }
    }
}

/// Tappable head-tracking status. Taps retry the stream, or open Settings
/// when Motion & Fitness is denied.
struct MotionStatusChip: View {
    let motion: MotionManager

    var body: some View {
        Button {
            if motion.status == .permissionDenied,
               let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            } else {
                motion.restart()
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(motion.status.isLive ? Theme.accent : Theme.warm)
                    .frame(width: 8, height: 8)
                Text(motion.status.label)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Retries head tracking"))
    }
}

/// A stylised head seen from the front, posed by the live head angles.
/// Roll tilts it, pitch shifts the face down/up, yaw shifts it sideways.
struct HeadFigure: View {
    var pose: HeadPose
    var tint: Color = Theme.accent
    var size: CGFloat = 180

    var body: some View {
        let faceShiftX = CGFloat(max(-45, min(45, pose.yaw))) / 45 * size * 0.18
        let faceShiftY = CGFloat(max(-40, min(40, -pose.pitch))) / 40 * size * 0.16

        ZStack {
            // Shoulders stay put — they're the reference the head moves against.
            Capsule()
                .fill(tint.opacity(0.18))
                .frame(width: size * 1.25, height: size * 0.34)
                .offset(y: size * 0.62)

            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                Circle()
                    .strokeBorder(tint, lineWidth: 4)
                // Face: eyes + nose move with pitch/yaw.
                Group {
                    HStack(spacing: size * 0.2) {
                        Capsule().frame(width: size * 0.07, height: size * 0.1)
                        Capsule().frame(width: size * 0.07, height: size * 0.1)
                    }
                    .offset(y: -size * 0.06)
                    Capsule()
                        .frame(width: size * 0.05, height: size * 0.12)
                        .offset(y: size * 0.08)
                }
                .foregroundStyle(tint)
                .offset(x: faceShiftX, y: faceShiftY)
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(pose.roll), anchor: .bottom)
        }
        .frame(width: size * 1.3, height: size * 1.5)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: pose)
        .accessibilityHidden(true)
    }
}

/// Circular progress ring.
struct Ring: View {
    var progress: Double
    var tint: Color = Theme.accent
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }
}

enum Format {
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func minutes(_ seconds: Double) -> String {
        String(localized: "\(Int((seconds / 60).rounded())) min")
    }
}
