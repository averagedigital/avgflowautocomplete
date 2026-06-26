import ApplicationServices
import Foundation

enum InsertionRoute: String {
    case accessibility
    case clipboardFallback
    case blockedSecure
    case blockedByPolicy
}

struct InsertionResult {
    let succeeded: Bool
    let route: InsertionRoute
    let targetClass: TargetAppClass
    let reason: String
}

final class AcceptanceSynthesizer {
    private let textInsertionService: TextInsertionService
    private let compatibilityLayer: AppCompatibilityLayer

    init(
        textInsertionService: TextInsertionService,
        compatibilityLayer: AppCompatibilityLayer
    ) {
        self.textInsertionService = textInsertionService
        self.compatibilityLayer = compatibilityLayer
    }

    func partialAcceptance(
        for completion: Completion,
        currentCompletionsCount: Int,
        acceptMode: SingleSuggestionAcceptMode,
        includeTrailingWhitespace: Bool
    ) -> (chunk: String, remainingText: String)? {
        guard currentCompletionsCount == 1,
              completion.type == .continuation,
              acceptMode == .nextWord else {
            return nil
        }

        let chunk = TextProcessor.partialAcceptanceChunk(
            from: completion.text,
            includeTrailingWhitespace: includeTrailingWhitespace
        )
        let remainingText = TextProcessor.remainingTextAfterPartialAcceptance(
            from: completion.text,
            includeTrailingWhitespace: includeTrailingWhitespace
        )
        guard !chunk.isEmpty else {
            return nil
        }
        return (chunk, remainingText)
    }

    func updatedContextAfterPartialAcceptance(
        previousContext: TextContext?,
        chunk: String
    ) -> TextContext? {
        guard let previousContext else {
            return nil
        }
        return TextContext(
            textBefore: previousContext.textBefore + chunk,
            textAfter: previousContext.textAfter,
            appIdentifier: previousContext.appIdentifier,
            language: previousContext.language,
            lexiconStyleSnippet: previousContext.lexiconStyleSnippet
        )
    }

    func insertCompletionText(
        _ completion: Completion,
        into element: AXUIElement,
        appBundleID: String?,
        currentAppPID: pid_t,
        activeSuggestionPID: pid_t?,
        textReader: AccessibilityTextReader
    ) -> InsertionResult {
        let targetClass = compatibilityLayer.classifyTargetAppClass(
            for: element,
            appBundleID: appBundleID,
            textReader: textReader
        )

        if targetClass == .secure {
            return InsertionResult(
                succeeded: false,
                route: .blockedSecure,
                targetClass: targetClass,
                reason: "secure_context"
            )
        }

        let insertedViaAX = textInsertionService.insertViaAccessibility(
            text: completion.text,
            into: element,
            replacementLength: completion.replacementLength
        )
        if insertedViaAX {
            return InsertionResult(
                succeeded: true,
                route: .accessibility,
                targetClass: targetClass,
                reason: "ax_success"
            )
        }

        guard compatibilityLayer.allowsClipboardFallback(for: targetClass) else {
            return InsertionResult(
                succeeded: false,
                route: .blockedByPolicy,
                targetClass: targetClass,
                reason: "clipboard_policy_blocked"
            )
        }

        if let activeSuggestionPID,
           currentAppPID != 0,
           currentAppPID != activeSuggestionPID {
            return InsertionResult(
                succeeded: false,
                route: .blockedByPolicy,
                targetClass: targetClass,
                reason: "clipboard_pid_mismatch"
            )
        }

        textInsertionService.insertViaClipboard(text: completion.text)
        return InsertionResult(
            succeeded: true,
            route: .clipboardFallback,
            targetClass: targetClass,
            reason: "clipboard_fallback"
        )
    }
}
