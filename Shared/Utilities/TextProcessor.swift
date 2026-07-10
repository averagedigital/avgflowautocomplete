import Foundation
import NaturalLanguage

enum TextProcessor {
    // MARK: - Context

    static func buildContext(
        textBefore: String,
        textAfter: String,
        appIdentifier: String? = nil,
        languageOverride: String? = nil,
        lexiconStyleSnippet: String? = nil,
        beforeLimit: Int = Constants.Limits.contextBeforeCharacterLimit,
        afterLimit: Int = Constants.Limits.contextAfterCharacterLimit
    ) -> TextContext {
        let trimmedBefore = String(textBefore.suffix(max(0, beforeLimit)))
        let trimmedAfter = String(textAfter.prefix(max(0, afterLimit)))
        let language = languageOverride ?? detectLanguage(for: "\(trimmedBefore) \(trimmedAfter)")

        return TextContext(
            textBefore: trimmedBefore,
            textAfter: trimmedAfter,
            appIdentifier: appIdentifier,
            language: language,
            lexiconStyleSnippet: lexiconStyleSnippet
        )
    }

    static func buildContext(
        fullText: String,
        cursorOffset: Int,
        appIdentifier: String? = nil,
        languageOverride: String? = nil,
        lexiconStyleSnippet: String? = nil,
        beforeLimit: Int = Constants.Limits.contextBeforeCharacterLimit,
        afterLimit: Int = Constants.Limits.contextAfterCharacterLimit
    ) -> TextContext {
        let boundedOffset = min(max(0, cursorOffset), fullText.count)
        let cursorIndex = fullText.index(fullText.startIndex, offsetBy: boundedOffset)
        let before = String(fullText[..<cursorIndex])
        let after = String(fullText[cursorIndex...])

        return buildContext(
            textBefore: before,
            textAfter: after,
            appIdentifier: appIdentifier,
            languageOverride: languageOverride,
            lexiconStyleSnippet: lexiconStyleSnippet,
            beforeLimit: beforeLimit,
            afterLimit: afterLimit
        )
    }

    static func buildContext(
        fullText: String,
        cursorUTF16Offset: Int,
        appIdentifier: String? = nil,
        languageOverride: String? = nil,
        lexiconStyleSnippet: String? = nil,
        beforeLimit: Int = Constants.Limits.contextBeforeCharacterLimit,
        afterLimit: Int = Constants.Limits.contextAfterCharacterLimit
    ) -> TextContext {
        let utf16View = fullText.utf16
        let boundedUTF16Offset = min(max(0, cursorUTF16Offset), utf16View.count)
        let utf16Index = utf16View.index(
            utf16View.startIndex,
            offsetBy: boundedUTF16Offset,
            limitedBy: utf16View.endIndex
        ) ?? utf16View.endIndex
        let cursorIndex = String.Index(utf16Index, within: fullText) ?? fullText.endIndex
        let before = String(fullText[..<cursorIndex])
        let after = String(fullText[cursorIndex...])

        return buildContext(
            textBefore: before,
            textAfter: after,
            appIdentifier: appIdentifier,
            languageOverride: languageOverride,
            lexiconStyleSnippet: lexiconStyleSnippet,
            beforeLimit: beforeLimit,
            afterLimit: afterLimit
        )
    }

    // MARK: - Language Detection

    static func detectLanguage(for text: String, fallback: String = "en") -> String {
        let compactText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compactText.isEmpty else {
            return fallback
        }

        let cyrillicCount = compactText.unicodeScalars.filter(isCyrillic).count
        let latinCount = compactText.unicodeScalars.filter(isLatin).count

        if cyrillicCount > latinCount, cyrillicCount >= 3 {
            return "ru"
        }
        if latinCount > cyrillicCount, latinCount >= 3 {
            return "en"
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(compactText)

        switch recognizer.dominantLanguage {
        case .russian:
            return "ru"
        case .english:
            return "en"
        default:
            return fallback
        }
    }

    // MARK: - Helpers

    static func contextPrefix(for textBefore: String) -> String {
        String(textBefore.suffix(Constants.Limits.userDictionaryContextPrefixLimit))
    }

    static func replacementSuffixUTF16Length(
        in textBefore: String,
        characterCount: Int
    ) -> Int {
        String(textBefore.suffix(max(0, characterCount))).utf16.count
    }

    static func wordCount(in text: String) -> Int {
        text
            .split { character in
                character.isWhitespace || character.isNewline
            }
            .count
    }

    static func endsWithSentenceBoundary(_ text: String) -> Bool {
        guard let lastCharacter = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".!?…\n".contains(lastCharacter)
    }

    static func normalizedSnippet(_ text: String, maxLength: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .split { $0.isWhitespace }
            .joined(separator: " ")
        return String(collapsed.suffix(max(0, maxLength)))
    }

    static func partialAcceptanceChunk(
        from suggestion: String,
        includeTrailingWhitespace: Bool = true
    ) -> String {
        let boundary = partialAcceptanceBoundary(
            in: suggestion,
            includeTrailingWhitespace: includeTrailingWhitespace
        )
        return String(suggestion[..<boundary])
    }

    static func remainingTextAfterPartialAcceptance(
        from suggestion: String,
        includeTrailingWhitespace: Bool = true
    ) -> String {
        let boundary = partialAcceptanceBoundary(
            in: suggestion,
            includeTrailingWhitespace: includeTrailingWhitespace
        )
        return String(suggestion[boundary...])
    }

    /// Produces only the continuation suffix that should be shown/inserted after `textBefore`.
    /// Strips echoed prefix if the model repeats already typed text.
    static func continuationSuffix(from rawSuggestion: String, after textBefore: String) -> String {
        var suggestion = rawSuggestion
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suggestion.isEmpty else { return "" }

        let before = textBefore
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let beforeTrimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !beforeTrimmed.isEmpty else { return suggestion }

        // First pass: exact character overlap (case-insensitive).
        if let exactDrop = exactOverlapPrefixLength(before: beforeTrimmed, suggestion: suggestion), exactDrop > 0 {
            suggestion = dropLeadingCharacters(suggestion, count: exactDrop)
        } else {
            // Second pass: tolerant overlap when punctuation/spacing differ.
            let tolerantDrop = tolerantOverlapPrefixLength(before: beforeTrimmed, suggestion: suggestion)
            if tolerantDrop > 0 {
                suggestion = dropLeadingCharacters(suggestion, count: tolerantDrop)
            }
        }

        suggestion = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suggestion.isEmpty else { return "" }

        // Add a leading space only when required.
        let firstScalar = suggestion.unicodeScalars.first
        let punctuationNoLeadingSpace: Set<UnicodeScalar> = [".", ",", "!", "?", ":", ";", ")", "]", "}"]
        let needsLeadingSpace = !before.hasSuffix(" ")
            && !before.hasSuffix("\n")
            && firstScalar.map { !punctuationNoLeadingSpace.contains($0) } == true

        return needsLeadingSpace ? " \(suggestion)" : suggestion
    }

    static func likelyMessageReset(previous: String, current: String) -> Bool {
        let previousTrimmed = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)

        if previousTrimmed.isEmpty {
            return false
        }
        if currentTrimmed.isEmpty {
            return true
        }
        return currentTrimmed.count < max(8, previousTrimmed.count / 4)
    }

