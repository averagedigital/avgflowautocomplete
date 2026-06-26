import SwiftUI

struct MemorySettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showClearConfirmation = false
    @State private var isClearing = false

    var body: some View {
        ScrollView {
            VStack(spacing: AITheme.spacingL) {
                memorySection
                styleProfileSection
                goodCompletionsSection
                clearSection
            }
            .padding(AITheme.spacingL)
            .padding(.bottom, AITheme.spacingL)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            L.settings_clearConfirmTitle,
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(L.settings_clear, role: .destructive) {
                Task {
                    isClearing = true
                    await viewModel.clearUserDictionary()
                    isClearing = false
                }
            }
            Button(L.settings_cancel, role: .cancel) {}
        } message: {
            Text(L.settings_clearConfirmMessage)
        }
        .onAppear {
            Task {
                await viewModel.reloadMemories()
                await viewModel.reloadPersonalizationSignals()
            }
        }
    }

    // MARK: - Memory

    @ViewBuilder
    private var memorySection: some View {
        premiumSection(title: L.settings_memoryAbout) {
            HStack {
                TextField(L.settings_addMemoryPlaceholder, text: $viewModel.memoryInput)
                    .textFieldStyle(.roundedBorder)
                Button(L.settings_addMemory) {
                    Task { await viewModel.addMemory() }
                }
                .disabled(viewModel.memoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.memories.isEmpty {
                Text(L.settings_noMemories)
                    .font(AITheme.fontCaption)
                    .foregroundStyle(AITheme.textSecondary)
            } else {
                ForEach(viewModel.memories) { memory in
                    HStack(alignment: .top) {
                        Text(memory.text)
                            .font(AITheme.fontCaption)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await viewModel.deleteMemory(id: memory.id) }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Style Profile

    @ViewBuilder
    private var styleProfileSection: some View {
        premiumSection(title: L.settings_styleProfile) {
            if viewModel.styleInsights.isEmpty {
                Text(L.settings_styleProfileHint)
                    .font(AITheme.fontCaption)
                    .foregroundStyle(AITheme.textSecondary)
            } else {
                ForEach(viewModel.styleInsights, id: \.self) { insight in
                    Text("• \(insight)")
                        .font(AITheme.fontCaption)
                }
            }
        }
    }

    // MARK: - Good Completions

    @ViewBuilder
    private var goodCompletionsSection: some View {
        premiumSection(title: L.settings_goodCompletions) {
            if viewModel.goodCompletions.isEmpty {
                Text(L.settings_noCompletions)
                    .font(AITheme.fontCaption)
                    .foregroundStyle(AITheme.textSecondary)
            } else {
                ForEach(viewModel.goodCompletions, id: \.self) { pair in
                    Text(pair)
                        .font(AITheme.fontCaption)
                        .foregroundStyle(AITheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Clear

    @ViewBuilder
    private var clearSection: some View {
        premiumSection(title: L.isRussian ? "Данные" : "Data") {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                if isClearing {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(L.settings_clearing)
                    }
                } else {
                    Text(L.settings_clearDictionary)
                }
            }
            .disabled(isClearing)
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
