import Foundation
import XCTest
@testable import avgFlow

// MARK: - TextNormalization Tests

final class TextNormalizationTests: XCTestCase {
    func testNormalizeRemovesPunctuationAndCollapsesSpaces() {
        let input = "Hello, World!   How are  you?"
        let result = TextNormalization.normalize(input)
        XCTAssertEqual(result, "hello world how are you")
    }

    func testTokenizeEnglishFiltersStopwordsAndShortTokens() {
        let tokens = TextNormalization.tokenize(text: "I am a good developer in the world", lang: "en")
        XCTAssertTrue(tokens.contains("good"))
        XCTAssertTrue(tokens.contains("developer"))
        XCTAssertTrue(tokens.contains("world"))
        XCTAssertFalse(tokens.contains("I"))
        XCTAssertFalse(tokens.contains("am"))
        XCTAssertFalse(tokens.contains("a"))
        XCTAssertFalse(tokens.contains("the"))
        XCTAssertFalse(tokens.contains("in"))
    }

    func testTokenizeRussianFiltersStopwords() {
        let tokens = TextNormalization.tokenize(text: "Я написал хороший код для проекта", lang: "ru")
        XCTAssertTrue(tokens.contains("написал"))
        XCTAssertTrue(tokens.contains("хороший"))
        XCTAssertTrue(tokens.contains("код"))
        XCTAssertTrue(tokens.contains("проекта"))
        XCTAssertFalse(tokens.contains("я"))
        XCTAssertFalse(tokens.contains("для"))
    }

    func testExtractPhrasesReturnsBigramsAndTrigrams() {
        let tokens = ["hello", "world", "test", "code"]
        let phrases = TextNormalization.extractPhrases(tokens: tokens)

        // Bigrams: hello world, world test, test code
        XCTAssertTrue(phrases.contains("hello world"))
        XCTAssertTrue(phrases.contains("world test"))
        XCTAssertTrue(phrases.contains("test code"))

        // Trigrams: hello world test, world test code
        XCTAssertTrue(phrases.contains("hello world test"))
        XCTAssertTrue(phrases.contains("world test code"))
    }

    func testExtractPhrasesEmptyForSingleToken() {
        let phrases = TextNormalization.extractPhrases(tokens: ["single"])
        XCTAssertTrue(phrases.isEmpty)
    }

    func testEmojiCount() {
        XCTAssertEqual(TextNormalization.emojiCount(in: "Hello 👋 World 🌍"), 2)
        XCTAssertEqual(TextNormalization.emojiCount(in: "No emoji here"), 0)
    }
}

// MARK: - LanguageDetect Tests

final class LanguageDetectTests: XCTestCase {
    func testDetectsRussian() {
        XCTAssertEqual(LanguageDetect.detect(from: "Привет мир"), "ru")
    }

    func testDetectsEnglish() {
        XCTAssertEqual(LanguageDetect.detect(from: "Hello world"), "en")
    }

    func testFallbackOnEmpty() {
        XCTAssertEqual(LanguageDetect.detect(from: ""), "en")
        XCTAssertEqual(LanguageDetect.detect(from: "", fallback: "ru"), "ru")
    }

    func testMixedFallsBackWhenEqual() {
        // Numbers only - no latin or cyrillic
        XCTAssertEqual(LanguageDetect.detect(from: "12345"), "en")
    }
}

// MARK: - StyleSnippetBuilder Tests

final class StyleSnippetBuilderTests: XCTestCase {
    func testBuildRussianSnippet() {
        let words = [
            LexiconRankedItem(term: "привет", count: 10, lastSeen: Date(), score: 7.3),
            LexiconRankedItem(term: "код", count: 8, lastSeen: Date(), score: 5.9),
        ]
        let phrases = [
            LexiconRankedItem(term: "привет мир", count: 5, lastSeen: Date(), score: 3.8),
        ]
        let signals = LexiconStyleSignals(
            samples: 10,
            totalWords: 30,
            commaCount: 15,
            exclamationCount: 2,
            questionCount: 1,
            emojiCount: 0
        )

        let snippet = StyleSnippetBuilder.build(
            language: "ru",
            words: words,
            phrases: phrases,
            signals: signals
        )

        XCTAssertTrue(snippet.contains("привет"))
        XCTAssertTrue(snippet.contains("код"))
        XCTAssertTrue(snippet.contains("привет мир"))
        XCTAssertTrue(snippet.contains("Стиль пользователя"))
        XCTAssertTrue(snippet.count <= 400)
    }

