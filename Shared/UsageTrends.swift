import Foundation
import Combine

/// One reading of a window: what was left, and its reset as read then.
struct TrendPoint: Equatable {
    let at: Date
    let left: Double
    let reset: Date?
}

/// A stretch of one window's readings with no cycle restart inside it.
struct TrendSegment: Identifiable {
    let kind: MetricKind
    let index: Int
    let points: [TrendPoint]
    var id: String { "\(kind.rawValue)#\(index)" }
}

/// Everything recorded for one window, split at each restart.
struct TrendLine: Identifiable {
    let kind: MetricKind
    let segments: [TrendSegment]
    var id: MetricKind { kind }

    var points: [TrendPoint] { segments.flatMap(\.points) }
}

/// A cycle of a window: from its start to its reset.
struct TrendCycle: Identifiable, Hashable {
    let start: Date
    let end: Date
    var id: Date { start }
}

/// The current cycle of a window. `reset` is nil when the window hasn't
/// reported one (not started), so it has no even pace either.
struct CurrentCycle: Equatable {
    let start: Date
    let reset: Date?
}

enum Forecast: Equatable {
    case runsOut(Date)
    case lastsPastReset
}

/// History split into cycles, and the run-out forecast. Ported from
/// Magpie's quota curves (quotaCycleBreak, quotaRecordedCycles, quotaEta),
/// adapted to history whose older lines carry no reset times.
enum UsageTrends {
    /// The windows charted, in card order.
    static let kinds: [MetricKind] = [.session, .weekly, .weeklyFable, .weeklyOpus, .weeklySonnet]

    /// The same deadline read twice can differ by a second or so; a real new
    /// cycle moves it by hours.
    static let resetSlack: TimeInterval = 5 * 60

    // MARK: Lines

    static func lines(from samples: [UsageSample]) -> [TrendLine] {
        kinds.compactMap { kind in
            let points: [TrendPoint] = samples.compactMap { sample in
                guard let used = value(of: kind, in: sample) else { return nil }
                return TrendPoint(at: sample.ts, left: min(max(100 - used.used, 0), 100), reset: used.reset)
            }
            guard !points.isEmpty else { return nil }
            return TrendLine(kind: kind, segments: split(points, kind: kind))
        }
    }

    private static func value(of kind: MetricKind, in s: UsageSample) -> (used: Double, reset: Date?)? {
        switch kind {
        case .session: return s.session.map { ($0, s.sessionReset) }
        case .weekly: return s.weekly.map { ($0, s.weeklyReset) }
        case .weeklyFable: return s.fable.map { ($0, s.fableReset) }
        case .weeklyOpus: return s.opus.map { ($0, s.opusReset) }
        case .weeklySonnet: return s.sonnet.map { ($0, s.sonnetReset) }
        case .extraUsage: return nil
        }
    }

    static func split(_ points: [TrendPoint], kind: MetricKind) -> [TrendSegment] {
        var groups: [[TrendPoint]] = []
        for point in points {
            if let prev = groups.last?.last, !isCycleBreak(prev, point) {
                groups[groups.count - 1].append(point)
            } else {
                groups.append([point])
            }
        }
        return groups.enumerated().map { TrendSegment(kind: kind, index: $0.offset, points: $0.element) }
    }

    /// Whether `b`, read after `a`, belongs to a new cycle of the window.
    static func isCycleBreak(_ a: TrendPoint, _ b: TrendPoint) -> Bool {
        let refilled = b.left > a.left + 5
        // Older lines have no reset times: go by a refill alone.
        guard let resetA = a.reset, let resetB = b.reset else { return refilled }
        if resetA <= b.at { return true }
        let moved = resetB.timeIntervalSince(resetA)
        let elapsed = b.at.timeIntervalSince(a.at)
        // A rolling window's deadline moves along with the clock.
        let rolling = moved > 0 && abs(moved - elapsed) <= resetSlack
        if !rolling && abs(moved) <= resetSlack && refilled { return true }
        return moved > elapsed + resetSlack || moved < -resetSlack
    }

