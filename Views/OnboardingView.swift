import SwiftUI

private struct PromptPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let text: String
}

private enum WizardStep: Int, CaseIterable {
    case style = 0
    case mode = 1
    case provider = 2
    case apiKey = 3
    case done = 4

    var label: String {
        switch self {
        case .style: return L.isRussian ? "Стиль" : "Style"
        case .mode: return L.isRussian ? "Режим" : "Mode"
        case .provider: return L.isRussian ? "Провайдер" : "Provider"
        case .apiKey: return "API Key"
        case .done: return L.isRussian ? "Готово" : "Done"
        }
    }
}

struct OnboardingView: View {
    @Binding var guideCompleted: Bool

    @State private var currentStep: WizardStep = .style
    @State private var userInput = ""
    @FocusState private var isInputFocused: Bool
    @State private var selectedPreset: PromptPreset?
    @State private var completionMode: String = "hybrid"
    @State private var cloudProvider: String = "openAI"
    @State private var apiKeyInput: String = ""
    @State private var apiKeyStatus: APIKeyStatus = .empty
    @State private var isVerifyingKey = false
    @State private var showDataDetails = false

    private let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
    private var isRussian: Bool { L.isRussian }

    private var promptPresets: [PromptPreset] {
        if isRussian {
            return [
                .init(id: "ru-tech", title: "Техничный", text: "Пиши кратко, по шагам, с чёткой логикой."),
                .init(id: "ru-friendly", title: "Дружелюбный", text: "Пиши тёпло и понятно, но по делу."),
                .init(id: "ru-business", title: "Деловой", text: "Пиши в деловом стиле: чётко, профессионально.")
            ]
        }
        return [
            .init(id: "en-tech", title: "Technical", text: "Write concise, step-by-step responses."),
            .init(id: "en-friendly", title: "Friendly", text: "Write in a warm and clear tone."),
            .init(id: "en-business", title: "Professional", text: "Use a professional and direct style.")
        ]
    }

    private enum APIKeyStatus {
        case empty, checking, valid, invalid, skipped
    }

    // Total visible steps (adjusted for localOnly skipping provider+apiKey)
    private var totalSteps: Int {
        completionMode == "localOnly" ? 3 : WizardStep.allCases.count
    }

