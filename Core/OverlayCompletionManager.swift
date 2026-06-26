import AppKit
import Foundation
import os

/// Central orchestrator for the system-wide autocomplete overlay.
/// Ties together: AX text reading → completion pipeline → overlay panel → text insertion.
/// This is the macOS equivalent of `KeyboardCompletionManager` + `KeyboardViewController`.
@MainActor
final class OverlayCompletionManager {
    private enum SuggestionTriggerMode {
        case automatic
        case manualHotkey
    }

    private struct SelectionRewriteRequest {
        let element: AXUIElement
        let appPID: pid_t
        let appBundleID: String?
        let snapshot: AccessibilityTextReader.SelectedTextSnapshot
    }

    // MARK: - Sub-components

    private let focusedAppMonitor = FocusedAppMonitor()
    private let accessibilityObserver = AccessibilityObserver()
    private let textReader = AccessibilityTextReader()
    private let panelController = SuggestionPanelController()
    private let cursorResolver = CursorPositionResolver()
    private let selectionRewritePromptController = SelectionRewritePromptPanelController()
    private let eventTapManager = EventTapManager()
    private let compatibilityLayer = AppCompatibilityLayer()
    private let textInsertionService = TextInsertionService()
    private let permissionsManager: PermissionsManager
    private let appOverridesStore = AppOverridesStore.shared
    private lazy var acceptanceSynthesizer = AcceptanceSynthesizer(
        textInsertionService: textInsertionService,
        compatibilityLayer: compatibilityLayer
    )
    private lazy var suggestionCoordinator = SuggestionCoordinator(
        panelController: panelController,
        eventTapManager: eventTapManager,
        debugLog: { [weak self] message in
            self?.debugLog(message)
        }
    )

    // MARK: - Completion Pipeline (from Shared/)

    private lazy var localModelManager = LocalModelManager()
    private lazy var cloudAPIManager = CloudAPIManager()
    private lazy var userDictionary = UserDictionary()
    private lazy var personalLexicon: PersonalLexicon = SharedStore.makePersonalLexicon()
    private lazy var personalizationManager: PersonalizationManager = {
        let contextHistory = ContextHistory()
        return PersonalizationManager(
            userDictionary: userDictionary,
            contextHistory: contextHistory
        )
    }()
    private lazy var hybridService: HybridCompletionService = {
        HybridCompletionService(
            localEngine: localModelManager,
            cloudEngine: cloudAPIManager,
            userDictionary: userDictionary,
            configuration: .default
        )
    }()
    private lazy var tinyStyleReranker = TinyStyleReranker()
    private let signpostLog = OSLog(subsystem: "com.aicomplete.mac", category: .pointsOfInterest)
    private let decisionLogger = Logger(subsystem: "com.aicomplete.mac", category: "Decision")

    // MARK: - State

    private var focusedElement: AXUIElement?
    private var previousContext: TextContext?
    private var lastInferenceWordCount = 0
    private var lastInferenceTextBefore = ""
    private var currentCompletionTask: Task<Void, Never>?
    private var trainingTask: Task<Void, Never>?
    private var localModelLoadAttempted = false
    private var cachedLexiconSnippet = ""
    private var isRunning = false
    private var completionRequestSerial: UInt64 = 0
    private var lastTypingEventAt: Date?
    private var typingSpeedEMA: Double = 0
    private var rapidTypingStreak = 0
    private var defaultsObserver: NSObjectProtocol?
    private var selectionRewriteTask: Task<Void, Never>?
    private var activeSelectionRewriteRequest: SelectionRewriteRequest?
    private var lastSelectionSignature: String?
    private var suppressSelectionPromptUntil: Date?

    // Settings cache
    private var completionMode: CompletionMode = .hybrid
    private var cloudProvider: CloudProvider = .openAI
    private var cloudModelIdentifier = "gpt-4.1-nano"
    private var cloudAPIKey: String?
    private var suggestionCount = 1
    private var maxTokens = 24
    private var suggestionTriggerMode: SuggestionTriggerMode = .manualHotkey
    private var manualTriggerKeyCode: Int64 = 49
    private var manualTriggerModifiersRaw: UInt64 = CGEventFlags.maskAlternate.rawValue
    private var paletteNextKeyCode: Int64 = 125
    private var paletteNextModifiersRaw: UInt64 = CGEventFlags.maskAlternate.rawValue
    private var palettePreviousKeyCode: Int64 = 126
    private var palettePreviousModifiersRaw: UInt64 = CGEventFlags.maskAlternate.rawValue
    private var singleSuggestionAcceptMode: SingleSuggestionAcceptMode = .nextWord
    private var partialAcceptTrailingSpaceEnabled = true
    private var localModelEnabled = true
    private var personalizationSystemPrompt: String?
    private var personalizationMemories: [String] = []
    private var personalizationStyleInsights: [String] = []
    private var personalizationGoodCompletions: [String] = []
    private var privacyModeEnabled = false
    private var selectionRewriteAutoPromptEnabled = false

    // Acceptance history for undo & analytics
    private let acceptanceHistory = AcceptanceHistoryStore.shared

    // MARK: - Init

    init(permissionsManager: PermissionsManager) {
        self.permissionsManager = permissionsManager

        selectionRewritePromptController.onSubmit = { [weak self] prompt in
            self?.submitSelectionRewritePrompt(prompt)
        }
        selectionRewritePromptController.onCancel = { [weak self] in
            self?.cancelSelectionRewriteFlow()
        }
        panelController.onSuggestionClicked = { [weak self] index in
            Task { @MainActor [weak self] in
                self?.acceptSuggestion(at: index, fromEventTargetPID: nil)
            }
        }
        panelController.onSelectionCycleRequested = { [weak self] delta in
            Task { @MainActor [weak self] in
                _ = self?.cycleSuggestionSelection(by: delta, forEventTargetPID: nil)
            }
        }

        Task {
            await TinyStyleTrainer.shared.restore()
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        isRunning = true
        debugLog("[AIComplete] OverlayManager.start()")

        reloadSettings()
        startTrainingLoop()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadSettings()
            }
        }

