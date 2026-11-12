import SwiftUI
import WidgetKit

struct DashboardView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @ObservedObject var trends: TrendModel
    @AppStorage(AppGroupStore.SharedKey.showLeft, store: AppGroupStore.defaults)
    private var showLeft = false
    @AppStorage(AppGroupStore.SharedKey.hideAccount, store: AppGroupStore.defaults)
    private var hideAccount = false

    private var sessionPercent: Double {
        refresher.snapshot?.session?.utilization ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Dashboard") {
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
                content
                    .padding(.init(top: 4, leading: 22, bottom: 22, trailing: 22))
            }
        }
        .background(Color.windowContent)
        // Widgets read the mode from the shared store; redraw them with it.
        .onChange(of: showLeft) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
        // Each fetch may have added a history sample.
        .task(id: refresher.snapshot?.fetchedAt) { await trends.reload() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = refresher.snapshot {
            VStack(spacing: 16) {
                if refresher.isStale {
                    StaleBanner()
                }
                AllowancesCard(snapshot: snapshot, profile: refresher.profile,
                               showLeft: $showLeft, hideAccount: $hideAccount,
                               isStale: refresher.isStale, trends: trends)
            }
        } else {
            ProgressView("Loading usage…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
        }
    }
}
