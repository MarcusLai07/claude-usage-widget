# Usage redesign: what to borrow from Magpie

A review of how Claude Usage works today, how Magpie (`yetone/magpie`, v0.1.1566)
designs its Usage flow, and a phased plan for adapting the parts that fit a
native, single-provider macOS app.

Sources: every file in this repo; Magpie's source (`internal/gui/assets/app.js`,
`plugins/usage/page.js`, `internal/gui/trayusage.go`, `internal/provider/claude_limits.go`)
and its local API (`127.0.0.1:3425/v1/magpie/quotas`, `/quotas/history`, `/usage`).

---

## 1. Claude Usage today

### Data flow

```
OAuthClient / ClaudeCodeImport ──► TokenStore (data-protection keychain)
                                        │
UsageAPI.fetchUsage()  ◄── UsageFetcher (actor: freshness window + single flight)
        │                                ▲              ▲
        ▼                                │              │
UsageRefresher (5-min timer, @MainActor) │      Widget UsageProvider (15-min timeline)
  ├─ AppGroupStore.cachedSnapshot ───────┴──────────────┘
  ├─ UsageHistory.append  → usage-history.jsonl   (one sample / ≥4 min)
  ├─ NotificationManager.evaluate                  (threshold + limit alerts)
  └─ WidgetCenter.reloadAllTimelines

TranscriptStats (~/.claude/projects/**/*.jsonl, per-file mtime/size cache)
  └─ AnalyticsModel → AnalyticsView (tokens by model)
```

### Surfaces

| Surface | File | What it shows |
|---|---|---|
| Menu bar label | `ClaudeUsageApp.swift` | Sunburst template icon only |
| Popover | `MenuBarView.swift` | Visible metrics as `MetricBarRow`s, stale banner, updated line, menu rows |
| Window › Dashboard | `DashboardView.swift` | Session + Weekly rings, "More limits" bars |
| Window › Analytics | `AnalyticsView.swift` | Utilization line chart (24h/7d/30d), tokens-by-model bars, two window summaries, model table |
| Window › Settings / Account | `SettingsView.swift`, `AccountView.swift` | Metric checklist, notification thresholds; sign-out, `~/.claude` grant |
| Widgets | `ClaudeUsageWidget.swift` | Bars and Rings, small/medium/large |

### Gaps found while reading (independent of Magpie)

1. **The weekly Fable window is invisible.** The usage endpoint now also returns
   `limits[]`, rows Claude Code's `/usage` renders as sent:
   `{kind: "session" | "weekly_all" | "weekly_scoped", group, percent (0–100),
   resets_at, scope: {model | surface: {display_name}}, severity}`. Fable is a
   `weekly_scoped` row with `scope.model.display_name = "Fable"` (Magpie shows it
   as "7 days · Fable"; your account reports it today). Rate-limit headers call
   the same window `seven_day_overage_included`. `UsageAPI.APIResponse` decoded
   only `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet` and
   `extra_usage`. *(Fixed in phase 0.)*
2. **An unstarted session window disappears.** Anthropic returns `five_hour: null`
   until you've used Claude in the last 5 hours. `MetricPresentation` drops nil
   windows, so the Dashboard loses its Session hero card. Magpie shows it as
   "not started" at 0 %.
3. **History can't be split into cycles.** `UsageSample` stores percentages but
   not `resetsAt`, so a chart can't tell where one 5-hour or 7-day cycle ends and
   the next begins. History is forward-only, so every day without this field is
   lost for good.
4. **The transcript parser ignores useful fields.** Each assistant line also has
   `sessionId`, `cwd`, `gitBranch`, `entrypoint` (`claude-desktop`,
   `claude-vscode`, `sdk-cli`), `effort`, `isSidechain` and
   `usage.output_tokens_details.thinking_tokens`. The file path itself is
   `projects/<encoded-cwd>/<sessionId>.jsonl`.
5. **Limits and tokens live on different pages.** Dashboard has the limits,
   Analytics has the tokens. To answer "what burned my week?" you flip between
   them.

---

## 2. How Magpie's Usage page works

One page, **Usage**, with tabs Overview · Requests · Sessions · Context. A single
toolbar row holds the tabs, the period (Today · 7 days · 30 days · All · Custom),
the auto-refresh interval and a total cost.

### Overview, top to bottom

