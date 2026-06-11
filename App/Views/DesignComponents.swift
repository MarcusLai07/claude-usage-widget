import SwiftUI

// MARK: - Window design tokens (from the Claude Usage Window design handoff)

extension Color {
    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkHex : lightHex
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }

    static let windowContent = Color(lightHex: 0xF3F3F5, darkHex: 0x1D1D20)
    static let cardBackground = Color(lightHex: 0xFFFFFF, darkHex: 0x2A2A2E)
    static let cardStroke = Color.primary.opacity(0.07)
    /// Weekly chart series — distinct from clay in lightness, dashed for grayscale safety.
    static let chartIndigo = Color(lightHex: 0x5B53E0, darkHex: 0x9C8CFF)
    static let chartTeal = Color(lightHex: 0x16A89A, darkHex: 0x5FD9C8)
}

/// Stable model → color assignment for analytics charts, in share order.
let modelPalette: [Color] = [.clay, .chartIndigo, .chartTeal, .orange, .green, .purple]

func compactTokens(_ count: Int) -> String {
    count.formatted(.number.notation(.compactName))
}

// MARK: - Card

extension View {
    /// Window content card: 12 pt radius, hairline stroke, 16 pt padding.
    func designCard() -> some View {
        padding(16)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.cardStroke, lineWidth: 0.5))
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
