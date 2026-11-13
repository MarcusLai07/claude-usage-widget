import Foundation

/// The made-up account the screenshots show: a healthy mid-week Max plan and
/// twelve weeks of Claude Code on seven public repositories. Nothing comes
/// from the keychain, the network or ~/.claude. The draws are seeded, so a
/// run looks the same as the last one apart from the clock.
struct SampleData {
    let snapshot: UsageSnapshot
    let profile: AccountProfile
    /// Five-minute readings over the current weekly cycle and the two before.
    let history: [UsageSample]
    /// Every request, oldest first, and the sessions' titles.
    let scan: TranscriptScan

    /// The limits the popover and widgets list, in Settings' order.
    static let visibleMetrics: [MetricKind] = [.session, .weekly, .weeklyFable, .weeklyOpus, .weeklySonnet]

    // What the account reads now.
    static let sessionUsed = 38.0
    static let weeklyUsed = 57.0
    static let opusUsed = 41.0
    static let sonnetUsed = 22.0
    static let fableUsed = 12.0

    static func make(now: Date) -> SampleData {
        let fetchedAt = now.addingTimeInterval(-64)
        // The session window has 2 h 10 min to run; the week resets on the
        // hour 2 d 14–15 h out ("in 3d"), so 57% is a little under even pace.
        let sessionStart = now.addingTimeInterval(-(2 * 3600 + 50 * 60) + 40)
        let sessionReset = sessionStart.addingTimeInterval(5 * 3600)
        let weekAhead = now.addingTimeInterval(2 * 86400 + 14 * 3600)
        let weeklyReset = Date(timeIntervalSinceReferenceDate:
            (weekAhead.timeIntervalSinceReferenceDate / 3600).rounded(.up) * 3600)

        var generator = RequestGenerator(seed: 0xC1A0_DE5A_3B1E, fetchedAt: fetchedAt,
                                         currentSessionStart: sessionStart)
        let scan = generator.run()

        let snapshot = UsageSnapshot(
            fetchedAt: fetchedAt,
            session: UsageWindow(utilization: sessionUsed, resetsAt: sessionReset),
            weekly: UsageWindow(utilization: weeklyUsed, resetsAt: weeklyReset),
            weeklyOpus: UsageWindow(utilization: opusUsed, resetsAt: weeklyReset),
            weeklySonnet: UsageWindow(utilization: sonnetUsed, resetsAt: weeklyReset),
            extra: nil,
            weeklyFable: UsageWindow(utilization: fableUsed, resetsAt: weeklyReset))
        // A healthy week lasts past its reset at the pace of its readings.
        // How the requests fall over the week depends on the day this runs,
        // so lean on the steady share until the forecast says so.
        let weeklyStart = weeklyReset.addingTimeInterval(-7 * 86400)
        var history: [UsageSample] = []
        for elsewhere in [0.4, 0.55, 0.7, 0.85, 1] {
            history = makeHistory(requests: scan.samples, fetchedAt: fetchedAt,
                                  sessionStart: sessionStart, sessionReset: sessionReset,
                                  weeklyReset: weeklyReset, elsewhere: elsewhere)
            let weekly = UsageTrends.lines(from: history).first { $0.kind == .weekly }
            let forecast = UsageTrends.forecast(
                points: weekly?.points.filter { $0.at >= weeklyStart } ?? [],
                cycle: CurrentCycle(start: weeklyStart, reset: weeklyReset), now: now)
            if case .runsOut = forecast { continue }
            break
        }
        return SampleData(snapshot: snapshot,
                          profile: AccountProfile(email: "you@example.com", plan: "Max 20x", fetchedAt: now),
                          history: history, scan: scan)
    }

    // MARK: History

