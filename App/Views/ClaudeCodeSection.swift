import SwiftUI
import Charts

/// The Usage page's token half: Claude Code activity on this Mac for the
/// toolbar's period — stat strip, activity chart, and Models / Apps /
/// Projects bar lists, in Magpie's layout.
struct ClaudeCodeSection: View {
    @ObservedObject var analytics: AnalyticsModel
    let period: UsagePeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionLabel("Claude Code on this Mac")
                Spacer()
                if analytics.hasClaudeAccess && !analytics.hasDesktopAccess {
                    Button("Add Claude Desktop sessions…") { analytics.grantDesktopAccess() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dataAccent)
                        .help("Claude Desktop's local-agent sessions keep transcripts of their own in ~/Library/Application Support/Claude")
                }
            }
            TranscriptGate(analytics: analytics) {
                let overview = analytics.overview(period)
                if overview.isEmpty {
                    EmptyStateView(icon: "tray",
                                   title: "No Claude Code activity \(period == .all ? "yet" : "in this period")",
                                   message: "Token usage appears here once you run Claude Code on this Mac.")
                        .designCard()
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        StatStrip(totals: overview.totals)
                        ActivityChart(overview: overview, colors: analytics.modelColors)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 14) {
                                modelsList(overview)
                                appsList(overview)
                            }
                            VStack(spacing: 14) {
                                modelsList(overview)
                                appsList(overview)
                            }
                        }
                        BarListPanel(title: "Projects", rows: overview.projects, limit: 8,
                                     color: { _ in .dataAccent })
                    }
                }
                footnote
            }
        }
    }

    private func modelsList(_ overview: UsageOverview) -> some View {
        BarListPanel(title: "Models", rows: overview.models, limit: 6,
                     color: { analytics.modelColors[$0.id] ?? .gray })
            .frame(minWidth: 300)
    }

    private func appsList(_ overview: UsageOverview) -> some View {
        BarListPanel(title: "Apps", rows: overview.apps, limit: 6, color: { _ in .chartSky },
                     icon: { AnalyticsModel.appIcon($0.id) })
            .frame(minWidth: 300)
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
            Text("Token counts cover **Claude Code on this Mac only** — claude.ai and other devices count toward the same limits but leave no trace here, so Anthropic's percentages above are the source of truth. Tokens are fresh input + output + cache reads and writes, as Magpie counts them. Cost is what the same calls would cost at Anthropic API list prices, not what a subscription bills.")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }
}

// MARK: - Stat strip

/// Joined tiles: Tokens · Requests · Cost · Cache hit rate · Output speed.
struct StatStrip: View {
    let totals: UsageTotals

    var body: some View {
        StatStripPanel {
            StatTile(label: "Tokens", value: compactTokens(totals.tokens),
                     caption: "\(compactTokens(totals.input)) in · \(compactTokens(totals.output)) out · \(compactTokens(totals.cache)) cache")
            TileDivider()
            StatTile(label: "Requests", value: totals.requests.formatted(),
                     caption: totals.failed > 0
                        ? "\(totals.failed) failed · \(String(format: "%.1f", totals.successRate))% succeeded"
                        : "\(totals.sessions.formatted()) session\(totals.sessions == 1 ? "" : "s")")
            TileDivider()
            StatTile(label: "Cost", value: costText(totals.cost),
                     caption: totals.unpriced > 0 ? "\(totals.unpriced) calls unpriced" : "at API list prices",
                     valueColor: .costGreen)
            TileDivider()
            StatTile(label: "Cache hit rate", value: String(format: "%.1f%%", totals.cacheHitRate),
                     progress: totals.cacheHitRate)
            if let speed = totals.outputSpeed {
                TileDivider()
                StatTile(label: "Output speed", value: "\(Int(speed.rounded())) tok/s",
                         caption: "\(totals.timedReplies.formatted()) replies")
            }
        }
    }
}

// MARK: - Activity chart