    // MARK: Cycles

    /// The window's current cycle: reset − span → reset when it has a reset
    /// ahead, else from its last restart to now.
    static func currentCycle(of line: TrendLine?, window: UsageWindow?, now: Date) -> CurrentCycle? {
        if let reset = window?.resetsAt, reset > now, let span = line?.kind.span ?? nil {
            return CurrentCycle(start: reset.addingTimeInterval(-span), reset: reset)
        }
        guard let first = line?.segments.last?.points.first else { return nil }
        return CurrentCycle(start: min(first.at, now), reset: nil)
    }

    /// Recorded cycles of a window, oldest first. A cycle whose readings
    /// carry a reset spans reset − span → reset. Older ones are bounded by
    /// their readings, or by the deadline grid of `anchor` (a known reset,
    /// every `span` before it) when a grid point falls in the gap between
    /// two cycles — the usual Tuesday reset rather than the first reading
    /// after it.
    static func recordedCycles(of line: TrendLine, anchor: Date?) -> [TrendCycle] {
        guard let span = line.kind.span else { return [] }
        let segments = line.segments
        var cycles: [TrendCycle] = []
        for (i, segment) in segments.enumerated() {
            guard let first = segment.points.first, let last = segment.points.last else { continue }
            if let reset = segment.points.last(where: { $0.reset != nil })?.reset {
                cycles.append(TrendCycle(start: reset.addingTimeInterval(-span), end: reset))
                continue
            }
            let previousEnd = i > 0 ? segments[i - 1].points.last?.at : nil
            let nextStart = i + 1 < segments.count ? segments[i + 1].points.first?.at : nil
            var start = first.at
            var end = last.at
            if let anchor {
                // Latest grid point at or before the first reading, if the
                // reset could have happened there (after the previous cycle).
                let k = (anchor.timeIntervalSince(first.at) / span).rounded(.up)
                let gridStart = anchor.addingTimeInterval(-k * span)
                if previousEnd.map({ gridStart > $0 }) ?? true,
                   first.at.timeIntervalSince(gridStart) < span {
                    start = gridStart
                }
                // Earliest grid point after the last reading, if it comes
                // before the next cycle's first one.
                let j = (anchor.timeIntervalSince(last.at) / span).rounded(.down)
                let gridEnd = anchor.addingTimeInterval(-j * span)
                if gridEnd > last.at, nextStart.map({ gridEnd <= $0 }) ?? true {
                    end = gridEnd
                }
            }
            if let nextStart { end = min(end, nextStart) }
            cycles.append(TrendCycle(start: start, end: max(end, start)))
        }
        return cycles
    }

    // MARK: Forecast

    /// When the window empties at the pace of its latest falling run of
    /// readings this cycle (least squares, at least 3 readings over an hour,
    /// at most a week back). Nil when there isn't enough to tell, or the
    /// cycle is over.
    static func forecast(points: [TrendPoint], cycle: CurrentCycle, now: Date) -> Forecast? {
        if let reset = cycle.reset, reset <= now { return nil }
        let inCycle = points.filter { $0.at >= cycle.start && $0.at <= now }
        guard !inCycle.isEmpty else { return nil }
        var i = inCycle.count - 1
        while i > 0, inCycle[i - 1].left >= inCycle[i].left,
              now.timeIntervalSince(inCycle[i - 1].at) <= 7 * 86400 {
            i -= 1
        }
        let run = Array(inCycle[i...])
        guard run.count >= 3, let first = run.first, let last = run.last, last.left > 0,
              last.at.timeIntervalSince(first.at) >= 3600 else { return nil }

        let t0 = first.at
        let n = Double(run.count)
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for p in run {
            let x = p.at.timeIntervalSince(t0) / 86400
            sx += x; sy += p.left; sxx += x * x; sxy += x * p.left
        }
        let denominator = n * sxx - sx * sx
        guard denominator > 0 else { return nil }
        let slope = (n * sxy - sx * sy) / denominator   // % left per day
        guard slope < 0 else { return cycle.reset != nil ? .lastsPastReset : nil }
        let intercept = (sy - slope * sx) / n
        let out = t0.addingTimeInterval(-intercept / slope * 86400)
        guard out > now else { return nil }
        if let reset = cycle.reset, out >= reset { return .lastsPastReset }
        return .runsOut(out)
    }

