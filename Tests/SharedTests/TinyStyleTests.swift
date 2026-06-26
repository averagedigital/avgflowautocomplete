import Foundation
import XCTest
@testable import avgFlow

// MARK: - TinyStyleTokenizer Tests

final class TinyStyleTokenizerTests: XCTestCase {
    func testTokensFromSimpleEnglish() {
        let tokens = TinyStyleTokenizer.tokens(from: "Hello, world! How are you?")
        XCTAssertTrue(tokens.contains("hello"))
        XCTAssertTrue(tokens.contains("world"))
        XCTAssertTrue(tokens.contains("how"))
        XCTAssertTrue(tokens.contains("are"))
        XCTAssertTrue(tokens.contains("you"))
        // Punctuation tokens
        XCTAssertTrue(tokens.contains(","))
        XCTAssertTrue(tokens.contains("!"))
        XCTAssertTrue(tokens.contains("?"))
    }

    func testTokensFromRussian() {
        let tokens = TinyStyleTokenizer.tokens(from: "Привет, мир!")
        XCTAssertTrue(tokens.contains("привет"))
        XCTAssertTrue(tokens.contains("мир"))
    }

    func testTokensFromEmptyString() {
        let tokens = TinyStyleTokenizer.tokens(from: "")
        XCTAssertTrue(tokens.isEmpty)
    }

    func testMakeExampleReturnsNilForEmptyCompletion() {
        let example = TinyStyleTokenizer.makeExample(
            context: "Hello world",
            completion: "   ",
            language: "en"
        )
        XCTAssertNil(example)
    }

    func testMakeExampleCreatesValidExample() {
        let example = TinyStyleTokenizer.makeExample(
            context: "The weather is",
            completion: "sunny today",
            language: "en"
        )
        XCTAssertNotNil(example)
        XCTAssertFalse(example!.contextTokens.isEmpty)
        XCTAssertFalse(example!.completionTokens.isEmpty)
        XCTAssertEqual(example!.language, "en")
    }

    func testMakeExampleTruncatesLongContext() {
        let longContext = String(repeating: "word ", count: 500)
        let example = TinyStyleTokenizer.makeExample(
            context: longContext,
            completion: "end",
            language: "en"
        )
        XCTAssertNotNil(example)
        XCTAssertLessThanOrEqual(example!.contextTokens.count, TinyStyleTokenizer.maxContextTokens)
    }
}

// MARK: - TinyStyleLMModel Tests

final class TinyStyleLMModelTests: XCTestCase {
    func testScoreReturnsFiniteValue() async {
        let model = TinyStyleLMModel()
        let score = await model.score(
            contextTokens: ["hello", "world"],
            candidateTokens: ["how", "are", "you"]
        )
        XCTAssertTrue(score.isFinite)
    }

    func testScoreIsNegativeInfForEmptyCandidate() async {
        let model = TinyStyleLMModel()
        let score = await model.score(
            contextTokens: ["hello"],
            candidateTokens: []
        )
        XCTAssertEqual(score, -.infinity)
    }

    func testScoreIsDeterministic() async {
        let model = TinyStyleLMModel()
        let score1 = await model.score(
            contextTokens: ["the", "weather"],
            candidateTokens: ["is", "nice"]
        )
        let score2 = await model.score(
            contextTokens: ["the", "weather"],
            candidateTokens: ["is", "nice"]
        )
        XCTAssertEqual(score1, score2)
    }

    func testTrainingReducesLoss() async {
        let model = TinyStyleLMModel()
        await model.loadIfNeeded()

        let examples = (0..<20).compactMap { _ in
            TinyStyleTokenizer.makeExample(
                context: "The quick brown fox jumps over",
                completion: "the lazy dog",
                language: "en"
            )
        }
        XCTAssertFalse(examples.isEmpty)

        // Run multiple training steps to accumulate enough data
        var lastLossBefore = Double.infinity
        for _ in 0..<5 {
            let metrics = await model.train(on: examples)
            lastLossBefore = metrics.lossBefore
        }

        // After training on the same data multiple times, loss should decrease
        let finalMetrics = await model.train(on: examples)
        XCTAssertLessThan(finalMetrics.lossAfter, lastLossBefore,
                          "Training should reduce loss on repeated data")
    }

    func testTrainingStepsIncrement() async {
        let model = TinyStyleLMModel()
        await model.loadIfNeeded()

        let stepsBefore = await model.trainingSteps()

        let examples = [
            TinyStyleTokenizer.makeExample(
                context: "test context",
                completion: "test completion",
                language: "en"
            )!,
        ]
        _ = await model.train(on: examples)

        let stepsAfter = await model.trainingSteps()
        XCTAssertEqual(stepsAfter, stepsBefore + 1)
    }
}

// MARK: - TinyStyleReplayBuffer Tests

final class TinyStyleReplayBufferTests: XCTestCase {
    func testAddAndCount() async {
        let buffer = TinyStyleReplayBuffer(maxCapacity: 100)
        let countBefore = await buffer.count()
        XCTAssertEqual(countBefore, 0)

        let example = makeExample()
        await buffer.add(example)
        let countAfter = await buffer.count()
        XCTAssertEqual(countAfter, 1)
    }

    func testCapacityLimit() async {
        let buffer = TinyStyleReplayBuffer(maxCapacity: 5)

        for i in 0..<10 {
            await buffer.add(makeExample(context: "context\(i)"))
        }

        let count = await buffer.count()
        XCTAssertEqual(count, 5)
    }

