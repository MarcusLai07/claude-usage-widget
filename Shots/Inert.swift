import SwiftUI
import WidgetKit

// What the screenshot tool swaps in so the real views can run without the
// real Mac's state behind them.

/// Stands in for Shared/TokenStore.swift, which this target leaves out: the
/// tool never opens the keychain. With no token, every request the app could
/// make stops at "not signed in" before it reaches the network.
enum TokenStore {
    static func load() -> TokenSet? { nil }
    static func save(_ tokens: TokenSet) {}
    static func clear() {}
}

/// WidgetKit's `widgetFamily` can only be read; a widget host sets it. In this
/// target this one shadows it, so the widget views (which read
/// `\.widgetFamily`) can be told which size they are drawing.
extension EnvironmentValues {
    var widgetFamily: WidgetFamily {
        get { self[ShotWidgetFamilyKey.self] }
        set { self[ShotWidgetFamilyKey.self] = newValue }
    }
}

private struct ShotWidgetFamilyKey: EnvironmentKey {
    static let defaultValue: WidgetFamily = .systemSmall
}

/// Sample data the app's own loaders hand out in this target, in place of
/// the usage history file and the transcript scan (see the `#if SHOTS`
/// lines in UsageHistory.load and AnalyticsModel.reload).
extension UsageHistory {
    nonisolated(unsafe) static var shotsHistory: [UsageSample] = []
}

extension AnalyticsModel {
    static var shotsScan = TranscriptScan()
}

extension UsageView {
    /// The tab the Usage page opens on (see its `#if SHOTS` line).
    static var shotsTab = UsageTab.overview
}
