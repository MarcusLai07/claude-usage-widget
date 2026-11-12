import Foundation

/// One request (an API call) parsed from a Claude Code transcript
/// (`~/.claude/projects/**/*.jsonl`, or Claude Desktop's local-agent
/// sessions). This covers Claude Code activity on this Mac only — claude.ai
/// chats and other devices count toward the same limits but leave no local
/// trace.
struct TokenSample: Identifiable {
    /// The request's message id (or request id): one per call.
    let id: String
    /// When its reply finished (the message's last line).
    let ts: Date
    /// Display name, "Opus 5.5"; empty for a failed call.
    let model: String
    /// Fresh (uncached) input.
    let input: Int
    let output: Int
    let cacheRead: Int
    /// Cache writes, both durations.
    let cacheWrite: Int
    /// The part of `cacheWrite` cached for an hour (billed 2× input, not 1.25×).
    let cacheWrite1h: Int
    /// Reasoning tokens, already counted inside `output`.
    let thinking: Int
    let sessionID: String
    /// The working directory (`cwd`) the request ran in.
    let project: String?
    /// Which surface sent it (`entrypoint`): "claude-desktop",
    /// "claude-vscode", "cli", "sdk-cli", "local-agent"…
    let app: String?
    let effort: String?
    /// Sent by a subagent rather than the main conversation.
    let isSidechain: Bool
    /// An API error reply (no tokens), with its error code.
    let error: String?
    /// From the prompt (or the previous reply) to this reply's last line.
    let durationMs: Int?
    /// ≈ USD at API list prices; nil when the model isn't in the table.
    let cost: Double?

    var failed: Bool { error != nil }

    /// The same call filed under another folder.
    func with(project: String?) -> TokenSample {
        TokenSample(id: id, ts: ts, model: model, input: input, output: output,
                    cacheRead: cacheRead, cacheWrite: cacheWrite, cacheWrite1h: cacheWrite1h,
                    thinking: thinking, sessionID: sessionID, project: project, app: app,
                    effort: effort, isSidechain: isSidechain, error: error,
                    durationMs: durationMs, cost: cost)
    }
    /// Every token the call moved, as Magpie counts them.
    var tokens: Int { input + output + cacheRead + cacheWrite }
    /// The prompt as the model saw it: everything read, cached or not.
    var context: Int { input + cacheWrite + cacheRead }
}

/// What a scan of the transcripts found.
struct TranscriptScan {
    var samples: [TokenSample] = []
    /// Session id → its title: one you set (`/rename`), else Claude's own.
    var titles: [String: String] = [:]
}

enum TranscriptStats {
    /// A session's title line: `custom-title` or `ai-title`.
    private struct TitleLine: Decodable {
        let type: String?
        let sessionId: String?
        let customTitle: String?
        let aiTitle: String?
    }

