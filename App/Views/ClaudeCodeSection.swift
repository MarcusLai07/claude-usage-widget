import SwiftUI
import Charts

/// The Usage page's token half: Claude Code activity on this Mac for the
/// picked period — stat strip, activity chart, and Apps / Models /
/// Projects lists.
struct ClaudeCodeSection: View {
    @ObservedObject var analytics: AnalyticsModel
    @Binding var period: UsagePeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code on this Mac")
                        .font(.system(size: 15, weight: .semibold))
                    Text("From local transcripts in ~/.claude")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if analytics.hasClaudeAccess && !analytics.hasDesktopAccess {
                    Button("Add Claude Desktop sessions…") { analytics.grantDesktopAccess() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.clay)
                        .help("Claude Desktop's local-agent sessions keep transcripts of their own in ~/Library/Application Support/Claude")
                }
                if analytics.hasClaudeAccess {
                    Picker("Period", selection: $period) {
                        ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.top, 6)

            content
        }
    }

    private var content: some View {
        TranscriptGate(analytics: analytics) {
            let overview = analytics.overview(period)
            if overview.isEmpty {
                EmptyStateView(icon: "tray",
                               title: "No Claude Code activity \(period == .all ? "yet" : "in this period")",
                               message: "Token usage appears here once you run Claude Code on this Mac.")
                    .designCard()
            } else {
                StatStrip(totals: overview.totals)
                ActivityChart(overview: overview, colors: analytics.modelColors)
                BreakdownCard(title: "Apps", storageKey: "apps", rows: overview.apps, limit: 6) { row in
                    Image(systemName: AnalyticsModel.appIcon(row.id))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } tint: { _ in .clay }
                BreakdownCard(title: "Models", storageKey: "models", rows: overview.models, limit: 8) { row in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(analytics.modelColors[row.id] ?? .gray)
                        .frame(width: 9, height: 9)
                } tint: { row in analytics.modelColors[row.id] ?? .gray }
                BreakdownCard(title: "Projects", storageKey: "projects", rows: overview.projects, limit: 8) { _ in
                    Image(systemName: "folder")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } tint: { _ in .chartIndigo }
            }
            footnote
        }
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
    }
}

// MARK: - Stat strip

/// Joined tiles: Tokens · Cache read · Thinking · Requests.
struct StatStrip: View {
    let totals: UsageTotals

    var body: some View {
        HStack(spacing: 0) {
            tile("Tokens", compactTokens(totals.tokens),
                 "\(compactTokens(totals.input)) in · \(compactTokens(totals.output)) out · \(compactTokens(totals.cache)) cache")
            Divider()
            tile("Requests", totals.requests.formatted(),
                 totals.failed > 0
                    ? "\(totals.failed) failed · \(String(format: "%.1f", totals.successRate))% succeeded"
                    : "\(totals.sessions.formatted()) session\(totals.sessions == 1 ? "" : "s")")
            Divider()
            tile("Cost", costText(totals.cost), "at API list prices", valueColor: .costGreen)
            Divider()
            tile("Cache hit rate", String(format: "%.1f%%", totals.cacheHitRate),
                 "\(compactTokens(totals.cacheRead)) read from cache")
            if let speed = totals.outputSpeed {
                Divider()
                tile("Output speed", "\(Int(speed.rounded())) tok/s",
                     "\(totals.timedReplies.formatted()) replies")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.cardStroke, lineWidth: 0.5))
    }

    private func tile(_ label: String, _ value: String, _ caption: String,
                      valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

// MARK: - Activity chart

/// Bars per hour (Today), day, or week, stacked by model.
struct ActivityChart: View {
    let overview: UsageOverview
    let colors: [String: Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle("Activity")
                Spacer()
                if let peak = overview.peak {
                    (Text("Peak ") + Text(compactTokens(peak.tokens)).fontWeight(.semibold)
                     + Text(" · \(peakLabel(peak.start))"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Chart(overview.bars) { bar in
                BarMark(x: .value("Time", bar.start, unit: overview.barUnit),
                        y: .value("Tokens", bar.tokens))
                    .foregroundStyle(colors[bar.model] ?? .gray)
                    .cornerRadius(2)
            }
            .chartXScale(domain: domain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) { Text(compactTokens(tokens)) }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 150)

            // Legend in the Models list's order (most tokens first).
            let charted = Set(overview.bars.map(\.model))
            HStack(spacing: 14) {
                ForEach(overview.models.filter { charted.contains($0.id) }.prefix(6)) { row in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(colors[row.id] ?? .gray)
                            .frame(width: 9, height: 9)
                        Text(row.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .designCard()
    }

    /// The period's span, so a quiet stretch shows as empty rather than
    /// being cropped away.
    private var domain: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        let from = overview.period == .all ? (overview.bars.first?.start ?? now) : overview.since
        let lower = calendar.dateInterval(of: overview.barUnit, for: from)?.start ?? from
        let upper = calendar.dateInterval(of: overview.barUnit, for: now)?.end ?? now
        return lower...upper
    }

    private func peakLabel(_ date: Date) -> String {
        switch overview.barUnit {
        case .hour: return date.formatted(.dateTime.hour().minute())
        case .weekOfYear: return "week of " + date.formatted(.dateTime.month(.abbreviated).day())
        default: return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
}

// MARK: - Breakdown lists

/// A collapsible list of rows: icon · name and "41 requests · 3 sessions" ·
/// share bar · tokens with "in · out" under them.
struct BreakdownCard<Icon: View>: View {
    let title: String
    let storageKey: String
    let rows: [BreakdownRow]
    var limit = 8
    @ViewBuilder var icon: (BreakdownRow) -> Icon
    var tint: (BreakdownRow) -> Color

    @AppStorage private var collapsed: Bool
    @State private var showAll = false

    init(title: String, storageKey: String, rows: [BreakdownRow], limit: Int = 8,
         @ViewBuilder icon: @escaping (BreakdownRow) -> Icon,
         tint: @escaping (BreakdownRow) -> Color) {
        self.title = title
        self.storageKey = storageKey
        self.rows = rows
        self.limit = limit
        self.icon = icon
        self.tint = tint
        _collapsed = AppStorage(wrappedValue: false, "breakdown.\(storageKey).collapsed")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .foregroundStyle(.tertiary)
                    CardTitle(title)
                    Text("\(rows.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                let shown = showAll ? rows : Array(rows.prefix(limit))
                VStack(spacing: 0) {
                    ForEach(shown) { row in
                        Divider()
                        BreakdownRowView(row: row, tint: tint(row)) { icon(row) }
                    }
                }
                .padding(.top, 8)
                if rows.count > limit {
                    Button(showAll ? "Show fewer" : "Show all \(rows.count)") { showAll.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.clay)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }
}

struct BreakdownRowView<Icon: View>: View {
    let row: BreakdownRow
    let tint: Color
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        HStack(spacing: 10) {
            icon()
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(row.requests.formatted()) request\(row.requests == 1 ? "" : "s") · \(row.sessions.formatted()) session\(row.sessions == 1 ? "" : "s")\(row.failed > 0 ? " · \(row.failed) failed" : "")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .help(row.detail ?? row.name)
            Spacer(minLength: 12)
            UsageBarTinted(percent: row.share, color: tint)
                .frame(width: 90)
            Text("\(Int(row.share.rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 1) {
                Text(compactTokens(row.tokens))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                Text(costText(row.cost))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.costGreen)
            }
            .frame(width: 118, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}

/// Thin share bar tinted with a row's color (not the escalation scale).
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
