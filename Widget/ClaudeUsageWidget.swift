import WidgetKit
import SwiftUI

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let visibleMetrics: [MetricKind]
    let signedIn: Bool
    let isStale: Bool

    var displays: [MetricDisplay] {
        guard let snapshot else { return [] }
        return MetricPresentation.displays(for: snapshot, kinds: visibleMetrics)
    }
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder,
                   visibleMetrics: [.session, .weekly], signedIn: true, isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(),
                              snapshot: AppGroupStore.cachedSnapshot ?? .placeholder,
                              visibleMetrics: AppGroupStore.visibleMetrics,
                              signedIn: true, isStale: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            var snapshot: UsageSnapshot?
            var signedIn = true
            var stale = false
            let started = Date()
            do {
                snapshot = try await UsageAPI.fetchUsage()
                AppGroupStore.cachedSnapshot = snapshot
                PerfLog.record(source: "widget", started: started, error: nil)
            } catch UsageAPIError.notSignedIn {
                signedIn = false
            } catch {
                snapshot = AppGroupStore.cachedSnapshot
                stale = true
                PerfLog.record(source: "widget", started: started, error: error.localizedDescription)
            }
            let entry = UsageEntry(date: Date(), snapshot: snapshot,
                                   visibleMetrics: AppGroupStore.visibleMetrics,
                                   signedIn: signedIn, isStale: stale)
            let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(refresh)))
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
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Sign in to see your limits")
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Open Claude Usage")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }
}

struct WidgetHeader: View {
    let entry: UsageEntry
    var markSize: CGFloat = 15
    var showAge = true

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                SunburstMark(size: markSize)
                Text("Claude Usage")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            Spacer()
            if showAge, let fetchedAt = entry.snapshot?.fetchedAt {
                AgeBadge(since: fetchedAt, stale: entry.isStale)
            }
        }
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
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.tertiary)
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
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var small: some View {
        let metrics = entry.displays
        let hero = metrics[0]
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(hero.name.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(.secondary)
                Spacer()
                if let fetchedAt = entry.snapshot?.fetchedAt {
                    AgeBadge(since: fetchedAt, stale: entry.isStale)
                }
            }
            (Text("\(Int(hero.percent))")
                .font(.system(size: 44, weight: .bold, design: .rounded))
             + Text("%")
                .font(.system(size: 22, weight: .semibold, design: .rounded)))
                .padding(.vertical, 4)
            UsageBar(percent: hero.percent)
                .opacity(entry.isStale ? 0.62 : 1)
            if let resetsAt = hero.resetsAt {
                ResetCaption(date: resetsAt, percent: hero.percent, font: .system(size: 11))
                    .padding(.top, 6)
            }
            Spacer(minLength: 4)
            if metrics.count > 1 {
                let second = metrics[1]
                HStack {
                    Text(second.name)
                    Spacer()
                    Text(second.valueText)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 5)
                UsageBar(percent: second.percent, height: 4)
                    .opacity(entry.isStale ? 0.62 : 1)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(entry: entry)
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 11) {
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
            WidgetHeader(entry: entry, markSize: 16, showAge: false)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(entry.displays.prefix(5)) { metric in
                    MetricBarRow(metric: metric)
                }
            }
            .opacity(entry.isStale ? 0.8 : 1)
            .padding(.top, 14)
            Spacer(minLength: 6)
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
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var small: some View {
        let metrics = entry.displays
        let hero = metrics[0]
        return VStack(spacing: 0) {
            HStack {
                SunburstMark(size: 14)
                Spacer()
                if let fetchedAt = entry.snapshot?.fetchedAt {
                    AgeBadge(since: fetchedAt, stale: entry.isStale)
                }
            }
            Spacer(minLength: 2)
            UsageRing(percent: hero.percent, size: 78, stroke: 9)
                .opacity(entry.isStale ? 0.75 : 1)
            VStack(spacing: 1) {
                Text(hero.name)
                    .font(.system(size: 12.5, weight: .semibold))
                if let resetsAt = hero.resetsAt {
                    ResetCaption(date: resetsAt, percent: hero.percent, font: .system(size: 10.5))
                }
            }
            .padding(.top, 7)
            Spacer(minLength: 2)
            if metrics.count > 1 {
                let second = metrics[1]
                HStack(spacing: 6) {
                    Circle()
                        .fill(usageColor(second.percent))
                        .frame(width: 7, height: 7)
                    Text("\(second.name) \(second.valueText)")
                        .font(.system(size: 11, weight: .medium))
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
                        UsageRing(percent: metric.percent, size: 62, stroke: 7)
                            .opacity(entry.isStale ? 0.75 : 1)
                        Text(metric.name)
                            .font(.system(size: 11.5, weight: .semibold))
                        if let resetsAt = metric.resetsAt {
                            ResetCaption(date: resetsAt, percent: metric.percent, font: .system(size: 9.5))
                        } else if let caption = metric.caption {
                            Text(caption)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
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
            WidgetHeader(entry: entry, markSize: 16, showAge: false)
            HStack(spacing: 14) {
                UsageRing(percent: hero.percent, size: 96, stroke: 10)
                    .opacity(entry.isStale ? 0.75 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hero.name)
                        .font(.system(size: 14, weight: .semibold))
                    if let resetsAt = hero.resetsAt {
                        ResetCaption(date: resetsAt, percent: hero.percent, font: .system(size: 11.5))
                    }
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

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageBarsWidget()
        ClaudeUsageRingsWidget()
    }
}

struct ClaudeUsageBarsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageBars", provider: UsageProvider()) { entry in
            BarsWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage — Bars")
        .description("Plan usage as labelled progress bars with reset countdowns.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ClaudeUsageRingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageRings", provider: UsageProvider()) { entry in
            RingsWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage — Rings")
        .description("Plan usage as radial gauges with reset countdowns.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