    /// What the app would have recorded every five minutes: each weekly
    /// window rising with the cost of the requests in its cycle plus a steady
    /// share (`elsewhere`) for use on claude.ai and other devices, scaled so
    /// the latest reading is the snapshot's; the 5-hour session window rising
    /// with the requests inside it.
    private static func makeHistory(requests: [TokenSample], fetchedAt: Date, sessionStart: Date,
                                    sessionReset: Date, weeklyReset: Date,
                                    elsewhere: Double) -> [UsageSample] {
        let week: TimeInterval = 7 * 86400
        let weeklyStart = weeklyReset.addingTimeInterval(-week)
        let priced = requests.filter { !$0.failed && $0.ts <= fetchedAt }

        // A cycle runs from its start (the previous reset) up to its reset.
        func cycleEnd(_ date: Date) -> Date {
            let k = (weeklyReset.timeIntervalSince(date) / week).rounded(.up) - 1
            return weeklyReset.addingTimeInterval(-k * week)
        }
        let elapsedNow = fetchedAt.timeIntervalSince(weeklyStart)
        func cost(_ sample: TokenSample, family: String?) -> Double {
            guard family == nil || sample.model.hasPrefix(family!) else { return 0 }
            return sample.cost ?? 0
        }
        let families: [String?] = [nil, "Opus", "Sonnet", "Fable"]
        let targets = [weeklyUsed, opusUsed, sonnetUsed, fableUsed]
        let current = priced.filter { $0.ts >= weeklyStart }
        let scales = zip(families, targets).map { family, target in
            target / max(current.reduce(0) { $0 + cost($1, family: family) }, 1e-9)
        }

        // 5-hour windows: each opens with the first request after the last
        // one closed; the current one opens at `sessionStart`.
        var windows: [(start: Date, end: Date, reset: Date)] = []
        for sample in priced where sample.ts < sessionStart {
            if let last = windows.last, sample.ts < last.end { continue }
            windows.append((sample.ts, min(sample.ts.addingTimeInterval(5 * 3600), sessionStart),
                            sample.ts.addingTimeInterval(5 * 3600)))
        }
        windows.append((sessionStart, sessionReset, sessionReset))
        let sessionScale = sessionUsed / max(priced.filter { $0.ts >= sessionStart }
            .reduce(0) { $0 + ($1.cost ?? 0) }, 1e-9)

        var samples: [UsageSample] = []
        var index = 0
        var sums = [Double](repeating: 0, count: families.count)
        var sumsCycle: Date?
        var windowIndex = 0
        var windowSum = 0.0
        var windowSumFor = -1
        var tick = weeklyReset.addingTimeInterval(-3 * week)
        while tick <= fetchedAt {
            while index < priced.count, priced[index].ts <= tick {
                let sample = priced[index]
                let end = cycleEnd(sample.ts)
                if end != sumsCycle { sums = sums.map { _ in 0 }; sumsCycle = end }
                for (i, family) in families.enumerated() { sums[i] += cost(sample, family: family) }
                while windowIndex + 1 < windows.count, windows[windowIndex + 1].start <= sample.ts { windowIndex += 1 }
                if windows[windowIndex].start <= sample.ts, sample.ts < windows[windowIndex].end {
                    if windowSumFor != windowIndex { windowSum = 0; windowSumFor = windowIndex }
                    windowSum += sample.cost ?? 0
                }
                index += 1
            }
            let end = cycleEnd(tick)
            let steady = tick.timeIntervalSince(end.addingTimeInterval(-week)) / elapsedNow
            let used = (0..<families.count).map { i -> Double in
                let here = sumsCycle == end ? sums[i] * scales[i] : 0
                return min(99, ((1 - elsewhere) * here + elsewhere * targets[i] * steady).rounded())
            }
            var session = 0.0
            var sessionResetAt: Date?
            if let w = windows.lastIndex(where: { $0.start <= tick && tick < $0.end }) {
                session = windowSumFor == w ? min(100, (windowSum * sessionScale).rounded()) : 0
                sessionResetAt = windows[w].reset
            }
            samples.append(UsageSample(ts: tick, session: session, weekly: used[0], opus: used[1],
                                       sonnet: used[2], fable: used[3],
                                       sessionReset: sessionResetAt, weeklyReset: end, fableReset: end,
                                       opusReset: end, sonnetReset: end))
            tick = tick.addingTimeInterval(300)
        }
        // The latest reading is the snapshot itself.
        samples.append(UsageSample(ts: fetchedAt, session: sessionUsed, weekly: weeklyUsed, opus: opusUsed,
                                   sonnet: sonnetUsed, fable: fableUsed,
                                   sessionReset: sessionReset, weeklyReset: weeklyReset,
                                   fableReset: weeklyReset, opusReset: weeklyReset, sonnetReset: weeklyReset))
        return samples
    }
}

// MARK: - Requests

/// Simulates Claude Code sessions: a main conversation whose prompt grows
/// call by call (cache reads of what came before, cache writes of what was
/// added), the odd subagent, quick Haiku calls, and a rare overloaded reply.
struct RequestGenerator {
    private var rng: SeededRandom
    private let fetchedAt: Date
    private let currentSessionStart: Date
    private var samples: [TokenSample] = []
    private var titles: [String: String] = [:]
    private var usedTitles: [String: Int] = [:]

    init(seed: UInt64, fetchedAt: Date, currentSessionStart: Date) {
        rng = SeededRandom(seed: seed)
        self.fetchedAt = fetchedAt
        self.currentSessionStart = currentSessionStart
    }

