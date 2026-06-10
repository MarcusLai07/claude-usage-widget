import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case dashboard, analytics, settings, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .analytics: return "Analytics"
        case .settings: return "Settings"
        case .account: return "Account"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.needle"
        case .analytics: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        case .account: return "person.crop.circle"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @StateObject private var analytics = AnalyticsModel()
    @State private var section: MainSection = .dashboard

    var body: some View {
        Group {
            if !refresher.isSignedIn {
                onboarding
            } else {
                NavigationSplitView {
                    List(MainSection.allCases, selection: $section) { item in
                        Label(item.title, systemImage: item.icon)
                            .tag(item)
                    }
                    .navigationSplitViewColumnWidth(min: 170, ideal: 190)
                } detail: {
                    detail
                        .navigationTitle(section.title)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        // Widget taps arrive as claudeusage://open; as an accessory (menu bar)
        // app we must activate explicitly or the window opens behind others.
        .onOpenURL { _ in
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .dashboard:
            DashboardView()
        case .analytics:
            AnalyticsView(model: analytics)
        case .settings:
            WindowSettingsView()
        case .account:
            AccountView()
        }
    }

    private var onboarding: some View {
        VStack(spacing: 0) {
            Spacer()
            SignInView()
                .frame(maxWidth: 320)
            Spacer()
            Text("Your token is stored only in the macOS keychain. The app reads usage metadata — it never invokes models or consumes Claude tokens.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Settings tabs embedded as a single scrolling page in the main window.
struct WindowSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                GroupBox {
                    DisplaySettingsView()
                }
                GroupBox {
                    NotificationSettingsView()
                }
            }
            .padding(20)
        }
    }
}
