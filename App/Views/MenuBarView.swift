import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var refresher: UsageRefresher

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Usage").font(.headline)
                Spacer()
                if refresher.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await refresher.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!refresher.isSignedIn)
                }
            }

            if !refresher.isSignedIn {
                SignInView()
            } else if let snapshot = refresher.snapshot {
                ForEach(AppGroupStore.visibleMetrics) { kind in
                    if let window = snapshot.window(for: kind) {
                        MetricRow(kind: kind, window: window)
                    }
                }
                if let error = refresher.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                (Text("Updated ") + Text(snapshot.fetchedAt, style: .relative) + Text(" ago"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Loading usage…")
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings…")
                }
                Spacer()
                if refresher.isSignedIn {
                    Button("Sign Out") { refresher.signOut() }
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
    }
}

struct MetricRow: View {
    let kind: MetricKind
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(kind.title).font(.subheadline)
                Spacer()
                Text("\(Int(window.utilization ?? 0))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(color)
            }
            ProgressView(value: min((window.utilization ?? 0) / 100, 1))
                .tint(color)
            if let resetsAt = window.resetsAt {
                (Text("Resets in ") + Text(resetsAt, style: .relative))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        let value = window.utilization ?? 0
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        return .accentColor
    }
}
