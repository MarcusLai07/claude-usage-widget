import Foundation

/// Coordinates all usage fetches to avoid hammering the endpoint (it returns
/// HTTP 429 under bursts). Two layers of protection:
///
/// 1. **Freshness window** — if the cached snapshot is younger than `maxAge`,
///    serve it without touching the network. Widgets pass a long window since
///    the app refreshes for them and reloads their timelines after each fetch.
/// 2. **Single flight** — concurrent callers (several widget timelines reload
///    at once) share one in-flight network request.
actor UsageFetcher {
    static let shared = UsageFetcher()

    private var inFlight: Task<UsageSnapshot, Error>?

    func fetch(maxAge: TimeInterval) async throws -> UsageSnapshot {
        if let cached = AppGroupStore.cachedSnapshot,
           Date().timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached
        }
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await UsageAPI.fetchUsage() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
