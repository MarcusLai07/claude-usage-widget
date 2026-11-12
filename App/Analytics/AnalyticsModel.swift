import Foundation
import SwiftUI

/// The stretch of Claude Code activity the token sections cover. The
/// allowances above them are always "now".
enum UsagePeriod: String, CaseIterable, Identifiable {
    case today, week, month, quarter, all, custom

    var id: String { rawValue }

    /// The Custom period's days, remembered across launches (start of the
    /// first day through the end of the last).
    static var customRange: ClosedRange<Date> {
        get {
            let defaults = UserDefaults.standard
            let calendar = Calendar.current
            let now = Date()
            let start = (defaults.object(forKey: "customPeriodStart") as? Double).map(Date.init(timeIntervalSince1970:))
                ?? calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now))!
            let end = (defaults.object(forKey: "customPeriodEnd") as? Double).map(Date.init(timeIntervalSince1970:))
                ?? now
            let lower = calendar.startOfDay(for: min(start, end))
            let upper = calendar.date(byAdding: DateComponents(day: 1, second: -1),
                                      to: calendar.startOfDay(for: max(start, end)))!
            return lower...upper
        }
        set {
            UserDefaults.standard.set(newValue.lowerBound.timeIntervalSince1970, forKey: "customPeriodStart")
            UserDefaults.standard.set(newValue.upperBound.timeIntervalSince1970, forKey: "customPeriodEnd")
        }
    }

    /// The period's span; every period but Custom runs to now.
    func range(now: Date = Date()) -> ClosedRange<Date> {
        if self == .custom { return Self.customRange }
        return since(now: now)...max(now, since(now: now))
    }

    /// Changes when the period's span does: memo key for summaries.
    var cacheKey: String {
        self == .custom
            ? "custom-\(Int(Self.customRange.lowerBound.timeIntervalSince1970))-\(Int(Self.customRange.upperBound.timeIntervalSince1970))"
            : rawValue
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        case .quarter: return "90 days"
        case .all: return "All"
        case .custom: return "Custom"
        }
    }

    func since(now: Date = Date()) -> Date {
        switch self {
        case .today: return Calendar.current.startOfDay(for: now)
        case .week: return now.addingTimeInterval(-7 * 86400)
        case .month: return now.addingTimeInterval(-30 * 86400)
        case .quarter: return now.addingTimeInterval(-90 * 86400)
        case .all: return .distantPast
        case .custom: return Self.customRange.lowerBound
        }
    }
}

/// Totals for the stat strips. Tokens count as Magpie counts them: fresh
/// input + output + cache reads + cache writes.
struct UsageTotals {
    var input = 0          // fresh (uncached) input
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var thinking = 0
    var requests = 0
    var failed = 0
    var sessions = 0
    /// ≈ USD at API list prices, of the priced calls.
    var cost: Double = 0
    var unpriced = 0
    /// Replies with a known duration, for output speed.
    var timedReplies = 0
    var timedOutput = 0
    var timedMs = 0

    var cache: Int { cacheRead + cacheWrite }
    var tokens: Int { input + output + cacheRead + cacheWrite }
    /// Share of the prompt served from cache.
    var cacheHitRate: Double {
        let prompt = input + cacheRead + cacheWrite
        return prompt > 0 ? Double(cacheRead) / Double(prompt) * 100 : 0
    }
    /// Rounded down to a tenth, so a failure never reads as 100%.
    var successRate: Double {
        guard requests > 0 else { return 100 }
        return (Double(requests - failed) / Double(requests) * 1000).rounded(.down) / 10
    }
    /// Output tokens per second across timed replies.
    var outputSpeed: Double? {
        timedMs > 0 ? Double(timedOutput) / (Double(timedMs) / 1000) : nil
    }

