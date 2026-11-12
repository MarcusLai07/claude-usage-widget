import SwiftUI
import WidgetKit

private extension MetricKind {
    var settingsSubtitle: String {
        switch self {
        case .session: return "5-hour rolling window"
        case .weekly: return "7-day rolling window"
        case .weeklyFable: return "7-day Fable allotment"
        case .weeklyOpus: return "7-day Opus allotment"
        case .weeklySonnet: return "7-day Sonnet allotment"
        case .extraUsage: return "Prepaid credit balance"
        }
    }

    var settingsBadge: String {
        switch self {
        case .session: return "5-hr"
        case .weekly, .weeklyFable, .weeklyOpus, .weeklySonnet: return "7-day"
        case .extraUsage: return "$"
        }
    }
}

struct DisplaySettingsView: View {
    @State private var visible = Set(AppGroupStore.visibleMetrics)
    @AppStorage(AppGroupStore.SharedKey.showLeft, store: AppGroupStore.defaults)
    private var showLeft = false
    @AppStorage(AppGroupStore.SharedKey.hideAccount, store: AppGroupStore.defaults)
    private var hideAccount = false
    @AppStorage(AppGroupStore.SharedKey.menuBarStyle, store: AppGroupStore.defaults)
    private var menuBarStyle: MenuBarStyle = .percentages

    private var unreported: Set<MetricKind> {
        guard let snapshot = AppGroupStore.cachedSnapshot else { return [] }
        return Set(MetricKind.allCases.filter { snapshot.window(for: $0) == nil })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("Visible metrics")
                .padding(.bottom, 4)

            ForEach(MetricKind.allCases) { kind in
                HStack(alignment: .center, spacing: 12) {
                    Toggle("", isOn: binding(for: kind))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                            .font(.system(size: 13, weight: .medium))
                        Text(kind.settingsSubtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if unreported.contains(kind) {
                        badge("no data yet", color: .orange)
                            .help("Anthropic isn't reporting this metric for your account right now. It appears automatically once reported.")
                    }
                    badge(kind.settingsBadge, color: nil)
                }
                .padding(.vertical, 11)
                if kind != MetricKind.allCases.last {
                    Divider()
                }
            }

            HintRow("Widgets show your first two enabled metrics. The small widget always leads with these.")

            Divider()
                .padding(.top, 14)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show percentages as")
                        .font(.system(size: 13, weight: .medium))
                    Text("What's used, or what's left — in the window, menu bar and widgets")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Show percentages as", selection: $showLeft) {
                    Text("Used").tag(false)
                    Text("Left").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.vertical, 12)
            .onChange(of: showLeft) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Menu bar")
                        .font(.system(size: 13, weight: .medium))
                    Text("Session over Weekly beside the icon, as used or left")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Menu bar", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.vertical, 12)
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hide account email")
                        .font(.system(size: 13, weight: .medium))
                    Text("Masks it on the Usage and Account pages, for screenshots")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Hide account email", isOn: $hideAccount)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    private func badge(_ text: String, color: Color?) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color?.opacity(0.14).asAnyShapeStyle ?? AnyShapeStyle(.quaternary)))
    }

    private func binding(for kind: MetricKind) -> Binding<Bool> {
        Binding(
            get: { visible.contains(kind) },
            set: { isOn in
                if isOn { visible.insert(kind) } else { visible.remove(kind) }
                AppGroupStore.visibleMetrics = MetricKind.allCases.filter(visible.contains)
                WidgetCenter.shared.reloadAllTimelines()
            }
        )
    }
}

private extension Color {
    var asAnyShapeStyle: AnyShapeStyle { AnyShapeStyle(self) }
}

struct NotificationSettingsView: View {
    @State private var enabled = AppGroupStore.notificationsEnabled
    @State private var notifyOnLimit = AppGroupStore.notifyOnLimitReached
    @State private var sessionThreshold = AppGroupStore.sessionWarnThreshold
    @State private var weeklyThreshold = AppGroupStore.weeklyWarnThreshold
    @AppStorage(AppGroupStore.SharedKey.resetReminderEnabled, store: AppGroupStore.defaults)
    private var resetReminder = true
    @AppStorage(AppGroupStore.SharedKey.resetReminderHours, store: AppGroupStore.defaults)
    private var reminderHours = 12
    @AppStorage(AppGroupStore.SharedKey.resetReminderMinLeft, store: AppGroupStore.defaults)
    private var reminderMinLeft = 40.0
    @AppStorage(AppGroupStore.SharedKey.paceAlertEnabled, store: AppGroupStore.defaults)
    private var paceAlert = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("Notifications")
                .padding(.bottom, 4)

            toggleRow(title: "Enable notifications",
                      subtitle: "Master switch for all usage alerts",
                      isOn: $enabled)
                .onChange(of: enabled) { _, value in AppGroupStore.notificationsEnabled = value }
            Divider()
            toggleRow(title: "Notify when a limit is reached",
                      subtitle: "Alert at 100% for Session or Weekly",
                      isOn: $notifyOnLimit)
                .onChange(of: notifyOnLimit) { _, value in AppGroupStore.notifyOnLimitReached = value }
                .disabled(!enabled)
            Divider()

            Group {
                thresholdRow(title: "Session warning", value: $sessionThreshold)
                    .onChange(of: sessionThreshold) { _, value in AppGroupStore.sessionWarnThreshold = value }
                Divider()
                thresholdRow(title: "Weekly warning", value: $weeklyThreshold)
                    .onChange(of: weeklyThreshold) { _, value in AppGroupStore.weeklyWarnThreshold = value }
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    toggleRow(title: "Remind me before the weekly reset",
                              subtitle: "When much of the week is still unused — it doesn't carry over",
                              isOn: $resetReminder)
                    HStack(spacing: 8) {
                        Text("Up to")
                        Picker("Hours before the reset", selection: $reminderHours) {
                            ForEach([3, 6, 12, 24], id: \.self) { Text("\($0) hours").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Text("before it, with at least")
                        Picker("Least left", selection: $reminderMinLeft) {
                            ForEach([20.0, 30, 40, 50, 60], id: \.self) { Text("\(Int($0))%").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Text("left")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                    .disabled(!resetReminder)
                    .opacity(resetReminder ? 1 : 0.5)
                }
                Divider()
                toggleRow(title: "Warn when on pace to run out early",
                          subtitle: "When the weekly limit would run out 6+ hours before it resets",
                          isOn: $paceAlert)
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)

            HintRow("Each alert fires once per window so you're not alerted repeatedly.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 12)
    }

    private func thresholdRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(usageColor(value.wrappedValue))
            }
            Slider(value: value, in: 50...95, step: 5)
            HStack {
                Text("50%")
                Spacer()
                Text("95%")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
    }
}
