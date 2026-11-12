import Foundation
import SwiftUI

/// The stretch of Claude Code activity the token sections cover. The
/// allowances above them are always "now".
enum UsagePeriod: String, CaseIterable, Identifiable {
    case today, week, month, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        case .all: return "All"
        }
    }

    func since(now: Date = Date()) -> Date {
        switch self {
        case .today: return Calendar.current.startOfDay(for: now)
        case .week: return now.addingTimeInterval(-7 * 86400)
        case .month: return now.addingTimeInterval(-30 * 86400)
        case .all: return .distantPast
        }
    }
}

/// Totals for the stat strip.
struct UsageTotals {
    var input = 0          // fresh input + cache writes
    var output = 0
    var cacheRead = 0
    var thinking = 0
    var requests = 0
    var sessions = 0

    var tokens: Int { input + output }
    /// Share of the prompt served from cache.
    var cacheHitRate: Double {
        let prompt = input + cacheRead
        return prompt > 0 ? Double(cacheRead) / Double(prompt) * 100 : 0
    }
}

/// One row of a breakdown list (an app, a model or a project).
struct BreakdownRow: Identifiable {
    let id: String
    let name: String
    /// Shown on hover: a project's full path.
    let detail: String?
    var input = 0
    var output = 0
    var requests = 0
    var sessions = 0
    var share: Double = 0

    var tokens: Int { input + output }
}

/// Tokens of one model in one bar of the activity chart.
struct ActivityBar: Identifiable {
    let start: Date
    let model: String
    let tokens: Int
    var id: String { "\(start.timeIntervalSince1970)-\(model)" }
}

/// Everything the token sections show for one period.
struct UsageOverview {
    let period: UsagePeriod
    let since: Date
    let totals: UsageTotals
    let bars: [ActivityBar]
    /// .hour for Today, .day up to two months, else .weekOfYear.
    let barUnit: Calendar.Component
    let peak: (start: Date, tokens: Int)?
    let apps: [BreakdownRow]
    let models: [BreakdownRow]
    let projects: [BreakdownRow]

    var isEmpty: Bool { totals.requests == 0 }
}

@MainActor
final class AnalyticsModel: ObservableObject {
    /// Every request in the local transcripts, oldest first.
    @Published private(set) var tokenSamples: [TokenSample] = []
    @Published var hasClaudeAccess = ClaudeFolderAccess.resolve() != nil
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoaded: Date?
    /// Stable model → chart color assignment, by all-time share.
    @Published private(set) var modelColors: [String: Color] = [:]

    private var overviews: [UsagePeriod: (at: Date, overview: UsageOverview)] = [:]

    func grantAccess() {
        if ClaudeFolderAccess.requestAccess() != nil {
            hasClaudeAccess = true
            Task { await reload() }
        }
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let folder = ClaudeFolderAccess.resolve() else {
            hasClaudeAccess = false
            lastLoaded = Date()
            return
        }
        hasClaudeAccess = true
        let scanStarted = Date()
        let samples = await Task.detached(priority: .userInitiated) {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            return TranscriptStats.collectSamples(claudeFolder: folder, since: .distantPast)
                .sorted { $0.ts < $1.ts }
        }.value
        PerfLog.record(source: "scan", started: scanStarted, error: nil)

        tokenSamples = samples
        overviews = [:]
        var byModel: [String: Int] = [:]
        for sample in samples { byModel[sample.model, default: 0] += sample.billable }
        let ordered = byModel.sorted { $0.value > $1.value }.map(\.key)
        modelColors = Dictionary(uniqueKeysWithValues: ordered.enumerated().map {
            ($0.element, modelPalette[$0.offset % modelPalette.count])
        })
        lastLoaded = Date()
    }

    /// The period's summary, reused for a minute (views ask on every draw).
    func overview(_ period: UsagePeriod) -> UsageOverview {
        let now = Date()
        if let cached = overviews[period], now.timeIntervalSince(cached.at) < 60 {
            return cached.overview
        }
        let overview = Self.summarize(tokenSamples, period: period, now: now)
        overviews[period] = (now, overview)
        return overview
    }

    /// Requests in a period, newest first (the Requests tab).
    func samples(in period: UsagePeriod) -> [TokenSample] {
        let since = period.since()
        return tokenSamples.reversed().prefix { $0.ts >= since }.map { $0 }
    }

    // MARK: Summaries

