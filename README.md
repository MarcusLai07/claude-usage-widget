# Claude Usage Widget

A native macOS desktop widget (plus menu bar companion app) that shows your
Claude plan usage at a glance — session (5-hour) and weekly utilization with
reset countdowns, just like the `/usage` screen in Claude Code, but on your
desktop or in Notification Center.

> ⚠️ **Unofficial.** This app uses the same undocumented endpoint Claude Code
> uses internally (`api.anthropic.com/api/oauth/usage`). It may change or stop
> working without notice. Not affiliated with Anthropic.

## Features

- **Desktop / Notification Center widget** in small, medium, and large sizes
- **Menu bar app** with live usage, manual refresh, and reset countdowns
- **Sign in with Claude** — OAuth 2.0 + PKCE in your browser, or one-click
  import of existing Claude Code credentials from the keychain
- **Choose what to show** — session, weekly, Opus 7-day, Sonnet 7-day, extra usage
- **Notifications** — get warned when session or weekly usage crosses a
  threshold you set (50–95%), and when a limit is reached
- **Zero token consumption** — only reads usage metadata, never calls model APIs

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+ to build
- A Claude Pro / Max / Team subscription

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open ClaudeUsage.xcodeproj
```

Then in Xcode:

1. Select the **ClaudeUsage** target → *Signing & Capabilities* → pick your
   team (a free personal team works). Repeat for **ClaudeUsageWidget**.
2. If Xcode complains about the App Group or keychain group, change
   `com.marcuslai` / `group.com.marcuslai.ClaudeUsage` in `project.yml` to your
   own identifiers and re-run `xcodegen generate`. The same group string also
   lives in `Shared/AppGroupStore.swift`.
3. Run the **ClaudeUsage** scheme. The app lives in the menu bar (gauge icon).
4. Sign in (browser OAuth, or import Claude Code credentials).
5. Add the widget: right-click the desktop → *Edit Widgets* → search "Claude Usage".

## Security notes

- OAuth tokens are stored only in the **macOS keychain** (a shared keychain
  access group so the widget can refresh on its own). They never touch
  UserDefaults, files, or logs.
- The app is sandboxed; the only network access is to `api.anthropic.com`,
  `claude.ai`, and `console.anthropic.com`.
- Treat your access/refresh tokens as account credentials. Don't paste them
  anywhere.

## How it works

- The menu bar app polls the usage endpoint every 5 minutes, caches the result
  in an App Group container, evaluates your notification thresholds, and asks
  WidgetKit to reload.
- The widget's `TimelineProvider` also fetches directly (reading the token
  from the shared keychain group), so it stays current even if the menu bar
  app isn't running. WidgetKit refresh is best-effort — expect up to ~15
  minutes of lag on the desktop widget.

## Roadmap

- [ ] Per-widget configuration (AppIntents) instead of global metric toggles
- [ ] Launch-at-login toggle
- [ ] Multiple accounts

## License

MIT — see [LICENSE](LICENSE).
