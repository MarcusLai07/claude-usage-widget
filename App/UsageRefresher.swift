import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class UsageRefresher: ObservableObject {
    @Published var snapshot: UsageSnapshot? = AppGroupStore.cachedSnapshot
    @Published var lastError: String?
    @Published var isSignedIn: Bool = TokenStore.load() != nil
    @Published var isRefreshing = false
    @Published var profile: AccountProfile? = AppGroupStore.accountProfile

    /// True when the last fetch failed and we're showing cached data.
    var isStale: Bool { lastError != nil && snapshot != nil }

    static let refreshInterval: TimeInterval = 5 * 60
    /// Plan and email rarely change; re-read them twice a day.
    static let profileMaxAge: TimeInterval = 12 * 3600

    private var timer: Timer?
    private var lastProfileAttempt: Date?

    init() {
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await refresh() }
    }

    /// `force` is for user-initiated refreshes: it shrinks the freshness
    /// window but still coalesces rapid clicks instead of hitting the
    /// endpoint per click (it rate-limits at HTTP 429 under bursts).
    func refresh(force: Bool = false) async {
        guard isSignedIn else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let started = Date()
        do {
            let snapshot = try await UsageFetcher.shared.fetch(maxAge: force ? 5 : 60)
            self.snapshot = snapshot
            self.lastError = nil
            AppGroupStore.cachedSnapshot = snapshot
            UsageHistory.append(snapshot)
            PerfLog.record(source: "app", started: started, error: nil)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.evaluate(snapshot)
            // The pace alert reads this week's history: off the main thread.
            Task.detached(priority: .utility) { NotificationManager.checkPace(snapshot) }
            await refreshProfileIfNeeded()
        } catch UsageAPIError.notSignedIn {
            isSignedIn = false
        } catch {
            lastError = error.localizedDescription
            PerfLog.record(source: "app", started: started, error: error.localizedDescription)
        }
    }

    /// Reads the plan and email after a successful usage fetch (the token is
    /// fresh then). A failure only costs the badge; it retries hourly.
    private func refreshProfileIfNeeded() async {
        if let profile, Date().timeIntervalSince(profile.fetchedAt) < Self.profileMaxAge { return }
        if let lastProfileAttempt, Date().timeIntervalSince(lastProfileAttempt) < 3600 { return }
        lastProfileAttempt = Date()
        guard let fetched = try? await UsageAPI.fetchProfile() else { return }
        profile = fetched
        AppGroupStore.accountProfile = fetched
    }

    func signIn(with tokens: TokenSet) {
        TokenStore.save(tokens)
        // Possibly a different account: read its plan and email afresh.
        AppGroupStore.accountProfile = nil
        profile = nil
        lastProfileAttempt = nil
        isSignedIn = true
        Task { await refresh() }
    }

    func signOut() {
        TokenStore.clear()
        AppGroupStore.cachedSnapshot = nil
        AppGroupStore.accountProfile = nil
        snapshot = nil
        profile = nil
        lastProfileAttempt = nil
        isSignedIn = false
        WidgetCenter.shared.reloadAllTimelines()
    }
}
