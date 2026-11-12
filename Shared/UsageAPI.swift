import Foundation

enum UsageAPIError: Error, LocalizedError {
    case notSignedIn
    case http(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .http(429): return "Rate limited — will retry on the next cycle"
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

    /// Decodes a value the endpoint may send in a shape this version doesn't
    /// expect: a mismatch yields nil instead of failing the whole response.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// One row of the endpoint's `limits[]`, the meters Claude Code's /usage
    /// renders as sent. `kind` is "session", "weekly_all" or "weekly_scoped";
    /// a scoped row names its model ("Fable") or surface.
    private struct APILimit: Decodable {
        struct Named: Decodable { let display_name: String? }
        struct Scope: Decodable {
            let model: Named?
            let surface: Named?
        }
        let kind: String?
        let percent: Double?
        let utilization: Double?
        let resets_at: String?
        let scope: Scope?
    }

    private struct APIResponse: Decodable {
        let five_hour: APIWindow?
        let seven_day: APIWindow?
        let seven_day_opus: APIWindow?
        let seven_day_sonnet: APIWindow?
        let seven_day_overage_included: Lenient<APIWindow>?
        let extra_usage: APIExtra?
        let limits: Lenient<[Lenient<APILimit>]>?
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
        let rows = (api.limits?.value ?? []).compactMap(\.value)
        var snapshot = UsageSnapshot(
            fetchedAt: Date(),
            // The named keys first; the limits[] rows stand in if the
            // endpoint ever stops sending them.
            session: window(api.five_hour) ?? window(rows.first { $0.kind == "session" }),
            weekly: window(api.seven_day) ?? window(rows.first { $0.kind == "weekly_all" }),
            weeklyOpus: window(api.seven_day_opus),
            weeklySonnet: window(api.seven_day_sonnet),
            extra: api.extra_usage.map {
                ExtraUsage(isEnabled: $0.is_enabled ?? false,
                           monthlyLimit: $0.monthly_limit,
                           usedCredits: $0.used_credits,
                           currency: $0.currency)
            },
            weeklyFable: window(scopedRow(model: "fable", in: rows))
                ?? window(api.seven_day_overage_included?.value)
        )
        // Anthropic leaves the 5-hour window out (null) until it starts. A
        // reading that reports any other window means it simply hasn't begun.
        let reportsOthers = [snapshot.weekly, snapshot.weeklyFable,
                             snapshot.weeklyOpus, snapshot.weeklySonnet].contains { $0 != nil }
        if snapshot.session == nil, reportsOthers {
            snapshot.session = UsageWindow(utilization: 0, resetsAt: nil)
        }
        return snapshot
    }

    /// The weekly row scoped to a model family ("Fable", "Fable 5.1"); the
    /// most used one when several match.
    private static func scopedRow(model family: String, in rows: [APILimit]) -> APILimit? {
        rows.filter {
            $0.kind == "weekly_scoped"
                && ($0.scope?.model?.display_name ?? "").lowercased().hasPrefix(family)
        }
        .max { ($0.percent ?? $0.utilization ?? 0) < ($1.percent ?? $1.utilization ?? 0) }
    }

    private static func window(_ api: APIWindow?) -> UsageWindow? {
        guard let api else { return nil }
        return UsageWindow(utilization: api.utilization, resetsAt: parseDate(api.resets_at))
    }

    private static func window(_ row: APILimit?) -> UsageWindow? {
        guard let row else { return nil }
        return UsageWindow(utilization: row.percent ?? row.utilization,
                           resetsAt: parseDate(row.resets_at))
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
