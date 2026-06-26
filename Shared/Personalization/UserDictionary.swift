import CoreData
import Foundation

actor UserDictionary: UserDictionaryProviding {
    // MARK: - Constants

    private enum Entity {
        static let userPhrase = "UserPhrase"

        static let id = "id"
        static let phrase = "phrase"
        static let contextPrefix = "contextPrefix"
        static let frequency = "frequency"
        static let lastUsed = "lastUsed"
        static let source = "source"
    }

    // MARK: - Properties

    private let context: NSManagedObjectContext
    private let userDefaults: UserDefaults
    private let maxEntries: Int
    private let decayFactor: Double
    private let decayInterval: TimeInterval

    // MARK: - Init

    init(
        coreDataStack: CoreDataStack = .shared,
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        maxEntries: Int = 10_000,
        decayFactor: Double = 0.95,
        decayInterval: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.context = coreDataStack.makeBackgroundContext()
        self.userDefaults = appGroupManager.sharedUserDefaults() ?? .standard
        self.maxEntries = maxEntries
        self.decayFactor = decayFactor
        self.decayInterval = decayInterval
    }

    // MARK: - Queries

    func quickSuggestions(for context: TextContext, limit: Int) async -> [Completion] {
        guard limit > 0 else {
            return []
        }

        do {
            try await applyWeeklyDecayIfNeeded()

            let prefix = TextProcessor.contextPrefix(for: context.textBefore)
            let exactMatches = try await fetchPhrases(
                matchingPrefix: prefix,
                exactMatch: true,
                limit: max(limit, Constants.Limits.maxPromptPatterns)
            )

            let fallbackMatches: [UserPhraseRecord]
            if exactMatches.isEmpty {
                let relaxedPrefix = String(prefix.suffix(20))
                fallbackMatches = try await fetchPhrases(
                    matchingPrefix: relaxedPrefix,
                    exactMatch: false,
                    limit: max(limit, Constants.Limits.maxPromptPatterns)
                )
            } else {
                fallbackMatches = []
            }

            let records = exactMatches + fallbackMatches
            let uniqueRecords = stableUnique(records) { "\($0.phrase.lowercased())::\($0.contextPrefix.lowercased())" }

            return Array(uniqueRecords.prefix(limit)).map { record in
                Completion(
                    text: record.phrase,
                    confidence: confidence(for: record.frequency),
                    source: .userDictionary
                )
            }
        } catch {
            return []
        }
    }

    func topPatterns(for context: TextContext, limit: Int) async -> [String] {
        let suggestions = await quickSuggestions(for: context, limit: limit)
        return suggestions.map(\.text)
    }

    // MARK: - Mutations

    func recordAcceptedCompletion(
        phrase: String,
        contextPrefix: String,
        sourceApp: String?
    ) async throws {
        let normalizedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrefix = contextPrefix.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedPhrase.isEmpty, !normalizedPrefix.isEmpty else {
            return
        }

        try await applyWeeklyDecayIfNeeded()

        try await performOnContext { [self] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.userPhrase)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %@", Entity.phrase, normalizedPhrase),
                NSPredicate(format: "%K == %@", Entity.contextPrefix, normalizedPrefix),
                sourcePredicate(sourceApp: sourceApp)
            ])

            let currentDate = Date()
            if let existing = try context.fetch(request).first {
                let frequency = existing.value(forKey: Entity.frequency) as? Int32 ?? 0
                existing.setValue(frequency + 1, forKey: Entity.frequency)
                existing.setValue(currentDate, forKey: Entity.lastUsed)
            } else {
                let object = NSEntityDescription.insertNewObject(forEntityName: Entity.userPhrase, into: context)
                object.setValue(UUID(), forKey: Entity.id)
                object.setValue(normalizedPhrase, forKey: Entity.phrase)
                object.setValue(normalizedPrefix, forKey: Entity.contextPrefix)
                object.setValue(Int32(1), forKey: Entity.frequency)
                object.setValue(currentDate, forKey: Entity.lastUsed)
                object.setValue(sourceApp, forKey: Entity.source)
            }

            if context.hasChanges {
                try context.save()
            }
        }

        try await enforceEntryLimitIfNeeded()
    }

    func clear() async throws {
        try await performOnContext { [self] in
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: Entity.userPhrase)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)

            if context.hasChanges {
                try context.save()
            }
        }
    }

    // MARK: - Private

    private func fetchPhrases(
        matchingPrefix: String,
        exactMatch: Bool,
        limit: Int
    ) async throws -> [UserPhraseRecord] {
        try await performOnContext { [self] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.userPhrase)
            request.fetchLimit = max(1, limit)
            request.sortDescriptors = [
                NSSortDescriptor(key: Entity.frequency, ascending: false),
                NSSortDescriptor(key: Entity.lastUsed, ascending: false)
            ]

            if exactMatch {
                request.predicate = NSPredicate(format: "%K == %@", Entity.contextPrefix, matchingPrefix)
            } else {
                request.predicate = NSPredicate(format: "%K BEGINSWITH[cd] %@", Entity.contextPrefix, matchingPrefix)
            }

            let objects = try context.fetch(request)
            return objects.compactMap(UserPhraseRecord.init(object:))
        }
    }

    private func applyWeeklyDecayIfNeeded() async throws {
        let now = Date()
        if let lastDecayDate = userDefaults.object(forKey: Constants.UserDefaultsKeys.userDictionaryLastDecayDate) as? Date,
           now.timeIntervalSince(lastDecayDate) < decayInterval {
            return
        }

        try await performOnContext { [self] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.userPhrase)
            let objects = try context.fetch(request)

            for object in objects {
                let current = object.value(forKey: Entity.frequency) as? Int32 ?? 1
                let decayedValue = Int32(max(1, floor(Double(current) * decayFactor)))
                object.setValue(decayedValue, forKey: Entity.frequency)
            }

            if context.hasChanges {
                try context.save()
            }
        }

        userDefaults.set(now, forKey: Constants.UserDefaultsKeys.userDictionaryLastDecayDate)
    }

    private func enforceEntryLimitIfNeeded() async throws {
        let currentCount: Int = try await performOnContext { [self] in
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: Entity.userPhrase)
            return try context.count(for: request)
        }

        guard currentCount > maxEntries else {
            return
        }

        let overflow = currentCount - maxEntries

        try await performOnContext { [self] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.userPhrase)
            request.fetchLimit = overflow
            request.sortDescriptors = [
                NSSortDescriptor(key: Entity.lastUsed, ascending: true)
            ]

            let oldest = try context.fetch(request)
            oldest.forEach(context.delete)

            if context.hasChanges {
                try context.save()
            }
        }
    }

    private func confidence(for frequency: Int32) -> Double {
        let base = 0.45
        let boost = min(0.5, log(Double(max(1, frequency))) / 6.0)
        return min(0.98, base + boost)
    }

    private func sourcePredicate(sourceApp: String?) -> NSPredicate {
        guard let sourceApp, !sourceApp.isEmpty else {
            return NSPredicate(format: "%K == nil", Entity.source)
        }
        return NSPredicate(format: "%K == %@", Entity.source, sourceApp)
    }

    private func performOnContext<T>(
        _ block: @escaping () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    continuation.resume(returning: try block())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stableUnique<T, Key: Hashable>(
        _ values: [T],
        key: (T) -> Key
    ) -> [T] {
        var seen = Set<Key>()
        var output: [T] = []

        for value in values {
            if seen.insert(key(value)).inserted {
                output.append(value)
            }
        }

        return output
    }
}

private struct UserPhraseRecord {
    let phrase: String
    let contextPrefix: String
    let frequency: Int32

    init?(object: NSManagedObject) {
        guard
            let phrase = object.value(forKey: "phrase") as? String,
            let contextPrefix = object.value(forKey: "contextPrefix") as? String
        else {
            return nil
        }

        self.phrase = phrase
        self.contextPrefix = contextPrefix
        self.frequency = object.value(forKey: "frequency") as? Int32 ?? 1
    }
}