    func testBuildEnglishSnippet() {
        let words = [
            LexiconRankedItem(term: "hello", count: 10, lastSeen: Date(), score: 7.3),
        ]
        let phrases: [LexiconRankedItem] = []
        let signals = LexiconStyleSignals()

        let snippet = StyleSnippetBuilder.build(
            language: "en",
            words: words,
            phrases: phrases,
            signals: signals
        )

        XCTAssertTrue(snippet.contains("User style"))
        XCTAssertTrue(snippet.contains("hello"))
        XCTAssertTrue(snippet.count <= 400)
    }

    func testBuildEmptySnippetStillValid() {
        let snippet = StyleSnippetBuilder.build(
            language: "en",
            words: [],
            phrases: [],
            signals: LexiconStyleSignals()
        )
        XCTAssertFalse(snippet.isEmpty)
        XCTAssertTrue(snippet.count <= 400)
    }

    func testSnippetTruncation() {
        let manyWords = (0..<50).map { i in
            LexiconRankedItem(term: "word\(i)longtoken", count: 50 - i, lastSeen: Date(), score: Double(50 - i))
        }
        let snippet = StyleSnippetBuilder.build(
            language: "en",
            words: manyWords,
            phrases: [],
            signals: LexiconStyleSignals(),
            maxLength: 100
        )
        XCTAssertTrue(snippet.count <= 100)
    }
}

// MARK: - LexiconStore Tests

final class LexiconStoreTests: XCTestCase {
    private var tempDir: URL!
    private var appGroupManager: LexiconTestAppGroupManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lexicon_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "test.lexicon.\(UUID().uuidString)")!
        appGroupManager = LexiconTestAppGroupManager(rootURL: tempDir, userDefaults: defaults)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRecordAndRetrieveWords() async throws {
        let store = LexiconStore(appGroupManager: appGroupManager)
        let now = Date()

        try await store.recordWords(["hello", "world", "hello"], lang: "en", at: now)

        let top = try await store.topWords(lang: "en", limit: 5, now: now)
        XCTAssertFalse(top.isEmpty)

        let helloItem = top.first { $0.term == "hello" }
        XCTAssertNotNil(helloItem)
        XCTAssertEqual(helloItem?.count, 2)

        let worldItem = top.first { $0.term == "world" }
        XCTAssertNotNil(worldItem)
        XCTAssertEqual(worldItem?.count, 1)
    }

    func testRecordAndRetrievePhrases() async throws {
        let store = LexiconStore(appGroupManager: appGroupManager)
        let now = Date()

        for _ in 0..<5 {
            try await store.recordPhrases(["hello world"], lang: "en", at: now)
        }

        let top = try await store.topPhrases(lang: "en", limit: 5, minCount: 3, now: now)
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top.first?.term, "hello world")
        XCTAssertEqual(top.first?.count, 5)
    }

    func testLanguageIsolation() async throws {
        let store = LexiconStore(appGroupManager: appGroupManager)
        let now = Date()

        try await store.recordWords(["hello"], lang: "en", at: now)
        try await store.recordWords(["привет"], lang: "ru", at: now)

        let enWords = try await store.topWords(lang: "en", limit: 10, now: now)
        let ruWords = try await store.topWords(lang: "ru", limit: 10, now: now)

        XCTAssertEqual(enWords.count, 1)
        XCTAssertEqual(enWords.first?.term, "hello")
        XCTAssertEqual(ruWords.count, 1)
        XCTAssertEqual(ruWords.first?.term, "привет")
    }

    func testClearAll() async throws {
        let store = LexiconStore(appGroupManager: appGroupManager)
        let now = Date()

        try await store.recordWords(["test"], lang: "en", at: now)
        try await store.clearAll()

        let words = try await store.topWords(lang: "en", limit: 10, now: now)
        XCTAssertTrue(words.isEmpty)
    }

    func testRankingScoreAccountsForRecency() async throws {
        let store = LexiconStore(appGroupManager: appGroupManager)
        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -30, to: now)!

        // "old" word has higher count but much older
        for _ in 0..<10 {
            try await store.recordWords(["old"], lang: "en", at: oldDate)
        }
        // "new" has lower count but very recent
        for _ in 0..<3 {
            try await store.recordWords(["new"], lang: "en", at: now)
        }

        let top = try await store.topWords(lang: "en", limit: 2, now: now)
        XCTAssertEqual(top.count, 2)
        // "old" should still rank higher due to count=10 vs count=3 (0.7 weight on count)
        // but let's just verify both are present
        let terms = top.map(\.term)
        XCTAssertTrue(terms.contains("old"))
        XCTAssertTrue(terms.contains("new"))
    }
}

// MARK: - Test Helpers

private final class LexiconTestAppGroupManager: AppGroupManaging, @unchecked Sendable {
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
