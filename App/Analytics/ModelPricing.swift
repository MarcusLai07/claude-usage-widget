import Foundation

/// USD per million tokens.
struct ModelPrice: Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double
    /// Cache writes kept for 5 minutes (1.25× input).
    let write5m: Double
    /// Cache writes kept for an hour (2× input).
    let write1h: Double

    /// The usual shape: cache writes 1.25× / 2× input; cache reads as given.
    init(_ input: Double, _ output: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        write5m = input * 1.25
        write1h = input * 2
    }
}

/// Anthropic API list prices for the models Claude Code uses, so the app can
/// show ≈ cost as Magpie does ("effective prices"), without a network call.
/// A subscription isn't billed per token: this is what the same calls would
/// cost on the API. Update when new models ship (claude.com/pricing).
enum ModelPricing {
    /// Keyed by display name ("Opus 5.5"), as transcripts are stored. Cache
    /// reads differ by model: 0.025× input on Fable 5.1/5.2, 0.05× on Opus
    /// and Sonnet 5.5, 0.1× elsewhere. Prices as of 2026-11.
    static let table: [String: ModelPrice] = {
        var table: [String: ModelPrice] = [
            "Fable 5.2": ModelPrice(8, 40, cacheRead: 0.20),
            "Fable 5.1": ModelPrice(10, 50, cacheRead: 0.25),
            "Fable 5": ModelPrice(10, 50, cacheRead: 1.00),
            "Opus 5.5": ModelPrice(4, 20, cacheRead: 0.20),
            "Opus 5": ModelPrice(5, 25, cacheRead: 0.50),
            "Opus 4.8": ModelPrice(5, 25, cacheRead: 0.50),
            "Opus 4.7": ModelPrice(5, 25, cacheRead: 0.50),
            "Opus 4.6": ModelPrice(5, 25, cacheRead: 0.50),
            "Opus 4.5": ModelPrice(5, 25, cacheRead: 0.50),
            "Opus 4.1": ModelPrice(15, 75, cacheRead: 1.50),
            "Opus 4": ModelPrice(15, 75, cacheRead: 1.50),
            "Sonnet 5.5": ModelPrice(2, 10, cacheRead: 0.10),
            "Sonnet 5": ModelPrice(2, 10, cacheRead: 0.20),
            "Sonnet 4.6": ModelPrice(3, 15, cacheRead: 0.30),
            "Sonnet 4.5": ModelPrice(3, 15, cacheRead: 0.30),
            "Sonnet 4": ModelPrice(3, 15, cacheRead: 0.30),
            "Sonnet 3.7": ModelPrice(3, 15, cacheRead: 0.30),
            "Haiku 5.5": ModelPrice(0.10, 0.50, cacheRead: 0.01),
            "Haiku 4.5": ModelPrice(1, 5, cacheRead: 0.10),
            "Haiku 3.5": ModelPrice(0.80, 4, cacheRead: 0.08),
        ]
        // Mythos models are priced as the Fable of the same version.
        for (name, price) in table where name.hasPrefix("Fable ") {
            table["Mythos" + name.dropFirst("Fable".count)] = price
        }
        return table
    }()

    /// Haiku 5.5 costs 5× more for a prompt over 100K tokens.
    private static let haikuLongPrompt = ModelPrice(0.50, 2.50, cacheRead: 0.05)

    static func price(for model: String, promptTokens: Int = 0) -> ModelPrice? {
        if model == "Haiku 5.5", promptTokens > 100_000 { return haikuLongPrompt }
        return table[model]
    }

    /// ≈ USD for one call; nil when the model isn't in the table.
    static func cost(model: String, input: Int, output: Int, cacheRead: Int,
                     cacheWrite: Int, cacheWrite1h: Int) -> Double? {
        guard let price = price(for: model, promptTokens: input + cacheRead + cacheWrite) else {
            return nil
        }
        let write1h = min(cacheWrite1h, cacheWrite)
        let write5m = cacheWrite - write1h
        let micro = Double(input) * price.input
            + Double(output) * price.output
            + Double(cacheRead) * price.cacheRead
            + Double(write5m) * price.write5m
            + Double(write1h) * price.write1h
        return micro / 1_000_000
    }
}
