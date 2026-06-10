import SwiftUI

extension Color {
    /// Anthropic clay — the brand accent from the wireframes (#D97757).
    static let clay = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
}

/// Semantic escalation from the wireframe legend: clay < 70%, orange ≥ 70%,
/// red ≥ 90%. Color never carries meaning alone — the numeral stays prominent.
func usageColor(_ percent: Double) -> Color {
    if percent >= 90 { return .red }
    if percent >= 70 { return .orange }
    return .clay
}

/// The 12-ray sunburst app mark used across widget, popover, and sign-in.
struct SunburstMark: View {
    var size: CGFloat = 15

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let unit = canvasSize.width / 24
            for i in 0..<12 {
                let angle = Double(i) * 30 * .pi / 180
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(angle) * unit * 3.2,
                                      y: center.y + sin(angle) * unit * 3.2))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * unit * 9,
                                         y: center.y + sin(angle) * unit * 9))
                context.stroke(path, with: .color(.clay),
                               style: StrokeStyle(lineWidth: unit * 2.1, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Capsule progress bar on a quaternary track (6 pt, or 4 pt thin).
struct UsageBar: View {
    let percent: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if percent > 0 {
                    Capsule()
                        .fill(usageColor(percent))
                        .frame(width: max(height, geo.size.width * min(percent, 100) / 100))
                }
            }
        }
        .frame(height: height)
    }
}

/// Radial gauge with the percentage centered in rounded numerals.
struct UsageRing: View {
    let percent: Double
    let size: CGFloat
    let stroke: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: min(percent, 100) / 100)
                .stroke(usageColor(percent), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            (Text("\(Int(percent))")
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
             + Text("%")
                .font(.system(size: size * 0.15, weight: .semibold, design: .rounded)))
        }
        .padding(stroke / 2)
        .frame(width: size, height: size)
    }
}

/// Minimal top-corner age indicator: "4:28" counting up since the last fetch.
/// Goes orange with an alert icon when showing stale (cached) data.
struct AgeBadge: View {
    let since: Date
    var stale: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: stale ? "clock.badge.exclamationmark" : "clock")
                .font(.system(size: 8, weight: .semibold))
            Text(since, style: .timer)
        }
        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
        .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
    }
}