/// What the activity bars measure.
enum ActivityMetric: String, CaseIterable, Identifiable {
    case tokens, cost, requests
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Bars per hour, day or week, stacked by model, with Magpie's metric tabs.
struct ActivityChart: View {
    let overview: UsageOverview
    let colors: [String: Color]
    @AppStorage("activityMetric") private var metric: ActivityMetric = .tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                PillTabs(options: ActivityMetric.allCases.map { ($0, $0.title) }, selection: $metric, size: 12)
                Spacer()
                if let peak = peak {
                    (Text("Peak ") + Text(format(peak.value)).fontWeight(.semibold)
                     + Text(" · \(peakLabel(peak.start))"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Chart(overview.bars) { bar in
                BarMark(x: .value("Time", bar.start, unit: overview.barUnit),
                        y: .value(metric.title, value(of: bar)))
                    .foregroundStyle(colors[bar.model] ?? .gray)
                    .cornerRadius(2)
            }
            .chartXScale(domain: domain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let number = value.as(Double.self) { Text(format(number)) }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 170)

            // Legend in the Models list's order (most tokens first).
            let charted = Set(overview.bars.map(\.model))
            HStack(spacing: 14) {
                ForEach(overview.models.filter { charted.contains($0.id) }.prefix(6)) { row in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(colors[row.id] ?? .gray)
                            .frame(width: 9, height: 9)
                        Text(row.name)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .designCard()
    }

    private func value(of bar: ActivityBar) -> Double {
        switch metric {
        case .tokens: return Double(bar.tokens)
        case .cost: return bar.cost
        case .requests: return Double(bar.requests)
        }
    }

    private func format(_ value: Double) -> String {
        switch metric {
        case .tokens: return compactTokens(Int(value))
        case .cost: return costText(value, approximate: false)
        case .requests: return Int(value).formatted()
        }
    }

    private var peak: (start: Date, value: Double)? {
        var perBar: [Date: Double] = [:]
        for bar in overview.bars { perBar[bar.start, default: 0] += value(of: bar) }
        return perBar.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    /// The period's span, so a quiet stretch shows as empty rather than
    /// being cropped away.
    private var domain: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = min(Date(), overview.until)
        let from = overview.period == .all ? (overview.bars.first?.start ?? end) : overview.since
        let lower = calendar.dateInterval(of: overview.barUnit, for: from)?.start ?? from
        let upper = calendar.dateInterval(of: overview.barUnit, for: end)?.end ?? end
        return lower...max(upper, lower.addingTimeInterval(3600))
    }

    private func peakLabel(_ date: Date) -> String {
        switch overview.barUnit {
        case .hour: return shortDateTime(date)
        case .weekOfYear: return "week of " + date.formatted(.dateTime.month(.abbreviated).day())
        default: return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
}

// MARK: - Bar lists

/// Magpie's ranked list: name · share bar · tokens · cost, one line per row;
/// requests, sessions and failures on hover; "+N more" to expand.
struct BarListPanel: View {
    let title: String
    let rows: [BreakdownRow]
    var limit = 8
    var color: (BreakdownRow) -> Color
    var icon: ((BreakdownRow) -> String)? = nil
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            let maxTokens = max(rows.map(\.tokens).max() ?? 1, 1)
            VStack(spacing: 9) {
                ForEach(showAll ? rows : Array(rows.prefix(limit))) { row in
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            if let icon {
                                Image(systemName: icon(row))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 14)
                            }
                            Text(row.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(width: 150, alignment: .leading)
                        UsageBarTinted(percent: Double(row.tokens) / Double(maxTokens) * 100,
                                       color: color(row))
                        Text(compactTokens(row.tokens))
                            .font(.system(size: 12).monospacedDigit())
                            .frame(width: 52, alignment: .trailing)
                        Text(costText(row.cost))
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(Color.costGreen)
                            .frame(width: 62, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .help(hoverText(row))
                }
            }
            if rows.count > limit {
                Button(showAll ? "Show fewer" : "+\(rows.count - limit) more") { showAll.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    private func hoverText(_ row: BreakdownRow) -> String {
        var parts = ["\(row.requests.formatted()) request\(row.requests == 1 ? "" : "s")",
                     "\(row.sessions.formatted()) session\(row.sessions == 1 ? "" : "s")",
                     "\(Int(row.share.rounded()))% of tokens"]
        if row.failed > 0 { parts.append("\(row.failed) failed") }
        let line = parts.joined(separator: " · ")
        return row.detail.map { "\($0)\n\(line)" } ?? "\(row.name)\n\(line)"
    }
}

/// Thin share bar tinted with a row's color (not the escalation scale).
struct UsageBarTinted: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.track)
                if percent > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * min(percent, 100) / 100))
                }
            }
        }
        .frame(height: 4)
    }
}
