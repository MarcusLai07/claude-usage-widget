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
            Image(systemName: "gauge.with.needle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(refresher)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.requestAuthorization()
    }
}
