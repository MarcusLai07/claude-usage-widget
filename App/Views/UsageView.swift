import SwiftUI
import WidgetKit

/// Usage › Overview: the allowances (always "now") over Claude Code's token
/// activity for the picked period. Replaces the Dashboard and Analytics.
struct UsageView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @ObservedObject var trends: TrendModel
    @ObservedObject var analytics: AnalyticsModel

    @AppStorage(AppGroupStore.SharedKey.showLeft, store: AppGroupStore.defaults)
    private var showLeft = false
    @AppStorage(AppGroupStore.SharedKey.hideAccount, store: AppGroupStore.defaults)
    private var hideAccount = false
    @AppStorage("usagePeriod") private var period: UsagePeriod = .week

    private var sessionPercent: Double {
        refresher.snapshot?.session?.utilization ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Usage") {
                if sessionPercent >= 100 {
                    StatusPill(text: "Session limit reached", color: .red)
                } else if sessionPercent >= 70 {
                    StatusPill(text: "Approaching session limit", color: .orange)
                }
                Spacer()
                if let fetchedAt = refresher.snapshot?.fetchedAt {
                    AgeIndicator(since: fetchedAt, stale: refresher.isStale)
                }
                RefreshButton()
            }
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
