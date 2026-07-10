import ApplicationServices
import Foundation

struct SuggestionRequestGate {
    private var generation: UInt64 = 0

    mutating func beginRequest() -> UInt64 {
        generation &+= 1
        return generation
    }

    mutating func invalidate() {
        generation &+= 1
    }

    func isCurrent(_ request: UInt64) -> Bool {
        request == generation
    }
}

@MainActor
final class SuggestionCoordinator {
    private let panelController: SuggestionPanelController
    private let eventTapManager: EventTapManager
    private let debugLog: (String) -> Void

    private(set) var activeSuggestionPID: pid_t?
    private(set) var currentCompletion: Completion?
    private(set) var currentCompletions: [Completion] = []
    private(set) var selectedSuggestionIndex = 0

    init(
        panelController: SuggestionPanelController,
        eventTapManager: EventTapManager,
        debugLog: @escaping (String) -> Void
    ) {
        self.panelController = panelController
        self.eventTapManager = eventTapManager
        self.debugLog = debugLog
    }

    func showLoading(
        near element: AXUIElement,
        geometryFallbackPolicy: GeometryFallbackPolicy
    ) {
        clearState()
        panelController.showLoading(
            near: element,
            geometryFallbackPolicy: geometryFallbackPolicy
        )
    }

    func presentSuggestions(
        _ completions: [Completion],
        limit: Int,
        near element: AXUIElement,
        isLoading: Bool,
        source: CompletionSource,
        confidence: Double,
        modelName: String?,
        currentAppPID: pid_t,
        geometryFallbackPolicy: GeometryFallbackPolicy
    ) {
        let normalized = normalizedCompletions(from: completions, limit: limit)
        guard !normalized.isEmpty else {
            reset()
            return
        }

        currentCompletions = normalized
        selectedSuggestionIndex = min(max(0, selectedSuggestionIndex), normalized.count - 1)
        currentCompletion = normalized[selectedSuggestionIndex]
        panelController.show(
            suggestions: normalized.map(\.text),
            selectedIndex: selectedSuggestionIndex,
            near: element,
            isLoading: isLoading,
            source: source,
            confidence: confidence,
            modelName: modelName,
            geometryFallbackPolicy: geometryFallbackPolicy
        )
        markSuggestionVisible(currentAppPID: currentAppPID)
    }

    func presentStreamedSuggestion(
        _ completion: Completion,
        near element: AXUIElement,
        isLoading: Bool,
        modelName: String?,
        currentAppPID: pid_t,
        geometryFallbackPolicy: GeometryFallbackPolicy
    ) {
        currentCompletions = [completion]
        selectedSuggestionIndex = 0
        currentCompletion = completion
        panelController.show(
            suggestions: [completion.text],
            selectedIndex: 0,
            near: element,
            isLoading: isLoading,
            source: completion.source,
            confidence: completion.confidence,
            modelName: modelName,
            geometryFallbackPolicy: geometryFallbackPolicy
        )
        markSuggestionVisible(currentAppPID: currentAppPID)
    }

    func presentRemainingPartialSuggestion(
        _ completion: Completion,
        near element: AXUIElement,
        modelName: String?,
        currentAppPID: pid_t,
        geometryFallbackPolicy: GeometryFallbackPolicy
    ) {
        presentStreamedSuggestion(
            completion,
            near: element,
            isLoading: false,
            modelName: modelName,
            currentAppPID: currentAppPID,
            geometryFallbackPolicy: geometryFallbackPolicy
        )
    }

    @discardableResult
    func cycleSelection(
        by delta: Int,
        forEventTargetPID targetPID: pid_t?,
        currentFocusedAppPID: pid_t
    ) -> Bool {
        guard canInteractWithSuggestionPalette(
            forEventTargetPID: targetPID,
            currentFocusedAppPID: currentFocusedAppPID
        ) else {
            return false
        }
        guard currentCompletions.count > 1 else {
            return false
        }

        let count = currentCompletions.count
        let nextIndex = (selectedSuggestionIndex + delta % count + count) % count
        selectedSuggestionIndex = nextIndex
        currentCompletion = currentCompletions[nextIndex]
        panelController.updateSelection(index: nextIndex)
        return true
    }

    @discardableResult
    func selectSuggestion(
        at index: Int,
        forEventTargetPID targetPID: pid_t?,
        currentFocusedAppPID: pid_t
    ) -> Bool {
        guard canInteractWithSuggestionPalette(
            forEventTargetPID: targetPID,
            currentFocusedAppPID: currentFocusedAppPID
        ) else {
            return false
        }
        guard currentCompletions.indices.contains(index) else {
            return false
        }

        selectedSuggestionIndex = index
        currentCompletion = currentCompletions[index]
        panelController.updateSelection(index: index)
        return true
    }

    func canInteractWithSuggestionPalette(
        forEventTargetPID targetPID: pid_t?,
        currentFocusedAppPID: pid_t
    ) -> Bool {
        guard eventTapManager.isSuggestionVisible, currentCompletion != nil else {
            return false
        }
        guard let suggestionPID = activeSuggestionPID else {
            return false
        }
        if let targetPID, targetPID != suggestionPID {
            debugLog("[AIComplete] Ignoring palette interaction: event target PID \(targetPID) != suggestion PID \(suggestionPID)")
            return false
        }
        if currentFocusedAppPID != 0, currentFocusedAppPID != suggestionPID {
            debugLog("[AIComplete] Ignoring palette interaction: focused app PID changed (current=\(currentFocusedAppPID), suggestion=\(suggestionPID))")
            return false
        }
        return true
    }

    func reset() {
        panelController.hide()
        clearState()
    }

    private func markSuggestionVisible(currentAppPID: pid_t) {
        activeSuggestionPID = currentAppPID
        eventTapManager.isSuggestionVisible = true
    }

    private func clearState() {
        eventTapManager.isSuggestionVisible = false
        currentCompletion = nil
        currentCompletions = []
        selectedSuggestionIndex = 0
        activeSuggestionPID = nil
    }

    private func normalizedCompletions(from completions: [Completion], limit: Int) -> [Completion] {
        var seen = Set<String>()
        var normalized: [Completion] = []

        for completion in completions {
            let key = "\(completion.type)|\(completion.replacementLength)|\(completion.text)"
            guard seen.insert(key).inserted else { continue }
            normalized.append(completion)
            if normalized.count >= max(1, limit) {
                break
            }
        }

        return normalized
    }
}