| Block | What it does | Why it works |
|---|---|---|
| **Allowances card** (one per account) | Logo + name, email, plan badge. Windows in a 2-column grid: name ↔ "17% used", thin bar, muted line "Resets Nov 17 17:59 · in 5d · Pace −8%", second line "Whole ≈ 4.2M tokens" or "Whole: not enough data" | Every window answers *how much*, *until when*, and *am I on track* in three short lines |
| **Used / Left toggle** | Global switch (also: click any figure). Bars fill with whichever is shown; pace sign flips to match | People think in "left" when rationing, "used" when auditing |
| **Pace** | `used% − elapsed%` of the window. Orange when positive (burning faster than an even pace) | One number replaces reading a chart |
| **Trends: Off · 2 days · Cycle** | "Left over time" curve under each card: a solid line per window, a **dashed even-pace line** from 100 % at cycle start to 0 % at reset, a "now" marker, legend with current % left. Head says "Runs out Sat 14:00 at this pace" or "Lasts past the reset at this pace". A picker reopens past cycles. Click to enlarge | The curve's only question ("will it last?") is answered in words; the even-pace line makes the shape readable at 60 px tall |
| **Hide accounts** | Masks emails | Safe screenshots |
| **Stat strip** | Joined tiles: Tokens (in · out), Cache read (hit rate), Reasoning, Calls (failed) | Totals for the picked period at a glance |
| **Activity chart** | Bars per day, stacked in/out, max label in the corner | Shape of the period |
| **Breakdown lists** | Collapsible Agents · Models · Accounts. Row: icon, name, "3 calls · 3 failed", an inline share bar, totals right-aligned, ≈ cost | Dense, scannable, comparable without a table |

### Elsewhere

- **Requests**: a ledger, one row per request, newest first, paged, CSV export.
- **Sessions**: per-session rows with a context line.
- **Menu bar**: the percentages are drawn *in* the menu bar, "42%" stacked over
  "18%" beside the logo, optionally with pace. The tray panel has its own
  Allowances tab.
- **Alerts**: threshold alerts plus a **reset reminder**, "a long window renewing
  soon with much of it left", so unused allowance isn't wasted.
- **Look**: monochrome dark UI, one accent, small muted metadata joined with
  "·", uppercase section labels, minimal chrome.

---

## 3. Proposed design for Claude Usage

Borrow Magpie's **information design and interactions**; keep our **native
SwiftUI look and brand** (clay accent, escalation colors, sunburst, SF Rounded
numerals, system materials). Magpie is a web page in a webview; copying its skin
would make a native app look like one.

### 3.1 Information architecture

```
Sidebar                         Toolbar (Usage page)
───────                         ─────────────────────────────────────────────
◉ Usage                         [Overview | Requests | Sessions]
   Overview                     [Today | 7 days | 30 days | All]   Used ⇄ Left
   Requests                     👁 Hide account    ⟳  Updated 2 min ago
   Sessions
⚙ Settings
👤 Account
```

Dashboard and Analytics merge into **Usage › Overview**. The period picker only
affects the token sections. Allowances are always "now", as in Magpie.

### 3.2 Usage › Overview

**1. Allowances card** (replaces the two ring heroes and "More limits")

- Header: sunburst · "Claude" · plan badge (`Max`, from `subscriptionType` when
  the token came from Claude Code) · account email (masked when *Hide account*
  is on).
- Grid of window meters, 2 columns (1 below ~760 pt): Session · Weekly ·
  Fable 7-day · Opus 7-day · Sonnet 7-day · Extra usage, showing only what the
  API reports, with Session always present ("Not started" at 0 %).
- Each meter, three lines:
  - `Weekly` ………………… `17% used` (tap → `83% left`, global)
  - capsule bar (existing `UsageBar`, escalation colors)
  - `Resets Tue 17:59 · in 5d · Pace −8%`, then `Runs out Sat 14:00 at this pace`
    or `Lasts past reset`, only when the forecast has enough samples
- Pace is orange when over even pace; stays secondary when under.

**2. Left over time** (inside the same card, under the meters)

- Swift Charts: one `LineMark` per window (% left), a dashed `LineMark` for even
  pace (100 → 0 across the cycle), `RuleMark` at now, x-domain = cycle start →
  reset.
- Range menu: *Cycle* (default) · *2 days* · *Off*. A cycle picker lists recorded
  past cycles ("Nov 3 – Nov 10").
