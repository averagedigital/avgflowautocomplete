import Foundation

/// Tracks recently accepted completions for undo and analytics.
/// Stores the last N accepted items in UserDefaults for quick access.
actor AcceptanceHistoryStore {
    static let shared = AcceptanceHistoryStore()

    struct AcceptedItem: Codable, Identifiable, Sendable {
        let id: UUID
        let originalText: String   // text before cursor at acceptance time
        let acceptedText: String   // the completion text that was inserted
        let source: String         // "local", "cloud", "hybrid", "userDictionary"
        let confidence: Double
        let timestamp: Date
        let appIdentifier: String?
    }

    private let maxItems = 50
    private let key = "acceptance.history"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    func record(
        originalText: String,
        acceptedText: String,
        source: CompletionSource,
        confidence: Double,
        appIdentifier: String?
    ) {
        var list = loadHistory()
        let item = AcceptedItem(
            id: UUID(),
            originalText: String(originalText.suffix(200)),
            acceptedText: acceptedText,
            source: sourceString(source),
            confidence: confidence,
            timestamp: Date(),
            appIdentifier: appIdentifier
        )
        list.insert(item, at: 0)
        if list.count > maxItems {
            list = Array(list.prefix(maxItems))
        }
        saveHistory(list)
    }

    func lastAccepted() -> AcceptedItem? {
        loadHistory().first
    }

    func recentItems(limit: Int = 10) -> [AcceptedItem] {
        Array(loadHistory().prefix(limit))
    }

    func rollbackRate(windowHours: Int = 48) -> Double {
        // Placeholder: count manual edits within 5s of acceptance vs total
        // Actual implementation requires AX observer integration
        return 0.0
    }

    func acceptRate(windowHours: Int = 48) -> (accepted: Int, shown: Int) {
        let history = loadHistory()
        let cutoff = Date().addingTimeInterval(-Double(windowHours * 3600))
        let recent = history.filter { $0.timestamp > cutoff }
        return (accepted: recent.count, shown: max(recent.count, 1))
    }

    func clearHistory() {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Private

    private func loadHistory() -> [AcceptedItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AcceptedItem].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveHistory(_ list: [AcceptedItem]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }

    private func sourceString(_ source: CompletionSource) -> String {
        switch source {
        case .local: return "local"
        case .cloud: return "cloud"
        case .hybrid: return "hybrid"
        case .userDictionary: return "userDictionary"
        }
    }
}