    // MARK: Drawing helpers

    /// A segment's points for a chart over `domain`: the ones inside, plus
    /// the neighbours just outside so the line reaches the edges, thinned to
    /// one point per `step` while the value holds steady.
    static func visiblePoints(_ points: [TrendPoint], in domain: ClosedRange<Date>,
                              step: TimeInterval) -> [TrendPoint] {
        guard let firstInside = points.firstIndex(where: { $0.at >= domain.lowerBound }) else {
            return []
        }
        let lower = max(firstInside - 1, 0)
        let upper = min((points.lastIndex(where: { $0.at <= domain.upperBound }) ?? lower) + 1,
                        points.count - 1)
        guard lower <= upper else { return [] }
        var kept: [TrendPoint] = []
        var skipped: TrendPoint?
        for (offset, point) in points[lower...upper].enumerated() {
            let isLast = lower + offset == upper
            if let previous = kept.last, !isLast, previous.left == point.left,
               point.at.timeIntervalSince(previous.at) < step {
                skipped = point
                continue
            }
            // Keep the end of a flat stretch so a drop draws as a step.
            if let flat = skipped, flat.left != point.left { kept.append(flat) }
            skipped = nil
            kept.append(point)
        }
        return kept
    }
}

/// History as trend lines, read off the main thread and re-read after
/// each new sample.
@MainActor
final class TrendModel: ObservableObject {
    @Published private(set) var lines: [TrendLine] = []
    /// Finished cycles of the longest window, newest first, for the picker.
    @Published private(set) var pastCycles: [TrendCycle] = []
    /// The window that owns the cycle picker (usually Weekly).
    @Published private(set) var cycleKind: MetricKind?
    @Published private(set) var loadedAt: Date?

    private var isLoading = false

    func line(_ kind: MetricKind) -> TrendLine? {
        lines.first { $0.kind == kind }
    }

    /// The window's run-out forecast from its readings this cycle.
    func forecast(for kind: MetricKind, window: UsageWindow?, now: Date) -> Forecast? {
        guard let line = line(kind),
              let cycle = UsageTrends.currentCycle(of: line, window: window, now: now) else { return nil }
        // Only the segments reaching into this cycle, not all of history.
        let points = line.segments
            .filter { ($0.points.last?.at ?? .distantPast) >= cycle.start }
            .flatMap(\.points)
        return UsageTrends.forecast(points: points, cycle: cycle, now: now)
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let since = Date().addingTimeInterval(-365 * 86400)
        let now = Date()
        let result = await Task.detached(priority: .utility) { () -> ([TrendLine], MetricKind?, [TrendCycle]) in
            let lines = UsageTrends.lines(from: UsageHistory.load(since: since))
            // The longest window owns the picker; weekly ones come first.
            let owner = lines.max { ($0.kind.span ?? 0) < ($1.kind.span ?? 0) }
            guard let owner else { return (lines, nil, []) }
            let anchor = owner.points.last(where: { $0.reset != nil })?.reset
            let past = UsageTrends.recordedCycles(of: owner, anchor: anchor)
                .filter { $0.end <= now }
                .reversed()
                .prefix(26)
            return (lines, owner.kind, Array(past))
        }.value
        lines = result.0
        cycleKind = result.1
        pastCycles = result.2
        loadedAt = Date()
    }
}