    private struct Project {
        let name: String
        let weight: Double
        let titles: [String]
    }

    /// Public repositories only.
    private static let projects: [Project] = [
        Project(name: "claude-usage-widget", weight: 0.24, titles: [
            "Rings widget for the medium size", "Pace line on the left-over chart",
            "Requests ledger sorting", "Stale banner after sleep", "Heatmap quantile scale",
            "Popover rows in the new look", "Week curve on the large widget", "Context tab replays",
            "Sign-in sheet copy", "Widget timeline refresh", "Cost column at API prices"]),
        Project(name: "bonsai", weight: 0.16, titles: [
            "Noise filter for orphan nodes", "Headless screenshot script", "Folder picker for graph roots",
            "Faster community detection", "Playbook tab layout", "Merge duplicate nodes",
            "Graph export to JSON", "Rebuild progress bar"]),
        Project(name: "lumen", weight: 0.14, titles: [
            "Settings store refactor", "Keyboard shortcuts pass", "Flaky snapshot test",
            "Dark mode polish", "Export progress sheet", "Onboarding checklist", "Crash on empty library",
            "Localise date formats"]),
        Project(name: "f1-pitwall", weight: 0.13, titles: [
            "Timing tower layout", "Tyre strategy chart", "Sector delta colours", "Race control feed",
            "Pit window estimate", "Gap chart smoothing", "Session picker"]),
        Project(name: "penang-transit-map", weight: 0.12, titles: [
            "Night palette for bus lines", "Bus speed stand-in for traffic", "Stop label collisions",
            "Full-day bus log importer", "Route legend layout", "Ferry line styling"]),
        Project(name: "planner-widget", weight: 0.11, titles: [
            "Week view widget", "Reminder sync", "Drag to reschedule", "Due-today badge",
            "Recurring tasks", "Calendar import"]),
        Project(name: "epic-seven-imprint-ledger", weight: 0.10, titles: [
            "Imprint calculator edge cases", "Weekly roster check", "Hero filter chips",
            "Import from the old tracker", "Weekly check workflow", "Roster stats page"]),
    ]

    /// Claude Code's entrypoints: Terminal, Claude Desktop, VS Code, Agent SDK.
    private static let apps: [(String, Double)] = [
        ("cli", 0.48), ("claude-desktop", 0.24), ("claude-vscode", 0.20), ("sdk-cli", 0.08),
    ]

    private static let mainModels: [(String, Double)] = [
        ("Opus 5.5", 0.62), ("Sonnet 5.5", 0.20), ("Fable 5.2", 0.18),
    ]

    /// Output tokens per second.
    private static func speed(_ model: String) -> Double {
        switch model {
        case "Haiku 5.5": return 190
        case "Sonnet 5.5": return 86
        case "Fable 5.2": return 44
        default: return 60
        }
    }

    private static func thinks(_ model: String) -> Bool { model.hasPrefix("Opus") || model.hasPrefix("Fable") }

    /// How much of a normal week a day `daysAgo` back saw: more lately.
    private static func volume(daysAgo: Int) -> Double {
        switch daysAgo {
        case ...4: return 1
        case ...11: return 0.82
        case ...18: return 0.74
        case ...40: return 0.66
        default: return 0.56
        }
    }

