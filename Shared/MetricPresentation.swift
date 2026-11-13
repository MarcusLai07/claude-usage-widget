import SwiftUI

/// One displayable metric row, derived from the snapshot and the user's
/// enabled-metrics setting. Extra usage shows dollars instead of a percent.
struct MetricDisplay: Identifiable {
    let kind: MetricKind
    let name: String
    /// Percent used. Drives the escalation color in both Used and Left mode,
    /// so a nearly empty window stays red whichever figure is shown.
    let percent: Double
    /// Showing what's left instead of what's used.
    let showLeft: Bool
    /// The figure in the current mode: "17%" / "83%", or dollars.
    let valueText: String
    /// "used" / "left" after the figure; nil when it speaks for itself.
    let unitText: String?
    let resetsAt: Date?
    let caption: String?
    /// used% − elapsed% of the window: positive when burning faster than an
    /// even pace. Nil when the window hasn't started, has no fixed length,
    /// or is already used up.
    let pace: Double?

    var id: String { kind.rawValue }

    /// What the bar or ring fills with. Left is 100 minus the whole percent
    /// used, so it matches `valueText` (16.6% used shows 84% left).
    var shownPercent: Double { showLeft ? max(0, 100 - percent.rounded(.down)) : percent }

    var color: Color { usageColor(percent) }

    /// "83% left", for one-line spots that can't style the parts apart.
    var valueWithUnit: String {
        unitText.map { "\(valueText) \($0)" } ?? valueText
    }

    private var roundedPace: Int? {
        pace.map { Int(($0).rounded()) }
    }

    /// Burning faster than an even pace (by at least a point).
    var isOverPace: Bool { (roundedPace ?? 0) >= 1 }

    /// "Pace +8%", signed relative to the figure shown (Magpie's rule): in
    /// Left mode being 8 points ahead of pace reads "Pace −8%".
    var paceText: String? {
        guard let roundedPace else { return nil }
        let shown = showLeft ? -roundedPace : roundedPace
        if shown == 0 { return "On pace" }
        return "Pace \(shown > 0 ? "+" : "−")\(abs(shown))%"
    }
}

enum MetricPresentation {
    static func displays(for snapshot: UsageSnapshot, kinds: [MetricKind],
                         showLeft: Bool = AppGroupStore.showLeft,
                         now: Date = Date()) -> [MetricDisplay] {
        kinds.compactMap { kind in
            guard let window = snapshot.window(for: kind) else { return nil }
            let percent = window.utilization ?? 0

            if kind == .extraUsage, let extra = snapshot.extra {
                // The API reports credits in cents.
                let used = (extra.usedCredits ?? 0) / 100
                let limit = extra.monthlyLimit.map { $0 / 100 }
                let value: String
                let unit: String
                if let limit {
                    let figure = showLeft ? max(0, limit - used) : used
                    value = "\(money(figure)) of \(money(limit))"
                    unit = showLeft ? "left" : "used"
                } else {
                    value = money(used)
                    unit = "used"
                }
                return MetricDisplay(kind: kind, name: kind.title, percent: percent,
                                     showLeft: showLeft, valueText: value, unitText: unit,
                                     resetsAt: nil, caption: "Prepaid credits", pace: nil)
            }
            // Nothing used and no reset yet: the window starts with your next
            // message (Anthropic reports the 5-hour window this way).
            let notStarted = window.resetsAt == nil && percent == 0
            let used = Int(percent)
            return MetricDisplay(kind: kind, name: kind.title, percent: percent,
                                 showLeft: showLeft,
                                 valueText: "\(showLeft ? max(0, 100 - used) : used)%",
                                 unitText: showLeft ? "left" : "used",
                                 resetsAt: window.resetsAt,
                                 caption: notStarted ? "Not started" : nil,
                                 pace: pace(used: percent, resetsAt: window.resetsAt,
                                            span: kind.span, now: now))
        }
    }

    /// used% − elapsed%, where elapsed is how far `now` is into the cycle
    /// that ends at `resetsAt`.
    static func pace(used: Double, resetsAt: Date?, span: TimeInterval?, now: Date) -> Double? {
        guard let resetsAt, let span, used < 100, resetsAt > now else { return nil }
        let start = resetsAt.addingTimeInterval(-span)
        let elapsed = min(max(now.timeIntervalSince(start) / span, 0), 1) * 100
        return used - elapsed
    }

