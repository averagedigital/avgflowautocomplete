import Foundation

enum TextNormalization {
    private static let englishStopwords: Set<String> = [
        "a", "an", "the", "to", "for", "of", "in", "on", "at", "and", "or", "but", "if", "then", "so", "is", "are", "am", "be", "was", "were", "it", "its", "this", "that", "these", "those", "as", "with", "from", "by", "you", "your", "we", "our", "they", "their", "i", "me", "my"
    ]

    private static let russianStopwords: Set<String> = [
        "и", "в", "во", "на", "по", "к", "ко", "за", "из", "у", "о", "об", "от", "до", "для", "с", "со", "а", "но", "или", "как", "что", "это", "тот", "эта", "эти", "же", "ли", "бы", "я", "ты", "он", "она", "мы", "вы", "они", "мой", "твой", "наш", "ваш", "их"
    ]

    static func tokenize(text: String, lang: String) -> [String] {
        let normalized = normalize(text)
        let stopwords = lang == "ru" ? russianStopwords : englishStopwords

        return normalized
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 }
            .filter { !stopwords.contains($0) }
    }

    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let stripped = lowered.replacingOccurrences(
            of: "[^\\p{L}\\p{N}\\-\\s]",
            with: " ",
            options: .regularExpression
        )

        return stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractPhrases(tokens: [String]) -> [String] {
        guard tokens.count >= 2 else {
            return []
        }

        var phrases: [String] = []

        for index in 0 ..< max(0, tokens.count - 1) {
            phrases.append("\(tokens[index]) \(tokens[index + 1])")
        }

        if tokens.count >= 3 {
            for index in 0 ..< max(0, tokens.count - 2) {
                phrases.append("\(tokens[index]) \(tokens[index + 1]) \(tokens[index + 2])")
            }
        }

        return phrases
    }

    static func emojiCount(in text: String) -> Int {
        text.reduce(into: 0) { partialResult, character in
            if character.isEmoji {
                partialResult += 1
            }
        }
    }
}

private extension Character {
    var isEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }
}
