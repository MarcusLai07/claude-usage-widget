import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class UsageRefresher: ObservableObject {
    @Published var snapshot: UsageSnapshot? = AppGroupStore.cachedSnapshot
    @Published var lastError: String?
    @Published var isSignedIn: Bool = TokenStore.load() != nil
    @Published var isRefreshing = false

    /// True when the last fetch failed and we're showing cached data.
    var isStale: Bool { lastError != nil && snapshot != nil }

    static let refreshInterval: TimeInterval = 5 * 60

    private var timer: Timer?

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
            PerfLog.record(source: "app", started: started, error: nil)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.evaluate(snapshot)
        } catch UsageAPIError.notSignedIn {
            isSignedIn = false
        } catch {
            lastError = error.localizedDescription
            PerfLog.record(source: "app", started: started, error: error.localizedDescription)
        }
    }

    func signIn(with tokens: TokenSet) {
        TokenStore.save(tokens)
        isSignedIn = true
        Task { await refresh() }
    }

    func signOut() {
        TokenStore.clear()
        AppGroupStore.cachedSnapshot = nil
        snapshot = nil
        isSignedIn = false
        WidgetCenter.shared.reloadAllTimelines()
    }
}
