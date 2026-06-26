import XCTest
@testable import avgFlow

final class PromptBuilderTests: XCTestCase {
    // MARK: - Prompt Construction

    func testBuildPromptEscapesAndLimitsContextAndPatterns() {
        let beforeSource = String(repeating: "a", count: 510) + "<tag>&"
        let afterSource = "head>" + String(repeating: "b", count: 220)
        let context = TextContext(
            textBefore: beforeSource,
            textAfter: afterSource,
            appIdentifier: nil,
            language: "en"
        )

        let prompt = PromptBuilder.buildPrompt(
            context: context,
            suggestionCount: 3,
            userPatterns: ["  first  ", "", "second", "third", "fourth", "fifth", "sixth"]
        )

        let expectedBefore = escapeXML(String(beforeSource.suffix(Constants.Limits.contextBeforeCharacterLimit)))
        let expectedAfter = escapeXML(String(afterSource.prefix(Constants.Limits.contextAfterCharacterLimit)))

        XCTAssertTrue(prompt.contains("<context>\n\(expectedBefore)\n</context>"))
        XCTAssertTrue(prompt.contains("<after>\n\(expectedAfter)\n</after>"))
        XCTAssertTrue(prompt.contains("Provide 3 natural suggestions."))

        XCTAssertTrue(prompt.contains("- first"))
        XCTAssertTrue(prompt.contains("- second"))
        XCTAssertTrue(prompt.contains("- third"))
        XCTAssertTrue(prompt.contains("- fourth"))
        XCTAssertTrue(prompt.contains("- fifth"))
        XCTAssertFalse(prompt.contains("sixth"))
    }

    func testBuildPromptUsesNoneWhenPatternsEmptyAndSanitizesCount() {
        let context = TextContext(
            textBefore: "Hello",
            textAfter: "World",
            appIdentifier: nil,
            language: "ru<&>"
        )

        let prompt = PromptBuilder.buildPrompt(
            context: context,
            suggestionCount: 0,
            userPatterns: []
        )

        XCTAssertTrue(prompt.contains("<none/>"))
        XCTAssertTrue(prompt.contains("Provide 1 natural suggestions."))
        XCTAssertTrue(prompt.contains("Language: ru&lt;&amp;&gt;"))
    }

    // MARK: - Helpers

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

final class TextProcessorPartialAcceptanceTests: XCTestCase {
    func testPartialAcceptanceChunkConsumesWordAndFollowingWhitespace() {
        let suggestion = " hello world again"

        XCTAssertEqual(TextProcessor.partialAcceptanceChunk(from: suggestion), " hello ")
        XCTAssertEqual(TextProcessor.remainingTextAfterPartialAcceptance(from: suggestion), "world again")
    }

    func testPartialAcceptanceChunkConsumesFinalWord() {
        let suggestion = " world"

        XCTAssertEqual(TextProcessor.partialAcceptanceChunk(from: suggestion), " world")
        XCTAssertEqual(TextProcessor.remainingTextAfterPartialAcceptance(from: suggestion), "")
    }

    func testPartialAcceptanceChunkKeepsPunctuationAttachedToToken() {
        let suggestion = ", world"

        XCTAssertEqual(TextProcessor.partialAcceptanceChunk(from: suggestion), ", ")
        XCTAssertEqual(TextProcessor.remainingTextAfterPartialAcceptance(from: suggestion), "world")
    }

    func testPartialAcceptanceCanOmitTrailingWhitespace() {
        let suggestion = " hello world"

        XCTAssertEqual(
            TextProcessor.partialAcceptanceChunk(from: suggestion, includeTrailingWhitespace: false),
            " hello"
        )
        XCTAssertEqual(
            TextProcessor.remainingTextAfterPartialAcceptance(from: suggestion, includeTrailingWhitespace: false),
            " world"
        )
    }
}

final class AppOverridesStoreTests: XCTestCase {
    func testStorePersistsOverrideAndResolvesPolicies() {
        let suiteName = "AppOverridesStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppOverridesStore(defaults: defaults)
        store.registerSeenApp(bundleIdentifier: "com.example.Editor", displayName: "Editor")

        var record = store.record(for: "com.example.Editor")
        XCTAssertEqual(record?.displayName, "Editor")
        XCTAssertEqual(record?.resolvedCompletionsEnabled(), true)
        XCTAssertEqual(record?.resolvedTabDisabled(), false)

        record?.completionsMode = .disabled
        record?.disableTabMode = .enabled
        record?.customInstructions = "Be concise in this app."
        if let record {
            store.save(record)
        }

        let updated = store.record(for: "com.example.Editor")
        XCTAssertEqual(updated?.resolvedCompletionsEnabled(), false)
        XCTAssertEqual(updated?.resolvedTabDisabled(), true)
        XCTAssertEqual(store.customInstructions(for: "com.example.Editor"), "Be concise in this app.")
    }
}
