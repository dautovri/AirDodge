import SwiftUI

/// Looping animated demo of the controls: a glove swings in, the head slips
/// or ducks under it. Drawn in code (no footage), so it shows generic
/// over-ear headphones and is identical in every language.
struct DodgeDemoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One beat per move; the loop is three beats long.
    static let beat: Double = 2.0

    enum Move: CaseIterable {
        case slipRight, slipLeft, duck

        var caption: String {
            switch self {
            case .slipRight: return String(localized: "Tilt right to slip")
            case .slipLeft:  return String(localized: "Tilt left to slip")
            case .duck:      return String(localized: "Nod down to duck")
            }
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let t = reduceMotion
                ? Self.beat * 0.95   // static pose: mid-slip, glove passing
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.beat * 3)
            DemoFrame(time: t)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Animation: tilt your head left or right to slip punches, nod down to duck."))
    }
}

private struct DemoFrame: View {
    let time: Double

    private var move: DodgeDemoView.Move {
        DodgeDemoView.Move.allCases[min(2, Int(time / DodgeDemoView.beat))]
    }
    /// Position inside the current beat, 0..<1.
    private var u: Double { time.truncatingRemainder(dividingBy: DodgeDemoView.beat) / DodgeDemoView.beat }

    /// 0 = centered, 1 = fully dodged. Ease in before the glove arrives,
    /// hold while it passes, ease back out.
    private var dodge: Double {
        func smooth(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
        return smooth((u - 0.18) / 0.2) * (1 - smooth((u - 0.68) / 0.2))
    }

    /// Glove travel 0 (offscreen) → 1 (past the head), during the middle of the beat.
    private var glove: Double { min(max((u - 0.3) / 0.35, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let headSize = min(w, h) * 0.42
            let center = CGPoint(x: w / 2, y: h * 0.47)
            let head = headOffset(headSize)

            ZStack {
                // Ring floor + spotlight
                RadialGradient(colors: [Color.orange.opacity(0.25), .clear],
                               center: .center, startRadius: 4, endRadius: w * 0.5)

                HeadWithHeadphones(size: headSize)
                    .rotationEffect(.degrees(head.angle))
                    .position(x: center.x + head.dx, y: center.y + head.dy)

                Text(verbatim: "🥊")
                    .font(.system(size: headSize * 0.55))
                    .scaleEffect(x: move == .slipLeft ? 1 : -1) // the emoji punches leftward
                                        .position(glovePosition(w: w, h: h, center: center, headSize: headSize))
                    .opacity(glove > 0 && glove < 1 ? 1 : 0)

                VStack {
                    Spacer()
                    Text(move.caption.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 8)
                }
            }
        }
        .background(
            LinearGradient(colors: [Color(red: 0.16, green: 0.08, blue: 0.20),
                                    Color(red: 0.08, green: 0.05, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func headOffset(_ size: CGFloat) -> (dx: CGFloat, dy: CGFloat, angle: Double) {
        let d = CGFloat(dodge)
        switch move {
        case .slipRight: return (size * 0.30 * d, size * 0.05 * d, 20 * dodge)
        case .slipLeft:  return (-size * 0.30 * d, size * 0.05 * d, -20 * dodge)
        case .duck:      return (0, size * 0.42 * d, 0)
        }
    }

    /// The glove punches into where the head *was* and pulls back: out and in
    /// along a half sine, so it never travels through the dodged head.
    private func glovePosition(w: CGFloat, h: CGFloat, center: CGPoint, headSize: CGFloat) -> CGPoint {
        let reach = CGFloat(sin(Double.pi * glove))
        let fromLeft = -headSize * 0.4
        let fromRight = w + headSize * 0.4
        switch move {
        case .slipRight: // hook from the left
            return CGPoint(x: fromLeft + (center.x - fromLeft) * reach, y: center.y)
        case .slipLeft:  // hook from the right
            return CGPoint(x: fromRight - (fromRight - center.x) * reach, y: center.y)
        case .duck:      // swing in over the ducked head
            return CGPoint(x: fromLeft + (center.x - fromLeft) * reach, y: center.y - headSize * 0.1)
        }
    }
}

/// A simple face wearing generic over-ear headphones.
private struct HeadWithHeadphones: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.78, blue: 0.60),
                                              Color(red: 0.86, green: 0.60, blue: 0.44)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
            // Eyes + determined mouth
            HStack(spacing: size * 0.22) {
                Capsule().frame(width: size * 0.08, height: size * 0.12)
                Capsule().frame(width: size * 0.08, height: size * 0.12)
            }
            .foregroundStyle(Color(red: 0.2, green: 0.12, blue: 0.1))
            .offset(y: -size * 0.04)
            Capsule()
                .fill(Color(red: 0.45, green: 0.18, blue: 0.15))
                .frame(width: size * 0.22, height: size * 0.05)
                .offset(y: size * 0.2)
            // Headband
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(Color(white: 0.18), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .frame(width: size * 1.12, height: size * 1.12)
            // Ear cups
            HStack(spacing: size * 0.86) {
                RoundedRectangle(cornerRadius: size * 0.08)
                    .fill(Color(white: 0.14))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.08).stroke(Color.orange, lineWidth: 2))
                    .frame(width: size * 0.2, height: size * 0.36)
                RoundedRectangle(cornerRadius: size * 0.08)
                    .fill(Color(white: 0.14))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.08).stroke(Color.orange, lineWidth: 2))
                    .frame(width: size * 0.2, height: size * 0.36)
            }
        }
    }
}

#Preview {
    DodgeDemoView()
        .aspectRatio(16 / 9, contentMode: .fit)
        .padding()
        .background(.black)
}
