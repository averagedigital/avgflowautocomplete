import Foundation

enum CloudProvider: String, Sendable, Codable {
    case openAI
    case anthropic
    case xAI
    case openRouter
}

struct CloudConfiguration: Sendable {
    var provider: CloudProvider
    var modelIdentifier: String
    var apiKey: String?
    var networkEnabled: Bool
    var timeout: TimeInterval
    var userStylePrompt: String?
    var userPatterns: [String] = []
    var userMemories: [String] = []
    var styleInsights: [String] = []
    var goodCompletions: [String] = []
    var lexiconStyleSnippet: String?

    static let `default` = CloudConfiguration(
        provider: .openAI,
        modelIdentifier: "gpt-4.1-nano",
        apiKey: nil,
        networkEnabled: true,
        timeout: 20,
        userStylePrompt: nil,
        userPatterns: [],
        userMemories: [],
        styleInsights: [],
        goodCompletions: [],
        lexiconStyleSnippet: nil
    )
}

enum CloudAPIError: LocalizedError {
    case networkDisabled
    case missingAPIKey
    case invalidResponse
    case failedStatusCode(Int)
    case circuitOpen(TimeInterval)
    case invalidURL
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .networkDisabled:
            return "Cloud completions are disabled."
        case .missingAPIKey:
            return "Cloud API key is missing."
        case .invalidResponse:
            return "Cloud API returned an invalid response."
        case let .failedStatusCode(statusCode):
            return "Cloud API failed with status \(statusCode)."
        case let .circuitOpen(seconds):
            return "Cloud requests are temporarily paused (\(Int(seconds))s) after repeated failures."
        case .invalidURL:
            return "Cloud API URL is invalid."
        case let .streamError(message):
            return "Cloud streaming failed: \(message)"
        }
    }
}

