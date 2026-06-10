import Foundation

/// Local-only telemetry: one JSON line per usage fetch with duration, process
/// CPU time, resident memory, and outcome. Lives in the App Group container
/// so the app and widget share one file. Nothing ever leaves the machine.
///
/// Inspect with:
///   cat ~/Library/Group\ Containers/group.com.marcuslai.ClaudeUsage/perf-log.jsonl | jq
struct PerfEntry: Codable {
    let ts: Date
    let source: String     // "app" | "widget"
    let durationMs: Int    // wall time of this fetch
    let cpuMs: Int         // cumulative CPU time of the process so far
    let rssMB: Double      // resident memory at time of fetch
    let ok: Bool
    let error: String?
}

enum PerfLog {
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroupStore.suiteName)?
            .appendingPathComponent("perf-log.jsonl")
    }

    static func record(source: String, started: Date, error: String?) {
        guard let url = fileURL else { return }
        let entry = PerfEntry(
            ts: Date(),
            source: source,
            durationMs: Int(Date().timeIntervalSince(started) * 1000),
            cpuMs: processCPUMillis(),
            rssMB: (residentBytes() * 10 / 1_048_576).rounded() / 10,
            ok: error == nil,
            error: error
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(entry) else { return }
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

    /// Keep at most ~2 MB live + one rotated generation (months of headroom
    /// at one line per few minutes).
    private static func rotateIfNeeded(_ url: URL) {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 2_000_000 else { return }
        let old = url.deletingPathExtension().appendingPathExtension("old.jsonl")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }

    private static func processCPUMillis() -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) * 1000 + Double(usage.ru_utime.tv_usec) / 1000
        let system = Double(usage.ru_stime.tv_sec) * 1000 + Double(usage.ru_stime.tv_usec) / 1000
        return Int(user + system)
    }

    private static func residentBytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size
                                           / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) : 0
    }
}
