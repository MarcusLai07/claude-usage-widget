import SwiftUI

extension Color {
    /// Anthropic clay — the brand accent from the wireframes (#D97757).
    static let clay = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)

    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkHex : lightHex
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }

    /// Track behind bars and pills.
    static let track = Color.primary.opacity(0.08)
    /// The data accent (Magpie's periwinkle): first series, bars, heatmaps.
    static let dataAccent = Color(lightHex: 0x5B67E8, darkHex: 0x9AA5FF)
    static let chartSky = Color(lightHex: 0x1E8FD6, darkHex: 0x6CC6FF)
    static let chartTeal = Color(lightHex: 0x12A38F, darkHex: 0x4FD6BF)
    static let chartAmber = Color(lightHex: 0xD18A00, darkHex: 0xF5C04A)
    static let chartPink = Color(lightHex: 0xD6488E, darkHex: 0xF27FB8)
    static let chartViolet = Color(lightHex: 0x8A4FD8, darkHex: 0xC09BFF)
    static let chartGreen = Color(lightHex: 0x2E9E4F, darkHex: 0x6FD98C)
    /// Kept for older call sites: the first series.
    static let chartIndigo = dataAccent
    /// Cost figures, as Magpie shows them.
    static let costGreen = Color(lightHex: 0x1E9E5A, darkHex: 0x4CC38A)
}

extension MetricKind {
    /// Each window's series color, in the app, the popover and the widgets.
    var chartColor: Color {
        switch self {
        case .session: return .dataAccent
        case .weekly: return .chartSky
        case .weeklyFable: return .chartTeal
        case .weeklyOpus: return .chartViolet
        case .weeklySonnet: return .chartGreen
        case .extraUsage: return .chartAmber
        }
    }

    /// A limit's bar: its series color until it nears the limit, then the
    /// escalation colors (orange from 70%, red from 90%).
    func meterColor(percentUsed: Double) -> Color {
        percentUsed >= 70 ? usageColor(percentUsed) : chartColor
    }
}

/// "Runs out Sat 14:00 at this pace" (orange) or "Lasts past the reset at
/// this pace", from the window's readings this cycle.
struct ForecastLine: View {
    let forecast: Forecast
    var font: Font = .system(size: 11.5)

    var body: some View {
        switch forecast {
        case .runsOut(let date):
            Text("Runs out \(timeText(date)) at this pace")
                .font(font)
                .foregroundStyle(.orange)
        case .lastsPastReset:
            Text("Lasts past the reset at this pace")
                .font(font)
                .foregroundStyle(.secondary)
        }
    }

    private func timeText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
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
    var color: Color = .clay

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
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: unit * 2.1, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Capsule progress bar on a quaternary track (6 pt, or 4 pt thin). `tint`
/// overrides the escalation color of `percent`, for Left mode, where the
/// fill is what's left but the color still follows what's used.
struct UsageBar: View {
    let percent: Double
    var height: CGFloat = 6
    var tint: Color? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.track)
                if percent > 0 {
                    Capsule()
                        .fill(tint ?? usageColor(percent))
                        .frame(width: max(height, geo.size.width * min(percent, 100) / 100))
                }
            }
        }
        .frame(height: height)
    }
}

/// Radial gauge with the percentage centered in rounded numerals. `tint`
/// overrides the escalation color (see `UsageBar`); `label` ("left") sits
/// under the number.
struct UsageRing: View {
    let percent: Double
    let size: CGFloat
    let stroke: CGFloat
    var tint: Color? = nil
    var label: String? = nil

    init(percent: Double, size: CGFloat, stroke: CGFloat,
         tint: Color? = nil, label: String? = nil) {
        self.percent = percent
        self.size = size
        self.stroke = stroke
        self.tint = tint
        self.label = label
    }

    /// The metric's shown figure in its window's series color (orange, then
    /// red, near the limit), labelled "left" in Left mode.
    init(metric: MetricDisplay, size: CGFloat, stroke: CGFloat) {
        self.init(percent: metric.shownPercent, size: size, stroke: stroke,
                  tint: metric.kind.meterColor(percentUsed: metric.percent),
                  label: metric.showLeft ? "left" : nil)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.track, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: min(percent, 100) / 100)
                .stroke(tint ?? usageColor(percent), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                (Text("\(Int(percent.rounded(.down)))")
                    .font(.system(size: size * 0.27, weight: .semibold).monospacedDigit())
                 + Text("%")
                    .font(.system(size: size * 0.15, weight: .medium)))
                if let label {
                    Text(label)
                        .font(.system(size: max(8, size * 0.11), weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
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
