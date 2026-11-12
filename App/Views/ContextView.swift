import SwiftUI
import Charts
import AppKit

/// Usage › Context ("Tuned for you", after Magpie): the auto-compact window
/// and prompt-cache lifetime that would have spent the fewest tokens on the
/// period's own calls, replayed setting by setting.
struct ContextView: View {
    @ObservedObject var analytics: AnalyticsModel
    let period: UsagePeriod
    @State private var report: ContextTuning.Report?

    private var key: String {
        "\(period.cacheKey)|\(analytics.lastLoaded?.timeIntervalSince1970 ?? 0)|\(analytics.compactSetting ?? 0)"
    }

    var body: some View {
        TranscriptGate(analytics: analytics) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Tuned for you")
                Text("Your own calls of the period, replayed setting by setting from Claude Code's session files: the settings that would have spent the fewest tokens, for how you work. Tokens are weighed as Anthropic prices them for each model — a cache read is a small fraction of an input token, a cache write a quarter more (twice for an hour's).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let report {
                    if report.compactions.isEmpty && report.mainCache == nil && report.subagentCache == nil {
                        EmptyStateView(icon: "tray", title: "Too few calls to tune",
                                       message: "The replays need at least 50 calls of a model in the period. Try a longer period.")
                            .designCard()
                    } else {
                        card(report)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
        }
        .task(id: key) {
            let samples = analytics.samples(in: period)
            let setting = analytics.compactSetting
            report = await Task.detached(priority: .userInitiated) {
                ContextTuning.report(samples, compactSetting: setting)
            }.value
        }
    }

    private func card(_ report: ContextTuning.Report) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    SunburstMark(size: 17)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Claude Code").font(.system(size: 14, weight: .semibold))
                        Text("\(report.calls.formatted()) calls").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if report.bestSaving >= ContextTuning.sameCost {
                    Badge(text: "Up to \(Int((report.bestSaving * 100).rounded()))% fewer", color: .costGreen)
                } else {
                    Badge(text: "Already lean", color: .costGreen)
                }
            }
            .padding(.bottom, 14)
            ForEach(report.compactions, id: \.model) { compaction in
                Divider()
                CompactionSection(compaction: compaction, hasSetting: analytics.compactSetting != nil)
                    .padding(.vertical, 16)
            }
            if let cache = report.mainCache {
                Divider()
                CacheSection(title: "Prompt cache · main conversation", cache: cache)
                    .padding(.vertical, 16)
            }
            if let cache = report.subagentCache {
                Divider()
                CacheSection(title: "Prompt cache · subagents", cache: cache)
                    .padding(.vertical, 16)
            }
        }
        .designCard()
    }
}

/// A small rounded label: "Up to 13% fewer".
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private func tokensK(_ value: Int) -> String {
    value >= 1_000_000 && value % 1_000_000 == 0 ? "\(value / 1_000_000)M" : compactTokens(value)
}

/// Auto-compact for one model: now → fewest tokens, the cost curve over
/// every window, what the user's conversations do, and the setting to copy.
struct CompactionSection: View {
    let compaction: ContextTuning.Compaction
    let hasSetting: Bool
    @State private var copied = false

    private struct CurvePoint: Identifiable {
        let window: Int
        let over: Double
        var id: Int { window }
    }

