import Foundation

enum LocalModelError: LocalizedError {
    case runtimeUnavailable
    case modelNotLoaded
    case inferenceFailed(Error)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "Local inference runtime is unavailable. Build the bundled llama.cpp runtime or keep the external fallback available."
        case .modelNotLoaded:
            return "Local model is not loaded."
        case let .inferenceFailed(error):
            return "Local inference failed: \(error.localizedDescription)"
        }
    }
}

actor LocalModelManager: CompletionEngine {
    // MARK: - Properties

    private let bridge: LlamaBridge
    private(set) var isLoaded = false
    private(set) var memoryUsage = 0
    private(set) var loadedModelPath: String?
    private(set) var loadedContextSize = 0

    // MARK: - Init

    init(bridge: LlamaBridge = LlamaBridge()) {
        self.bridge = bridge
    }

    static var isAvailable: Bool {
        LlamaBridge.isAvailable
    }

    // MARK: - Lifecycle

    func loadModel(path: String, contextSize: Int) throws {
        guard Self.isAvailable else {
            throw LocalModelError.runtimeUnavailable
        }
        try bridge.loadModel(path: path, contextSize: contextSize)
        isLoaded = bridge.isLoaded
        memoryUsage = bridge.memoryUsage
        loadedModelPath = path
        loadedContextSize = contextSize
    }

    func unloadModel() {
        bridge.unloadModel()
        isLoaded = false
        memoryUsage = 0
        loadedModelPath = nil
        loadedContextSize = 0
    }

    // MARK: - CompletionEngine

    func complete(context: TextContext, maxTokens: Int, count: Int) async throws -> [Completion] {
        guard count > 0 else {
            throw CompletionEngineError.invalidCount
        }
        guard maxTokens > 0 else {
            throw CompletionEngineError.invalidMaxTokens
        }
        guard Self.isAvailable else {
            throw LocalModelError.runtimeUnavailable
        }
        guard isLoaded else {
            throw LocalModelError.modelNotLoaded
        }

        do {
            let modelContext = contextForLocalInference(context)
            let suggestions = try await bridge.generate(
                context: modelContext,
                maxTokens: maxTokens,
                count: count
            )

            memoryUsage = bridge.memoryUsage

            return suggestions.enumerated().map { index, text in
                Completion(
                    text: text,
                    confidence: max(0.35, 0.78 - (Double(index) * 0.12)),
                    source: .local
                )
            }
        } catch {
            throw LocalModelError.inferenceFailed(error)
        }
    }

    // MARK: - Private

    private func contextForLocalInference(_ context: TextContext) -> TextContext {
        let snippet = (context.lexiconStyleSnippet ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else {
            return context
        }

        let stylePrefix = "[STYLE]\n\(snippet)\n[/STYLE]\n"
        return TextContext(
            textBefore: stylePrefix + context.textBefore,
            textAfter: context.textAfter,
            appIdentifier: context.appIdentifier,
            language: context.language,
            lexiconStyleSnippet: context.lexiconStyleSnippet
        )
    }
}