    mutating func add(_ sample: TokenSample) {
        input += sample.input
        output += sample.output
        cacheRead += sample.cacheRead
        cacheWrite += sample.cacheWrite
        thinking += sample.thinking
        requests += 1
        if sample.failed { failed += 1 }
        if let callCost = sample.cost { cost += callCost } else { unpriced += 1 }
        if let ms = sample.durationMs, ms > 0, sample.output > 0 {
            timedReplies += 1
            timedOutput += sample.output
            timedMs += ms
        }
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
    var cache = 0
    var requests = 0
    var failed = 0
    var sessions = 0
    var cost: Double = 0
    var share: Double = 0

    var tokens: Int { input + output + cache }
}

/// Tokens of one model in one bar of the activity chart.
struct ActivityBar: Identifiable {
    let start: Date
    let model: String
    var tokens: Int
    var cost: Double
    var requests: Int
    var id: String { "\(start.timeIntervalSince1970)-\(model)" }
}

/// Everything the token sections show for one period.
struct UsageOverview {
    let period: UsagePeriod
    let since: Date
    let until: Date
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

/// One Claude Code session, for the Sessions tab.
struct SessionSummary: Identifiable {
    let id: String
    let title: String?
    let project: String?
    let first: Date
    let last: Date
    let requests: Int
    let subagentRequests: Int
    let failed: Int
    let input: Int
    let output: Int
    let cache: Int
    let cost: Double
    /// The largest prompt the model saw in one request.
    let peakContext: Int
    /// Models by tokens, most first.
    let models: [(name: String, tokens: Int)]
    let apps: [String]

    /// In + out, as Magpie's Sessions page counts a session's tokens.
    var tokens: Int { input + output }
    var duration: TimeInterval { last.timeIntervalSince(first) }
}

/// Sessions of one project, most recent first.
struct ProjectSessions: Identifiable {
    let id: String
    let name: String
    let path: String?
    let sessions: [SessionSummary]
}

@MainActor
final class AnalyticsModel: ObservableObject {
    /// Every request in the local transcripts, oldest first.
    @Published private(set) var tokenSamples: [TokenSample] = []
    @Published var hasClaudeAccess = ClaudeFolderAccess.resolve() != nil
    /// Claude Desktop's folder, for its local-agent sessions (optional).
    @Published var hasDesktopAccess = ClaudeFolderAccess.resolve(ClaudeFolderAccess.claudeDesktop) != nil
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoaded: Date?
    /// Stable model → chart color assignment, by all-time share.
    @Published private(set) var modelColors: [String: Color] = [:]
    /// Session id → title, from the transcripts' title lines.
    @Published private(set) var sessionTitles: [String: String] = [:]
    /// Claude Code's auto-compact window setting, when set.
    @Published private(set) var compactSetting: Int?

    private var overviews: [String: (at: Date, overview: UsageOverview)] = [:]
    private var sessionLists: [String: (at: Date, projects: [ProjectSessions])] = [:]

    func grantAccess() {
        if ClaudeFolderAccess.requestAccess() != nil {
            hasClaudeAccess = true
            Task { await reload() }
        }
    }

    func grantDesktopAccess() {
        if ClaudeFolderAccess.requestAccess(ClaudeFolderAccess.claudeDesktop) != nil {
            hasDesktopAccess = true
            Task { await reload() }
        }
    }

    func revokeDesktopAccess() {
        ClaudeFolderAccess.revoke(ClaudeFolderAccess.claudeDesktop)
        hasDesktopAccess = false
        Task { await reload() }
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
        let desktop = ClaudeFolderAccess.resolve(ClaudeFolderAccess.claudeDesktop)
        hasDesktopAccess = desktop != nil
        let scanStarted = Date()
        let scan = await Task.detached(priority: .userInitiated) {
            let scoped = folder.startAccessingSecurityScopedResource()
            let desktopScoped = desktop?.startAccessingSecurityScopedResource() ?? false
            defer {
                if scoped { folder.stopAccessingSecurityScopedResource() }
                if desktopScoped { desktop?.stopAccessingSecurityScopedResource() }
            }
            var scan = TranscriptStats.scan(claudeFolder: folder, desktopFolder: desktop, since: .distantPast)
            scan.samples.sort { $0.ts < $1.ts }
            return (scan, ContextTuning.compactSetting(claudeFolder: folder))
        }.value
        PerfLog.record(source: "scan", started: scanStarted, error: nil)
        compactSetting = scan.1
        apply(scan.0)
    }

    /// Takes in a scan's requests (sorted oldest first) and session titles.
    func apply(_ scan: TranscriptScan) {
        tokenSamples = Self.fileBySessionFolder(scan.samples)
        sessionTitles = scan.titles
        overviews = [:]
        sessionLists = [:]
        var byModel: [String: Int] = [:]
        for sample in scan.samples where !sample.failed { byModel[sample.model, default: 0] += sample.tokens }
        let ordered = byModel.sorted { $0.value > $1.value }.map(\.key)
        modelColors = Dictionary(uniqueKeysWithValues: ordered.enumerated().map {
            ($0.element, modelPalette[$0.offset % modelPalette.count])
        })
        lastLoaded = Date()
    }