    // MARK: - Overlap Helpers

    private static func exactOverlapPrefixLength(before: String, suggestion: String) -> Int? {
        let lowerBefore = before.lowercased()
        let lowerSuggestion = suggestion.lowercased()
        let overlapLimit = min(lowerBefore.count, lowerSuggestion.count)
        guard overlapLimit > 0 else { return nil }

        for overlap in stride(from: overlapLimit, through: 1, by: -1) {
            let beforeSuffix = lowerBefore.suffix(overlap)
            let suggestionPrefix = lowerSuggestion.prefix(overlap)
            if beforeSuffix == suggestionPrefix {
                return overlap
            }
        }
        return nil
    }

    private static func partialAcceptanceBoundary(
        in suggestion: String,
        includeTrailingWhitespace: Bool
    ) -> String.Index {
        guard !suggestion.isEmpty else {
            return suggestion.startIndex
        }

        var index = suggestion.startIndex

        while index < suggestion.endIndex, suggestion[index].isWhitespace {
            index = suggestion.index(after: index)
        }

        guard index < suggestion.endIndex else {
            return suggestion.endIndex
        }

        while index < suggestion.endIndex, !suggestion[index].isWhitespace {
            index = suggestion.index(after: index)
        }

        guard includeTrailingWhitespace else {
            return index
        }

        while index < suggestion.endIndex, suggestion[index].isWhitespace {
            index = suggestion.index(after: index)
        }

        return index
    }

    private static func tolerantOverlapPrefixLength(before: String, suggestion: String) -> Int {
        let beforeChars = Array(before.lowercased())
        let suggestionChars = Array(suggestion.lowercased())
        guard !beforeChars.isEmpty, !suggestionChars.isEmpty else { return 0 }

        let minMatchedCount = 5
        let startLowerBound = max(0, beforeChars.count - 140)
        var bestConsumedInSuggestion = 0

        for start in startLowerBound..<beforeChars.count {
            var i = start
            var j = 0
            var matchedLetters = 0
            var consumed = 0

            while i < beforeChars.count, j < suggestionChars.count {
                let bc = beforeChars[i]
                let sc = suggestionChars[j]

                if bc == sc {
                    i += 1
                    j += 1
                    consumed = j
                    if bc.isLetter || bc.isNumber {
                        matchedLetters += 1
                    }
                    continue
                }

                if isSoftSeparator(bc) {
                    i += 1
                    continue
                }

                if isSoftSeparator(sc) {
                    j += 1
                    consumed = j
                    continue
                }

                break
            }

            if i == beforeChars.count, matchedLetters >= minMatchedCount {
                bestConsumedInSuggestion = max(bestConsumedInSuggestion, consumed)
            }
        }

        return bestConsumedInSuggestion
    }

    private static func dropLeadingCharacters(_ value: String, count: Int) -> String {
        guard count > 0 else { return value }
        guard count < value.count else { return "" }
        let index = value.index(value.startIndex, offsetBy: count)
        return String(value[index...])
    }

    private static func isSoftSeparator(_ character: Character) -> Bool {
        if character.isWhitespace || character.isNewline {
            return true
        }
        return ",.!?:;…-—_()[]{}\"'`/\\|".contains(character)
    }

    private static func isLatin(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func isCyrillic(_ scalar: UnicodeScalar) -> Bool {
        (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
    }
}
