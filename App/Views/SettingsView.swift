import SwiftUI
import WidgetKit

struct SettingsView: View {
    var body: some View {
        TabView {
            DisplaySettingsView()
                .tabItem { Label("Display", systemImage: "rectangle.3.group") }
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 420)
        .padding()
    }
}

struct DisplaySettingsView: View {
    @State private var visible = Set(AppGroupStore.visibleMetrics)

    var body: some View {
        Form {
            Section("Show these metrics in the widget and menu bar:") {
                ForEach(MetricKind.allCases) { kind in
                    Toggle(kind.title, isOn: binding(for: kind))
                }
            }
        }
        .formStyle(.grouped)
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
        Form {
            Toggle("Enable notifications", isOn: $enabled)
                .onChange(of: enabled) { _, value in AppGroupStore.notificationsEnabled = value }

            Toggle("Notify when a limit is reached", isOn: $notifyOnLimit)
                .onChange(of: notifyOnLimit) { _, value in AppGroupStore.notifyOnLimitReached = value }
                .disabled(!enabled)

            Section("Early warning thresholds") {
                ThresholdSlider(title: "Session", value: $sessionThreshold)
                    .onChange(of: sessionThreshold) { _, value in AppGroupStore.sessionWarnThreshold = value }
                ThresholdSlider(title: "Weekly", value: $weeklyThreshold)
                    .onChange(of: weeklyThreshold) { _, value in AppGroupStore.weeklyWarnThreshold = value }
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
    }
}

struct ThresholdSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: 50...95, step: 5)
            Text("\(Int(value))%")
                .font(.body.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }
}
