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
        static let accountProfile = "accountProfile"
    }

    /// Keys views bind with `@AppStorage(…, store: AppGroupStore.defaults)`,
    /// so a change in one window re-renders the others.
    enum SharedKey {
        static let showLeft = "showLeft"
        static let hideAccount = "hideAccount"
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

    /// Show what's left of each window instead of what's used (Magpie's
    /// Used/Left switch). Applies everywhere: window, popover, widgets.
    static var showLeft: Bool {
        get { defaults.bool(forKey: SharedKey.showLeft) }
        set { defaults.set(newValue, forKey: SharedKey.showLeft) }
    }

    /// Mask the account email, for screenshots.
    static var hideAccount: Bool {
        get { defaults.bool(forKey: SharedKey.hideAccount) }
        set { defaults.set(newValue, forKey: SharedKey.hideAccount) }
    }

    // MARK: Account

    static var accountProfile: AccountProfile? {
        get {
            guard let data = defaults.data(forKey: Key.accountProfile) else { return nil }
            return try? JSONDecoder().decode(AccountProfile.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.accountProfile)
            } else {
                defaults.removeObject(forKey: Key.accountProfile)
            }
        }
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

    /// Keys are `<alert>-<reset epoch seconds>`, e.g. "session-warn-80-1763373600",
    /// or `<alert>-current` for a window without a reset time.
    static func notificationKey(_ alert: String, resetsAt: Date?) -> String {
        "\(alert)-\(resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "current")"
    }

    /// Whether `alert` already fired for this window.
    static func hasNotified(_ alert: String, resetsAt: Date?) -> Bool {
        alreadyNotified(alert, resetsAt: resetsAt,
                        in: defaults.stringArray(forKey: Key.notifiedKeys) ?? [])
    }

    static func markNotified(_ alert: String, resetsAt: Date?) {
        var keys = defaults.stringArray(forKey: Key.notifiedKeys) ?? []
        keys.append(notificationKey(alert, resetsAt: resetsAt))
        defaults.set(Array(keys.suffix(50)), forKey: Key.notifiedKeys)
    }

    /// The same window's reset moves by a second or so between reads
    /// (09:59:59.6, then 10:00:00), so a recorded reset within `slack` of
    /// this one counts as the same window. Real cycles are hours apart.
    static func alreadyNotified(_ alert: String, resetsAt: Date?, in keys: [String],
                                slack: TimeInterval = 5 * 60) -> Bool {
        guard let resetsAt else {
            return keys.contains(notificationKey(alert, resetsAt: nil))
        }
        let prefix = "\(alert)-"
        return keys.contains { key in
            guard key.hasPrefix(prefix),
                  let epoch = TimeInterval(key.dropFirst(prefix.count)) else { return false }
            return abs(epoch - resetsAt.timeIntervalSince1970) <= slack
        }
    }
}
