import Foundation

/// One utilization sample, persisted every ~5 minutes from the app's poll so
/// the Analytics window can chart limit usage over time. JSONL in the App
/// Group container; local only.
struct UsageSample: Codable, Identifiable {
    let ts: Date
    let session: Double?
    let weekly: Double?
    let opus: Double?
    let sonnet: Double?
    // Added later: absent from older lines, which still decode as nil.
    let fable: Double?
    /// Each window's reset as read with this sample, so charts can split
    /// history into cycles (a cycle runs from reset − span to reset). Nil
    /// for a window that wasn't reported or hadn't started.
    let sessionReset: Date?
    let weeklyReset: Date?
    let fableReset: Date?
    let opusReset: Date?
    let sonnetReset: Date?

    var id: Date { ts }
}

enum UsageHistory {
    private static let minSampleGap: TimeInterval = 4 * 60

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroupStore.suiteName)?
            .appendingPathComponent("usage-history.jsonl")
    }

    static func append(_ snapshot: UsageSnapshot) {
        guard let url = fileURL else { return }
        let lastKey = "lastHistorySample"
        if let last = AppGroupStore.defaults.object(forKey: lastKey) as? Date,
           Date().timeIntervalSince(last) < minSampleGap {
            return
        }
        AppGroupStore.defaults.set(Date(), forKey: lastKey)

        let sample = UsageSample(
            ts: snapshot.fetchedAt,
            session: snapshot.session?.utilization,
            weekly: snapshot.weekly?.utilization,
            opus: snapshot.weeklyOpus?.utilization,
            sonnet: snapshot.weeklySonnet?.utilization,
            fable: snapshot.weeklyFable?.utilization,
            sessionReset: snapshot.session?.resetsAt,
            weeklyReset: snapshot.weekly?.resetsAt,
            fableReset: snapshot.weeklyFable?.resetsAt,
            opusReset: snapshot.weeklyOpus?.resetsAt,
            sonnetReset: snapshot.weeklySonnet?.resetsAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(sample) else { return }
        line.append(0x0A)

        rotateIfNeeded(url)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    /// Samples at or after `since`, oldest first. Lines are appended in time
    /// order, so it reads back from the newest and stops at the first one
    /// older than `since`: a week costs a week of lines, not the whole file.
    static func load(since: Date) -> [UsageSample] {
        guard let url = fileURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var samples: [UsageSample] = []
        for line in content.split(separator: "\n").reversed() {
            guard let sample = try? decoder.decode(UsageSample.self, from: Data(line.utf8)) else { continue }
            if sample.ts < since { break }
            samples.append(sample)
        }
        return samples.reversed()
    }

    /// ~5 MB ≈ two years of 5-minute samples; keep one rotated generation.
    private static func rotateIfNeeded(_ url: URL) {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 5_000_000 else { return }
        let old = url.deletingPathExtension().appendingPathExtension("old.jsonl")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
}
