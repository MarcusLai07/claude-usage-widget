import SwiftUI
import Charts

/// Which stretch of history the curves cover.
enum TrendRange: String, CaseIterable {
    case cycle, twoDays, off

    var title: String {
        switch self {
        case .cycle: return "Cycle"
        case .twoDays: return "2 days"
        case .off: return "Off"
        }
    }
}

/// "Left over time" under the meters (Magpie's quota curve): what was left
/// of each window, a dashed even pace from full at the cycle's start to
/// empty at its reset, and now. A line above its dashes lasts the cycle.
struct LeftOverTimeView: View {
    let snapshot: UsageSnapshot
    @ObservedObject var trends: TrendModel

    @AppStorage("trendRange") private var range: TrendRange = .cycle
    @State private var picked: TrendCycle?
    @State private var enlarged = false

    init(snapshot: UsageSnapshot, trends: TrendModel, picked: TrendCycle? = nil) {
        self.snapshot = snapshot
        self.trends = trends
        _picked = State(initialValue: picked)
    }

    var body: some View {
        let now = Date()
        let lines = UsageTrends.kinds.compactMap { kind -> TrendLine? in
            guard snapshot.window(for: kind) != nil else { return nil }
            return trends.line(kind)
        }
        // Trends: Off (in the Allowances head) hides the curves entirely.
        if !lines.isEmpty && range != .off {
            VStack(alignment: .leading, spacing: 8) {
                head(forecast: picked == nil ? headForecast(lines, now: now) : nil)
                if let plot = plot(lines, now: now) {
                    chart(plot, now: now)
                    axisLabels(plot, now: now)
                    legend(plot)
                }
            }
        }
    }

    // MARK: Head and range menu

    /// The window whose reset is furthest off answers for the card, as in
    /// Magpie: the head says what the curve's shape only hints at.
    private func headForecast(_ lines: [TrendLine], now: Date) -> Forecast? {
        let longest = lines.max {
            (snapshot.window(for: $0.kind)?.resetsAt ?? .distantPast)
                < (snapshot.window(for: $1.kind)?.resetsAt ?? .distantPast)
        }
        guard let longest else { return nil }
        return trends.forecast(for: longest.kind, window: snapshot.window(for: longest.kind), now: now)
    }

