import SwiftUI

/// Routes the popover (and deep links) to a specific section of the main
/// window — the window binds its sidebar selection to this.
@MainActor
final class WindowRouter: ObservableObject {
    @Published var section: MainSection = .usage
}

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var refresher = UsageRefresher()
    @StateObject private var router = WindowRouter()

    init() {
        // Before anything reads the store: bring the old group's data over.
        AppGroupStore.migrateLegacyGroupIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(refresher)
                .environmentObject(router)
        } label: {
            MenuBarLabel(refresher: refresher)
        }
        .menuBarExtraStyle(.window)

        Window("Claude Usage", id: "main") {
            MainWindowView()
                .environmentObject(refresher)
                .environmentObject(router)
        }
        .defaultSize(width: 1180, height: 820)
        .defaultLaunchBehavior(.suppressed)
        // Tapping a widget opens claudeusage://open. The only external events
        // this app receives are its own URL scheme, so match everything.
        .handlesExternalEvents(matching: ["*"])
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

/// What the menu bar shows beside nothing but the icon.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon, percentages

    var id: String { rawValue }
    var title: String {
        switch self {
        case .icon: return "Icon"
        case .percentages: return "Icon + percentages"
        }
    }
}

/// The menu bar label is the one view that's always alive, so it hosts the
/// bridge from AppKit URL delivery to SwiftUI's openWindow action.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var refresher: UsageRefresher
    @AppStorage(AppGroupStore.SharedKey.menuBarStyle, store: AppGroupStore.defaults)
    private var style: MenuBarStyle = .percentages
    @AppStorage(AppGroupStore.SharedKey.showLeft, store: AppGroupStore.defaults)
    private var showLeft = false

    var body: some View {
        Image(nsImage: image)
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
    }

    /// The icon, or the icon with Session over Weekly beside it (Magpie's
    /// menu bar), in the Used/Left figure the rest of the app shows.
    private var image: NSImage {
        guard style == .percentages, refresher.isSignedIn, let snapshot = refresher.snapshot else {
            return MenuBarIcon.mark
        }
        let figures = [snapshot.session, snapshot.weekly].compactMap { window -> String? in
            guard let window else { return nil }
            let used = Int(window.utilization ?? 0)
            return "\(showLeft ? max(0, 100 - used) : used)%"
        }
        guard !figures.isEmpty else { return MenuBarIcon.mark }
        return MenuBarIcon.label(figures)
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
