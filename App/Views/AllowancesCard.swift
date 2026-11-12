import SwiftUI

/// Every limit the account reports, in one card (Magpie's Allowances card):
/// account header with plan badge, then one meter per window answering how
/// much, until when, and whether you're on pace.
struct AllowancesCard: View {
    let snapshot: UsageSnapshot
    let profile: AccountProfile?
    @Binding var showLeft: Bool
    @Binding var hideAccount: Bool
    var isStale = false
    @ObservedObject var trends: TrendModel

    var body: some View {
        let now = Date()
        let metrics = MetricPresentation.displays(for: snapshot, kinds: MetricKind.allCases,
                                                  showLeft: showLeft, now: now)
        VStack(alignment: .leading, spacing: 18) {
            header
            // Two columns when there's room, one in a narrow window.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 28, alignment: .top)],
                      alignment: .leading, spacing: 20) {
                ForEach(metrics) { metric in
                    AllowanceMeter(metric: metric, runsOut: runsOut(metric.kind, now: now)) {
                        showLeft.toggle()
                    }
                }
            }
            .opacity(isStale ? 0.75 : 1)
            if trends.loadedAt != nil {
                Divider()
                LeftOverTimeView(snapshot: snapshot, trends: trends)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    /// A forecast worth a line on the meter: the window empties before it
    /// resets. ("Lasts past the reset" goes once, in the chart's head.)
    private func runsOut(_ kind: MetricKind, now: Date) -> Forecast? {
        let forecast = trends.forecast(for: kind, window: snapshot.window(for: kind), now: now)
        if case .runsOut = forecast { return forecast }
        return nil
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            SunburstMark(size: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Claude")
                        .font(.system(size: 15, weight: .semibold))
                    if let plan = profile?.plan {
                        PlanBadge(text: plan)
                    }
                }
                Text(accountLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Picker("Show", selection: $showLeft) {
                Text("Used").tag(false)
                Text("Left").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Show what's used or what's left of each limit")
            if profile?.email != nil {
                Button {
                    hideAccount.toggle()
                } label: {
                    Image(systemName: hideAccount ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 22)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(hideAccount ? "Show account email" : "Hide account email (for screenshots)")
            }
        }
    }

    private var accountLine: String {
        guard let email = profile?.email else { return "Plan limits" }
        return hideAccount ? AccountProfile.masked(email) : email
    }
}

/// One window: name and figure, bar, then "Resets Tue 6:00 PM · in 5d ·
/// Pace −8%". Clicking the figure flips Used/Left everywhere.
struct AllowanceMeter: View {
    let metric: MetricDisplay
    /// "Runs out Sat 14:00 at this pace", when it will.
    var runsOut: Forecast? = nil
    var onToggleMode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Button(action: onToggleMode) {
                    MetricValue(metric: metric, size: 15)
                }
                .buttonStyle(.plain)
                .help(metric.showLeft ? "Show what's used" : "Show what's left")
            }
            UsageBar(percent: metric.shownPercent, height: 7, tint: metric.color)
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
