import Foundation

/// Settings and the latest usage snapshot, shared between the app and the
/// widget extension through an App Group UserDefaults suite. Tokens never
/// live here — they stay in the keychain.
enum AppGroupStore {
    static let suiteName = "group.com.marcuslai.ClaudeUsage"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private enum Key {
        static let snapshot = "cachedSnapshot"
        static let visibleMetrics = "visibleMetrics"
        static let notificationsEnabled = "notificationsEnabled"
        static let sessionWarnThreshold = "sessionWarnThreshold"
        static let weeklyWarnThreshold = "weeklyWarnThreshold"
        static let notifyOnLimitReached = "notifyOnLimitReached"
        static let notifiedKeys = "notifiedKeys"
    }

    // MARK: Cached usage

    static var cachedSnapshot: UsageSnapshot? {
        get {
            guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
            return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.snapshot)
            } else {
                defaults.removeObject(forKey: Key.snapshot)
            }
        }
    }

    // MARK: Display settings

    static var visibleMetrics: [MetricKind] {
        get {
            guard let raw = defaults.stringArray(forKey: Key.visibleMetrics) else {
                return [.session, .weekly]
            }
            return raw.compactMap(MetricKind.init(rawValue:))
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Key.visibleMetrics) }
    }

    // MARK: Notification settings

    static var notificationsEnabled: Bool {
        get { defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    static var notifyOnLimitReached: Bool {
        get { defaults.object(forKey: Key.notifyOnLimitReached) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifyOnLimitReached) }
    }

    static var sessionWarnThreshold: Double {
        get { defaults.object(forKey: Key.sessionWarnThreshold) as? Double ?? 80 }
        set { defaults.set(newValue, forKey: Key.sessionWarnThreshold) }
    }

    static var weeklyWarnThreshold: Double {
        get { defaults.object(forKey: Key.weeklyWarnThreshold) as? Double ?? 80 }
        set { defaults.set(newValue, forKey: Key.weeklyWarnThreshold) }
    }

    // MARK: Notification dedupe (one alert per threshold per reset window)

    static func hasNotified(_ key: String) -> Bool {
        (defaults.stringArray(forKey: Key.notifiedKeys) ?? []).contains(key)
    }

    static func markNotified(_ key: String) {
        var keys = defaults.stringArray(forKey: Key.notifiedKeys) ?? []
        keys.append(key)
        defaults.set(Array(keys.suffix(50)), forKey: Key.notifiedKeys)
    }
}
