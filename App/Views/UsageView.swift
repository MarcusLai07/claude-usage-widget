import SwiftUI
import WidgetKit

enum UsageTab: String, CaseIterable, Identifiable {
    case overview, requests, sessions, context

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .requests: return "Requests"
        case .sessions: return "Sessions"
        case .context: return "Context"
        }
    }
}

/// The Usage page, laid out as Magpie's: one toolbar row (tabs, period,
/// refresh, the period's cost), then the tab. Overview: allowances (always
/// "now") over Claude Code's token activity. Requests: the ledger.
/// Sessions: one row per session.
struct UsageView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @ObservedObject var trends: TrendModel
    @ObservedObject var analytics: AnalyticsModel

    @AppStorage(AppGroupStore.SharedKey.showLeft, store: AppGroupStore.defaults)
    private var showLeft = false
    @AppStorage(AppGroupStore.SharedKey.hideAccount, store: AppGroupStore.defaults)
    private var hideAccount = false
    @AppStorage("usagePeriod") private var period: UsagePeriod = .week
    @AppStorage("trendRange") private var trendRange: TrendRange = .cycle
    #if SHOTS
    // The screenshot tool (Shots/) picks the tab; it has no scene to restore.
    @SceneStorage("usageTab") private var tab: UsageTab = UsageView.shotsTab
    #else
    @SceneStorage("usageTab") private var tab: UsageTab = .overview
    #endif
    @State private var sessionFilter: String?
    @State private var editingRange = false
    /// Bumped when the custom range changes, to redraw what depends on it.
    @State private var rangeTick = 0

    private var sessionPercent: Double {
        refresher.snapshot?.session?.utilization ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.init(top: 12, leading: 20, bottom: 12, trailing: 20))
            Divider().opacity(0.6)
            content
                .id(rangeTick)
        }
        .background(Color.windowContent)
        // Widgets read the mode from the shared store; redraw them with it.
        .onChange(of: showLeft) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
        // Each fetch may have added a history sample and new transcript lines.
        .task(id: refresher.snapshot?.fetchedAt) {
            await trends.reload()
            await analytics.reload()
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                tabs
                periodControls
                Spacer(minLength: 8)
                trailing
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    tabs
                    Spacer(minLength: 8)
                    trailing
                }
                periodControls
            }
        }
    }

    private var tabs: some View {
        PillTabs(options: UsageTab.allCases.map { ($0, $0.title) }, selection: $tab)
    }

    private var periodControls: some View {
        HStack(spacing: 6) {
            PillTabs(options: UsagePeriod.allCases.map { ($0, $0.title) }, selection: $period)
            if period == .custom {
                Button {
                    editingRange = true
                } label: {
                    Label(rangeLabel, systemImage: "calendar")
                        .font(.system(size: 12))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.track, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $editingRange, arrowEdge: .bottom) {
                    CustomRangeEditor { rangeTick &+= 1 }
                }
            }
        }
    }

    private var rangeLabel: String {
        let range = UsagePeriod.customRange
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(range.lowerBound.formatted(style)) – \(range.upperBound.formatted(style))"
    }

    private var trailing: some View {
        HStack(spacing: 10) {
            limitStatus
            if let fetchedAt = refresher.snapshot?.fetchedAt {
                AgeIndicator(since: fetchedAt, stale: refresher.isStale)
            }
            RefreshButton()
            if analytics.hasClaudeAccess, analytics.lastLoaded != nil {
                let cost = analytics.overview(period).totals.cost
                (Text(costText(cost)).font(.system(size: 15, weight: .semibold).monospacedDigit())
                 + Text("  API prices").font(.system(size: 11)).foregroundStyle(.secondary))
                    .fixedSize()
                    .help("What \(period == .custom ? "this range" : period.title.lowercased())'s Claude Code calls would cost at Anthropic API list prices")
            }
        }
    }

    /// The session warning pill, or just its icon when the header is narrow.
    @ViewBuilder
    private var limitStatus: some View {
        if sessionPercent >= 70 {
            let text = sessionPercent >= 100 ? "Session limit reached" : "Approaching session limit"
            let color: Color = sessionPercent >= 100 ? .red : .orange
            ViewThatFits(in: .horizontal) {
                StatusPill(text: text, color: color)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                    .help(text)
            }
        }
    }

    // MARK: Tabs

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview:
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if refresher.isStale {
                        StaleBanner()
                    }
                    allowances
                    ClaudeCodeSection(analytics: analytics, period: period)
                }
                .padding(20)
            }
        case .requests:
            ScrollView {
                RequestsView(analytics: analytics, period: period, sessionFilter: $sessionFilter)
                    .padding(20)
            }
        case .sessions:
            ScrollView {
                SessionsView(analytics: analytics, period: period) { session in
                    sessionFilter = session
                    tab = .requests
                }
                .padding(20)
            }
        case .context:
            ScrollView {
                ContextView(analytics: analytics, period: period)
                    .padding(20)
            }
        }
    }

    private var allowances: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionLabel("Allowances")
                Spacer()
                Menu {
                    Picker("Trends", selection: $trendRange) {
                        ForEach(TrendRange.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text("Trends: \(trendRange.title)")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.track, in: RoundedRectangle(cornerRadius: 7))
                .help("What was left over time, under the limits")
                Button {
                    hideAccount.toggle()
                } label: {
                    Label(hideAccount ? "Show account" : "Hide account",
                          systemImage: hideAccount ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Mask the account email, for screenshots")
                PillTabs(options: [(false, "Used"), (true, "Left")], selection: $showLeft, size: 12)
            }
            if let snapshot = refresher.snapshot {
                AllowancesCard(snapshot: snapshot, profile: refresher.profile,
                               hideAccount: hideAccount, showLeft: $showLeft,
                               isStale: refresher.isStale, trends: trends)
            } else {
                ProgressView("Loading usage…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .designCard()
            }
        }
    }
}

/// Picks the Custom period's first and last day.
struct CustomRangeEditor: View {
    var onChange: () -> Void
    @State private var start = UsagePeriod.customRange.lowerBound
    @State private var end = UsagePeriod.customRange.upperBound

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom range")
                .font(.system(size: 12.5, weight: .semibold))
            DatePicker("From", selection: $start, in: ...Date(), displayedComponents: .date)
            DatePicker("To", selection: $end, in: start...max(start, Date()), displayedComponents: .date)
        }
        .datePickerStyle(.field)
        .padding(14)
        .frame(width: 240)
        .onChange(of: start) { _, _ in save() }
        .onChange(of: end) { _, _ in save() }
    }

    private func save() {
        UsagePeriod.customRange = min(start, end)...max(start, end)
        onChange()
    }
}
