import SwiftUI
import Charts

// MARK: - Derived data

/// Which surface a session ran in, as Magpie's Sessions filter splits them.
enum SessionAppGroup: String, CaseIterable, Identifiable {
    case all, code, desktop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .code: return "Claude Code"
        case .desktop: return "Claude Desktop"
        }
    }

    func contains(appKey: String) -> Bool {
        switch self {
        case .all: return true
        case .desktop: return appKey == "claude-desktop" || appKey == "local-agent"
        case .code: return !(appKey == "claude-desktop" || appKey == "local-agent")
        }
    }
}

enum SessionDayMetric: String, CaseIterable, Identifiable {
    case tokens, output, messages, sessions, cost, active
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tokens: return "Tokens"
        case .output: return "Output tokens"
        case .messages: return "Messages"
        case .sessions: return "Sessions"
        case .cost: return "Cost"
        case .active: return "Active"
        }
    }
}

enum TopSessionMetric: String, CaseIterable, Identifiable {
    case tokens, cost, active
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// One session's activity inside the period.
struct SessionStat: Identifiable {
    let id: String
    var title: String?
    var project: String?
    var appKey = ""
    var model = ""
    var first: Date
    var last: Date
    var requests = 0
    var input = 0
    var output = 0
    var cacheRead = 0
    var prompt = 0
    var cost: Double = 0
    /// Time between consecutive requests, gaps over 10 minutes left out.
    var active: TimeInterval = 0
    /// In + out, as Magpie's Sessions page counts a session's tokens.
    var tokens: Int { input + output }
}

struct SessionDay: Identifiable {
    let start: Date
    var tokens = 0
    var output = 0
    var messages = 0
    var sessions = Set<String>()
    var cost: Double = 0
    var active: TimeInterval = 0
    var id: Date { start }
}

struct SessionsDerived {
    struct Filters: Hashable {
        var group: SessionAppGroup = .all
        var model: String?
        var folder: String?
    }

