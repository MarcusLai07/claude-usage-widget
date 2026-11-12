import SwiftUI
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

/// One request as the table shows it; every column is sortable.
struct RequestRow: Identifiable {
    let id: String
    let ts: Date
    let app: String
    let appKey: String
    let projectName: String
    let projectPath: String
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

    init(_ sample: TokenSample) {
        id = sample.id
        ts = sample.ts
        appKey = AnalyticsModel.appKey(sample.app)
        app = AnalyticsModel.appName(appKey)
        let path = AnalyticsModel.projectPath(sample.project)
        projectName = path.map(AnalyticsModel.projectName) ?? "—"
        projectPath = path.map(AnalyticsModel.abbreviateHome) ?? ""
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
    }
}

/// Usage › Requests: a ledger of every request, newest first.
struct RequestsView: View {
    @ObservedObject var analytics: AnalyticsModel
    let period: UsagePeriod
    /// Set from the Sessions tab: show one session's requests.
    @Binding var sessionFilter: String?

    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\RequestRow.ts, order: .reverse)]
    @State private var selection = Set<RequestRow.ID>()

    var body: some View {
        TranscriptGate(analytics: analytics) {
            let rows = filteredRows
            VStack(spacing: 10) {
                toolbar(rows)
                table(rows)
                summary(rows)
            }
        }
    }

    private var filteredRows: [RequestRow] {
        var samples = analytics.samples(in: sessionFilter == nil ? period : .all)
        if let sessionFilter { samples = samples.filter { $0.sessionID == sessionFilter } }
        var rows = samples.map(RequestRow.init)
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            let titles = analytics.sessionTitles
            rows = rows.filter { row in
                [row.app, row.projectName, row.projectPath, row.model, row.effort, row.sessionID,
                 titles[row.sessionID] ?? ""].contains { $0.lowercased().contains(query) }
            }
        }
        return rows.sorted(using: sortOrder)
    }

    // MARK: Toolbar

    private func toolbar(_ rows: [RequestRow]) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search app, project, model, session", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.cardStroke, lineWidth: 0.5))
            .frame(maxWidth: 300)

            if let sessionFilter {
                Button { self.sessionFilter = nil } label: {
                    HStack(spacing: 5) {
                        Text("Session: \(analytics.sessionTitles[sessionFilter] ?? String(sessionFilter.prefix(8)))")
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.clay)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.clay.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Show all requests again")
                .frame(maxWidth: 220)
            }

            Spacer(minLength: 8)

            Button {
                exportCSV(rows)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export these requests as CSV")
            .disabled(rows.isEmpty)
        }
    }

    // MARK: Table

    private func table(_ rows: [RequestRow]) -> some View {
        // Fixed widths (each column also gets ~15 pt of padding) so the
        // table fits the default window; Project takes what's left.
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Time", value: \.ts) { row in
                Text(shortDateTime(row.ts))
                    .monospacedDigit()
            }
            .width(82)
            TableColumn("App", value: \.app) { row in
                HStack(spacing: 2) {
                    if row.isSubagent {
                        Text("↳").foregroundStyle(.tertiary)
                    }
                    Image(systemName: AnalyticsModel.appIcon(row.appKey))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .help(row.isSubagent ? "\(row.app) · sent by a subagent" : row.app)
            }
            .width(30)
            TableColumn("Project", value: \.projectName) { row in
                Text(row.projectName).help(row.projectPath)
            }
            .width(min: 56, ideal: 80)
            // Effort rides along in the model's cell: one column fewer.
            TableColumn("Model", value: \.model) { row in
                (Text(row.model) + Text(row.effort.isEmpty ? "" : " \(row.effort)").foregroundStyle(.tertiary))
                    .lineLimit(1)
            }
            .width(88)
            Group {
                TableColumn("In", value: \RequestRow.input) { (row: RequestRow) in number(row.input) }
                    .width(42)
                TableColumn("Out", value: \RequestRow.output) { (row: RequestRow) in number(row.output) }
                    .width(40)
                TableColumn("Cache", value: \RequestRow.cache) { (row: RequestRow) in number(row.cache) }
                    .width(46)
                TableColumn("Cost", value: \RequestRow.cost) { (row: RequestRow) in
                    Text(row.cost > 0 ? costText(row.cost) : "–")
                        .monospacedDigit()
                        .foregroundStyle(row.cost > 0 ? Color.costGreen : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                    .width(54)
                TableColumn("Context", value: \RequestRow.context) { (row: RequestRow) in number(row.context) }
                    .width(48)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .font(.system(size: 11.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cardStroke, lineWidth: 0.5))
    }

    private func number(_ value: Int) -> some View {
        Text(value == 0 ? "–" : compactTokens(value))
            .monospacedDigit()
            .foregroundStyle(value == 0 ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func summary(_ rows: [RequestRow]) -> some View {
        let tokens = rows.reduce(0) { $0 + $1.input + $1.cache + $1.output }
        let cost = rows.reduce(0) { $0 + $1.cost }
        let sessions = Set(rows.map(\.sessionID)).count
        let failed = rows.filter { !$0.status.isEmpty }.count
        return HStack {
            Text("\(rows.count.formatted()) request\(rows.count == 1 ? "" : "s")\(failed > 0 ? " (\(failed) failed)" : "") · \(sessions.formatted()) session\(sessions == 1 ? "" : "s") · \(compactTokens(tokens)) tokens · \(costText(cost))")
            Spacer()
            Text("Cache = reads + writes · Cost ≈ API list prices")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
    }

    // MARK: CSV

    private func exportCSV(_ rows: [RequestRow]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let stamp = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "claude-code-requests-\(stamp).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let titles = analytics.sessionTitles
        try? Self.csv(rows, titles: titles).write(to: url, atomically: true, encoding: .utf8)
    }

    static func csv(_ rows: [RequestRow], titles: [String: String]) -> String {
        func field(_ value: String) -> String {
            value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
        }
        let iso = ISO8601DateFormatter()
        var lines = ["time,app,subagent,project,model,effort,status,input,output,cache_read,cache_write,thinking,context,cost_usd,session_id,session_title"]
        for row in rows {
            lines.append([
                iso.string(from: row.ts), field(row.app), row.isSubagent ? "1" : "0",
                field(row.projectPath), field(row.model), field(row.effort),
                field(row.status.isEmpty ? "ok" : row.status),
                String(row.input), String(row.output), String(row.cacheRead), String(row.cacheWrite),
                String(row.thinking), String(row.context), String(format: "%.4f", row.cost), row.sessionID,
                field(titles[row.sessionID] ?? ""),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
