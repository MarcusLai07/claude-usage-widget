import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @ObservedObject var model: AnalyticsModel
    @State private var utilizationRange: TimeRange = .day
    @State private var tokenRange: TimeRange = .week

    enum TimeRange: String, CaseIterable, Identifiable {
        case day = "24 h"
        case week = "7 days"
        case month = "30 days"

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                utilizationCard
                tokensCard
                if model.hasClaudeAccess {
                    windowSummaries
                    modelTable
                }
                footer
            }
            .padding(20)
        }
        .task { await model.reload() }
    }

    // MARK: Limit utilization over time

    private struct UtilPoint: Identifiable {
        let ts: Date
        let metric: String
        let value: Double
        var id: String { "\(ts.timeIntervalSince1970)-\(metric)" }
    }

    private var utilizationCard: some View {
        let since = Date().addingTimeInterval(-utilizationRange.interval)
        var points: [UtilPoint] = []
        for sample in model.history where sample.ts >= since {
            if let v = sample.session { points.append(UtilPoint(ts: sample.ts, metric: "Session", value: v)) }
            if let v = sample.weekly { points.append(UtilPoint(ts: sample.ts, metric: "Weekly", value: v)) }
        }
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Limit utilization")
                        .font(.headline)
                    Spacer()
                    Picker("", selection: $utilizationRange) {
                        ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                if points.count < 2 {
                    emptyChart("Collecting samples — the app records one every 5 minutes while it runs.")
                } else {
                    Chart(points) { point in
                        LineMark(x: .value("Time", point.ts),
                                 y: .value("Used %", point.value))
                            .foregroundStyle(by: .value("Metric", point.metric))
                            .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100)
                    .chartForegroundStyleScale(["Session": Color.clay, "Weekly": Color.blue])
                    .frame(height: 200)
                }
            }
            .padding(8)
        }
    }

    // MARK: Tokens by model (Claude Code transcripts)

    private var tokensCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Claude Code tokens by model")
                        .font(.headline)
                    Spacer()
                    if model.hasClaudeAccess {
                        Picker("", selection: $tokenRange) {
                            ForEach([TimeRange.week, .month]) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }
                if !model.hasClaudeAccess {
                    VStack(spacing: 10) {
                        Text("Token analytics read Claude Code's local transcripts (~/.claude). Grant read access once to enable them.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Grant Access to ~/.claude…") { model.grantAccess() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else if model.isLoading && model.tokenSamples.isEmpty {
                    ProgressView("Scanning transcripts…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    let rows = model.tokensPerDay(since: Date().addingTimeInterval(-tokenRange.interval))
                    if rows.isEmpty {
                        emptyChart("No Claude Code activity in this range.")
                    } else {
                        Chart(rows) { row in
                            BarMark(x: .value("Day", row.day, unit: .day),
                                    y: .value("Tokens", row.tokens))
                                .foregroundStyle(by: .value("Model", row.model))
                        }
                        .frame(height: 200)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: Current-window summaries

    private var windowSummaries: some View {
        HStack(spacing: 16) {
            summaryCard(title: "This session window",
                        since: sessionWindowStart,
                        caption: "5-hour window")
            summaryCard(title: "This week window",
                        since: weekWindowStart,
                        caption: "7-day window")
        }
    }

    private func summaryCard(title: String, since: Date, caption: String) -> some View {
        let shares = model.modelShares(since: since)
        let total = shares.reduce(0) { $0 + $1.billable }
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text("\(total.formatted()) tokens")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                ForEach(shares.prefix(3)) { share in
                    HStack {
                        Text(share.model).font(.callout)
                        Spacer()
                        Text("\(Int(share.share))%")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.clay)
                    }
                }
                Spacer(minLength: 0)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sessionWindowStart: Date {
        if let resetsAt = refresher.snapshot?.session?.resetsAt {
            return resetsAt.addingTimeInterval(-5 * 3600)
        }
        return Date().addingTimeInterval(-5 * 3600)
    }

    private var weekWindowStart: Date {
        if let resetsAt = refresher.snapshot?.weekly?.resetsAt {
            return resetsAt.addingTimeInterval(-7 * 86400)
        }
        return Date().addingTimeInterval(-7 * 86400)
    }

    // MARK: Per-model table

    private var modelTable: some View {
        let shares = model.modelShares(since: Date().addingTimeInterval(-tokenRange.interval))
        return GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("Models · last \(tokenRange.rawValue)")
                    .font(.headline)
                    .padding(.bottom, 4)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    GridRow {
                        Text("Model")
                        Text("Share")
                        Text("Input")
                        Text("Output")
                        Text("Cache read")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(shares) { share in
                        GridRow {
                            Text(share.model).font(.callout.weight(.medium))
                            Text("\(Int(share.share))%")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(Color.clay)
                            Text(share.input.formatted()).font(.callout.monospacedDigit())
                            Text(share.output.formatted()).font(.callout.monospacedDigit())
                            Text(share.cacheRead.formatted())
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text("Token counts cover Claude Code on this Mac only — claude.ai chats count toward the same limits but aren't visible locally. Percentages come from Anthropic and are the source of truth.")
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private func emptyChart(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}
