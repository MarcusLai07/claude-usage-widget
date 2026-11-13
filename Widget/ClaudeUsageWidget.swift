import WidgetKit
import SwiftUI
import Charts

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let visibleMetrics: [MetricKind]
    let signedIn: Bool
    let isStale: Bool
    var showLeft = AppGroupStore.showLeft
    /// "Max 5x", from the app's profile read.
    var plan: String? = AppGroupStore.accountProfile?.plan
    /// The week's left-over-time curve, for the large widget only.
    var trend: WidgetTrend? = nil

    /// Pace is measured at the entry's date, so later entries of one
    /// timeline move it along without a new fetch.
    var displays: [MetricDisplay] {
        guard let snapshot else { return [] }
        return MetricPresentation.displays(for: snapshot, kinds: visibleMetrics,
                                           showLeft: showLeft, now: date)
    }
}

/// What was left of each weekly window this cycle (the app's "Left over
/// time"), read from the shared usage history, and the run-out forecast.
struct WidgetTrend {
    struct Line: Identifiable {
        let kind: MetricKind
        let points: [TrendPoint]
        var id: MetricKind { kind }
    }

    let start: Date
    let reset: Date
    let lines: [Line]
    let forecast: Forecast?

    static func make(snapshot: UsageSnapshot, now: Date) -> WidgetTrend? {
        guard let reset = snapshot.weekly?.resetsAt, reset > now,
              let span = MetricKind.weekly.span else { return nil }
        let start = reset.addingTimeInterval(-span)
        let history = UsageTrends.lines(from: UsageHistory.load(since: start.addingTimeInterval(-3600)))
        var lines: [Line] = []
        for kind in [MetricKind.weekly, .weeklyFable, .weeklyOpus, .weeklySonnet]
        where snapshot.window(for: kind) != nil {
            guard let line = history.first(where: { $0.kind == kind }) else { continue }
            let points = UsageTrends.visiblePoints(line.points.filter { $0.at >= start },
                                                   in: start...reset, step: span / 120)
            if !points.isEmpty { lines.append(Line(kind: kind, points: points)) }
        }
        guard !lines.isEmpty else { return nil }
        let weekly = history.first { $0.kind == .weekly }
        let forecast = weekly.flatMap {
            UsageTrends.forecast(points: $0.points.filter { $0.at >= start },
                                 cycle: CurrentCycle(start: start, reset: reset), now: now)
        }
        return WidgetTrend(start: start, reset: reset, lines: lines, forecast: forecast)
    }
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder,
                   visibleMetrics: [.session, .weekly], signedIn: true, isStale: false,
                   showLeft: false, plan: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = AppGroupStore.cachedSnapshot ?? .placeholder
        completion(UsageEntry(date: Date(), snapshot: snapshot,
                              visibleMetrics: AppGroupStore.visibleMetrics,
                              signedIn: true, isStale: false,
                              trend: context.family == .systemLarge
                                ? WidgetTrend.make(snapshot: snapshot, now: Date()) : nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            var snapshot: UsageSnapshot?
            var signedIn = true
            var stale = false
            let started = Date()
            do {
                // Long freshness window: the app refreshes every 5 minutes and
                // reloads widget timelines after each fetch, so the widget only
                // goes to the network itself if the app hasn't run in a while.
                snapshot = try await UsageFetcher.shared.fetch(maxAge: 10 * 60)
                AppGroupStore.cachedSnapshot = snapshot
                PerfLog.record(source: "widget", started: started, error: nil)
            } catch UsageAPIError.notSignedIn {
                signedIn = false
            } catch {
                snapshot = AppGroupStore.cachedSnapshot
                stale = true
                PerfLog.record(source: "widget", started: started, error: error.localizedDescription)
            }
            // One entry per 5 minutes until the next reload: the session's
            // pace moves about 1.7 points in that time.
            let now = Date()
            let visible = AppGroupStore.visibleMetrics
            let trend = context.family == .systemLarge
                ? snapshot.flatMap { WidgetTrend.make(snapshot: $0, now: now) } : nil
            let entries = stride(from: 0, to: 15, by: 5).map { minutes in
                UsageEntry(date: now.addingTimeInterval(TimeInterval(minutes * 60)),
                           snapshot: snapshot, visibleMetrics: visible,
                           signedIn: signedIn, isStale: stale, trend: trend)
            }
            let refresh = now.addingTimeInterval(15 * 60)
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }
}

extension UsageSnapshot {
    static var placeholder: UsageSnapshot {
        UsageSnapshot(
            fetchedAt: Date(),
            session: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(3 * 3600)),
            weekly: UsageWindow(utilization: 17, resetsAt: Date().addingTimeInterval(4 * 86400)),
            weeklyOpus: nil,
            weeklySonnet: nil,
            extra: nil
        )
    }
}

// MARK: - Shared pieces