    func testSampleMixed() async {
        let buffer = TinyStyleReplayBuffer(maxCapacity: 100)

        for i in 0..<50 {
            await buffer.add(makeExample(context: "context\(i)"))
        }

        let sample = await buffer.sampleMixed(batchSize: 16)
        XCTAssertEqual(sample.count, 16)
    }

    func testSampleMixedOnSmallBuffer() async {
        let buffer = TinyStyleReplayBuffer(maxCapacity: 100)
        await buffer.add(makeExample())

        let sample = await buffer.sampleMixed(batchSize: 16)
        XCTAssertFalse(sample.isEmpty)
        XCTAssertLessThanOrEqual(sample.count, 16)
    }

    func testSaveAndLoad() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let defaults = UserDefaults(suiteName: "test.replay.\(UUID().uuidString)")!
        let mgr = TinyStyleTestAppGroupManager(rootURL: tempDir, userDefaults: defaults)

        let buffer1 = TinyStyleReplayBuffer(appGroupManager: mgr, maxCapacity: 100)
        for i in 0..<5 {
            await buffer1.add(makeExample(context: "saved\(i)"))
        }
        try await buffer1.save()

        let buffer2 = TinyStyleReplayBuffer(appGroupManager: mgr, maxCapacity: 100)
        try await buffer2.load()
        let loadedCount = await buffer2.count()
        XCTAssertEqual(loadedCount, 5)
    }

    // MARK: - Helpers

    private func makeExample(context: String = "test context") -> TinyStyleExample {
        TinyStyleExample(
            contextTokens: TinyStyleTokenizer.tokens(from: context),
            completionTokens: ["completion"],
            language: "en"
        )
    }
}

// MARK: - TinyStyleReranker Tests

final class TinyStyleRerankerTests: XCTestCase {
    func testRerankReturnsRequestedCount() async {
        let reranker = TinyStyleReranker()
        let context = TextContext(
            textBefore: "The weather is",
            textAfter: "",
            appIdentifier: nil,
            language: "en"
        )

        let completions = [
            Completion(text: "sunny", confidence: 0.8, source: .cloud),
            Completion(text: "rainy", confidence: 0.7, source: .cloud),
            Completion(text: "cloudy", confidence: 0.6, source: .cloud),
            Completion(text: "windy", confidence: 0.5, source: .cloud),
            Completion(text: "snowy", confidence: 0.4, source: .cloud),
        ]

        let result = await reranker.rerank(context: context, completions: completions, keepTop: 3)
        XCTAssertEqual(result.count, 3)
    }

    func testRerankEmptyCompletions() async {
        let reranker = TinyStyleReranker()
        let context = TextContext(
            textBefore: "Test",
            textAfter: "",
            appIdentifier: nil,
            language: "en"
        )

        let result = await reranker.rerank(context: context, completions: [], keepTop: 3)
        XCTAssertTrue(result.isEmpty)
    }

    func testRerankPreservesCompletionText() async {
        let reranker = TinyStyleReranker()
        let context = TextContext(
            textBefore: "Hello",
            textAfter: "",
            appIdentifier: nil,
            language: "en"
        )

        let completions = [
            Completion(text: "world", confidence: 0.5, source: .cloud),
            Completion(text: "there", confidence: 0.6, source: .local),
        ]

        let result = await reranker.rerank(context: context, completions: completions, keepTop: 2)
        let texts = result.map(\.text)
        XCTAssertTrue(texts.contains("world"))
        XCTAssertTrue(texts.contains("there"))
    }
}

// MARK: - TinyStyleEventLogger Tests

final class TinyStyleEventLoggerTests: XCTestCase {
    func testAppendAndDrain() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("events_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let defaults = UserDefaults(suiteName: "test.events.\(UUID().uuidString)")!
        let mgr = TinyStyleTestAppGroupManager(rootURL: tempDir, userDefaults: defaults)
        let logger = TinyStyleEventLogger(appGroupManager: mgr)

        let event = TinyStyleEvent(
            context: "Hello world",
            completion: "how are you",
            language: "en",
            createdAt: Date()
        )
        try await logger.append(event: event)
        try await logger.append(event: event)

        let drained = try await logger.drainEvents(limit: 10)
        XCTAssertEqual(drained.count, 2)

        // After drain, should be empty
        let remaining = try await logger.drainEvents(limit: 10)
        XCTAssertTrue(remaining.isEmpty)
    }
}

// MARK: - Test Helpers

private final class TinyStyleTestAppGroupManager: AppGroupManaging, @unchecked Sendable {
    let rootURL: URL
    let userDefaults: UserDefaults

    init(rootURL: URL, userDefaults: UserDefaults) {
        self.rootURL = rootURL
        self.userDefaults = userDefaults
    }

    func sharedContainerURL() -> URL? {
        rootURL
    }

    func sharedUserDefaults() -> UserDefaults? {
        userDefaults
    }

    func modelsDirectoryURL(createIfMissing: Bool) throws -> URL {
        let url = rootURL.appendingPathComponent("Documents/models", isDirectory: true)
        if createIfMissing {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func persistentStoreURL(createParentIfMissing: Bool) throws -> URL {
        let directory = rootURL.appendingPathComponent("Documents", isDirectory: true)
        if createParentIfMissing {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("AIComplete.sqlite", isDirectory: false)
    }
}
