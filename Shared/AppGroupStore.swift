import Foundation

/// Settings and the latest usage snapshot, shared between the app and the
/// widget extension through an App Group UserDefaults suite. Tokens never
/// live here — they stay in the keychain.
enum AppGroupStore {
    /// Team-prefixed, as macOS expects: a `group.`-style id has to be
    /// authorized by the provisioning profile, which the development
    /// profile doesn't do, so every access to it asked "would like to access
    /// data from other apps" (and blocked the thread that asked).
    static let suiteName = "P7DV5ZUK9A.com.marcuslai.ClaudeUsage"
    /// The group used before 0.6.1; read once, to move its data over.
    static let legacySuiteName = "group.com.marcuslai.ClaudeUsage"

    static var defaults: UserDefaults {
        #if SHOTS
        // The screenshot tool (Shots/) keeps to its own defaults.
        return .standard
        #else
        UserDefaults(suiteName: suiteName) ?? .standard
        #endif
    }

    /// Moves settings, folder grants, usage history and logs from the old
    /// group, once. Reading the old group asks for permission one last time;
    /// declined, the app starts with empty history and the old data stays
    /// where it was. The transcript cache isn't moved: a scan rebuilds it.
    static func migrateLegacyGroupIfNeeded() {
        let doneKey = "migratedFromLegacyGroup"
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        // A store that already has a snapshot has nothing to receive.
        guard defaults.object(forKey: Key.snapshot) == nil else { return }

        if let legacy = UserDefaults(suiteName: legacySuiteName),
           let values = legacy.persistentDomain(forName: legacySuiteName) {
            for (key, value) in values where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        let files = FileManager.default
        guard let from = files.containerURL(forSecurityApplicationGroupIdentifier: legacySuiteName),
              let to = files.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else { return }
        for name in ["usage-history.jsonl", "usage-history.old.jsonl", "perf-log.jsonl", "perf-log.old.jsonl"] {
            let source = from.appendingPathComponent(name)
            let target = to.appendingPathComponent(name)
            if files.fileExists(atPath: source.path), !files.fileExists(atPath: target.path) {
                try? files.copyItem(at: source, to: target)
            }
        }
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
        static let menuBarStyle = "menuBarStyle"
        static let resetReminderEnabled = "resetReminderEnabled"
        static let resetReminderHours = "resetReminderHours"
        static let resetReminderMinLeft = "resetReminderMinLeft"
        static let paceAlertEnabled = "paceAlertEnabled"
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

    /// Remind before the weekly reset when much of the week is unused.
    static var resetReminderEnabled: Bool {
        defaults.object(forKey: SharedKey.resetReminderEnabled) as? Bool ?? true
    }

    /// How long before the weekly reset the reminder may come.
    static var resetReminderHours: Int {
        defaults.object(forKey: SharedKey.resetReminderHours) as? Int ?? 12
    }

    /// The least % left worth a reminder.
    static var resetReminderMinLeft: Double {
        defaults.object(forKey: SharedKey.resetReminderMinLeft) as? Double ?? 40
    }

    /// Warn when the weekly limit is on pace to run out well before it resets.
    static var paceAlertEnabled: Bool {
        defaults.object(forKey: SharedKey.paceAlertEnabled) as? Bool ?? true
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
