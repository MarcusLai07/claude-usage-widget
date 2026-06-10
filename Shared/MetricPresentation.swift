import SwiftUI

/// One displayable metric row, derived from the snapshot and the user's
/// enabled-metrics setting. Extra usage shows dollars instead of a percent.
struct MetricDisplay: Identifiable {
    let kind: MetricKind
    let name: String
    let percent: Double
    let valueText: String
    let resetsAt: Date?
    let caption: String?

    var id: String { kind.rawValue }
}

enum MetricPresentation {
    static func displays(for snapshot: UsageSnapshot, kinds: [MetricKind]) -> [MetricDisplay] {
        kinds.compactMap { kind in
            guard let window = snapshot.window(for: kind) else { return nil }
            let percent = window.utilization ?? 0

            if kind == .extraUsage, let extra = snapshot.extra {
                // The API reports credits in cents.
                let used = (extra.usedCredits ?? 0) / 100
                let limitText = extra.monthlyLimit.map { money($0 / 100) } ?? "—"
                return MetricDisplay(kind: kind, name: kind.title, percent: percent,
                                     valueText: "\(money(used)) / \(limitText)",
                                     resetsAt: nil, caption: "Prepaid credits")
            }
            return MetricDisplay(kind: kind, name: kind.title, percent: percent,
                                 valueText: "\(Int(percent))%",
                                 resetsAt: window.resetsAt, caption: nil)
        }
    }

    private static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

/// One labelled metric row — name, colored rounded-numeral value, capsule bar,
/// and reset/caption line. Used by the popover and both widget directions.
struct MetricBarRow: View {
    let metric: MetricDisplay
    var showCaption = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.name)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(metric.valueText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(usageColor(metric.percent))
            }
            UsageBar(percent: metric.percent)
            if showCaption {
                if let resetsAt = metric.resetsAt {
                    ResetCaption(date: resetsAt, percent: metric.percent, font: .system(size: 10.5))
                } else if let caption = metric.caption {
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// "Resets in 4 hr 21 min" (auto-updating) when the reset is within a day,
/// otherwise "Resets Tue 6:00 PM". At 100% the line is emphasized so the
/// widget stays legible in grayscale.
struct ResetCaption: View {
    let date: Date
    var percent: Double = 0
    var font: Font = .caption2

    var body: some View {
        Group {
            if date.timeIntervalSinceNow < 24 * 3600 {
                Text("Resets in ") + Text(date, style: .relative)
            } else {
                Text("Resets ") + Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
            }
        }
        .font(percent >= 100 ? font.weight(.semibold) : font)
        .foregroundStyle(percent >= 100 ? AnyShapeStyle(usageColor(percent)) : AnyShapeStyle(.secondary))
    }
}
