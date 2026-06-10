import SwiftUI

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var refresher = UsageRefresher()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(refresher)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Claude Usage", id: "main") {
            MainWindowView()
                .environmentObject(refresher)
        }
        .defaultSize(width: 900, height: 640)
        .defaultLaunchBehavior(.suppressed)
        // Tapping a widget opens claudeusage://open. The only external events
        // this app receives are its own URL scheme, so match everything.
        .handlesExternalEvents(matching: ["*"])

        Settings {
            SettingsView()
                .environmentObject(refresher)
        }
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

/// The menu bar label is the one view that's always alive, so it hosts the
/// bridge from AppKit URL delivery to SwiftUI's openWindow action.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "gauge.with.needle")
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.requestAuthorization()
    }

    /// Widget taps arrive as claudeusage://open URLs.
    func application(_ application: NSApplication, open urls: [URL]) {
        // Delay slightly so the scene graph exists on a cold launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
    }
}
