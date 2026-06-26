import SwiftUI

struct TinyStyleSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: AITheme.spacingL) {
                premiumSection(title: "TinyStyleLM") {
                    HStack(spacing: AITheme.spacingS) {
                        Circle()
                            .fill(viewModel.tinyStyleStatus.contains("step") ? AITheme.accentMint : AITheme.textTertiary)
                            .frame(width: 8, height: 8)

                        Text(viewModel.tinyStyleStatus)
                            .font(AITheme.fontCaption)
                            .foregroundStyle(AITheme.textSecondary)
                    }

                    Text(L.isRussian
                         ? "TinyStyleLM — маленькая языковая модель, обучаемая на ваших принятых автодополнениях. Она перерасставляет приоритеты подсказок в соответствии с вашим стилем письма."
                         : "TinyStyleLM is a tiny language model trained on your accepted completions. It reranks suggestions to match your writing style.")
                        .font(AITheme.fontCaption)
                        .foregroundStyle(AITheme.textSecondary)

                    Button {
                        Task { await viewModel.runTinyStyleTrainingNow() }
                    } label: {
                        Label(L.settings_trainNow, systemImage: "brain")
                    }
                    .buttonStyle(AIAccentButtonStyle())
                }
            }
            .padding(AITheme.spacingL)
            .padding(.bottom, AITheme.spacingL)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            Task { await viewModel.reloadTinyStyleStatus() }
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