    /// A string field that is sometimes another shape (or null).
    private struct LooseString: Decodable {
        let value: String?
        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                struct OutputDetails: Decodable { let thinking_tokens: Int? }
                struct CacheCreation: Decodable {
                    let ephemeral_1h_input_tokens: Int?
                    let ephemeral_5m_input_tokens: Int?
                }
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
                let cache_creation: CacheCreation?
                let output_tokens_details: OutputDetails?
            }
            let id: String?
            let model: String?
            let usage: Usage?
        }
        let type: String?
        let timestamp: String?
        let requestId: String?
        let uuid: String?
        let message: Message?
        let sessionId: String?
        let cwd: String?
        let entrypoint: String?
        let effort: LooseString?
        let perTurnEffort: LooseString?
        let isSidechain: Bool?
        let isApiErrorMessage: Bool?
        let error: LooseString?
    }

    // MARK: Incremental per-file cache
    //
    // Transcripts are append-only and numerous; re-parsing every file on each
    // load doesn't scale. Parsed samples are cached per file keyed by
    // (mtime, size) — only new or changed files get re-read. The message id
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
        let cacheCreate1h: Int
        let thinking: Int
        let session: String
        let cwd: String?
        let app: String?
        let effort: String?
        let side: Bool
        let error: String?
        let durationMs: Int?

        enum CodingKeys: String, CodingKey {
            case key = "k", ts = "t", model = "m", input = "i", output = "o"
            case cacheRead = "r", cacheCreate = "w", cacheCreate1h = "w1", thinking = "th"
            case session = "s", cwd = "c", app = "a", effort = "e", side = "sc"
            case error = "er", durationMs = "d"
        }
    }

    private struct FileEntry: Codable {
        let mtime: Date
        let size: Int
        let samples: [CachedSample]
        let titles: [String: String]
    }

    private static var cacheURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroupStore.suiteName)?
            .appendingPathComponent("transcript-cache-v4.json")
    }

    /// Earlier cache formats: without sessions, folders and apps (v1), without
    /// session titles (v2), or keeping a message's first line, not its last,
    /// and no failed calls or timings (v3).
    private static var legacyCacheURLs: [URL] {
        guard let folder = cacheURL?.deletingLastPathComponent() else { return [] }
        return ["transcript-cache.json", "transcript-cache-v2.json", "transcript-cache-v3.json"].map {
            folder.appendingPathComponent($0)
        }
    }

    /// The transcript files under one root: Claude Code's `projects` folder,
    /// or every local-agent session's Claude Code folder inside Claude
    /// Desktop's data folder.
    private static func transcriptFiles(claudeFolder: URL?, desktopFolder: URL?) -> [URL] {
        var roots: [URL] = []
        if let claudeFolder { roots.append(claudeFolder.appendingPathComponent("projects")) }
        if let desktopFolder { roots.append(desktopFolder.appendingPathComponent("local-agent-mode-sessions")) }
        var files: [URL] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                // In Desktop's folder, only the Claude Code transcripts.
                if root.lastPathComponent == "local-agent-mode-sessions",
                   !url.path.contains("/.claude/projects/") { continue }
                files.append(url)
            }
        }
        return files
    }

    static func scan(claudeFolder: URL?, desktopFolder: URL? = nil, since: Date) -> TranscriptScan {
        var cache = loadCache()
        var livePaths = Set<String>()
        var entries: [(mtime: Date, path: String, entry: FileEntry)] = []
        var changed = false

        for fileURL in transcriptFiles(claudeFolder: claudeFolder, desktopFolder: desktopFolder) {
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
                entries.append((mtime, path, entry))
            } else {
                let parsed = parse(fileURL, since: since)
                let entry = FileEntry(mtime: mtime, size: size, samples: parsed.samples, titles: parsed.titles)
                cache[path] = entry
                entries.append((mtime, path, entry))
                changed = true
            }
        }

        // Drop cache entries for deleted or aged-out files; write the cache
        // only when something in it changed (it holds every request).
        let live = cache.filter { livePaths.contains($0.key) }
        if changed || live.count != cache.count { saveCache(live) }

        // Earlier files own messages copied into a resumed session (as
        // Magpie does): merge oldest file first, first claim wins.
        entries.sort { $0.mtime != $1.mtime ? $0.mtime < $1.mtime : $0.path < $1.path }
        var seenKeys = Set<String>()
        var samples: [TokenSample] = []
        var titles: [String: String] = [:]
        for (_, _, entry) in entries {
            titles.merge(entry.titles) { _, new in new }
            for sample in entry.samples {
                guard sample.ts >= since, seenKeys.insert(sample.key).inserted else { continue }
                samples.append(TokenSample(
                    id: sample.key, ts: sample.ts, model: sample.model,
                    input: sample.input, output: sample.output,
                    cacheRead: sample.cacheRead, cacheWrite: sample.cacheCreate,
                    cacheWrite1h: sample.cacheCreate1h, thinking: sample.thinking,
                    sessionID: sample.session, project: sample.cwd, app: sample.app,
                    effort: sample.effort, isSidechain: sample.side,
                    error: sample.error, durationMs: sample.durationMs,
                    cost: sample.error != nil ? 0 : ModelPricing.cost(
                        model: sample.model, input: sample.input, output: sample.output,
                        cacheRead: sample.cacheRead, cacheWrite: sample.cacheCreate,
                        cacheWrite1h: sample.cacheCreate1h)
                ))
            }
        }
        return TranscriptScan(samples: samples, titles: titles)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()

    private static func date(_ string: String) -> Date? {
        isoFractional.date(from: string) ?? iso.date(from: string)
    }

    private static let usageTag = Array("\"usage\"".utf8)
    private static let apiErrorTag = Array("\"isApiErrorMessage\":true".utf8)
    private static let customTitleTag = Array("\"custom-title\"".utf8)
    private static let aiTitleTag = Array("\"ai-title\"".utf8)
    private static let userTypeTag = Array("\"type\":\"user\"".utf8)
    private static let timestampTag = Array("\"timestamp\":\"".utf8)

    /// Whether `needle` occurs in the `count` bytes at `bytes`.
    private static func contains(_ bytes: UnsafeRawPointer, _ count: Int, _ needle: [UInt8]) -> Bool {
        needle.withUnsafeBytes { memmem(bytes, count, $0.baseAddress, $0.count) != nil }
    }

    /// A user line's top-level timestamp. Claude Code writes it after the
    /// message (which can be a huge tool result), so it is read from the
    /// line's tail rather than by decoding the line: the last
    /// `"timestamp":"` in its final kilobyte.
    private static func userTimestamp(_ line: UnsafeRawPointer, _ length: Int) -> Date? {
        let tailLength = min(length, 1024)
        let tail = line + (length - tailLength)
        var found: UnsafeRawPointer?
        var cursor = tail
        var remaining = tailLength
        while remaining > 0,
              let hit = timestampTag.withUnsafeBytes({ memmem(cursor, remaining, $0.baseAddress, $0.count) }) {
            let hitPointer = UnsafeRawPointer(hit)
            found = hitPointer
            let advance = cursor.distance(to: hitPointer) + timestampTag.count
            cursor += advance
            remaining -= advance
        }
        guard let found else { return nil }
        let valueStart = found + timestampTag.count
        let available = valueStart.distance(to: line + length)
        guard available > 0,
              let quote = memchr(valueStart, 0x22, min(available, 40)) else { return nil }
        let count = valueStart.distance(to: UnsafeRawPointer(quote))
        let text = String(decoding: UnsafeRawBufferPointer(start: valueStart, count: count), as: UTF8.self)
        return date(text)
    }

    /// Works on the file's bytes: transcripts run to hundreds of megabytes,
    /// mostly tool output, so lines are found with memchr, the few that
    /// matter with memmem, and only those are copied and decoded.
    ///
    /// Claude Code writes one line per content block of a reply and repeats
    /// the message's usage on each; the **last** line has the final count
    /// (Magpie counts it the same way), so a later line replaces an earlier
    /// one. A reply's duration runs from the prompt, or the previous reply
    /// when it follows on, to its last line.
    private static func parse(_ fileURL: URL, since: Date) -> (samples: [CachedSample], titles: [String: String]) {
        let decoder = JSONDecoder()
        var samples: [CachedSample] = []
        var indexByKey: [String: Int] = [:]
        var askedByKey: [String: Date] = [:]
        var lastUser: Date?
        var lastReply: Date?
        var customTitles: [String: String] = [:]
        var aiTitles: [String: String] = [:]
        // Claude Code names each transcript after its session.
        let fileSession = fileURL.deletingPathExtension().lastPathComponent
        autoreleasepool {
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return }
            data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let line = base + offset
                    let remaining = buffer.count - offset
                    let length = memchr(line, 0x0A, remaining).map { line.distance(to: UnsafeRawPointer($0)) } ?? remaining
                    offset += length + 1
                    guard length > 0 else { continue }

                    // Title lines are short; the latest of each kind wins.
                    if length < 4000,
                       contains(line, length, customTitleTag) || contains(line, length, aiTitleTag),
                       let title = try? decoder.decode(TitleLine.self, from: Data(bytes: line, count: length)),
                       let session = title.sessionId {
                        if title.type == "custom-title", let text = title.customTitle, !text.isEmpty {
                            customTitles[session] = text
                        } else if title.type == "ai-title", let text = title.aiTitle, !text.isEmpty {
                            aiTitles[session] = text
                        }
                        continue
                    }
                    // A prompt or tool result: only its time matters.
                    if contains(line, min(length, 1024), userTypeTag) {
                        if let at = userTimestamp(line, length) { lastUser = at }
                        continue
                    }
                    let isError = contains(line, length, apiErrorTag)
                    guard isError || contains(line, length, usageTag),
                          let entry = try? decoder.decode(Line.self, from: Data(bytes: line, count: length)),
                          entry.type == "assistant",
                          let message = entry.message,
                          let tsString = entry.timestamp,
                          let ts = date(tsString),
                          ts >= since else { continue }

                    let rawModel = message.model ?? ""
                    let failed = entry.isApiErrorMessage == true
                    // A synthetic line is a call only as an API error.
                    if rawModel == "<synthetic>" && !failed { continue }
                    guard let key = message.id ?? entry.requestId ?? entry.uuid else { continue }
                    let usage = message.usage
                    if !failed && usage == nil { continue }

                    var asked = askedByKey[key]
                    if asked == nil {
                        asked = [lastUser, lastReply].compactMap { $0 }.max()
                        askedByKey[key] = asked
                    }
                    var duration: Int?
                    if let asked, ts > asked {
                        let ms = Int(ts.timeIntervalSince(asked) * 1000)
                        if ms < 2 * 3600 * 1000 { duration = ms }
                    }
                    let sample = CachedSample(
                        key: key, ts: ts,
                        model: failed ? "" : displayName(for: rawModel),
                        input: usage?.input_tokens ?? 0,
                        output: usage?.output_tokens ?? 0,
                        cacheRead: usage?.cache_read_input_tokens ?? 0,
                        cacheCreate: usage?.cache_creation_input_tokens ?? 0,
                        cacheCreate1h: usage?.cache_creation?.ephemeral_1h_input_tokens ?? 0,
                        thinking: usage?.output_tokens_details?.thinking_tokens ?? 0,
                        session: entry.sessionId ?? fileSession,
                        cwd: entry.cwd, app: entry.entrypoint,
                        effort: entry.perTurnEffort?.value ?? entry.effort?.value,
                        side: entry.isSidechain ?? false,
                        error: failed ? (entry.error?.value ?? "unknown") : nil,
                        durationMs: failed ? nil : duration
                    )
                    if let index = indexByKey[key] {
                        samples[index] = sample
                    } else {
                        indexByKey[key] = samples.count
                        samples.append(sample)
                    }
                    if lastReply.map({ ts > $0 }) ?? true { lastReply = ts }
                }
            }
        }
        return (samples, aiTitles.merging(customTitles) { _, custom in custom })
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
        for legacy in legacyCacheURLs { try? FileManager.default.removeItem(at: legacy) }
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
