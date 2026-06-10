# Design handoff — Claude Usage main window (paste into Claude to redesign)

You are redesigning the **main window** of *Claude Usage*, a native macOS
SwiftUI app. The widgets, menu bar popover, and app icon already shipped from
an earlier wireframe pass — your job is to bring the new window up to that
same visual standard and **keep the whole product consistent**. Produce
hi-fi mockups (interactive HTML artifact preferred; one frame per surface,
dark mode primary + one light variant per surface) with redline specs I can
translate straight to SwiftUI.

## Established design language (consistency contract — do not reinvent)

These are already shipped across the widgets and popover. Reuse them:

- **Accent**: clay `#D97757` (dark-mode variant `#E3906F`).
- **Semantic escalation**: clay < 70 % · orange ≥ 70 % · red ≥ 90 %. Color
  never carries meaning alone — the numeral stays prominent.
- **Brand mark**: 12-ray sunburst, clay, round caps (drawn in code, scalable).
- **App icon**: sunburst inside a 270° radial progress ring on a dark
  gradient squircle (`#2D2740 → #101D28`).
- **Numerals**: SF Pro Rounded, bold, monospaced digits for percentages and
  token counts. Body text: SF Pro. Icons: SF Symbols only.
- **Components**: capsule progress bar (6 pt, quaternary track), radial gauge
  ring with centered % label, metric row (name left / colored value right /
  bar / caption), compact age badge (tiny clock + counting timer, orange when
  stale).
- **Captions**: "Resets in 4 hr 21 min" (auto-updating) within 24 h,
  "Resets Tue 6:00 PM" beyond.

## Information architecture (already implemented, plain — redesign freely
within this structure)

Window ≈ 900 × 640 pt, `NavigationSplitView`: sidebar (Dashboard, Analytics,
Settings, Account) + detail. Signed-out users see a full-window onboarding
instead of the split view. The window opens on demand from the menu bar
(⌘O); the popover stays the quick-glance surface.

## Surfaces to design

### 1. Onboarding / sign-in (full window, signed out)
Current: centered sign-in card (clay primary button "Sign in with Claude",
"or paste a code" divider + paste field + Submit, "Use Claude Code
credentials" key-icon link) and a privacy footnote. Make this feel like a
proper welcome: brand moment, 2–3 line value proposition, the three auth
paths with clear hierarchy, privacy reassurance (keychain-only token, zero
Claude-token cost). Error state for a bad pasted code.

### 2. Sidebar
Default macOS `List` today. Consider icon treatment, selected state using
clay, and whether a footer slot (version, refresh status) earns its place.

### 3. Dashboard
Current: two GroupBox cards with 110 pt rings (Session, Weekly) + a card
listing remaining metrics as bars + an "Updated n ago / refresh" line.
Goals: a confident at-a-glance hero (rings are the established gauge
vocabulary), the limit-reached and near-limit states must be unmissable,
stale state shows an amber "Couldn't refresh — showing data from n ago /
Retry" banner (same pattern as the popover).

### 4. Analytics (the centerpiece — most in need of design)
Four stacked blocks today, all default-styled:
- **Limit utilization chart**: Session + Weekly lines over time, segmented
  range picker 24 h / 7 d / 30 d, y-axis 0–100 %. Series colors today:
  Session = clay, Weekly = blue (pick a better consistent pair if you like —
  must survive grayscale). Empty state: "Collecting samples — one every
  5 minutes" (data accumulates only while the app runs).
- **Tokens by model**: stacked daily bars (one color per model), range
  7 d / 30 d. Pre-permission state: explainer + "Grant Access to ~/.claude…"
  button (sandbox requires a one-time folder grant — this state must look
  intentional, not like an error). Loading state: "Scanning transcripts…".
  Empty state: "No Claude Code activity in this range."
- **Window summary cards** (×2): "This session window" / "This week window" —
  big rounded token total + top-3 models with % share + window caption.
- **Model table**: Model / Share % / Input / Output / Cache read columns,
  monospaced numerals, cache-read de-emphasized.
- **Footer disclaimer** (must stay, design it gracefully): token counts
  cover Claude Code on this Mac only; Anthropic's percentages are the source
  of truth. Tokens charted = input + output + cache-write ("billable");
  cache reads shown only in the table.

### 5. Settings
Current: two GroupBoxes stacking the old popover-era forms. Redesign as a
proper settings page: metric visibility checklist (title + subtitle + window
badge "5-hr / 7-day / $"), notification master toggle, limit-reached toggle,
two threshold sliders (50–95 %, value label takes the escalation color),
"fires once per rolling window" hint. A "widgets show your first two enabled
metrics" hint belongs near the checklist.

### 6. Account
Current: "Signed in" status card with Sign Out, plus a "How your credentials
are handled" explainer card (OAuth via Anthropic's public Claude Code client,
keychain-only storage, zero token cost). Keep both; consider adding the
~/.claude access grant status here with a revoke affordance.

## States matrix (cover each at least once)

Signed out · normal · near limit (≥ 70) · limit reached (100 %, reset time
prominent) · stale data (amber banner + dimmed values) · analytics
pre-permission · analytics loading · analytics empty (no samples yet) ·
sign-in error.

## Technical constraints

- Native SwiftUI on macOS 15: system materials, vibrancy-friendly, honors
  dark/light. No web-style chrome, no custom fonts.
- Charts are **Swift Charts**: line marks, bar marks, segmented pickers are
  cheap; fancy custom interactions (scrubbing tooltips) are possible but
  note them as enhancements, not baseline.
- All data refreshes on a 5-minute poll; manual refresh exists. Live
  countdowns are free (auto-updating text).
- Model names arrive as short labels ("Opus 4.8", "Sonnet 4.6", "Fable 5") —
  count is dynamic (1–6 models).
- Window is resizable; design for 900 × 640 default and state how blocks
  reflow at ~760 pt min width.

## Deliverable

Per surface: the mockup frames (dark + light), a short rationale, and
redline callouts in SwiftUI vocabulary — font styles (`.headline`,
`.system(size: 26, weight: .bold, design: .rounded)`), SF Symbol names,
spacing/padding in pt, corner radii, and which established component each
element maps to. Flag anything that deviates from the design language above
and why.
