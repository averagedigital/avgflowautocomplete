import Foundation

protocol CompletionEngine: Sendable {
    func complete(context: TextContext, maxTokens: Int, count: Int) async throws -> [Completion]
}

enum CompletionEngineError: LocalizedError, Equatable {
    case invalidCount
    case invalidMaxTokens
    case noAvailableEngine
    case noCompletion
    case engineFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidCount:
            return "Suggestion count must be greater than zero."
        case .invalidMaxTokens:
            return "Max tokens must be greater than zero."
        case .noAvailableEngine:
            return "No completion engine is available for the selected mode."
        case .noCompletion:
            return "No completion candidates were produced."
        case let .engineFailure(message):
            return message
        }
    }
}

struct TextContext: Sendable, Equatable {
    let textBefore: String
    let textAfter: String
    let appIdentifier: String?
    let language: String
    let lexiconStyleSnippet: String?

    init(
        textBefore: String,
        textAfter: String,
        appIdentifier: String? = nil,
        language: String,
        lexiconStyleSnippet: String? = nil
    ) {
        self.textBefore = textBefore
        self.textAfter = textAfter
        self.appIdentifier = appIdentifier
        self.language = language
        self.lexiconStyleSnippet = lexiconStyleSnippet
    }
}

// MARK: - Completion Type

enum CompletionType: Sendable, Hashable {
    /// Append text after cursor (default behavior)
    case continuation
    /// Replace N characters before cursor with new text
    case replacement
}

// MARK: - Completion

struct Completion: Sendable, Hashable {
    let text: String
    let confidence: Double
    let source: CompletionSource
    let type: CompletionType
    let replacementLength: Int

    init(
        text: String,
        confidence: Double,
        source: CompletionSource,
        type: CompletionType = .continuation,
        replacementLength: Int = 0
    ) {
        self.text = text
        self.confidence = confidence
        self.source = source
        self.type = type
        self.replacementLength = replacementLength
    }
}

enum CompletionSource: Sendable, Hashable {
    case local
    case cloud
    case userDictionary
    case hybrid
}
