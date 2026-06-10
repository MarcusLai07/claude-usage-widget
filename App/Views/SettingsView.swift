import SwiftUI
import WidgetKit

struct SettingsView: View {
    var body: some View {
        TabView {
            DisplaySettingsView()
                .tabItem { Label("Display", systemImage: "rectangle.on.rectangle") }
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 560)
        .padding()
    }
}

private extension MetricKind {
    var settingsSubtitle: String {
        switch self {
        case .session: return "5-hour rolling window"
        case .weekly: return "7-day rolling window"
        case .weeklyOpus: return "7-day Opus allotment"
        case .weeklySonnet: return "7-day Sonnet allotment"
        case .extraUsage: return "Prepaid credit balance"
        }
    }

    var settingsBadge: String {
        switch self {
        case .session: return "5-hr"
        case .weekly, .weeklyOpus, .weeklySonnet: return "7-day"
        case .extraUsage: return "$"
        }
    }
}

struct DisplaySettingsView: View {
    @State private var visible = Set(AppGroupStore.visibleMetrics)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SHOW THESE METRICS IN WIDGETS & MENU BAR")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 10)

            ForEach(MetricKind.allCases) { kind in
                HStack(alignment: .top, spacing: 11) {
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
                    Text(kind.settingsBadge)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                }
                .padding(.vertical, 9)
                if kind != MetricKind.allCases.last {
                    Divider()
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text("The small widget always shows your first two enabled metrics.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
        }
        .padding(.init(top: 18, leading: 22, bottom: 22, trailing: 22))
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

struct NotificationSettingsView: View {
    @State private var enabled = AppGroupStore.notificationsEnabled
    @State private var notifyOnLimit = AppGroupStore.notifyOnLimitReached
    @State private var sessionThreshold = AppGroupStore.sessionWarnThreshold
    @State private var weeklyThreshold = AppGroupStore.weeklyWarnThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOTIFICATIONS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)

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

            Text("ALERT THRESHOLDS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .padding(.init(top: 22, leading: 0, bottom: 6, trailing: 0))

            Group {
                thresholdRow(title: "Session warning", value: $sessionThreshold)
                    .onChange(of: sessionThreshold) { _, value in AppGroupStore.sessionWarnThreshold = value }
                Divider()
                thresholdRow(title: "Weekly warning", value: $weeklyThreshold)
                    .onChange(of: weeklyThreshold) { _, value in AppGroupStore.weeklyWarnThreshold = value }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text("Thresholds fire once per rolling window so you're not alerted repeatedly.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
        }
        .padding(.init(top: 18, leading: 22, bottom: 22, trailing: 22))
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
        .padding(.vertical, 11)
    }

    private func thresholdRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
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
        .padding(.vertical, 13)
    }
}
