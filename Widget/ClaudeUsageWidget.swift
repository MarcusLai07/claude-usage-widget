import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let visibleMetrics: [MetricKind]
    let signedIn: Bool
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder, visibleMetrics: [.session, .weekly], signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(
            date: Date(),
            snapshot: AppGroupStore.cachedSnapshot ?? .placeholder,
            visibleMetrics: AppGroupStore.visibleMetrics,
            signedIn: true
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            var snapshot: UsageSnapshot?
            var signedIn = true
            do {
                snapshot = try await UsageAPI.fetchUsage()
                AppGroupStore.cachedSnapshot = snapshot
            } catch UsageAPIError.notSignedIn {
                signedIn = false
            } catch {
                snapshot = AppGroupStore.cachedSnapshot
            }
            let entry = UsageEntry(
                date: Date(),
                snapshot: snapshot,
                visibleMetrics: AppGroupStore.visibleMetrics,
                signedIn: signedIn
            )
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

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if !entry.signedIn {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.title2)
                    Text("Open Claude Usage to sign in")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            } else if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                Text("No usage data yet").font(.caption)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func content(_ snapshot: UsageSnapshot) -> some View {
        let metrics = entry.visibleMetrics.compactMap { kind in
            snapshot.window(for: kind).map { (kind, $0) }
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(metrics.prefix(maxMetrics), id: \.0) { kind, window in
                WidgetMetricRow(kind: kind, window: window, compact: family == .systemSmall)
            }
        }
        .padding(.vertical, 2)
    }

    private var maxMetrics: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        default: return 5
        }
    }
}

struct WidgetMetricRow: View {
    let kind: MetricKind
    let window: UsageWindow
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(kind.title)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.utilization ?? 0))%")
                    .font((compact ? Font.caption : Font.body).weight(.semibold).monospacedDigit())
            }
            ProgressView(value: min((window.utilization ?? 0) / 100, 1))
                .tint(color)
            if !compact, let resetsAt = window.resetsAt {
                (Text("Resets in ") + Text(resetsAt, style: .relative))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        let value = window.utilization ?? 0
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        return .green
    }
}

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
    }
}

struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Session and weekly Claude plan usage with reset times.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