- Legend: colored dot · window name · current %.
- Replaces today's utilization chart, whose fixed 24h/7d/30d ranges cut across
  cycles and put a 5-hour sawtooth on top of a weekly line.

**3. Stat strip** (period-bound, from transcripts)

| Tokens | Cache read | Thinking | Requests |
|---|---|---|---|
| 23M · 21M in · 2.2M out | 158M · hit rate 88 % | 1.4M · inside output | 705 · 12 sessions |

**4. Activity chart**: daily bars stacked by model (keep today's palette),
max label top-right, period-bound.

**5. Breakdown lists** (collapsible, Magpie row style)

- **Apps**, from `entrypoint`: Claude Desktop, VS Code, CLI / SDK. This is
  Magpie's "Agents" list, and the data already sits in your transcripts.
- **Models**: today's model table, re-cut as rows with inline share bars.
- **Projects**, from `cwd`: top projects by tokens, with session count.

Row anatomy: icon · name / caption (`41 requests · 3 sessions`) · inline share
bar · right-aligned `1.2M` / `in 0.9M · out 0.3M`.

**6. Footnote**: keep the existing disclaimer (tokens = Claude Code on this
Mac; Anthropic's percentages are the source of truth).

### 3.3 Usage › Requests

SwiftUI `Table`, newest first, sortable: Time · App · Project · Model · Effort ·
In · Out · Cache read · Cache write · Thinking. Search field, CSV export. A
"Context" column (`input + cache_read + cache_write`) stands in for Magpie's
Context tab without needing request bodies.

### 3.4 Usage › Sessions

One row per `sessionId`, grouped by project: first → last time, duration,
model mix chips, requests, tokens, peak context. Clicking a row filters
Requests to that session.

### 3.5 Menu bar, popover, widgets

- **Menu bar label**: Settings option *Icon* / *Icon + percentages*. The latter
  draws a small template image with Session over Weekly ("5%" / "17%") beside
  the sunburst, as Magpie does. Respects Used/Left.
- **Popover**: each `MetricBarRow` caption gains `· Pace −8%`. Used/Left applies.
- **Widgets**: medium/large reset captions gain pace. Used/Left is read from
  `AppGroupStore`. Bump `CURRENT_PROJECT_VERSION`.

### 3.6 Notifications

Keep the threshold and limit alerts and add two, each once per cycle:

- **Reset reminder**: "Your weekly limit resets tonight with 60 % unused."
  (weekly window, reset < 12 h away, ≥ 40 % left; both configurable)
- **Pace alert**: "At this pace your weekly limit runs out Sat 14:00, a day
  before it resets." (forecast run-out more than 6 h before reset)

---

## 4. Formulas

```swift
// Window spans: five_hour = 5 h; every seven_day* = 7 d.
start    = resetsAt - span
elapsed% = clamp((now - start) / span) * 100
pace     = used% - elapsed%          // + = burning faster than even
// In "Left" mode show -pace, so the sign is relative to the figure shown.

// Run-out forecast (Magpie's quotaEta): least-squares slope of %left over the
// current cycle's latest falling run of samples (≥ 3 samples spanning ≥ 1 h).
// slope ≥ 0                → "Lasts past reset"
// zero-crossing ≥ resetsAt → "Lasts past reset"
// else                     → "Runs out <time> at this pace"
```

**Cycle detection needs slack.** The same window's `resets_at` moves by a
minute between reads (seen live: weekly 17:59 one fetch, 18:00 the next), so
treat a new cycle as a reset that moves by more than ~5 minutes, or used %
dropping sharply, as Magpie's `quotaCycleBreak` does.

**Leave out:** Magpie's "Whole ≈ N tokens" (tokens seen ÷ used %). It
contradicts this app's stated stance (README: token counts can't be converted
to percentages, because Anthropic weights models differently and other
devices count too). Cost at API list prices is possible but needs a price
table to maintain. Keep it as a later, optional extra.

---

## 5. Changes by file

| File | Change |
|---|---|
| `Shared/UsageAPI.swift` | Decode `limits[]` (Fable from its `weekly_scoped` row); keep a nil `five_hour` as "not started". Phase 1 can render every `limits[]` row as sent, so new meters need no release |
| `Shared/Models.swift` | `MetricKind.weeklyFable`; `span` per kind; `UsageWindow.startsAt` (derived) |
| `Shared/MetricPresentation.swift` | Pace, used/left text, forecast line in `MetricBarRow` / `ResetCaption` |
| `Shared/AppGroupStore.swift` | `showLeft`, `menuBarStyle`, `hideAccount`, reminder settings |
| `App/Analytics/UsageHistory.swift` | Add optional `sessionReset`, `weeklyReset`, `fableReset`, `fable` to `UsageSample` (old lines still decode) |
| `App/Analytics/TranscriptStats.swift` | Parse `sessionId`, `cwd`, `entrypoint`, `effort`, `thinking_tokens`; bump the cache format |
| `App/Analytics/AnalyticsModel.swift` | Period filter, stat totals, breakdowns by app, model and project, sessions, cycles, forecast |
| `App/Views/*` | New `UsageView` (tabs), `AllowancesCard`, `CycleTrendChart`, `StatStrip`, `BreakdownList`, `RequestsTable`, `SessionsList`; retire `DashboardView` and `AnalyticsView` |
| `App/ClaudeUsageApp.swift` | Menu bar label with percentages |
| `App/NotificationManager.swift` | Reset reminder and pace alert |
| `Widget/ClaudeUsageWidget.swift` | Pace in captions; Used/Left |

---

## 6. Phases

| Phase | Scope | Size |
|---|---|---|
| **0, done** | Fable window, unstarted session, `resetsAt` in history samples | Small; starts the history clock |
| **1, done** | Allowances card: pace, Used/Left, plan badge, hide account; pace in popover and widgets | Medium |
| **2, done** | Left over time: cycle chart, even-pace line, forecast, past-cycle picker | Medium |
| **3, done** | Usage › Overview: period picker, stat strip, activity chart, Apps/Models/Projects lists; merges Dashboard and Analytics | Large |
| **4, done** | Requests table and Sessions list | Medium |
| **5, done** | Menu bar percentages, reset reminder, pace alert | Small–medium |

### Phase 1 notes (as built)

- **Plan and email** come from `GET /api/oauth/profile` (Bearer token, no beta
  header), the endpoint Claude Code reads for its plan name. Plan =
  `organization.plan_display_name` when sent, else `organization_type`
  (`claude_max` → Max) plus the multiplier from `rate_limit_tier`
  (`default_claude_max_5x` → "Max 5x"). Cached in the App Group, re-read every
  12 h, cleared on sign-in and sign-out.
- **Used/Left**: the bar or ring fills with the figure shown; the color still
  follows what's used. Left = 100 − whole % used, so the two always add up.
- **Pace** shows as "On pace" within ±1 point, and is hidden for a window that
  hasn't started, is used up, or whose reset has passed. Small widgets leave
  it out (no room); widget timelines carry an entry every 5 minutes so pace
  keeps moving between fetches.
- **Reset times are rounded to the minute** when shown, so the same reset no
  longer reads 17:59 on one row and 18:00 on the next.

### Phase 2 notes (as built)

- **Cycles** split where Magpie's `quotaCycleBreak` says (reset passed, or
  moved by more than 5 minutes). Lines older than phase 0 have no reset times,
  so between those a refill of more than 5 points marks the break. Past cycles
  without recorded resets snap to the weekly deadline grid when a grid point
  falls in the gap between two cycles, so they read "Oct 27 – Nov 3" rather
  than from the first reading after the reset; mid-week resets keep their
  real times.
