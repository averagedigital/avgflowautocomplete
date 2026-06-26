import Foundation

enum TinyStyleTokenizer {
    static let maxContextTokens = 128
    static let maxCompletionTokens = 32

    static func tokens(from text: String) -> [String] {
        let lowered = text.lowercased()
        let pattern = #"[\p{L}\p{N}\-]+|[.,!?;:]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(lowered.startIndex..., in: lowered)
        let matches = regex.matches(in: lowered, options: [], range: range)

        return matches.compactMap { match -> String? in
            guard let matchRange = Range(match.range, in: lowered) else {
                return nil
            }
            return String(lowered[matchRange])
        }
    }

    static func makeExample(context: String, completion: String, language: String) -> TinyStyleExample? {
        let contextTokens = Array(tokens(from: context).suffix(maxContextTokens))
        let completionTokens = Array(tokens(from: completion).prefix(maxCompletionTokens))

        guard !completionTokens.isEmpty else {
            return nil
        }

        return TinyStyleExample(
            contextTokens: contextTokens,
            completionTokens: completionTokens,
            language: language
        )
    }
}
