import Foundation

/// Per-message token counts parsed from Claude Code's local transcripts
/// (`~/.claude/projects/**/*.jsonl`). This covers Claude Code activity on this
/// Mac only — claude.ai chats and other devices count toward the same limits
/// but leave no local trace.
struct TokenSample {
    let ts: Date
    let model: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreate: Int
    /// Reasoning tokens, already counted inside `output`.
    let thinking: Int
    let sessionID: String
    /// The working directory (`cwd`) the request ran in.
    let project: String?
    /// Which Claude Code surface sent it (`entrypoint`): "claude-desktop",
    /// "claude-vscode", "cli", "sdk-cli"…
    let app: String?
    let effort: String?
    /// Sent by a subagent rather than the main conversation.
    let isSidechain: Bool

    /// Fresh tokens the model actually processed/produced (cache reads are
    /// cheap replays and would drown the chart).
    var billable: Int { input + output + cacheCreate }
    /// Input in the wide sense: fresh input plus cache writes.
    var inputTotal: Int { input + cacheCreate }
    /// The prompt as the model saw it: everything read, cached or not.
    var context: Int { input + cacheCreate + cacheRead }
}

enum TranscriptStats {
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                struct OutputDetails: Decodable { let thinking_tokens: Int? }
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
                let output_tokens_details: OutputDetails?
            }
            let id: String?
            let model: String?
            let usage: Usage?
        }
        let type: String?
        let timestamp: String?
        let requestId: String?
        let message: Message?
        let sessionId: String?
        let cwd: String?
        let entrypoint: String?
        let effort: String?
        let isSidechain: Bool?
    }

    // MARK: Incremental per-file cache
    //
    // Transcripts are append-only and numerous; re-parsing every file on each
    // Analytics load doesn't scale. Parsed samples are cached per file keyed
    // by (mtime, size) — only new or changed files get re-read. The dedup key
    // travels with each sample so cross-file dedup (resumed sessions copy
    // lines into new files) still works at aggregation time.

    /// Short coding keys: the cache holds every request ever made, and a
    /// session's id and folder repeat on each one.
    private struct CachedSample: Codable {
        let key: String
        let ts: Date
        let model: String
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheCreate: Int
        let thinking: Int
        let session: String
        let cwd: String?
        let app: String?
        let effort: String?
        let side: Bool

        enum CodingKeys: String, CodingKey {
            case key = "k", ts = "t", model = "m", input = "i", output = "o"
            case cacheRead = "r", cacheCreate = "w", thinking = "th"
            case session = "s", cwd = "c", app = "a", effort = "e", side = "sc"
        }
    }

    private struct FileEntry: Codable {
        let mtime: Date
        let size: Int
        let samples: [CachedSample]
    }

    private static var cacheURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroupStore.suiteName)?
            .appendingPathComponent("transcript-cache-v2.json")
    }

    /// The first cache format, without sessions, folders or apps.
    private static var legacyCacheURL: URL? {
        cacheURL?.deletingLastPathComponent().appendingPathComponent("transcript-cache.json")
    }

    static func collectSamples(claudeFolder: URL, since: Date) -> [TokenSample] {
        let projects = claudeFolder.appendingPathComponent("projects")
        guard let enumerator = FileManager.default.enumerator(
            at: projects,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }

        var cache = loadCache()
        var livePaths = Set<String>()
        var collected: [CachedSample] = []
        var changed = false

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            // A file's mtime bounds its newest message; files that predate the
            // window can't contribute and only get older — skip entirely.
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey,
                                                                     .fileSizeKey]),
                  let mtime = values.contentModificationDate,
                  mtime >= since else { continue }
            let size = values.fileSize ?? 0
            let path = fileURL.path
            livePaths.insert(path)

            if let entry = cache[path], entry.mtime == mtime, entry.size == size {
                collected.append(contentsOf: entry.samples)
            } else {
                let parsed = parse(fileURL, since: since)
                cache[path] = FileEntry(mtime: mtime, size: size, samples: parsed)
                collected.append(contentsOf: parsed)
                changed = true
            }
        }

        // Drop cache entries for deleted or aged-out files; write the cache
        // only when something in it changed (it holds every request).
        let live = cache.filter { livePaths.contains($0.key) }
        if changed || live.count != cache.count { saveCache(live) }

        var seenKeys = Set<String>()
        seenKeys.reserveCapacity(collected.count)
        var samples: [TokenSample] = []
        samples.reserveCapacity(collected.count)
        for sample in collected {
            guard sample.ts >= since, seenKeys.insert(sample.key).inserted else { continue }
            samples.append(TokenSample(ts: sample.ts, model: sample.model,
                                       input: sample.input, output: sample.output,
                                       cacheRead: sample.cacheRead, cacheCreate: sample.cacheCreate,
                                       thinking: sample.thinking, sessionID: sample.session,
                                       project: sample.cwd, app: sample.app,
                                       effort: sample.effort, isSidechain: sample.side))
        }
        return samples
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()

    private static func parse(_ fileURL: URL, since: Date) -> [CachedSample] {
        let decoder = JSONDecoder()
        var samples: [CachedSample] = []
        // Claude Code names each transcript after its session.
        let fileSession = fileURL.deletingPathExtension().lastPathComponent
        autoreleasepool {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
            for line in content.split(separator: "\n") where line.contains("\"usage\"") {
                guard let data = line.data(using: .utf8),
                      let entry = try? decoder.decode(Line.self, from: data),
                      entry.type == "assistant",
                      let message = entry.message,
                      let usage = message.usage,
                      let model = message.model, model != "<synthetic>",
                      let tsString = entry.timestamp,
                      let ts = isoFractional.date(from: tsString) ?? iso.date(from: tsString),
                      ts >= since else { continue }

                let key = "\(message.id ?? "")|\(entry.requestId ?? "")"
                guard key != "|" else { continue }

                samples.append(CachedSample(
                    key: key, ts: ts, model: displayName(for: model),
                    input: usage.input_tokens ?? 0,
                    output: usage.output_tokens ?? 0,
                    cacheRead: usage.cache_read_input_tokens ?? 0,
                    cacheCreate: usage.cache_creation_input_tokens ?? 0,
                    thinking: usage.output_tokens_details?.thinking_tokens ?? 0,
                    session: entry.sessionId ?? fileSession,
                    cwd: entry.cwd, app: entry.entrypoint, effort: entry.effort,
                    side: entry.isSidechain ?? false
                ))
            }
        }
        return samples
    }

    private static func loadCache() -> [String: FileEntry] {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode([String: FileEntry].self, from: data) else { return [:] }
        return cache
    }

    private static func saveCache(_ cache: [String: FileEntry]) {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url)
        if let legacy = legacyCacheURL { try? FileManager.default.removeItem(at: legacy) }
    }

    /// "claude-opus-4-8" → "Opus 4.8", "claude-sonnet-4-6-20250930" → "Sonnet 4.6".
    static func displayName(for modelID: String) -> String {
        var id = modelID
        if let bracket = id.firstIndex(of: "[") { id = String(id[..<bracket]) }
        id = id.replacingOccurrences(of: "claude-", with: "")
        let parts = id.split(separator: "-").map(String.init)
            .filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
        guard let family = parts.first else { return modelID }
        let version = parts.dropFirst().filter { $0.allSatisfy(\.isNumber) }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version.joined(separator: "."))"
    }
}