- **Chart** (`LeftOverTimeView`): range Cycle · 2 days · Off plus up to 26
  past cycles, one menu. A window under 1/12 of the span (the session in a
  week) shows only its current cycle and no even pace; past cycles leave it
  out. Windows that share a cycle share one even-pace line. Click to enlarge.
- **Forecast**: the chart's head carries the furthest-resetting window's
  forecast ("Lasts past the reset at this pace" or "Runs out …"); a meter
  only adds a line, in orange, when its window runs out before it resets.

### Phase 3 notes (as built)

- **One page.** The sidebar is Usage · Settings · Account. Usage holds the
  Allowances card, then "Claude Code on this Mac" with its own period picker
  (Today · 7 days · 30 days · All), since the period only applies there.
- **Transcripts** are now parsed in full (not 30 days) with session, `cwd`,
  `entrypoint`, `effort`, sidechain and thinking tokens, into
  `transcript-cache-v2.json` (short keys; about 16 MB for 21k requests). The
  first scan after updating reads everything once (about 36 s for 1 GB of
  transcripts); later ones only read changed files and skip rewriting the
  cache when nothing changed.
- **Stat strip**: Tokens (input incl. cache writes, plus output) · Cache read
  (hit rate = cache read ÷ all prompt tokens) · Thinking · Requests (sessions).
