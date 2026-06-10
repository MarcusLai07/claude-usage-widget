# Design prompt (paste into Claude to generate wireframes)

You are designing the UI for **Claude Usage**, a native macOS app I'm building
in SwiftUI. It shows Claude AI plan usage limits. Produce high-fidelity
**wireframes/mockups** (interactive HTML artifact preferred, one screen per
frame, dark mode primary + a light mode variant) for the surfaces below.

## Product context

- Claude subscriptions have rolling usage limits: a **Session** limit (5-hour
  window) and a **Weekly** limit (7-day window), each reported as a percentage
  used plus a reset timestamp. Optional extras: **Opus 7-day**, **Sonnet
  7-day**, and **Extra usage** (prepaid credits: $used of $limit).
- The app is a macOS **menu bar app** + a **WidgetKit desktop widget** (like
  the built-in Battery widget). Data refreshes every 5–15 minutes.

## Surfaces to design

1. **Desktop widget — small** (square, ~170×170 pt): must show 2 metrics max.
   Percentage is the hero; reset countdown secondary.
2. **Desktop widget — medium** (~364×170 pt): 2–3 metrics with room for
   labels, progress visualization, and "Resets in 4 hr 21 min" countdowns.
3. **Desktop widget — large** (~364×382 pt): all 5 metrics, plus "last
   updated" footer.
4. **Menu bar popover** (320 pt wide): metric list, manual refresh button,
   last-updated line, links to Settings, Sign Out, Quit.
5. **Settings window — Display tab**: checkboxes choosing which metrics are
   visible.
6. **Settings window — Notifications tab**: master toggle, "notify when limit
   reached" toggle, and two threshold sliders (Session / Weekly, 50–95%).
7. **Sign-in state** (popover + widget variants): "Sign in with Claude"
   button, paste-code field, and an "Use Claude Code credentials" secondary
   option; widget shows "Open Claude Usage to sign in".

## Constraints (WidgetKit reality — don't design around these)

- Widgets are **static snapshots**: no scrolling, no hover, no text input.
  The whole widget is one tap target (opens the app).
- Countdown text auto-updates, but data can be up to ~15 min stale.
- Must look native on macOS: SF Pro, SF Symbols, vibrancy-friendly
  backgrounds, respects dark/light mode and accent color.
- Color semantics: normal usage = neutral/green, ≥70% = orange, ≥90% = red.
  Don't rely on color alone — keep the percentage text prominent.

## States to cover per widget size

- Normal (e.g. Session 11% resets in 4 h 21 m, Weekly 2% resets Tue 6 PM)
- Near limit (Session 87%) and limit reached (100%, show reset time clearly)
- Signed out
- Stale data (last fetch failed; show last-known values + subtle staleness cue)

## Deliverable

Wireframes for every surface and state above, with a short rationale per
screen and exact spacing/typography callouts I can translate to SwiftUI
(font styles like .headline/.caption, SF Symbol names, layout in pt). Keep
the visual language consistent across widget, popover, and settings.
