import Foundation

enum CompletionMode: String, Sendable {
    case localOnly
    case cloudOnly
    case hybrid
}

struct HybridCompletionConfiguration: Sendable {
    var mode: CompletionMode
    var cloudAllowed: Bool
    var debounceMilliseconds: UInt64
    var cloudReplacementLengthDelta: Int

    static let `default` = HybridCompletionConfiguration(
        mode: .hybrid,
        cloudAllowed: true,
        debounceMilliseconds: 0,
        cloudReplacementLengthDelta: 6
    )
}

protocol UserDictionaryProviding: Sendable {
    func quickSuggestions(for context: TextContext, limit: Int) async -> [Completion]
}

actor HybridCompletionService: CompletionEngine {
    // MARK: - Properties

    private let localEngine: LocalModelManager?
    private let cloudEngine: CloudAPIManager?
    private let userDictionary: UserDictionaryProviding?
    private var configuration: HybridCompletionConfiguration

    // MARK: - Init

    init(
        localEngine: LocalModelManager? = nil,
        cloudEngine: CloudAPIManager? = nil,
        userDictionary: UserDictionaryProviding? = nil,
        configuration: HybridCompletionConfiguration = .default
    ) {
        self.localEngine = localEngine
        self.cloudEngine = cloudEngine
        self.userDictionary = userDictionary
        self.configuration = configuration
    }

    // MARK: - Configuration

    func updateConfiguration(_ configuration: HybridCompletionConfiguration) {
        self.configuration = configuration
    }

    // MARK: - CompletionEngine

    func complete(context: TextContext, maxTokens: Int, count: Int) async throws -> [Completion] {
        guard count > 0 else {
            throw CompletionEngineError.invalidCount
        }
        guard maxTokens > 0 else {
            throw CompletionEngineError.invalidMaxTokens
        }

        if configuration.debounceMilliseconds > 0 {
            try await Task.sleep(nanoseconds: configuration.debounceMilliseconds * 1_000_000)
            try Task.checkCancellation()
        }

        let dictionarySuggestions = await userDictionary?.quickSuggestions(for: context, limit: count) ?? []
        if dictionarySuggestions.count >= count {
            return Array(dictionarySuggestions.prefix(count))
        }

        let engineSuggestions = try await gatherEngineSuggestions(
            context: context,
            maxTokens: maxTokens,
            count: count
        )

        let merged = mergeSuggestions(
            dictionarySuggestions: dictionarySuggestions,
            engineSuggestions: engineSuggestions,
            limit: count
        )

        guard !merged.isEmpty else {
            throw CompletionEngineError.noCompletion
        }
        return merged
    }

    // MARK: - Private

    private func gatherEngineSuggestions(
        context: TextContext,
        maxTokens: Int,
        count: Int
    ) async throws -> [Completion] {
        let shouldUseLocal = configuration.mode != .cloudOnly && localEngine != nil
        let shouldUseCloud = configuration.mode != .localOnly && configuration.cloudAllowed && cloudEngine != nil

        guard shouldUseLocal || shouldUseCloud else {
            throw CompletionEngineError.noAvailableEngine
        }

        if shouldUseLocal, shouldUseCloud, configuration.mode == .hybrid,
           let localEngine, let cloudEngine {
            return try await firstSuccessfulEngineResult(
                context: context,
                maxTokens: maxTokens,
                count: count,
                localEngine: localEngine,
                cloudEngine: cloudEngine
            )
        }

        if shouldUseCloud, let cloudEngine {
            do {
                return Array(try await cloudEngine.complete(context: context, maxTokens: maxTokens, count: count).prefix(count))
            } catch {
                if shouldUseLocal, let localEngine {
                    return Array(try await localEngine.complete(context: context, maxTokens: maxTokens, count: count).prefix(count))
                }
                throw CompletionEngineError.engineFailure(error.localizedDescription)
            }
        }

        if shouldUseLocal, let localEngine {
            do {
                return Array(try await localEngine.complete(context: context, maxTokens: maxTokens, count: count).prefix(count))
            } catch {
                if shouldUseCloud, let cloudEngine {
                    return Array(try await cloudEngine.complete(context: context, maxTokens: maxTokens, count: count).prefix(count))
                }
                throw CompletionEngineError.engineFailure(error.localizedDescription)
            }
        }

        throw CompletionEngineError.noCompletion
    }

    private func firstSuccessfulEngineResult(
        context: TextContext,
        maxTokens: Int,
        count: Int,
        localEngine: LocalModelManager,
        cloudEngine: CloudAPIManager
    ) async throws -> [Completion] {
        var localFailureMessage: String?
        var cloudFailureMessage: String?
        var firstResult: [Completion] = []

        await withTaskGroup(of: (CompletionSource, [Completion]?, String?).self) { group in
            group.addTask {
                do {
                    return (.local, try await localEngine.complete(context: context, maxTokens: maxTokens, count: count), nil)
                } catch {
                    return (.local, nil, error.localizedDescription)
                }
            }

            group.addTask {
                do {
                    return (.cloud, try await cloudEngine.complete(context: context, maxTokens: maxTokens, count: count), nil)
                } catch {
                    return (.cloud, nil, error.localizedDescription)
                }
            }

            for await (source, result, failureMessage) in group {
                if let result, !result.isEmpty {
                    firstResult = Array(result.prefix(count)).map { completion in
                        if completion.source == .local || completion.source == .cloud {
                            return Completion(
                                text: completion.text,
                                confidence: completion.confidence,
                                source: .hybrid,
                                type: completion.type,
                                replacementLength: completion.replacementLength
                            )
                        }
                        return completion
                    }
                    group.cancelAll()
                    break
                }

                if let failureMessage, !failureMessage.isEmpty {
                    switch source {
                    case .local:
                        localFailureMessage = failureMessage
                    case .cloud:
                        cloudFailureMessage = failureMessage
                    default:
                        break
                    }
                }
            }
        }

        if !firstResult.isEmpty {
            return firstResult
        }

        if let cloudFailureMessage, !cloudFailureMessage.isEmpty {
            throw CompletionEngineError.engineFailure(cloudFailureMessage)
        }
        if let localFailureMessage, !localFailureMessage.isEmpty {
            throw CompletionEngineError.engineFailure(localFailureMessage)
        }
        throw CompletionEngineError.noCompletion
    }

    private func mergeSuggestions(
        dictionarySuggestions: [Completion],
        engineSuggestions: [Completion],
        limit: Int
    ) -> [Completion] {
        blendPrimarySecondary(
            primary: dictionarySuggestions,
            secondary: engineSuggestions,
            limit: limit
        )
    }

    private func blendPrimarySecondary(
        primary: [Completion],
        secondary: [Completion],
        limit: Int
    ) -> [Completion] {
        let merged = primary + secondary
        let unique = stableUnique(merged) { completion in
            completion.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        if primary.isEmpty {
            return Array(unique.prefix(limit))
        }

        return Array(unique.prefix(max(1, limit))).map { completion in
            if completion.source == .local || completion.source == .cloud {
                return Completion(
                    text: completion.text,
                    confidence: completion.confidence,
                    source: .hybrid,
                    type: completion.type,
                    replacementLength: completion.replacementLength
                )
            }
            return completion
        }
    }

    private func stableUnique<T, K: Hashable>(
        _ values: [T],
        key: (T) -> K
    ) -> [T] {
        var seen = Set<K>()
        var result: [T] = []

        for value in values {
            if seen.insert(key(value)).inserted {
                result.append(value)
            }
        }

        return result
    }
}