- **Activity**: bars per hour (Today), day (up to two months) or week,
  stacked by model, peak in the corner.
- **Lists**: Apps from `entrypoint` (Claude Desktop, VS Code, Terminal,
  Agent SDK), Models, Projects from `cwd` (worktrees count toward their
  repository). Collapsible, remembered per list.

### Phase 4 notes (as built)

- **Tabs** Overview · Requests · Sessions sit in the Usage page header; the
  session warning pill shrinks to its icon when the header runs out of room.
- **Requests**: a sortable `Table`, newest first: Time · App (icon; ↳ for a
  subagent) · Project · Model with effort · In (incl. cache writes) · Out ·
  Cached · Thinking · Context. Fixed column widths so it fits the default
  900 pt window. Search covers app, project, model, effort, session id and
  title. CSV export writes every field, cache writes and effort included
  (the app's file entitlement is now `user-selected.read-write`).
- **Sessions**: whole sessions active in the period, grouped by project,
  titled from the transcripts' `custom-title` / `ai-title` lines (cache v3).
  Each row: first → last, duration, requests (with subagent share), peak
  context, model chips with shares, apps. A click opens Requests filtered
  to that session.

### Phase 5 notes (as built)

- **Menu bar** (Settings › Display › Menu bar): *Icon + percentages* is the
  default — Session over Weekly beside the sunburst in one template image,
  as used or left. *Icon* brings back the plain mark.
- **Reset reminder** (on by default): once per weekly cycle, up to 12 hours
  before the reset (3/6/12/24) with at least 40% left (20–60%): "Weekly
  limit resets in 5 hours — 60% of it is still unused, and it doesn't carry
  over."
- **Pace alert** (on by default): once per weekly cycle, when the forecast
  says the week runs out more than 6 hours before it resets. It reads only
  this week's history, off the main thread; `UsageHistory.load(since:)`
  now reads back from the newest line and stops at the start date.
- Both go through the same once-per-window record as the threshold alerts
  (5-minute slack on the reset time).

---

## 7. Round 2: data parity with Magpie and a fresh look

### 7.1 Why "All" differs from Magpie (measured on this Mac, Nov 12)

| | Ours (0.6.0) | Last line per message | + Desktop local-agent sessions | = | Magpie |
|---|---|---|---|---|---|
| Fresh input | 0.11M | 0.11M | +0.16M | 0.27M | 267K |
| Output | 21.25M | **22.59M** | +0.17M | 22.76M | 23M |
| Cache read | 6.96B | 6.96B | +0.02B | 6.98B | 6.98B |
| Cache write | 158M | 158M | +3M | 161M | 161M |
| Requests | 21,303 | 21,303 | +335, +20 API errors | 21,658 | 21,656 |

Four causes:

1. **We keep a message's first line; Magpie its last.** Claude Code writes one
   line per content block and repeats `usage` on each; the last has the final
   count. 955 messages grew after their first line, so our output is 1.34M
   (6%) short. A bug: fix it.
2. **Claude Desktop's local-agent sessions.** Desktop keeps a Claude Code
   folder per local-agent session under `~/Library/Application Support/
   Claude/local-agent-mode-sessions/*/*/local_*/.claude/projects` (47 files,
   335 requests, 26M tokens here). We read only `~/.claude`; reading these
   needs one more folder grant in the sandbox.
3. **Failed calls.** Magpie counts API-error replies (`<synthetic>` with
   `isApiErrorMessage`) as failed requests; we drop them (20 here).
4. **The headline differs by definition, not data.** Magpie's *Tokens* is
   everything — in + out + cache read + cache write (7.16B). Ours is in +
   cache write + out (179M), with cache reads shown apart (7B).

### 7.2 What Magpie's data pages do (from its 0.1.1566 screens)

- **One toolbar** for the page: tabs Overview · Requests · Sessions · Context,
  then the period (Today · 7 · 30 · 90 days · All · Custom), refresh, and a
  running cost "≈$4106 effective prices" (models.dev prices).
- **Requests**: filters (agent, provider, All/Failed/Retried), search, CSV;
  stat strip Tokens (in · out · cache) · Requests (failed, % succeeded) ·
  Cost · Cache hit rate (with a bar) · Output speed; a chart with metric tabs
  (Tokens/Cost/Requests/Speed), bar/line, *Split by* Model/Provider/Agent and
  a ranked legend list beside it; a 53-week daily heatmap (Tokens/Requests/
  Cost); the ledger with cost, TTFT, duration, speed, status.
- **Sessions**: filters (app, model, folder); stat strip Sessions (median,
  p90) · Tokens · Cost · Cache read · Active hours on N days · Projects;
  *By day* bars with metric tabs (Tokens, Output, Messages, Sessions, Cost,
  Active); Projects and Models as bar lists with cost; *By hour* weekday ×
  hour heatmap ("Busiest at Wed 16:00"); *Top sessions* (Tokens/Cost/Active).
- **Context**: "Tuned for you" — replays your own calls to find the
  auto-compact window and prompt-cache TTL that would have spent the fewest
  tokens.
- **Look**: dark, flat and dense; hairline-bordered cards; small uppercase
  section labels; light-weight large numerals with muted captions; one
  periwinkle accent for data, green for cost; controls live in section heads.

### 7.3 Proposal

**Phase 6 — data parity.** Last line per message; failed calls as requests
with a status; optional Desktop local-agent folder; Magpie's token headline
(in · out · cache) with fresh tokens kept as a caption; active time per
session and day (gaps under 10 minutes); optional ≈ cost at API list prices
from a bundled Claude-only price table (no new network calls); 90 days and a
custom range. Cache format v4.

**Phase 7 — shell and visual language.** The tabs and period move into the
window's toolbar (native, unified; no duplicated "Usage" title); section labels
in small caps; lighter numerals with monospaced digits; a periwinkle-led data
palette in both appearances (clay stays the brand and selection color);
Allowances gets Magpie's section head (Trends: Cycle/2 days/Off, Hide account,
Used/Left) and slimmer meters.

