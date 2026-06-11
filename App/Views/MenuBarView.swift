import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @EnvironmentObject private var router: WindowRouter
    @Environment(\.openWindow) private var openWindow
    // The popover view persists between opens, so re-render when settings
    // (visible metrics, thresholds) change in the window or Settings pane.
    @State private var settingsTick = 0

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                settingsTick &+= 1
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if !refresher.isSignedIn {
                signedOutPrompt
            } else {
                header
                if refresher.isStale {
                    staleBanner
                }
                if let snapshot = refresher.snapshot {
                    metricList(snapshot)
                    updatedLine(snapshot)
                } else {
                    ProgressView("Loading usage…")
                        .controlSize(.small)
                        .padding(.vertical, 24)
                }
                Divider()
                    .padding(.top, 6)
                footer
            }
        }
        .frame(width: 320)
    }

    private var signedOutPrompt: some View {
        VStack(spacing: 13) {
            SunburstMark(size: 28)
                .padding(.top, 8)
            Text("Claude Usage")
                .font(.system(size: 15, weight: .semibold))
            Text("Sign in to see your session and weekly limits.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                openMain(.dashboard)
            } label: {
                Text("Open Claude Usage to Sign In")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.clay, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                SunburstMark(size: 16)
                Text("Claude Usage")
                    .font(.headline)
            }
            Spacer()
            if refresher.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await refresher.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }
        }
        .padding(.init(top: 13, leading: 14, bottom: 11, trailing: 14))
    }

    /// Opens the main window at a specific section (shared stale banner and
    /// settings/dashboard rows all route through here).
    private func openMain(_ section: MainSection) {
        router.section = section
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    private var staleBanner: some View {
        StaleBanner()
            .padding(.init(top: 0, leading: 14, bottom: 6, trailing: 14))
    }

    private func metricList(_ snapshot: UsageSnapshot) -> some View {
        let displays = MetricPresentation.displays(for: snapshot, kinds: AppGroupStore.visibleMetrics)
        return VStack(spacing: 13) {
            ForEach(displays) { metric in
                MetricBarRow(metric: metric)
            }
            if displays.isEmpty {
                Text("No metrics enabled — pick some in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.init(top: 2, leading: 14, bottom: 4, trailing: 14))
    }

    private func updatedLine(_ snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: refresher.isStale ? "clock.badge.exclamationmark" : "clock")
                .font(.system(size: 10))
            (Text(refresher.isStale ? "Last updated " : "Updated ")
             + Text(snapshot.fetchedAt, style: .relative) + Text(" ago"))
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 1) {
            Button {
                openMain(.dashboard)
            } label: {
                MenuRow(icon: "macwindow", title: "Open Claude Usage…", shortcut: "⌘O")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o")

            Button {
                openMain(.settings)
            } label: {
                MenuRow(icon: "gearshape", title: "Settings…", shortcut: "⌘,")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")

            Button {
                refresher.signOut()
            } label: {
                MenuRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out", shortcut: nil)
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                MenuRow(icon: "power", title: "Quit Claude Usage", shortcut: "⌘Q")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.init(top: 5, leading: 6, bottom: 7, trailing: 6))
    }
}

/// One footer menu row: icon, label, optional shortcut hint, hover highlight.
struct MenuRow: View {
    let icon: String
    let title: String
    let shortcut: String?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.init(top: 8, leading: 9, bottom: 8, trailing: 9))
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