    private func head(forecast: Forecast?) -> some View {
        HStack(spacing: 10) {
            Text("Left over time")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if let forecast {
                ForecastLine(forecast: forecast, font: .system(size: 11.5))
                    .lineLimit(1)
            }
            Spacer()
            // The range is the section head's Trends menu; here, in Cycle
            // range, a recorded past cycle can be picked instead.
            if range == .cycle {
                Menu {
                    Picker("Cycle", selection: selection) {
                        Text("Current cycle").tag(TrendRange.cycle.rawValue)
                    }
                    .pickerStyle(.inline)
                    if !trends.pastCycles.isEmpty {
                        Picker("Past cycles", selection: selection) {
                            ForEach(trends.pastCycles) { cycle in
                                Text(cycleLabel(cycle)).tag(pastTag(cycle))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    Text(picked.map(cycleLabel) ?? "Cycle")
                        .font(.system(size: 11.5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Choose a recorded cycle")
            } else {
                Text(range.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One selection for the range and the picked past cycle.
    private var selection: Binding<String> {
        Binding(
            get: { picked.map(pastTag) ?? range.rawValue },
            set: { value in
                if let cycle = trends.pastCycles.first(where: { pastTag($0) == value }) {
                    range = .cycle
                    picked = cycle
                } else {
                    picked = nil
                    range = TrendRange(rawValue: value) ?? .cycle
                }
            }
        )
    }

    private func pastTag(_ cycle: TrendCycle) -> String {
        "past:\(Int(cycle.start.timeIntervalSince1970))"
    }

    private func cycleLabel(_ cycle: TrendCycle) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(cycle.start.formatted(style)) – \(cycle.end.formatted(style))"
    }

    // MARK: Plot model

    private struct Even: Identifiable {
        let kind: MetricKind
        let start: Date
        let reset: Date
        var id: MetricKind { kind }
    }

    private struct Shown: Identifiable {
        let kind: MetricKind
        let left: Double
        var id: MetricKind { kind }
    }

    private struct Plot {
        let domain: ClosedRange<Date>
        let segments: [TrendSegment]
        let evens: [Even]
        let legend: [Shown]
        let isPast: Bool
    }

    private func plot(_ lines: [TrendLine], now: Date) -> Plot? {
        var cycles: [MetricKind: CurrentCycle] = [:]
        for line in lines {
            cycles[line.kind] = UsageTrends.currentCycle(of: line, window: snapshot.window(for: line.kind), now: now)
        }

        let domain: ClosedRange<Date>
        let isPast = range == .cycle && picked != nil
        if let picked, range == .cycle {
            domain = picked.start...max(picked.end, picked.start.addingTimeInterval(60))
        } else if range == .twoDays {
            domain = now.addingTimeInterval(-48 * 3600)...now
        } else {
            let start = cycles.values.map(\.start).min() ?? now.addingTimeInterval(-3600)
            let end = max(now, cycles.values.compactMap(\.reset).max() ?? now)
            domain = min(start, now.addingTimeInterval(-3600))...end
        }
        let length = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let step = max(length / 300, 60)

        var segments: [TrendSegment] = []
        var evens: [Even] = []
        var legend: [Shown] = []
        for line in lines {
            let cycle = cycles[line.kind]
            // A window far shorter than the span (5 hours in a week) shows
            // only its current cycle, without an even pace: its earlier
            // cycles would comb across the chart.
            let short = (line.kind.span ?? 0) < length / 12
            if short && isPast { continue }

            var source = line.segments
            if short, let cycle, let current = line.segments.last {
                source = [TrendSegment(kind: current.kind, index: current.index,
                                       points: current.points.filter { $0.at >= cycle.start })]
            }
            for segment in source {
                var points = segment.points
                // A refill read right at a past cycle's end is the next one's.
                if isPast, let picked { points = points.filter { $0.at < picked.end } }
                points = UsageTrends.visiblePoints(points, in: domain, step: step)
                if !points.isEmpty {
                    segments.append(TrendSegment(kind: segment.kind, index: segment.index, points: points))
                }
            }

            // Windows sharing a cycle (Weekly and Fable) share one even
            // pace; draw it once, in the first one's color.
            func addEven(_ start: Date, _ reset: Date) {
                let shared = evens.contains {
                    abs($0.start.timeIntervalSince(start)) <= UsageTrends.resetSlack
                        && abs($0.reset.timeIntervalSince(reset)) <= UsageTrends.resetSlack
                }
                if !shared { evens.append(Even(kind: line.kind, start: start, reset: reset)) }
            }

            if isPast, let picked {
                if line.kind.span == trends.cycleKind?.span {
                    addEven(picked.start, picked.end)
                }
                let last = line.points.last { $0.at >= picked.start && $0.at < picked.end }
                if let last { legend.append(Shown(kind: line.kind, left: last.left)) }
            } else {
                if !short, let cycle, let reset = cycle.reset {
                    addEven(cycle.start, reset)
                }
                let used = snapshot.window(for: line.kind)?.utilization ?? 0
                legend.append(Shown(kind: line.kind, left: max(0, 100 - used)))
            }
        }
        guard !segments.isEmpty else { return nil }
        return Plot(domain: domain, segments: segments, evens: evens, legend: legend, isPast: isPast)
    }

    // MARK: Chart

    private func chart(_ plot: Plot, now: Date) -> some View {
        Chart {
            ForEach(plot.evens) { even in
                LineMark(x: .value("Time", even.start), y: .value("Left", 100),
                         series: .value("Line", "even-\(even.kind.rawValue)"))
                    .foregroundStyle(even.kind.chartColor.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                LineMark(x: .value("Time", even.reset), y: .value("Left", 0),
                         series: .value("Line", "even-\(even.kind.rawValue)"))
                    .foregroundStyle(even.kind.chartColor.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(plot.segments) { segment in
                ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Time", point.at), y: .value("Left", point.left),
                             series: .value("Line", segment.id))
                        .foregroundStyle(segment.kind.chartColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                if segment.points.count == 1, let point = segment.points.first {
                    PointMark(x: .value("Time", point.at), y: .value("Left", point.left))
                        .foregroundStyle(segment.kind.chartColor)
                        .symbolSize(14)
                }
            }
            if !plot.isPast, plot.domain.contains(now) {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartXScale(domain: plot.domain)
        // Headroom, so a line at 100% or 0% isn't half clipped at the edge.
        .chartYScale(domain: -4...104)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%").font(.system(size: 9.5))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .frame(height: enlarged ? 220 : 92)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { enlarged.toggle() } }
        .help("Solid: what was left. Dashed: an even pace, full at the cycle's start to empty at its reset — a line above its dashes lasts the cycle. Click to \(enlarged ? "shrink" : "enlarge").")
        .accessibilityLabel("Left over time, \(picked.map(cycleLabel) ?? range.title)")
    }

    private func axisLabels(_ plot: Plot, now: Date) -> some View {
        HStack {
            Text(timeLabel(plot.domain.lowerBound, now: now, past: plot.isPast))
            Spacer()
            Text(timeLabel(plot.domain.upperBound, now: now, past: plot.isPast))
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
        .padding(.trailing, 30)
    }

    /// "Now", "14:58" today, else "Nov 10 18:00" — to the nearest minute, as
    /// reset times are shown (a cycle's start is its reset, read as 17:59:59.6,
    /// minus a week).
    private func timeLabel(_ exact: Date, now: Date, past: Bool) -> String {
        if !past, abs(exact.timeIntervalSince(now)) < 60 { return "Now" }
        let date = Date(timeIntervalSinceReferenceDate: (exact.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let time = date.formatted(.dateTime.hour().minute())
        if !past, Calendar.current.isDate(date, inSameDayAs: now) { return time }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) \(time)"
    }

    private func legend(_ plot: Plot) -> some View {
        HStack(spacing: 14) {
            ForEach(plot.legend) { item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(item.kind.chartColor)
                        .frame(width: 7, height: 7)
                    Text(item.kind.title)
                        .foregroundStyle(.secondary)
                    Text("\(Int(item.left.rounded()))%")
                        .fontWeight(.semibold)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }
}
