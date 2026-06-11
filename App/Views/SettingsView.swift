import SwiftUI
import WidgetKit

/// Standalone Settings scene (⌘,) — same cards as the window's Settings page.
struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DisplaySettingsView()
                NotificationSettingsView()
            }
            .padding(20)
        }
        .frame(width: 560, height: 620)
        .background(Color.windowContent)
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

            hint("Widgets show your first two enabled metrics. The small widget always leads with these.")
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
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)

            hint("Each threshold fires once per rolling window so you're not alerted repeatedly.")
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

func hint(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Image(systemName: "info.circle")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
    }
    .padding(.top, 13)
}