    private static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

/// One labelled metric row, as the app's Allowances card draws a limit: the
/// name, "17% used", a thin bar in the window's series color (orange, then
/// red, near the limit), and the reset/pace line. Used by the popover and
/// both widget directions.
struct MetricBarRow: View {
    let metric: MetricDisplay
    var showCaption = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                MetricValue(metric: metric)
            }
            UsageBar(percent: metric.shownPercent, height: 5,
                     tint: metric.kind.meterColor(percentUsed: metric.percent))
            if showCaption {
                MetricCaption(metric: metric, font: .system(size: 10.5))
            }
        }
    }
}

/// "17% used" / "83% left": the figure in medium-weight digits — orange or
/// red only near the limit — the unit after it.
struct MetricValue: View {
    let metric: MetricDisplay
    var size: CGFloat = 12.5

    var body: some View {
        let figure = Text(metric.valueText)
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .foregroundStyle(metric.percent >= 70 ? metric.color : Color.primary)
        if let unit = metric.unitText {
            figure + Text(" \(unit)")
                .font(.system(size: size * 0.92, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            figure
        }
    }
}

/// Where a caption puts the pace: after the reset time, on its own line
/// (narrow widgets), or not at all.
enum PacePlacement {
    case inline, below, hidden
}

/// A metric's reset line, or its caption ("Not started", "Prepaid credits")
/// when it has no reset. Draws nothing when it has neither.
struct MetricCaption: View {
    let metric: MetricDisplay
    var font: Font = .caption2
    var pace: PacePlacement = .inline
    /// Adds "· in 5d" after a reset more than a day away.
    var countdown = false
    var alignment: HorizontalAlignment = .leading

    var hasContent: Bool { metric.resetsAt != nil || metric.caption != nil }

    var body: some View {
        if let resetsAt = metric.resetsAt {
            switch pace {
            case .inline:
                ResetCaption(date: resetsAt, percent: metric.percent, font: font,
                             countdown: countdown, paceText: metric.paceText,
                             overPace: metric.isOverPace)
            case .below:
                // One line for the reset, so the pace line doesn't make
                // a narrow column taller than it was without it.
                VStack(alignment: alignment, spacing: 1) {
                    ResetCaption(date: resetsAt, percent: metric.percent, font: font,
                                 countdown: countdown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let paceText = metric.paceText {
                        Text(paceText)
                            .font(font)
                            .foregroundStyle(metric.isOverPace ? AnyShapeStyle(Color.orange)
                                                               : AnyShapeStyle(.secondary))
                    }
                }
            case .hidden:
                ResetCaption(date: resetsAt, percent: metric.percent, font: font,
                             countdown: countdown)
            }
        } else if let caption = metric.caption {
            Text(caption)
                .font(font)
                .foregroundStyle(.tertiary)
        }
    }
}

/// "Resets in 4 hr 21 min" (auto-updating) when the reset is within a day,
/// otherwise "Resets Tue 6:00 PM", optionally "· in 5d". A pace, when
/// given, follows as "· Pace +8%", orange when over pace. At 100% the line
/// is emphasized so the widget stays legible in grayscale.
struct ResetCaption: View {
    let date: Date
    var percent: Double = 0
    var font: Font = .caption2
    var countdown = false
    var paceText: String? = nil
    var overPace = false

    var body: some View {
        resetText
            .font(percent >= 100 ? font.weight(.semibold) : font)
            .foregroundStyle(percent >= 100 ? AnyShapeStyle(usageColor(percent)) : AnyShapeStyle(.secondary))
    }

    private var resetText: Text {
        let interval = date.timeIntervalSinceNow
        var text: Text
        if interval < 24 * 3600 {
            text = Text("Resets in ") + Text(date, style: .relative)
        } else {
            // Rounded to the minute: Anthropic sends the same reset as
            // 09:59:59.6 one read and 10:00:00 the next, which would show
            // as 17:59 next to 18:00.
            let minute = (date.timeIntervalSinceReferenceDate / 60).rounded() * 60
            let shown = Date(timeIntervalSinceReferenceDate: minute)
            text = Text("Resets ") + Text(shown, format: .dateTime.weekday(.abbreviated).hour().minute())
            if countdown {
                text = text + Text(" · in \(Int((interval / 86400).rounded()))d")
            }
        }
        if let paceText {
            let pace = Text(paceText)
            text = text + Text(" · ") + (overPace ? pace.foregroundStyle(Color.orange) : pace)
        }
        return text
    }
}
