import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var refresher: UsageRefresher

    private var sessionPercent: Double {
        refresher.snapshot?.session?.utilization ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Dashboard") {
                if sessionPercent >= 100 {
                    StatusPill(text: "Session limit reached", color: .red)
                } else if sessionPercent >= 70 {
                    StatusPill(text: "Approaching session limit", color: .orange)
                }
                Spacer()
                if let fetchedAt = refresher.snapshot?.fetchedAt {
                    AgeIndicator(since: fetchedAt, stale: refresher.isStale)
                }
                RefreshButton()
            }
            ScrollView {
                content
                    .padding(.init(top: 4, leading: 22, bottom: 22, trailing: 22))
            }
        }
        .background(Color.windowContent)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = refresher.snapshot {
            let displays = MetricPresentation.displays(for: snapshot, kinds: MetricKind.allCases)
            VStack(spacing: 16) {
                if refresher.isStale {
                    StaleBanner()
                }

                HStack(spacing: 16) {
                    if let session = displays.first(where: { $0.kind == .session }) {
                        heroCard(session, windowLabel: "5-hour window")
                    }
                    if let weekly = displays.first(where: { $0.kind == .weekly }) {
                        heroCard(weekly, windowLabel: "7-day window")
                    }
                }

                moreLimits(displays)
            }
        } else {
            ProgressView("Loading usage…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
        }
    }

    private func heroCard(_ metric: MetricDisplay, windowLabel: String) -> some View {
        HStack(spacing: 16) {
            UsageRing(percent: metric.percent, size: 108, stroke: 11)
                .opacity(refresher.isStale ? 0.75 : 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(metric.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(windowLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .padding(.init(top: 1, leading: 0, bottom: 8, trailing: 0))
                if let resetsAt = metric.resetsAt {
                    ResetCaption(date: resetsAt, percent: metric.percent,
                                 font: .system(size: 12.5, weight: .medium))
                }
            }
            Spacer(minLength: 0)
        }
        .designCard()
    }

    private func moreLimits(_ displays: [MetricDisplay]) -> some View {
        let others = displays.filter { $0.kind != .session && $0.kind != .weekly }
        let reported = Set(displays.map(\.kind))
        let unreported = MetricKind.allCases.filter { !reported.contains($0) }
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle("More limits")
            ForEach(others) { metric in
                MetricBarRow(metric: metric)
            }
            ForEach(unreported) { kind in
                HStack(alignment: .firstTextBaseline) {
                    Text(kind.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("—")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Text("not reported for your account yet")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
        .opacity(refresher.isStale ? 0.85 : 1)
    }
}
