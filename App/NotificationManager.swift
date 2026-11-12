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
        remindBeforeReset(snapshot.weekly)
    }

    // MARK: Reset reminder

    /// Once per cycle: the weekly limit resets soon with much of it unused,
    /// so it isn't wasted (Magpie's reset reminder).
    static func remindBeforeReset(_ window: UsageWindow?, now: Date = Date()) {
        guard AppGroupStore.resetReminderEnabled,
              let window, let used = window.utilization, let reset = window.resetsAt else { return }
        let left = max(0, 100 - used)
        let untilReset = reset.timeIntervalSince(now)
        guard untilReset > 0,
              untilReset <= TimeInterval(AppGroupStore.resetReminderHours) * 3600,
              left >= AppGroupStore.resetReminderMinLeft else { return }
        let alert = "weekly-reset-reminder"
        guard !AppGroupStore.hasNotified(alert, resetsAt: reset) else { return }
        AppGroupStore.markNotified(alert, resetsAt: reset)
        let when = reset.formatted(.relative(presentation: .named))
        send(title: "Weekly limit resets \(when)",
             body: "\(Int(left.rounded()))% of it is still unused, and it doesn't carry over.")
    }

    // MARK: Pace alert

    /// How early a run-out has to be to warn about it.
    static let paceAlertMargin: TimeInterval = 6 * 3600

    /// Once per cycle: at this cycle's pace the weekly limit runs out more
    /// than six hours before it resets. Reads the week's history, so call
    /// it off the main thread.
    static func checkPace(_ snapshot: UsageSnapshot, now: Date = Date()) {
        guard AppGroupStore.notificationsEnabled, AppGroupStore.paceAlertEnabled,
              let window = snapshot.weekly, let reset = window.resetsAt, reset > now,
              let span = MetricKind.weekly.span else { return }
        let alert = "weekly-pace"
        guard !AppGroupStore.hasNotified(alert, resetsAt: reset) else { return }
        let cycle = CurrentCycle(start: reset.addingTimeInterval(-span), reset: reset)
        let line = UsageTrends.lines(from: UsageHistory.load(since: cycle.start))
            .first { $0.kind == .weekly }
        guard let line,
              case .runsOut(let out)? = UsageTrends.forecast(points: line.points, cycle: cycle, now: now),
              reset.timeIntervalSince(out) > paceAlertMargin else { return }
        AppGroupStore.markNotified(alert, resetsAt: reset)
        send(title: "On pace to run out early",
             body: paceText(runsOut: out, reset: reset, now: now))
    }

    /// "At this pace your weekly limit runs out Sat 14:00, 1 day before it resets."
    static func paceText(runsOut out: Date, reset: Date, now: Date) -> String {
        let when = Calendar.current.isDate(out, inSameDayAs: now)
            ? "today at \(out.formatted(.dateTime.hour().minute()))"
            : out.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let early = DateComponentsFormatter()
        early.unitsStyle = .full
        early.allowedUnits = [.day, .hour]
        early.maximumUnitCount = 1
        let gap = early.string(from: reset.timeIntervalSince(out)) ?? "well"
        return "At this pace your weekly limit runs out \(when), \(gap) before it resets."
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
