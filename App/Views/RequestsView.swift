import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

/// Shows its content once transcripts are readable and scanned; otherwise
/// the grant-access or scanning state, as a card.
struct TranscriptGate<Content: View>: View {
    @ObservedObject var analytics: AnalyticsModel
    @ViewBuilder var content: () -> Content

    var body: some View {
        if !analytics.hasClaudeAccess {
            EmptyStateView(icon: "folder",
                           title: "Grant access to see token usage",
                           message: "Claude Usage reads transcript files in ~/.claude to count tokens by app, model and project. This stays on your Mac.",
                           actionLabel: "Grant Access to ~/.claude…",
                           action: { analytics.grantAccess() })
                .designCard()
        } else if analytics.lastLoaded == nil || (analytics.isLoading && analytics.tokenSamples.isEmpty) {
            VStack(spacing: 10) {
                ProgressView()
                Text("Scanning transcripts…")
                    .font(.system(size: 13, weight: .semibold))
                Text("The first scan reads all of ~/.claude once; later ones only read what changed.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .designCard()
        } else {
            content()
        }
    }
}

/// One request as the ledger shows it.
struct RequestRow: Identifiable {
    let id: String
    let ts: Date
    let app: String
    let appKey: String
    let projectName: String
    let projectPath: String
    /// The model's name; "" for a failed call.
    let modelKey: String
    let model: String
    let effort: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    /// Cache reads and writes.
    let cache: Int
    let cost: Double
    /// "" when it succeeded; the API error code when it failed.
    let status: String
    let thinking: Int
    let context: Int
    let sessionID: String
    let isSubagent: Bool
    let durationMs: Int?

    /// Output tokens per second, when timed.
    var speed: Double? {
        guard let durationMs, durationMs > 0, output > 0 else { return nil }
        return Double(output) / (Double(durationMs) / 1000)
    }

    init(_ sample: TokenSample) {
        id = sample.id
        ts = sample.ts
        appKey = AnalyticsModel.appKey(sample.app)
        app = AnalyticsModel.appName(appKey)
        let path = AnalyticsModel.projectPath(sample.project)
        projectName = path.map(AnalyticsModel.projectName) ?? "—"
        projectPath = path.map(AnalyticsModel.abbreviateHome) ?? ""
        modelKey = sample.model
        model = sample.failed ? "Failed" : sample.model
        effort = sample.effort ?? ""
        input = sample.input
        output = sample.output
        cacheRead = sample.cacheRead
        cacheWrite = sample.cacheWrite
        cache = sample.cacheRead + sample.cacheWrite
        cost = sample.cost ?? 0
        status = sample.error ?? ""
        thinking = sample.thinking
        context = sample.context
        sessionID = sample.sessionID
        isSubagent = sample.isSidechain
        durationMs = sample.durationMs
    }
}

// MARK: - Filters and derived data

enum SplitBy: String, CaseIterable, Identifiable {
    case model, app, project
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum RequestMetric: String, CaseIterable, Identifiable {
    case tokens, cost, requests, speed
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum RequestSort: String {
    case time, app, model, project, input, output, cache, cost, duration, speed, status
}

/// One split group (a model, app or project) across the period.
struct SplitGroup: Identifiable {
    let id: String
    let name: String
    var tokens = 0
    var cost: Double = 0
    var requests = 0
    var failed = 0
    var output = 0
    var ms = 0
    var cacheRead = 0
    var prompt = 0
    var share: Double = 0

    var speed: Double? { ms > 0 ? Double(output) / (Double(ms) / 1000) : nil }
    var hitRate: Double { prompt > 0 ? Double(cacheRead) / Double(prompt) * 100 : 0 }
}

/// One group's share of one bar.
struct SplitBucket: Identifiable {
    let start: Date
    let group: String
    var tokens = 0
    var cost: Double = 0
    var requests = 0
    var output = 0
    var ms = 0
    var id: String { "\(start.timeIntervalSince1970)|\(group)" }
    var speed: Double? { ms > 0 ? Double(output) / (Double(ms) / 1000) : nil }
}

struct HeatCell {
    var tokens = 0
    var requests = 0
    var cost: Double = 0
}

/// The filtered requests and everything drawn from them, computed once
/// per change of filters (off the main thread), not on every redraw.
struct RequestsDerived {
    var rows: [RequestRow] = []
    var totals = UsageTotals()
    var cacheWrite = 0
    var groups: [SplitGroup] = []
    var buckets: [SplitBucket] = []
    var barUnit: Calendar.Component = .day
    var domain: ClosedRange<Date> = Date()...Date()
    var heat: [Date: HeatCell] = [:]
    var apps: [(key: String, name: String)] = []
    var models: [String] = []

    struct Filters: Hashable {
        var app: String?
        var model: String?
        var failedOnly = false
        var search = ""
        var session: String?
        var split: SplitBy = .model
        var sort: RequestSort = .time
        var ascending = false
    }

    static func make(periodSamples: [TokenSample], allSamples: [TokenSample],
                     titles: [String: String], range: ClosedRange<Date>,
                     filters f: Filters) -> RequestsDerived {
        var out = RequestsDerived()
        // Options come from the period, before the app/model filters.
        var appNames: [String: String] = [:]
        var modelSet = Set<String>()
        for sample in periodSamples {
            let key = AnalyticsModel.appKey(sample.app)
            appNames[key] = AnalyticsModel.appName(key)
            if !sample.failed { modelSet.insert(sample.model) }
        }
        out.apps = appNames.sorted { $0.value < $1.value }.map { ($0.key, $0.value) }
        out.models = modelSet.sorted()

        let query = f.search.trimmingCharacters(in: .whitespaces).lowercased()
        func keep(_ sample: TokenSample) -> Bool {
            if let session = f.session, sample.sessionID != session { return false }
            if let app = f.app, AnalyticsModel.appKey(sample.app) != app { return false }
            if let model = f.model, sample.model != model { return false }
            if f.failedOnly && !sample.failed { return false }
            if !query.isEmpty {
                let path = AnalyticsModel.projectPath(sample.project) ?? ""
                let fields = [AnalyticsModel.appName(AnalyticsModel.appKey(sample.app)), sample.model,
                              path, sample.effort ?? "", sample.sessionID, titles[sample.sessionID] ?? "",
                              sample.error ?? ""]
                if !fields.contains(where: { $0.lowercased().contains(query) }) { return false }
            }
            return true
        }
        let samples = periodSamples.filter(keep)

        // Totals and the split.
        func groupKey(_ sample: TokenSample) -> (String, String) {
            switch f.split {
            case .model: return sample.failed ? ("Failed", "Failed") : (sample.model, sample.model)
            case .app:
                let key = AnalyticsModel.appKey(sample.app)
                return (key, AnalyticsModel.appName(key))
            case .project:
                let path = AnalyticsModel.projectPath(sample.project)
                return (path ?? "—", path.map(AnalyticsModel.projectName) ?? "Unknown folder")
            }
        }
        var groups: [String: SplitGroup] = [:]
        for sample in samples {
            out.totals.add(sample)
            out.cacheWrite += sample.cacheWrite
            let (key, name) = groupKey(sample)
            var group = groups[key] ?? SplitGroup(id: key, name: name)
            group.tokens += sample.tokens
            group.cost += sample.cost ?? 0
            group.requests += 1
            if sample.failed { group.failed += 1 }
            if let ms = sample.durationMs, ms > 0, sample.output > 0 {
                group.output += sample.output
                group.ms += ms
            }
            group.cacheRead += sample.cacheRead
            group.prompt += sample.context
            groups[key] = group
        }
        out.totals.sessions = Set(samples.map(\.sessionID)).count
        let totalTokens = max(groups.values.reduce(0) { $0 + $1.tokens }, 1)
        var ranked = groups.values.map { group -> SplitGroup in
            var group = group
            group.share = Double(group.tokens) / Double(totalTokens) * 100
            return group
        }
        .sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.requests > $1.requests }
        // Seven series and "Other (n)", as Magpie charts them.
        var chartKey: [String: String] = [:]
        if ranked.count > 8 {
            let rest = ranked[7...]
            var other = SplitGroup(id: "__other", name: "Other (\(rest.count))")
            for group in rest {
                other.tokens += group.tokens; other.cost += group.cost; other.requests += group.requests
                other.failed += group.failed; other.output += group.output; other.ms += group.ms
                other.cacheRead += group.cacheRead; other.prompt += group.prompt; other.share += group.share
                chartKey[group.id] = other.id
            }
            ranked = Array(ranked[..<7]) + [other]
        }
        out.groups = ranked

        // Bars: hours up to two days, days up to two months, else weeks.
        let calendar = Calendar.current
        let first = samples.map(\.ts).min() ?? range.lowerBound
        let lower = max(range.lowerBound, first)
        let upper = min(range.upperBound, Date())
        let span = upper.timeIntervalSince(lower)
        out.barUnit = span <= 2 * 86400 ? .hour : (span <= 62 * 86400 ? .day : .weekOfYear)
        let domainLower = calendar.dateInterval(of: out.barUnit, for: range.lowerBound == .distantPast ? first : range.lowerBound)?.start ?? lower
        let domainUpper = calendar.dateInterval(of: out.barUnit, for: upper)?.end ?? upper
        out.domain = domainLower...max(domainUpper, domainLower.addingTimeInterval(3600))
        var buckets: [String: SplitBucket] = [:]
        for sample in samples {
            let start = calendar.dateInterval(of: out.barUnit, for: sample.ts)?.start ?? sample.ts
            let (rawKey, _) = groupKey(sample)
            let key = chartKey[rawKey] ?? rawKey
            let id = "\(start.timeIntervalSince1970)|\(key)"
            var bucket = buckets[id] ?? SplitBucket(start: start, group: key)
            bucket.tokens += sample.tokens
            bucket.cost += sample.cost ?? 0
            bucket.requests += 1
            if let ms = sample.durationMs, ms > 0, sample.output > 0 {
                bucket.output += sample.output
                bucket.ms += ms
            }
            buckets[id] = bucket
        }
        out.buckets = buckets.values.sorted { $0.start < $1.start }

        // The heatmap: the last 53 weeks, whatever the period, same filters.
        let heatStart = calendar.date(byAdding: .day, value: -7 * 54, to: Date())!
        let dayCalendar = DailyHeatmap.mondayCalendar
        for sample in allSamples where sample.ts >= heatStart && keep(sample) {
            let day = dayCalendar.startOfDay(for: sample.ts)
            var cell = out.heat[day] ?? HeatCell()
            cell.tokens += sample.tokens
            cell.requests += 1
            cell.cost += sample.cost ?? 0
            out.heat[day] = cell
        }

        // The ledger, sorted.
        var rows = samples.map(RequestRow.init)
        func order(_ a: RequestRow, _ b: RequestRow) -> Bool {
            switch f.sort {
            case .time: return a.ts < b.ts
            case .app: return a.app < b.app
            case .model: return a.model < b.model
            case .project: return a.projectName.localizedCaseInsensitiveCompare(b.projectName) == .orderedAscending
            case .input: return a.input < b.input
            case .output: return a.output < b.output
            case .cache: return a.cache < b.cache
            case .cost: return a.cost < b.cost
            case .duration: return (a.durationMs ?? -1) < (b.durationMs ?? -1)
            case .speed: return (a.speed ?? -1) < (b.speed ?? -1)
            case .status: return a.status < b.status
            }
        }
        rows.sort { f.ascending ? order($0, $1) : order($1, $0) }
        out.rows = rows
        return out
    }
}

// MARK: - Requests page

/// Usage › Requests, as Magpie lays it out: filters, the stat strip, a
/// split chart with its ranked legend, the 53-week heatmap, and the ledger.
struct RequestsView: View {
    @ObservedObject var analytics: AnalyticsModel
    let period: UsagePeriod
    /// Set from the Sessions tab: show one session's requests.
    @Binding var sessionFilter: String?

    @State private var filters = RequestsDerived.Filters()
    @State private var derived: RequestsDerived?
    @AppStorage("requestsMetric") private var metric: RequestMetric = .tokens
    @AppStorage("requestsSplit") private var split: SplitBy = .model
    @AppStorage("requestsLines") private var lines = false
    @AppStorage("heatMetric") private var heatMetric: ActivityMetric = .tokens
    @State private var shown = 100

    private var key: String {
        var f = filters
        f.session = sessionFilter
        f.split = split
        return "\(period.cacheKey)|\(f.hashValue)|\(analytics.lastLoaded?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        TranscriptGate(analytics: analytics) {
            VStack(alignment: .leading, spacing: 14) {
                filterBar
                if let derived {
                    StatStrip(totals: derived.totals)
                    chartPanel(derived)
                    heatmapPanel(derived)
                    summaryLine(derived)
                    ledger(derived)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
        }
        .task(id: key) { await recompute() }
    }

    private func recompute() async {
        var f = filters
        f.session = sessionFilter
        f.split = split
        let periodSamples = analytics.samples(in: sessionFilter == nil ? period : .all)
        let all = analytics.tokenSamples
        let titles = analytics.sessionTitles
        let range = sessionFilter == nil ? period.range() : UsagePeriod.all.range()
        let result = await Task.detached(priority: .userInitiated) {
            RequestsDerived.make(periodSamples: periodSamples, allSamples: all, titles: titles,
                                 range: range, filters: f)
        }.value
        derived = result
        shown = 100
    }

    // MARK: Filters

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("App", selection: $filters.app) {
                    Text("All apps").tag(String?.none)
                    ForEach(derived?.apps ?? [], id: \.key) { app in
                        Text(app.name).tag(Optional(app.key))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(filters.app.map(AnalyticsModel.appName) ?? "All apps").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.track, in: RoundedRectangle(cornerRadius: 7))

            Menu {
                Picker("Model", selection: $filters.model) {
                    Text("All models").tag(String?.none)
                    ForEach(derived?.models ?? [], id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(filters.model ?? "All models").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.track, in: RoundedRectangle(cornerRadius: 7))

            PillTabs(options: [(false, "All"), (true, "Failed")], selection: $filters.failedOnly, size: 12)

            if let sessionFilter {
                Button { self.sessionFilter = nil } label: {
                    HStack(spacing: 5) {
                        Text("Session: \(analytics.sessionTitles[sessionFilter] ?? String(sessionFilter.prefix(8)))")
                            .lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dataAccent)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.dataAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Show all requests again")
                .frame(maxWidth: 260)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Search models, apps, projects, sessions", text: $filters.search)
                    .textFieldStyle(.plain)
                if !filters.search.isEmpty {
                    Button { filters.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.track, in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 260)

            Button("Export CSV") { exportCSV(derived?.rows ?? []) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .disabled((derived?.rows.isEmpty ?? true))
                .help("Export these requests as CSV")
        }
    }

    // MARK: Chart

    private func chartPanel(_ d: RequestsDerived) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PillTabs(options: RequestMetric.allCases.map { ($0, $0.title) }, selection: $metric, size: 12)
                PillTabs(options: [(false, "▮▮"), (true, "∿")], selection: $lines, size: 12)
                    .help("Bars or lines")
                Spacer()
                Text("Split by").font(.system(size: 12)).foregroundStyle(.secondary)
                PillTabs(options: SplitBy.allCases.map { ($0, $0.title) }, selection: $split, size: 12)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    splitChart(d).frame(minWidth: 420)
                    legend(d).frame(width: 300)
                }
                VStack(alignment: .leading, spacing: 12) {
                    splitChart(d)
                    legend(d)
                }
            }
        }
        .designCard()
    }

    private func color(_ group: String, in d: RequestsDerived) -> Color {
        if split == .model, let color = analytics.modelColors[group] { return color }
        if group == "Failed" { return .red }
        if group == "__other" { return .gray }
        let index = d.groups.firstIndex { $0.id == group } ?? 0
        return modelPalette[index % modelPalette.count]
    }

    private func value(_ bucket: SplitBucket) -> Double {
        switch metric {
        case .tokens: return Double(bucket.tokens)
        case .cost: return bucket.cost
        case .requests: return Double(bucket.requests)
        case .speed: return bucket.speed ?? 0
        }
    }

    private func format(_ value: Double) -> String {
        switch metric {
        case .tokens: return compactTokens(Int(value))
        case .cost: return costText(value, approximate: false)
        case .requests: return Int(value).formatted()
        case .speed: return "\(Int(value.rounded())) tok/s"
        }
    }

    private func splitChart(_ d: RequestsDerived) -> some View {
        let keys = d.groups.map(\.id)
        let buckets = metric == .speed ? d.buckets.filter { $0.speed != nil } : d.buckets
        return Chart {
            ForEach(buckets) { bucket in
                if lines || metric == .speed {
                    LineMark(x: .value("Time", bucket.start), y: .value(metric.title, value(bucket)),
                             series: .value("Group", bucket.group))
                        .foregroundStyle(by: .value("Group", bucket.group))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                } else {
                    BarMark(x: .value("Time", bucket.start, unit: d.barUnit),
                            y: .value(metric.title, value(bucket)))
                        .foregroundStyle(by: .value("Group", bucket.group))
                        .cornerRadius(2)
                }
            }
        }
        .chartForegroundStyleScale(domain: keys, range: keys.map { color($0, in: d) })
        .chartLegend(.hidden)
        .chartXScale(domain: d.domain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { if let number = value.as(Double.self) { Text(format(number)) } }
            }
        }
        .frame(height: 230)
    }

    private func legendValue(_ group: SplitGroup) -> String {
        switch metric {
        case .tokens: return group.tokens.formatted()
        case .cost: return costText(group.cost)
        case .requests: return group.requests.formatted()
        case .speed: return group.speed.map { "\(Int($0.rounded())) tok/s" } ?? "—"
        }
    }

    private func legend(_ d: RequestsDerived) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(d.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(color(group.id, in: d))
                                .frame(width: 9, height: 9)
                            Text(group.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(legendValue(group))
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        }
                        UsageBarTinted(percent: group.share, color: color(group.id, in: d))
                        Text(legendCaption(group))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.trailing, 6)
        }
        .frame(maxHeight: 230)
    }

    private func legendCaption(_ group: SplitGroup) -> String {
        var parts = ["\(group.requests.formatted()) request\(group.requests == 1 ? "" : "s")", costText(group.cost)]
        if let speed = group.speed { parts.append("\(Int(speed.rounded())) tok/s") }
        parts.append("hit rate \(Int(group.hitRate.rounded()))%")
        parts.append("\(Int(group.share.rounded()))%")
        var text = parts.joined(separator: " · ")
        if group.failed > 0 { text += " · \(group.failed) failed" }
        return text
    }

    // MARK: Heatmap

    private func heatmapPanel(_ d: RequestsDerived) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usage heatmap").font(.system(size: 13, weight: .semibold))
                    Text("Daily usage over the last 53 weeks").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                PillTabs(options: ActivityMetric.allCases.map { ($0, $0.title) }, selection: $heatMetric, size: 12)
            }
            DailyHeatmap(values: d.heat.mapValues { cell in
                switch heatMetric {
                case .tokens: return Double(cell.tokens)
                case .requests: return Double(cell.requests)
                case .cost: return cell.cost
                }
            }, describe: { value in
                switch heatMetric {
                case .tokens: return "\(compactTokens(Int(value))) tokens"
                case .requests: return "\(Int(value)) requests"
                case .cost: return costText(value)
                }
            })
            HStack { Spacer(); HeatLegend() }
        }
        .designCard()
    }

    // MARK: Ledger

    private func summaryLine(_ d: RequestsDerived) -> some View {
        let t = d.totals
        var parts = ["\(t.requests.formatted()) requests", "\(compactTokens(t.input)) in",
                     "\(compactTokens(t.output)) out", "\(compactTokens(d.cacheWrite)) cache write",
                     "\(compactTokens(t.cacheRead)) cache read"]
        if t.failed > 0 { parts.append("\(t.failed) failed") }
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
    }

    private struct Column {
        let title: String
        let sort: RequestSort
        let width: CGFloat?
        var trailing = false
    }

    /// Fixed widths add up to ~720 pt (plus spacing) so Project, the one
    /// flexible column, keeps ~110 pt in the default window.
    private let columns: [Column] = [
        Column(title: "Time", sort: .time, width: 92),
        Column(title: "App", sort: .app, width: 96),
        Column(title: "Model", sort: .model, width: 108),
        Column(title: "Project", sort: .project, width: nil),
        Column(title: "In", sort: .input, width: 46, trailing: true),
        Column(title: "Out", sort: .output, width: 50, trailing: true),
        Column(title: "Cache", sort: .cache, width: 54, trailing: true),
        Column(title: "Cost", sort: .cost, width: 60, trailing: true),
        Column(title: "Duration", sort: .duration, width: 60, trailing: true),
        Column(title: "Speed", sort: .speed, width: 64, trailing: true),
        Column(title: "Status", sort: .status, width: 90),
    ]

    private func ledger(_ d: RequestsDerived) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(columns.indices, id: \.self) { index in
                    let column = columns[index]
                    Button {
                        if filters.sort == column.sort { filters.ascending.toggle() } else {
                            filters.sort = column.sort
                            filters.ascending = column.sort == .app || column.sort == .model
                                || column.sort == .project || column.sort == .status
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(column.title.uppercased())
                            if filters.sort == column.sort {
                                Image(systemName: filters.ascending ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: column.trailing ? .trailing : .leading)
                    }
                    .buttonStyle(.plain)
                    .frame(width: column.width)
                    .frame(maxWidth: column.width == nil ? .infinity : nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            Divider()
            LazyVStack(spacing: 0) {
                ForEach(d.rows.prefix(shown)) { row in
                    LedgerRow(row: row, columns: columns.map { ($0.width, $0.trailing) })
                    Divider().opacity(0.5)
                }
            }
            if d.rows.count > shown {
                HStack {
                    Text("Showing \(shown.formatted()) of \(d.rows.count.formatted())")
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Show \(min(100, d.rows.count - shown)) more") { shown += 100 }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.dataAccent)
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cardStroke, lineWidth: 0.5))
    }

    // MARK: CSV

    private func exportCSV(_ rows: [RequestRow]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let stamp = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "claude-code-requests-\(stamp).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Self.csv(rows, titles: analytics.sessionTitles).write(to: url, atomically: true, encoding: .utf8)
    }

    static func csv(_ rows: [RequestRow], titles: [String: String]) -> String {
        func field(_ value: String) -> String {
            value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
        }
        let iso = ISO8601DateFormatter()
        var lines = ["time,app,subagent,project,model,effort,status,input,output,cache_read,cache_write,thinking,context,duration_ms,cost_usd,session_id,session_title"]
        for row in rows {
            lines.append([
                iso.string(from: row.ts), field(row.app), row.isSubagent ? "1" : "0",
                field(row.projectPath), field(row.model), field(row.effort),
                field(row.status.isEmpty ? "ok" : row.status),
                String(row.input), String(row.output), String(row.cacheRead), String(row.cacheWrite),
                String(row.thinking), String(row.context), row.durationMs.map(String.init) ?? "",
                String(format: "%.4f", row.cost), row.sessionID,
                field(titles[row.sessionID] ?? ""),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// One ledger line.
struct LedgerRow: View {
    let row: RequestRow
    let columns: [(width: CGFloat?, trailing: Bool)]
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            cell(0) {
                Text(timeText).monospacedDigit()
            }
            cell(1) {
                HStack(spacing: 5) {
                    Image(systemName: AnalyticsModel.appIcon(row.appKey))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(shortApp).lineLimit(1)
                    if row.isSubagent {
                        Text("↳").foregroundStyle(.tertiary)
                    }
                }
                .help(row.isSubagent ? "\(row.app), sent by a subagent" : row.app)
            }
            cell(2) {
                (Text(row.model) + Text(row.effort.isEmpty ? "" : " \(row.effort)").foregroundStyle(.tertiary))
                    .lineLimit(1)
            }
            cell(3) {
                Text(row.projectName).lineLimit(1).truncationMode(.middle).help(row.projectPath)
            }
            cell(4) { number(row.input) }
            cell(5) { number(row.output) }
            cell(6) { number(row.cache) }
            cell(7) {
                Text(row.cost > 0 ? costText(row.cost) : "–")
                    .foregroundStyle(row.cost > 0 ? Color.costGreen : Color.secondary)
            }
            cell(8) { Text(row.durationMs.map(durationText) ?? "—").foregroundStyle(.secondary) }
            cell(9) { Text(row.speed.map { "\(Int($0.rounded())) tok/s" } ?? "—").foregroundStyle(.secondary) }
            cell(10) {
                HStack(spacing: 5) {
                    Circle().fill(row.status.isEmpty ? Color.costGreen : Color.red).frame(width: 6, height: 6)
                    Text(row.status.isEmpty ? "Succeeded" : row.status)
                        .lineLimit(1)
                        .foregroundStyle(row.status.isEmpty ? Color.secondary : Color.red)
                }
                .help(row.status.isEmpty ? "Succeeded" : "Failed: \(row.status)")
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
    }

    private func cell<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        let column = columns[index]
        return content()
            .frame(maxWidth: .infinity, alignment: column.trailing ? .trailing : .leading)
            .frame(width: column.width)
            .frame(maxWidth: column.width == nil ? .infinity : nil)
    }

    private func number(_ value: Int) -> some View {
        Text(value == 0 ? "–" : compactTokens(value))
            .foregroundStyle(value == 0 ? Color.secondary : Color.primary)
    }

    /// App names short enough for the ledger's column.
    private var shortApp: String {
        switch row.appKey {
        case "claude-desktop": return "Desktop"
        case "sdk": return "SDK"
        default: return row.app
        }
    }

    /// "16:00:28" today, "Nov 11 16:00" before.
    private var timeText: String {
        Calendar.current.isDateInToday(row.ts)
            ? row.ts.formatted(.dateTime.hour().minute().second())
            : shortDateTime(row.ts)
    }

    private func durationText(_ ms: Int) -> String {
        if ms < 60_000 { return String(format: "%.1f s", Double(ms) / 1000) }
        return "\(ms / 60_000) m \((ms % 60_000) / 1000) s"
    }
}
