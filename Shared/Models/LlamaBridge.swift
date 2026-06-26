import Foundation

final class LlamaBridge: @unchecked Sendable {
    private enum BackendKind {
        case inProcess
        case externalCLI
    }

    private let inProcessRuntime = InProcessLlamaRuntime()
    private let externalCLIRuntime = ExternalLlamaCLIRuntime()

    private(set) var isLoaded = false
    private(set) var memoryUsage: Int = 0
    private var activeBackendKind: BackendKind?

    static var isAvailable: Bool {
        InProcessLlamaRuntime.isAvailable || ExternalLlamaCLIRuntime.isAvailable
    }

    func loadModel(path: String, contextSize: Int) throws {
        var attemptedErrors: [String] = []

        if InProcessLlamaRuntime.isAvailable {
            do {
                try inProcessRuntime.loadModel(path: path, contextSize: contextSize)
                activeBackendKind = .inProcess
                syncStateFromActiveBackend()
                return
            } catch {
                attemptedErrors.append("in-process: \(error.localizedDescription)")
                inProcessRuntime.unloadModel()
            }
        }

        if ExternalLlamaCLIRuntime.isAvailable {
            do {
                try externalCLIRuntime.loadModel(path: path, contextSize: contextSize)
                activeBackendKind = .externalCLI
                syncStateFromActiveBackend()
                return
            } catch {
                attemptedErrors.append("cli: \(error.localizedDescription)")
                externalCLIRuntime.unloadModel()
            }
        }

        isLoaded = false
        memoryUsage = 0
        activeBackendKind = nil

        if attemptedErrors.isEmpty {
            throw LlamaBridgeError.runtimeUnavailable
        }
        throw LlamaBridgeError.processFailed(attemptedErrors.joined(separator: " | "))
    }

    func unloadModel() {
        inProcessRuntime.unloadModel()
        externalCLIRuntime.unloadModel()
        activeBackendKind = nil
        isLoaded = false
        memoryUsage = 0
    }

    func generate(context: TextContext, maxTokens: Int, count: Int) async throws -> [String] {
        guard isLoaded else {
            throw LlamaBridgeError.modelNotLoaded
        }

        let prompt = buildPrompt(context: context)
        let backend = try currentBackend()
        let boundedCount = activeBackendKind == .externalCLI ? 1 : max(1, min(count, 3))

        var suggestions: [String] = []
        for index in 0..<boundedCount {
            try Task.checkCancellation()
            let seed = Int(Date().timeIntervalSince1970 * 1000) + (index * 7919)
            let rawOutput = try await backend.generate(prompt: prompt, maxTokens: maxTokens, seed: seed)
            let normalized = normalizeCompletion(rawOutput, prompt: prompt, textBefore: context.textBefore)
            if !normalized.isEmpty {
                suggestions.append(normalized)
            }
        }

        syncStateFromActiveBackend()

        let unique = stableUnique(suggestions)
        guard !unique.isEmpty else {
            throw LlamaBridgeError.invalidOutput
        }
        return unique
    }

    private func currentBackend() throws -> any LlamaRuntimeBackend {
        switch activeBackendKind {
        case .inProcess:
            return inProcessRuntime
        case .externalCLI:
            return externalCLIRuntime
        case .none:
            throw LlamaBridgeError.modelNotLoaded
        }
    }

    private func syncStateFromActiveBackend() {
        switch activeBackendKind {
        case .inProcess:
            isLoaded = inProcessRuntime.isLoaded
            memoryUsage = inProcessRuntime.memoryUsage
        case .externalCLI:
            isLoaded = externalCLIRuntime.isLoaded
            memoryUsage = externalCLIRuntime.memoryUsage
        case .none:
            isLoaded = false
            memoryUsage = 0
        }
    }

    private func buildPrompt(context: TextContext) -> String {
        var parts = ["""
        Continue the user's text in the same language and style.
        Return only continuation text.
        ---
        \(context.textBefore)
        """]

        if let appInstructions = AppOverridesStore.shared.customInstructions(for: context.appIdentifier) {
            parts.append("""
            ---
            Additional app-specific instructions:
            \(appInstructions)
            """)
        }

        return parts.joined(separator: "\n")
    }

    private func normalizeCompletion(_ raw: String, prompt: String, textBefore: String) -> String {
        let cleaned = stripANSI(raw)
        let withoutPrompt: String
        if cleaned.hasPrefix(prompt) {
            withoutPrompt = String(cleaned.dropFirst(prompt.count))
        } else {
            withoutPrompt = cleaned
        }

        let compact = withoutPrompt
            .components(separatedBy: .newlines)
            .filter { line in
                let lower = line.lowercased()
                return !lower.contains("llama_print_timings")
                    && !lower.hasPrefix("main:")
                    && !lower.hasPrefix("build:")
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return TextProcessor.continuationSuffix(from: compact, after: textBefore)
    }

    private func stripANSI(_ value: String) -> String {
        let pattern = #"\u{001B}\[[0-9;]*[A-Za-z]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: "")
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }
}

enum LlamaBridgeError: LocalizedError {
    case runtimeUnavailable
    case modelNotLoaded
    case modelFileMissing(String)
    case processFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "Local inference runtime is unavailable. Build the bundled llama.cpp runtime or keep llama-cli fallback available."
        case .modelNotLoaded:
            return "Local model is not loaded."
        case let .modelFileMissing(path):
            return "Model file not found: \(path)"
        case let .processFailed(reason):
            return "Local inference backend failed: \(reason)"
        case .invalidOutput:
            return "Local model returned empty output."
        }
    }
}
