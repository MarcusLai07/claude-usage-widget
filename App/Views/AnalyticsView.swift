import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @ObservedObject var model: AnalyticsModel
    @State private var utilizationRange: TimeRange = .day
    @State private var tokenRange: TimeRange = .week

    enum TimeRange: String, CaseIterable, Identifiable {
        case day = "24h"
        case week = "7d"
        case month = "30d"

        var id: String { rawValue }
        var interval: TimeInterval {
            switch self {
            case .day: return 86400
            case .week: return 7 * 86400
            case .month: return 30 * 86400
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Analytics") {
                Spacer()
                if let fetchedAt = model.lastLoaded ?? refresher.snapshot?.fetchedAt {
                    AgeIndicator(since: fetchedAt)
                }
                RefreshButton()
            }
            ScrollView {
                VStack(spacing: 16) {
                    utilizationCard
                    tokenCard
                    HStack(alignment: .top, spacing: 16) {
                        summaryCard(title: "This session window",
                                    since: sessionWindowStart,
                                    caption: sessionCaption)
                        summaryCard(title: "This week window",
                                    since: weekWindowStart,
                                    caption: weekCaption)
                    }
                    if model.hasClaudeAccess {
                        modelTableCard
                    }
                    disclaimer
                }
                .padding(.init(top: 4, leading: 22, bottom: 22, trailing: 22))
            }
        }
        .background(Color.windowContent)
        .task { await model.reload() }
    }

    // MARK: Limit utilization (line chart)

    private struct UtilPoint: Identifiable {
        let ts: Date
        let value: Double
        var id: Date { ts }
    }

    private var utilizationCard: some View {
        let since = Date().addingTimeInterval(-utilizationRange.interval)
        let samples = model.history.filter { $0.ts >= since }
        let sessionPoints = samples.compactMap { s in s.session.map { UtilPoint(ts: s.ts, value: $0) } }
        let weeklyPoints = samples.compactMap { s in s.weekly.map { UtilPoint(ts: s.ts, value: $0) } }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("Limit utilization")
                Spacer()
                Picker("", selection: $utilizationRange) {
                    ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }
            if sessionPoints.count < 2 {
                EmptyStateView(icon: "chart.xyaxis.line",
                               title: "Collecting samples",
                               message: "The app records one sample every 5 minutes while it runs — the chart fills in as history accumulates.")
            } else {
                Chart {
                    RuleMark(y: .value("Threshold", 70))
                        .foregroundStyle(.orange.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    RuleMark(y: .value("Threshold", 90))
                        .foregroundStyle(.red.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    ForEach(sessionPoints) { point in
                        AreaMark(x: .value("Time", point.ts), y: .value("Used", point.value))
                            .foregroundStyle(Color.clay.opacity(0.10))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(sessionPoints) { point in
                        LineMark(x: .value("Time", point.ts), y: .value("Used", point.value),
                                 series: .value("Metric", "Session"))
                            .foregroundStyle(Color.clay)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(weeklyPoints) { point in
                        LineMark(x: .value("Time", point.ts), y: .value("Used", point.value),
                                 series: .value("Metric", "Weekly"))
                            .foregroundStyle(Color.chartIndigo)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 4]))
                            .interpolationMethod(.monotone)
                    }
                    if let last = sessionPoints.last {
                        PointMark(x: .value("Time", last.ts), y: .value("Used", last.value))
                            .foregroundStyle(Color.clay)
                            .symbolSize(42)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) }
                .chartLegend(.hidden)
                .frame(height: 170)

                HStack(spacing: 16) {
                    LegendSwatch(color: .clay, label: "Session")
                    LegendSwatch(color: .chartIndigo, dashed: true, label: "Weekly")
                    Spacer()
                    LegendSwatch(color: .orange, dashed: true, label: "70% / 90% thresholds")
                }
            }
        }
        .designCard()
    }

    // MARK: Tokens by model (stacked bars + states)

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("Tokens by model")
                Spacer()
                if model.hasClaudeAccess {
                    Picker("", selection: $tokenRange) {
                        ForEach([TimeRange.week, .month]) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            if !model.hasClaudeAccess {
                EmptyStateView(icon: "folder",
                               title: "Grant access to see token usage",
                               message: "Claude Usage reads transcript files in ~/.claude to count tokens by model. This stays on your Mac.",
                               actionLabel: "Grant Access to ~/.claude…",
                               action: { model.grantAccess() })
            } else if model.isLoading && model.tokenSamples.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning transcripts…")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Reading Claude Code activity from ~/.claude.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                let rows = model.tokensPerDay(since: Date().addingTimeInterval(-tokenRange.interval))
                if rows.isEmpty {
                    EmptyStateView(icon: "tray",
                                   title: "No Claude Code activity in this range",
                                   message: "Token usage will appear here once you run Claude Code on this Mac.")
                } else {
                    let colors = model.modelColors
                    Chart(rows) { row in
                        BarMark(x: .value("Day", row.day, unit: .day),
                                y: .value("Tokens", row.tokens))
                            .foregroundStyle(colors[row.model] ?? .gray)
                            .cornerRadius(2)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 150)

                    HStack(spacing: 16) {
                        ForEach(model.modelShares(since: Date().addingTimeInterval(-tokenRange.interval))) { share in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(colors[share.model] ?? .gray)
                                    .frame(width: 10, height: 10)
                                Text(share.model)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .designCard()
    }

    // MARK: Window summaries

    private var sessionWindowStart: Date {
        refresher.snapshot?.session?.resetsAt.map { $0.addingTimeInterval(-5 * 3600) }
            ?? Date().addingTimeInterval(-5 * 3600)
    }

    private var weekWindowStart: Date {
        refresher.snapshot?.weekly?.resetsAt.map { $0.addingTimeInterval(-7 * 86400) }
            ?? Date().addingTimeInterval(-7 * 86400)
    }

    private var sessionCaption: String { "Last 5 hours" }
    private var weekCaption: String { "Last 7 days" }

    private func summaryCard(title: String, since: Date, caption: String) -> some View {
        let shares = model.modelShares(since: since)
        let total = shares.reduce(0) { $0 + $1.billable }
        let colors = model.modelColors
        return VStack(alignment: .leading, spacing: 0) {
            CardTitle(title)
                .padding(.bottom, 12)
            (Text(compactTokens(total))
                .font(.system(size: 30, weight: .bold, design: .rounded))
             + Text("  tokens")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary))
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.init(top: 5, leading: 0, bottom: 14, trailing: 0))
            VStack(spacing: 9) {
                ForEach(shares.prefix(3)) { share in
                    VStack(spacing: 4) {
                        HStack {
                            Text(share.model)
                                .font(.system(size: 11.5, weight: .medium))
                            Spacer()
                            Text("\(Int(share.share))%")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        }
                        UsageBarTinted(percent: share.share, color: colors[share.model] ?? .gray)
                    }
                }
                if shares.isEmpty {
                    Text(model.hasClaudeAccess ? "No Claude Code activity in this window."
                                               : "Grant ~/.claude access to see token totals.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    // MARK: Model table

    private var modelTableCard: some View {
        let shares = model.modelShares(since: Date().addingTimeInterval(-tokenRange.interval))
        let colors = model.modelColors
        return VStack(alignment: .leading, spacing: 0) {
            CardTitle("By model")
                .padding(.bottom, 10)
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 0) {
                GridRow {
                    Text("Model").gridColumnAlignment(.leading)
                    Text("Share")
                    Text("Input")
                    Text("Output")
                    Text("Cache read")
                }
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.3)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 9)

                ForEach(shares) { share in
                    Divider().gridCellColumns(5)
                    GridRow {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(colors[share.model] ?? .gray)
                                .frame(width: 9, height: 9)
                            Text(share.model)
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .gridColumnAlignment(.leading)
                        Text("\(Int(share.share))%")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        Text(compactTokens(share.input))
                            .font(.system(size: 12.5, design: .rounded))
                        Text(compactTokens(share.output))
                            .font(.system(size: 12.5, design: .rounded))
                        Text(compactTokens(share.cacheRead))
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                }
            }
            if shares.isEmpty {
                Text("No data in this range.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
            Text("Token counts cover **Claude Code on this Mac only** — Anthropic's percentages above are the source of truth. Charted tokens are input + output + cache-write (\"billable\"); cache reads appear in the table only.")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }
}

/// Thin share bar tinted with a model's chart color (not the escalation scale).
struct UsageBarTinted: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if percent > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(5, geo.size.width * min(percent, 100) / 100))
                }
            }
        }
        .frame(height: 5)
    }
}
