import Foundation

actor TinyStyleReranker {
    // MARK: - Dependencies

    private let model: TinyStyleLMModel

    // MARK: - Init

    init(model: TinyStyleLMModel = TinyStyleLMModel()) {
        self.model = model
    }

    // MARK: - API

    func rerank(
        context: TextContext,
        completions: [Completion],
        keepTop: Int
    ) async -> [Completion] {
        guard !completions.isEmpty, keepTop > 0 else {
            return []
        }

        await model.loadIfNeeded()
        let contextTokens = TinyStyleTokenizer.tokens(from: context.textBefore)

        var scored: [(Completion, Double)] = []
        scored.reserveCapacity(completions.count)

        for completion in completions {
            let candidateTokens = TinyStyleTokenizer.tokens(from: completion.text)
            let styleScore = await modelScore(
                contextTokens: contextTokens,
                candidateTokens: candidateTokens,
                fallbackConfidence: completion.confidence
            )
            scored.append((completion, styleScore))
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.confidence > rhs.0.confidence
                }
                return lhs.1 > rhs.1
            }
            .prefix(keepTop)
            .map { completion, styleScore in
                Completion(
                    text: completion.text,
                    confidence: max(completion.confidence, styleScore),
                    source: completion.source
                )
            }
    }

    // MARK: - Private

    private func modelScore(
        contextTokens: [String],
        candidateTokens: [String],
        fallbackConfidence: Double
    ) async -> Double {
        guard !candidateTokens.isEmpty else {
            return fallbackConfidence
        }

        let value = await model.score(contextTokens: contextTokens, candidateTokens: candidateTokens)
        guard value.isFinite else {
            return fallbackConfidence
        }

        // Convert log-likelihood into a stable 0...1-like signal.
        let normalized = 1.0 / (1.0 + exp(-value / Double(max(1, candidateTokens.count))))
        return max(0.01, min(0.99, normalized))
    }
}
