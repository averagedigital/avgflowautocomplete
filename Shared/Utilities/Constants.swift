import Foundation

enum Constants {
    // MARK: - App Group

    enum AppGroup {
        static let identifier = "group.com.aicomplete.shared"
        static let suiteName = identifier
        static let sharedRootDirectoryName = "AICompleteShared"
        static let documentsDirectoryName = "Documents"
        static let modelsDirectoryName = "models"
    }

    // MARK: - Keychain

    enum Keychain {
        static let accessGroupSuffix = "com.aicomplete.shared"
    }

    // MARK: - Storage

    enum Storage {
        static let coreDataModelName = "AIComplete"
        static let sqliteFileName = "AIComplete.sqlite"
        static let lexiconSQLiteFileName = "PersonalLexicon.sqlite"
        static let tinyStyleWeightsFileName = "TinyStyleLM.json"
        static let tinyStyleReplayBufferFileName = "TinyStyleReplayBuffer.json"
        static let tinyStyleEventsFileName = "TinyStyleEvents.json"
    }

    // MARK: - Local Models

    enum LocalModels {
        static let preferredDefaultFileName = "gemma-3-1b-it-Q4_K_M.gguf"
    }

    // MARK: - User Defaults Keys

    enum UserDefaultsKeys {
        static let completionMode = "settings.completionMode"
        static let cloudProvider = "settings.cloudProvider"
        static let cloudModelIdentifier = "settings.cloudModelIdentifier"
        static let maxTokens = "settings.maxTokens"
        static let suggestionTriggerMode = "settings.suggestionTriggerMode"
        static let manualTriggerKeyCode = "settings.manualTriggerKeyCode"
        static let manualTriggerModifiers = "settings.manualTriggerModifiers"
        static let paletteNextKeyCode = "settings.paletteNextKeyCode"
        static let paletteNextModifiers = "settings.paletteNextModifiers"
        static let palettePreviousKeyCode = "settings.palettePreviousKeyCode"
        static let palettePreviousModifiers = "settings.palettePreviousModifiers"
        static let apiKey = "settings.apiKey"
        static let suggestionCount = "settings.suggestionCount"
        static let singleSuggestionAcceptMode = "settings.singleSuggestionAcceptMode"
        static let partialAcceptTrailingSpaceEnabled = "settings.partialAcceptTrailingSpaceEnabled"
        static let languageMode = "settings.languageMode"
        static let privacyModeEnabled = "settings.privacyModeEnabled"
        static let localModelEnabled = "settings.localModelEnabled"
        static let personalizationSystemPrompt = "personalization.systemPrompt"
        static let personalizationUserMemories = "personalization.userMemories"
        static let personalizationGoodCompletions = "personalization.goodCompletions"
        static let personalizationStyleInsights = "personalization.styleInsights"
        static let selectedModelIdentifier = "settings.selectedModelIdentifier"
        static let userDictionaryLastDecayDate = "personalization.userDictionaryLastDecayDate"
        static let contextHistoryEntries = "personalization.contextHistoryEntries"
        static let lexiconStyleStats = "personalization.lexiconStyleStats"
        static let guideCompleted = "onboarding.guideCompleted"
        static let appLanguage = "settings.appLanguage"
        static let acceptedCompletionCount = "analytics.acceptedCompletionCount"
        static let totalTypedCharacters = "analytics.totalTypedCharacters"
        static let lastLLMAnalysis = "analytics.lastLLMAnalysis"
        static let customContinuationPrompt = "settings.customContinuationPrompt"
        static let customReplacementPrompt = "settings.customReplacementPrompt"
        static let replacementModeEnabled = "settings.replacementModeEnabled"
        static let promptRevision = "settings.promptRevision"
        static let totalSuggestionsShown = "analytics.totalSuggestionsShown"
        static let appOverrideRecords = "settings.appOverrideRecords"
    }

    // MARK: - Limits

    enum Limits {
        static let contextBeforeCharacterLimit = 500
        static let contextAfterCharacterLimit = 200
        static let userDictionaryContextPrefixLimit = 50
        static let maxPromptPatterns = 5
        static let maxGoodCompletions = 5
        static let completionInferenceWordDelta = 2
    }
}
