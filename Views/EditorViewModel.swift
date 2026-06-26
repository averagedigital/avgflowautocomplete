import Combine
import Foundation
import os.log

@MainActor
final class EditorViewModel: ObservableObject {
    private enum SuggestionTriggerMode {
        case automatic
        case manualHotkey
    }

    // MARK: - State

    @Published var text: String = ""
    @Published var ghostSuggestion: String = ""
    @Published var isLoading = false
    @Published var completionError: String?

    // MARK: - Telemetry
    private var suggestionPresentedAt: Date?
    private var lastAcceptedSuggestion: String?
    private var lastAcceptedAt: Date?
    private let logger = Logger(subsystem: "com.aicomplete", category: "Telemetry")
    private let analyticsDefaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard

    // MARK: - Dependencies

    private let localModelManager: LocalModelManager
    private let cloudAPIManager: CloudAPIManager
    private let userDictionary: UserDictionary
    private let personalizationManager: PersonalizationManager
    private let personalLexicon: PersonalLexicon
    private let hybridService: HybridCompletionService
    private let tinyStyleReranker: TinyStyleReranker

    // MARK: - Runtime

    private var completionTask: Task<Void, Never>?
    private var ghostStreamTask: Task<Void, Never>?
    private var localModelLoadAttempted = false
    private var lastInferenceWordCount = 0
    private var lastInferenceText = ""
    private var isComposingText = false
    private var currentMode: CompletionMode = .hybrid
    private var currentCloudProvider: CloudProvider = .openAI
    private var cloudRequestsAllowed = true
    private var cloudKeyAvailable = false
    private var maxTokens = 24
    private var suggestionTriggerMode: SuggestionTriggerMode = .manualHotkey
    private var lastTypingEventAt: Date?
    private var typingSpeedEMA: Double = 0
    private var rapidTypingStreak = 0
    private var settingsObserver: NSObjectProtocol?
    private var needsSettingsRefresh = true
    private var pendingSuggestionsShown = 0
    private var telemetryFlushTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let localModelManager = LocalModelManager()
        let cloudAPIManager = CloudAPIManager()
        let userDictionary = UserDictionary()

        self.localModelManager = localModelManager
        self.cloudAPIManager = cloudAPIManager
        self.userDictionary = userDictionary
        self.personalLexicon = SharedStore.makePersonalLexicon()

        let contextHistory = ContextHistory()
        self.personalizationManager = PersonalizationManager(
            userDictionary: userDictionary,
            contextHistory: contextHistory
        )

        self.hybridService = HybridCompletionService(
            localEngine: localModelManager,
            cloudEngine: cloudAPIManager,
            userDictionary: userDictionary,
            configuration: .default
        )
        self.tinyStyleReranker = TinyStyleReranker()