    /// The period's summary, reused for a minute (views ask on every draw).
    func overview(_ period: UsagePeriod) -> UsageOverview {
        let now = Date()
        if let cached = overviews[period.cacheKey], now.timeIntervalSince(cached.at) < 60 {
            return cached.overview
        }
        let overview = Self.summarize(tokenSamples, period: period, now: now)
        overviews[period.cacheKey] = (now, overview)
        return overview
    }

    /// Requests in a period, newest first (the Requests tab).
    func samples(in period: UsagePeriod) -> [TokenSample] {
        let range = period.range()
        return tokenSamples.reversed()
            .drop { $0.ts > range.upperBound }
            .prefix { $0.ts >= range.lowerBound }
            .map { $0 }
    }

    /// Sessions active in the period, grouped by project; both ordered by
    /// latest activity. Reused for a minute.
    func sessions(_ period: UsagePeriod) -> [ProjectSessions] {
        let now = Date()
        if let cached = sessionLists[period.cacheKey], now.timeIntervalSince(cached.at) < 60 {
            return cached.projects
        }
        let projects = Self.groupSessions(tokenSamples, titles: sessionTitles, range: period.range(now: now))
        sessionLists[period.cacheKey] = (now, projects)
        return projects
    }

    nonisolated static func groupSessions(_ all: [TokenSample], titles: [String: String],
                                          range: ClosedRange<Date>) -> [ProjectSessions] {
        struct Acc {
            var project: String?
            var first: Date
            var last: Date
            var requests = 0, subagent = 0, failed = 0, input = 0, output = 0, cache = 0, peak = 0
            var cost: Double = 0
            var models: [String: Int] = [:]
            var apps: Set<String> = []
        }
        // Whole sessions: every request of a session active in the period.
        let active = Set(all.lazy.filter { range.contains($0.ts) }.map(\.sessionID))
        var bySession: [String: Acc] = [:]
        for sample in all where active.contains(sample.sessionID) {
            var acc = bySession[sample.sessionID]
                ?? Acc(project: projectPath(sample.project), first: sample.ts, last: sample.ts)
            acc.first = min(acc.first, sample.ts)
            acc.last = max(acc.last, sample.ts)
            acc.requests += 1
            if sample.isSidechain { acc.subagent += 1 }
            if sample.failed { acc.failed += 1 }
            acc.input += sample.input
            acc.output += sample.output
            acc.cache += sample.cacheRead + sample.cacheWrite
            acc.cost += sample.cost ?? 0
            acc.peak = max(acc.peak, sample.context)
            if !sample.failed { acc.models[sample.model, default: 0] += sample.tokens }
            acc.apps.insert(appName(appKey(sample.app)))
            if acc.project == nil { acc.project = projectPath(sample.project) }
            bySession[sample.sessionID] = acc
        }
        let sessions = bySession.map { id, acc in
            SessionSummary(id: id, title: titles[id], project: acc.project,
                           first: acc.first, last: acc.last, requests: acc.requests,
                           subagentRequests: acc.subagent, failed: acc.failed,
                           input: acc.input, output: acc.output, cache: acc.cache, cost: acc.cost,
                           peakContext: acc.peak,
                           models: acc.models.sorted { $0.value > $1.value }.map { ($0.key, $0.value) },
                           apps: acc.apps.sorted())
        }
        let byProject = Dictionary(grouping: sessions) { $0.project ?? "—" }
        return byProject.map { key, sessions in
            ProjectSessions(id: key,
                            name: key == "—" ? "Unknown folder" : projectName(key),
                            path: key == "—" ? nil : abbreviateHome(key),
                            sessions: sessions.sorted { $0.last > $1.last })
        }
        .sorted { ($0.sessions.first?.last ?? .distantPast) > ($1.sessions.first?.last ?? .distantPast) }
    }