    nonisolated static func summarize(_ all: [TokenSample], period: UsagePeriod, now: Date) -> UsageOverview {
        let since = period.since(now: now)
        let start = all.firstIndex { $0.ts >= since } ?? all.endIndex
        let samples = all[start...]

        var totals = UsageTotals()
        var sessions = Set<String>()
        var apps: [String: (row: BreakdownRow, sessions: Set<String>)] = [:]
        var models: [String: (row: BreakdownRow, sessions: Set<String>)] = [:]
        var projects: [String: (row: BreakdownRow, sessions: Set<String>)] = [:]

        func add(_ sample: TokenSample, to table: inout [String: (row: BreakdownRow, sessions: Set<String>)],
                 key: String, name: String, detail: String?) {
            var entry = table[key] ?? (BreakdownRow(id: key, name: name, detail: detail), [])
            entry.row.input += sample.inputTotal
            entry.row.output += sample.output
            entry.row.requests += 1
            entry.sessions.insert(sample.sessionID)
            table[key] = entry
        }

        for sample in samples {
            totals.input += sample.inputTotal
            totals.output += sample.output
            totals.cacheRead += sample.cacheRead
            totals.thinking += sample.thinking
            totals.requests += 1
            sessions.insert(sample.sessionID)

            let app = appKey(sample.app)
            add(sample, to: &apps, key: app, name: appName(app), detail: nil)
            add(sample, to: &models, key: sample.model, name: sample.model, detail: nil)
            let project = projectPath(sample.project)
            add(sample, to: &projects, key: project ?? "—",
                name: project.map(projectName) ?? "Unknown folder", detail: project.map(abbreviateHome))
        }
        totals.sessions = sessions.count

        func rows(_ table: [String: (row: BreakdownRow, sessions: Set<String>)]) -> [BreakdownRow] {
            let total = max(table.values.reduce(0) { $0 + $1.row.tokens }, 1)
            return table.values.map { entry in
                var row = entry.row
                row.sessions = entry.sessions.count
                row.share = Double(row.tokens) / Double(total) * 100
                return row
            }
            .sorted { $0.tokens > $1.tokens }
        }

        // Bars: hours today, days up to two months, else weeks.
        let calendar = Calendar.current
        let first = samples.first?.ts ?? now
        let span = now.timeIntervalSince(max(since, first))
        let unit: Calendar.Component = period == .today ? .hour : (span <= 62 * 86400 ? .day : .weekOfYear)
        var buckets: [String: ActivityBar] = [:]
        var perBar: [Date: Int] = [:]
        for sample in samples {
            let barStart = calendar.dateInterval(of: unit, for: sample.ts)?.start ?? sample.ts
            let key = "\(barStart.timeIntervalSince1970)-\(sample.model)"
            let tokens = (buckets[key]?.tokens ?? 0) + sample.billable
            buckets[key] = ActivityBar(start: barStart, model: sample.model, tokens: tokens)
            perBar[barStart, default: 0] += sample.billable
        }
        let peak = perBar.max { $0.value < $1.value }.map { (start: $0.key, tokens: $0.value) }

        return UsageOverview(
            period: period, since: since, totals: totals,
            bars: buckets.values.sorted { $0.start < $1.start },
            barUnit: unit, peak: peak,
            apps: rows(apps), models: rows(models), projects: rows(projects)
        )
    }

    // MARK: Names

    nonisolated static func appKey(_ entrypoint: String?) -> String {
        guard let entrypoint, !entrypoint.isEmpty else { return "other" }
        if entrypoint.hasPrefix("sdk") { return "sdk" }
        return entrypoint
    }

    nonisolated static func appName(_ key: String) -> String {
        switch key {
        case "claude-desktop": return "Claude Desktop"
        case "claude-vscode": return "VS Code"
        case "claude-jetbrains": return "JetBrains"
        case "cli": return "Terminal"
        case "sdk": return "Agent SDK"
        case "other": return "Other"
        default: return key
        }
    }

    nonisolated static func appIcon(_ key: String) -> String {
        switch key {
        case "claude-desktop": return "macwindow"
        case "claude-vscode", "claude-jetbrains": return "chevron.left.forwardslash.chevron.right"
        case "cli": return "terminal"
        case "sdk": return "shippingbox"
        default: return "questionmark.app"
        }
    }

    /// A worktree counts toward the repository it was made from.
    nonisolated static func projectPath(_ cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        if let range = cwd.range(of: "/.claude/worktrees/") {
            return String(cwd[..<range.lowerBound])
        }
        return cwd
    }

    /// The user's real home folder. In the sandbox `NSHomeDirectory()` is
    /// the app's container, but transcripts record real paths.
    nonisolated static let realHome: String = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }()

    nonisolated static func projectName(_ path: String) -> String {
        if path == realHome { return "~" }
        return (path as NSString).lastPathComponent
    }

    nonisolated static func abbreviateHome(_ path: String) -> String {
        path.hasPrefix(realHome) ? "~" + path.dropFirst(realHome.count) : path
    }
}