    var body: some View {
        let low = max(compaction.curve.map(\.cost).min() ?? compaction.low, 1)
        let points = compaction.curve.map { CurvePoint(window: $0.window, over: ($0.cost / low - 1) * 100) }
        let nowOver = (compaction.cost / low - 1) * 100
        let facts = compaction.facts
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Auto-compact").font(.system(size: 13, weight: .semibold))
                Text(compaction.model).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(hasSetting ? "Your setting" : "Claude Code's default: the model's whole window")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOW").font(.system(size: 10, weight: .semibold)).kerning(0.5).foregroundStyle(.tertiary)
                    Text(tokensK(compaction.current))
                        .font(.system(size: 22, weight: .medium).monospacedDigit())
                        .strikethrough(compaction.changes)
                        .foregroundStyle(compaction.changes ? .secondary : .primary)
                }
                if compaction.changes {
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FEWEST TOKENS").font(.system(size: 10, weight: .semibold)).kerning(0.5).foregroundStyle(.tertiary)
                        Text(tokensK(compaction.best))
                            .font(.system(size: 22, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.costGreen)
                    }
                }
            }
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Window", point.window), y: .value("Over", point.over))
                        .foregroundStyle(LinearGradient(colors: [Color.clay.opacity(0.35), Color.clay.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Window", point.window), y: .value("Over", point.over))
                        .foregroundStyle(Color.clay)
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Leanest", 0))
                    .foregroundStyle(Color.costGreen.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Window", compaction.best), y: .value("Over", 0))
                    .foregroundStyle(Color.costGreen)
                    .symbolSize(60)
                    .annotation(position: .top) {
                        Text("Leanest").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.costGreen)
                    }
                if compaction.changes {
                    PointMark(x: .value("Window", compaction.current), y: .value("Over", nowOver))
                        .foregroundStyle(Color.red)
                        .symbolSize(50)
                        .annotation(position: .top) {
                            Text("+\(Int(nowOver.rounded()))%").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.red)
                        }
                }
            }
            // A little room past the edge so the window's label isn't clipped.
            .chartXScale(domain: (compaction.curve.first?.window ?? 0)...(max(compaction.modelWindow, compaction.current) * 103 / 100))
            .chartXAxis {
                AxisMarks(values: [compaction.curve.first?.window ?? 0, compaction.best, compaction.modelWindow]) { value in
                    AxisValueLabel {
                        if let window = value.as(Int.self) { Text(tokensK(window)) }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 110)

            Text(factLine(facts))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Text("A token estimate only: it doesn't measure how well Claude keeps the task after a compaction. The lower the window, the more often it compacts.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if compaction.changes {
                    let saved = compaction.cost - compaction.low
                    Badge(text: "\(Int((compaction.saving * 100).rounded()))% fewer tokens · \(compactTokens(Int(saved))) over the period · \(costText(saved * compaction.usdPerUnit))",
                          color: .dataAccent)
                    Spacer()
                    Button(copied ? "Copied" : "Copy setting") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\"autoCompactWindow\": \(compaction.best)", forType: .string)
                        copied = true
                    }
                    .help("Copies \"autoCompactWindow\": \(compaction.best) for ~/.claude/settings.json")
                } else {
                    Badge(text: "Already the leanest for how you work", color: .costGreen)
                    Spacer()
                }
            }
        }
    }

    private func factLine(_ f: ContextTuning.Facts) -> String {
        var text = "Your conversations grow \(compactTokens(f.growth)) a call"
        if f.compactions > 0 {
            text += "; a compaction leaves \(compactTokens(f.after)), and reading back what it dropped costs \(compactTokens(f.rework)). \(f.compactions) compaction\(f.compactions == 1 ? "" : "s") in the period."
        } else {
            text += ". No compactions in the period."
        }
        return text
    }
}

/// The prompt cache's lifetime: 5 minutes against an hour, on the period's
/// own gaps between calls.
struct CacheSection: View {
    let title: String
    let cache: ContextTuning.CacheLife

    var body: some View {
        let low = max(min(cache.short, cache.hour), 1)
        let options: [(String, Double)] = [("5 min", cache.short), ("1 hour", cache.hour)]
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text("Claude Code's default").font(.system(size: 11)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("NOW").font(.system(size: 10, weight: .semibold)).kerning(0.5).foregroundStyle(.tertiary)
                Text(cache.current).font(.system(size: 22, weight: .medium))
            }
            VStack(spacing: 6) {
                ForEach(options, id: \.0) { option in
                    let over = (option.1 / low - 1) * 100
                    HStack(spacing: 10) {
                        Text(option.0).font(.system(size: 12)).frame(width: 52, alignment: .leading)
                        UsageBarTinted(percent: min(100, option.1 / max(cache.short, cache.hour) * 100),
                                       color: over < 0.5 ? .costGreen : .clay)
                        Text(over < 0.5 ? "Leanest" : "+\(Int(over.rounded()))%")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(over < 0.5 ? Color.costGreen : Color.red)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
            Text("\(Int((cache.facts.quick * 100).rounded()))% of your calls came within 5 minutes of the one before, \(Int((cache.facts.pause * 100).rounded()))% after a pause of 5 to 60 minutes.")
                .font(.system(size: 12))
            if cache.best == cache.current {
                Badge(text: "Already the leanest for how you work", color: .costGreen)
            } else {
                Badge(text: "\(Int((cache.saving * 100).rounded()))% fewer tokens with \(cache.best) · \(costText((cache.currentCost - cache.bestCost) * cache.usdPerUnit))",
                      color: .dataAccent)
            }
        }
    }
}
