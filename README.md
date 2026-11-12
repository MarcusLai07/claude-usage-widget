<p align="center">
  <img src="docs/icon.png" width="128" alt="Claude Usage icon">
</p>

<h1 align="center">Claude Usage</h1>

<p align="center">
  Your Claude plan limits, on your Mac — menu bar, desktop widgets, and a full usage window.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/macOS-15%2B-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-orange">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

Claude subscriptions have rolling usage limits — a 5-hour **session** window and a 7-day **weekly** window — but checking them means opening Claude Code or claude.ai. **Claude Usage** puts them where you can see them:

- 🖥️ **Desktop widgets** (WidgetKit) in two styles — progress **bars** or radial **rings** — in small, medium, and large, with live reset countdowns. Tap to open the app.
- 📊 **Menu bar** percentages (Session over Weekly) and a popover for a quick glance: every metric with its reset and pace, manual refresh, last-updated age.
- 📈 **Usage window** — an Allowances card (each limit's figure, reset and **pace**, plan badge, Used/Left switch), a **left-over-time** chart per cycle with an even-pace line and a run-out forecast, and Claude Code's token activity from local transcripts: stat strip, activity chart, **Apps / Models / Projects** breakdowns, a **Requests** ledger with CSV export, and a **Sessions** list.
- 🔔 **Notifications** when usage crosses thresholds you set (50–95%, separately for session and weekly), when a limit is reached, before a weekly reset with much of it unused, and when the week is on pace to run out early — each at most once per window.
- 🎛️ **Configurable metrics**: Session, Weekly, Fable 7-day, Opus 7-day, Sonnet 7-day, Extra usage (prepaid credits).

> ⚠️ **Unofficial.** This app reads the same undocumented endpoint Claude Code uses internally. It may change or stop working without notice. Not affiliated with Anthropic.

## How it works

| | Limit percentages | Token analytics |
|---|---|---|
| **Source** | `api.anthropic.com/api/oauth/usage` (what Claude Code's `/usage` shows) | Local transcripts in `~/.claude/projects` |
| **Coverage** | Your whole account — every device, claude.ai, mobile | Claude Code on **this Mac only** |
| **Granularity** | Percent used + reset time per window | Exact tokens per message, per model |

The two views are complementary, not reconcilable: Anthropic weights models differently in its limit math, so token counts can't be converted to percentages. The percentages are always the source of truth.

**Reading your usage costs zero Claude tokens** — the endpoint is account metadata and never invokes a model. The app polls once per 5 minutes (fetches are coalesced across the app and all widgets).

## Install

### Build from source (recommended)

Requires macOS 15+, Xcode 16+, and a Claude Pro / Max / Team subscription.

```sh
brew install xcodegen
git clone https://github.com/MarcusLai07/claude-usage-widget.git
cd claude-usage-widget
xcodegen generate
open ClaudeUsage.xcodeproj
```

In Xcode: select your team under *Signing & Capabilities* for **both** targets (a free personal team works), then run. If Xcode complains about the App Group or keychain group, replace `com.marcuslai` with your own identifier in `project.yml` and `Shared/AppGroupStore.swift`, then re-run `xcodegen generate`.

Prefer the terminal? After the one-time team setup:

```sh
xcodebuild -scheme ClaudeUsage -configuration Debug \
  -allowProvisioningUpdates -derivedDataPath build.noindex build
ditto build.noindex/Build/Products/Debug/ClaudeUsage.app /Applications/ClaudeUsage.app
open /Applications/ClaudeUsage.app
```

### Download

Prebuilt zips are attached to [Releases](https://github.com/MarcusLai07/claude-usage-widget/releases), but **they are currently development-signed and macOS will refuse to run them on machines other than the author's** — Apple requires a paid Developer ID certificate plus notarization for distributable builds. Until that ships, build from source. (If you've dealt with this before: yes, even right-click → Open won't help here, because the provisioning profile is device-bound.)

## First run

1. The app lives in the **menu bar** (gauge icon) — no dock icon.
2. **Sign in** from the window (menu bar → Open Claude Usage): use the browser OAuth flow or one-click import of existing Claude Code credentials from your keychain.
3. Add widgets: right-click the desktop → *Edit Widgets* → search "Claude Usage". Two styles, three sizes each.
4. For token activity, open **Usage** and grant access to `~/.claude` (one-time, sandboxed; the app only reads it).

### Why does the sign-in page say "Claude Code"?

Anthropic doesn't offer OAuth registration for third-party apps, so Claude Usage authenticates through Anthropic's own public Claude Code client — the standard approach among community usage tools. The token is exchanged locally and stored only in your keychain.

## FAQ

**A metric shows "—" / "no data yet".** Anthropic isn't reporting that window for your account (e.g. `seven_day_opus` is often `null` until you've used Opus that week). It appears automatically once reported. Pro plans report fewer windows than Max plans.

**The left-over-time chart is mostly empty.** History is recorded forward-only, one sample per 5 minutes while the app runs — there's no historical API to backfill from. It fills in within a day or two; the run-out forecast needs an hour of readings this cycle.

**I use Claude on two Macs.** Percentages already include both (they're account-level). Token analytics are per-Mac — run the app on each machine to see each one's Claude Code activity.

**Widget data lags a little.** WidgetKit refresh is best-effort (~15 min worst case). The menu bar popover and window are the live views.

**Which tokens count.** Token totals are input (with cache writes) plus output. Cache *reads* are counted apart — they're ~90% of raw volume and cheap — in the stat strip and the Requests table.

## Privacy & security

- OAuth tokens live **only in the macOS keychain** (data-protection keychain, shared app group so the widget can refresh independently). They never touch files, UserDefaults, or logs.
- The app is **sandboxed**. Network access goes only to `api.anthropic.com`, `claude.ai`, and `console.anthropic.com`.
- `~/.claude` transcripts are read locally through a user-granted, revocable security-scoped bookmark; the app only reads them. Nothing is uploaded anywhere. (The sandbox's user-selected file access is read-write so Requests can be exported to a CSV file you choose.)
- Local-only telemetry (fetch duration, CPU, memory, scan times) is written to `~/Library/Group Containers/P7DV5ZUK9A.com.marcuslai.ClaudeUsage/perf-log.jsonl` so polling cost is measurable. It never leaves your machine. Inspect it:

```sh
jq -s 'group_by(.source)[] | {source: .[0].source, n: length, avgMs: (map(.durationMs) | add/length)}' \
  ~/Library/Group\ Containers/P7DV5ZUK9A.com.marcuslai.ClaudeUsage/perf-log.jsonl
```

## Architecture

```
App/                     Menu bar app + main window (SwiftUI)
  Analytics/             Usage history, transcript parsing (incremental,
                         per-file cache), ~/.claude bookmark access
  Views/                 Window (sidebar/usage — overview, requests, sessions —
                         /settings/account), popover, onboarding, components
Widget/                  WidgetKit extension — two widget kinds, three sizes
Shared/                  OAuth (PKCE), keychain token store, usage API client,
                         fetch coalescing, models, theme, app-group storage
Scripts/                 Icon generator, release packaging
project.yml              XcodeGen project definition (the .xcodeproj is generated)
```

Notes that save you a debugging session:

- Tokens must live in the **data-protection keychain** — widgets can't show the login keychain's consent prompt, so file-based keychain items are unreadable from the extension.
- **Bump `CURRENT_PROJECT_VERSION`** whenever widget configurations change; the widget gallery caches descriptors by bundle version.
- All fetches go through a coalescing actor — the usage endpoint returns **HTTP 429** under bursts (every placed widget fetching independently will trigger it).
- Build into `build.noindex/` (Spotlight skips `.noindex` folders) to avoid duplicate app entries in Launchpad from build products.

## Roadmap

- [ ] Developer ID signing + notarization (downloadable builds that just work)
- [ ] Per-widget configuration (AppIntents) instead of global metric toggles
- [ ] Launch at login toggle
- [ ] Multi-account / multi-Mac token merging

## License

MIT — see [LICENSE](LICENSE). The app icon and sunburst mark are generated by `Scripts/GenerateIcon.swift`.
