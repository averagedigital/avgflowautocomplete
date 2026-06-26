import SwiftUI

struct PromptsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var promptApplyStatus = ""

    var body: some View {
        ScrollView {
            VStack(spacing: AITheme.spacingL) {
                promptModeSection
                customPromptSection
                systemPromptSection
            }
            .padding(AITheme.spacingL)
            .padding(.bottom, AITheme.spacingL)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.promptSettingsDirty) {
            if viewModel.promptSettingsDirty {
                promptApplyStatus = ""
            }
        }
    }

    // MARK: - Prompt Mode

    @ViewBuilder
    private var promptModeSection: some View {
        premiumSection(title: L.isRussian ? "Режим промпта" : "Prompt Mode") {
            Picker("", selection: $viewModel.selectedPromptTab) {
                Text(L.isRussian ? "Продолжение" : "Continuation").tag(0)
                Text(L.isRussian ? "Замена" : "Replacement").tag(1)
            }
            .pickerStyle(.segmented)

            Toggle(L.isRussian ? "Замена текста" : "Text Replacement", isOn: $viewModel.replacementModeEnabled)
                .toggleStyle(.switch)

            Text(viewModel.replacementModeEnabled
                 ? (L.isRussian ? "AI может заменять набранный текст на исправленные/расширенные версии." : "AI can replace typed text with corrected/expanded versions.")
                 : (L.isRussian ? "AI будет только продолжать текст после курсора." : "AI will only continue text after the cursor."))
                .font(AITheme.fontCaption)
                .foregroundStyle(AITheme.textSecondary)
        }
    }

    // MARK: - Custom Prompt

    @ViewBuilder
    private var customPromptSection: some View {
        premiumSection(title: viewModel.selectedPromptTab == 0
                       ? (L.isRussian ? "Промпт продолжения" : "Continuation Prompt")
                       : (L.isRussian ? "Промпт замены" : "Replacement Prompt")) {
            TextEditor(text: viewModel.selectedPromptTab == 0
                       ? $viewModel.customContinuationPrompt
                       : $viewModel.customReplacementPrompt)
                .frame(minHeight: 96)
                .padding(8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AITheme.inputRadius, style: .continuous))

            Text(L.isRussian
                 ? "Добавляется в конец системного промпта. Оставьте пустым для значений по умолчанию."
                 : "Added to the end of the system prompt. Leave empty to use defaults.")
                .font(AITheme.fontCaption)
                .foregroundStyle(AITheme.textSecondary)

            if !(viewModel.selectedPromptTab == 0
                 ? viewModel.customContinuationPrompt
                 : viewModel.customReplacementPrompt).isEmpty {
                Button(L.isRussian ? "Сбросить" : "Reset to Default", role: .destructive) {
                    if viewModel.selectedPromptTab == 0 {
                        viewModel.customContinuationPrompt = ""
                    } else {
                        viewModel.customReplacementPrompt = ""
                    }
                }
                .font(AITheme.fontCaption)
            }

            Button(L.isRussian ? "Применить промпт сейчас" : "Apply Prompt Now") {
                viewModel.forceApplyPromptSettings()
                promptApplyStatus = L.isRussian ? "Промпт принудительно применён." : "Prompt re-applied."
            }
            .buttonStyle(.borderedProminent)
            .font(AITheme.fontCaptionBold)
            .disabled(!viewModel.promptSettingsDirty)

            if !promptApplyStatus.isEmpty {
                Text(promptApplyStatus)
                    .font(AITheme.fontCaption2)
                    .foregroundStyle(AITheme.accentMint)
            }
        }
    }

    // MARK: - System Prompt

    @ViewBuilder
    private var systemPromptSection: some View {
        premiumSection(title: L.settings_systemPrompt) {
            TextEditor(text: $viewModel.systemPrompt)
                .frame(minHeight: 96)
                .padding(8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AITheme.inputRadius, style: .continuous))

            Button(L.isRussian ? "Применить системный промпт" : "Apply System Prompt") {
                viewModel.forceApplyPromptSettings()
                promptApplyStatus = L.isRussian ? "Системный промпт применён." : "System prompt re-applied."
            }
            .buttonStyle(.borderedProminent)
            .font(AITheme.fontCaptionBold)
            .disabled(!viewModel.promptSettingsDirty)

            Text(L.isRussian
                 ? "Основной системный промпт, определяющий поведение AI."
                 : "The core system prompt that defines AI behavior.")
                .font(AITheme.fontCaption)
                .foregroundStyle(AITheme.textSecondary)

            Text(viewModel.promptSettingsDirty
                 ? (L.isRussian ? "Есть неприменённые изменения промптов." : "There are unapplied prompt changes.")
                 : (L.isRussian ? "Промпты синхронизированы с применённой конфигурацией." : "Prompts are synchronized with applied configuration."))
                .font(AITheme.fontCaption2)
                .foregroundStyle(viewModel.promptSettingsDirty ? .orange : AITheme.textSecondary)

            if !promptApplyStatus.isEmpty {
                Text(promptApplyStatus)
                    .font(AITheme.fontCaption2)
                    .foregroundStyle(AITheme.accentMint)
            }
        }
    }

    // MARK: - Helpers

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
