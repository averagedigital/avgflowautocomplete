import Foundation
import XCTest
@testable import avgFlow

final class UserDictionaryTests: XCTestCase {
    // MARK: - Lifecycle

    override func tearDown() {
        super.tearDown()
        TestUserDefaultsStore.cleanupAll()
    }

    // MARK: - Tests

    func testRecordAcceptedCompletionAndReturnQuickSuggestion() async throws {
        let dependencies = makeDependencies(maxEntries: 10)
        let dictionary = dependencies.dictionary

        let contextPrefix = TextProcessor.contextPrefix(for: "The weather today is")
        try await dictionary.recordAcceptedCompletion(
            phrase: " sunny and warm.",
            contextPrefix: contextPrefix,
            sourceApp: "com.apple.Notes"
        )
        try await dictionary.recordAcceptedCompletion(
            phrase: " sunny and warm.",
            contextPrefix: contextPrefix,
            sourceApp: "com.apple.Notes"
        )

        let context = TextContext(
            textBefore: "The weather today is",
            textAfter: "",
            appIdentifier: "com.apple.Notes",
            language: "en"
        )
        let suggestions = await dictionary.quickSuggestions(for: context, limit: 3)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.text, "sunny and warm.")
        XCTAssertEqual(suggestions.first?.source, .userDictionary)
        XCTAssertNotNil(suggestions.first?.confidence)
    }

    func testEntryLimitKeepsMostRecentPhrases() async throws {
        let dependencies = makeDependencies(maxEntries: 2)
        let dictionary = dependencies.dictionary
        let prefix = TextProcessor.contextPrefix(for: "prefix")

        try await dictionary.recordAcceptedCompletion(phrase: "first", contextPrefix: prefix, sourceApp: nil)
        try await Task.sleep(nanoseconds: 5_000_000)
        try await dictionary.recordAcceptedCompletion(phrase: "second", contextPrefix: prefix, sourceApp: nil)
        try await Task.sleep(nanoseconds: 5_000_000)
        try await dictionary.recordAcceptedCompletion(phrase: "third", contextPrefix: prefix, sourceApp: nil)

        let context = TextContext(textBefore: "prefix", textAfter: "", appIdentifier: nil, language: "en")
        let suggestions = await dictionary.quickSuggestions(for: context, limit: 5)
        let values = suggestions.map(\.text)

        XCTAssertEqual(suggestions.count, 2)
        XCTAssertFalse(values.contains("first"))
        XCTAssertTrue(values.contains("second"))
        XCTAssertTrue(values.contains("third"))
    }

    func testClearRemovesAllSuggestions() async throws {
        let dependencies = makeDependencies(maxEntries: 10)
        let dictionary = dependencies.dictionary
        let prefix = TextProcessor.contextPrefix(for: "Meeting notes")

        try await dictionary.recordAcceptedCompletion(
            phrase: " tomorrow at 10 AM",
            contextPrefix: prefix,
            sourceApp: nil
        )

        let context = TextContext(textBefore: "Meeting notes", textAfter: "", appIdentifier: nil, language: "en")
        let suggestionsBeforeClear = await dictionary.quickSuggestions(for: context, limit: 5)
        XCTAssertEqual(suggestionsBeforeClear.count, 1)

        try await dictionary.clear()

        let suggestionsAfterClear = await dictionary.quickSuggestions(for: context, limit: 5)
        XCTAssertEqual(suggestionsAfterClear.count, 0)
    }

    // MARK: - Helpers

    private func makeDependencies(maxEntries: Int) -> (
        dictionary: UserDictionary,
        stack: CoreDataStack,
        appGroupManager: TestAppGroupManager
    ) {
        let defaults = TestUserDefaultsStore.makeIsolated()
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appGroupManager = TestAppGroupManager(rootURL: rootURL, userDefaults: defaults)
        let stack = CoreDataStack(inMemory: true, appGroupManager: appGroupManager)
        let dictionary = UserDictionary(
            coreDataStack: stack,
            appGroupManager: appGroupManager,
            maxEntries: maxEntries,
            decayFactor: 0.95,
            decayInterval: 7 * 24 * 60 * 60
        )

        return (dictionary, stack, appGroupManager)
    }
}

private final class TestAppGroupManager: AppGroupManaging, @unchecked Sendable {
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

private enum TestUserDefaultsStore {
    private static var suiteNames: [String] = []

    static func makeIsolated() -> UserDefaults {
        let suiteName = "tests.ai.complete.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func cleanupAll() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
    }
}
