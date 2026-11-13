import SwiftUI

// MARK: - Window design tokens (from the Claude Usage Window design handoff)

// The data palette (dataAccent, chartSky…, costGreen, track) and
// `Color(lightHex:darkHex:)` live in Shared/Theme.swift, for the widget too.
extension Color {
    // Flat and dense, as Magpie's data pages: a dark page, panels a step
    // lighter with a hairline edge.
    static let windowContent = Color(lightHex: 0xF4F4F6, darkHex: 0x18181A)
    static let cardBackground = Color(lightHex: 0xFFFFFF, darkHex: 0x212124)
    static let cardStroke = Color.primary.opacity(0.08)
}

/// Stable model → color assignment for charts, in share order: the data
/// accent first, then hues far enough apart to tell stacked bars apart.
let modelPalette: [Color] = [.dataAccent, .chartSky, .chartTeal, .chartAmber, .chartPink,
                             .chartViolet, .chartGreen, .gray]

/// "7.16B", "22.8M", "267K": three significant digits, as Magpie shows them.
func compactTokens(_ count: Int) -> String {
    count.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
}

/// "≈$4,112", "≈$0.128": dollars at API list prices, more precision when small.
func costText(_ usd: Double, approximate: Bool = true) -> String {
    let prefix = approximate ? "≈$" : "$"
    if usd >= 100 { return prefix + Int(usd.rounded()).formatted() }
    if usd >= 1 { return prefix + String(format: "%.2f", usd) }
    return prefix + String(format: "%.3f", usd)
}

/// "Nov 12 15:20" (the system's month-day-hour format adds "at").
func shortDateTime(_ date: Date) -> String {
    "\(date.formatted(.dateTime.month(.abbreviated).day())) \(date.formatted(.dateTime.hour().minute()))"
}

// MARK: - Card

extension View {
    /// Window content card: 10 pt radius, hairline stroke, 16 pt padding.
    func designCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cardStroke, lineWidth: 0.5))
    }
}

/// A section's small-caps label ("ALLOWANCES"), as Magpie heads its blocks.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.7)
            .foregroundStyle(.secondary)
    }
}

/// A group of pill buttons, one selected (Magpie's segmented groups).
struct PillTabs<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var size: CGFloat = 12.5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: size, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selected ? Color.primary.opacity(0.11) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.track, in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }
}

/// A stat tile's parts: small label, figure, muted caption (Magpie's strip).
struct StatTile: View {
    let label: String
    let value: String
    var caption: String? = nil
    var valueColor: Color? = nil
    /// 0–100: a thin bar under the figure (Magpie's cache hit rate).
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .medium).monospacedDigit())
                .foregroundStyle(valueColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let progress {
                UsageBarTinted(percent: progress, color: .costGreen)
                    .padding(.vertical, 2)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Tiles joined in one panel with hairline dividers.
struct StatStripPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            content()
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cardStroke, lineWidth: 0.5))
    }
}

/// A thin vertical hairline between joined tiles.
struct TileDivider: View {
    var body: some View {
        Rectangle().fill(Color.cardStroke).frame(width: 0.5)
    }
}

struct CardTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Page header

struct PageHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            accessory()
        }
        .padding(.init(top: 14, leading: 22, bottom: 12, trailing: 22))
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

struct AgeIndicator: View {
    let since: Date
    var stale = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: stale ? "clock.badge.exclamationmark" : "clock")
                .font(.system(size: 11))
            Text(since, style: .relative) + Text(" ago")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
    }
}

struct RefreshButton: View {
    @EnvironmentObject private var refresher: UsageRefresher

    var body: some View {
        Group {
            if refresher.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await refresher.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Refresh now")
            }
        }
    }
}

// MARK: - Stale banner (shared pattern with the popover)

struct StaleBanner: View {
    @EnvironmentObject private var refresher: UsageRefresher

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
            if let fetchedAt = refresher.snapshot?.fetchedAt {
                (Text("Couldn't refresh — showing data from ")
                 + Text(fetchedAt, style: .relative) + Text(" ago."))
                    .font(.system(size: 12))
            } else {
                Text("Couldn't refresh.").font(.system(size: 12))
            }
            Spacer()
            Button("Retry") { Task { await refresher.refresh(force: true) } }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.clay)
        }
        .padding(.init(top: 10, leading: 13, bottom: 10, trailing: 13))
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Empty states (analytics token block)

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let actionLabel, let action {
                Button(action: action) {
                    Label(actionLabel, systemImage: "folder")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.clay)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(.vertical, 20)
    }
}

// MARK: - Hint footnote (settings/account cards)

struct HintRow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 13)
    }
}

// MARK: - Chart legend swatch

struct LegendSwatch: View {
    let color: Color
    var dashed = false
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 1.25))
                p.addLine(to: CGPoint(x: 16, y: 1.25))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: dashed ? [4, 3] : []))
            .frame(width: 16, height: 2.5)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
