import Foundation
import SwiftUI

@MainActor
final class AnalyticsModel: ObservableObject {
    @Published var history: [UsageSample] = []
    @Published var tokenSamples: [TokenSample] = []
    @Published var hasClaudeAccess = ClaudeFolderAccess.resolve() != nil
    @Published var isLoading = false
    @Published var lastLoaded: Date?

    func grantAccess() {
        if ClaudeFolderAccess.requestAccess() != nil {
            hasClaudeAccess = true
            Task { await reload() }
        }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        let since = Date().addingTimeInterval(-30 * 86400)
        history = UsageHistory.load(since: since)

        guard let folder = ClaudeFolderAccess.resolve() else {
            hasClaudeAccess = false
            lastLoaded = Date()
            return
        }
        hasClaudeAccess = true
        tokenSamples = await Task.detached(priority: .userInitiated) {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            return TranscriptStats.collectSamples(claudeFolder: folder, since: since)
        }.value
        lastLoaded = Date()
    }

    // MARK: Aggregations

    struct ModelShare: Identifiable {
        let model: String
        let billable: Int
        let input: Int
        let output: Int
        let cacheRead: Int
        let share: Double
        var id: String { model }
    }

    func modelShares(since: Date) -> [ModelShare] {
        let windowSamples = tokenSamples.filter { $0.ts >= since }
        var byModel: [String: (billable: Int, input: Int, output: Int, cacheRead: Int)] = [:]
        for sample in windowSamples {
            var t = byModel[sample.model] ?? (0, 0, 0, 0)
            t.billable += sample.billable
            t.input += sample.input
            t.output += sample.output
            t.cacheRead += sample.cacheRead
            byModel[sample.model] = t
        }
        let total = max(byModel.values.reduce(0) { $0 + $1.billable }, 1)
        return byModel
            .map { ModelShare(model: $0.key, billable: $0.value.billable,
                              input: $0.value.input, output: $0.value.output,
                              cacheRead: $0.value.cacheRead,
                              share: Double($0.value.billable) / Double(total) * 100) }
            .sorted { $0.billable > $1.billable }
    }

    struct DayModelRow: Identifiable {
        let day: Date
        let model: String
        let tokens: Int
        var id: String { "\(day.timeIntervalSince1970)-\(model)" }
    }

    func tokensPerDay(since: Date) -> [DayModelRow] {
        let calendar = Calendar.current
        var buckets: [String: (day: Date, model: String, tokens: Int)] = [:]
        for sample in tokenSamples where sample.ts >= since {
            let day = calendar.startOfDay(for: sample.ts)
            let key = "\(day.timeIntervalSince1970)-\(sample.model)"
            var bucket = buckets[key] ?? (day, sample.model, 0)
            bucket.tokens += sample.billable
            buckets[key] = bucket
        }
        return buckets.values
            .map { DayModelRow(day: $0.day, model: $0.model, tokens: $0.tokens) }
            .sorted { $0.day < $1.day }
    }
}
