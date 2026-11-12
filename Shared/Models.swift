import Foundation

enum MetricKind: String, CaseIterable, Codable, Identifiable {
    case session
    case weekly
    case weeklyFable
    case weeklyOpus
    case weeklySonnet
    case extraUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: return "Session"
        case .weekly: return "Weekly"
        case .weeklyFable: return "Fable · 7-day"
        case .weeklyOpus: return "Opus · 7-day"
        case .weeklySonnet: return "Sonnet · 7-day"
        case .extraUsage: return "Extra usage"
        }
    }

    /// How long one cycle of the window lasts; nil for extra usage, which
    /// has no rolling window. Pace is measured against this.
    var span: TimeInterval? {
        switch self {
        case .session: return 5 * 3600
        case .weekly, .weeklyFable, .weeklyOpus, .weeklySonnet: return 7 * 86400
        case .extraUsage: return nil
        }
    }
}

struct UsageWindow: Codable, Equatable {
    var utilization: Double?
    var resetsAt: Date?
}

/// Who is signed in and on which plan, from the OAuth profile endpoint.
/// Shown in the Allowances card header; the email can be masked.
struct AccountProfile: Codable, Equatable {
    var email: String?
    /// "Max 20x", "Pro", "Team"… nil when the endpoint doesn't say.
    var plan: String?
    var fetchedAt: Date

    /// "m•••@g•••.com", for screenshots with *Hide account* on.
    static func masked(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return "•••" }
        let domain = parts[1]
        let tld = domain.split(separator: ".").last.map { ".\($0)" } ?? ""
        return "\(parts[0].prefix(1))•••@\(domain.prefix(1))•••\(tld)"
    }
}

struct ExtraUsage: Codable, Equatable {
    var isEnabled: Bool
    var monthlyLimit: Double?
    var usedCredits: Double?
    var currency: String?

    var utilization: Double? {
        guard let limit = monthlyLimit, limit > 0, let used = usedCredits else { return nil }
        return used / limit * 100
    }
}

struct UsageSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var session: UsageWindow?
    var weekly: UsageWindow?
    var weeklyOpus: UsageWindow?
    var weeklySonnet: UsageWindow?
    var extra: ExtraUsage?
    /// The weekly allowance of the Fable models (the endpoint's
    /// `weekly_scoped` Fable row). Last, with a default, so older cached
    /// snapshots and existing initializers stay valid.
    var weeklyFable: UsageWindow? = nil

    func window(for kind: MetricKind) -> UsageWindow? {
        switch kind {
        case .session: return session
        case .weekly: return weekly
        case .weeklyFable: return weeklyFable
        case .weeklyOpus: return weeklyOpus
        case .weeklySonnet: return weeklySonnet
        case .extraUsage:
            guard let extra, extra.isEnabled else { return nil }
            return UsageWindow(utilization: extra.utilization, resetsAt: nil)
        }
    }
}
