# Graph Report - .  (2026-07-05)

## Corpus Check
- Corpus is ~16,470 words - fits in a single context window. You may not need a graph.

## Summary
- 366 nodes · 688 edges · 19 communities (17 shown, 2 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 26 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_AppViews DesignComponents|App/Views: DesignComponents]]
- [[_COMMUNITY_Shared OAuthClient|Shared: OAuthClient]]
- [[_COMMUNITY_Widget ClaudeUsageWidget|Widget: ClaudeUsageWidget]]
- [[_COMMUNITY_Shared Models|Shared: Models]]
- [[_COMMUNITY_AppAnalytics AnalyticsModel|App/Analytics: AnalyticsModel]]
- [[_COMMUNITY_App UsageRefresher|App: UsageRefresher]]
- [[_COMMUNITY_AppAnalytics ClaudeFolderAccess|App/Analytics: ClaudeFolderAccess]]
- [[_COMMUNITY_Shared UsageAPI|Shared: UsageAPI]]
- [[_COMMUNITY_App NotificationManager|App: NotificationManager]]
- [[_COMMUNITY_AppAnalytics TranscriptStats|App/Analytics: TranscriptStats]]
- [[_COMMUNITY_AppViews SettingsView|App/Views: SettingsView]]
- [[_COMMUNITY_Shared MetricPresentation|Shared: MetricPresentation]]
- [[_COMMUNITY_Shared PerfLog|Shared: PerfLog]]
- [[_COMMUNITY_Shared Theme|Shared: Theme]]
- [[_COMMUNITY_personalclaude-usage-widget README|personal/claude-usage-widget: README]]
- [[_COMMUNITY_Scripts refresh-signing|Scripts: refresh-signing]]
- [[_COMMUNITY_personalclaude-usage-widget project|personal/claude-usage-widget: project]]
- [[_COMMUNITY_Scripts install-signing-refresh|Scripts: install-signing-refresh]]
- [[_COMMUNITY_Scripts release|Scripts: release]]

## God Nodes (most connected - your core abstractions)
1. `View` - 46 edges
2. `UsageRefresher` - 20 edges
3. `SwiftUI` - 14 edges
4. `UsageEntry` - 14 edges
5. `Foundation` - 13 edges
6. `AnalyticsModel` - 13 edges
7. `TokenSet` - 13 edges
8. `MainSection` - 12 edges
9. `AppGroupStore` - 11 edges
10. `MetricDisplay` - 11 edges

## Surprising Connections (you probably didn't know these)
- `SignedOutWidgetView` --references--> `View`  [EXTRACTED]
  Widget/ClaudeUsageWidget.swift → App/Views/DesignComponents.swift
- `ResetCaption` --references--> `View`  [EXTRACTED]
  Shared/MetricPresentation.swift → App/Views/DesignComponents.swift
- `AgeBadge` --references--> `View`  [EXTRACTED]
  Shared/Theme.swift → App/Views/DesignComponents.swift
- `SunburstMark` --references--> `View`  [EXTRACTED]
  Shared/Theme.swift → App/Views/DesignComponents.swift
- `UsageBar` --references--> `View`  [EXTRACTED]
  Shared/Theme.swift → App/Views/DesignComponents.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Claude Usage Consistent Design System** — personal_claude_usage_widget_design_prompt_design_prompt, personal_claude_usage_widget_design_handoff_window_design_handoff, personal_claude_usage_widget_design_handoff_window_design_language, personal_claude_usage_widget_readme_claude_usage_app [INFERRED 0.85]

## Communities (19 total, 2 thin omitted)

### Community 0 - "App/Views: DesignComponents"
Cohesion: 0.06
Nodes (44): Accessory, App, ClaudeUsageApp, MenuBarLabel, Notification.Name, WindowRouter, AccountView, String (+36 more)

### Community 1 - "Shared: OAuthClient"
Cohesion: 0.09
Nodes (22): CryptoKit, Error, Foundation, Security, Key, ClaudeCodeImport, Data, OAuthClient (+14 more)

### Community 2 - "Widget: ClaudeUsageWidget"
Cohesion: 0.09
Nodes (29): Context, Error, TimeInterval, UsageSnapshot, UsageFetcher, Task, Timeline, TimelineEntry (+21 more)

### Community 3 - "Shared: Models"
Cohesion: 0.10
Nodes (28): AnalyticsView, Color, Date, Double, TimeInterval, TimeRange, day, month (+20 more)

