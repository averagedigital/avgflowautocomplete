import Foundation

actor PersonalizationManager {
    // MARK: - Properties

    private let userDictionary: UserDictionary
    private let contextHistory: ContextHistory
    private let memoryStore = UserMemoryStore()
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum InternalKeys {
        static let styleStats = "personalization.styleStats"
    }

    // MARK: - Init

    init(
        userDictionary: UserDictionary = UserDictionary(),
        contextHistory: ContextHistory = ContextHistory()
    ) {
        self.userDictionary = userDictionary
        self.contextHistory = contextHistory
        defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
    }

    // MARK: - Public

    func quickSuggestions(for context: TextContext, limit: Int) async -> [Completion] {
        await userDictionary.quickSuggestions(for: context, limit: limit)
    }

    func topPatterns(for context: TextContext, limit: Int = Constants.Limits.maxPromptPatterns) async -> [String] {
        guard limit > 0 else {
            return []
        }

        let languagePrefix = String(context.language.lowercased().prefix(2))
        let dictionaryPatterns = await userDictionary.topPatterns(for: context, limit: limit)
        if dictionaryPatterns.count >= limit {
            return Array(dictionaryPatterns.prefix(limit))
        }

        let historyEntries = await contextHistory.recent(limit: max(limit * 2, 10))
        let historyPatterns = historyEntries
            .filter { entry in
                entry.language.lowercased().hasPrefix(languagePrefix)
            }
            .map { entry in
                TextProcessor.contextPrefix(for: entry.textBeforeTail)
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let merged = stableUnique(dictionaryPatterns + historyPatterns)
        return Array(merged.prefix(limit))
    }

    func recordAcceptedCompletion(_ completion: Completion, context: TextContext) async {
        do {
            try await userDictionary.recordAcceptedCompletion(
                phrase: completion.text,
                contextPrefix: TextProcessor.contextPrefix(for: context.textBefore),
                sourceApp: context.appIdentifier
            )
        } catch {
            // Keep user personalization resilient even if one subsystem fails.
        }

        await contextHistory.append(context: context)
        await maybeCaptureMemory(completion: completion, context: context)
        updateGoodCompletions(completion: completion, context: context)
        updateStyleInsights(completion: completion, context: context)
    }

    func clearAll() async {
        do {
            try await userDictionary.clear()
        } catch {
            // Keep method non-throwing for settings flow simplicity.
        }
        await contextHistory.clear()
        await memoryStore.clear()
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.personalizationGoodCompletions)
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.personalizationStyleInsights)
        defaults.removeObject(forKey: InternalKeys.styleStats)
    }

    // MARK: - Private

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                continue
            }
            guard seen.insert(normalized.lowercased()).inserted else {
                continue
            }
            output.append(normalized)
        }

        return output
    }

    private func maybeCaptureMemory(completion: Completion, context: TextContext) async {
        let merged = "\(context.textBefore)\(completion.text)"
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard merged.count >= 20 else {
            return
        }

        let normalized = merged
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .prefix(12)
            .joined(separator: " ")

        guard !normalized.isEmpty else {
            return
        }

        let memory = context.language.lowercased().hasPrefix("ru")
            ? "Обычно пишу так: \(normalized)"
            : "I often write like this: \(normalized)"

        await memoryStore.add(memory)
    }

    private func updateGoodCompletions(completion: Completion, context: TextContext) {
        let before = TextProcessor.normalizedSnippet(context.textBefore, maxLength: 70)
        let after = TextProcessor.normalizedSnippet("\(context.textBefore)\(completion.text)", maxLength: 100)

        guard !before.isEmpty, !after.isEmpty else {
            return
        }

        let isRussian = context.language.lowercased().hasPrefix("ru")
        let example = isRussian
            ? "было: \(before) -> стало: \(after)"
            : "was: \(before) -> became: \(after)"

        var examples = loadStringList(forKey: Constants.UserDefaultsKeys.personalizationGoodCompletions)
        examples.removeAll { $0.caseInsensitiveCompare(example) == .orderedSame }
        examples.insert(example, at: 0)

        if examples.count > Constants.Limits.maxGoodCompletions {
            examples = Array(examples.prefix(Constants.Limits.maxGoodCompletions))
        }

        saveStringList(examples, forKey: Constants.UserDefaultsKeys.personalizationGoodCompletions)
    }

    private func updateStyleInsights(completion: Completion, context: TextContext) {
        var stats = loadStyleStats()
        stats.samples += 1

        let words = TextProcessor.wordCount(in: completion.text)
        stats.totalWords += words

        if words <= 6 {
            stats.shortCount += 1
        } else if words >= 14 {
            stats.longCount += 1
        }

        if completion.text.contains("!") {
            stats.exclamationCount += 1
        }
        if completion.text.contains("?") {
            stats.questionCount += 1
        }
        if completion.text.contains(where: { $0.isEmoji }) {
            stats.emojiCount += 1
        }

        if context.language.lowercased().hasPrefix("ru") {
            stats.russianCount += 1
        } else {
            stats.englishCount += 1
        }

        saveStyleStats(stats)
        saveStringList(buildInsights(from: stats), forKey: Constants.UserDefaultsKeys.personalizationStyleInsights)
    }

    private func buildInsights(from stats: StyleStats) -> [String] {
        guard stats.samples > 0 else {
            return []
        }

        let averageWords = Double(stats.totalWords) / Double(stats.samples)
        let lengthInsight: String
        switch averageWords {
        case ..<6:
            lengthInsight = "Prefers very short completions"
        case ..<11:
            lengthInsight = "Prefers concise completions"
        default:
            lengthInsight = "Often accepts longer completions"
        }

        let languageInsight: String
        if stats.russianCount > stats.englishCount {
            languageInsight = "Primary writing language: Russian"
        } else if stats.englishCount > stats.russianCount {
            languageInsight = "Primary writing language: English"
        } else {
            languageInsight = "Primary writing language: mixed Russian/English"
        }

        let punctuationInsight: String
        if stats.exclamationCount > stats.samples / 3 {
            punctuationInsight = "Style is expressive (frequent exclamation marks)"
        } else if stats.questionCount > stats.samples / 3 {
            punctuationInsight = "Style often uses questions"
        } else {
            punctuationInsight = "Style is mostly neutral punctuation"
        }

        let emojiInsight = stats.emojiCount > 0
            ? "Uses emoji occasionally"
            : "Rarely uses emoji"

        return [languageInsight, lengthInsight, punctuationInsight, emojiInsight]
    }

    private func loadStyleStats() -> StyleStats {
        guard let data = defaults.data(forKey: InternalKeys.styleStats),
              let decoded = try? decoder.decode(StyleStats.self, from: data) else {
            return StyleStats()
        }
        return decoded
    }

    private func saveStyleStats(_ stats: StyleStats) {
        guard let data = try? encoder.encode(stats) else {
            return
        }
        defaults.set(data, forKey: InternalKeys.styleStats)
    }

    private func loadStringList(forKey key: String) -> [String] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveStringList(_ list: [String], forKey key: String) {
        guard let data = try? encoder.encode(list) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

private struct StyleStats: Codable, Sendable {
    var samples = 0
    var totalWords = 0
    var shortCount = 0
    var longCount = 0
    var exclamationCount = 0
    var questionCount = 0
    var emojiCount = 0
    var russianCount = 0
    var englishCount = 0
}

private extension Character {
    var isEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }
}
