import Foundation

actor PersonalLexicon {
    // MARK: - Properties

    private let store: LexiconStore
    private let defaults: UserDefaults

    private var cachedSnippet: String?
    private var cachedSnippetLang: String?
    private var cachedSnippetTimestamp: Date?

    // MARK: - Init

    init(
        store: LexiconStore = LexiconStore(),
        appGroupManager: AppGroupManaging = AppGroupManager.shared
    ) {
        self.store = store
        defaults = appGroupManager.sharedUserDefaults() ?? .standard
    }

    // MARK: - Ingestion

    func ingestTypedText(text: String, source: LexiconIngestSource) async {
        let language = LanguageDetect.detect(from: text)
        let tokens = TextNormalization.tokenize(text: text, lang: language)
        guard !tokens.isEmpty else {
            return
        }

        let phrases = TextNormalization.extractPhrases(tokens: tokens)
        let now = Date()

        do {
            try await store.recordWords(tokens, lang: language, at: now)
            try await store.recordPhrases(phrases, lang: language, at: now)
        } catch {
            // Never block typing UX on lexicon failures.
        }

        updateStyleSignals(from: text)
        invalidateSnippetCache()
    }

    func ingestAcceptedCompletion(context: String, completion: String) async {
        await ingestTypedText(text: completion, source: .keyboardAccepted)

        let contextTokens = TextNormalization.tokenize(
            text: String(context.suffix(140)),
            lang: LanguageDetect.detect(from: context)
        )
        let completionLang = LanguageDetect.detect(from: completion)
        let completionTokens = TextNormalization.tokenize(text: completion, lang: completionLang)

        let boundaryTokens = Array(contextTokens.suffix(3)) + completionTokens
        let boundaryPhrases = TextNormalization.extractPhrases(tokens: boundaryTokens)

        do {
            try await store.recordPhrases(boundaryPhrases, lang: completionLang, at: Date())
        } catch {
            // Keep completion flow resilient.
        }

        invalidateSnippetCache()
    }

    // MARK: - Query

    func styleSnippet(preferredLanguage: String? = nil, maxLength: Int = 400) async -> String {
        let language = await resolvedLanguage(preferredLanguage)

        if let cachedSnippet,
           let cachedSnippetLang,
           let cachedSnippetTimestamp,
           cachedSnippetLang == language,
           Date().timeIntervalSince(cachedSnippetTimestamp) < 5 {
            return cachedSnippet
        }

        let words = (try? await store.topWords(lang: language, limit: 20)) ?? []
        let phrases = (try? await store.topPhrases(lang: language, limit: 10)) ?? []
        let signals = loadStyleSignals()

        let snippet = StyleSnippetBuilder.build(
            language: language,
            words: words,
            phrases: phrases,
            signals: signals,
            maxLength: maxLength
        )

        cachedSnippet = snippet
        cachedSnippetLang = language
        cachedSnippetTimestamp = Date()

        return snippet
    }

    func topWords(lang: String, limit: Int) async -> [LexiconRankedItem] {
        (try? await store.topWords(lang: lang, limit: limit)) ?? []
    }

    func topPhrases(lang: String, limit: Int, minCount: Int = 3) async -> [LexiconRankedItem] {
        (try? await store.topPhrases(lang: lang, limit: limit, minCount: minCount)) ?? []
    }

    func clearAll() async {
        try? await store.clearAll()
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.lexiconStyleStats)
        invalidateSnippetCache()
    }

    // MARK: - Private

    private func resolvedLanguage(_ preferredLanguage: String?) async -> String {
        if let preferredLanguage {
            let normalized = preferredLanguage.lowercased()
            return normalized.hasPrefix("ru") ? "ru" : "en"
        }

        let ruScore = ((try? await store.topWords(lang: "ru", limit: 1).first?.score) ?? 0)
        let enScore = ((try? await store.topWords(lang: "en", limit: 1).first?.score) ?? 0)
        return ruScore >= enScore ? "ru" : "en"
    }

    private func updateStyleSignals(from text: String) {
        var signals = loadStyleSignals()
        signals.samples += 1
        signals.totalWords += TextNormalization.tokenize(
            text: text,
            lang: LanguageDetect.detect(from: text)
        ).count

        signals.commaCount += text.filter { $0 == "," }.count
        signals.exclamationCount += text.filter { $0 == "!" }.count
        signals.questionCount += text.filter { $0 == "?" }.count
        signals.emojiCount += TextNormalization.emojiCount(in: text)

        saveStyleSignals(signals)
    }

    private func loadStyleSignals() -> LexiconStyleSignals {
        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.lexiconStyleStats),
              let decoded = try? JSONDecoder().decode(LexiconStyleSignals.self, from: data) else {
            return LexiconStyleSignals()
        }
        return decoded
    }

    private func saveStyleSignals(_ signals: LexiconStyleSignals) {
        guard let data = try? JSONEncoder().encode(signals) else {
            return
        }
        defaults.set(data, forKey: Constants.UserDefaultsKeys.lexiconStyleStats)
    }

    private func invalidateSnippetCache() {
        cachedSnippet = nil
        cachedSnippetLang = nil
        cachedSnippetTimestamp = nil
    }
}
