import Foundation

struct ContextHistoryEntry: Codable, Sendable {
    let textBeforeTail: String
    let textAfterHead: String
    let appIdentifier: String?
    let language: String
    let createdAt: Date
}

actor ContextHistory {
    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let maxEntries: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init

    init(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        storageKey: String = Constants.UserDefaultsKeys.contextHistoryEntries,
        maxEntries: Int = 200
    ) {
        self.userDefaults = appGroupManager.sharedUserDefaults() ?? .standard
        self.storageKey = storageKey
        self.maxEntries = maxEntries
    }

    // MARK: - Public

    func append(context: TextContext) async {
        let entry = ContextHistoryEntry(
            textBeforeTail: String(context.textBefore.suffix(Constants.Limits.contextBeforeCharacterLimit)),
            textAfterHead: String(context.textAfter.prefix(Constants.Limits.contextAfterCharacterLimit)),
            appIdentifier: context.appIdentifier,
            language: context.language,
            createdAt: Date()
        )

        var entries = loadEntries()
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        saveEntries(entries)
    }

    func recent(limit: Int) async -> [ContextHistoryEntry] {
        guard limit > 0 else {
            return []
        }
        return Array(loadEntries().prefix(limit))
    }

    func clear() async {
        userDefaults.removeObject(forKey: storageKey)
    }

    // MARK: - Private

    private func loadEntries() -> [ContextHistoryEntry] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }

        return (try? decoder.decode([ContextHistoryEntry].self, from: data)) ?? []
    }

    private func saveEntries(_ entries: [ContextHistoryEntry]) {
        guard let data = try? encoder.encode(entries) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}
