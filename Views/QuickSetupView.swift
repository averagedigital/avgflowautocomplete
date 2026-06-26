import SwiftUI
import ServiceManagement

/// Быстрая настройка — всё необходимое на одном экране
struct QuickSetupView: View {
    @ObservedObject var permissionsManager: PermissionsManager

    // Cloud settings
    @State private var cloudProvider: SettingsViewModel.CloudProviderOption = .openAI
    @State private var apiKey: String = ""
    @State private var cloudModelIdentifier: String = "gpt-4.1-nano"
    @State private var completionMode: String = "hybrid"
    @State private var loginItemEnabled = false

    private let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard

    private var cloudModels: [SettingsViewModel.CloudModelOption] {
        SettingsViewModel.cloudModels(for: cloudProvider)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ── Hero ────────────────────────────
                heroCard

                // ── Permissions ─────────────────────
                permissionsCard

                // ── Provider + Key ──────────────────
                providerCard

                // ── Mode ────────────────────────────
                modeCard

                // ── Auto-Launch ─────────────────────
                autoLaunchCard
            }
            .padding(24)
        }
        .background(AITheme.backgroundGradient.ignoresSafeArea())
        .onAppear { loadSettings() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Hero
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var heroCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Рисованный логотип
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AITheme.accentGradient)
                        .frame(width: 56, height: 56)
                        .shadow(color: AITheme.accent.opacity(0.3), radius: 10, y: 4)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AIComplete")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AITheme.textPrimary)
                    Text(L.isRussian
                         ? "Умный автокомплит для всего macOS"
                         : "Smart autocomplete for all of macOS")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AITheme.textSecondary)
                }
                Spacer()
            }
        }
        .aiCard(tint: AITheme.cream.opacity(0.3))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Permissions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AITheme.sectionHeader(L.isRussian ? "Разрешения" : "Permissions", icon: "lock.shield")

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(permissionsManager.isAccessibilityGranted
                              ? AITheme.accent.opacity(0.2)
                              : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: permissionsManager.isAccessibilityGranted
                          ? "checkmark.shield.fill"
                          : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(permissionsManager.isAccessibilityGranted
                                         ? AITheme.accentDeep
                                         : .orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Accessibility API")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        AITheme.statusPill(
                            permissionsManager.isAccessibilityGranted
                                ? (L.isRussian ? "Включено" : "Granted")
                                : (L.isRussian ? "Требуется" : "Required"),
                            isPositive: permissionsManager.isAccessibilityGranted
                        )
                    }
                    Text(L.isRussian
                         ? "Нужен для чтения текста и показа подсказок поверх окон"
                         : "Required to read text and show suggestions over windows")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(AITheme.textSecondary)
                }

                Spacer()

                if !permissionsManager.isAccessibilityGranted {
                    Button {
                        permissionsManager.openAccessibilitySettings()
                    } label: {
                        Label(L.isRussian ? "Открыть" : "Open Settings",
                              systemImage: "gear")
                    }
                    .buttonStyle(AIAccentButtonStyle())
                }
            }

            if !permissionsManager.isAccessibilityGranted {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AITheme.accent)
                    Text(L.isRussian
                         ? "После включения в Системных настройках — перезапустите приложение"
                         : "After enabling in System Settings — restart the app")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(AITheme.textSecondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AITheme.peach.opacity(0.3))
                )
            }
        }
        .aiCard(tint: permissionsManager.isAccessibilityGranted
                ? AITheme.sectionTint
                : AITheme.peach.opacity(0.15))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Provider
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AITheme.sectionHeader(L.isRussian ? "Облачный провайдер" : "Cloud Provider", icon: "cloud")

            // Provider picker
            HStack(spacing: 8) {
                ForEach(SettingsViewModel.CloudProviderOption.allCases) { provider in
                    Button {
                        cloudProvider = provider
                        if !cloudModels.contains(where: { $0.id == cloudModelIdentifier }) {
                            cloudModelIdentifier = cloudModels.first?.id ?? ""
                        }
                        persistSettings()
                    } label: {
                        Text(provider.title)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous)
                                    .fill(cloudProvider == provider
                                          ? AITheme.accent.opacity(0.2)
                                          : AITheme.accentMist)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous)
                                    .stroke(cloudProvider == provider
                                            ? AITheme.accent
                                            : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Model picker
            Picker(L.isRussian ? "Модель" : "Model", selection: $cloudModelIdentifier) {
                ForEach(cloudModels) { model in
                    Text(model.title).tag(model.id)
                }
            }
            .onChange(of: cloudModelIdentifier) { persistSettings() }

            // API Key
            HStack(spacing: 10) {
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: 300)
                    .autocorrectionDisabled()
                    .onChange(of: apiKey) { persistSettings() }

                if apiKey.isEmpty {
                    providerLink
                }
            }

            if apiKey.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "key")
                        .foregroundStyle(.orange)
                    Text(L.isRussian
                         ? "Добавьте API ключ для облачных подсказок"
                         : "Add API key to enable cloud completions")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
        }
        .aiCard()
    }

    @ViewBuilder
    private var providerLink: some View {
        let (title, url) = providerLinkData
        Link(destination: url) {
            Label(title, systemImage: "arrow.up.right.square")
                .font(.system(.caption, design: .rounded))
        }
    }

    private var providerLinkData: (String, URL) {
        switch cloudProvider {
        case .xAI:
            return ("Get Key", URL(string: "https://console.x.ai/")!)
        case .openRouter:
            return ("Get Key", URL(string: "https://openrouter.ai/keys")!)
        case .anthropic:
            return ("Get Key", URL(string: "https://console.anthropic.com/")!)
        default:
            return ("Get Key", URL(string: "https://platform.openai.com/api-keys")!)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Mode
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AITheme.sectionHeader(L.isRussian ? "Режим работы" : "Completion Mode", icon: "slider.horizontal.3")

            HStack(spacing: 10) {
                modeButton(id: "localOnly",
                           title: "Local",
                           subtitle: LocalModelManager.isAvailable
                               ? (L.isRussian ? "Приватно, офлайн" : "Private, offline")
                               : (L.isRussian ? "Пока недоступно" : "Not available yet"),
                           icon: "cpu",
                           enabled: LocalModelManager.isAvailable)
                modeButton(id: "hybrid",
                           title: "Hybrid",
                           subtitle: L.isRussian ? "Лучший баланс" : "Best balance",
                           icon: "arrow.triangle.merge")
                modeButton(id: "cloudOnly",
                           title: "Cloud",
                           subtitle: L.isRussian ? "Макс. качество" : "Max quality",
                           icon: "cloud")
            }
        }
        .aiCard(tint: AITheme.lavender.opacity(0.12))
    }

    private func modeButton(id: String, title: String, subtitle: String, icon: String, enabled: Bool = true) -> some View {
        Button {
            guard enabled else { return }
            completionMode = id
            persistSettings()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(completionMode == id
                              ? AITheme.accent.opacity(0.15)
                              : AITheme.accentMist.opacity(0.5))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(completionMode == id
                                         ? AITheme.accentDeep
                                         : AITheme.textSecondary)
                }
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(AITheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(AITheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                    .fill(completionMode == id
                          ? AITheme.accentMist
                          : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                            .stroke(completionMode == id
                                    ? AITheme.accent
                                    : AITheme.separator, lineWidth: completionMode == id ? 2 : 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.55)
        .disabled(!enabled)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Auto-Launch
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var autoLaunchCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sunrise")
                .font(.title2)
                .foregroundStyle(AITheme.accent)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(AITheme.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(L.isRussian ? "Автозапуск" : "Launch at Login")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text(L.isRussian
                     ? "Запускать при входе в macOS"
                     : "Start automatically when you log in")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(AITheme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $loginItemEnabled)
                .toggleStyle(.switch)
                .tint(AITheme.accent)
                .onChange(of: loginItemEnabled) { updateLoginItem() }
        }
        .aiCard(tint: AITheme.cream.opacity(0.2))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Logic
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadSettings() {
        APIKeyStore.migrateFromUserDefaultsIfNeeded(defaults)
        cloudProvider = SettingsViewModel.CloudProviderOption(
            rawValue: defaults.string(forKey: Constants.UserDefaultsKeys.cloudProvider) ?? "openAI"
        ) ?? .openAI
        apiKey = APIKeyStore.read() ?? ""
        cloudModelIdentifier = defaults.string(forKey: Constants.UserDefaultsKeys.cloudModelIdentifier)
            ?? cloudModels.first?.id ?? ""
        completionMode = defaults.string(forKey: Constants.UserDefaultsKeys.completionMode) ?? "hybrid"
        if !LocalModelManager.isAvailable, completionMode == "localOnly" {
            completionMode = "hybrid"
        }

        if #available(macOS 13.0, *) {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func persistSettings() {
        defaults.set(cloudProvider.rawValue, forKey: Constants.UserDefaultsKeys.cloudProvider)
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = APIKeyStore.delete()
        } else {
            _ = APIKeyStore.save(apiKey)
        }
        defaults.set(cloudModelIdentifier, forKey: Constants.UserDefaultsKeys.cloudModelIdentifier)
        defaults.set(completionMode, forKey: Constants.UserDefaultsKeys.completionMode)
    }

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if loginItemEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch { }
        }
    }
}
