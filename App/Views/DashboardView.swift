import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var refresher: UsageRefresher

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if refresher.isStale, let fetchedAt = refresher.snapshot?.fetchedAt {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        (Text("Couldn't refresh — showing data from ")
                         + Text(fetchedAt, style: .relative) + Text(" ago."))
                        Spacer()
                        Button("Retry") { Task { await refresher.refresh(force: true) } }
                    }
                    .font(.callout)
                    .padding(12)
                    .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }

                if let snapshot = refresher.snapshot {
                    let displays = MetricPresentation.displays(for: snapshot,
                                                               kinds: MetricKind.allCases)
                    HStack(spacing: 16) {
                        ForEach(displays.prefix(2)) { metric in
                            GroupBox {
                                VStack(spacing: 10) {
                                    UsageRing(percent: metric.percent, size: 110, stroke: 11)
                                    Text(metric.name)
                                        .font(.headline)
                                    if let resetsAt = metric.resetsAt {
                                        ResetCaption(date: resetsAt, percent: metric.percent,
                                                     font: .callout)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                        }
                    }

                    let reported = Set(displays.map(\.kind))
                    let unreported = MetricKind.allCases.filter { !reported.contains($0) }
                    GroupBox {
                        VStack(spacing: 15) {
                            ForEach(displays.dropFirst(2)) { metric in
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
                        .padding(8)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        (Text("Updated ") + Text(snapshot.fetchedAt, style: .relative) + Text(" ago"))
                        Button {
                            Task { await refresher.refresh(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView("Loading usage…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                }
            }
            .padding(20)
        }
    }
}
