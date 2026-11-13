import AppKit
import SwiftUI
import WidgetKit

// Renders the README screenshots: the app's and the widget's real views, fed
// the sample account in SampleData.swift, drawn in windows that are never
// put on screen, saved as 2x PNGs in dark appearance. No Dock icon, no
// focus taken, no keychain, network, ~/.claude or app group (see Inert.swift).
//
//   ClaudeUsageShots <out-dir> [shot …] [-settle 3] [-height 820]
//
// With no shot names it renders them all (see `shots` below). `-settle` is how
// many seconds a window gets to load before it is drawn; `-height` draws the
// window taller than its default 820 pt, to see a whole page.

final class ShotDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await shoot()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("ClaudeUsageShots: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }
}

struct ShotError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// macOS widget sizes in points, and the system's look around the content.
enum WidgetSize {
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large = CGSize(width: 364, height: 382)
    static let cornerRadius: CGFloat = 22
}

/// The window's default size (ClaudeUsageApp's `.defaultSize`).
let windowSize = CGSize(width: 1180, height: 820)

// An accessory app: no Dock icon, never activated, so it can't take focus.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = ShotDelegate()
app.delegate = delegate
app.run()

@MainActor
func shoot() async throws {
    // Positional arguments; `-key value` pairs are UserDefaults' to read.
    var arguments: [String] = []
    var rest = CommandLine.arguments[...]
    while let argument = rest.popFirst() {
        if argument.hasPrefix("-") { _ = rest.popFirst() } else { arguments.append(argument) }
    }
    guard arguments.count >= 2 else {
        throw ShotError(message: "usage: ClaudeUsageShots <out-dir> [shot …] [-settle 3]")
    }
    let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let wanted = Set(arguments.dropFirst(2))
    let settle = UserDefaults.standard.double(forKey: "settle") > 0 ? UserDefaults.standard.double(forKey: "settle") : 3

    // Settings, in memory only (the registration domain is never saved).
    UserDefaults.standard.register(defaults: [
        "visibleMetrics": SampleData.visibleMetrics.map(\.rawValue),
        AppGroupStore.SharedKey.showLeft: false,
        AppGroupStore.SharedKey.hideAccount: false,
        AppGroupStore.SharedKey.menuBarStyle: MenuBarStyle.percentages.rawValue,
        "usagePeriod": UsagePeriod.month.rawValue,
        "trendRange": TrendRange.cycle.rawValue,
    ])

    let now = Date()
    let sample = SampleData.make(now: now)
    UsageHistory.shotsHistory = sample.history
    AnalyticsModel.shotsScan = sample.scan

    // The refresher's own first refresh finds no token (Inert.swift) and
    // stops; then it is handed the sample account.
    let refresher = UsageRefresher()
    try await Task.sleep(for: .milliseconds(300))
    refresher.snapshot = sample.snapshot
    refresher.profile = sample.profile
    refresher.isSignedIn = true
    let router = WindowRouter()

    // The sample week should read as healthy; say so when it doesn't.
    if let weekly = UsageTrends.lines(from: sample.history).first(where: { $0.kind == .weekly }),
       let cycle = UsageTrends.currentCycle(of: weekly, window: sample.snapshot.weekly, now: now),
       case .runsOut(let date)? = UsageTrends.forecast(points: weekly.points.filter { $0.at >= cycle.start },
                                                      cycle: cycle, now: now) {
        print("note: the sample week's forecast runs out \(date.formatted()), before its reset")
    }

    /// A widget entry for the sample account; `metrics` are the limits picked
    /// in Settings.
    func entry(_ metrics: [MetricKind], snapshot: UsageSnapshot = sample.snapshot,
               trend: Bool = false) -> UsageEntry {
        UsageEntry(date: now, snapshot: snapshot, visibleMetrics: metrics,
                   signedIn: true, isStale: false, showLeft: false, plan: sample.profile.plan,
                   trend: trend ? WidgetTrend.make(snapshot: snapshot, now: now) : nil)
    }
    let all = SampleData.visibleMetrics
    // As of 0.6.2 three rows overflow the 170 pt medium Bars widget, so it
    // shows the app's default two limits.
    let defaultMetrics: [MetricKind] = [.session, .weekly]
    // As of 0.6.2 the large Bars widget's curve legend wraps with more than
    // two weekly windows, so its account shows Weekly and Opus only.
    var weeklyAndOpus = sample.snapshot
    weeklyAndOpus.weeklyFable = nil
    weeklyAndOpus.weeklySonnet = nil

    let shots: [(name: String, render: () async throws -> CGSize)] = [
        ("popover", {
            try await render(PopoverChrome { MenuBarView() }
                .environmentObject(refresher).environmentObject(router),
                size: nil, settle: 1, to: folder.appendingPathComponent("popover.png"))
        }),
        ("menubar", {
            // The menu bar tints its template image white in dark mode.
            try await render(MenuBarLabel(refresher: refresher).foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1),
                             size: nil, settle: 0.5, to: folder.appendingPathComponent("menubar.png"))
        }),
        ("widget-rings-small", {
            try await render(WidgetChrome(family: .systemSmall) { RingsWidgetView(entry: entry(all)) },
                             size: WidgetSize.small, settle: 0.5,
                             to: folder.appendingPathComponent("widget-rings-small.png"))
        }),
        ("widget-bars-medium", {
            try await render(WidgetChrome(family: .systemMedium) { BarsWidgetView(entry: entry(defaultMetrics)) },
                             size: WidgetSize.medium, settle: 0.5,
                             to: folder.appendingPathComponent("widget-bars-medium.png"))
        }),
        ("widget-rings-medium", {
            try await render(WidgetChrome(family: .systemMedium) { RingsWidgetView(entry: entry(all)) },
                             size: WidgetSize.medium, settle: 0.5,
                             to: folder.appendingPathComponent("widget-rings-medium.png"))
        }),
        ("widget-bars-large", {
            try await render(WidgetChrome(family: .systemLarge) {
                BarsWidgetView(entry: entry(all, snapshot: weeklyAndOpus, trend: true))
            },
                             size: WidgetSize.large, settle: 0.5,
                             to: folder.appendingPathComponent("widget-bars-large.png"))
        }),
    ] + [UsageTab.overview, .requests, .sessions, .context].map { tab in
        (tab == .overview ? "window-usage" : "window-\(tab.rawValue)", {
            router.section = .usage
            UsageView.shotsTab = tab
            return try await render(MainWindowView().environmentObject(refresher).environmentObject(router),
                                    size: CGSize(width: windowSize.width,
                                                 height: max(windowSize.height, UserDefaults.standard.double(forKey: "height"))),
                                    settle: settle,
                                    to: folder.appendingPathComponent(tab == .overview
                                        ? "window-usage.png" : "window-\(tab.rawValue).png"))
        })
    }

    let unknown = wanted.subtracting(shots.map(\.name))
    guard unknown.isEmpty else {
        throw ShotError(message: "unknown shot \(unknown.sorted().joined(separator: ", ")); "
                        + "shots: \(shots.map(\.name).joined(separator: " "))")
    }
    for shot in shots where wanted.isEmpty || wanted.contains(shot.name) {
        let size = try await shot.render()
        print("wrote \(shot.name).png  \(Int(size.width * 2))×\(Int(size.height * 2)) px")
    }
}

