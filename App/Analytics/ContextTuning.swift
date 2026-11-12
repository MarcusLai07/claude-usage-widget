import Foundation

/// Works out, from what Claude Code really did on this Mac, the settings that
/// would have cost the fewest tokens: the window it compacts its conversation
/// at, and how long it keeps its prompt cache. Every setting is tried on the
/// user's own calls of the period, replayed one by one — the same prompts
/// growing by the same amounts at the same times, compacted or read from the
/// cache as the setting would have had them. The answers hold for this user's
/// habits only.
///
/// Ported from Magpie's `internal/tune` (compaction replay, rework, the 3%
/// bar for advice, the largest of the near-cheapest windows), weighing tokens
/// by each model's own Anthropic prices rather than generic ratios.
enum ContextTuning {
    /// One call as the replays see it.
    struct Call {
        let time: Date
        let stream: String
        let sub: Bool
        let model: String
        /// The whole prompt: input, cache read and cache write.
        let prompt: Int
        let output: Int
        let wrote: Int
        let wrote1h: Int
    }

    /// Each kind of token against one of plain input, from the model's price.
    struct Weights {
        let read: Double
        let write: Double
        let write1h: Double
        let output: Double
        /// USD per weighted token (the input price), to turn savings into ≈$.
        let usdPerUnit: Double

        static func of(_ model: String) -> Weights {
            guard let price = ModelPricing.price(for: model), price.input > 0 else {
                return Weights(read: 0.1, write: 1.25, write1h: 2, output: 5, usdPerUnit: 0)
            }
            return Weights(read: price.cacheRead / price.input, write: price.write5m / price.input,
                           write1h: price.write1h / price.input, output: price.output / price.input,
                           usdPerUnit: price.input / 1_000_000)
        }
    }

    /// One window tried, and what the period would have cost with it.
    struct Point: Identifiable {
        let window: Int
        let cost: Double
        let compactions: Int
        var id: Int { window }
    }

    /// What the replays found of how this user works.
    struct Facts {
        var calls = 0
        var streams = 0
        var compactions = 0
        /// Median prompt a compaction was made at, and right after one.
        var peak = 0
        var after = 0
        /// Median growth of a prompt from one call to the next.
        var growth = 0
        /// What a compaction costs to read back in the calls after it.
        var rework = 0
        /// Of the gaps between calls: under 5 minutes, 5–60 minutes, longer.
        var quick: Double = 0
        var pause: Double = 0
        var away: Double = 0
        /// Of the cache writes, the share kept an hour.
        var hourShare: Double = 0
    }

    struct Compaction {
        let model: String
        /// The window it runs with now (inferred), and the model's.
        let current: Int
        let modelWindow: Int
        let best: Int
        /// Weighted tokens of the period with `current`, and with `best`.
        let cost: Double
        let low: Double
        let curve: [Point]
        let facts: Facts
        let usdPerUnit: Double

        var saving: Double { cost > 0 ? (cost - low) / cost : 0 }
        var changes: Bool { best != current }
    }

    struct CacheLife {
        /// "5 min" or "1 hour".
        let current: String
        let best: String
        let short: Double
        let hour: Double
        let facts: Facts
        let usdPerUnit: Double

        var currentCost: Double { current == "1 hour" ? hour : short }
        var bestCost: Double { best == "1 hour" ? hour : short }
        var saving: Double { currentCost > 0 ? (currentCost - bestCost) / currentCost : 0 }
    }

    // MARK: Constants (Magpie's)

    /// A drop to under this share of the prompt before is a compaction…
    static let dropShare = 0.6
    /// …and only from a prompt at least this long.
    static let dropFrom = 20_000
    /// The calls after a compaction its rework is counted over.
    static let reworkCalls = 10
    /// Settings within this share of the cheapest cost the same: advice
    /// only changes what saves at least this much.
    static let sameCost = 0.03
    /// Claude Code compacts at the window less room for its reply.
    static let reserve = 33_000
    static let step = 10_000
    static let minWindow = 100_000

    static func calls(from samples: [TokenSample]) -> [Call] {
        samples.compactMap { sample in
            guard !sample.failed, sample.context > 0 else { return nil }
            return Call(time: sample.ts, stream: sample.stream, sub: sample.isSidechain || sample.agent != nil,
                        model: sample.model, prompt: sample.context, output: sample.output,
                        wrote: sample.cacheWrite, wrote1h: sample.cacheWrite1h)
        }
    }

    /// The context window a model runs with in Claude Code.
    static func modelWindow(_ model: String) -> Int {
        let parts = model.split(separator: " ")
        guard parts.count == 2, let version = Double(parts[1]) else { return 1_000_000 }
        switch parts[0] {
        case "Haiku": return version >= 5 ? 1_000_000 : 200_000
        case "Opus", "Sonnet": return version >= 4.6 ? 1_000_000 : 200_000
        default: return 1_000_000
        }
    }

    // MARK: Helpers

