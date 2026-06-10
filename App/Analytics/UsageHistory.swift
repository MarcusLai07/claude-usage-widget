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
            sonnet: snapshot.weeklySonnet?.utilization
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

    static func load(since: Date) -> [UsageSample] {
        guard let url = fileURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return content.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let sample = try? decoder.decode(UsageSample.self, from: data),
                  sample.ts >= since else { return nil }
            return sample
        }
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
