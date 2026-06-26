import Foundation

enum SingleSuggestionAcceptMode: String, CaseIterable, Identifiable {
    case nextWord
    case fullSuggestion

    var id: String { rawValue }

    init(storedValue: String?) {
        switch storedValue {
        case "fullSuggestion":
            self = .fullSuggestion
        case "nextChunk", "nextWord", nil:
            self = .nextWord
        default:
            self = .nextWord
        }
    }
}