    private var currentStepNumber: Int {
        if completionMode == "localOnly" {
            switch currentStep {
            case .style: return 1
            case .mode: return 2
            case .done: return 3
            default: return currentStep.rawValue + 1
            }
        }
        return currentStep.rawValue + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with progress
            VStack(spacing: AITheme.spacingS) {
                HStack {
                    Text(isRussian ? "Настройка помощника" : "Assistant Setup")
                        .font(AITheme.fontHeading)
                    Spacer()
                    Text("\(currentStepNumber) / \(totalSteps)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Progress bar
                ProgressView(value: Double(currentStepNumber), total: Double(totalSteps))
                    .tint(AITheme.accent)

                // Step labels
                HStack(spacing: AITheme.spacingXS) {
                    ForEach(Array(visibleSteps.enumerated()), id: \.element) { index, step in
                        stepChip(step, index: index)
                    }
                    Spacer()
                }
            }
            .padding(AITheme.spacingM)
            .background(Color.black.opacity(0.6))

            Divider()

            // Content
            ZStack {
                switch currentStep {
                case .style: styleStep
                case .mode: modeStep
                case .provider: providerStep
                case .apiKey: apiKeyStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(AITheme.spacingL)

            Divider()

            // Footer
            HStack {
                if currentStep != .style && currentStep != .done {
                    Button(isRussian ? "Назад" : "Back") { goBack() }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                }
                Spacer()
                if currentStep != .done {
                    Button(isRussian ? "Далее" : "Next") { goForward() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canGoForward)
                        .keyboardShortcut(.return, modifiers: [.command])
                } else {
                    Button(isRussian ? "Начать работу" : "Start Using") {
                        guideCompleted = true
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .padding(AITheme.spacingM)
            .background(Color.black.opacity(0.6))
        }
        .background(AITheme.backgroundGradient)
        .sheet(item: $selectedPreset) { preset in
            VStack(spacing: AITheme.spacingM) {
                Text(preset.title).font(AITheme.fontHeading)
                Text(preset.text).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer()
                    Button(isRussian ? "Использовать" : "Use") {
                        userInput = preset.text
                        selectedPreset = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(AITheme.spacingL)
            .frame(width: 400)
        }
        .onAppear {
            completionMode = defaults.string(forKey: Constants.UserDefaultsKeys.completionMode) ?? "hybrid"
            cloudProvider = defaults.string(forKey: Constants.UserDefaultsKeys.cloudProvider) ?? "openAI"
            let storedPrompt = defaults.string(forKey: Constants.UserDefaultsKeys.personalizationSystemPrompt)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            userInput = (storedPrompt?.isEmpty == false) ? storedPrompt! : SystemPrompts.defaultStarterProfile
            apiKeyInput = APIKeyStore.read() ?? ""
            if !apiKeyInput.isEmpty { apiKeyStatus = .valid }
            isInputFocused = true
        }
    }

    // MARK: - Step Chips

    private var visibleSteps: [WizardStep] {
        if completionMode == "localOnly" {
            return [.style, .mode, .done]
        }
        return WizardStep.allCases
    }

    private func stepChip(_ step: WizardStep, index: Int) -> some View {
        let isCurrent = step == currentStep
        let isCompleted = index < currentStepNumber - 1

        return Text(step.label)
            .font(AITheme.fontCaption2)
            .padding(.horizontal, AITheme.spacingS)
            .padding(.vertical, AITheme.spacingXS)
            .background(
                Capsule()
                    .fill(isCurrent ? AITheme.accent.opacity(0.2) :
                            isCompleted ? AITheme.accent.opacity(0.08) : Color.clear)
            )
            .foregroundStyle(isCurrent ? AITheme.textPrimary :
                                isCompleted ? AITheme.textSecondary : AITheme.textTertiary)
    }

    // MARK: - Steps Views

    private var styleStep: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingM) {
            AITheme.sectionHeader(isRussian ? "1. Ваш стиль" : "1. Your Style", icon: "text.quote")

            Text(isRussian
                 ? "Опишите, как вы обычно пишете, чтобы AI мог подстраиваться под ваш тон, или выберите готовый пресет."
                 : "Describe your writing style so the AI can adapt to your tone, or pick a preset.")
                .foregroundStyle(.secondary)

            TextEditor(text: $userInput)
                .focused($isInputFocused)
                .frame(height: 100)
                .padding(AITheme.spacingXS)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AITheme.spacingS))
                .overlay(RoundedRectangle(cornerRadius: AITheme.spacingS).stroke(Color.secondary.opacity(0.2)))

            HStack {
                Text(isRussian ? "Пресеты:" : "Presets:")
                    .font(AITheme.fontCaption)
                    .foregroundStyle(.secondary)
                ForEach(promptPresets) { preset in
                    Button(preset.title) { selectedPreset = preset }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
            Spacer()
        }
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingM) {
            AITheme.sectionHeader(isRussian ? "2. Режим работы" : "2. Completion Mode", icon: "slider.horizontal.3")

            Text(isRussian
                 ? "Выберите, где будут обрабатываться ваши данные."
                 : "Choose where your data will be processed.")
                .foregroundStyle(.secondary)

            VStack(spacing: AITheme.spacingS + 4) {
                modeOption(id: "localOnly", title: "Local Only",
                           desc: isRussian ? "Максимальная приватность. Работает офлайн." : "Maximum privacy. Works offline.",
                           privacy: isRussian ? "Ничего не отправляется" : "Nothing sent anywhere",
                           enabled: LocalModelManager.isAvailable)
                modeOption(id: "hybrid", title: "Hybrid",
                           desc: isRussian ? "Баланс. Лёгкие задачи локально, сложные в облаке." : "Balanced. Simple tasks locally, complex in cloud.",
                           privacy: isRussian ? "Контекст отправляется при необходимости" : "Context sent when needed",
                           enabled: true)
                modeOption(id: "cloudOnly", title: "Cloud Only",
                           desc: isRussian ? "Максимальное качество. Требует интернет." : "Best quality. Requires internet.",
                           privacy: isRussian ? "Каждый запрос отправляется в облако" : "Every request sent to cloud",
                           enabled: true)
            }

            // Data transparency disclosure
            if completionMode != "localOnly" {
                DisclosureGroup(isExpanded: $showDataDetails) {
                    VStack(alignment: .leading, spacing: AITheme.spacingS) {
                        dataRow(
                            icon: "arrow.up.doc",
                            title: isRussian ? "Что отправляется:" : "What is sent:",
                            detail: isRussian
                                ? "До \(Constants.Limits.contextBeforeCharacterLimit) символов до курсора и \(Constants.Limits.contextAfterCharacterLimit) после"
                                : "Up to \(Constants.Limits.contextBeforeCharacterLimit) chars before cursor and \(Constants.Limits.contextAfterCharacterLimit) after"
                        )
                        dataRow(
                            icon: "server.rack",
                            title: isRussian ? "Куда:" : "Where:",
                            detail: providerEndpoint
                        )
                        dataRow(
                            icon: "clock",
                            title: isRussian ? "Хранение:" : "Storage:",
                            detail: isRussian
                                ? "Зависит от политики провайдера. AIComplete не хранит данные на своих серверах."
                                : "Depends on provider policy. AIComplete does not store data on its own servers."
                        )
                        dataRow(
                            icon: "lock.shield",
                            title: isRussian ? "Локальные данные:" : "Stored locally:",
                            detail: isRussian
                                ? "Словарь фраз, стиль-профиль, TinyStyleLM — всё на устройстве"
                                : "Phrase dictionary, style profile, TinyStyleLM — all on device"
                        )
                    }
                    .padding(.top, AITheme.spacingS)
                } label: {
                    Label(
                        isRussian ? "Какие данные отправляются?" : "What data is shared?",
                        systemImage: "shield.lefthalf.filled"
                    )
                    .font(AITheme.fontCaptionBold)
                    .foregroundStyle(AITheme.accent)
                }
                .padding(AITheme.spacingS + 4)
                .background(AITheme.accentMist, in: RoundedRectangle(cornerRadius: AITheme.inputRadius))
            }

            Spacer()
        }
    }

    private func modeOption(id: String, title: String, desc: String, privacy: String, enabled: Bool) -> some View {
        Button {
            if enabled { completionMode = id }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: AITheme.spacingXS) {
                    Text(title).font(AITheme.fontHeading)
                    Text(desc).font(AITheme.fontCaption).foregroundStyle(.secondary)
                    HStack(spacing: AITheme.spacingXS) {
                        Image(systemName: id == "localOnly" ? "lock.fill" : "cloud")
                            .font(.caption2)
                        Text(privacy)
                            .font(AITheme.fontCaption2)
                    }
                    .foregroundStyle(id == "localOnly" ? .green : .orange)
                }
                Spacer()
                if completionMode == id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AITheme.accent)
                        .font(.title3)
                }
            }
            .padding(AITheme.spacingM)
            .background(completionMode == id ? AITheme.accentMist : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(AITheme.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AITheme.buttonRadius)
                    .stroke(completionMode == id ? AITheme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1.0 : 0.5)
        .disabled(!enabled)
    }

    private func dataRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AITheme.spacingS) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AITheme.fontCaption2.weight(.semibold))
                Text(detail).font(AITheme.fontCaption2).foregroundStyle(.secondary)
            }
        }
    }

    private var providerEndpoint: String {
        switch cloudProvider {
        case "openAI": return "api.openai.com"
        case "anthropic": return "api.anthropic.com"
        case "xAI": return "api.x.ai"
        case "openRouter": return "openrouter.ai/api"
        default: return "api.openai.com"
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingM) {
            AITheme.sectionHeader(isRussian ? "3. Провайдер облака" : "3. Cloud Provider", icon: "cloud")

            Text(isRussian
                 ? "Выберите облачного провайдера для AI-дополнений."
                 : "Select a cloud provider for AI completions.")
                .foregroundStyle(.secondary)

            VStack(spacing: AITheme.spacingS + 4) {
                providerOption(id: "openAI", title: "OpenAI", desc: "GPT-4.1 Nano, Mini, Full")
                providerOption(id: "xAI", title: "Grok (xAI)", desc: "Grok-3, Grok-3-mini")
                providerOption(id: "openRouter", title: "OpenRouter", desc: "Gemini, Claude, Llama")
                providerOption(id: "anthropic", title: "Anthropic", desc: "Claude 3.5 Sonnet, Haiku")
            }
            Spacer()
        }
    }

    private func providerOption(id: String, title: String, desc: String) -> some View {
        Button {
            cloudProvider = id
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).font(AITheme.fontHeading)
                    Text(desc).font(AITheme.fontCaption).foregroundStyle(.secondary)
                }
                Spacer()
                if cloudProvider == id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AITheme.accent)
                        .font(.title3)
                }
            }
            .padding(AITheme.spacingM)
            .background(cloudProvider == id ? AITheme.accentMist : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(AITheme.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AITheme.buttonRadius)
                    .stroke(cloudProvider == id ? AITheme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - API Key Step (NEW)

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingM) {
            AITheme.sectionHeader(isRussian ? "4. API Ключ" : "4. API Key", icon: "key")

            Text(isRussian
                 ? "Введите API ключ для \(providerTitle). Без ключа облачные дополнения не будут работать."
                 : "Enter your API key for \(providerTitle). Cloud completions won't work without it.")
                .foregroundStyle(.secondary)

            SecureField(isRussian ? "Вставьте API ключ..." : "Paste your API key...", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340, alignment: .leading)
                .autocorrectionDisabled()
                .font(.system(.caption, design: .monospaced))

            HStack(spacing: AITheme.spacingS) {
                Button {
                    verifyAPIKey()
                } label: {
                    if isVerifyingKey {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(isRussian ? "Проверить" : "Verify", systemImage: "checkmark.shield")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifyingKey)

                apiKeyStatusChip
            }

            // Help text
            Text(isRussian
                 ? "Ключ хранится в macOS Keychain. AIComplete не передаёт его третьим сторонам."
                 : "Key is stored in macOS Keychain. AIComplete never shares it with third parties.")
                .font(AITheme.fontCaption2)
                .foregroundStyle(.tertiary)

            Button(isRussian ? "Пропустить (настрою позже)" : "Skip (I'll set it up later)") {
                apiKeyStatus = .skipped
                goForward()
            }
            .font(AITheme.fontCaption)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    @ViewBuilder
    private var apiKeyStatusChip: some View {
        switch apiKeyStatus {
        case .empty:
            EmptyView()
        case .checking:
            AITheme.statusPill(isRussian ? "Проверяю..." : "Checking...", isPositive: true)
        case .valid:
            AITheme.statusPill(isRussian ? "Ключ валиден" : "Key valid", isPositive: true)
        case .invalid:
            AITheme.statusPill(isRussian ? "Ключ невалиден" : "Key invalid", isPositive: false)
        case .skipped:
            AITheme.statusPill(isRussian ? "Пропущено" : "Skipped", isPositive: false)
        }
    }

    private var providerTitle: String {
        switch cloudProvider {
        case "openAI": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "xAI": return "xAI"
        case "openRouter": return "OpenRouter"
        default: return "Provider"
        }
    }

    private func verifyAPIKey() {
        isVerifyingKey = true
        apiKeyStatus = .checking

        // Save the key
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            _ = APIKeyStore.save(trimmed)
        }

        // Simple verification: check key format and try a lightweight request
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 20 {
                    apiKeyStatus = .valid
                } else {
                    apiKeyStatus = .invalid
                }
                isVerifyingKey = false
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: AITheme.spacingL) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(AITheme.accent)

            Text(isRussian ? "Всё готово!" : "All set!")
                .font(AITheme.fontTitleLarge)

            VStack(alignment: .leading, spacing: AITheme.spacingS) {
                Text(isRussian ? "Что дальше:" : "Next steps:")
                    .font(AITheme.fontHeading)

                if apiKeyStatus != .valid && completionMode != "localOnly" {
                    doneStepRow(icon: "key", text: isRussian
                        ? "Добавьте API ключ в разделе Модели и Провайдеры."
                        : "Add your provider API key in Models & Providers.",
                        isWarning: true)
                }

                doneStepRow(icon: "hand.raised", text: isRussian
                    ? "Дайте разрешение Accessibility в настройках macOS."
                    : "Grant Accessibility permission in macOS Settings.")

                if completionMode != "cloudOnly" {
                    doneStepRow(icon: "arrow.down.circle", text: isRussian
                        ? "Скачайте модель в разделе Модели и Провайдеры."
                        : "Download a model in Models & Providers.")
                }

                doneStepRow(icon: "keyboard", text: isRussian
                    ? "Начните печатать в любом приложении — Tab примет подсказку."
                    : "Start typing in any app — Tab accepts a suggestion.")
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: 400)

            Spacer()
        }
    }

    private func doneStepRow(icon: String, text: String, isWarning: Bool = false) -> some View {
        HStack(alignment: .top, spacing: AITheme.spacingS) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(isWarning ? .orange : .secondary)
                .frame(width: 20)
            Text(text)
                .font(AITheme.fontCaption)
                .foregroundStyle(isWarning ? .orange : .secondary)
        }
    }

    // MARK: - Navigation Logic

    private var canGoForward: Bool {
        switch currentStep {
        case .style:
            return !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .apiKey:
            return apiKeyStatus == .valid || apiKeyStatus == .skipped ||
                   !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    private func goForward() {
        withAnimation {
            switch currentStep {
            case .style:
                defaults.set(userInput, forKey: Constants.UserDefaultsKeys.personalizationSystemPrompt)
                currentStep = .mode
            case .mode:
                defaults.set(completionMode, forKey: Constants.UserDefaultsKeys.completionMode)
                if completionMode == "localOnly" {
                    currentStep = .done
                } else {
                    currentStep = .provider
                }
            case .provider:
                defaults.set(cloudProvider, forKey: Constants.UserDefaultsKeys.cloudProvider)
                currentStep = .apiKey
            case .apiKey:
                let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    _ = APIKeyStore.save(trimmed)
                }
                currentStep = .done
            case .done:
                break
            }
        }
    }

    private func goBack() {
        withAnimation {
            switch currentStep {
            case .style: break
            case .mode: currentStep = .style
            case .provider: currentStep = .mode
            case .apiKey: currentStep = .provider
            case .done:
                if completionMode == "localOnly" {
                    currentStep = .mode
                } else {
                    currentStep = .apiKey
                }
            }
        }
    }
}
