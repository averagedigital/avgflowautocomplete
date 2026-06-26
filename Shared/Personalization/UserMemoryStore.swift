import Foundation

struct UserMemoryEntry: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
}

actor UserMemoryStore {
    // MARK: - Properties

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxEntries: Int

    // MARK: - Init

    init(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        maxEntries: Int = 100
    ) {
        self.defaults = appGroupManager.sharedUserDefaults() ?? .standard
        self.maxEntries = maxEntries
    }

    // MARK: - Public

    func list() -> [UserMemoryEntry] {
        load()
    }

    func add(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        var entries = load()
        if entries.contains(where: { $0.text.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return
        }

        entries.insert(UserMemoryEntry(id: UUID(), text: normalized, createdAt: Date()), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save(entries)
    }

    func remove(id: UUID) {
        var entries = load()
        entries.removeAll { $0.id == id }
        save(entries)
    }

    func clear() {
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.personalizationUserMemories)
    }

    // MARK: - Private

    private func load() -> [UserMemoryEntry] {
        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.personalizationUserMemories) else {
            return []
        }
        return (try? decoder.decode([UserMemoryEntry].self, from: data)) ?? []
    }

    private func save(_ entries: [UserMemoryEntry]) {
        guard let data = try? encoder.encode(entries) else {
            return
        }
        defaults.set(data, forKey: Constants.UserDefaultsKeys.personalizationUserMemories)
    }
}
