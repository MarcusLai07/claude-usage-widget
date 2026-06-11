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
        case .dashboard: return "gauge.medium"
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
                OnboardingView()
            } else {
                NavigationSplitView {
                    sidebar
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

    // MARK: Sidebar — brand lockup, clay-tinted selection, live status footer

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                SunburstMark(size: 19)
                Text("Claude Usage")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.init(top: 6, leading: 8, bottom: 12, trailing: 8))

            ForEach(MainSection.allCases) { item in
                navRow(item)
            }

            Spacer()

            VStack(spacing: 0) {
                Divider()
                footerStatus
                    .padding(.init(top: 8, leading: 8, bottom: 2, trailing: 8))
            }
        }
        .padding(.init(top: 4, leading: 10, bottom: 9, trailing: 10))
        .navigationSplitViewColumnWidth(204)
    }

    private func navRow(_ item: MainSection) -> some View {
        let selected = section == item
        return Button {
            section = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Color.clay : Color.secondary)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.clay : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.init(top: 7, leading: 8, bottom: 7, trailing: 8))
            .background(selected ? Color.clay.opacity(0.2) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var footerStatus: some View {
        HStack(spacing: 7) {
            if refresher.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Refreshing…")
            } else if refresher.isStale, let fetchedAt = refresher.snapshot?.fetchedAt {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 11))
                (Text("Stale · ") + Text(fetchedAt, style: .relative) + Text(" ago"))
                    .foregroundStyle(.orange)
            } else if let fetchedAt = refresher.snapshot?.fetchedAt {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                Text("Updated ") + Text(fetchedAt, style: .relative) + Text(" ago")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
}

// MARK: - Onboarding (full window, signed out)

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            SunburstMark(size: 52)
                .padding(.bottom, 18)
            Text("Welcome to Claude Usage")
                .font(.system(size: 26, weight: .bold))
                .padding(.bottom, 10)
            Text("Keep an eye on your Claude plan limits right from the menu bar and desktop. Sign in to see your session and weekly usage, model breakdowns, and reset countdowns.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 380)
                .padding(.bottom, 26)
            SignInView()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12))
                Text("Your token is stored only in the macOS Keychain and never leaves this Mac. Reading your usage costs **zero** Claude tokens.")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: 340)
            .padding(.top, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowContent)
    }
}

/// Settings rendered as a page in the main window.
struct WindowSettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Settings")
            ScrollView {
                VStack(spacing: 16) {
                    DisplaySettingsView()
                    NotificationSettingsView()
                }
                .padding(.init(top: 4, leading: 22, bottom: 22, trailing: 22))
            }
        }
        .background(Color.windowContent)
    }
}
