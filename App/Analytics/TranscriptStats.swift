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

    /// Fresh tokens the model actually processed/produced (cache reads are
    /// cheap replays and would drown the chart).
    var billable: Int { input + output + cacheCreate }
}

enum TranscriptStats {
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
            }
            let id: String?
            let model: String?
            let usage: Usage?
        }
        let type: String?
        let timestamp: String?
        let requestId: String?
        let message: Message?
    }

    static func collectSamples(claudeFolder: URL, since: Date) -> [TokenSample] {
        let projects = claudeFolder.appendingPathComponent("projects")
        guard let enumerator = FileManager.default.enumerator(
            at: projects,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        let decoder = JSONDecoder()
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        // Sessions can be resumed into new files, duplicating message lines —
        // dedupe on (message id, request id) like ccusage does.
        var seen = Set<String>()
        var samples: [TokenSample] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            // A file's mtime bounds its newest message; skip files that
            // predate the window entirely.
            if let mtime = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate, mtime < since {
                continue
            }
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
                    guard key != "|", !seen.contains(key) else { continue }
                    seen.insert(key)

                    samples.append(TokenSample(
                        ts: ts,
                        model: displayName(for: model),
                        input: usage.input_tokens ?? 0,
                        output: usage.output_tokens ?? 0,
                        cacheRead: usage.cache_read_input_tokens ?? 0,
                        cacheCreate: usage.cache_creation_input_tokens ?? 0
                    ))
                }
            }
        }
        return samples
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
