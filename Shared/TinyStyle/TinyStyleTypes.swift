import Foundation

struct TinyStyleExample: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let contextTokens: [String]
    let completionTokens: [String]
    let language: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        contextTokens: [String],
        completionTokens: [String],
        language: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.contextTokens = contextTokens
        self.completionTokens = completionTokens
        self.language = language
        self.createdAt = createdAt
    }
}

struct TinyStyleEvent: Codable, Sendable {
    let context: String
    let completion: String
    let language: String
    let createdAt: Date
}

struct TinyStyleTrainingMetrics: Sendable, Equatable {
    let step: Int
    let lossBefore: Double
    let lossAfter: Double
    let batchSize: Int
}
