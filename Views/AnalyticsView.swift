import Charts
import SwiftUI

struct AnalyticsView: View {
    @StateObject private var viewModel = AnalyticsViewModel()
    @State private var wordsPhraseTab = 0
    @State private var hoveredWordsPhraseTab: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160), spacing: AITheme.spacingM)]
    }

    private var totalWordMentions: Int {
        viewModel.topWords.reduce(0) { $0 + $1.count }
    }

    private var totalPhraseMentions: Int {
        viewModel.topPhrases.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AITheme.spacingM + 4) {
                summaryDashboard
                acceptanceDashboard
                actionableInsightsSection

                if !viewModel.topPhrases.isEmpty || !viewModel.topWords.isEmpty {
                    autoRuleSection
                }

                perAppUsageSection
                recentAcceptancesSection
                wordsPhraseSection
                languageSplitSection
                styleSignalsSection
                llmAnalysisSection
            }
            .padding(AITheme.spacingL)
        }
        .onAppear {
            Task { await viewModel.reload() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .aiCompleteRefreshRequested)
                .receive(on: RunLoop.main)
        ) { _ in
            Task { await viewModel.reload() }
        }
    }

    private var actionableInsightsSection: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingS + 2) {
            AITheme.sectionHeader(
                L.isRussian ? "Практические инсайты" : "Actionable Insights",
                icon: "lightbulb.max"
            )

            ForEach(analyticsRecommendations, id: \.title) { recommendation in
                HStack(alignment: .top, spacing: AITheme.spacingS) {
                    Circle()
                        .fill(recommendation.priorityColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recommendation.title)
                            .font(AITheme.fontCaptionBold)
                        Text(recommendation.subtitle)
                            .font(AITheme.fontCaption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(recommendation.badge)
                        .font(AITheme.fontCaption2.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .padding(.vertical, 2)
            }
        }
        .liquidChromiumCard()
    }

    private var analyticsRecommendations: [AnalyticsRecommendation] {
        var items: [AnalyticsRecommendation] = []

        let avgWords = viewModel.styleSignals.averageWords
        if avgWords < 4 {
            items.append(
                .init(
                    title: L.isRussian ? "Короткие сообщения" : "Short-message pattern",
                    subtitle: L.isRussian
                        ? "Для естественного продолжения держите 1-2 кратких варианта в top-1."
                        : "Bias top-1 toward concise continuations for chat-like flow.",
                    badge: String(format: "%.1f", avgWords),
                    priorityColor: .orange
                )
            )
        } else {
            items.append(
                .init(
                    title: L.isRussian ? "Средняя длина стабильна" : "Stable message length",
                    subtitle: L.isRussian
                        ? "Можно давать 2-3 варианта разной длины без потери релевантности."
                        : "Safe to offer mixed short/medium completions.",
                    badge: String(format: "%.1f", avgWords),
                    priorityColor: AITheme.accentMint
                )
            )
        }

        let languageCount = viewModel.languageSplit.count
        items.append(
            .init(
                title: languageCount > 1
                    ? (L.isRussian ? "Смешанный языковой поток" : "Mixed-language usage")
                    : (L.isRussian ? "Один основной язык" : "Single-language usage"),
                subtitle: languageCount > 1
                    ? (L.isRussian
                        ? "Добавьте строгую фиксацию языка в custom prompt."
                        : "Add stricter language lock in prompt.")
                    : (L.isRussian
                        ? "Автоопределение языка работает стабильно."
                        : "Auto language detection looks stable."),
                badge: "\(languageCount)",
                priorityColor: languageCount > 1 ? .orange : .blue
            )
        )

        let emojiCount = viewModel.styleSignals.emojiCount
        items.append(
            .init(
                title: L.isRussian ? "Эмоциональность тона" : "Tone expressiveness",
                subtitle: emojiCount > 20
                    ? (L.isRussian
                        ? "Сохраняйте эмодзи в продолжениях для естественности."
                        : "Keep emoji in suggestions to preserve user tone.")
                    : (L.isRussian
                        ? "Фокус на нейтральном деловом стиле."
                        : "Bias completions toward neutral/professional tone."),
                badge: "\(emojiCount)",
                priorityColor: emojiCount > 20 ? AITheme.accentMint : .gray
            )
        )

        return items
    }

    // MARK: - Summary Dashboard

    private var acceptanceDashboard: some View {
        LazyVGrid(columns: summaryColumns, spacing: AITheme.spacingM) {
            metricCard(
                icon: "checkmark.circle",
                title: L.isRussian ? "Принято" : "Accepted",
                value: "\(viewModel.acceptedCount)",
                subtitle: L.isRussian ? "за 48ч" : "in 48h"
            )
            metricCard(
                icon: "eye",
                title: L.isRussian ? "Показано" : "Shown",
                value: "\(viewModel.totalShown)",
                subtitle: L.isRussian ? "всего" : "total"
            )
            metricCard(
                icon: "percent",
                title: L.isRussian ? "Принятие" : "Accept Rate",
                value: String(format: "%.0f%%", viewModel.acceptanceRate * 100),
                subtitle: viewModel.acceptanceRate > 0.5
                    ? (L.isRussian ? "отлично" : "great")
                    : (L.isRussian ? "норма" : "normal")
            )
        }
    }

    private var perAppUsageSection: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingS + 4) {
            AITheme.sectionHeader(
                L.isRussian ? "По приложениям" : "Per-App Usage",
                icon: "square.grid.2x2"
            )

            if viewModel.perAppUsage.isEmpty {
                AITheme.emptyState(
                    icon: "app.dashed",
                    title: L.isRussian ? "Нет данных" : "No data yet",
                    subtitle: L.isRussian
                        ? "Примите несколько подсказок в разных приложениях"
                        : "Accept some completions in different apps"
                )
            } else {
                ForEach(Array(viewModel.perAppUsage.prefix(6).enumerated()), id: \.offset) { _, entry in
                    HStack {
                        Text(appDisplayName(entry.app))
                            .font(AITheme.fontCaptionBold)
                            .lineLimit(1)
                        Spacer()
                        Text("\(entry.count)")
                            .font(AITheme.fontCaption.monospacedDigit().bold())
                            .foregroundStyle(AITheme.accentMint)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .liquidChromiumCard()
    }

    private var recentAcceptancesSection: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingS + 4) {
            AITheme.sectionHeader(
                L.isRussian ? "Последние принятые" : "Recent Acceptances",
                icon: "clock.arrow.circlepath"
            )

            if viewModel.recentAcceptances.isEmpty {
                AITheme.emptyState(
                    icon: "tray",
                    title: L.isRussian ? "Нет данных" : "No data yet",
                    subtitle: L.isRussian
                        ? "Принятые подсказки появятся здесь"
                        : "Accepted completions will appear here"
                )
            } else {
                ForEach(viewModel.recentAcceptances) { item in
                    HStack(alignment: .top, spacing: AITheme.spacingS) {
                        Text(item.acceptedText)
                            .font(AITheme.fontCaption)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.source)
                                .font(AITheme.fontCaption2)
                                .foregroundStyle(AITheme.accentMint)
                            Text(item.timestamp, style: .relative)
                                .font(AITheme.fontCaption2)
                                .foregroundStyle(AITheme.textTertiary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .liquidChromiumCard()
    }

    private func appDisplayName(_ bundleId: String) -> String {
        if bundleId == "Unknown" { return bundleId }
        return bundleId.components(separatedBy: ".").last?.capitalized ?? bundleId
    }

    private var summaryDashboard: some View {
        LazyVGrid(columns: summaryColumns, spacing: AITheme.spacingM) {
            metricCard(
                icon: "doc.text",
                title: L.isRussian ? "Образцов" : "Samples",
                value: "\(viewModel.styleSignals.samples)",
                subtitle: L.isRussian ? "текстовых" : "text"
            )
            metricCard(
                icon: "globe",
                title: L.isRussian ? "Языки" : "Languages",
                value: "\(viewModel.languageSplit.count)",
                subtitle: viewModel.languageSplit.map(\.language).joined(separator: ", ")
            )
            metricCard(
                icon: "textformat.size",
                title: L.isRussian ? "Ср. слов" : "Avg words",
                value: String(format: "%.1f", viewModel.styleSignals.averageWords),
                subtitle: L.isRussian ? "на сообщ." : "per msg"
            )
            metricCard(
                icon: "face.smiling",
                title: L.isRussian ? "Эмодзи" : "Emoji",
                value: "\(viewModel.styleSignals.emojiCount)",
                subtitle: viewModel.styleSignals.emojiCount > 20
                    ? (L.isRussian ? "активно" : "active")
                    : (L.isRussian ? "редко" : "rare")
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.isRussian ? "Сводка по стилю письма" : "Writing style summary")
    }

    private func metricCard(icon: String, title: String, value: String, subtitle: String) -> some View {
        VStack(spacing: AITheme.spacingS) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AITheme.accentGradient)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(AITheme.textPrimary)
            Text(title)
                .font(AITheme.fontCaptionBold)
                .foregroundStyle(AITheme.textSecondary)
            Text(subtitle)
                .font(AITheme.fontCaption2)
                .foregroundStyle(AITheme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .liquidChromiumCard(padding: AITheme.spacingM)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(subtitle)")
    }

    // MARK: - Auto Rule

    private var autoRuleSection: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingS) {
            AITheme.sectionHeader(
                L.isRussian ? "Авто-Правило" : "Auto-Rule",
                icon: "wand.and.stars"
            )

            Text(L.isRussian
                 ? "Создайте системный промпт на основе вашего стиля, чтобы модель лучше подражала вам."
                 : "Create a system prompt based on your style so the model better mimics you.")
                .font(AITheme.fontCaption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    viewModel.generateRuleFromAnalytics()
                } label: {
                    Label(
                        L.isRussian ? "Применить как Системный Промпт" : "Apply as System Prompt",
                        systemImage: "wand.and.stars"
                    )
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(L.isRussian
                    ? "Создаст правило на основе аналитики"
                    : "Will create a rule based on analytics")

                if viewModel.ruleGenerated {
                    Label(
                        L.isRussian ? "Сохранено!" : "Saved!",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(AITheme.fontCaption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
                }
            }
        }
        .liquidChromiumCard()
    }

    // MARK: - Words & Phrases

    private var wordsPhraseSection: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingS + 4) {
            HStack {
                AITheme.sectionHeader(
                    L.isRussian ? "Частотность" : "Frequency",
                    icon: "chart.bar"
                )
                Spacer()
                wordsPhraseTabs
            }

            if wordsPhraseTab == 0 {
                wordsChart
            } else {
                phrasesChart
            }
        }
        .liquidChromiumCard()
    }

    private var wordsPhraseTabs: some View {
        HStack(spacing: 6) {
            tabButton(
                id: 0,
                title: L.isRussian ? "Слова" : "Words"
            )
            tabButton(
                id: 1,
                title: L.isRussian ? "Фразы" : "Phrases"
            )
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AITheme.bgSurfaceElevated.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AITheme.borderSubtle, lineWidth: 0.7)
        )
        .frame(width: 220)
    }

    private func tabButton(id: Int, title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                wordsPhraseTab = id
            }
        } label: {
            Text(title)
                .font(AITheme.fontCaptionBold)
                .foregroundStyle(wordsPhraseTab == id ? AITheme.textPrimary : AITheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            wordsPhraseTab == id
                                ? AITheme.accentMint.opacity(0.16)
                                : (hoveredWordsPhraseTab == id ? AITheme.borderSubtle : Color.clear)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            wordsPhraseTab == id
                                ? AITheme.borderHover
                                : Color.clear,
                            lineWidth: 0.8
                        )
                )
                .scaleEffect(hoveredWordsPhraseTab == id ? 1.015 : 1.0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hoveredWordsPhraseTab == id)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: wordsPhraseTab == id)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredWordsPhraseTab = hovering ? id : (hoveredWordsPhraseTab == id ? nil : hoveredWordsPhraseTab)
        }
    }

    private var wordsChart: some View {
        Group {
            if viewModel.topWords.isEmpty {
                AITheme.emptyState(
                    icon: "textformat",
                    title: L.isRussian ? "Нет данных" : "No data yet",
                    subtitle: L.isRussian
                        ? "Начните печатать, чтобы увидеть частые слова"
                        : "Start typing to see your frequent words"
                )
            } else {
                VStack(alignment: .leading, spacing: AITheme.spacingS) {
                    chartMetaRow(
                        label: L.isRussian ? "Сумма вхождений" : "Total mentions",
                        value: "\(totalWordMentions)"
                    )

                    Chart(Array(viewModel.topWords.enumerated()), id: \.element.id) { index, item in
                        BarMark(
                            x: .value("Count", item.count),
                            y: .value("Word", item.term)
                        )
                        .foregroundStyle(chromiumBarGradient(index: index, total: viewModel.topWords.count))
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("\(item.count)")
                                .font(AITheme.fontCaption2.monospacedDigit())
                                .foregroundStyle(AITheme.textSecondary)
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(chromiumPlotBackground)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4))
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let term = value.as(String.self) {
                                    Text(term).font(AITheme.fontCaption)
                                }
                            }
                        }
                    }
                    .frame(height: CGFloat(viewModel.topWords.count * 30 + 28))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L.isRussian ? "График частых слов" : "Top Words Chart")
                    .accessibilityValue("\(viewModel.topWords.count) \(L.isRussian ? "слов" : "words")")
                }
            }
        }
    }

    private var phrasesChart: some View {
        Group {
            if viewModel.topPhrases.isEmpty {
                AITheme.emptyState(
                    icon: "text.quote",
                    title: L.isRussian ? "Нет данных" : "No data yet",
                    subtitle: L.isRussian
                        ? "Фразы появятся после нескольких сессий"
                        : "Phrases will appear after a few sessions"
                )
            } else {
                VStack(alignment: .leading, spacing: AITheme.spacingS) {
                    chartMetaRow(
                        label: L.isRussian ? "Сумма вхождений" : "Total mentions",
                        value: "\(totalPhraseMentions)"
                    )

                    Chart(Array(viewModel.topPhrases.enumerated()), id: \.element.id) { index, item in
                        BarMark(
                            x: .value("Count", item.count),
                            y: .value("Phrase", item.term)
                        )
                        .foregroundStyle(chromiumSecondaryGradient(index: index, total: viewModel.topPhrases.count))
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("\(item.count)")
                                .font(AITheme.fontCaption2.monospacedDigit())
                                .foregroundStyle(AITheme.textSecondary)
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(chromiumPlotBackground)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let phrase = value.as(String.self) {
                                    Text(phrase).font(AITheme.fontCaption2)
                                }
                            }
                        }
                    }
                    .frame(height: CGFloat(viewModel.topPhrases.count * 34 + 24))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L.isRussian ? "График частых фраз" : "Top Phrases Chart")
                    .accessibilityValue("\(viewModel.topPhrases.count) \(L.isRussian ? "фраз" : "phrases")")
                }
            }
        }
    }

    // MARK: - Language Split

    private var languageSplitSection: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingS + 4) {
            AITheme.sectionHeader(L.analytics_languageSplit, icon: "globe")

            if viewModel.languageSplit.isEmpty {
                AITheme.emptyState(
                    icon: "globe",
                    title: L.isRussian ? "Нет данных" : "No data",
                    subtitle: L.analytics_noData
                )
            } else {
                let total = max(1, viewModel.languageSplit.reduce(0) { $0 + $1.count })
                VStack(spacing: AITheme.spacingS) {
                    ZStack {
                        Chart(viewModel.languageSplit) { item in
                            SectorMark(
                                angle: .value("Count", item.count),
                                innerRadius: .ratio(0.58),
                                angularInset: 2
                            )
                            .foregroundStyle(languageColor(for: item.language).gradient)
                        }
                        .chartLegend(.hidden)
                        .frame(height: 220)

                        VStack(spacing: 2) {
                            Text("\(total)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(AITheme.textPrimary)
                            Text(L.isRussian ? "сэмплов" : "samples")
                                .font(AITheme.fontCaption2)
                                .foregroundStyle(AITheme.textSecondary)
                        }
                    }

                    HStack(spacing: AITheme.spacingS) {
                        ForEach(viewModel.languageSplit) { item in
                            let share = (Double(item.count) / Double(total)) * 100
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(languageColor(for: item.language))
                                    .frame(width: 8, height: 8)
                                Text("\(item.language) \(Int(share.rounded()))%")
                                    .font(AITheme.fontCaption2.monospacedDigit())
                                    .foregroundStyle(AITheme.textSecondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.isRussian ? "График распределения языков" : "Language Split Chart")
                .accessibilityValue("\(viewModel.languageSplit.count) \(L.isRussian ? "языков" : "languages")")
            }
        }
        .liquidChromiumCard()
    }

    // MARK: - Style Signals

    private var styleSignalsSection: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingS + 4) {
            AITheme.sectionHeader(L.analytics_styleProfile, icon: "waveform.path.ecg")

            if viewModel.styleSignals.samples == 0 {
                AITheme.emptyState(
                    icon: "person.text.rectangle",
                    title: L.isRussian ? "Профиль ещё не создан" : "Profile not created yet",
                    subtitle: L.isRussian ? "Начните печатать для формирования профиля" : "Start typing to build your style profile"
                )
            } else {
                HStack(spacing: AITheme.spacingM) {
                    VStack(alignment: .leading, spacing: AITheme.spacingS) {
                        styleRow(L.analytics_samples, value: "\(viewModel.styleSignals.samples)")
                        styleRow(L.analytics_avgWords, value: String(format: "%.1f", viewModel.styleSignals.averageWords))
                        styleRow(L.analytics_commas, value: "\(viewModel.styleSignals.commaCount)")
                        styleRow(L.analytics_questions, value: "\(viewModel.styleSignals.questionCount)")
                        styleRow(L.analytics_exclamations, value: "\(viewModel.styleSignals.exclamationCount)")
                        styleRow(L.analytics_emoji, value: "\(viewModel.styleSignals.emojiCount)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Chart(Array(viewModel.punctuationChartData.enumerated()), id: \.element.id) { index, item in
                        BarMark(
                            x: .value("Type", item.label),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(chromiumBarGradient(index: index, total: max(1, viewModel.punctuationChartData.count)))
                        .annotation(position: .top) {
                            Text("\(item.count)")
                                .font(AITheme.fontCaption2.monospacedDigit())
                                .foregroundStyle(AITheme.textSecondary)
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(chromiumPlotBackground)
                    }
                    .frame(width: 260, height: 156)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L.isRussian ? "График пунктуации" : "Punctuation Chart")
                }

                if !viewModel.styleSnippet.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: AITheme.spacingXS) {
                        Text(L.analytics_snippet)
                            .font(AITheme.fontCaptionBold)
                            .foregroundStyle(.secondary)
                        Text(viewModel.styleSnippet)
                            .font(AITheme.fontCaption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .liquidChromiumCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.isRussian ? "Секция: Профиль стиля" : "Section: Style Profile")
    }

    // MARK: - LLM Analysis

    private var llmAnalysisSection: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingS + 4) {
            AITheme.sectionHeader(L.analytics_llmAnalysis, icon: "brain.head.profile")

            if viewModel.isAnalyzing {
                HStack(spacing: AITheme.spacingS) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L.analytics_analyzing)
                        .font(AITheme.fontCaption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                if !viewModel.llmAnalysisResult.isEmpty {
                    Text(viewModel.llmAnalysisResult)
                        .font(AITheme.fontCaption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await viewModel.runLLMAnalysis() }
                } label: {
                    Label(L.analytics_analyzeButton, systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()
            HStack(spacing: AITheme.spacingS) {
                Image(systemName: "brain")
                    .foregroundStyle(.secondary)
                Text(viewModel.tinyStyleStatus)
                    .font(AITheme.fontCaption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .liquidChromiumCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.isRussian ? "Секция: AI анализ" : "Section: AI Analysis")
    }

    // MARK: - Helpers

    private var chromiumPlotBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        AITheme.bgSurfaceElevated.opacity(0.92),
                        AITheme.bgSurface.opacity(0.82),
                        AITheme.bgBase.opacity(0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AITheme.borderSubtle,
                                AITheme.accentMint.opacity(0.18),
                                AITheme.borderSubtle
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            )
    }

    private func chartMetaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AITheme.fontCaption2)
                .foregroundStyle(AITheme.textSecondary)
            Spacer()
            Text(value)
                .font(AITheme.fontCaption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(AITheme.textPrimary)
        }
    }

    private func styleRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AITheme.fontCaption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(AITheme.fontCaption.monospacedDigit().bold())
        }
    }

    private func chromiumBarGradient(index: Int, total: Int) -> LinearGradient {
        let normalized = Double(index) / Double(max(1, total - 1))
        let top = Color(
            red: 0.88 - normalized * 0.12,
            green: 0.95 - normalized * 0.16,
            blue: 0.93 - normalized * 0.14
        )
        let bottom = Color(
            red: 0.22 + normalized * 0.16,
            green: 0.54 + normalized * 0.20,
            blue: 0.48 + normalized * 0.18
        )
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    private func chromiumSecondaryGradient(index: Int, total: Int) -> LinearGradient {
        let normalized = Double(index) / Double(max(1, total - 1))
        let top = Color(
            red: 0.80 - normalized * 0.06,
            green: 0.86 - normalized * 0.08,
            blue: 0.95 - normalized * 0.11
        )
        let bottom = Color(
            red: 0.24 + normalized * 0.14,
            green: 0.40 + normalized * 0.16,
            blue: 0.58 + normalized * 0.18
        )
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func languageColor(for language: String) -> Color {
        switch language.uppercased() {
        case "RU": return AITheme.chromeBlue
        case "EN": return AITheme.accentMint
        default: return AITheme.liquidChromeBase.opacity(0.82)
        }
    }
}

private struct AnalyticsRecommendation {
    let title: String
    let subtitle: String
    let badge: String
    let priorityColor: Color
}

// LiquidChromiumCardModifier moved to Theme.swift