    /// Files every call of a session under the folder the session started
    /// in, as Magpie does: a session that changes into a subfolder stays one
    /// project rather than spreading over several.
    nonisolated static func fileBySessionFolder(_ samples: [TokenSample]) -> [TokenSample] {
        var startFolder: [String: String] = [:]
        for sample in samples {
            guard startFolder[sample.sessionID] == nil, let project = sample.project, !project.isEmpty else { continue }
            startFolder[sample.sessionID] = project
        }
        return samples.map { sample in
            guard let folder = startFolder[sample.sessionID], folder != sample.project else { return sample }
            return sample.with(project: folder)
        }
    }

    // MARK: Summaries

    nonisolated static func summarize(_ all: [TokenSample], period: UsagePeriod, now: Date) -> UsageOverview {
        let range = period.range(now: now)
        let since = range.lowerBound
        let start = all.firstIndex { $0.ts >= since } ?? all.endIndex
        let end = all.lastIndex { $0.ts <= range.upperBound }.map { $0 + 1 } ?? start
        let samples = all[start..<max(start, end)]

        var totals = UsageTotals()
        var sessions = Set<String>()
        var apps: [String: (row: BreakdownRow, sessions: Set<String>)] = [:]
        var models: [String: (row: BreakdownRow, sessions: Set<String>)] = [:]
        var projects: [String: (row: BreakdownRow, sessions: Set<String>)] = [:]

        func add(_ sample: TokenSample, to table: inout [String: (row: BreakdownRow, sessions: Set<String>)],
                 key: String, name: String, detail: String?) {
            var entry = table[key] ?? (BreakdownRow(id: key, name: name, detail: detail), [])
            entry.row.input += sample.input
            entry.row.output += sample.output
            entry.row.cache += sample.cacheRead + sample.cacheWrite
            entry.row.cost += sample.cost ?? 0
            entry.row.requests += 1
            if sample.failed { entry.row.failed += 1 }
            entry.sessions.insert(sample.sessionID)
            table[key] = entry
        }

        for sample in samples {
            totals.add(sample)
            sessions.insert(sample.sessionID)

            let app = appKey(sample.app)
            add(sample, to: &apps, key: app, name: appName(app), detail: nil)
            if !sample.failed {
                add(sample, to: &models, key: sample.model, name: sample.model, detail: nil)
            }
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
        let span = min(now, range.upperBound).timeIntervalSince(max(since, first))
        let unit: Calendar.Component = span <= 2 * 86400 ? .hour : (span <= 62 * 86400 ? .day : .weekOfYear)
        var buckets: [String: ActivityBar] = [:]
        var perBar: [Date: Int] = [:]
        for sample in samples where !sample.failed {
            let barStart = calendar.dateInterval(of: unit, for: sample.ts)?.start ?? sample.ts
            let key = "\(barStart.timeIntervalSince1970)-\(sample.model)"
            var bar = buckets[key] ?? ActivityBar(start: barStart, model: sample.model, tokens: 0, cost: 0, requests: 0)
            bar.tokens += sample.tokens
            bar.cost += sample.cost ?? 0
            bar.requests += 1
            buckets[key] = bar
            perBar[barStart, default: 0] += sample.tokens
        }
        let peak = perBar.max { $0.value < $1.value }.map { (start: $0.key, tokens: $0.value) }

        return UsageOverview(
            period: period, since: since, until: range.upperBound, totals: totals,
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
        case "local-agent": return "Desktop agent"
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
        case "local-agent": return "sparkles"
        default: return "questionmark.app"
        }
    }

    /// A worktree counts toward the repository it was made from; Claude
    /// Desktop's local-agent sessions (each in a scratch folder of its own)
    /// count as one project, Claude Desktop.
    nonisolated static func projectPath(_ cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        if let range = cwd.range(of: "/local-agent-mode-sessions/") {
            return String(cwd[..<range.lowerBound])
        }
        if let range = cwd.range(of: "/.claude/worktrees/") {
            return String(cwd[..<range.lowerBound])
        }
        return cwd
    }

    /// The user's real home folder. In the sandbox `NSHomeDirectory()` is
    /// the app's container, but transcripts record real paths.
    nonisolated static var realHome: String { ClaudeFolderAccess.realHome.path }

    nonisolated static func projectName(_ path: String) -> String {
        if path == realHome { return "~" }
        if path.hasSuffix("/Application Support/Claude") { return "Claude Desktop" }
        return (path as NSString).lastPathComponent
    }

    nonisolated static func abbreviateHome(_ path: String) -> String {
        path.hasPrefix(realHome) ? "~" + path.dropFirst(realHome.count) : path
    }
}