    var sessions: [SessionStat] = []
    var days: [SessionDay] = []
    var projects: [BreakdownRow] = []
    var models: [BreakdownRow] = []
    /// [weekday, Monday first][hour] → requests.
    var hours: [[Double]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    var busiest: (weekday: Int, hour: Int)?
    var input = 0
    var output = 0
    var cacheRead = 0
    var prompt = 0
    var cost: Double = 0
    var active: TimeInterval = 0
    var activeDays = 0
    var median = 0
    var p90 = 0
    var folders: [(path: String, name: String)] = []
    var modelOptions: [String] = []

    /// Idle gaps longer than this end a stretch of activity.
    static let idleGap: TimeInterval = 10 * 60

    static func make(samples periodSamples: [TokenSample], titles: [String: String],
                     filters f: Filters) -> SessionsDerived {
        var out = SessionsDerived()
        var folderNames: [String: String] = [:]
        var modelSet = Set<String>()
        for sample in periodSamples where !sample.failed {
            modelSet.insert(sample.model)
            if let path = AnalyticsModel.projectPath(sample.project) {
                folderNames[path] = AnalyticsModel.projectName(path)
            }
        }
        out.folders = folderNames.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
            .map { ($0.key, $0.value) }
        out.modelOptions = modelSet.sorted()

        let samples = periodSamples.filter { sample in
            if !f.group.contains(appKey: AnalyticsModel.appKey(sample.app)) { return false }
            if let model = f.model, sample.model != model { return false }
            if let folder = f.folder, AnalyticsModel.projectPath(sample.project) != folder { return false }
            return true
        }.sorted { $0.ts < $1.ts }

        let calendar = Calendar.current
        var stats: [String: SessionStat] = [:]
        var lastSeen: [String: Date] = [:]
        var days: [Date: SessionDay] = [:]
        var projectRows: [String: (row: BreakdownRow, sessions: Set<String>)] = [:]
        var modelRows: [String: (row: BreakdownRow, sessions: Set<String>)] = [:]
        var modelTally: [String: [String: Int]] = [:]
        var appTally: [String: [String: Int]] = [:]
        let mondayFirst = DailyHeatmap.mondayCalendar

        for sample in samples {
            var stat = stats[sample.sessionID] ?? SessionStat(
                id: sample.sessionID, title: titles[sample.sessionID],
                project: AnalyticsModel.projectPath(sample.project), first: sample.ts, last: sample.ts)
            stat.requests += 1
            stat.input += sample.input
            stat.output += sample.output
            stat.cacheRead += sample.cacheRead
            stat.prompt += sample.context
            stat.cost += sample.cost ?? 0
            stat.last = max(stat.last, sample.ts)
            var gap: TimeInterval = 0
            if let previous = lastSeen[sample.sessionID] {
                let elapsed = sample.ts.timeIntervalSince(previous)
                if elapsed > 0 && elapsed <= idleGap { gap = elapsed }
            }
            stat.active += gap
            lastSeen[sample.sessionID] = sample.ts
            if !sample.failed {
                modelTally[sample.sessionID, default: [:]][sample.model, default: 0] += sample.input + sample.output
            }
            appTally[sample.sessionID, default: [:]][AnalyticsModel.appKey(sample.app), default: 0] += 1
            stats[sample.sessionID] = stat

            let day = calendar.startOfDay(for: sample.ts)
            var dayStat = days[day] ?? SessionDay(start: day)
            dayStat.tokens += sample.input + sample.output
            dayStat.output += sample.output
            dayStat.messages += 1
            dayStat.sessions.insert(sample.sessionID)
            dayStat.cost += sample.cost ?? 0
            dayStat.active += gap
            days[day] = dayStat

            let weekday = (mondayFirst.component(.weekday, from: sample.ts) + 5) % 7   // Monday = 0
            out.hours[weekday][calendar.component(.hour, from: sample.ts)] += 1

            func add(_ table: inout [String: (row: BreakdownRow, sessions: Set<String>)], key: String, name: String, detail: String?) {
                var entry = table[key] ?? (BreakdownRow(id: key, name: name, detail: detail), [])
                entry.row.input += sample.input
                entry.row.output += sample.output
                entry.row.cost += sample.cost ?? 0
                entry.row.requests += 1
                if sample.failed { entry.row.failed += 1 }
                entry.sessions.insert(sample.sessionID)
                table[key] = entry
            }
            let path = AnalyticsModel.projectPath(sample.project)
            add(&projectRows, key: path ?? "—", name: path.map(AnalyticsModel.projectName) ?? "Unknown folder",
                detail: path.map(AnalyticsModel.abbreviateHome))
            if !sample.failed { add(&modelRows, key: sample.model, name: sample.model, detail: nil) }

            out.input += sample.input
            out.output += sample.output
            out.cacheRead += sample.cacheRead
            out.prompt += sample.context
            out.cost += sample.cost ?? 0
            out.active += gap
        }

        for (id, var stat) in stats {
            stat.model = modelTally[id]?.max { $0.value < $1.value }?.key ?? ""
            stat.appKey = appTally[id]?.max { $0.value < $1.value }?.key ?? ""
            stats[id] = stat
        }
        out.sessions = stats.values.sorted { $0.tokens > $1.tokens }
        out.days = days.values.sorted { $0.start < $1.start }
        out.activeDays = days.count
        let sortedTokens = out.sessions.map(\.tokens).sorted()
        if !sortedTokens.isEmpty {
            out.median = sortedTokens[sortedTokens.count / 2]
            out.p90 = sortedTokens[min(sortedTokens.count - 1, Int(Double(sortedTokens.count) * 0.9))]
        }
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
        out.projects = rows(projectRows)
        out.models = rows(modelRows)
        var best: (Int, Int, Double)?
        for day in 0..<7 { for hour in 0..<24 where out.hours[day][hour] > (best?.2 ?? 0) {
            best = (day, hour, out.hours[day][hour])
        } }
        out.busiest = best.map { ($0.0, $0.1) }
        return out
    }
}

// MARK: - Sessions page

/// Usage › Sessions, as Magpie lays it out: filters, the stat strip, By day,
/// Projects and Models, By hour, Top sessions, then every session by
/// project. Clicking a session opens its requests.
struct SessionsView: View {
    @ObservedObject var analytics: AnalyticsModel
    let period: UsagePeriod
    /// Opens the Requests tab filtered to a session.
    var openSession: (String) -> Void

    @State private var filters = SessionsDerived.Filters()
    @State private var derived: SessionsDerived?
    @AppStorage("sessionDayMetric") private var dayMetric: SessionDayMetric = .tokens
    @AppStorage("topSessionMetric") private var topMetric: TopSessionMetric = .tokens

    private var key: String {
        "\(period.cacheKey)|\(filters.hashValue)|\(analytics.lastLoaded?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        TranscriptGate(analytics: analytics) {
            VStack(alignment: .leading, spacing: 14) {
                filterBar
                if let derived {
                    if derived.sessions.isEmpty {
                        EmptyStateView(icon: "tray", title: "No sessions in this period",
                                       message: "Claude Code sessions on this Mac appear here.")
                            .designCard()
                    } else {
                        stats(derived)
                        byDay(derived)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 14) {
                                projectsList(derived)
                                modelsList(derived)
                            }
                            VStack(spacing: 14) {
                                projectsList(derived)
                                modelsList(derived)
                            }
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 14) {
                                byHour(derived).frame(minWidth: 420)
                                topSessions(derived).frame(minWidth: 380)
                            }
                            VStack(spacing: 14) {
                                byHour(derived)
                                topSessions(derived)
                            }
                        }
                        allSessions
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
        }
        .task(id: key) { await recompute() }
    }

