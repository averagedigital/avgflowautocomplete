import Combine
import CoreGraphics
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    struct MemoryItem: Codable, Identifiable, Hashable {
        let id: UUID
        let text: String
        let createdAt: Date
    }

    struct CloudModelOption: Identifiable, Hashable {
        let id: String
        let title: String
        let detail: String
    }

    enum CompletionModeOption: String, CaseIterable, Identifiable {
        case localOnly
        case cloudOnly
        case hybrid

        var id: String { rawValue }

        var title: String {
            switch self {
            case .localOnly:
                return "Local Only"
            case .cloudOnly:
                return "Cloud Only"
            case .hybrid:
                return "Hybrid"
            }
        }

        var engineMode: CompletionMode {
            switch self {
            case .localOnly:
                return .localOnly
            case .cloudOnly:
                return .cloudOnly
            case .hybrid:
                return .hybrid
            }
        }
    }

    enum CloudProviderOption: String, CaseIterable, Identifiable {
        case openAI
        case anthropic
        case xAI
        case openRouter

        var id: String { rawValue }

        var title: String {
            switch self {
            case .openAI:
                return "OpenAI"
            case .anthropic:
                return "Anthropic"
            case .xAI:
                return "Grok (xAI)"
            case .openRouter:
                return "OpenRouter"
            }
        }

        var provider: CloudProvider {
            switch self {
            case .openAI:
                return .openAI
            case .anthropic:
                return .anthropic
            case .xAI:
                return .xAI
            case .openRouter:
                return .openRouter
            }
        }
    }

    enum LanguageModeOption: String, CaseIterable, Identifiable {
        case auto
        case russian
        case english
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto:
                return "Auto"
            case .russian:
                return "Russian"
            case .english:
                return "English"
            case .both:
                return "Both"
            }
        }
    }

    enum SuggestionTriggerModeOption: String, CaseIterable, Identifiable {
        case automatic
        case manualHotkey

        var id: String { rawValue }
    }

    struct ManualTriggerHotkeyOption: Identifiable, Hashable {
        let id: String
        let title: String
        let keyCode: Int
        let modifiersRaw: UInt64
    }

    @Published var completionMode: CompletionModeOption {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var cloudProvider: CloudProviderOption {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var apiKey: String {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var maxTokensInput: String {
        didSet {
            let digitsOnly = maxTokensInput.filter(\.isWholeNumber)
            if digitsOnly != maxTokensInput {
                maxTokensInput = digitsOnly
                return
            }
            updateEngineSettingsDirtyState()
        }
    }

    @Published var cloudModelIdentifier: String {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var localModelEnabled: Bool {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var languageMode: LanguageModeOption {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var suggestionTriggerMode: SuggestionTriggerModeOption {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var suggestionCount: Int {
        didSet {
            let clamped = min(3, max(1, suggestionCount))
            if suggestionCount != clamped {
                suggestionCount = clamped
                return
            }
            updateEngineSettingsDirtyState()
        }
    }

    @Published var singleSuggestionAcceptMode: SingleSuggestionAcceptMode {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var partialAcceptTrailingSpaceEnabled: Bool {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var manualTriggerHotkeyID: String {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var paletteNextHotkeyID: String {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published var palettePreviousHotkeyID: String {
        didSet { updateEngineSettingsDirtyState() }
    }

    @Published private(set) var engineSettingsDirty: Bool = false
    @Published private(set) var promptSettingsDirty: Bool = false


    @Published var privacyModeEnabled: Bool {
        didSet {
            if privacyModeEnabled {
                completionMode = .localOnly
            }
            updateEngineSettingsDirtyState()
        }
    }

    @Published var systemPrompt: String {
        didSet { updatePromptSettingsDirtyState() }
    }

    @Published var customContinuationPrompt: String {
        didSet { updatePromptSettingsDirtyState() }
    }

    @Published var customReplacementPrompt: String {
        didSet { updatePromptSettingsDirtyState() }
    }

    @Published var replacementModeEnabled: Bool {
        didSet { updatePromptSettingsDirtyState() }
    }

    @Published var selectedPromptTab: Int = 0

    @Published var memoryInput: String = ""
    @Published private(set) var memories: [MemoryItem] = []
    @Published private(set) var goodCompletions: [String] = []
    @Published private(set) var styleInsights: [String] = []
    @Published private(set) var tinyStyleStatus: String = "TinyStyleLM: waiting for training data"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var defaultsObserver: NSObjectProtocol?
    private var lastKnownPromptRevision: TimeInterval = 0
    private var appliedCompletionMode: CompletionModeOption = .hybrid
    private var appliedCloudProvider: CloudProviderOption = .openAI
    private var appliedAPIKey: String = ""
    private var appliedMaxTokensInput: String = "24"
    private var appliedCloudModelIdentifier: String = "gpt-4.1-nano"
    private var appliedLocalModelEnabled: Bool = true
    private var appliedLanguageMode: LanguageModeOption = .auto
    private var appliedSuggestionTriggerMode: SuggestionTriggerModeOption = .automatic
    private var appliedSuggestionCount: Int = 1
    private var appliedSingleSuggestionAcceptMode: SingleSuggestionAcceptMode = .nextWord
    private var appliedPartialAcceptTrailingSpaceEnabled: Bool = true
    private var appliedManualTriggerHotkeyID: String = "opt_space"
    private var appliedPaletteNextHotkeyID: String = "opt_down"
    private var appliedPalettePreviousHotkeyID: String = "opt_up"
    private var appliedPrivacyModeEnabled: Bool = false
    private var appliedSystemPrompt: String = SystemPrompts.defaultStarterProfile
    private var appliedCustomContinuationPrompt: String = ""
    private var appliedCustomReplacementPrompt: String = ""
    private var appliedReplacementModeEnabled: Bool = false

    init(defaults: UserDefaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard) {
        self.defaults = defaults
        APIKeyStore.migrateFromUserDefaultsIfNeeded(defaults)

        let storedMode = CompletionModeOption(
            rawValue: defaults.string(forKey: Constants.UserDefaultsKeys.completionMode) ?? "hybrid"
        ) ?? .hybrid
        completionMode = (!LocalModelManager.isAvailable && storedMode == .localOnly) ? .hybrid : storedMode
        let initialProvider = CloudProviderOption(rawValue: defaults.string(forKey: Constants.UserDefaultsKeys.cloudProvider) ?? "openAI") ?? .openAI
        cloudProvider = initialProvider
        apiKey = APIKeyStore.read() ?? ""
        let storedMaxTokens = defaults.object(forKey: Constants.UserDefaultsKeys.maxTokens) as? Int ?? 24
        maxTokensInput = String(max(1, storedMaxTokens))
        cloudModelIdentifier = defaults.string(forKey: Constants.UserDefaultsKeys.cloudModelIdentifier) ?? SettingsViewModel.defaultCloudModel(for: initialProvider)
        localModelEnabled = defaults.object(forKey: Constants.UserDefaultsKeys.localModelEnabled) as? Bool ?? true
        languageMode = LanguageModeOption(rawValue: defaults.string(forKey: Constants.UserDefaultsKeys.languageMode) ?? "auto") ?? .auto
        suggestionTriggerMode = SuggestionTriggerModeOption(
            rawValue: defaults.string(forKey: Constants.UserDefaultsKeys.suggestionTriggerMode) ?? "manualHotkey"
        ) ?? .manualHotkey
        let storedSuggestionCount = defaults.object(forKey: Constants.UserDefaultsKeys.suggestionCount) as? Int ?? 1
        suggestionCount = min(3, max(1, storedSuggestionCount))
        singleSuggestionAcceptMode = SingleSuggestionAcceptMode(
            storedValue: defaults.string(forKey: Constants.UserDefaultsKeys.singleSuggestionAcceptMode)
        )
        partialAcceptTrailingSpaceEnabled =
            defaults.object(forKey: Constants.UserDefaultsKeys.partialAcceptTrailingSpaceEnabled) as? Bool ?? true
        let storedManualKeyCode = defaults.object(forKey: Constants.UserDefaultsKeys.manualTriggerKeyCode) as? Int ?? 49
        let storedManualModifiers = defaults.object(forKey: Constants.UserDefaultsKeys.manualTriggerModifiers) as? Int
            ?? Int(CGEventFlags.maskAlternate.rawValue)
        manualTriggerHotkeyID = Self.resolveManualHotkeyID(
            keyCode: storedManualKeyCode,
            modifiersRaw: UInt64(max(0, storedManualModifiers))
        )
        let storedPaletteNextKeyCode = defaults.object(forKey: Constants.UserDefaultsKeys.paletteNextKeyCode) as? Int ?? 125
        let storedPaletteNextModifiers = defaults.object(forKey: Constants.UserDefaultsKeys.paletteNextModifiers) as? Int
            ?? Int(CGEventFlags.maskAlternate.rawValue)
        paletteNextHotkeyID = Self.resolvePaletteNavigationHotkeyID(
            keyCode: storedPaletteNextKeyCode,
            modifiersRaw: UInt64(max(0, storedPaletteNextModifiers)),
            fallbackID: "opt_down"
        )
        let storedPalettePreviousKeyCode = defaults.object(forKey: Constants.UserDefaultsKeys.palettePreviousKeyCode) as? Int ?? 126
        let storedPalettePreviousModifiers = defaults.object(forKey: Constants.UserDefaultsKeys.palettePreviousModifiers) as? Int
            ?? Int(CGEventFlags.maskAlternate.rawValue)
        palettePreviousHotkeyID = Self.resolvePaletteNavigationHotkeyID(
            keyCode: storedPalettePreviousKeyCode,
            modifiersRaw: UInt64(max(0, storedPalettePreviousModifiers)),
            fallbackID: "opt_up"
        )
        privacyModeEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.privacyModeEnabled)
        let storedSystemPrompt = defaults.string(forKey: Constants.UserDefaultsKeys.personalizationSystemPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSystemPrompt = (storedSystemPrompt?.isEmpty == false)
            ? storedSystemPrompt!
            : SystemPrompts.defaultStarterProfile
        systemPrompt = resolvedSystemPrompt
        customContinuationPrompt = defaults.string(forKey: Constants.UserDefaultsKeys.customContinuationPrompt) ?? ""
        customReplacementPrompt = defaults.string(forKey: Constants.UserDefaultsKeys.customReplacementPrompt) ?? ""
        replacementModeEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.replacementModeEnabled)

        if storedSystemPrompt?.isEmpty != false {
            defaults.set(resolvedSystemPrompt, forKey: Constants.UserDefaultsKeys.personalizationSystemPrompt)
        }

        if !Self.cloudModels(for: cloudProvider).contains(where: { $0.id == cloudModelIdentifier }) {
            cloudModelIdentifier = Self.defaultCloudModel(for: cloudProvider)
        }
        captureAppliedEngineSettings()
        captureAppliedPromptSettings()
        lastKnownPromptRevision = defaults.double(forKey: Constants.UserDefaultsKeys.promptRevision)
        engineSettingsDirty = false
        promptSettingsDirty = false
        observeDefaultsChanges()

        Task { [weak self] in
            await self?.reloadMemories()
            await self?.reloadPersonalizationSignals()
            await self?.reloadTinyStyleStatus()
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func clearUserDictionary() async {
        await PersonalizationManager().clearAll()
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.personalizationUserMemories)
        await reloadMemories()
        await reloadPersonalizationSignals()
    }

    func manualHotkeyOptions() -> [ManualTriggerHotkeyOption] {
        Self.manualHotkeyOptions
    }

    func paletteNavigationHotkeyOptions() -> [ManualTriggerHotkeyOption] {
        Self.paletteNavigationHotkeyOptions
    }

    func handleProviderChanged() {
        if !Self.cloudModels(for: cloudProvider).contains(where: { $0.id == cloudModelIdentifier }) {
            cloudModelIdentifier = Self.defaultCloudModel(for: cloudProvider)
        }
        updateEngineSettingsDirtyState()
    }

    func addMemory() async {
        let normalized = memoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        var list = loadMemories()
        if list.contains(where: { $0.text.caseInsensitiveCompare(normalized) == .orderedSame }) {
            memoryInput = ""
            return
        }

        list.insert(.init(id: UUID(), text: normalized, createdAt: Date()), at: 0)
        if list.count > 100 {
            list = Array(list.prefix(100))
        }
        saveMemories(list)
        memoryInput = ""
        await reloadMemories()
    }

    func deleteMemory(id: UUID) async {
        var list = loadMemories()
        list.removeAll { $0.id == id }
        saveMemories(list)
        await reloadMemories()
    }

    func reloadMemories() async {
        memories = loadMemories()
    }

    func reloadPersonalizationSignals() async {
        goodCompletions = decodeStringList(forKey: Constants.UserDefaultsKeys.personalizationGoodCompletions)
        styleInsights = decodeStringList(forKey: Constants.UserDefaultsKeys.personalizationStyleInsights)
    }

    func runTinyStyleTrainingNow() async {
        await TinyStyleTrainer.shared.restore()
        let metrics = await TinyStyleTrainer.shared.runTrainingCycle(force: true)
        if let metrics {
            tinyStyleStatus = String(
                format: "TinyStyleLM step %d • loss %.3f → %.3f",
                metrics.step,
                metrics.lossBefore,
                metrics.lossAfter
            )
        } else {
            tinyStyleStatus = "TinyStyleLM: not enough accepted samples yet"
        }
    }

    func reloadTinyStyleStatus() async {
        if let metrics = await TinyStyleTrainer.shared.latestTrainingMetrics() {
            tinyStyleStatus = String(
                format: "TinyStyleLM step %d • loss %.3f → %.3f",
                metrics.step,
                metrics.lossBefore,
                metrics.lossAfter
            )
        } else {
            tinyStyleStatus = "TinyStyleLM: waiting for training data"
        }
    }

    func forceApplyPromptSettings() {
        let continuation = customContinuationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = customReplacementPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSystem = system.isEmpty ? SystemPrompts.defaultStarterProfile : system
        let revision = Date().timeIntervalSince1970

        defaults.set(continuation, forKey: Constants.UserDefaultsKeys.customContinuationPrompt)
        defaults.set(replacement, forKey: Constants.UserDefaultsKeys.customReplacementPrompt)
        defaults.set(resolvedSystem, forKey: Constants.UserDefaultsKeys.personalizationSystemPrompt)
        defaults.set(replacementModeEnabled, forKey: Constants.UserDefaultsKeys.replacementModeEnabled)
        defaults.set(revision, forKey: Constants.UserDefaultsKeys.promptRevision)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        NotificationCenter.default.post(name: .aiCompleteSettingsChanged, object: nil)
        lastKnownPromptRevision = revision

        // Keep editor fields exactly in sync with applied values.
        systemPrompt = resolvedSystem
        customContinuationPrompt = continuation
        customReplacementPrompt = replacement
        captureAppliedPromptSettings()
        updatePromptSettingsDirtyState()
    }

    func forceApplyEngineSettings() {
        let persistedMode: CompletionModeOption =
            (!LocalModelManager.isAvailable && completionMode == .localOnly) ? .hybrid : completionMode
        defaults.set(persistedMode.rawValue, forKey: Constants.UserDefaultsKeys.completionMode)
        defaults.set(cloudProvider.rawValue, forKey: Constants.UserDefaultsKeys.cloudProvider)
        if let parsedMaxTokens = Int(maxTokensInput), parsedMaxTokens > 0 {
            defaults.set(parsedMaxTokens, forKey: Constants.UserDefaultsKeys.maxTokens)
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = APIKeyStore.delete()
        } else {
            _ = APIKeyStore.save(apiKey)
        }
        defaults.set(cloudModelIdentifier, forKey: Constants.UserDefaultsKeys.cloudModelIdentifier)
        defaults.set(localModelEnabled, forKey: Constants.UserDefaultsKeys.localModelEnabled)
        defaults.set(languageMode.rawValue, forKey: Constants.UserDefaultsKeys.languageMode)
        defaults.set(suggestionTriggerMode.rawValue, forKey: Constants.UserDefaultsKeys.suggestionTriggerMode)
        defaults.set(suggestionCount, forKey: Constants.UserDefaultsKeys.suggestionCount)
        defaults.set(singleSuggestionAcceptMode.rawValue, forKey: Constants.UserDefaultsKeys.singleSuggestionAcceptMode)
        defaults.set(
            partialAcceptTrailingSpaceEnabled,
            forKey: Constants.UserDefaultsKeys.partialAcceptTrailingSpaceEnabled
        )
        if let manualHotkey = Self.manualHotkeyOptions.first(where: { $0.id == manualTriggerHotkeyID }) {
            defaults.set(manualHotkey.keyCode, forKey: Constants.UserDefaultsKeys.manualTriggerKeyCode)
            defaults.set(Int(manualHotkey.modifiersRaw), forKey: Constants.UserDefaultsKeys.manualTriggerModifiers)
        }
        if let nextHotkey = Self.paletteNavigationHotkeyOptions.first(where: { $0.id == paletteNextHotkeyID }) {
            defaults.set(nextHotkey.keyCode, forKey: Constants.UserDefaultsKeys.paletteNextKeyCode)
            defaults.set(Int(nextHotkey.modifiersRaw), forKey: Constants.UserDefaultsKeys.paletteNextModifiers)
        }
        if let previousHotkey = Self.paletteNavigationHotkeyOptions.first(where: { $0.id == palettePreviousHotkeyID }) {
            defaults.set(previousHotkey.keyCode, forKey: Constants.UserDefaultsKeys.palettePreviousKeyCode)
            defaults.set(Int(previousHotkey.modifiersRaw), forKey: Constants.UserDefaultsKeys.palettePreviousModifiers)
        }
        defaults.set(privacyModeEnabled, forKey: Constants.UserDefaultsKeys.privacyModeEnabled)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        NotificationCenter.default.post(name: .aiCompleteSettingsChanged, object: nil)

        completionMode = persistedMode
        captureAppliedEngineSettings()
        updateEngineSettingsDirtyState()
    }

    private func captureAppliedEngineSettings() {
        appliedCompletionMode = completionMode
        appliedCloudProvider = cloudProvider
        appliedAPIKey = apiKey
        appliedMaxTokensInput = maxTokensInput
        appliedCloudModelIdentifier = cloudModelIdentifier
        appliedLocalModelEnabled = localModelEnabled
        appliedLanguageMode = languageMode
        appliedSuggestionTriggerMode = suggestionTriggerMode
        appliedSuggestionCount = suggestionCount
        appliedSingleSuggestionAcceptMode = singleSuggestionAcceptMode
        appliedPartialAcceptTrailingSpaceEnabled = partialAcceptTrailingSpaceEnabled
        appliedManualTriggerHotkeyID = manualTriggerHotkeyID
        appliedPaletteNextHotkeyID = paletteNextHotkeyID
        appliedPalettePreviousHotkeyID = palettePreviousHotkeyID
        appliedPrivacyModeEnabled = privacyModeEnabled
    }

    private func captureAppliedPromptSettings() {
        appliedSystemPrompt = systemPrompt
        appliedCustomContinuationPrompt = customContinuationPrompt
        appliedCustomReplacementPrompt = customReplacementPrompt
        appliedReplacementModeEnabled = replacementModeEnabled
    }

    private func updateEngineSettingsDirtyState() {
        engineSettingsDirty = completionMode != appliedCompletionMode
            || cloudProvider != appliedCloudProvider
            || apiKey != appliedAPIKey
            || maxTokensInput != appliedMaxTokensInput
            || cloudModelIdentifier != appliedCloudModelIdentifier
            || localModelEnabled != appliedLocalModelEnabled
            || languageMode != appliedLanguageMode
            || suggestionTriggerMode != appliedSuggestionTriggerMode
            || suggestionCount != appliedSuggestionCount
            || singleSuggestionAcceptMode != appliedSingleSuggestionAcceptMode
            || partialAcceptTrailingSpaceEnabled != appliedPartialAcceptTrailingSpaceEnabled
            || manualTriggerHotkeyID != appliedManualTriggerHotkeyID
            || paletteNextHotkeyID != appliedPaletteNextHotkeyID
            || palettePreviousHotkeyID != appliedPalettePreviousHotkeyID
            || privacyModeEnabled != appliedPrivacyModeEnabled
    }

    private func updatePromptSettingsDirtyState() {
        promptSettingsDirty = systemPrompt != appliedSystemPrompt
            || customContinuationPrompt != appliedCustomContinuationPrompt
            || customReplacementPrompt != appliedCustomReplacementPrompt
            || replacementModeEnabled != appliedReplacementModeEnabled
    }

    private func observeDefaultsChanges() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncPromptEditorsWithAppliedDefaultsIfNeeded()
            }
        }
    }

    private func syncPromptEditorsWithAppliedDefaultsIfNeeded() {
        let revision = defaults.double(forKey: Constants.UserDefaultsKeys.promptRevision)
        let rawSystemPrompt = defaults.string(forKey: Constants.UserDefaultsKeys.personalizationSystemPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSystemPrompt = (rawSystemPrompt?.isEmpty == false)
            ? rawSystemPrompt!
            : SystemPrompts.defaultStarterProfile
        let continuation = defaults.string(forKey: Constants.UserDefaultsKeys.customContinuationPrompt) ?? ""
        let replacement = defaults.string(forKey: Constants.UserDefaultsKeys.customReplacementPrompt) ?? ""
        let replacementMode = defaults.bool(forKey: Constants.UserDefaultsKeys.replacementModeEnabled)

        let appliedChanged = revision != lastKnownPromptRevision
            || resolvedSystemPrompt != appliedSystemPrompt
            || continuation != appliedCustomContinuationPrompt
            || replacement != appliedCustomReplacementPrompt
            || replacementMode != appliedReplacementModeEnabled
        guard appliedChanged else { return }

        lastKnownPromptRevision = revision
        appliedSystemPrompt = resolvedSystemPrompt
        appliedCustomContinuationPrompt = continuation
        appliedCustomReplacementPrompt = replacement
        appliedReplacementModeEnabled = replacementMode

        // Do not wipe unsaved edits; synchronize only when editor is not dirty.
        if !promptSettingsDirty {
            systemPrompt = resolvedSystemPrompt
            customContinuationPrompt = continuation
            customReplacementPrompt = replacement
            replacementModeEnabled = replacementMode
        }
        updatePromptSettingsDirtyState()
    }

    private static func defaultCloudModel(for provider: CloudProviderOption) -> String {
        cloudModels(for: provider).first?.id ?? "gpt-4.1-nano"
    }

    private static var manualHotkeyOptions: [ManualTriggerHotkeyOption] {
        [
            .init(id: "opt_space", title: "Option + Space", keyCode: 49, modifiersRaw: CGEventFlags.maskAlternate.rawValue),
            .init(id: "ctrl_space", title: "Control + Space", keyCode: 49, modifiersRaw: CGEventFlags.maskControl.rawValue),
            .init(id: "opt_shift_space", title: "Option + Shift + Space", keyCode: 49, modifiersRaw: (CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue)),
            .init(id: "ctrl_opt_space", title: "Control + Option + Space", keyCode: 49, modifiersRaw: (CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)),
            .init(id: "cmd_shift_space", title: "Command + Shift + Space", keyCode: 49, modifiersRaw: (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))
        ]
    }

    private static var paletteNavigationHotkeyOptions: [ManualTriggerHotkeyOption] {
        [
            .init(id: "opt_down", title: "Option + Down", keyCode: 125, modifiersRaw: CGEventFlags.maskAlternate.rawValue),
            .init(id: "opt_up", title: "Option + Up", keyCode: 126, modifiersRaw: CGEventFlags.maskAlternate.rawValue),
            .init(id: "ctrl_down", title: "Control + Down", keyCode: 125, modifiersRaw: CGEventFlags.maskControl.rawValue),
            .init(id: "ctrl_up", title: "Control + Up", keyCode: 126, modifiersRaw: CGEventFlags.maskControl.rawValue),
            .init(id: "cmd_down", title: "Command + Down", keyCode: 125, modifiersRaw: CGEventFlags.maskCommand.rawValue),
            .init(id: "cmd_up", title: "Command + Up", keyCode: 126, modifiersRaw: CGEventFlags.maskCommand.rawValue)
        ]
    }

    private static func resolveManualHotkeyID(keyCode: Int, modifiersRaw: UInt64) -> String {
        if let matched = manualHotkeyOptions.first(where: { $0.keyCode == keyCode && $0.modifiersRaw == modifiersRaw }) {
            return matched.id
        }
        return manualHotkeyOptions.first?.id ?? "opt_space"
    }

    private static func resolvePaletteNavigationHotkeyID(
        keyCode: Int,
        modifiersRaw: UInt64,
        fallbackID: String
    ) -> String {
        if let matched = paletteNavigationHotkeyOptions.first(where: { $0.keyCode == keyCode && $0.modifiersRaw == modifiersRaw }) {
            return matched.id
        }
        return fallbackID
    }

    static func cloudModels(for provider: CloudProviderOption) -> [CloudModelOption] {
        switch provider {
        case .openAI:
            return [
                .init(id: "gpt-4.1-nano", title: "GPT-4.1 Nano", detail: "Fastest non-reasoning model"),
                .init(id: "gpt-4.1-mini", title: "GPT-4.1 Mini", detail: "Low-latency non-reasoning model"),
                .init(id: "gpt-4.1", title: "GPT-4.1", detail: "Highest quality non-reasoning model")
            ]
        case .anthropic:
            return [
                .init(id: "claude-3-5-haiku-latest", title: "Claude 3.5 Haiku", detail: "Fast and lightweight"),
                .init(id: "claude-sonnet-4-5", title: "Claude Sonnet 4.5", detail: "Higher quality")
            ]
        case .xAI:
            return [
                .init(id: "grok-3-mini-beta", title: "Grok 3 Mini", detail: "Fast completion model"),
                .init(id: "grok-3-beta", title: "Grok 3", detail: "Higher quality")
            ]
        case .openRouter:
            return [
                .init(id: "google/gemini-2.5-flash", title: "Gemini 2.5 Flash", detail: "Fast + strong text quality"),
                .init(id: "openai/gpt-4.1-mini", title: "GPT-4.1 Mini", detail: "Stable high-quality fallback"),
                .init(id: "anthropic/claude-3.5-haiku", title: "Claude 3.5 Haiku", detail: "Very fast text completion")
            ]
        }
    }

    private func loadMemories() -> [MemoryItem] {
        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.personalizationUserMemories) else {
            return []
        }
        return (try? decoder.decode([MemoryItem].self, from: data)) ?? []
    }

    private func saveMemories(_ list: [MemoryItem]) {
        guard let data = try? encoder.encode(list) else {
            return
        }
        defaults.set(data, forKey: Constants.UserDefaultsKeys.personalizationUserMemories)
    }

    private func decodeStringList(forKey key: String) -> [String] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode([String].self, from: data) else {
            return []
        }
        return decoded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