### Community 4 - "App/Analytics: AnalyticsModel"
Cohesion: 0.14
Nodes (16): AnalyticsModel, DayModelRow, ModelShare, Color, Date, Double, Int, String (+8 more)

### Community 5 - "App: UsageRefresher"
Cohesion: 0.13
Nodes (11): Any, Bool, String, TimeInterval, UsageSnapshot, UsageRefresher, SignInView, String (+3 more)

### Community 6 - "App/Analytics: ClaudeFolderAccess"
Cohesion: 0.12
Nodes (15): ClaudeFolderAccess, URL, AppKit, CGContext, draw(), renderPNG(), CGFloat, Int (+7 more)

### Community 7 - "Shared: UsageAPI"
Cohesion: 0.16
Nodes (16): ISO8601DateFormatter, LocalizedError, APIExtra, APIResponse, APIWindow, Bool, Date, Double (+8 more)

### Community 8 - "App: NotificationManager"
Cohesion: 0.11
Nodes (13): AppDelegate, URL, NotificationManager, Date, Double, MetricKind, String, UsageSnapshot (+5 more)

### Community 9 - "App/Analytics: TranscriptStats"
Cohesion: 0.31
Nodes (12): CachedSample, FileEntry, Line, Message, Date, Int, String, URL (+4 more)

### Community 10 - "App/Views: SettingsView"
Cohesion: 0.20
Nodes (11): AnyShapeStyle, Color, DisplaySettingsView, MetricKind, NotificationSettingsView, Bool, Color, Double (+3 more)

### Community 11 - "Shared: MetricPresentation"
Cohesion: 0.23
Nodes (10): String, Font, MetricDisplay, MetricPresentation, ResetCaption, Date, Double, MetricKind (+2 more)

### Community 12 - "Shared: PerfLog"
Cohesion: 0.31
Nodes (8): PerfEntry, PerfLog, Bool, Date, Double, Int, String, URL

### Community 13 - "Shared: Theme"
Cohesion: 0.29
Nodes (10): AgeBadge, Color, SunburstMark, Bool, CGFloat, Date, Double, UsageBar (+2 more)

### Community 14 - "personal/claude-usage-widget: README"
Cohesion: 0.36
Nodes (8): Claude Usage Main Window Design Handoff, Claude Usage Design Language (Clay Accent, Semantic Escalation), Claude Usage Widget Design Prompt, WidgetKit Constraints (Static Snapshots), Claude Usage App, Fetch Coalescing Actor, OAuth Usage Endpoint (api.anthropic.com/api/oauth/usage), Per-Model Token Analytics (Local Transcripts)

### Community 15 - "Scripts: refresh-signing"
Cohesion: 0.47
Nodes (4): log(), notify(), PATH, refresh-signing.sh script

### Community 16 - "personal/claude-usage-widget: project"
Cohesion: 1.00
Nodes (3): ClaudeUsage macOS App Target, ClaudeUsageWidget WidgetKit Extension Target, Shared App Group group.com.marcuslai.ClaudeUsage

## Knowledge Gaps
- **27 isolated node(s):** `Notification.Name`, `UserNotifications`, `Charts`, `day`, `week` (+22 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `View` connect `App/Views: DesignComponents` to `Widget: ClaudeUsageWidget`, `Shared: Models`, `App: UsageRefresher`, `App/Views: SettingsView`, `Shared: MetricPresentation`, `Shared: Theme`?**
  _High betweenness centrality (0.253) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Shared: OAuthClient` to `Shared: Models`, `App/Analytics: AnalyticsModel`, `Shared: UsageAPI`, `App: NotificationManager`, `App/Analytics: TranscriptStats`, `Shared: PerfLog`?**
  _High betweenness centrality (0.161) - this node is a cross-community bridge._
- **Why does `UsageRefresher` connect `App: UsageRefresher` to `App/Views: DesignComponents`, `Shared: OAuthClient`, `Shared: Models`?**
  _High betweenness centrality (0.133) - this node is a cross-community bridge._
- **What connects `Notification.Name`, `UserNotifications`, `Charts` to the rest of the system?**
  _27 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `App/Views: DesignComponents` be split into smaller, more focused modules?**
  _Cohesion score 0.05792349726775956 - nodes in this community are weakly interconnected._
- **Should `Shared: OAuthClient` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._
- **Should `Widget: ClaudeUsageWidget` be split into smaller, more focused modules?**
  _Cohesion score 0.0873440285204991 - nodes in this community are weakly interconnected._