    private func recompute() async {
        let samples = analytics.samples(in: period)
        let titles = analytics.sessionTitles
        let f = filters
        derived = await Task.detached(priority: .userInitiated) {
            SessionsDerived.make(samples: samples, titles: titles, filters: f)
        }.value
    }

    // MARK: Filters

    private var filterBar: some View {
        HStack(spacing: 8) {
            PillTabs(options: SessionAppGroup.allCases.map { ($0, $0.title) }, selection: $filters.group, size: 12)
            Menu {
                Picker("Model", selection: $filters.model) {
                    Text("All models").tag(String?.none)
                    ForEach(derived?.modelOptions ?? [], id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(filters.model ?? "All models").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.track, in: RoundedRectangle(cornerRadius: 7))
            Menu {
                Picker("Folder", selection: $filters.folder) {
                    Text("All folders").tag(String?.none)
                    ForEach(derived?.folders ?? [], id: \.path) { folder in
                        Text(folder.name).tag(Optional(folder.path))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(filters.folder.map(AnalyticsModel.projectName) ?? "All folders").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.track, in: RoundedRectangle(cornerRadius: 7))
            Spacer()
        }
    }

    // MARK: Stat strip

    private func stats(_ d: SessionsDerived) -> some View {
        let hitRate = d.prompt > 0 ? Double(d.cacheRead) / Double(d.prompt) * 100 : 0
        let top = d.projects.first
        return StatStripPanel {
            StatTile(label: "Sessions", value: d.sessions.count.formatted(),
                     caption: "median \(compactTokens(d.median)) · p90 \(compactTokens(d.p90))")
            TileDivider()
            StatTile(label: "Tokens", value: compactTokens(d.input + d.output),
                     caption: "\(compactTokens(d.input)) in · \(compactTokens(d.output)) out")
            TileDivider()
            StatTile(label: "Cost", value: costText(d.cost), caption: "at API list prices", valueColor: .costGreen)
            TileDivider()
            StatTile(label: "Cache read", value: compactTokens(d.cacheRead),
                     caption: "hit rate \(Int(hitRate.rounded()))%")
            TileDivider()
            StatTile(label: "Active", value: activeText(d.active),
                     caption: "on \(d.activeDays) day\(d.activeDays == 1 ? "" : "s")")
            TileDivider()
            StatTile(label: "Projects", value: d.projects.count.formatted(),
                     caption: top.map { "\(Int($0.share.rounded()))% in \($0.name)" })
        }
    }

    private func activeText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: By day

    private func dayValue(_ day: SessionDay) -> Double {
        switch dayMetric {
        case .tokens: return Double(day.tokens)
        case .output: return Double(day.output)
        case .messages: return Double(day.messages)
        case .sessions: return Double(day.sessions.count)
        case .cost: return day.cost
        case .active: return day.active / 3600
        }
    }

    private func dayFormat(_ value: Double) -> String {
        switch dayMetric {
        case .tokens, .output: return compactTokens(Int(value))
        case .messages, .sessions: return Int(value).formatted()
        case .cost: return costText(value, approximate: false)
        case .active: return String(format: "%.1fh", value)
        }
    }

    private func byDay(_ d: SessionsDerived) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SectionLabel("By day")
                PillTabs(options: SessionDayMetric.allCases.map { ($0, $0.title) }, selection: $dayMetric, size: 11.5)
                Spacer()
                if let peak = d.days.map(dayValue).max() {
                    Text(dayFormat(peak)).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Chart(d.days) { day in
                BarMark(x: .value("Day", day.start, unit: .day), y: .value(dayMetric.title, dayValue(day)))
                    .foregroundStyle(Color.dataAccent)
                    .cornerRadius(2)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 120)
        }
        .designCard()
    }

    // MARK: Lists

    private func projectsList(_ d: SessionsDerived) -> some View {
        BarListPanel(title: "Projects", rows: d.projects, limit: 6, color: { _ in .dataAccent })
            .frame(minWidth: 320)
    }

    private func modelsList(_ d: SessionsDerived) -> some View {
        BarListPanel(title: "Models", rows: d.models, limit: 6,
                     color: { analytics.modelColors[$0.id] ?? .dataAccent })
            .frame(minWidth: 320)
    }

    // MARK: By hour

    private func byHour(_ d: SessionsDerived) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("By hour")
                Spacer()
                Text(TimeZone.current.identifier).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            HourHeatmap(grid: d.hours, describe: { "\(Int($0)) request\(Int($0) == 1 ? "" : "s")" })
            HStack {
                if let busiest = d.busiest {
                    Text("Busiest at \(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][busiest.weekday]) \(String(format: "%02d:00", busiest.hour))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HeatLegend()
            }
        }
        .designCard()
    }

    // MARK: Top sessions

    private func topValue(_ session: SessionStat) -> Double {
        switch topMetric {
        case .tokens: return Double(session.tokens)
        case .cost: return session.cost
        case .active: return session.active
        }
    }

    private func topSessions(_ d: SessionsDerived) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Top sessions")
                Spacer()
                PillTabs(options: TopSessionMetric.allCases.map { ($0, $0.title) }, selection: $topMetric, size: 11.5)
            }
            VStack(spacing: 2) {
                ForEach(d.sessions.sorted { topValue($0) > topValue($1) }.prefix(8)) { session in
                    Button { openSession(session.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: AnalyticsModel.appIcon(session.appKey))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.clay)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title ?? "Session \(session.id.prefix(8))")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .lineLimit(1)
                                Text(meta(session))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(topText(session))
                                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(topMetric == .cost ? Color.costGreen : Color.primary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show this session's requests")
                }
            }
        }
        .designCard()
    }