// MARK: - Drawing

/// Draws `view` in a borderless window that is never ordered on screen and
/// writes it as a 2x PNG; transparent wherever the view draws nothing.
/// `size` nil: the view's own fitting size.
@MainActor
func render(_ view: some View, size: CGSize?, settle: Double, to url: URL) async throws -> CGSize {
    let dark = NSAppearance(named: .darkAqua)
    let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
    hosting.appearance = dark
    hosting.frame = CGRect(origin: .zero, size: size ?? hosting.fittingSize)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.appearance = dark
    window.contentView = hosting
    defer { window.contentView = nil; window.close() }

    try await Task.sleep(for: .seconds(settle))
    if size == nil { hosting.setFrameSize(hosting.fittingSize) }
    hosting.layoutSubtreeIfNeeded()
    flattenGlass(in: hosting)
    let points = hosting.bounds.size
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int((points.width * 2).rounded()),
        pixelsHigh: Int((points.height * 2).rounded()), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { throw ShotError(message: "couldn't make a bitmap for \(url.lastPathComponent)") }
    bitmap.size = points
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    guard let png = bitmap.retagging(with: .sRGB)?.representation(using: .png, properties: [:]) else {
        throw ShotError(message: "couldn't encode \(url.lastPathComponent)")
    }
    try png.write(to: url)
    return points
}

/// The menu bar extra's window: a rounded dark panel.
struct PopoverChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Color(red: 0.165, green: 0.165, blue: 0.175),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A desktop widget as the system draws one: its size, the content margins,
/// the container background, the rounded corners.
struct WidgetChrome<Content: View>: View {
    let family: WidgetFamily
    @ViewBuilder var content: Content

    private var size: CGSize {
        switch family {
        case .systemSmall: return WidgetSize.small
        case .systemMedium: return WidgetSize.medium
        default: return WidgetSize.large
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetSize.cornerRadius, style: .continuous)
        content
            .environment(\.widgetFamily, family)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background {
                // The widgets' `.containerBackground(.fill.tertiary, for: .widget)`
                // over the desktop widget's dark base.
                ZStack {
                    shape.fill(Color(red: 0.13, green: 0.13, blue: 0.14))
                    shape.fill(.fill.tertiary)
                }
            }
            .clipShape(shape)
    }
}


/// macOS 26 draws the window's sidebar as Liquid Glass, which a capture
/// outside the window server can't composite: it comes out as a white slab
/// over the sidebar. Paint it as the flat dark panel it reads as over the
/// window's dark page instead. Nothing to do on systems without it.
@MainActor
func flattenGlass(in view: NSView) {
    for subview in view.subviews {
        let name = String(describing: type(of: subview))
        if name.contains("GlassEffectView") {
            for child in subview.subviews where String(describing: type(of: child)).hasPrefix("_NSCoreHostingView") {
                child.isHidden = true
            }
            subview.wantsLayer = true
            subview.layer?.backgroundColor = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.16, alpha: 1).cgColor
            subview.layer?.cornerRadius = 18
            subview.layer?.cornerCurve = .continuous
            subview.layer?.borderWidth = 0.5
            subview.layer?.borderColor = NSColor(white: 1, alpha: 0.09).cgColor
        } else if name.contains("BlurryAlleyway") {
            subview.isHidden = true
        }
        flattenGlass(in: subview)
    }
}