**Phase 8 — Requests.** Filters (app, model, All/Failed), stat strip with cache
hit bar, metric-tab chart with *Split by* Model/App/Project and a ranked legend,
53-week heatmap, ledger with cost and status.

**Phase 9 — Sessions.** Filters, stat strip (median/p90, active hours,
projects), By day metric chart, Projects/Models bar lists, By hour heatmap,
Top sessions, then the grouped list.

**Phase 10 (optional) — Context.** Compaction and cache-TTL "what if" from your
own calls, as Magpie's Context tab does.

### Phase 6 notes (as built)

- Parser: a message's **last** line counts; API-error replies are failed
  requests (with their error code); each reply is timed from the prompt (or
  the previous reply) to its last line; cache writes keep their 1-hour part;
  the earliest file owns a message copied into a resumed session. Cache v4.
- Claude Desktop's local-agent sessions are read when its folder is granted
  (Account page, or "Add Claude Desktop sessions…" on Usage); they show as the
  app "Desktop agent" and the project "Claude Desktop".
- `ModelPricing` holds Anthropic API list prices for every model seen here
  (cache reads per model, writes 1.25×/2×, Haiku 5.5's long-prompt tier).
- Measured against Magpie on this Mac: 21,681 requests (20 failed), 267K in,
  22.8M out, 7.16B cache, 7.18B tokens, ≈$4,114 (Magpie ≈$4,106), hit rate
  97.7% (97.7%).
- Tokens everywhere are Magpie's (in + out + cache read + write), shown with
  three significant digits. The stat strip is Tokens · Requests · Cost ·
  Cache hit rate · Output speed. Periods gain 90 days.

### Phase 7 notes (as built)

- One toolbar row on the Usage page (no page header): tab pills, period pills
  (Today · 7 · 30 · 90 days · All · Custom with a from/to popover), the age,
  refresh, and the period's ≈ cost "API prices". It wraps to two rows when
  narrow. The period now drives every tab.
- Visual language: `PillTabs`, `SectionLabel` (small caps), `StatTile` /
  `StatStripPanel` (medium-weight monospaced figures, a hit-rate bar),
  flatter 10 pt panels with hairlines, darker page in dark mode.
- Palette: periwinkle data accent, then sky, teal, amber, pink, violet, green
  (`modelPalette`); cost in green. Limits use series colors (Session
  periwinkle, Weekly sky, Fable teal) and escalate to orange/red from 70/90%.
- Allowances: the section head holds Trends (Cycle / 2 days / Off), Hide
  account and Used/Left; the card shows the account with the plan at right;
  the chart's head keeps only the past-cycle picker.
- Claude Code: stat strip, activity bars with Tokens/Cost/Requests tabs,
  Models and Apps side by side, Projects below, as one-line bar lists with
  cost (details on hover).
- Window default 1180×820, minimum 940×600.

### Phase 8 notes (as built)

- Requests scrolls as one page: filters (app, model, All/Failed, session chip,
  search, Export CSV) · the stat strip for what's filtered · a chart with
  Tokens/Cost/Requests/Speed tabs, bars or lines, *Split by* Model/App/Project
  (seven series and "Other (n)") and a ranked legend (exact value, requests,
  cost, speed, hit rate, share) · a 53-week daily heatmap (Tokens/Cost/
  Requests, same filters, any period) · a summary line · the ledger.
- The ledger is a sortable custom list (click a header), 100 rows at a time:
  Time · App · Model with effort · Project · In · Out · Cache · Cost ·
  Duration · Speed · Status. Fixed widths leave Project ~110 pt by default.
- `RequestsDerived` computes filters, totals, the split, buckets, the heatmap
  and the sorted rows off the main thread, once per change of filters.
- `Heatmaps.swift`: `DailyHeatmap` (53 weeks, Monday first, month labels) and
  `HourHeatmap` (weekday × hour), quantile-scaled in five steps.

### Phase 9 notes (as built)

- Sessions: filters (All / Claude Code / Claude Desktop, model, folder) ·
  stat strip Sessions (median, p90) · Tokens (in · out, as Magpie's Sessions
  page counts them) · Cost · Cache read (hit rate) · Active (gaps under 10
  minutes, and on how many days) · Projects (top share) · By day with
  Tokens/Output/Messages/Sessions/Cost/Active tabs · Projects and Models bar
  lists · By hour (weekday × hour, time zone, busiest hour) · Top sessions
  (Tokens/Cost/Active; a click opens their requests) · every session by
  project.
- Every call of a session is filed under the folder the session started in,
  as Magpie does, so changing into a subfolder no longer splits a project
  (96 "projects" → 11 over 30 days; Magpie shows 10, top SCM-Portal at
  28% vs 29%). Top sessions match Magpie's (1.3M, 1.29M, 1.18M) and so does
  the busiest hour (Wed 16:00).
- `SessionsDerived` computes it all off the main thread per filter change.

### Phase 10 notes (as built)

- Usage › Context ("Tuned for you"): `ContextTuning` ports Magpie's
  `internal/tune` — conversations (a subagent's transcript is its own),
  compactions (a prompt dropping below 60% of one ≥ 20K), growth, the summary
  a compaction leaves, the rework after it; every auto-compact window from a
  floor to the model's window replayed on the period's calls; of windows
  within 1% of the cheapest the largest; advice only for 3%+ savings. Cache
  lifetime: 5 minutes against an hour on the real gaps between calls, for the
  main conversation and for subagents.
- Tokens are weighed by each model's own prices (Opus 5.5 reads at 0.05×
  input), so savings also show as ≈$.
- The current window is Claude Code's `autoCompactWindow` (settings.json) or
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, else the model's whole window — as
  Claude Code runs Claude models. "Copy setting" puts
  `"autoCompactWindow": N` on the clipboard; the app never edits Claude
  Code's configuration.
- On this Mac, 7 days: Opus 5.5 now 1M → 410K, 18% fewer weighted tokens
  (≈$78); main-conversation cache already leanest at 1 hour (5 min +21%);
  subagents leanest at 5 min (1 hour +18%). Transcript cache v5.

### App group fix (0.6.1)

- The development provisioning profile authorizes no app group, and on
  recent macOS a `group.`-style group the profile doesn't cover makes every
  access ask "would like to access data from other apps" — and blocks the
  thread that asked (the earlier "not responding"). The app and widget now
  use the team-prefixed group `P7DV5ZUK9A.com.marcuslai.ClaudeUsage`, which
  needs no profile entry. On first launch, 0.6.1 copies the old group's
  settings, folder grants, history and logs over once (the app keeps the old
  group in its entitlements only for that); the transcript cache is rebuilt.