    static func streams(_ calls: [Call]) -> [[Call]] {
        Dictionary(grouping: calls, by: \.stream)
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted { $0.time < $1.time } }
    }

    static func compacted(_ previous: Int, _ current: Int) -> Bool {
        previous >= dropFrom && Double(current) < dropShare * Double(previous)
    }

    static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }

    static func observe(_ streams: [[Call]]) -> Facts {
        var facts = Facts()
        var peaks: [Int] = [], afters: [Int] = [], growths: [Int] = [], reworks: [Int] = []
        for stream in streams {
            facts.streams += 1
            facts.calls += stream.count
            var deltas: [Int] = []
            var cuts: [Int] = []
            for i in 1..<max(stream.count, 1) where i < stream.count {
                if compacted(stream[i - 1].prompt, stream[i].prompt) {
                    peaks.append(stream[i - 1].prompt)
                    afters.append(stream[i].prompt)
                    cuts.append(i)
                    continue
                }
                let delta = stream[i].prompt - stream[i - 1].prompt
                if delta >= 0 { deltas.append(delta) }
            }
            let typical = median(deltas)
            growths.append(contentsOf: deltas)
            // What the calls after a compaction read back beyond the usual
            // growth: the files and results the summary left out.
            for at in cuts {
                let end = at + reworkCalls
                guard end < stream.count else { continue }
                let clean = (at + 1...end).allSatisfy { !compacted(stream[$0 - 1].prompt, stream[$0].prompt) }
                if clean {
                    reworks.append(max(0, stream[end].prompt - stream[at].prompt - reworkCalls * typical))
                }
            }
        }
        facts.compactions = peaks.count
        facts.peak = median(peaks)
        facts.after = median(afters)
        facts.growth = median(growths)
        facts.rework = median(reworks)
        return facts
    }

    /// What the streams would have cost compacting at `threshold`: each
    /// prompt grows by what it grew by, a compaction happens when it would
    /// pass the threshold (Claude Code's own compactions are taken out), a
    /// compaction reads the whole prompt and writes a summary, and the calls
    /// after it read back the rework.
    static func replayCompaction(_ streams: [[Call]], threshold: Int, after: Int, base: Int,
                                 rework: Int, weights w: Weights, write: Double) -> (cost: Double, compactions: Int) {
        var cost = 0.0
        var count = 0
        let summary = max(0, after - base)
        for stream in streams {
            guard let first = stream.first else { continue }
            var context = first.prompt
            cost += Double(context) * write + Double(first.output) * w.output
            for i in 1..<max(stream.count, 1) where i < stream.count {
                var delta = stream[i].prompt - stream[i - 1].prompt
                if delta < 0 || compacted(stream[i - 1].prompt, stream[i].prompt) { delta = 0 }
                if context + delta > threshold && context > after {
                    cost += Double(context) * w.read + Double(summary) * w.output + Double(summary + rework) * write
                    context = after + rework
                    count += 1
                }
                cost += Double(context) * w.read + Double(delta) * write + Double(stream[i].output) * w.output
                context += delta
            }
        }
        return (cost, count)
    }

    /// The window to compact at for one model's calls; nil with too little
    /// to go on (fewer than 50 calls). `setting` is Claude Code's
    /// `autoCompactWindow`, when set; without it Claude Code runs a Claude
    /// model to its whole window.
    static func compaction(_ calls: [Call], model: String, setting: Int? = nil) -> Compaction? {
        let ss = streams(calls)
        var facts = observe(ss)
        guard facts.calls >= 50 else { return nil }
        let weights = Weights.of(model)
        let wrote = calls.reduce(0) { $0 + $1.wrote }
        let wrote1h = calls.reduce(0) { $0 + $1.wrote1h }
        if wrote > 0 { facts.hourShare = Double(wrote1h) / Double(wrote) }
        let write = facts.hourShare > 0.5 ? weights.write1h : weights.write
        let base = median(ss.compactMap(\.first?.prompt))
        let after = facts.after > 0 ? facts.after : base + 10_000
        let rework = facts.compactions < 5 ? max(facts.rework, 10_000) : facts.rework
        let window = modelWindow(model)
        // Claude Code compacts at the smaller of its setting and the window.
        let current = min(setting ?? window, window)
        let floor = max(minWindow, roundUp(after + max(after / 2, 20 * facts.growth) + reserve))
        func run(_ value: Int) -> Point {
            let result = replayCompaction(ss, threshold: max(after + 1, value - reserve), after: after,
                                          base: base, rework: rework, weights: weights, write: write)
            return Point(window: value, cost: result.cost, compactions: result.compactions)
        }
        let now = run(current)
        var curve: [Point] = []
        var value = floor
        while value <= window {
            curve.append(run(value))
            value += step
        }
        guard let low = curve.min(by: { $0.cost < $1.cost }) else { return nil }
        // Of the windows within 1% of the cheapest, the largest: fewer
        // compactions lose less of what the conversation knew.
        var best = low
        for point in curve where point.cost <= low.cost * 1.01 && point.window > best.window {
            best = point
        }
        // Only advise a change that saves 3% or more.
        if now.cost <= 0 || (now.cost - best.cost) / now.cost < sameCost {
            best = now
        }
        return Compaction(model: model, current: current, modelWindow: window, best: best.window,
                          cost: now.cost, low: best.cost, curve: curve, facts: facts,
                          usdPerUnit: weights.usdPerUnit)
    }

    /// What the streams would have cost with the cache kept for `ttl`: a call
    /// within it of the one before reads what that one sent and writes what
    /// it adds; one after it, or after a compaction, writes its prompt again.
    static func replayCache(_ streams: [[Call]], ttl: TimeInterval, hour: Bool) -> Double {
        var cost = 0.0
        for stream in streams {
            guard let first = stream.first else { continue }
            let w = Weights.of(first.model)
            let write = hour ? w.write1h : w.write
            cost += Double(first.prompt) * write
            for i in 1..<max(stream.count, 1) where i < stream.count {
                let previous = stream[i - 1].prompt, current = stream[i].prompt
                if stream[i].time.timeIntervalSince(stream[i - 1].time) > ttl || compacted(previous, current) {
                    cost += Double(current) * write
                } else if current >= previous {
                    cost += Double(previous) * w.read + Double(current - previous) * write
                } else {
                    cost += Double(current) * w.read
                }
            }
        }
        return cost
    }

    /// The cache lifetime for calls (all of the main conversation, or all of
    /// the subagents'); nil under 50 calls.
    static func cacheLife(_ calls: [Call]) -> CacheLife? {
        let ss = streams(calls)
        var facts = observe(ss)
        guard facts.calls >= 50 else { return nil }
        var wrote = 0, wrote1h = 0, gaps = 0, quick = 0, pause = 0
        for stream in ss {
            for (i, call) in stream.enumerated() {
                wrote += call.wrote
                wrote1h += call.wrote1h
                guard i > 0 else { continue }
                gaps += 1
                let gap = call.time.timeIntervalSince(stream[i - 1].time)
                if gap <= 300 { quick += 1 } else if gap <= 3600 { pause += 1 }
            }
        }
        if gaps > 0 {
            facts.quick = Double(quick) / Double(gaps)
            facts.pause = Double(pause) / Double(gaps)
            facts.away = 1 - facts.quick - facts.pause
        }
        if wrote > 0 { facts.hourShare = Double(wrote1h) / Double(wrote) }
        let current = facts.hourShare > 0.5 ? "1 hour" : "5 min"
        let short = replayCache(ss, ttl: 300, hour: false)
        let hour = replayCache(ss, ttl: 3600, hour: true)
        var best = hour < short ? "1 hour" : "5 min"
        let currentCost = current == "1 hour" ? hour : short
        let bestCost = best == "1 hour" ? hour : short
        if currentCost <= 0 || (currentCost - bestCost) / currentCost < sameCost { best = current }
        let model = Dictionary(grouping: calls, by: \.model).max { $0.value.count < $1.value.count }?.key ?? ""
        return CacheLife(current: current, best: best, short: short, hour: hour, facts: facts,
                         usdPerUnit: Weights.of(model).usdPerUnit)
    }

    static func roundTo(_ value: Int) -> Int { (value + step / 2) / step * step }
    static func roundUp(_ value: Int) -> Int { (value + step - 1) / step * step }

    // MARK: The whole report

    struct Report {
        var calls = 0
        var compactions: [Compaction] = []
        var mainCache: CacheLife?
        var subagentCache: CacheLife?

        /// The largest saving any advice offers.
        var bestSaving: Double {
            (compactions.map(\.saving) + [mainCache?.saving ?? 0, subagentCache?.saving ?? 0]).max() ?? 0
        }
    }

    /// Claude Code's `autoCompactWindow` (settings.json) or
    /// `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (its env), nil when neither is set.
    static func compactSetting(claudeFolder: URL) -> Int? {
        guard let data = try? Data(contentsOf: claudeFolder.appendingPathComponent("settings.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let value = json["autoCompactWindow"] as? Int, value > 0 { return value }
        if let env = json["env"] as? [String: Any],
           let raw = env["CLAUDE_CODE_AUTO_COMPACT_WINDOW"],
           let value = (raw as? Int) ?? Int("\(raw)"), value > 0 { return value }
        return nil
    }

    static func report(_ samples: [TokenSample], compactSetting: Int? = nil) -> Report {
        let all = calls(from: samples)
        var report = Report(calls: all.count)
        let byModel = Dictionary(grouping: all, by: \.model)
        report.compactions = byModel
            .filter { $0.value.count >= 50 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(3)
            .compactMap { compaction($0.value, model: $0.key, setting: compactSetting) }
        report.mainCache = cacheLife(all.filter { !$0.sub })
        report.subagentCache = cacheLife(all.filter(\.sub))
        return report
    }
}
