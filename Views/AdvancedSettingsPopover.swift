import SwiftUI

enum AdvancedSection: String, CaseIterable, Identifiable {
    case general   = "general"
    case apps      = "apps"
    case models    = "models"
    case memory    = "memory"
    case analytics = "analytics"
    case tinyStyle = "tinyStyle"
    case setup     = "setup"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:   return "gearshape"
        case .apps:      return "app.badge"
        case .models:    return "cpu"
        case .memory:    return "brain.head.profile"
        case .analytics: return "chart.bar.xaxis"
        case .tinyStyle: return "brain"
        case .setup:     return "flag.checkered"
        }
    }

    var label: String {
        switch self {
        case .general:   return L.isRussian ? "Общие"      : "General"
        case .apps:      return L.isRussian ? "Приложения" : "Apps"
        case .models:    return L.isRussian ? "Модели"      : "Models"
        case .memory:    return L.isRussian ? "Память"      : "Memory"
        case .analytics: return L.isRussian ? "Аналитика"   : "Analytics"
        case .tinyStyle: return "TinyStyleLM"
        case .setup:     return L.isRussian ? "Настройка"   : "Setup"
        }
    }

    var subtitle: String {
        switch self {
        case .general:   return L.isRussian ? "Язык, запуск, доступы" : "Language, launch, access"
        case .apps:      return L.isRussian ? "Правила по приложениям" : "Per-app rules"
        case .models:    return L.isRussian ? "GGUF каталог"          : "GGUF catalog"
        case .memory:    return L.isRussian ? "Словарь, профиль"      : "Dictionary, profile"
        case .analytics: return L.isRussian ? "Метрики, анализ"       : "Metrics, analysis"
        case .tinyStyle: return L.isRussian ? "Обучение стилю"        : "Style training"
        case .setup:     return L.isRussian ? "Гайд настройки"        : "Setup guide"
        }
    }
}

struct AdvancedSettingsPopover: View {
    let onSelect: (AdvancedSection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [
        GridItem(.flexible(), spacing: AITheme.spacingM),
        GridItem(.flexible(), spacing: AITheme.spacingM)
    ]

    var body: some View {
        VStack(spacing: AITheme.spacingM) {
            Text(L.isRussian ? "Дополнительно" : "Advanced")
                .font(AITheme.fontHeading)
                .foregroundStyle(AITheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: AITheme.spacingM) {
                ForEach(AdvancedSection.allCases) { section in
                    Button {
                        onSelect(section)
                    } label: {
                        VStack(spacing: AITheme.spacingS) {
                            Image(systemName: section.icon)
                                .font(.title3)
                                .foregroundStyle(AITheme.chromeSilver)
                                .frame(height: 22)

                            Text(section.label)
                                .font(AITheme.fontCaptionBold)
                                .foregroundStyle(AITheme.textPrimary)
                                .lineLimit(1)

                            Text(section.subtitle)
                                .font(AITheme.fontCaption2)
                                .foregroundStyle(AITheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AITheme.spacingM)
                        .padding(.horizontal, AITheme.spacingS)
                        .background(
                            RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                                .stroke(AITheme.borderSubtle, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AITheme.spacingL)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AITheme.bgSurface.opacity(0.98))
        )
    }
}
