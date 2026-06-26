import SwiftUI

struct EngineSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var applyStatus = ""

    var body: some View {
        ScrollView {
            VStack(spacing: AITheme.spacingL) {
                completionModeSection
                suggestionTriggerSection
                cloudProviderSection
                languageSection
                applySection
            }
            .padding(AITheme.spacingL)
            .padding(.bottom, AITheme.spacingL)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.engineSettingsDirty) {
            if viewModel.engineSettingsDirty {
                applyStatus = ""
            }
        }
    }

    // MARK: - Completion Mode

    @ViewBuilder
    private var completionModeSection: some View {
        premiumSection(title: L.settings_completion) {
            Picker(L.settings_mode, selection: $viewModel.completionMode) {
                ForEach(availableModes) { mode in
                    Text(localizedMode(mode)).tag(mode)
                }
            }

            if !LocalModelManager.isAvailable {
                Text(L.isRussian
                     ? "Локальный рантайм недоступен. Соберите встроенный llama.cpp runtime или оставьте внешний fallback доступным."
                     : "Local runtime unavailable. Build the bundled llama.cpp runtime or keep the external fallback available.")
                    .font(AITheme.fontCaption)
                    .foregroundStyle(.orange)
            }

        }
    }

    // MARK: - Cloud Provider

    @ViewBuilder
    private var suggestionTriggerSection: some View {
        premiumSection(title: L.isRussian ? "Триггер подсказок" : "Suggestion Trigger") {
            Picker(L.isRussian ? "Режим подсказок" : "Suggestion Mode", selection: $viewModel.suggestionTriggerMode) {
                Text(L.isRussian ? "Автоматический" : "Automatic")
                    .tag(SettingsViewModel.SuggestionTriggerModeOption.automatic)
                Text(L.isRussian ? "По хоткею" : "On Hotkey")
                    .tag(SettingsViewModel.SuggestionTriggerModeOption.manualHotkey)
            }
            .pickerStyle(.segmented)

            Picker(L.isRussian ? "Количество вариантов" : "Suggestions", selection: $viewModel.suggestionCount) {
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .pickerStyle(.segmented)

            Picker(
                L.isRussian ? "Tab для одной подсказки" : "Single Suggestion Tab",
                selection: $viewModel.singleSuggestionAcceptMode
            ) {
                Text(L.isRussian ? "Следующее слово" : "Next Word")
                    .tag(SingleSuggestionAcceptMode.nextWord)
                Text(L.isRussian ? "Вся подсказка" : "Full Completion")
                    .tag(SingleSuggestionAcceptMode.fullSuggestion)
            }
            .pickerStyle(.segmented)

            if viewModel.singleSuggestionAcceptMode == .nextWord {
                Toggle(
                    L.isRussian ? "Добавлять пробел после следующего слова" : "Include trailing space after next word",
                    isOn: $viewModel.partialAcceptTrailingSpaceEnabled
                )
                .toggleStyle(.switch)
            }

            if viewModel.suggestionTriggerMode == .manualHotkey {
                Picker(L.isRussian ? "Горячая клавиша" : "Hotkey", selection: $viewModel.manualTriggerHotkeyID) {
                    ForEach(viewModel.manualHotkeyOptions()) { hotkey in
                        Text(hotkey.title).tag(hotkey.id)
                    }
                }

                Picker(L.isRussian ? "Следующий вариант" : "Next Option", selection: $viewModel.paletteNextHotkeyID) {
                    ForEach(viewModel.paletteNavigationHotkeyOptions()) { hotkey in
                        Text(hotkey.title).tag(hotkey.id)
                    }
                }

                Picker(L.isRussian ? "Предыдущий вариант" : "Previous Option", selection: $viewModel.palettePreviousHotkeyID) {
                    ForEach(viewModel.paletteNavigationHotkeyOptions()) { hotkey in
                        Text(hotkey.title).tag(hotkey.id)
                    }
                }
            }

            Text(viewModel.suggestionTriggerMode == .automatic
                 ? (L.isRussian ? "Подсказки появляются автоматически во время набора." : "Suggestions appear automatically while typing.")
                 : (L.isRussian
                    ? "Подсказка запрашивается по горячей клавише. Для одной подсказки Tab ведет себя по выбранной политике, а для palette из нескольких вариантов Tab принимает выбранный вариант. Клавиши 1/2/3 принимают конкретный вариант, а Next/Previous двигают выделение."
                    : "Suggestions are requested by hotkey. For a single suggestion, Tab follows the selected acceptance policy. For a multi-option palette, Tab accepts the selected option. Keys 1/2/3 accept a specific option, and Next/Previous move the selection."))
                .font(AITheme.fontCaption)
                .foregroundStyle(AITheme.textSecondary)
        }
    }

    // MARK: - Cloud Provider

    @ViewBuilder
    private var cloudProviderSection: some View {
        premiumSection(title: L.isRussian ? "Облачный провайдер" : "Cloud Provider") {
            Picker("Provider", selection: $viewModel.cloudProvider) {
                ForEach(SettingsViewModel.CloudProviderOption.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.cloudProvider) {
                viewModel.handleProviderChanged()
            }

            Picker(L.isRussian ? "Модель" : "Model", selection: $viewModel.cloudModelIdentifier) {
                ForEach(SettingsViewModel.cloudModels(for: viewModel.cloudProvider)) { model in
                    Text(model.title).tag(model.id)
                }
            }

            HStack(spacing: 10) {
                Text("API Key")
                    .font(AITheme.fontCaption)
                    .foregroundStyle(AITheme.textSecondary)
                    .frame(width: 56, alignment: .leading)
                SecureField("sk-...", text: $viewModel.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(AITheme.fontMono)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 320, alignment: .leading)
            }

            HStack(spacing: 10) {
                Text(L.isRussian ? "Max tokens" : "Max tokens")
                    .font(AITheme.fontCaption)
                    .foregroundStyle(AITheme.textSecondary)
                    .frame(width: 72, alignment: .leading)
                TextField("24", text: $viewModel.maxTokensInput)
                    .textFieldStyle(.roundedBorder)
                    .font(AITheme.fontMono)
                    .frame(width: 120, alignment: .leading)
                Text(L.isRussian ? "любое число > 0" : "any number > 0")
                    .font(AITheme.fontCaption2)
                    .foregroundStyle(AITheme.textSecondary)
            }

            if viewModel.apiKey.isEmpty {
                Text(L.isRussian
                     ? "Введите API ключ для облачных автодополнений."
                     : "Enter your API key to enable cloud completions.")
                    .font(AITheme.fontCaption)
                    .foregroundStyle(.orange)
            } else if viewModel.cloudProvider == .openAI && !viewModel.apiKey.lowercased().hasPrefix("sk-") {
                Text(L.isRussian
                     ? "Ключ OpenAI обычно начинается с sk-."
                     : "OpenAI key usually starts with sk-. If requests fail with 401, verify the key/provider pair.")
                    .font(AITheme.fontCaption)
                    .foregroundStyle(.orange)
            }

            Toggle(L.isRussian ? "Режим приватности" : "Privacy Mode", isOn: $viewModel.privacyModeEnabled)
                .toggleStyle(.switch)

            Text(viewModel.privacyModeEnabled
                 ? (L.isRussian ? "Используются только локальные модели. Данные не отправляются в облако." : "Only local models will be used. No data sent to cloud.")
                 : (L.isRussian ? "Текстовый контекст отправляется облачному провайдеру." : "Text context is sent to the cloud provider for completions."))
                .font(AITheme.fontCaption)
                .foregroundStyle(AITheme.textSecondary)
        }
    }

    // MARK: - Language

    @ViewBuilder
    private var languageSection: some View {
        premiumSection(title: L.isRussian ? "Язык" : "Language") {
            Picker(L.settings_language, selection: $viewModel.languageMode) {
                ForEach(SettingsViewModel.LanguageModeOption.allCases) { mode in
                    Text(localizedLangMode(mode)).tag(mode)
                }
            }
        }
    }

    @ViewBuilder
    private var applySection: some View {
        premiumSection(title: L.isRussian ? "Применение" : "Apply") {
            Button(L.isRussian ? "Применить все настройки" : "Apply All Settings") {
                viewModel.forceApplyEngineSettings()
                applyStatus = L.isRussian ? "Настройки применены." : "Settings applied."
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.engineSettingsDirty)

            Text(viewModel.engineSettingsDirty
                 ? (L.isRussian ? "Есть неприменённые изменения." : "There are unapplied changes.")
                 : (L.isRussian ? "Все изменения применены." : "All changes are applied."))
                .font(AITheme.fontCaption)
                .foregroundStyle(viewModel.engineSettingsDirty ? .orange : AITheme.textSecondary)

            if !applyStatus.isEmpty {
                Text(applyStatus)
                    .font(AITheme.fontCaption2)
                    .foregroundStyle(AITheme.accentMint)
            }
        }
    }

    // MARK: - Helpers

    private var availableModes: [SettingsViewModel.CompletionModeOption] {
        if LocalModelManager.isAvailable {
            return SettingsViewModel.CompletionModeOption.allCases
        }
        return SettingsViewModel.CompletionModeOption.allCases.filter { $0 != .localOnly }
    }

    private func localizedMode(_ mode: SettingsViewModel.CompletionModeOption) -> String {
        switch mode {
        case .localOnly: return L.mode_localOnly
        case .cloudOnly: return L.mode_cloudOnly
        case .hybrid: return L.mode_hybrid
        }
    }

    private func localizedLangMode(_ mode: SettingsViewModel.LanguageModeOption) -> String {
        switch mode {
        case .auto: return L.lang_auto
        case .russian: return L.lang_russian
        case .english: return L.lang_english
        case .both: return L.lang_both
        }
    }

    @ViewBuilder
    private func premiumSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: AITheme.spacingM) {
            Text(title)
                .font(AITheme.fontTitleSection)
                .foregroundStyle(AITheme.accentGradient)

            VStack(alignment: .leading, spacing: AITheme.spacingM) {
                content()
            }
        }
        .aiCard()
    }
}
