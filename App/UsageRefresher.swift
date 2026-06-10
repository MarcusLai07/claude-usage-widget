import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class UsageRefresher: ObservableObject {
    @Published var snapshot: UsageSnapshot? = AppGroupStore.cachedSnapshot
    @Published var lastError: String?
    @Published var isSignedIn: Bool = TokenStore.load() != nil
    @Published var isRefreshing = false

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

    func refresh() async {
        guard isSignedIn else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snapshot = try await UsageAPI.fetchUsage()
            self.snapshot = snapshot
            self.lastError = nil
            AppGroupStore.cachedSnapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.evaluate(snapshot)
        } catch UsageAPIError.notSignedIn {
            isSignedIn = false
        } catch {
            lastError = error.localizedDescription
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