    mutating func run() -> TranscriptScan {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: fetchedAt)
        // Everything else ends before the current session window opens.
        let otherLimit = currentSessionStart.addingTimeInterval(-25 * 60)
        for daysAgo in stride(from: 83, through: 0, by: -1) {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let weekday = calendar.component(.weekday, from: day)
            var level = Self.volume(daysAgo: daysAgo) * rng.range(0.75...1.2)
            if weekday == 1 || weekday == 7 { level *= rng.range(0.2...0.5) }
            if daysAgo > 1, rng.chance(0.05) { continue }
            let count = max(0, Int((7 * level).rounded()) + rng.int(-1...1))
            for _ in 0..<count {
                let hour: Double
                switch rng.unit() {
                case ..<0.38: hour = rng.range(9.2...12)
                case ..<0.84: hour = rng.range(13.4...18.2)
                default: hour = rng.range(20.4...23.4)
                }
                let start = day.addingTimeInterval(hour * 3600)
                let limit = min(day.addingTimeInterval(27 * 3600), otherLimit)
                guard start < limit.addingTimeInterval(-15 * 60) else { continue }
                session(start: start, limit: limit, project: nil, app: nil, model: nil)
            }
        }
        // The sessions in progress: this repository in Terminal on Opus, and
        // for the last hour another in Claude Desktop on Fable.
        session(start: currentSessionStart, limit: fetchedAt.addingTimeInterval(-5),
                project: Self.projects[0], app: "cli", model: "Opus 5.5", calls: 400)
        session(start: fetchedAt.addingTimeInterval(-58 * 60), limit: fetchedAt.addingTimeInterval(-5),
                project: Self.projects[1], app: "claude-desktop", model: "Fable 5.2", calls: 400)
        samples.sort { $0.ts < $1.ts }
        return TranscriptScan(samples: samples, titles: titles)
    }

    // MARK: Sessions

    private mutating func session(start: Date, limit: Date, project: Project?, app: String?,
                                  model: String?, calls: Int? = nil) {
        let project = project ?? rng.pick(Self.projects.map { ($0, $0.weight) })
        let app = app ?? rng.pick(Self.apps)
        let model = model ?? rng.pick(Self.mainModels)
        let id = rng.uuid()
        let path = ClaudeFolderAccess.realHome.path + "/Developer/" + project.name
        let effort: String? = model == "Sonnet 5.5" ? "medium" : (rng.chance(0.75) ? "high" : "medium")
        let turns = calls ?? Int(rng.logNormal(median: 52, spread: 0.65)).clamped(to: 6...260)

        let used = usedTitles[project.name, default: rng.int(0...7)]
        usedTitles[project.name] = used + 1
        titles[id] = project.titles[used % project.titles.count]

        // Claude Code names the session with a quick Haiku call.
        var t = start
        quickCall(at: t.addingTimeInterval(rng.range(1.5...4)), session: id, path: path, app: app, limit: limit)

        var context = rng.int(17_000...30_000)
        var added = 0
        var lastReply: Date?
        for turn in 0..<turns {
            if turn > 0 { t = t.addingTimeInterval(gap()) }
            guard t < limit else { break }
            if rng.chance(0.0025) {
                failedCall(at: t.addingTimeInterval(rng.range(2...9)), session: id, path: path, app: app)
                t = t.addingTimeInterval(rng.range(8...20))
            }
            let prompt = context + added
            let warm = lastReply.map { t.timeIntervalSince($0) <= 3600 } ?? false
            // A cold call still finds the system prompt and tools cached.
            let cached = warm ? context : min(prompt, rng.int(12_000...15_000))
            let fresh = rng.int(3...60)
            let output = Int(rng.logNormal(median: 330, spread: 0.85)).clamped(to: 12...9_000)
            let thinking = Self.thinks(model) ? Int(Double(output) * rng.range(0.1...0.5)) : 0
            let seconds = 1.0 + Double(prompt) / 260_000 + rng.range(0...1.6)
                + Double(output) / (Self.speed(model) * rng.range(0.82...1.18))
            let finish = t.addingTimeInterval(seconds)
            guard finish < limit else { break }
            let write = max(0, prompt - cached - fresh)
            emit(model: model, at: finish, input: fresh, output: output, cacheRead: cached,
                 cacheWrite: write, write1h: write, thinking: thinking, session: id, path: path,
                 app: app, effort: effort, agent: nil, ms: Int(seconds * 1000))
            context = prompt
            added = output + toolResult()
            lastReply = finish
            t = finish
            if turn > 1, rng.chance(0.035) {
                t = subagent(start: t.addingTimeInterval(1), session: id, path: path, app: app, limit: limit)
                    .addingTimeInterval(rng.range(1...4))
                added += rng.int(1_500...6_000)
            }
            if rng.chance(0.04) {
                quickCall(at: t.addingTimeInterval(rng.range(0.4...2)), session: id, path: path, app: app,
                          limit: limit)
            }
        }
    }

    /// Seconds from a reply to the next call: a tool running, the person
    /// reading and typing, a coffee, a meeting.
    private mutating func gap() -> TimeInterval {
        switch rng.unit() {
        case ..<0.68: return rng.range(2...25)
        case ..<0.90: return rng.range(25...180)
        case ..<0.98: return rng.range(180...900)
        default: return rng.range(900...3300)
        }
    }

    /// What a tool hands back: usually a little, sometimes a whole file.
    private mutating func toolResult() -> Int {
        Int(rng.logNormal(median: 1_500, spread: 1.05)).clamped(to: 40...40_000)
    }

    /// A subagent's own conversation; returns when it finished.
    private mutating func subagent(start: Date, session: String, path: String, app: String, limit: Date) -> Date {
        let model: String
        switch rng.unit() {
        case ..<0.66: model = "Sonnet 5.5"
        case ..<0.86: model = "Haiku 5.5"
        default: model = "Opus 5.5"
        }
        let agent = "agent-" + rng.hex(8)
        var t = start
        var context = rng.int(11_000...19_000)
        var added = 0
        var lastReply: Date?
        for turn in 0..<rng.int(5...32) {
            if turn > 0 { t = t.addingTimeInterval(rng.range(0.8...9)) }
            let prompt = context + added
            let warm = lastReply.map { t.timeIntervalSince($0) <= 300 } ?? false
            let cached = warm ? context : min(prompt, rng.int(8_000...10_000))
            let fresh = rng.int(3...40)
            let output = Int(rng.logNormal(median: 190, spread: 0.8)).clamped(to: 10...4_000)
            let seconds = 0.8 + Double(prompt) / 300_000 + rng.range(0...1)
                + Double(output) / (Self.speed(model) * rng.range(0.85...1.15))
            let finish = t.addingTimeInterval(seconds)
            guard finish < limit else { break }
            emit(model: model, at: finish, input: fresh, output: output, cacheRead: cached,
                 cacheWrite: max(0, prompt - cached - fresh), write1h: 0,
                 thinking: Self.thinks(model) ? output / 4 : 0, session: session, path: path, app: app,
                 effort: nil, agent: agent, ms: Int(seconds * 1000))
            context = prompt
            added = output + Int(rng.logNormal(median: 1_200, spread: 0.9)).clamped(to: 40...20_000)
            lastReply = finish
            t = finish
        }
        return t
    }

    /// A small Haiku call: a session title, a command check.
    private mutating func quickCall(at time: Date, session: String, path: String, app: String, limit: Date) {
        guard time < limit else { return }
        let input = rng.int(600...3_200)
        let output = rng.int(6...60)
        let seconds = rng.range(0.4...1.1) + Double(output) / Self.speed("Haiku 5.5")
        emit(model: "Haiku 5.5", at: time, input: input, output: output, cacheRead: 0, cacheWrite: 0,
             write1h: 0, thinking: 0, session: session, path: path, app: app, effort: nil, agent: nil,
             ms: Int(seconds * 1000))
    }

    private mutating func failedCall(at time: Date, session: String, path: String, app: String) {
        samples.append(TokenSample(
            id: "msg_01" + rng.base62(22), ts: time, model: "", input: 0, output: 0, cacheRead: 0,
            cacheWrite: 0, cacheWrite1h: 0, thinking: 0, sessionID: session, project: path, app: app,
            effort: nil, isSidechain: false, agent: nil,
            error: rng.chance(0.8) ? "overloaded_error" : "api_error", durationMs: nil, cost: 0))
    }

    private mutating func emit(model: String, at time: Date, input: Int, output: Int, cacheRead: Int,
                               cacheWrite: Int, write1h: Int, thinking: Int, session: String, path: String,
                               app: String, effort: String?, agent: String?, ms: Int) {
        samples.append(TokenSample(
            id: "msg_01" + rng.base62(22), ts: time, model: model, input: input, output: output,
            cacheRead: cacheRead, cacheWrite: cacheWrite, cacheWrite1h: write1h, thinking: thinking,
            sessionID: session, project: path, app: app, effort: effort, isSidechain: agent != nil,
            agent: agent, error: nil, durationMs: ms,
            cost: ModelPricing.cost(model: model, input: input, output: output, cacheRead: cacheRead,
                                    cacheWrite: cacheWrite, cacheWrite1h: write1h)))
    }
}