actor CloudAPIManager: CompletionEngine {
    // MARK: - Properties

    private let session: URLSession
    private var configuration: CloudConfiguration
    private var consecutiveFailures = 0
    private var circuitOpenUntil: Date?
    private var lastRequestAt: Date?

    private let maxRetries = 2
    private let baseBackoffNanoseconds: UInt64 = 300_000_000
    private let circuitBreakerThreshold = 5
    private let circuitOpenSeconds: TimeInterval = 20
    private let minRequestInterval: TimeInterval = 0.25

    // MARK: - Init

    init(
        configuration: CloudConfiguration = .default,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: - Configuration

    func updateConfiguration(_ configuration: CloudConfiguration) {
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
        guard configuration.networkEnabled else {
            throw CloudAPIError.networkDisabled
        }
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw CloudAPIError.missingAPIKey
        }

        let defaults = UserDefaults(suiteName: Constants.AppGroup.suiteName)
        let replacementEnabled = defaults?.bool(forKey: Constants.UserDefaultsKeys.replacementModeEnabled) ?? false

        let prompt = PromptBuilder.buildPrompt(
            context: context,
            suggestionCount: count,
            userPatterns: configuration.userPatterns,
            userMemories: configuration.userMemories,
            styleInsights: configuration.styleInsights,
            goodCompletions: configuration.goodCompletions,
            lexiconStyleSnippet: configuration.lexiconStyleSnippet ?? context.lexiconStyleSnippet,
            replacementMode: replacementEnabled
        )

        let sysPrompt = buildSystemPrompt(context: context, suggestionCount: count)

        let rawResponse: String
        switch configuration.provider {
        case .openAI:
            rawResponse = try await requestOpenAICompletion(
                prompt: prompt,
                systemPrompt: sysPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        case .anthropic:
            rawResponse = try await requestAnthropicCompletion(
                prompt: prompt,
                systemPrompt: sysPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        case .xAI:
            rawResponse = try await requestXAICompletion(
                prompt: prompt,
                systemPrompt: sysPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        case .openRouter:
            rawResponse = try await requestOpenRouterCompletion(
                prompt: prompt,
                systemPrompt: sysPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        }

        let completions = parseSuggestions(rawResponse, count: count)
        guard !completions.isEmpty else {
            throw CompletionEngineError.noCompletion
        }

        return completions
    }

    func completeStreaming(
        context: TextContext,
        maxTokens: Int,
        count: Int,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> [Completion] {
        guard count > 0 else {
            throw CompletionEngineError.invalidCount
        }
        guard maxTokens > 0 else {
            throw CompletionEngineError.invalidMaxTokens
        }
        guard configuration.networkEnabled else {
            throw CloudAPIError.networkDisabled
        }
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw CloudAPIError.missingAPIKey
        }

        let defaults = UserDefaults(suiteName: Constants.AppGroup.suiteName)
        let replacementEnabled = defaults?.bool(forKey: Constants.UserDefaultsKeys.replacementModeEnabled) ?? false

        let prompt = PromptBuilder.buildPrompt(
            context: context,
            suggestionCount: count,
            userPatterns: configuration.userPatterns,
            userMemories: configuration.userMemories,
            styleInsights: configuration.styleInsights,
            goodCompletions: configuration.goodCompletions,
            lexiconStyleSnippet: configuration.lexiconStyleSnippet ?? context.lexiconStyleSnippet,
            replacementMode: replacementEnabled
        )
        let sysPrompt = buildSystemPrompt(context: context, suggestionCount: count)

        let rawResponse: String
        switch configuration.provider {
        case .openAI:
            rawResponse = try await requestOpenAICompletion(
                prompt: prompt,
                systemPrompt: sysPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey,
                onToken: onToken
            )
        case .openRouter:
            rawResponse = try await requestOpenRouterCompletion(
                prompt: prompt,
                systemPrompt: sysPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey,
                onToken: onToken
            )
        case .anthropic:
            rawResponse = try await requestAnthropicCompletion(
                prompt: prompt,
                systemPrompt: sysPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        case .xAI:
            rawResponse = try await requestXAICompletion(
                prompt: prompt,
                systemPrompt: sysPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        }

        let completions = parseSuggestions(rawResponse, count: count)
        guard !completions.isEmpty else {
            throw CompletionEngineError.noCompletion
        }
        return completions
    }

    /// Rewrite user-selected text according to a free-form user instruction.
    /// Returns only replacement text for the selected segment.
    func rewriteSelectedText(
        selectedText: String,
        userInstruction: String,
        maxTokens: Int
    ) async throws -> String {
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInstruction = userInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSelection.isEmpty else {
            throw CompletionEngineError.noCompletion
        }
        guard !normalizedInstruction.isEmpty else {
            throw CompletionEngineError.engineFailure("Rewrite prompt is empty.")
        }
        guard maxTokens > 0 else {
            throw CompletionEngineError.invalidMaxTokens
        }
        guard configuration.networkEnabled else {
            throw CloudAPIError.networkDisabled
        }
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw CloudAPIError.missingAPIKey
        }

        let prompt = buildSelectionRewritePrompt(
            selectedText: selectedText,
            userInstruction: normalizedInstruction
        )
        let systemPrompt = buildSelectionRewriteSystemPrompt()

        let rawResponse: String
        switch configuration.provider {
        case .openAI:
            rawResponse = try await requestOpenAICompletion(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        case .anthropic:
            rawResponse = try await requestAnthropicCompletion(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        case .xAI:
            rawResponse = try await requestXAICompletion(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        case .openRouter:
            rawResponse = try await requestOpenRouterCompletion(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                apiKey: apiKey
            )
        }

        let normalized = normalizeSelectedTextRewriteOutput(rawResponse)
        guard !normalized.isEmpty else {
            throw CompletionEngineError.noCompletion
        }
        return normalized
    }

    // MARK: - OpenAI

    private func requestOpenAICompletion(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        apiKey: String,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw CloudAPIError.invalidURL
        }

        let body = OpenAIRequest(
            model: configuration.modelIdentifier,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2,
            max_tokens: maxTokens,
            stream: true
        )

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let streamedText = try await performStreamingRequest(request, onToken: onToken)
            if !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return streamedText
            }
        } catch let error as CloudAPIError {
            switch error {
            case .invalidResponse, .streamError:
                break
            default:
                throw error
            }
        }

        // Fallback to non-streaming response if SSE was not delivered.
        let fallbackBody = OpenAIRequest(
            model: configuration.modelIdentifier,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2,
            max_tokens: maxTokens,
            stream: false
        )
        var fallbackRequest = URLRequest(url: url, timeoutInterval: configuration.timeout)
        fallbackRequest.httpMethod = "POST"
        fallbackRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        fallbackRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        fallbackRequest.httpBody = try JSONEncoder().encode(fallbackBody)

        let data = try await performRequest(fallbackRequest)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw CloudAPIError.invalidResponse
        }
        return content
    }

    // MARK: - Anthropic

    private func requestAnthropicCompletion(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw CloudAPIError.invalidURL
        }

        let body = AnthropicRequest(
            model: configuration.modelIdentifier,
            max_tokens: maxTokens,
            temperature: 0.2,
            system: systemPrompt,
            messages: [
                .init(role: "user", content: [.init(type: "text", text: prompt)])
            ]
        )

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await performRequest(request)
        let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        let text = response.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")

        guard !text.isEmpty else {
            throw CloudAPIError.invalidResponse
        }

        return text
    }

    // MARK: - xAI

    private func requestXAICompletion(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
            throw CloudAPIError.invalidURL
        }

        let body = OpenAIRequest(
            model: configuration.modelIdentifier,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2,
            max_tokens: maxTokens,
            stream: false
        )

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await performRequest(request)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw CloudAPIError.invalidResponse
        }
        return content
    }

    // MARK: - OpenRouter

    private func requestOpenRouterCompletion(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        apiKey: String,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw CloudAPIError.invalidURL
        }

        let body = OpenAIRequest(
            model: configuration.modelIdentifier,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2,
            max_tokens: maxTokens,
            stream: true
        )

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("https://aicomplete.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("AIComplete", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let streamedText = try await performStreamingRequest(request, onToken: onToken)
            if !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return streamedText
            }
        } catch let error as CloudAPIError {
            switch error {
            case .invalidResponse, .streamError:
                break
            default:
                throw error
            }
        }

        // Fallback to non-streaming response if SSE was not delivered.
        let fallbackBody = OpenAIRequest(
            model: configuration.modelIdentifier,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2,
            max_tokens: maxTokens,
            stream: false
        )
        var fallbackRequest = URLRequest(url: url, timeoutInterval: configuration.timeout)
        fallbackRequest.httpMethod = "POST"
        fallbackRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        fallbackRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        fallbackRequest.setValue("https://aicomplete.app", forHTTPHeaderField: "HTTP-Referer")
        fallbackRequest.setValue("AIComplete", forHTTPHeaderField: "X-Title")
        fallbackRequest.httpBody = try JSONEncoder().encode(fallbackBody)

        let data = try await performRequest(fallbackRequest)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw CloudAPIError.invalidResponse
        }
        return content
    }

    // MARK: - Shared Helpers

    private func performStreamingRequest(
        _ request: URLRequest,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        if let circuitOpenUntil, circuitOpenUntil > Date() {
            throw CloudAPIError.circuitOpen(circuitOpenUntil.timeIntervalSinceNow)
        }

        if let lastRequestAt {
            let delta = Date().timeIntervalSince(lastRequestAt)
            if delta < minRequestInterval {
                let wait = UInt64((minRequestInterval - delta) * 1_000_000_000)
                try await Task.sleep(nanoseconds: wait)
            }
        }
        lastRequestAt = Date()

        var lastError: Error = CloudAPIError.invalidResponse

        for attempt in 0...maxRetries {
            do {
                let (bytes, response) = try await session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = CloudAPIError.invalidResponse
                    recordFailure()
                    throw CloudAPIError.invalidResponse
                }

                if (200...299).contains(httpResponse.statusCode) {
                    let streamedText = try await collectStreamText(from: bytes, onToken: onToken)
                    guard !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        lastError = CloudAPIError.invalidResponse
                        throw CloudAPIError.invalidResponse
                    }
                    resetFailureState()
                    return streamedText
                }

                let statusError = CloudAPIError.failedStatusCode(httpResponse.statusCode)
                lastError = statusError
                let shouldRetry = attempt < maxRetries && isTransientHTTPStatus(httpResponse.statusCode)
                if shouldRetry {
                    try await sleepBackoff(attempt: attempt)
                    continue
                }
                recordFailure()
                throw statusError
            } catch {
                lastError = error
                // Never count cancellation as a failure
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
                if attempt < maxRetries, isTransientNetworkError(error) {
                    try await sleepBackoff(attempt: attempt)
                    continue
                }
                if error is CloudAPIError {
                    throw error
                }
                recordFailure()
                throw error
            }
        }

        throw lastError
    }

    private func collectStreamText(
        from bytes: URLSession.AsyncBytes,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        var assembled = ""

        for try await rawLine in bytes.lines {
            if Task.isCancelled {
                throw CancellationError()
            }

            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // OpenRouter may send keepalive comments such as ': OPENROUTER PROCESSING'.
            if line.hasPrefix(":") {
                continue
            }

            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty else { continue }

            if payload == "[DONE]" {
                break
            }

            guard let payloadData = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: payloadData) else {
                continue
            }

            if let errorMessage = chunk.error?.message, !errorMessage.isEmpty {
                throw CloudAPIError.streamError(errorMessage)
            }

            let deltaText = chunk.choices
                .compactMap(\.delta.content)
                .joined()
            if !deltaText.isEmpty {
                assembled += deltaText
                onToken?(deltaText)
            }
        }

        return assembled
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        if let circuitOpenUntil, circuitOpenUntil > Date() {
            throw CloudAPIError.circuitOpen(circuitOpenUntil.timeIntervalSinceNow)
        }

        if let lastRequestAt {
            let delta = Date().timeIntervalSince(lastRequestAt)
            if delta < minRequestInterval {
                let wait = UInt64((minRequestInterval - delta) * 1_000_000_000)
                try await Task.sleep(nanoseconds: wait)
            }
        }
        lastRequestAt = Date()

        var lastError: Error = CloudAPIError.invalidResponse

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = CloudAPIError.invalidResponse
                    recordFailure()
                    throw CloudAPIError.invalidResponse
                }

                if (200...299).contains(httpResponse.statusCode) {
                    resetFailureState()
                    return data
                }

                let statusError = CloudAPIError.failedStatusCode(httpResponse.statusCode)
                lastError = statusError
                let shouldRetry = attempt < maxRetries && isTransientHTTPStatus(httpResponse.statusCode)
                if shouldRetry {
                    try await sleepBackoff(attempt: attempt)
                    continue
                }
                recordFailure()
                throw statusError
            } catch {
                lastError = error
                // Never count cancellation as a failure
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
                if attempt < maxRetries, isTransientNetworkError(error) {
                    try await sleepBackoff(attempt: attempt)
                    continue
                }
                if error is CloudAPIError {
                    throw error
                }
                recordFailure()
                throw error
            }
        }

        throw lastError
    }

    private func isTransientHTTPStatus(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func sleepBackoff(attempt: Int) async throws {
        let multiplier = UInt64(1 << attempt)
        let jitter = UInt64.random(in: 0...120_000_000)
        let delay = (baseBackoffNanoseconds * multiplier) + jitter
        try await Task.sleep(nanoseconds: delay)
    }

    private func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= circuitBreakerThreshold {
            circuitOpenUntil = Date().addingTimeInterval(circuitOpenSeconds)
            consecutiveFailures = 0
        }
    }

    private func resetFailureState() {
        consecutiveFailures = 0
        circuitOpenUntil = nil
    }

    private func parseSuggestions(_ rawValue: String, count: Int) -> [Completion] {
        let blockSeparator = "\n---\n"
        let candidates: [String]

        if rawValue.contains(blockSeparator) {
            candidates = rawValue.components(separatedBy: blockSeparator)
        } else {
            candidates = rawValue
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        let normalized = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { value in
                guard !value.isEmpty else { return false }
                let compact = value.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !compact.isEmpty
            }

        let unique = stableUnique(normalized)
        var results: [Completion] = []

        for (index, line) in unique.prefix(max(1, count)).enumerated() {
            let confidence = max(0.25, 0.74 - (Double(index) * 0.1))

            // Parse REPLACE:N:text format
            if line.hasPrefix("REPLACE:") {
                let afterPrefix = String(line.dropFirst("REPLACE:".count))
                if let colonIndex = afterPrefix.firstIndex(of: ":") {
                    let nString = String(afterPrefix[afterPrefix.startIndex..<colonIndex])
                    let replacementText = String(afterPrefix[afterPrefix.index(after: colonIndex)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let n = Int(nString), n > 0, !replacementText.isEmpty {
                        results.append(Completion(
                            text: replacementText,
                            confidence: confidence,
                            source: .cloud,
                            type: .replacement,
                            replacementLength: n
                        ))
                        continue
                    }
                }
            }

            // Plain continuation
            results.append(Completion(
                text: line,
                confidence: confidence,
                source: .cloud,
                type: .continuation,
                replacementLength: 0
            ))
        }

        return results
    }

    private func buildSelectionRewritePrompt(selectedText: String, userInstruction: String) -> String {
        """
        USER_INSTRUCTION:
        \(userInstruction)

        SELECTED_TEXT:
        <<<BEGIN_SELECTED_TEXT>>>
        \(selectedText)
        <<<END_SELECTED_TEXT>>>
        """
    }

    private func buildSelectionRewriteSystemPrompt() -> String {
        """
        You are a text rewriting assistant for direct in-place edits.
        Rewrite ONLY the provided selected text according to USER_INSTRUCTION.
        Return only the final rewritten text with no explanations, no markdown, no quotes.
        Preserve language unless instruction explicitly asks to change it.
        """
    }

    private func normalizeSelectedTextRewriteOutput(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        if value.hasPrefix("```"), value.hasSuffix("```") {
            let lines = value.components(separatedBy: .newlines)
            if lines.count >= 3 {
                value = lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("“") && value.hasSuffix("”"))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    private func buildSystemPrompt(context: TextContext, suggestionCount: Int) -> String {
        let defaults = UserDefaults(suiteName: Constants.AppGroup.suiteName)
        let customContinuation = defaults?.string(forKey: Constants.UserDefaultsKeys.customContinuationPrompt)
        let customReplacement = defaults?.string(forKey: Constants.UserDefaultsKeys.customReplacementPrompt)
        let replacementEnabled = defaults?.bool(forKey: Constants.UserDefaultsKeys.replacementModeEnabled) ?? false
        let appInstructions = AppOverridesStore.shared.customInstructions(for: context.appIdentifier)
        let combinedContinuationInstructions = [customContinuation, appInstructions]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let combinedReplacementInstructions = [customReplacement, appInstructions]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        if replacementEnabled {
            return SystemPrompts.hybrid(
                count: suggestionCount,
                userStyle: configuration.userStylePrompt,
                lexiconSnippet: configuration.lexiconStyleSnippet,
                customAddition: combinedReplacementInstructions
            )
        } else {
            return SystemPrompts.continuation(
                count: suggestionCount,
                userStyle: configuration.userStylePrompt,
                lexiconSnippet: configuration.lexiconStyleSnippet,
                customAddition: combinedContinuationInstructions
            )
        }
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values where seen.insert(value).inserted {
            result.append(value)
        }

        return result
    }
}

// MARK: - DTOs

private struct OpenAIRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
    let stream: Bool?
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct AnthropicRequest: Encodable {
    struct Message: Encodable {
        struct Content: Encodable {
            let type: String
            let text: String
        }

        let role: String
        let content: [Content]
    }

    let model: String
    let max_tokens: Int
    let temperature: Double
    let system: String
    let messages: [Message]
}

private struct AnthropicResponse: Decodable {
    struct Content: Decodable {
        let type: String
        let text: String?
    }

    let content: [Content]
}

private struct OpenAIStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct ContentPart: Decodable {
                let text: String?
            }

            let content: String?

            private enum CodingKeys: String, CodingKey {
                case content
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let direct = try? container.decode(String.self, forKey: .content) {
                    content = direct
                    return
                }
                if let parts = try? container.decode([ContentPart].self, forKey: .content) {
                    let joined = parts
                        .compactMap(\.text)
                        .joined()
                    content = joined.isEmpty ? nil : joined
                    return
                }
                content = nil
            }
        }

        let delta: Delta
    }

    struct StreamErrorPayload: Decodable {
        let message: String?
    }

    let choices: [Choice]
    let error: StreamErrorPayload?

    private enum CodingKeys: String, CodingKey {
        case choices
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = (try? container.decode([Choice].self, forKey: .choices)) ?? []
        error = try? container.decode(StreamErrorPayload.self, forKey: .error)
    }
}