struct SignedOutWidgetView: View {
    var body: some View {
        VStack(spacing: 9) {
            SunburstMark(size: 22)
            Text("Sign in to see your limits")
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Open Claude Usage")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }
}

/// The whole widget opens the app via widgetURL; the logo is additionally an
/// explicit tap target for the same deep link.
let openWindowURL = URL(string: "claudeusage://open")!

/// The mark, "Claude" and the plan; the data's age on the right.
struct WidgetHeader: View {
    let entry: UsageEntry
    var showAge = true

    var body: some View {
        HStack(spacing: 6) {
            Link(destination: openWindowURL) {
                HStack(spacing: 6) {
                    SunburstMark(size: 14)
                    Text("Claude")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            }
            if let plan = entry.plan {
                Text(plan)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showAge, let fetchedAt = entry.snapshot?.fetchedAt {
                AgeBadge(since: fetchedAt, stale: entry.isStale)
            }
        }
    }
}

/// A small-caps label, as the app heads its sections.
struct WidgetLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.7)
            .foregroundStyle(.secondary)
    }
}

struct WidgetFooter: View {
    let entry: UsageEntry

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: entry.isStale ? "clock.badge.exclamationmark" : "arrow.clockwise")
                .font(.system(size: 9, weight: .medium))
            if let fetchedAt = entry.snapshot?.fetchedAt {
                entry.isStale
                    ? Text("Last updated ") + Text(fetchedAt, style: .relative) + Text(" ago")
                    : Text("Updated ") + Text(fetchedAt, style: .relative) + Text(" ago")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.tertiary)
    }
}

/// "Left over time" for the week: each weekly window's line, the dashed even
/// pace from full to empty, now, and the forecast (the app's chart, small).
struct WidgetTrendView: View {
    let trend: WidgetTrend
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WidgetLabel("Left over time")
                Spacer(minLength: 4)
                if let forecast = trend.forecast {
                    ForecastLine(forecast: forecast, font: .system(size: 10))
                        .lineLimit(1)
                }
            }
            Chart {
                LineMark(x: .value("Time", trend.start), y: .value("Left", 100), series: .value("Line", "even"))
                    .foregroundStyle(MetricKind.weekly.chartColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                LineMark(x: .value("Time", trend.reset), y: .value("Left", 0), series: .value("Line", "even"))
                    .foregroundStyle(MetricKind.weekly.chartColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(trend.lines) { line in
                    ForEach(Array(line.points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Time", point.at), y: .value("Left", point.left),
                                 series: .value("Line", line.kind.rawValue))
                            .foregroundStyle(line.kind.chartColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                }
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            .chartXScale(domain: trend.start...trend.reset)
            .chartYScale(domain: -4...104)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                }
            }
            .chartPlotStyle { $0.clipped() }
            .frame(height: 54)
            HStack(spacing: 10) {
                ForEach(trend.lines) { line in
                    HStack(spacing: 4) {
                        Circle().fill(line.kind.chartColor).frame(width: 6, height: 6)
                        Text(line.kind == .weekly ? "Weekly" : line.kind.title)
                            .foregroundStyle(.secondary)
                        Text("\(Int(max(0, 100 - (snapshot.window(for: line.kind)?.utilization ?? 0))))%")
                            .fontWeight(.semibold)
                    }
                }
                Spacer(minLength: 0)
                Text(trend.reset.formatted(.dateTime.weekday(.abbreviated)))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10))
        }
    }
}

// MARK: - Direction B · Numeric + bar

struct BarsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if !entry.signedIn {
                SignedOutWidgetView()
            } else if entry.displays.isEmpty {
                Text("No usage data yet").font(.caption).foregroundStyle(.secondary)
            } else {
                switch family {
                case .systemSmall: small
                case .systemMedium: medium
                default: large
                }
            }
        }
        .widgetURL(openWindowURL)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var small: some View {
        let metrics = entry.displays
        let hero = metrics[0]
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetLabel(hero.name)
                Spacer()
                if let fetchedAt = entry.snapshot?.fetchedAt {
                    AgeBadge(since: fetchedAt, stale: entry.isStale)
                }
            }
            (Text("\(Int(hero.shownPercent))")
                .font(.system(size: 40, weight: .medium).monospacedDigit())
                .foregroundStyle(hero.percent >= 70 ? hero.color : Color.primary)
             + Text("%")
                .font(.system(size: 20, weight: .medium))
             + Text(hero.unitText.map { " \($0)" } ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 4)
                .padding(.bottom, 6)
            UsageBar(percent: hero.shownPercent, height: 5,
                     tint: hero.kind.meterColor(percentUsed: hero.percent))
                .opacity(entry.isStale ? 0.62 : 1)
            // No room for pace in the small widget; medium and large show it.
            let heroCaption = MetricCaption(metric: hero, font: .system(size: 10.5), pace: .hidden)
            if heroCaption.hasContent {
                heroCaption.padding(.top, 6)
            }
            Spacer(minLength: 4)
            if metrics.count > 1 {
                let second = metrics[1]
                HStack {
                    Text(second.name)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(second.valueWithUnit)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.system(size: 11))
                .padding(.bottom, 5)
                UsageBar(percent: second.shownPercent, height: 4,
                         tint: second.kind.meterColor(percentUsed: second.percent))
                    .opacity(entry.isStale ? 0.62 : 1)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(entry: entry)
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entry.displays.prefix(3)) { metric in
                    MetricBarRow(metric: metric)
                }
            }
            .opacity(entry.isStale ? 0.8 : 1)
            Spacer(minLength: 2)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(entry: entry, showAge: false)
            VStack(alignment: .leading, spacing: 12) {
                // With the curve below, three rows; without it, up to five.
                ForEach(entry.displays.prefix(entry.trend == nil ? 5 : 3)) { metric in
                    MetricBarRow(metric: metric)
                }
            }
            .opacity(entry.isStale ? 0.8 : 1)
            .padding(.top, 12)
            Spacer(minLength: 8)
            if let trend = entry.trend, let snapshot = entry.snapshot {
                WidgetTrendView(trend: trend, snapshot: snapshot, now: entry.date)
                    .opacity(entry.isStale ? 0.8 : 1)
                Spacer(minLength: 6)
            }
            WidgetFooter(entry: entry)
        }
    }
}

