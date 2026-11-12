import SwiftUI

/// Usage › Sessions: one row per Claude Code session, grouped by project.
/// Clicking a session shows its requests.
struct SessionsView: View {
    @ObservedObject var analytics: AnalyticsModel
    let period: UsagePeriod
    /// Opens the Requests tab filtered to a session.
    var openSession: (String) -> Void

    var body: some View {
        TranscriptGate(analytics: analytics) {
            let projects = analytics.sessions(period)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    let count = projects.reduce(0) { $0 + $1.sessions.count }
                    Text("\(count) session\(count == 1 ? "" : "s") in \(projects.count) project\(projects.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if projects.isEmpty {
                    EmptyStateView(icon: "tray",
                                   title: "No sessions in this period",
                                   message: "Claude Code sessions on this Mac appear here.")
                        .designCard()
                }
                ForEach(projects) { project in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 7) {
                            Image(systemName: "folder")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            CardTitle(project.name)
                            if let path = project.path, path != project.name {
                                Text(path)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }
                        .padding(.bottom, 6)
                        ForEach(project.sessions) { session in
                            Divider()
                            SessionRow(session: session, colors: analytics.modelColors) {
                                openSession(session.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .designCard()
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    let colors: [String: Color]
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.title ?? "Session \(session.id.prefix(8))")
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 12)
                    Text(compactTokens(session.tokens))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    Text(costText(session.cost))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.costGreen)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(detailLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    ForEach(session.models.prefix(3), id: \.name) { model in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colors[model.name] ?? .gray)
                                .frame(width: 6, height: 6)
                            Text(model.name)
                            if session.models.count > 1 {
                                Text("\(share(model.tokens))%")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    if !session.apps.isEmpty {
                        Text(session.apps.joined(separator: " · "))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background(hovering ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show this session's requests")
    }

    /// "Nov 12, 13:05 → 15:20 · 2 h 15 min · 196 requests (12 by agents) · peak context 180K"
    private var detailLine: String {
        let start = shortDateTime(session.first)
        let sameDay = Calendar.current.isDate(session.first, inSameDayAs: session.last)
        let end = sameDay ? session.last.formatted(.dateTime.hour().minute()) : shortDateTime(session.last)
        var parts = ["\(start) → \(end)"]
        if session.duration >= 60 {
            parts.append(Duration.seconds(session.duration)
                .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
        }
        var requests = "\(session.requests.formatted()) request\(session.requests == 1 ? "" : "s")"
        if session.subagentRequests > 0 { requests += " (\(session.subagentRequests) by agents)" }
        parts.append(requests)
        parts.append("peak context \(compactTokens(session.peakContext))")
        return parts.joined(separator: " · ")
    }

    private func share(_ tokens: Int) -> Int {
        let total = max(session.models.reduce(0) { $0 + $1.tokens }, 1)
        return Int((Double(tokens) / Double(total) * 100).rounded())
    }
}
