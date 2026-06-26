import Foundation

actor TinyStyleLMModel {
    // MARK: - State

    private struct State: Codable {
        var unigramCounts: [String: Int] = [:]
        var bigramCounts: [String: [String: Int]] = [:]
        var totalTokenCount: Int = 0
        var trainingSteps: Int = 0
        var updatedAt: Date = Date()
    }

    private let appGroupManager: AppGroupManaging
    private let fileManager: FileManager
    private var state = State()
    private var isLoaded = false

    // MARK: - Init

    init(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        fileManager: FileManager = .default
    ) {
        self.appGroupManager = appGroupManager
        self.fileManager = fileManager
    }

    // MARK: - Public

    func loadIfNeeded() {
        guard !isLoaded else {
            return
        }
        isLoaded = true
        do {
            try load()
        } catch {
            state = State()
        }
    }

    func score(contextTokens: [String], candidateTokens: [String]) -> Double {
        guard !candidateTokens.isEmpty else {
            return -.infinity
        }

        let vocabularySize = max(200, state.unigramCounts.count)
        let totalUnigrams = max(1, state.totalTokenCount)

        var previous = contextTokens.last ?? "<bos>"
        var totalLogProbability = 0.0

        for token in candidateTokens {
            let transitionCounts = state.bigramCounts[previous] ?? [:]
            let transitionTotal = max(1, transitionCounts.values.reduce(0, +))
            let pairCount = transitionCounts[token] ?? 0

            let unigramCount = state.unigramCounts[token] ?? 0
            let bigramProbability = Double(pairCount + 1) / Double(transitionTotal + vocabularySize)
            let unigramProbability = Double(unigramCount + 1) / Double(totalUnigrams + vocabularySize)
            let probability = (0.8 * bigramProbability) + (0.2 * unigramProbability)

            totalLogProbability += log(probability)
            previous = token
        }

        return totalLogProbability
    }

    func train(on examples: [TinyStyleExample]) -> (lossBefore: Double, lossAfter: Double) {
        guard !examples.isEmpty else {
            return (0, 0)
        }

        let lossBefore = negativeLogLikelihood(examples: examples)

        for example in examples {
            ingest(contextTokens: example.contextTokens, completionTokens: example.completionTokens)
        }

        state.trainingSteps += 1
        state.updatedAt = Date()

        let lossAfter = negativeLogLikelihood(examples: examples)
        return (lossBefore, lossAfter)
    }

    func save() throws {
        let url = try AppGroupPaths.tinyStyleWeightsURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: [.atomic])
    }

    func load() throws {
        let url = try AppGroupPaths.tinyStyleWeightsURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: url.path) else {
            state = State()
            return
        }
        let data = try Data(contentsOf: url)
        state = try JSONDecoder().decode(State.self, from: data)
    }

    func trainingSteps() -> Int {
        state.trainingSteps
    }

    // MARK: - Private

    private func negativeLogLikelihood(examples: [TinyStyleExample]) -> Double {
        let validExamples = examples.filter { !$0.completionTokens.isEmpty }
        guard !validExamples.isEmpty else {
            return 0
        }

        let total = validExamples.reduce(0.0) { partial, example in
            partial + (-score(contextTokens: example.contextTokens, candidateTokens: example.completionTokens))
        }
        return total / Double(validExamples.count)
    }

    private func ingest(contextTokens: [String], completionTokens: [String]) {
        guard !completionTokens.isEmpty else {
            return
        }

        var previous = contextTokens.last ?? "<bos>"
        for token in completionTokens {
            state.unigramCounts[token, default: 0] += 1
            state.totalTokenCount += 1

            var transitions = state.bigramCounts[previous] ?? [:]
            transitions[token, default: 0] += 1
            state.bigramCounts[previous] = transitions

            previous = token
        }
    }
}
