import Foundation
import SwiftUI

struct AnalyticsWordItem: Identifiable {
    let id = UUID()
    let term: String
    let count: Int
}

struct AnalyticsLanguageItem: Identifiable {
    let id = UUID()
    let language: String
    let count: Int
}

struct AnalyticsPunctuationItem: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}

@MainActor
final class AnalyticsViewModel: ObservableObject {
    @Published var topWords: [AnalyticsWordItem] = []
    @Published var topPhrases: [AnalyticsWordItem] = []
    @Published var languageSplit: [AnalyticsLanguageItem] = []
    @Published var styleSignals = LexiconStyleSignals()
    @Published var punctuationChartData: [AnalyticsPunctuationItem] = []
    @Published var styleSnippet: String = ""
    @Published var tinyStyleStatus: String = ""
    @Published var llmAnalysisResult: String = ""
    @Published var isAnalyzing = false
    @Published var ruleGenerated = false

    // Phase 5: Engineering-driven analytics
    @Published var acceptanceRate: Double = 0
    @Published var acceptedCount: Int = 0
    @Published var totalShown: Int = 0
    @Published var recentAcceptances: [AcceptanceHistoryStore.AcceptedItem] = []
    @Published var perAppUsage: [(app: String, count: Int)] = []

    private let lexicon = SharedStore.makePersonalLexicon()
    private let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard

    func reload() async {
        // Top words (both languages)
        let ruWords = await lexicon.topWords(lang: "ru", limit: 10)
        let enWords = await lexicon.topWords(lang: "en", limit: 10)
        let merged = (ruWords + enWords)
            .sorted { $0.count > $1.count }
            .prefix(15)
        topWords = merged.map { AnalyticsWordItem(term: $0.term, count: $0.count) }

        // Top phrases
        let ruPhrases = await lexicon.topPhrases(lang: "ru", limit: 8, minCount: 2)
        let enPhrases = await lexicon.topPhrases(lang: "en", limit: 8, minCount: 2)
        let mergedPhrases = (ruPhrases + enPhrases)
            .sorted { $0.count > $1.count }
            .prefix(10)
        topPhrases = mergedPhrases.map { AnalyticsWordItem(term: $0.term, count: $0.count) }

        // Language split
        let ruCount = ruWords.reduce(0) { $0 + $1.count }
        let enCount = enWords.reduce(0) { $0 + $1.count }
        var split: [AnalyticsLanguageItem] = []
        if ruCount > 0 { split.append(.init(language: "RU", count: ruCount)) }
        if enCount > 0 { split.append(.init(language: "EN", count: enCount)) }
        languageSplit = split

        // Style signals
        if let data = defaults.data(forKey: Constants.UserDefaultsKeys.lexiconStyleStats),
           let decoded = try? JSONDecoder().decode(LexiconStyleSignals.self, from: data) {
            styleSignals = decoded
            punctuationChartData = [
                .init(label: L.analytics_commas, count: decoded.commaCount),
                .init(label: L.analytics_questions, count: decoded.questionCount),
                .init(label: L.analytics_exclamations, count: decoded.exclamationCount),
                .init(label: L.analytics_emoji, count: decoded.emojiCount),
            ]
        } else {
            styleSignals = LexiconStyleSignals()
            punctuationChartData = []
        }

        // Style snippet
        styleSnippet = await lexicon.styleSnippet(maxLength: 400)

        // TinyStyleLM
        if let metrics = await TinyStyleTrainer.shared.latestTrainingMetrics() {
            tinyStyleStatus = String(
                format: "Step %d | loss %.3f -> %.3f | batch %d",
                metrics.step, metrics.lossBefore, metrics.lossAfter, metrics.batchSize
            )
        } else {
            tinyStyleStatus = L.isRussian
                ? "Ожидание данных для обучения"
                : "Waiting for training data"
        }

        // Persisted LLM analysis
        llmAnalysisResult = defaults.string(forKey: Constants.UserDefaultsKeys.lastLLMAnalysis) ?? ""

        // Phase 5: Acceptance data
        let acceptData = await AcceptanceHistoryStore.shared.acceptRate(windowHours: 48)
        acceptedCount = acceptData.accepted
        totalShown = defaults.integer(forKey: Constants.UserDefaultsKeys.totalSuggestionsShown)
        acceptanceRate = totalShown > 0 ? Double(acceptedCount) / Double(totalShown) : 0

        recentAcceptances = await AcceptanceHistoryStore.shared.recentItems(limit: 10)

        // Per-app usage from acceptance history
        let allRecent = await AcceptanceHistoryStore.shared.recentItems(limit: 50)
        var appCounts: [String: Int] = [:]
        for item in allRecent {
            let app = item.appIdentifier ?? "Unknown"
            appCounts[app, default: 0] += 1
        }
        perAppUsage = appCounts
            .sorted { $0.value > $1.value }
            .map { (app: $0.key, count: $0.value) }
    }

