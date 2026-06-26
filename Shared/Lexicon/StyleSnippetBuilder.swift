import Foundation

enum StyleSnippetBuilder {
    static func build(
        language: String,
        words: [LexiconRankedItem],
        phrases: [LexiconRankedItem],
        signals: LexiconStyleSignals,
        maxLength: Int = 400
    ) -> String {
        let isRussian = language.lowercased().hasPrefix("ru")

        let wordTerms = words.prefix(20).map(\.term)
        let phraseTerms = phrases.prefix(10).map(\.term)

        let frequentWords = fitList(wordTerms, maxCharacters: 140)
        let frequentPhrases = fitList(phraseTerms, maxCharacters: 160)
        let preferences = preferenceLine(signals: signals, russian: isRussian)

        let snippet: String
        if isRussian {
            snippet = "Стиль пользователя: часто использует слова: \(frequentWords); фразы: \(frequentPhrases); предпочтения: \(preferences)."
        } else {
            snippet = "User style: frequent words: \(frequentWords); frequent phrases: \(frequentPhrases); preferences: \(preferences)."
        }

        return truncate(snippet, maxLength: maxLength)
    }

    private static func preferenceLine(signals: LexiconStyleSignals, russian: Bool) -> String {
        let lengthPreference: String
        switch signals.averageWords {
        case ..<6:
            lengthPreference = russian ? "короткие предложения" : "short sentences"
        case 6..<12:
            lengthPreference = russian ? "средняя длина предложений" : "medium sentence length"
        default:
            lengthPreference = russian ? "длинные предложения" : "longer sentences"
        }

        let punctuationPreference: String
        if signals.commaCount >= max(signals.exclamationCount, signals.questionCount) {
            punctuationPreference = russian ? "много запятых" : "comma-heavy punctuation"
        } else if signals.questionCount > signals.exclamationCount {
            punctuationPreference = russian ? "частые вопросы" : "often asks questions"
        } else {
            punctuationPreference = russian ? "эмоциональные акценты" : "expressive punctuation"
        }

        let emojiPreference: String
        if signals.samples == 0 {
            emojiPreference = russian ? "эмодзи неизвестно" : "emoji usage unknown"
        } else {
            let ratio = Double(signals.emojiCount) / Double(signals.samples)
            if ratio < 0.1 {
                emojiPreference = russian ? "эмодзи редко" : "emoji rarely"
            } else if ratio < 0.35 {
                emojiPreference = russian ? "эмодзи иногда" : "emoji sometimes"
            } else {
                emojiPreference = russian ? "эмодзи часто" : "emoji often"
            }
        }

        return [lengthPreference, punctuationPreference, emojiPreference].joined(separator: ", ")
    }

    private static func fitList(_ values: [String], maxCharacters: Int) -> String {
        guard !values.isEmpty else {
            return "-"
        }

        var output: [String] = []
        var currentLength = 0

        for value in values {
            let tokenLength = value.count + (output.isEmpty ? 0 : 2)
            if currentLength + tokenLength > maxCharacters {
                break
            }
            output.append(value)
            currentLength += tokenLength
        }

        return output.isEmpty ? "-" : output.joined(separator: ", ")
    }

    private static func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength, maxLength > 1 else {
            return text
        }
        return String(text.prefix(maxLength - 1)) + "…"
    }
}
