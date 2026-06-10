import Foundation

enum MetricKind: String, CaseIterable, Codable, Identifiable {
    case session
    case weekly
    case weeklyOpus
    case weeklySonnet
    case extraUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: return "Session"
        case .weekly: return "Weekly"
        case .weeklyOpus: return "Opus · 7-day"
        case .weeklySonnet: return "Sonnet · 7-day"
        case .extraUsage: return "Extra usage"
        }
    }
}

struct UsageWindow: Codable, Equatable {
    var utilization: Double?
    var resetsAt: Date?
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

    func window(for kind: MetricKind) -> UsageWindow? {
        switch kind {
        case .session: return session
        case .weekly: return weekly
        case .weeklyOpus: return weeklyOpus
        case .weeklySonnet: return weeklySonnet
        case .extraUsage:
            guard let extra, extra.isEnabled else { return nil }
            return UsageWindow(utilization: extra.utilization, resetsAt: nil)
        }
    }
}
