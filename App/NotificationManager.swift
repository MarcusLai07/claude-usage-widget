import Foundation
import UserNotifications

enum NotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Checks the snapshot against the configured thresholds and fires at most
    /// one notification per threshold per reset window.
    static func evaluate(_ snapshot: UsageSnapshot) {
        guard AppGroupStore.notificationsEnabled else { return }
        check(kind: .session, window: snapshot.session, threshold: AppGroupStore.sessionWarnThreshold)
        check(kind: .weekly, window: snapshot.weekly, threshold: AppGroupStore.weeklyWarnThreshold)
    }

    private static func check(kind: MetricKind, window: UsageWindow?, threshold: Double) {
        guard let window, let utilization = window.utilization else { return }

        if AppGroupStore.notifyOnLimitReached, utilization >= 100 {
            let alert = "\(kind.rawValue)-limit"
            if !AppGroupStore.hasNotified(alert, resetsAt: window.resetsAt) {
                AppGroupStore.markNotified(alert, resetsAt: window.resetsAt)
                send(title: "\(kind.title) limit reached",
                     body: resetText(window.resetsAt, prefix: "Usage is at 100%."))
            }
            return
        }

        if utilization >= threshold {
            let alert = "\(kind.rawValue)-warn-\(Int(threshold))"
            if !AppGroupStore.hasNotified(alert, resetsAt: window.resetsAt) {
                AppGroupStore.markNotified(alert, resetsAt: window.resetsAt)
                send(title: "\(kind.title) usage at \(Int(utilization))%",
                     body: resetText(window.resetsAt, prefix: "You set a warning at \(Int(threshold))%."))
            }
        }
    }

    private static func resetText(_ date: Date?, prefix: String) -> String {
        guard let date else { return prefix }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(prefix) Resets \(formatter.localizedString(for: date, relativeTo: Date()))."
    }

    private static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