        // 1. Monitor which app is frontmost
        focusedAppMonitor.onAppChanged = { [weak self] pid, bundleID, appName in
            self?.debugLog("[AIComplete] App changed: pid=\(pid) bundle=\(bundleID ?? "nil") name=\(appName ?? "nil")")
            self?.handleAppChanged(pid: pid, bundleID: bundleID, appName: appName)
        }
        focusedAppMonitor.start()

        // 2. AX observer callbacks
        accessibilityObserver.onFocusChanged = { [weak self] in
            self?.debugLog("[AIComplete] Focus changed")
            self?.handleFocusChanged()
        }
        accessibilityObserver.onTextChanged = { [weak self] in
            self?.handleTextChanged()
        }

        // 3. Event tap for Tab / Escape
        eventTapManager.onTapStatusChanged = { [weak self] isActive in
            self?.debugLog("[AIComplete] EventTap status changed: active=\(isActive)")
            self?.logDecision(
                decision: "event_tap_state",
                reason: isActive ? "active" : "inactive"
            )
        }
        eventTapManager.onTabPressed = { [weak self] targetPID in
            guard let self else { return false }
            guard self.shouldConsumeTab(forEventTargetPID: targetPID) else {
                return false
            }
            self.debugLog("[AIComplete] Tab pressed — accepting suggestion")
            Task { @MainActor [weak self] in
                self?.acceptCurrentSuggestion(fromEventTargetPID: targetPID)
            }
            return true
        }
        eventTapManager.onEscapePressed = { [weak self] in
            Task { @MainActor [weak self] in
                self?.debugLog("[AIComplete] Escape pressed — dismissing suggestion")
                self?.dismissSuggestion()
            }
        }
        eventTapManager.onManualTriggerPressed = { [weak self] targetPID in
            guard let self else { return false }
            Task { @MainActor [weak self] in
                self?.debugLog("[AIComplete] Manual trigger hotkey pressed")
                self?.handleManualTriggerPressed(targetPID: targetPID)
            }
            return true
        }
        eventTapManager.onPaletteCycleRequested = { [weak self] delta, targetPID in
            guard let self else { return false }
            return self.cycleSuggestionSelection(by: delta, forEventTargetPID: targetPID)
        }
        eventTapManager.onSuggestionNumberPressed = { [weak self] index, targetPID in
            guard let self else { return false }
            return self.acceptSuggestion(at: index, fromEventTargetPID: targetPID)
        }
        eventTapManager.start()
        debugLog("[AIComplete] EventTap started")
    }

    func stop() {
        isRunning = false
        completionRequestSerial &+= 1
        resetTypingCadence()
        focusedAppMonitor.stop()
        accessibilityObserver.stopObserving()
        eventTapManager.stop()
        selectionRewritePromptController.hide()
        currentCompletionTask?.cancel()
        selectionRewriteTask?.cancel()
        trainingTask?.cancel()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        focusedElement = nil
        previousContext = nil
        activeSelectionRewriteRequest = nil
        lastSelectionSignature = nil
        suggestionCoordinator.reset()
    }

    // MARK: - App Changed

    private func handleAppChanged(pid: pid_t, bundleID: String?, appName: String?) {
        // Cross-app transitions must reset overlay/request state immediately
        // to avoid stale suggestions and mismatched Tab acceptance.
        resetInferenceState()
        dismissSuggestion()

        appOverridesStore.registerSeenApp(bundleIdentifier: bundleID, displayName: appName)

        // Don't observe our own app
        if bundleID == Bundle.main.bundleIdentifier {
            eventTapManager.manualTriggerEnabled = false
            accessibilityObserver.stopObserving()
            focusedElement = nil
            return
        }

        if selectionRewritePromptController.isVisible,
           let activeSelectionRewriteRequest,
           activeSelectionRewriteRequest.appPID != pid {
            cancelSelectionRewriteFlow()
        }

        // Reload settings BEFORE configuring the event tap
        reloadSettings()

        debugLog("[AIComplete] handleAppChanged: triggerMode=\(suggestionTriggerMode == .manualHotkey ? "manualHotkey" : "automatic") manualTriggerEnabled=\(suggestionTriggerMode == .manualHotkey)")

        eventTapManager.manualTriggerEnabled = suggestionTriggerMode == .manualHotkey
        eventTapManager.manualTriggerKeyCode = manualTriggerKeyCode
        eventTapManager.manualTriggerModifiers = CGEventFlags(rawValue: manualTriggerModifiersRaw)
        accessibilityObserver.observe(pid: pid)
        handleFocusChanged()
    }

    // MARK: - Focus Changed

    private func handleFocusChanged() {
        guard let appElement = focusedAppMonitor.currentAppElement else {
            debugLog("[AIComplete] handleFocusChanged: no appElement")
            dismissSuggestion()
            cancelSelectionRewriteFlow()
            return
        }

        guard let focused = textReader.focusedElement(for: appElement) else {
            debugLog("[AIComplete] handleFocusChanged: no focused element")
            dismissSuggestion()
            cancelSelectionRewriteFlow()
            focusedElement = nil
            return
        }

        let element = textReader.editableElement(from: focused) ?? focused

        guard textReader.isTextInput(element) else {
            debugLog("[AIComplete] handleFocusChanged: element is not text input")
            dismissSuggestion()
            cancelSelectionRewriteFlow()
            focusedElement = nil
            return
        }

        debugLog("[AIComplete] handleFocusChanged: found text input element")
        focusedElement = element
        evaluateAndRequestCompletions(force: true, manualInvocation: false)
    }

    // MARK: - Text Changed

    private func handleTextChanged() {
        if selectionRewritePromptController.isVisible {
            updateSelectionRewriteAnchorIfNeeded()
        }
        evaluateAndRequestCompletions(force: false, manualInvocation: false)
    }

    // MARK: - Completion Logic

    private func evaluateAndRequestCompletions(force: Bool, manualInvocation: Bool = false) {
        guard let element = focusedElement else {
            return
        }

        if selectionRewriteAutoPromptEnabled, maybePresentSelectionRewritePrompt(for: element) {
            currentCompletionTask?.cancel()
            dismissSuggestion()
            previousContext = nil
            return
        }

        let appBundleID = focusedAppMonitor.currentAppBundleID
        let contextReadSignpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "ax_read_context", signpostID: contextReadSignpostID)
        let maybeContext = textReader.readContext(from: element, appBundleID: appBundleID)
        os_signpost(.end, log: signpostLog, name: "ax_read_context", signpostID: contextReadSignpostID)

        guard let context = maybeContext else {
            debugLog("[AIComplete] evaluateAndRequest: could not read context")
            logDecision(decision: "suggestion_rejected", reason: "context_unavailable")
            dismissSuggestion()
            return
        }
        registerTypingCadence(previousText: previousContext?.textBefore, currentText: context.textBefore)

        if previousContext?.textBefore != context.textBefore {
            dismissSuggestion()
        }

        // Skip if text is empty
        if context.textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logDecision(decision: "suggestion_rejected", reason: "empty_prefix")
            dismissSuggestion()
            previousContext = context
            return
        }

        if !appOverridesStore.completionsEnabled(for: context.appIdentifier) {
            logDecision(
                decision: "suggestion_rejected",
                reason: "app_completions_disabled",
                appBundleID: context.appIdentifier
            )
            currentCompletionTask?.cancel()
            dismissSuggestion()
            previousContext = context
            return
        }

        if suggestionTriggerMode == .manualHotkey && !manualInvocation {
            debugLog("[AIComplete] Blocking auto-completion: triggerMode=manualHotkey, manualInvocation=false")
            logDecision(decision: "suggestion_rejected", reason: "manual_mode_blocked")
            currentCompletionTask?.cancel()
            dismissSuggestion()
            previousContext = context
            return
        }

        // Skip if no meaningful change (unless forced)
        guard force || textReader.hasMeaningfulChange(previous: previousContext, current: context) else {
            return
        }

        // Detect message reset
        if TextProcessor.likelyMessageReset(previous: lastInferenceTextBefore, current: context.textBefore) {
            resetInferenceState()
            dismissSuggestion()
        }

        // Check trigger conditions
        guard force || shouldTriggerInference(for: context) else {
            previousContext = context
            return
        }

        previousContext = context
        lastInferenceWordCount = TextProcessor.wordCount(in: context.textBefore)
        lastInferenceTextBefore = context.textBefore

        requestCompletions(for: context, element: element, manualInvocation: manualInvocation)
    }

    private func handleManualTriggerPressed(targetPID: pid_t?) {
        if panelController.isVisible, cycleSuggestionSelection(by: 1, forEventTargetPID: targetPID) {
            return
        }
        if focusedElement == nil {
            handleFocusChanged()
        }
        evaluateAndRequestCompletions(force: true, manualInvocation: true)
    }

    private func requestCompletions(for context: TextContext, element: AXUIElement, manualInvocation: Bool) {
        currentCompletionTask?.cancel()
        completionRequestSerial &+= 1
        let requestID = completionRequestSerial

        if suggestionTriggerMode == .manualHotkey && !manualInvocation {
            dismissSuggestion()
            return
        }
        if !appOverridesStore.completionsEnabled(for: context.appIdentifier) {
            logDecision(
                decision: "suggestion_rejected",
                reason: "app_completions_disabled",
                appBundleID: context.appIdentifier
            )
            dismissSuggestion()
            return
        }
        suggestionCoordinator.showLoading(
            near: element,
            geometryFallbackPolicy: geometryFallbackPolicy(for: element)
        )

        currentCompletionTask = Task { [weak self] in
            guard let self else { return }
            guard self.isCurrentRequest(requestID) else { return }
            let completionSignpostID = OSSignpostID(log: self.signpostLog)
            os_signpost(.begin, log: self.signpostLog, name: "completion_request", signpostID: completionSignpostID)
            defer {
                os_signpost(.end, log: self.signpostLog, name: "completion_request", signpostID: completionSignpostID)
            }

            do {
                if self.shouldBlockRequestForManualMode(manualInvocation: manualInvocation) {
                    self.logDecision(decision: "suggestion_rejected", reason: "manual_mode_blocked")
                    self.dismissSuggestion()
                    return
                }

                // Fast path: show personal dictionary continuation immediately when available.
                var quickSuggestionShown = false
                let quickSuggestions = await self.userDictionary.quickSuggestions(for: context, limit: max(1, self.suggestionCount))
                guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
                let preparedQuickSuggestions = quickSuggestions
                    .compactMap { self.prepareOverlayCompletion($0, context: context) }
                if !preparedQuickSuggestions.isEmpty {
                    if self.shouldBlockRequestForManualMode(manualInvocation: manualInvocation) {
                        self.dismissSuggestion()
                        return
                    }
                    self.presentSuggestions(
                        preparedQuickSuggestions,
                        near: element,
                        isLoading: true,
                        source: preparedQuickSuggestions.first?.source ?? .userDictionary,
                        confidence: preparedQuickSuggestions.first?.confidence ?? 0,
                        modelName: self.cloudModelIdentifier
                    )
                    self.logDecision(
                        decision: "suggestion_shown",
                        reason: "quick_dictionary",
                        source: self.sourceName(preparedQuickSuggestions.first?.source ?? .userDictionary)
                    )
                    quickSuggestionShown = true
                }

                // Get lexicon snippet
                let snippet = await self.personalLexicon.styleSnippet(
                    preferredLanguage: context.language,
                    maxLength: 400
                )
                guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
                self.cachedLexiconSnippet = snippet

                // Ensure local model is ready if needed
                await self.ensureLocalModelReadyIfNeeded()
                guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }

                // Refresh cloud/hybrid configuration
                await self.refreshConfiguration()
                guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }

                // Build enriched context
                let enrichedContext = TextContext(
                    textBefore: context.textBefore,
                    textAfter: context.textAfter,
                    appIdentifier: context.appIdentifier,
                    language: context.language,
                    lexiconStyleSnippet: snippet
                )

                var preparedCandidates: [Completion] = []

                if self.shouldUseLiveCloudStream() {
                    do {
                        if let prepared = try await self.requestCloudStreamingSuggestion(
                            context: enrichedContext,
                            element: element,
                            requestID: requestID,
                            manualInvocation: manualInvocation
                        ) {
                            preparedCandidates = [prepared]
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let urlError as URLError where urlError.code == .cancelled {
                        throw CancellationError()
                    } catch {
                        self.debugLog("[AIComplete] Provider streaming failed: \(error.localizedDescription)")
                        preparedCandidates = []
                    }
                }

                if preparedCandidates.isEmpty {
                    // Fallback to the existing hybrid path
                    let rawCompletions = try await self.hybridService.complete(
                        context: enrichedContext,
                        maxTokens: self.maxTokens,
                        count: max(self.suggestionCount, 5)
                    )

                    let useTinyStyleRerank = await TinyStyleTrainer.shared.hasSufficientPersonalData(minExamples: 120)
                    let primaryCandidates: [Completion]
                    if useTinyStyleRerank {
                        primaryCandidates = await self.tinyStyleReranker.rerank(
                            context: enrichedContext,
                            completions: rawCompletions,
                            keepTop: 3
                        )
                    } else {
                        primaryCandidates = rawCompletions
                    }

                    guard !Task.isCancelled, self.isCurrentRequest(requestID) else { return }
                    let primaryPrepared = primaryCandidates.compactMap { self.prepareOverlayCompletion($0, context: enrichedContext) }
                    let fallbackPrepared = rawCompletions.compactMap { self.prepareOverlayCompletion($0, context: enrichedContext) }
                    preparedCandidates = !primaryPrepared.isEmpty ? primaryPrepared : fallbackPrepared
                }

                if let best = preparedCandidates.first {
                    if self.shouldBlockRequestForManualMode(manualInvocation: manualInvocation) {
                        self.dismissSuggestion()
                        return
                    }
                    self.debugLog("[AIComplete] Showing suggestion (chars=\(best.text.count) source=\(best.source) type=\(String(describing: best.type)))")
                    self.presentSuggestions(
                        preparedCandidates,
                        near: element,
                        isLoading: false,
                        source: best.source,
                        confidence: best.confidence,
                        modelName: self.cloudModelIdentifier
                    )
                    self.logDecision(
                        decision: "suggestion_shown",
                        reason: "completion_ready",
                        source: self.sourceName(best.source)
                    )
                } else if quickSuggestionShown, let quick = self.suggestionCoordinator.currentCompletion {
                    // Keep quick result visible even if slower engines return nothing.
                    self.presentSuggestions(
                        self.suggestionCoordinator.currentCompletions.isEmpty
                            ? [quick]
                            : self.suggestionCoordinator.currentCompletions,
                        near: element,
                        isLoading: false,
                        source: quick.source,
                        confidence: quick.confidence,
                        modelName: self.cloudModelIdentifier
                    )
                    self.logDecision(
                        decision: "suggestion_shown",
                        reason: "quick_dictionary_retained",
                        source: self.sourceName(quick.source)
                    )
                } else {
                    self.debugLog("[AIComplete] No suggestions after reranking")
                    self.logDecision(decision: "suggestion_rejected", reason: "no_candidates")
                    self.dismissSuggestion()
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.debugLog("[AIComplete] Completion error: \(error.localizedDescription)")
                self.logDecision(decision: "suggestion_rejected", reason: "completion_error")
                self.dismissSuggestion()
            }
        }
    }

    private func prepareOverlayCompletion(_ completion: Completion, context: TextContext) -> Completion? {
        if completion.type == .replacement {
            var replacement = completion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if replacement.hasPrefix("REPLACE:") {
                let afterPrefix = String(replacement.dropFirst("REPLACE:".count))
                if let colonIndex = afterPrefix.firstIndex(of: ":") {
                    replacement = String(afterPrefix[afterPrefix.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            guard completion.replacementLength > 0, isMeaningfulSuggestion(replacement) else {
                return nil
            }

            return Completion(
                text: replacement,
                confidence: completion.confidence,
                source: completion.source,
                type: .replacement,
                replacementLength: completion.replacementLength
            )
        }

        let continuation = TextProcessor.continuationSuffix(from: completion.text, after: context.textBefore)
        guard isMeaningfulSuggestion(continuation) else { return nil }

        return Completion(
            text: continuation,
            confidence: completion.confidence,
            source: completion.source,
            type: .continuation,
            replacementLength: 0
        )
    }

    private func presentSuggestions(
        _ completions: [Completion],
        near element: AXUIElement,
        isLoading: Bool,
        source: CompletionSource,
        confidence: Double,
        modelName: String?
    ) {
        suggestionCoordinator.presentSuggestions(
            completions,
            limit: suggestionCount,
            near: element,
            isLoading: isLoading,
            source: source,
            confidence: confidence,
            modelName: modelName,
            currentAppPID: focusedAppMonitor.currentAppPID,
            geometryFallbackPolicy: geometryFallbackPolicy(for: element)
        )
    }

    private func geometryFallbackPolicy(for element: AXUIElement) -> GeometryFallbackPolicy {
        let targetAppClass = compatibilityLayer.classifyTargetAppClass(
            for: element,
            appBundleID: focusedAppMonitor.currentAppBundleID,
            textReader: textReader
        )
        return compatibilityLayer.geometryFallbackPolicy(for: targetAppClass)
    }

    private func canInteractWithSuggestionPalette(forEventTargetPID targetPID: pid_t?) -> Bool {
        suggestionCoordinator.canInteractWithSuggestionPalette(
            forEventTargetPID: targetPID,
            currentFocusedAppPID: focusedAppMonitor.currentAppPID
        )
    }

    @discardableResult
    private func cycleSuggestionSelection(by delta: Int, forEventTargetPID targetPID: pid_t?) -> Bool {
        let didCycle = suggestionCoordinator.cycleSelection(
            by: delta,
            forEventTargetPID: targetPID,
            currentFocusedAppPID: focusedAppMonitor.currentAppPID
        )
        guard didCycle else {
            return false
        }
        logDecision(
            decision: "palette_navigation",
            reason: delta >= 0 ? "next" : "previous",
            source: sourceName(suggestionCoordinator.currentCompletion?.source ?? .hybrid)
        )
        return true
    }

    @discardableResult
    private func acceptSuggestion(at index: Int, fromEventTargetPID targetPID: pid_t?) -> Bool {
        guard suggestionCoordinator.selectSuggestion(
            at: index,
            forEventTargetPID: targetPID,
            currentFocusedAppPID: focusedAppMonitor.currentAppPID
        ) else {
            return false
        }
        acceptCurrentSuggestion(fromEventTargetPID: targetPID)
        return true
    }

    // MARK: - Accept / Dismiss

    private func shouldConsumeTab(forEventTargetPID targetPID: pid_t?) -> Bool {
        guard canInteractWithSuggestionPalette(forEventTargetPID: targetPID) else {
            return false
        }
        if appOverridesStore.isTabKeyDisabled(for: focusedAppMonitor.currentAppBundleID) {
            logDecision(decision: "accept_rejected", reason: "tab_disabled_for_app")
            return false
        }
        return true
    }

    private func acceptCurrentSuggestion(fromEventTargetPID targetPID: pid_t?) {
        guard shouldConsumeTab(forEventTargetPID: targetPID) else {
            return
        }
        guard let completion = suggestionCoordinator.currentCompletion,
              let element = focusedElement else {
            return
        }

        if let acceptedChunk = acceptanceSynthesizer.partialAcceptance(
            for: completion,
            currentCompletionsCount: suggestionCoordinator.currentCompletions.count,
            acceptMode: singleSuggestionAcceptMode,
            includeTrailingWhitespace: partialAcceptTrailingSpaceEnabled
        ),
           !acceptedChunk.remainingText.isEmpty {
            let partialCompletion = Completion(
                text: acceptedChunk.chunk,
                confidence: completion.confidence,
                source: completion.source,
                type: .continuation,
                replacementLength: 0
            )
            let insertionResult = acceptanceSynthesizer.insertCompletionText(
                partialCompletion,
                into: element,
                appBundleID: focusedAppMonitor.currentAppBundleID,
                currentAppPID: focusedAppMonitor.currentAppPID,
                activeSuggestionPID: suggestionCoordinator.activeSuggestionPID,
                textReader: textReader
            )
            logDecision(
                decision: insertionResult.succeeded ? "accept_partial_success" : "accept_partial_failed",
                reason: insertionResult.reason,
                source: sourceName(completion.source),
                targetClass: insertionResult.targetClass.rawValue,
                strategy: insertionResult.route.rawValue
            )
            guard insertionResult.succeeded else {
                dismissSuggestion()
                return
            }

            let remainingCompletion = Completion(
                text: acceptedChunk.remainingText,
                confidence: completion.confidence,
                source: completion.source,
                type: .continuation,
                replacementLength: 0
            )
            previousContext = acceptanceSynthesizer.updatedContextAfterPartialAcceptance(
                previousContext: previousContext,
                chunk: acceptedChunk.chunk
            )
            suggestionCoordinator.presentRemainingPartialSuggestion(
                remainingCompletion,
                near: element,
                modelName: cloudModelIdentifier,
                currentAppPID: focusedAppMonitor.currentAppPID,
                geometryFallbackPolicy: geometryFallbackPolicy(for: element)
            )
            return
        }

        let contextBeforeAcceptance = previousContext

        let insertionResult = acceptanceSynthesizer.insertCompletionText(
            completion,
            into: element,
            appBundleID: focusedAppMonitor.currentAppBundleID,
            currentAppPID: focusedAppMonitor.currentAppPID,
            activeSuggestionPID: suggestionCoordinator.activeSuggestionPID,
            textReader: textReader
        )
        logDecision(
            decision: insertionResult.succeeded ? "accept_success" : "accept_failed",
            reason: insertionResult.reason,
            source: sourceName(completion.source),
            targetClass: insertionResult.targetClass.rawValue,
            strategy: insertionResult.route.rawValue
        )
        guard insertionResult.succeeded else {
            dismissSuggestion()
            return
        }

        dismissSuggestion()

        // Record for personalization + acceptance history
        if let context = contextBeforeAcceptance {
            Task { [personalizationManager, personalLexicon, acceptanceHistory] in
                await personalizationManager.recordAcceptedCompletion(completion, context: context)
                await personalLexicon.ingestAcceptedCompletion(
                    context: context.textBefore,
                    completion: completion.text
                )
                await TinyStyleTrainer.shared.logKeyboardAccepted(
                    context: context.textBefore,
                    completion: completion.text,
                    language: context.language
                )
                // Track in acceptance history for undo & metrics
                await acceptanceHistory.record(
                    originalText: context.textBefore,
                    acceptedText: completion.text,
                    source: completion.source,
                    confidence: completion.confidence,
                    appIdentifier: context.appIdentifier
                )
            }
        }

        // Schedule next completion after acceptance
        lastInferenceWordCount = 0
        lastInferenceTextBefore = ""
        guard suggestionTriggerMode == .automatic else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.evaluateAndRequestCompletions(force: true, manualInvocation: false)
        }
    }

    private func dismissSuggestion() {
        suggestionCoordinator.reset()
    }

    // MARK: - Selection Rewrite

    private func maybePresentSelectionRewritePrompt(for element: AXUIElement) -> Bool {
        if let suppressSelectionPromptUntil, suppressSelectionPromptUntil > Date() {
            return false
        }

        guard let snapshot = textReader.selectedTextSnapshot(from: element),
              snapshot.range.length > 0,
              !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if selectionRewritePromptController.isVisible {
                selectionRewritePromptController.hide()
                activeSelectionRewriteRequest = nil
                lastSelectionSignature = nil
            }
            return false
        }

        let signature = selectionSignature(snapshot)
        let request = SelectionRewriteRequest(
            element: element,
            appPID: focusedAppMonitor.currentAppPID,
            appBundleID: focusedAppMonitor.currentAppBundleID,
            snapshot: snapshot
        )

        activeSelectionRewriteRequest = request

        let anchor = selectionAnchorRect(for: element)
        if selectionRewritePromptController.isVisible {
            if lastSelectionSignature != signature {
                selectionRewritePromptController.show(near: anchor, selectedText: snapshot.text)
            } else {
                selectionRewritePromptController.updateAnchor(anchor)
            }
            lastSelectionSignature = signature
            return true
        }

        selectionRewritePromptController.show(near: anchor, selectedText: snapshot.text)
        lastSelectionSignature = signature
        return true
    }

    private func updateSelectionRewriteAnchorIfNeeded() {
        guard selectionRewritePromptController.isVisible,
              let request = activeSelectionRewriteRequest else {
            return
        }
        let anchor = selectionAnchorRect(for: request.element)
        selectionRewritePromptController.updateAnchor(anchor)
    }

    private func submitSelectionRewritePrompt(_ userPrompt: String) {
        guard let request = activeSelectionRewriteRequest else {
            selectionRewritePromptController.hide()
            return
        }

        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            selectionRewritePromptController.setStatus("Enter prompt", isError: true)
            return
        }

        selectionRewriteTask?.cancel()
        selectionRewritePromptController.setLoading(true)
        selectionRewritePromptController.setStatus("")

        selectionRewriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                await self.refreshConfiguration()
                let rewrite = try await self.cloudAPIManager.rewriteSelectedText(
                    selectedText: request.snapshot.text,
                    userInstruction: prompt,
                    maxTokens: max(128, self.maxTokens)
                )
                guard !Task.isCancelled else { return }

                let applied = await self.applyRewrittenSelection(rewrite, request: request)
                guard !Task.isCancelled else { return }

                if applied {
                    self.selectionRewritePromptController.hide()
                    self.activeSelectionRewriteRequest = nil
                    self.lastSelectionSignature = nil
                    self.suppressSelectionPromptUntil = Date().addingTimeInterval(0.9)
                } else {
                    self.selectionRewritePromptController.setLoading(false)
                    self.selectionRewritePromptController.setStatus("Selection changed or inaccessible", isError: true)
                }
            } catch is CancellationError {
                return
            } catch {
                self.selectionRewritePromptController.setLoading(false)
                self.selectionRewritePromptController.setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func cancelSelectionRewriteFlow() {
        selectionRewriteTask?.cancel()
        selectionRewriteTask = nil
        selectionRewritePromptController.hide()
        activeSelectionRewriteRequest = nil
        lastSelectionSignature = nil
    }

    private func applyRewrittenSelection(_ rewritten: String, request: SelectionRewriteRequest) async -> Bool {
        let normalizedRewrite = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRewrite.isEmpty else {
            return false
        }

        if focusedAppMonitor.currentAppPID != request.appPID,
           let targetApp = NSRunningApplication(processIdentifier: request.appPID) {
            targetApp.activate()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        if textInsertionService.replaceSelectedRangeViaAccessibility(
            text: normalizedRewrite,
            in: request.element,
            selectedRange: request.snapshot.range
        ) {
            return true
        }

        // Last fallback: restore selection range and paste.
        if textInsertionService.setSelectedRange(request.element, selectedRange: request.snapshot.range) {
            textInsertionService.insertViaClipboard(text: normalizedRewrite)
            return true
        }

        return false
    }

    private func selectionAnchorRect(for element: AXUIElement) -> NSRect {
        if let anchor = cursorResolver.caretAnchor(for: element)?.bounds {
            return anchor
        }
        if let input = cursorResolver.inputBounds(for: element) {
            return NSRect(
                x: input.minX + 16,
                y: max(input.minY + 6, input.maxY - 30),
                width: 2,
                height: 22
            )
        }
        if let screen = NSScreen.main?.visibleFrame {
            return NSRect(x: screen.midX, y: screen.midY, width: 2, height: 22)
        }
        return NSRect(x: 320, y: 320, width: 2, height: 22)
    }

    private func selectionSignature(_ snapshot: AccessibilityTextReader.SelectedTextSnapshot) -> String {
        "\(snapshot.range.location):\(snapshot.range.length):\(snapshot.text)"
    }

    // MARK: - Inference Trigger

    private func shouldTriggerInference(for context: TextContext) -> Bool {
        let wordCount = TextProcessor.wordCount(in: context.textBefore)
        guard wordCount > 0 else { return false }

        if hasSentenceBoundaryTrigger(context.textBefore) {
            return true
        }

        if isTypingRapidly {
            return false
        }

        if lastInferenceWordCount == 0 {
            return wordCount >= Constants.Limits.completionInferenceWordDelta
        }

        let delta = max(0, wordCount - lastInferenceWordCount)
        return delta >= Constants.Limits.completionInferenceWordDelta
    }

    private func resetInferenceState() {
        previousContext = nil
        lastInferenceWordCount = 0
        lastInferenceTextBefore = ""
        completionRequestSerial &+= 1
        resetTypingCadence()
        currentCompletionTask?.cancel()
    }

    private func isCurrentRequest(_ requestID: UInt64) -> Bool {
        requestID == completionRequestSerial
    }

    // MARK: - Settings

    private func reloadSettings() {
        let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
        APIKeyStore.migrateFromUserDefaultsIfNeeded(defaults)
        appOverridesStore.seedFromRunningApplications()

        let modeRaw = defaults.string(forKey: Constants.UserDefaultsKeys.completionMode) ?? "hybrid"
        completionMode = {
            switch modeRaw {
            case "localOnly": return .localOnly
            case "cloudOnly": return .cloudOnly
            default: return .hybrid
            }
        }()
        if !LocalModelManager.isAvailable, completionMode == .localOnly {
            completionMode = .hybrid
        }

        let providerRaw = defaults.string(forKey: Constants.UserDefaultsKeys.cloudProvider) ?? "openAI"
        cloudProvider = {
            switch providerRaw {
            case "anthropic": return .anthropic
            case "xAI": return .xAI
            case "openRouter": return .openRouter
            default: return .openAI
            }
        }()

        cloudModelIdentifier = defaults.string(forKey: Constants.UserDefaultsKeys.cloudModelIdentifier)
            ?? defaultCloudModel(for: cloudProvider)

        cloudAPIKey = APIKeyStore.read()

        debugLog("[AIComplete] Config: mode=\(modeRaw) provider=\(providerRaw) model=\(cloudModelIdentifier) hasKey=\(cloudAPIKey != nil) localModelAvailable=\(LocalModelManager.isAvailable)")

        let stylePrompt = defaults.string(forKey: Constants.UserDefaultsKeys.personalizationSystemPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        personalizationSystemPrompt = (stylePrompt?.isEmpty == false) ? stylePrompt : nil

        personalizationGoodCompletions = decodeStringList(defaults: defaults, key: Constants.UserDefaultsKeys.personalizationGoodCompletions)
        personalizationStyleInsights = decodeStringList(defaults: defaults, key: Constants.UserDefaultsKeys.personalizationStyleInsights)
        personalizationMemories = decodeMemoryTexts(defaults: defaults)

        localModelEnabled = (defaults.object(forKey: Constants.UserDefaultsKeys.localModelEnabled) as? Bool ?? true)
            && LocalModelManager.isAvailable

        let persistedCount = defaults.integer(forKey: Constants.UserDefaultsKeys.suggestionCount)
        suggestionCount = max(1, min(3, persistedCount == 0 ? 1 : persistedCount))
        let persistedMaxTokens = defaults.object(forKey: Constants.UserDefaultsKeys.maxTokens) as? Int ?? 24
        maxTokens = max(1, persistedMaxTokens)
        singleSuggestionAcceptMode = SingleSuggestionAcceptMode(
            storedValue: defaults.string(forKey: Constants.UserDefaultsKeys.singleSuggestionAcceptMode)
        )
        partialAcceptTrailingSpaceEnabled =
            defaults.object(forKey: Constants.UserDefaultsKeys.partialAcceptTrailingSpaceEnabled) as? Bool ?? true

        let triggerModeRaw = defaults.string(forKey: Constants.UserDefaultsKeys.suggestionTriggerMode) ?? "manualHotkey"
        suggestionTriggerMode = (triggerModeRaw == "manualHotkey") ? .manualHotkey : .automatic

        let persistedManualKeyCode = defaults.object(forKey: Constants.UserDefaultsKeys.manualTriggerKeyCode) as? Int ?? 49
        manualTriggerKeyCode = Int64(persistedManualKeyCode)

        let persistedManualModifiers = defaults.object(forKey: Constants.UserDefaultsKeys.manualTriggerModifiers) as? Int
            ?? Int(CGEventFlags.maskAlternate.rawValue)
        manualTriggerModifiersRaw = UInt64(max(0, persistedManualModifiers))

        let persistedPaletteNextKeyCode = defaults.object(forKey: Constants.UserDefaultsKeys.paletteNextKeyCode) as? Int ?? 125
        paletteNextKeyCode = Int64(persistedPaletteNextKeyCode)
        let persistedPaletteNextModifiers = defaults.object(forKey: Constants.UserDefaultsKeys.paletteNextModifiers) as? Int
            ?? Int(CGEventFlags.maskAlternate.rawValue)
        paletteNextModifiersRaw = UInt64(max(0, persistedPaletteNextModifiers))

        let persistedPalettePreviousKeyCode = defaults.object(forKey: Constants.UserDefaultsKeys.palettePreviousKeyCode) as? Int ?? 126
        palettePreviousKeyCode = Int64(persistedPalettePreviousKeyCode)
        let persistedPalettePreviousModifiers = defaults.object(forKey: Constants.UserDefaultsKeys.palettePreviousModifiers) as? Int
            ?? Int(CGEventFlags.maskAlternate.rawValue)
        palettePreviousModifiersRaw = UInt64(max(0, persistedPalettePreviousModifiers))

        eventTapManager.manualTriggerEnabled = suggestionTriggerMode == .manualHotkey
        eventTapManager.manualTriggerKeyCode = manualTriggerKeyCode
        eventTapManager.manualTriggerModifiers = CGEventFlags(rawValue: manualTriggerModifiersRaw)
        eventTapManager.paletteNextKeyCode = paletteNextKeyCode
        eventTapManager.paletteNextModifiers = CGEventFlags(rawValue: paletteNextModifiersRaw)
        eventTapManager.palettePreviousKeyCode = palettePreviousKeyCode
        eventTapManager.palettePreviousModifiers = CGEventFlags(rawValue: palettePreviousModifiersRaw)

        privacyModeEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.privacyModeEnabled)
    }

    private func refreshConfiguration() async {
        let cloudAllowed = !privacyModeEnabled

        let hybridConfig = HybridCompletionConfiguration(
            mode: completionMode,
            cloudAllowed: cloudAllowed,
            debounceMilliseconds: 0,
            cloudReplacementLengthDelta: 6
        )
        await hybridService.updateConfiguration(hybridConfig)

        let cloudConfig = CloudConfiguration(
            provider: cloudProvider,
            modelIdentifier: cloudModelIdentifier,
            apiKey: cloudAPIKey,
            networkEnabled: cloudAllowed,
            timeout: 20,
            userStylePrompt: personalizationSystemPrompt,
            userPatterns: personalizationGoodCompletions,
            userMemories: personalizationMemories,
            styleInsights: personalizationStyleInsights,
            goodCompletions: personalizationGoodCompletions,
            lexiconStyleSnippet: cachedLexiconSnippet.isEmpty ? nil : cachedLexiconSnippet
        )
        await cloudAPIManager.updateConfiguration(cloudConfig)
    }

    private func ensureLocalModelReadyIfNeeded() async {
        guard LocalModelManager.isAvailable else { return }
        guard localModelEnabled, completionMode != .cloudOnly else { return }
        guard !localModelLoadAttempted else { return }

        localModelLoadAttempted = true

        do {
            let modelsDir = try AppGroupManager.shared.modelsDirectoryURL(createIfMissing: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: modelsDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
            let selectedFileName = defaults.string(forKey: Constants.UserDefaultsKeys.selectedModelIdentifier)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let preferredFileName = Constants.LocalModels.preferredDefaultFileName
            let modelURL: URL?
            if let selectedFileName, !selectedFileName.isEmpty,
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
            // Silent fallback — local model unavailable
        }
    }

    // MARK: - Training Loop

    private func startTrainingLoop() {
        trainingTask?.cancel()
        trainingTask = Task {
            while !Task.isCancelled {
                _ = await TinyStyleTrainer.shared.runTrainingCycle(force: false)
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    // MARK: - Helpers

    private func shouldUseLiveCloudStream() -> Bool {
        guard completionMode != .localOnly else {
            return false
        }
        guard !privacyModeEnabled else {
            return false
        }

        guard let key = cloudAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return false
        }

        switch cloudProvider {
        case .openAI, .openRouter:
            return true
        case .anthropic, .xAI:
            return false
        }
    }

    private func requestCloudStreamingSuggestion(
        context: TextContext,
        element: AXUIElement,
        requestID: UInt64,
        manualInvocation: Bool
    ) async throws -> Completion? {
        var streamedRaw = ""

        let completions = try await cloudAPIManager.completeStreaming(
            context: context,
            maxTokens: maxTokens,
            count: 1
        ) { [weak self] delta in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isCurrentRequest(requestID) else { return }
                guard !self.shouldBlockRequestForManualMode(manualInvocation: manualInvocation) else { return }

                let normalizedDelta = self.normalizeStreamDelta(delta)
                guard !normalizedDelta.isEmpty else { return }

                streamedRaw += normalizedDelta
                let cleaned = self.stripReplacePrefix(streamedRaw)
                let display = TextProcessor.continuationSuffix(from: cleaned, after: context.textBefore)
                guard self.isMeaningfulSuggestion(display) else { return }

                let partial = Completion(
                    text: display,
                    confidence: 0.86,
                    source: .cloud,
                    type: .continuation,
                    replacementLength: 0
                )

                self.suggestionCoordinator.presentStreamedSuggestion(
                    partial,
                    near: element,
                    isLoading: true,
                    modelName: self.cloudModelIdentifier,
                    currentAppPID: self.focusedAppMonitor.currentAppPID,
                    geometryFallbackPolicy: self.geometryFallbackPolicy(for: element)
                )
            }
        }

        let prepared = completions
            .compactMap { prepareOverlayCompletion($0, context: context) }
            .first
        if let prepared {
            return prepared
        }

        let finalRaw = stripReplacePrefix(completions.first?.text ?? streamedRaw)
        guard !finalRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let fallback = Completion(
            text: finalRaw,
            confidence: 0.86,
            source: .cloud,
            type: .continuation,
            replacementLength: 0
        )
        return prepareOverlayCompletion(fallback, context: context)
    }

    private func stripReplacePrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("REPLACE:") else { return text }
        let afterPrefix = String(trimmed.dropFirst("REPLACE:".count))
        guard let colonIndex = afterPrefix.firstIndex(of: ":") else { return text }
        return String(afterPrefix[afterPrefix.index(after: colonIndex)...])
    }

    private func normalizeStreamDelta(_ delta: String) -> String {
        delta
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private func shouldBlockRequestForManualMode(manualInvocation: Bool) -> Bool {
        return suggestionTriggerMode == .manualHotkey && !manualInvocation
    }

    private func defaultCloudModel(for provider: CloudProvider) -> String {
        switch provider {
        case .openAI: return "gpt-4.1-nano"
        case .anthropic: return "claude-3-5-haiku-latest"
        case .xAI: return "grok-3-mini-beta"
        case .openRouter: return "google/gemini-2.5-flash"
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

    private func registerTypingCadence(previousText: String?, currentText: String) {
        let now = Date()
        defer { lastTypingEventAt = now }

        guard let previousText, previousText != currentText else { return }

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

    private func isMeaningfulSuggestion(_ rawText: String) -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.count < 2 { return false }

        let letterOrDigitSet = CharacterSet.letters.union(.decimalDigits)
        guard trimmed.rangeOfCharacter(from: letterOrDigitSet) != nil else {
            return false
        }

        let punctuationSet = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        if trimmed.unicodeScalars.allSatisfy({ punctuationSet.contains($0) }) {
            return false
        }

        return true
    }

    private func resetTypingCadence() {
        lastTypingEventAt = nil
        typingSpeedEMA = 0
        rapidTypingStreak = 0
    }

    private func sourceName(_ source: CompletionSource) -> String {
        switch source {
        case .local: return "local"
        case .cloud: return "cloud"
        case .hybrid: return "hybrid"
        case .userDictionary: return "userDictionary"
        }
    }

    private func logDecision(
        decision: String,
        reason: String,
        appBundleID: String? = nil,
        source: String = "n/a",
        targetClass: String = "n/a",
        strategy: String = "n/a"
    ) {
        let bundle = appBundleID ?? focusedAppMonitor.currentAppBundleID ?? "nil"
        let pid = focusedAppMonitor.currentAppPID
        decisionLogger.notice(
            "decision=\(decision, privacy: .public) reason=\(reason, privacy: .public) app=\(bundle, privacy: .public) pid=\(pid, privacy: .public) source=\(source, privacy: .public) class=\(targetClass, privacy: .public) strategy=\(strategy, privacy: .public)"
        )
    }

    private func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
        NSLog(message())
#endif
    }
}

private struct StoredMemoryItem: Codable {
    let id: UUID
    let text: String
    let createdAt: Date
}