// MARK: - Direction A · Radial ring

struct RingsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if !entry.signedIn {
                SignedOutWidgetView()
            } else if entry.displays.isEmpty {
                Text("No usage data yet").font(.caption).foregroundStyle(.secondary)
            } else {
                switch family {
                case .systemSmall: small
                case .systemMedium: medium
                default: large
                }
            }
        }
        .widgetURL(openWindowURL)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var small: some View {
        let metrics = entry.displays
        let hero = metrics[0]
        return VStack(spacing: 0) {
            HStack {
                Link(destination: openWindowURL) {
                    SunburstMark(size: 14)
                }
                Spacer()
                if let fetchedAt = entry.snapshot?.fetchedAt {
                    AgeBadge(since: fetchedAt, stale: entry.isStale)
                }
            }
            Spacer(minLength: 2)
            UsageRing(metric: hero, size: 78, stroke: 8)
                .opacity(entry.isStale ? 0.75 : 1)
            VStack(spacing: 1) {
                Text(hero.name)
                    .font(.system(size: 12, weight: .semibold))
                MetricCaption(metric: hero, font: .system(size: 10.5), pace: .hidden)
            }
            .padding(.top, 7)
            Spacer(minLength: 2)
            if metrics.count > 1 {
                let second = metrics[1]
                HStack(spacing: 6) {
                    Circle()
                        .fill(second.kind.meterColor(percentUsed: second.percent))
                        .frame(width: 7, height: 7)
                    Text("\(second.name) \(second.valueWithUnit)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var medium: some View {
        VStack(spacing: 0) {
            WidgetHeader(entry: entry)
            Spacer(minLength: 5)
            HStack(alignment: .top, spacing: 0) {
                ForEach(entry.displays.prefix(3)) { metric in
                    VStack(spacing: 5) {
                        UsageRing(metric: metric, size: 62, stroke: 6)
                            .opacity(entry.isStale ? 0.75 : 1)
                        Text(metric.name)
                            .font(.system(size: 11.5, weight: .semibold))
                        MetricCaption(metric: metric, font: .system(size: 9.5),
                                      pace: .below, alignment: .center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 3)
        }
    }

    private var large: some View {
        let metrics = entry.displays
        let hero = metrics[0]
        return VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(entry: entry, showAge: false)
            HStack(spacing: 14) {
                UsageRing(metric: hero, size: 96, stroke: 9)
                    .opacity(entry.isStale ? 0.75 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hero.name)
                        .font(.system(size: 14, weight: .semibold))
                    MetricCaption(metric: hero, font: .system(size: 11.5))
                    if hero.kind == .session {
                        Text("5-hour window")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 12)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(metrics.dropFirst().prefix(4)) { metric in
                    MetricBarRow(metric: metric, showCaption: false)
                }
            }
            .opacity(entry.isStale ? 0.8 : 1)
            .padding(.top, 12)
            Spacer(minLength: 6)
            WidgetFooter(entry: entry)
        }
    }
}

// MARK: - Widget declarations

#if !SHOTS  // The screenshot tool (Shots/) has an entry point of its own.
@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageBarsWidget()
        ClaudeUsageRingsWidget()
    }
}
#endif

struct ClaudeUsageBarsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageBars", provider: UsageProvider()) { entry in
            BarsWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage — Bars")
        .description("Your limits as bars with reset times and pace; the large size adds the week's left-over-time curve.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ClaudeUsageRingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageRings", provider: UsageProvider()) { entry in
            RingsWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage — Rings")
        .description("Your limits as rings in each window's color, with reset times.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