        Task { [weak self] in
            await TinyStyleTrainer.shared.restore()
            self?.reloadTriggerSettings()
            await self?.applySettings()
        }
        observeSettingsChanges()
    }

    deinit {
        completionTask?.cancel()
        ghostStreamTask?.cancel()
        telemetryFlushTask?.cancel()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    // MARK: - Public

    func userDidChangeText(_ newValue: String, isComposing: Bool = false) {
        let previousValue = text
        text = newValue
        isComposingText = isComposing

        if let lastAccepted = lastAcceptedSuggestion, let acceptedAt = lastAcceptedAt {
            if Date().timeIntervalSince(acceptedAt) < 10.0 {
                // If the previous text contained the suggestion but the new text does not, user potentially reverted it.
                if previousValue.hasSuffix(lastAccepted) && !newValue.hasSuffix(lastAccepted) {
                    logger.warning("Telemetry: rollback-rate event (User reverted accepted suggestion)")
                    lastAcceptedSuggestion = nil
                    lastAcceptedAt = nil
                }
            } else {
                lastAcceptedSuggestion = nil
                lastAcceptedAt = nil
            }
        }

        registerTypingCadence(previousText: previousValue, currentText: newValue)

        ghostSuggestion = ""
        ghostStreamTask?.cancel()
        suggestionPresentedAt = nil
        completionError = nil
        ingestTypedDeltaIfNeeded(previous: previousValue, current: newValue)

        if isComposingText {
            completionTask?.cancel()
            isLoading = false
            return
        }
        scheduleCompletion()
    }

    func acceptGhostSuggestion() {
        let suggestion = ghostSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suggestion.isEmpty else {
            return
        }

        let contextBeforeAcceptance = TextProcessor.buildContext(textBefore: text, textAfter: "")

        let needsSpace = !text.isEmpty && !text.hasSuffix(" ") && !suggestion.hasPrefix(" ")
        text += needsSpace ? " \(suggestion)" : suggestion
        ghostSuggestion = ""
        ghostStreamTask?.cancel()

        if let presentedAt = suggestionPresentedAt {
            let latency = Date().timeIntervalSince(presentedAt)
            logger.info("Telemetry: time-to-first-accept = \(latency, privacy: .public) seconds")
        }

        lastAcceptedSuggestion = suggestion
        lastAcceptedAt = Date()
        suggestionPresentedAt = nil

        Task { [personalizationManager] in
            await personalizationManager.recordAcceptedCompletion(
                Completion(text: suggestion, confidence: 0.9, source: .hybrid),
                context: contextBeforeAcceptance
            )
        }

        Task { [personalLexicon] in
            await personalLexicon.ingestAcceptedCompletion(
                context: contextBeforeAcceptance.textBefore,
                completion: suggestion
            )
        }

        Task {
            await TinyStyleTrainer.shared.recordHostAccepted(
                context: contextBeforeAcceptance.textBefore,
                completion: suggestion,
                language: contextBeforeAcceptance.language
            )
        }

        lastInferenceWordCount = TextProcessor.wordCount(in: text)
        lastInferenceText = text
        scheduleCompletion()
    }

    func dismissGhostSuggestion() {
        ghostSuggestion = ""
        ghostStreamTask?.cancel()
        suggestionPresentedAt = nil
    }

    func handleTabPressed() {
        acceptGhostSuggestion()
    }

    func setCompositionState(_ composing: Bool) {
        guard isComposingText != composing else { return }
        isComposingText = composing
        if composing {
            ghostSuggestion = ""
            ghostStreamTask?.cancel()
            completionTask?.cancel()
            isLoading = false
            return
        }

        scheduleCompletion()
    }

    func handleManualTriggerPressed() {
        reloadTriggerSettings()
        guard suggestionTriggerMode == .manualHotkey else { return }
        guard !isComposingText else { return }
        scheduleCompletion(force: true)
    }

    // MARK: - Private

    private func scheduleCompletion(force: Bool = false) {
        completionTask?.cancel()
        reloadTriggerSettings()

        guard !isComposingText else {
            ghostSuggestion = ""
            isLoading = false
            return
        }

        if suggestionTriggerMode == .manualHotkey && !force {
            isLoading = false
            return
        }

        let snapshot = text
        let trimmedSnapshot = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSnapshot.isEmpty else {
            ghostSuggestion = ""
            isLoading = false
            resetInferenceWindow()
            return
        }

        guard force || shouldTriggerInference(for: snapshot) else {
            isLoading = false
            return
        }

        isLoading = true
        completionTask = Task { [weak self] in
            guard let self else {
                return
            }

            let snippet = await self.refreshLexiconSnippet(for: snapshot)
            if self.needsSettingsRefresh {
                await self.applySettings()
            }
            await self.ensureLocalModelReadyIfNeeded()
            let context = TextProcessor.buildContext(
                textBefore: snapshot,
                textAfter: "",
                lexiconStyleSnippet: snippet
            )

            var suggestion = ""
            var usedLiveTokenStream = false
            do {
                if self.shouldUseLiveCloudStream() {
                    do {
                        usedLiveTokenStream = true
                        suggestion = try await self.requestCloudStreamingSuggestion(
                            context: context,
                            snapshot: snapshot
                        )
                        if suggestion.isEmpty {
                            usedLiveTokenStream = false
                            suggestion = try await self.requestHybridSuggestion(for: context)
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let urlError as URLError where urlError.code == .cancelled {
                        throw CancellationError()
                    } catch {
                        self.logger.error("Streaming inference failed: \(error.localizedDescription)")
                        usedLiveTokenStream = false
                        suggestion = try await self.requestHybridSuggestion(for: context)
                    }
                } else {
                    suggestion = try await self.requestHybridSuggestion(for: context)
                }
                self.completionError = nil
            } catch is CancellationError {
                suggestion = ""
                self.completionError = nil
            } catch let error as CompletionEngineError {
                switch error {
                case .noCompletion:
                    // Keep editor responsive even if cloud/local returned no text.
                    suggestion = self.makeFallbackSuggestion(for: context)
                    self.completionError = nil
                case let .engineFailure(message):
                    suggestion = ""
                    self.completionError = message
                default:
                    suggestion = ""
                    self.completionError = error.localizedDescription
                }
                self.logger.error("Inference failed: \(error.localizedDescription)")
            } catch {
                suggestion = ""
                self.completionError = error.localizedDescription
                self.logger.error("Inference failed: \(error.localizedDescription)")
            }

            guard !Task.isCancelled else {
                return
            }

            if self.text == snapshot {
                if !suggestion.isEmpty {
                    if usedLiveTokenStream {
                        if self.ghostSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.startStreamingGhostSuggestion(suggestion, snapshot: snapshot)
                        } else {
                            self.ghostSuggestion = suggestion
                            self.trackSuggestionShown()
                        }
                    } else {
                        self.startStreamingGhostSuggestion(suggestion, snapshot: snapshot)
                    }
                } else {
                    self.ghostStreamTask?.cancel()
                }
                self.isLoading = false
                self.lastInferenceWordCount = TextProcessor.wordCount(in: snapshot)
                self.lastInferenceText = snapshot
            }
        }
    }

    private func requestHybridSuggestion(for context: TextContext) async throws -> String {
        let rawCompletions = try await hybridService.complete(
            context: context,
            maxTokens: maxTokens,
            count: 5
        )
        let useTinyStyleRerank = await TinyStyleTrainer.shared.hasSufficientPersonalData(minExamples: 120)
        let candidates: [Completion]
        if useTinyStyleRerank {
            candidates = await tinyStyleReranker.rerank(
                context: context,
                completions: rawCompletions,
                keepTop: 1
            )
        } else {
            candidates = rawCompletions
        }
        let rawSuggestion = candidates.first?.text ?? makeFallbackSuggestion(for: context)
        return TextProcessor.continuationSuffix(from: rawSuggestion, after: context.textBefore)
    }

    private func shouldUseLiveCloudStream() -> Bool {
        guard currentMode != .localOnly else {
            return false
        }
        guard cloudRequestsAllowed, cloudKeyAvailable else {
            return false
        }
        switch currentCloudProvider {
        case .openAI, .openRouter:
            return true
        case .anthropic, .xAI:
            return false
        }
    }

    private func requestCloudStreamingSuggestion(
        context: TextContext,
        snapshot: String
    ) async throws -> String {
        ghostStreamTask?.cancel()
        ghostSuggestion = ""
        suggestionPresentedAt = nil
        var streamedRaw = ""

        let completions = try await cloudAPIManager.completeStreaming(
            context: context,
            maxTokens: maxTokens,
            count: 1
        ) { [weak self] delta in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.text == snapshot else { return }

                let normalizedDelta = self.normalizeStreamDelta(delta)
                guard !normalizedDelta.isEmpty else { return }

                streamedRaw += normalizedDelta
                let cleaned = self.stripReplacePrefix(streamedRaw)
                let display = TextProcessor.continuationSuffix(from: cleaned, after: snapshot)
                self.ghostSuggestion = display
                if self.suggestionPresentedAt == nil { self.trackSuggestionShown() }

                if self.suggestionPresentedAt == nil, !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.suggestionPresentedAt = Date()
                }
            }
        }

        let finalRaw = completions.first?.text ?? streamedRaw
        let cleaned = stripReplacePrefix(finalRaw)
        let suggestion = TextProcessor.continuationSuffix(from: cleaned, after: snapshot)
        if suggestionPresentedAt == nil, !suggestion.isEmpty {
            suggestionPresentedAt = Date()
        }
        return suggestion
    }

    /// Strip `REPLACE:N:` protocol prefix from cloud response if present.
    private func stripReplacePrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("REPLACE:") else { return text }
        let afterPrefix = String(trimmed.dropFirst("REPLACE:".count))
        guard let colonIndex = afterPrefix.firstIndex(of: ":") else { return text }
        return String(afterPrefix[afterPrefix.index(after: colonIndex)...])
    }

    private func normalizeStreamDelta(_ delta: String) -> String {
        let withoutNewlines = delta
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return withoutNewlines
    }

    private func startStreamingGhostSuggestion(_ suggestion: String, snapshot: String) {
        ghostStreamTask?.cancel()
        ghostSuggestion = ""
        suggestionPresentedAt = Date()

        let streamDelay: UInt64 = 26_000_000
        ghostStreamTask = Task { [weak self] in
            guard let self else { return }
            var assembled = ""
            try? await Task.sleep(nanoseconds: 90_000_000)
            for scalar in suggestion.unicodeScalars {
                guard !Task.isCancelled else { return }
                guard self.text == snapshot else { return }
                assembled.unicodeScalars.append(scalar)
                self.ghostSuggestion = assembled
                if assembled.count == 1 { self.trackSuggestionShown() }
                try? await Task.sleep(nanoseconds: streamDelay)
            }
        }
    }

    private func applySettings() async {
        let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
        APIKeyStore.migrateFromUserDefaultsIfNeeded(defaults)

        let modeRaw = defaults.string(forKey: Constants.UserDefaultsKeys.completionMode) ?? "hybrid"
        let mode: CompletionMode = {
            switch modeRaw {
            case "localOnly":
                return .localOnly
            case "cloudOnly":
                return .cloudOnly
            default:
                return .hybrid
            }
        }()
        let effectiveMode: CompletionMode = {
            if !LocalModelManager.isAvailable, mode == .localOnly {
                return .hybrid
            }
            return mode
        }()

        let cloudProviderRaw = defaults.string(forKey: Constants.UserDefaultsKeys.cloudProvider) ?? "openAI"
        let cloudProvider: CloudProvider = {
            switch cloudProviderRaw {
            case "anthropic":
                return .anthropic
            case "xAI":
                return .xAI
            case "openRouter":
                return .openRouter
            default:
                return .openAI
            }
        }()
        let cloudModelIdentifier = defaults.string(forKey: Constants.UserDefaultsKeys.cloudModelIdentifier) ?? defaultCloudModel(for: cloudProvider)
        let apiKey = APIKeyStore.read()
        let persistedMaxTokens = defaults.object(forKey: Constants.UserDefaultsKeys.maxTokens) as? Int ?? 24
        let privacyEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.privacyModeEnabled)
        let stylePrompt = defaults.string(forKey: Constants.UserDefaultsKeys.personalizationSystemPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let memories = decodeMemoryTexts(defaults: defaults)
        let styleInsights = decodeStringList(defaults: defaults, key: Constants.UserDefaultsKeys.personalizationStyleInsights)
        let goodCompletions = decodeStringList(defaults: defaults, key: Constants.UserDefaultsKeys.personalizationGoodCompletions)

        currentMode = effectiveMode
        currentCloudProvider = cloudProvider
        cloudRequestsAllowed = !privacyEnabled
        cloudKeyAvailable = !(apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        maxTokens = max(1, persistedMaxTokens)

        await cloudAPIManager.updateConfiguration(
            CloudConfiguration(
                provider: cloudProvider,
                modelIdentifier: cloudModelIdentifier,
                apiKey: apiKey,
                networkEnabled: !privacyEnabled,
                timeout: 20,
                userStylePrompt: stylePrompt,
                userPatterns: goodCompletions,
                userMemories: memories,
                styleInsights: styleInsights,
                goodCompletions: goodCompletions,
                lexiconStyleSnippet: nil
            )
        )

        await hybridService.updateConfiguration(
            HybridCompletionConfiguration(
                mode: effectiveMode,
                cloudAllowed: !privacyEnabled,
                debounceMilliseconds: 0,
                cloudReplacementLengthDelta: 6
            )
        )
        needsSettingsRefresh = false
    }

    private func reloadTriggerSettings() {
        let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
        let triggerModeRaw = defaults.string(forKey: Constants.UserDefaultsKeys.suggestionTriggerMode) ?? "manualHotkey"
        suggestionTriggerMode = (triggerModeRaw == "manualHotkey") ? .manualHotkey : .automatic
    }

    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.needsSettingsRefresh = true
                self?.reloadTriggerSettings()
            }
        }
    }

    private func ensureLocalModelReadyIfNeeded() async {
        guard LocalModelManager.isAvailable else {
            return
        }
        let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
        let localEnabled = defaults.object(forKey: Constants.UserDefaultsKeys.localModelEnabled) as? Bool ?? true
        guard localEnabled else {
            return
        }

        guard !localModelLoadAttempted else {
            return
        }

        localModelLoadAttempted = true

        do {
            let modelsDirectory = try AppGroupManager.shared.modelsDirectoryURL(createIfMissing: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: modelsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
            let selectedFileName = defaults.string(forKey: Constants.UserDefaultsKeys.selectedModelIdentifier)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let preferredFileName = Constants.LocalModels.preferredDefaultFileName
            let modelURL: URL?
            if let selectedFileName,
               !selectedFileName.isEmpty,
               let selectedURL = files.first(where: { $0.lastPathComponent.caseInsensitiveCompare(selectedFileName) == .orderedSame }) {
                modelURL = selectedURL
            } else {
                modelURL = files.first(where: {
                    $0.lastPathComponent.caseInsensitiveCompare(preferredFileName) == .orderedSame
                }) ?? files.first(where: { $0.pathExtension.lowercased() == "gguf" })
            }

            if let modelURL {
                try await localModelManager.loadModel(path: modelURL.path, contextSize: 4096)
            }
        } catch {
            // Silent fallback to cloud/rule-based suggestion.
        }
    }

    private func makeFallbackSuggestion(for context: TextContext) -> String {
        let normalizedLanguage = context.language.lowercased().hasPrefix("ru") ? "ru" : "en"
        let needsSpace = !context.textBefore.isEmpty && !context.textBefore.hasSuffix(" ")
        let prefix = needsSpace ? " " : ""

        if normalizedLanguage == "ru" {
            return "\(prefix)и продолжить мысль в этом направлении"
        }
        return "\(prefix)and continue this thought naturally"
    }

    private func defaultCloudModel(for provider: CloudProvider) -> String {
        switch provider {
        case .openAI:
            return "gpt-4.1-nano"
        case .anthropic:
            return "claude-3-5-haiku-latest"
        case .xAI:
            return "grok-3-mini-beta"
        case .openRouter:
            return "google/gemini-2.5-flash"
        }
    }

    private func shouldTriggerInference(for text: String) -> Bool {
        let currentWordCount = TextProcessor.wordCount(in: text)
        guard currentWordCount > 0 else {
            return false
        }

        if hasSentenceBoundaryTrigger(text) {
            return true
        }

        if isTypingRapidly {
            return false
        }

        if TextProcessor.likelyMessageReset(previous: lastInferenceText, current: text) {
            resetInferenceWindow()
            return currentWordCount >= Constants.Limits.completionInferenceWordDelta
        }

        if lastInferenceWordCount == 0 {
            return currentWordCount >= Constants.Limits.completionInferenceWordDelta
                || TextProcessor.endsWithSentenceBoundary(text)
        }

        let delta = max(0, currentWordCount - lastInferenceWordCount)
        return delta >= Constants.Limits.completionInferenceWordDelta
            || TextProcessor.endsWithSentenceBoundary(text)
    }

    private func resetInferenceWindow() {
        lastInferenceWordCount = 0
        lastInferenceText = ""
        lastTypingEventAt = nil
        typingSpeedEMA = 0
        rapidTypingStreak = 0
    }

    private func refreshLexiconSnippet(for text: String) async -> String {
        let language = LanguageDetect.detect(from: text)
        return await personalLexicon.styleSnippet(preferredLanguage: language, maxLength: 400)
    }

    private func ingestTypedDeltaIfNeeded(previous: String, current: String) {
        guard current.count >= previous.count else {
            return
        }
        guard current != previous else {
            return
        }

        if current.hasPrefix(previous) {
            let appended = String(current.dropFirst(previous.count))
            guard !appended.isEmpty else {
                return
            }
            guard appended.rangeOfCharacter(from: .whitespacesAndNewlines.union(.punctuationCharacters)) != nil else {
                return
            }
            Task { [personalLexicon] in
                await personalLexicon.ingestTypedText(text: appended, source: .hostEditor)
            }
            return
        }

        guard TextProcessor.endsWithSentenceBoundary(current) else {
            return
        }
        Task { [personalLexicon] in
            await personalLexicon.ingestTypedText(text: String(current.suffix(180)), source: .hostEditor)
        }
    }

    private func decodeStringList(defaults: UserDefaults, key: String) -> [String] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func decodeMemoryTexts(defaults: UserDefaults) -> [String] {
        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.personalizationUserMemories),
              let decoded = try? JSONDecoder().decode([StoredMemoryItem].self, from: data) else {
            return []
        }
        return decoded
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isTypingRapidly: Bool {
        rapidTypingStreak >= 2 || typingSpeedEMA >= 12
    }

    private func registerTypingCadence(previousText: String, currentText: String) {
        let now = Date()
        defer { lastTypingEventAt = now }

        guard previousText != currentText else { return }

        guard currentText.count >= previousText.count,
              currentText.hasPrefix(previousText) else {
            rapidTypingStreak = max(0, rapidTypingStreak - 1)
            typingSpeedEMA = max(0, typingSpeedEMA * 0.88)
            return
        }

        let appendedCount = currentText.count - previousText.count
        guard appendedCount > 0 else { return }
        guard let lastTypingEventAt else { return }

        let delta = max(0.001, now.timeIntervalSince(lastTypingEventAt))
        let charsPerSecond = Double(appendedCount) / delta
        typingSpeedEMA = typingSpeedEMA == 0
            ? charsPerSecond
            : ((typingSpeedEMA * 0.7) + (charsPerSecond * 0.3))

        if delta < 0.09 && appendedCount <= 3 {
            rapidTypingStreak += 1
        } else {
            rapidTypingStreak = max(0, rapidTypingStreak - 1)
        }
    }

    private func hasSentenceBoundaryTrigger(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        if ".!?…".contains(last) {
            return true
        }
        return text.hasSuffix("\n")
    }

    private func trackSuggestionShown() {
        pendingSuggestionsShown += 1
        guard telemetryFlushTask == nil else { return }

        telemetryFlushTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }

            let flushValue = self.pendingSuggestionsShown
            self.pendingSuggestionsShown = 0
            let current = self.analyticsDefaults.integer(forKey: Constants.UserDefaultsKeys.totalSuggestionsShown)
            self.analyticsDefaults.set(current + flushValue, forKey: Constants.UserDefaultsKeys.totalSuggestionsShown)
            self.telemetryFlushTask = nil
        }
    }
}

private struct StoredMemoryItem: Codable {
    let id: UUID
    let text: String
    let createdAt: Date
}