    private func topText(_ session: SessionStat) -> String {
        switch topMetric {
        case .tokens: return compactTokens(session.tokens)
        case .cost: return costText(session.cost)
        case .active: return activeText(session.active)
        }
    }

    /// "SCM-Portal · VS Code · Opus 5.5 · 3 weeks ago"
    private func meta(_ session: SessionStat) -> String {
        var parts: [String] = []
        if let project = session.project { parts.append(AnalyticsModel.projectName(project)) }
        parts.append(AnalyticsModel.appName(session.appKey))
        if !session.model.isEmpty { parts.append(session.model) }
        parts.append(session.last.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }

    // MARK: Every session

    private var allSessions: some View {
        let projects = analytics.sessions(period).compactMap { project -> ProjectSessions? in
            if let folder = filters.folder, project.id != folder { return nil }
            let sessions = project.sessions.filter { session in
                let desktop = session.apps.contains("Claude Desktop") || session.apps.contains("Desktop agent")
                switch filters.group {
                case .all: break
                case .desktop: if !desktop { return false }
                case .code: if desktop && session.apps.count == 1 { return false }
                }
                if let model = filters.model, !session.models.contains(where: { $0.name == model }) { return false }
                return true
            }
            return sessions.isEmpty ? nil : ProjectSessions(id: project.id, name: project.name,
                                                            path: project.path, sessions: sessions)
        }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("All sessions")
            ForEach(projects) { project in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        CardTitle(project.name)
                        if let path = project.path, path != project.name {
                            Text(path)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 6)
                    ForEach(project.sessions) { session in
                        Divider()
                        SessionRow(session: session, colors: analytics.modelColors) {
                            openSession(session.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .designCard()
            }
        }
        .padding(.top, 6)
    }
}

struct SessionRow: View {
    let session: SessionSummary
    let colors: [String: Color]
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.title ?? "Session \(session.id.prefix(8))")
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 12)
                    Text(compactTokens(session.tokens))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    Text(costText(session.cost))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.costGreen)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(detailLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    ForEach(session.models.prefix(3), id: \.name) { model in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colors[model.name] ?? .gray)
                                .frame(width: 6, height: 6)
                            Text(model.name)
                            if session.models.count > 1 {
                                Text("\(share(model.tokens))%")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    if !session.apps.isEmpty {
                        Text(session.apps.joined(separator: " · "))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background(hovering ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show this session's requests")
    }

    /// "Nov 12, 13:05 → 15:20 · 2 h 15 min · 196 requests (12 by agents) · peak context 180K"
    private var detailLine: String {
        let start = shortDateTime(session.first)
        let sameDay = Calendar.current.isDate(session.first, inSameDayAs: session.last)
        let end = sameDay ? session.last.formatted(.dateTime.hour().minute()) : shortDateTime(session.last)
        var parts = ["\(start) → \(end)"]
        if session.duration >= 60 {
            parts.append(Duration.seconds(session.duration)
                .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
        }
        var requests = "\(session.requests.formatted()) request\(session.requests == 1 ? "" : "s")"
        if session.subagentRequests > 0 { requests += " (\(session.subagentRequests) by agents)" }
        parts.append(requests)
        parts.append("peak context \(compactTokens(session.peakContext))")
        return parts.joined(separator: " · ")
    }

    private func share(_ tokens: Int) -> Int {
        let total = max(session.models.reduce(0) { $0 + $1.tokens }, 1)
        return Int((Double(tokens) / Double(total) * 100).rounded())
    }
}
