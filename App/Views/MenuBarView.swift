import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            if !refresher.isSignedIn {
                SignInView()
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

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            if let fetchedAt = refresher.snapshot?.fetchedAt {
                (Text("Couldn't refresh — showing data from ")
                 + Text(fetchedAt, style: .relative) + Text(" ago."))
                    .font(.system(size: 11))
            } else {
                Text("Couldn't refresh.")
                    .font(.system(size: 11))
            }
            Spacer()
            Button("Retry") {
                Task { await refresher.refresh(force: true) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.clay)
        }
        .padding(.init(top: 8, leading: 10, bottom: 8, trailing: 10))
        .background(.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
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
                // Accessory apps open the Settings window unfocused (or not at
                // all via SettingsLink) unless the app is activated first.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
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
