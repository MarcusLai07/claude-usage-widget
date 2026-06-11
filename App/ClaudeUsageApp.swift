import SwiftUI

/// Routes the popover (and deep links) to a specific section of the main
/// window — the window binds its sidebar selection to this.
@MainActor
final class WindowRouter: ObservableObject {
    @Published var section: MainSection = .dashboard
}

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var refresher = UsageRefresher()
    @StateObject private var router = WindowRouter()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(refresher)
                .environmentObject(router)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Claude Usage", id: "main") {
            MainWindowView()
                .environmentObject(refresher)
                .environmentObject(router)
        }
        .defaultSize(width: 900, height: 640)
        .defaultLaunchBehavior(.suppressed)
        // Tapping a widget opens claudeusage://open. The only external events
        // this app receives are its own URL scheme, so match everything.
        .handlesExternalEvents(matching: ["*"])
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

/// The menu bar label is the one view that's always alive, so it hosts the
/// bridge from AppKit URL delivery to SwiftUI's openWindow action.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    /// The sunburst brand mark as a template image, so it adapts to menu bar
    /// appearance (dark/light, active/inactive) like system status items.
    private static let markImage: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let unit = rect.width / 24
            let center = CGPoint(x: rect.midX, y: rect.midY)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(unit * 2.4)
            ctx.setLineCap(.round)
            for i in 0..<12 {
                let angle = CGFloat(i) * 30 * .pi / 180
                ctx.move(to: CGPoint(x: center.x + cos(angle) * unit * 3.2,
                                     y: center.y + sin(angle) * unit * 3.2))
                ctx.addLine(to: CGPoint(x: center.x + cos(angle) * unit * 9,
                                        y: center.y + sin(angle) * unit * 9))
            }
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Image(nsImage: Self.markImage)
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
