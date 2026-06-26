import Foundation

/// Lightweight localization helper. Uses `appLanguage` setting or falls back to system locale.
enum L {
    private static var overrideLanguage: String?

    static var isRussian: Bool {
        if let override = overrideLanguage {
            return override == "ru"
        }
        let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
        let appLang = defaults.string(forKey: Constants.UserDefaultsKeys.appLanguage) ?? "auto"
        if appLang == "ru" { return true }
        if appLang == "en" { return false }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true
    }

    static func setLanguage(_ lang: String) {
        overrideLanguage = (lang == "auto") ? nil : lang
    }

    // MARK: - Tabs
    static var tab_guide: String { isRussian ? "Гайд" : "Guide" }
    static var tab_editor: String { isRussian ? "Редактор" : "Editor" }
    static var tab_models: String { isRussian ? "Модели" : "Models" }
    static var tab_analytics: String { isRussian ? "Аналитика" : "Analytics" }
    static var tab_settings: String { isRussian ? "Настройки" : "Settings" }

    // MARK: - Analytics
    static var analytics_title: String { isRussian ? "Аналитика" : "Analytics" }
    static var analytics_languageSplit: String { isRussian ? "Языки" : "Languages" }
    static var analytics_topWords: String { isRussian ? "Частые слова" : "Top Words" }
    static var analytics_topPhrases: String { isRussian ? "Частые фразы" : "Top Phrases" }
    static var analytics_styleProfile: String { isRussian ? "Профиль стиля" : "Style Profile" }
    static var analytics_snippet: String { isRussian ? "Сниппет стиля" : "Style Snippet" }
    static var analytics_llmAnalysis: String { isRussian ? "Анализ от ИИ" : "AI Analysis" }
    static var analytics_analyzeButton: String { isRussian ? "Проанализировать" : "Analyze with AI" }
    static var analytics_analyzing: String { isRussian ? "Анализирую..." : "Analyzing..." }
    static var analytics_noData: String { isRussian ? "Пока нет данных. Начните печатать." : "No data yet. Start typing." }
    static var analytics_samples: String { isRussian ? "Образцов текста" : "Text samples" }
    static var analytics_avgWords: String { isRussian ? "Среднее слов/сообщ." : "Avg words/message" }
    static var analytics_commas: String { isRussian ? "Запятые" : "Commas" }
    static var analytics_questions: String { isRussian ? "Вопросы" : "Questions" }
    static var analytics_exclamations: String { isRussian ? "Восклицания" : "Exclamations" }
    static var analytics_emoji: String { isRussian ? "Эмодзи" : "Emoji" }

    // MARK: - Settings
    static var settings_title: String { isRussian ? "Настройки" : "Settings" }
    static var settings_completion: String { isRussian ? "Дополнение" : "Completion" }
    static var settings_mode: String { isRussian ? "Режим" : "Mode" }
    static var settings_suggestions: String { isRussian ? "Подсказки" : "Suggestions" }
    static var settings_language: String { isRussian ? "Язык" : "Language" }
    static var settings_cloud: String { isRussian ? "Облако" : "Cloud" }
    static var settings_privacyMode: String { isRussian ? "Режим приватности" : "Privacy Mode" }
    static var settings_provider: String { isRussian ? "Провайдер" : "Provider" }
    static var settings_model: String { isRussian ? "Модель" : "Model" }
    static var settings_apiKey: String { isRussian ? "API ключ" : "API Key" }
    static var settings_localModel: String { isRussian ? "Локальная модель" : "Local Model" }
    static var settings_enableLocal: String { isRussian ? "Включить локальную модель" : "Enable Local Model" }
    static var settings_localModelHint: String { isRussian ? "Когда выключено, GGUF модели остаются на устройстве, но не загружаются в память." : "When OFF, local GGUF models stay on device but are not loaded into memory." }
    static var settings_personalization: String { isRussian ? "Персонализация" : "Personalization" }
    static var settings_systemPrompt: String { isRussian ? "Системный промпт" : "System Prompt" }
    static var settings_memoryAbout: String { isRussian ? "Память о вас" : "Memory About You" }
    static var settings_addMemory: String { isRussian ? "Добавить" : "Add" }
    static var settings_addMemoryPlaceholder: String { isRussian ? "Добавить память (стиль, предпочтения)" : "Add memory (style, preferences, events)" }
    static var settings_noMemories: String { isRussian ? "Пока нет сохраненных воспоминаний." : "No stored memories yet." }
    static var settings_styleProfile: String { isRussian ? "Авто профиль стиля" : "Auto Style Profile" }
    static var settings_styleProfileHint: String { isRussian ? "Профиль появится после принятых подсказок." : "Profile will appear after accepted suggestions." }
    static var settings_goodCompletions: String { isRussian ? "Хорошие дополнения (5)" : "Good Additions (Last 5)" }
    static var settings_noCompletions: String { isRussian ? "Ещё нет принятых дополнений." : "No accepted completion pairs yet." }
    static var settings_clearDictionary: String { isRussian ? "Очистить словарь" : "Clear User Dictionary" }
    static var settings_clearing: String { isRussian ? "Очистка..." : "Clearing..." }
    static var settings_clearConfirmTitle: String { isRussian ? "Очистить данные персонализации?" : "Clear personalization data?" }
    static var settings_clearConfirmMessage: String { isRussian ? "Это удалит сохраненные привязки контекста к фразам." : "This will remove stored context-prefix to phrase mappings." }
    static var settings_clear: String { isRussian ? "Очистить" : "Clear" }
    static var settings_cancel: String { isRussian ? "Отмена" : "Cancel" }
    static var settings_trainNow: String { isRussian ? "Обучить сейчас" : "Train Now" }
    static var settings_keyboardAccess: String { isRussian ? "Доступ клавиатуры" : "Keyboard Access" }
    static var settings_openSettings: String { isRussian ? "Открыть настройки iOS" : "Open iOS Settings" }
    static var settings_keyboardHint: String { isRussian ? "Включите клавиатуру AIComplete и разрешите полный доступ для облачного дополнения." : "Enable AIComplete keyboard and allow Full Access for cloud completion." }
    static var settings_appLanguage: String { isRussian ? "Язык интерфейса" : "App Language" }

    // MARK: - Guide
    static var guide_title: String { isRussian ? "Гайд" : "Guide" }
    static var guide_restartButton: String { isRussian ? "Пройти заново" : "Restart Guide" }

    // MARK: - Editor
    static var editor_title: String { isRussian ? "Редактор" : "Editor" }
    static var editor_dismiss: String { isRussian ? "Убрать" : "Dismiss" }

    // MARK: - Completion Modes (for settings picker)
    static var mode_localOnly: String { isRussian ? "Только локально" : "Local Only" }
    static var mode_cloudOnly: String { isRussian ? "Только облако" : "Cloud Only" }
    static var mode_hybrid: String { isRussian ? "Гибрид" : "Hybrid" }

    // MARK: - Language modes
    static var lang_auto: String { isRussian ? "Авто" : "Auto" }
    static var lang_russian: String { isRussian ? "Русский" : "Russian" }
    static var lang_english: String { isRussian ? "Английский" : "English" }
    static var lang_both: String { isRussian ? "Оба" : "Both" }
}
