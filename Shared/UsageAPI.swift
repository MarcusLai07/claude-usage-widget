import Foundation

enum UsageAPIError: Error, LocalizedError {
    case notSignedIn
    case http(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .http(let code): return "Request failed (HTTP \(code))"
        case .decoding: return "Unexpected response from server"
        }
    }
}

/// Talks to the (undocumented) endpoint Claude Code itself uses for the
/// /usage screen. Returns rolling-window utilization percentages and reset
/// timestamps. May change without notice — degrade gracefully on decode errors.
enum UsageAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private struct APIWindow: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    private struct APIExtra: Decodable {
        let is_enabled: Bool?
        let monthly_limit: Double?
        let used_credits: Double?
        let currency: String?
    }

    private struct APIResponse: Decodable {
        let five_hour: APIWindow?
        let seven_day: APIWindow?
        let seven_day_opus: APIWindow?
        let seven_day_sonnet: APIWindow?
        let extra_usage: APIExtra?
    }

    static func fetchUsage() async throws -> UsageSnapshot {
        guard var tokens = TokenStore.load() else { throw UsageAPIError.notSignedIn }

        if tokens.isExpired {
            tokens = try await OAuthClient.refresh(tokens)
            TokenStore.save(tokens)
        }

        var (data, status) = try await request(token: tokens.accessToken)
        if status == 401 {
            tokens = try await OAuthClient.refresh(tokens)
            TokenStore.save(tokens)
            (data, status) = try await request(token: tokens.accessToken)
        }
        guard status == 200 else { throw UsageAPIError.http(status) }
        guard let response = try? JSONDecoder().decode(APIResponse.self, from: data) else {
            throw UsageAPIError.decoding
        }
        return snapshot(from: response)
    }

    private static func request(token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func snapshot(from api: APIResponse) -> UsageSnapshot {
        UsageSnapshot(
            fetchedAt: Date(),
            session: window(api.five_hour),
            weekly: window(api.seven_day),
            weeklyOpus: window(api.seven_day_opus),
            weeklySonnet: window(api.seven_day_sonnet),
            extra: api.extra_usage.map {
                ExtraUsage(isEnabled: $0.is_enabled ?? false,
                           monthlyLimit: $0.monthly_limit,
                           usedCredits: $0.used_credits,
                           currency: $0.currency)
            }
        )
    }

    private static func window(_ api: APIWindow?) -> UsageWindow? {
        guard let api else { return nil }
        return UsageWindow(utilization: api.utilization, resetsAt: parseDate(api.resets_at))
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
