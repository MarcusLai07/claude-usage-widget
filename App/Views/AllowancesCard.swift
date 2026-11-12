import SwiftUI

/// Every limit the account reports, in one card (Magpie's Allowances card):
/// the account, then one meter per window answering how much, until when,
/// and whether you're on pace, then what was left over time. The controls
/// (Trends, Hide account, Used/Left) sit in the section head above it.
struct AllowancesCard: View {
    let snapshot: UsageSnapshot
    let profile: AccountProfile?
    var hideAccount = false
    @Binding var showLeft: Bool
    var isStale = false
    @ObservedObject var trends: TrendModel

    var body: some View {
        let now = Date()
        let metrics = MetricPresentation.displays(for: snapshot, kinds: MetricKind.allCases,
                                                  showLeft: showLeft, now: now)
        // Pairs of meters, row by row.
        let pairs = stride(from: 0, to: metrics.count, by: 2).map {
            Array(metrics[$0..<min($0 + 2, metrics.count)])
        }
        VStack(alignment: .leading, spacing: 16) {
            header
            // Two columns when there's room, one in a narrow window. Not a
            // LazyVGrid: inside the page's ScrollView it could leave its
            // items undrawn, and six meters gain nothing from laziness.
            ViewThatFits(in: .horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 28, verticalSpacing: 18) {
                    ForEach(pairs.indices, id: \.self) { row in
                        GridRow {
                            ForEach(pairs[row]) { metric in
                                meter(metric, now: now)
                                    .frame(minWidth: 250, maxWidth: .infinity, alignment: .topLeading)
                            }
                            if pairs[row].count == 1 {
                                Color.clear.frame(minWidth: 250, maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(metrics) { meter($0, now: now) }
                }
            }
            .opacity(isStale ? 0.75 : 1)
            if trends.loadedAt != nil {
                LeftOverTimeView(snapshot: snapshot, trends: trends)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SunburstMark(size: 17)
                Text("Claude")
                    .font(.system(size: 14, weight: .semibold))
            }
            HStack {
                Text(accountLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if let plan = profile?.plan {
                    Text(plan)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var accountLine: String {
        guard let email = profile?.email else { return "Plan limits" }
        return hideAccount ? AccountProfile.masked(email) : email
    }

    private func meter(_ metric: MetricDisplay, now: Date) -> some View {
        AllowanceMeter(metric: metric, runsOut: runsOut(metric.kind, now: now)) {
            showLeft.toggle()
        }
    }

    /// A forecast worth a line on the meter: the window empties before it
    /// resets. ("Lasts past the reset" goes once, in the chart's head.)
    private func runsOut(_ kind: MetricKind, now: Date) -> Forecast? {
        let forecast = trends.forecast(for: kind, window: snapshot.window(for: kind), now: now)
        if case .runsOut = forecast { return forecast }
        return nil
    }
}

/// One window: name and figure, a thin bar in the window's series color
/// (orange, then red, near the limit), then "Resets Tue 18:00 · in 5d ·
/// Pace −7%". Clicking the figure flips Used/Left everywhere.
struct AllowanceMeter: View {
    let metric: MetricDisplay
    /// "Runs out Sat 14:00 at this pace", when it will.
    var runsOut: Forecast? = nil
    var onToggleMode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(action: onToggleMode) {
                    (Text(metric.valueText)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(metric.percent >= 70 ? metric.color : Color.primary)
                     + Text(metric.unitText.map { " \($0)" } ?? "")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.primary))
                }
                .buttonStyle(.plain)
                .help(metric.showLeft ? "Show what's used" : "Show what's left")
            }
            UsageBar(percent: metric.shownPercent, height: 5,
                     tint: metric.kind.meterColor(percentUsed: metric.percent))
            VStack(alignment: .leading, spacing: 2) {
                MetricCaption(metric: metric, font: .system(size: 11.5), countdown: true)
                    .fixedSize(horizontal: false, vertical: true)
                if let runsOut {
                    ForecastLine(forecast: runsOut)
                }
            }
        }
    }
}

struct PlanBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.clay)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.clay.opacity(0.16)))
    }
}