// MARK: - Seeded randomness

/// SplitMix64, so the sample account is the same every run.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func range(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }

    mutating func chance(_ probability: Double) -> Bool { unit() < probability }

    /// Log-normal around `median`; `spread` is sigma.
    mutating func logNormal(median: Double, spread: Double) -> Double {
        let u = max(unit(), 1e-12), v = unit()
        return median * exp(spread * sqrt(-2 * log(u)) * cos(2 * .pi * v))
    }

    mutating func pick<T>(_ weighted: [(T, Double)]) -> T {
        var roll = unit() * weighted.reduce(0) { $0 + $1.1 }
        for (value, weight) in weighted {
            roll -= weight
            if roll < 0 { return value }
        }
        return weighted[weighted.count - 1].0
    }

    mutating func hex(_ count: Int) -> String {
        String((0..<count).map { _ in "0123456789abcdef".randomElement(using: &self)! })
    }

    mutating func base62(_ count: Int) -> String {
        let alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        return String((0..<count).map { _ in alphabet.randomElement(using: &self)! })
    }

    mutating func uuid() -> String {
        "\(hex(8))-\(hex(4))-4\(hex(3))-\(["8", "9", "a", "b"].randomElement(using: &self)!)\(hex(3))-\(hex(12))"
    }
}
