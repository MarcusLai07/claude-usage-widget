import SwiftUI
import WidgetKit

enum UsageTab: String, CaseIterable, Identifiable {
    case overview, requests, sessions

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .requests: return "Requests"
        case .sessions: return "Sessions"
        }
    }
}

/// The Usage page. Overview: the allowances (always "now") over Claude
/// Code's token activity for the picked period. Requests: a ledger of every
/// request. Sessions: one row per session, by project.
struct UsageView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @ObservedObject var trends: TrendModel
    @ObservedObject var analytics: AnalyticsModel

    @AppStorage(AppGroupStore.SharedKey.showLeft, store: AppGroupStore.defaults)
    private var showLeft = false
    @AppStorage(AppGroupStore.SharedKey.hideAccount, store: AppGroupStore.defaults)
    private var hideAccount = false
    @AppStorage("usagePeriod") private var period: UsagePeriod = .week
    @SceneStorage("usageTab") private var tab: UsageTab = .overview
    @State private var sessionFilter: String?

    private var sessionPercent: Double {
        refresher.snapshot?.session?.utilization ?? 0
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

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Usage") {
                Picker("Tab", selection: $tab) {
                    ForEach(UsageTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                limitStatus
                Spacer()
                if let fetchedAt = refresher.snapshot?.fetchedAt {
                    AgeIndicator(since: fetchedAt, stale: refresher.isStale)
                }
                RefreshButton()
            }
            switch tab {
            case .overview:
                ScrollView {
                    VStack(spacing: 16) {
                        if refresher.isStale {
                            StaleBanner()
                        }
                        if let snapshot = refresher.snapshot {
                            AllowancesCard(snapshot: snapshot, profile: refresher.profile,
                                           showLeft: $showLeft, hideAccount: $hideAccount,
                                           isStale: refresher.isStale, trends: trends)
                        } else {
                            ProgressView("Loading usage…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                        }
                        ClaudeCodeSection(analytics: analytics, period: $period)
                    }
                    .padding(.init(top: 4, leading: 22, bottom: 22, trailing: 22))
                }
            case .requests:
                VStack {
                    RequestsView(analytics: analytics, period: $period, sessionFilter: $sessionFilter)
                    Spacer(minLength: 0)
                }
                // Slimmer margins: the table needs the width.
                .padding(.init(top: 4, leading: 12, bottom: 14, trailing: 12))
            case .sessions:
                ScrollView {
                    SessionsView(analytics: analytics, period: $period) { session in
                        sessionFilter = session
                        tab = .requests
                    }
                    .padding(.init(top: 4, leading: 22, bottom: 22, trailing: 22))
                }
            }
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
}
