import Foundation

struct LexiconRankedItem: Sendable, Equatable {
    let term: String
    let count: Int
    let lastSeen: Date
    let score: Double
}

struct LexiconStyleSignals: Codable, Sendable, Equatable {
    var samples = 0
    var totalWords = 0
    var commaCount = 0
    var exclamationCount = 0
    var questionCount = 0
    var emojiCount = 0

    var averageWords: Double {
        guard samples > 0 else { return 0 }
        return Double(totalWords) / Double(samples)
    }
}

enum LexiconIngestSource: String, Sendable {
    case hostEditor
    case keyboardAccepted
}