    func runLLMAnalysis() async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let privacyEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.privacyModeEnabled)
        if privacyEnabled {
            llmAnalysisResult = L.isRussian
                ? "LLM-анализ отключен: включен Privacy Mode."
                : "LLM analysis is disabled while Privacy Mode is enabled."
            return
        }

        let wordsSection = topWords.prefix(20).map { "\($0.term) (\($0.count))" }.joined(separator: ", ")
        let phrasesSection = topPhrases.prefix(10).map { "\($0.term) (\($0.count))" }.joined(separator: ", ")
        let signals = styleSignals

        let userDataBlock = """
        === USER WRITING DATA ===
        Frequent words: \(wordsSection.isEmpty ? "none" : wordsSection)
        Frequent phrases: \(phrasesSection.isEmpty ? "none" : phrasesSection)
        Total text samples: \(signals.samples)
        Average words per message: \(String(format: "%.1f", signals.averageWords))
        Comma usage: \(signals.commaCount)
        Question marks: \(signals.questionCount)
        Exclamation marks: \(signals.exclamationCount)
        Emoji usage: \(signals.emojiCount)
        Language split: \(languageSplit.map { "\($0.language): \($0.count)" }.joined(separator: ", "))
        Style snippet: \(styleSnippet)
        === END DATA ===
        """

        let systemPrompt = """
        You are a personal writing style analyst. The user has been typing on their device \
        and we collected aggregated statistics about their writing patterns. \
        Analyze the data below and provide a detailed, actionable summary covering:

        1. **Primary language and bilingual patterns** — which language dominates, do they code-switch?
        2. **Vocabulary richness** — are they using diverse words or repeating a small set?
        3. **Sentence structure** — short/long, simple/complex based on avg words and punctuation.
        4. **Emotional tone** — inferred from punctuation (questions = curious, exclamations = expressive, commas = structured).
        5. **Emoji habits** — frequent, rare, or absent.
        6. **Key phrases** — what topics or patterns their frequent phrases reveal.
        7. **Recommendations** — 2-3 specific suggestions for how the AI autocomplete should behave to match this user's style.

        Be concise but insightful. Write in the same language the user primarily uses (based on the data). \
        If bilingual, write the summary in the dominant language. \
        Format with short paragraphs, no bullet points longer than one line.
        """

        let prompt = """
        \(systemPrompt)

        \(userDataBlock)

        Provide your analysis:
        """

        // Use CloudAPIManager to run the analysis
        let cloudManager = CloudAPIManager()
        APIKeyStore.migrateFromUserDefaultsIfNeeded(defaults)
        let apiKey = APIKeyStore.read()
        guard let apiKey, !apiKey.isEmpty else {
            llmAnalysisResult = L.isRussian
                ? "Ошибка: API ключ не задан. Добавьте его в Settings."
                : "Error: API key is missing. Add it in Settings."
            return
        }
        let providerRaw = defaults.string(forKey: Constants.UserDefaultsKeys.cloudProvider) ?? "openAI"
        let provider: CloudProvider = {
            switch providerRaw {
            case "anthropic": return .anthropic
            case "xAI": return .xAI
            case "openRouter": return .openRouter
            default: return .openAI
            }
        }()

        let model: String
        switch provider {
        case .openAI: model = "gpt-4.1-mini"
        case .anthropic: model = "claude-3-5-haiku-latest"
        case .xAI: model = "grok-3-mini-beta"
        case .openRouter: model = "google/gemini-2.5-flash"
        }

        await cloudManager.updateConfiguration(CloudConfiguration(
            provider: provider,
            modelIdentifier: model,
            apiKey: apiKey,
            networkEnabled: !privacyEnabled,
            timeout: 30,
            userStylePrompt: nil,
            userPatterns: [],
            userMemories: [],
            styleInsights: [],
            goodCompletions: [],
            lexiconStyleSnippet: nil
        ))

        let context = TextContext(
            textBefore: prompt,
            textAfter: "",
            appIdentifier: nil,
            language: "en"
        )

        do {
            let completions = try await cloudManager.complete(context: context, maxTokens: 800, count: 1)
            let result = completions.first?.text ?? (L.isRussian ? "Не удалось получить анализ." : "Failed to get analysis.")
            llmAnalysisResult = result
            defaults.set(result, forKey: Constants.UserDefaultsKeys.lastLLMAnalysis)
        } catch {
            llmAnalysisResult = L.isRussian
                ? "Ошибка: \(error.localizedDescription). Проверьте API ключ в настройках."
                : "Error: \(error.localizedDescription). Check your API key in Settings."
        }
    }

    func generateRuleFromAnalytics() {
        let words = topWords.prefix(5).map(\.term).joined(separator: ", ")
        let phrases = topPhrases.prefix(3).map(\.term).joined(separator: ", ")

        var ruleText = L.isRussian
            ? "Пиши в моем стиле. Мои частые слова: \(words). Мои частые фразы: \(phrases)."
            : "Write in my style. My frequent words: \(words). My frequent phrases: \(phrases)."

        // Emoji policy
        if styleSignals.emojiCount > 20 {
            ruleText += L.isRussian ? " Используй эмодзи." : " Use emojis."
        } else if styleSignals.emojiCount == 0 {
            ruleText += L.isRussian ? " Не используй эмодзи." : " Do not use emojis."
        }

        // Message length insights
        let avgWords = styleSignals.averageWords
        if avgWords > 0 && avgWords < 8 {
            ruleText += L.isRussian ? " Пиши короткими фразами." : " Keep completions short."
        } else if avgWords > 20 {
            ruleText += L.isRussian ? " Можно давать длинные автодополнения." : " Longer completions are OK."
        }

        // Punctuation style
        if styleSignals.exclamationCount > styleSignals.questionCount * 2 {
            ruleText += L.isRussian ? " Пользователь экспрессивный — ОК использовать !" : " User is expressive — exclamation marks are fine."
        }
        if styleSignals.commaCount > styleSignals.samples * 3 {
            ruleText += L.isRussian ? " Используй сложные предложения с запятыми." : " Use complex sentences with commas."
        }

        // Acceptance patterns — mention source if clear preference
        if !recentAcceptances.isEmpty {
            let sources = Dictionary(grouping: recentAcceptances, by: \.source)
            if let topSource = sources.max(by: { $0.value.count < $1.value.count }) {
                if topSource.value.count > recentAcceptances.count / 2 {
                    ruleText += L.isRussian
                        ? " Пользователь предпочитает \(topSource.key) подсказки."
                        : " User prefers \(topSource.key) completions."
                }
            }
        }

        defaults.set(ruleText, forKey: Constants.UserDefaultsKeys.personalizationSystemPrompt)

        withAnimation {
            ruleGenerated = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation {
                    self.ruleGenerated = false
                }
            }
        }
    }
}
