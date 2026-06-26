import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var permissionsManager: PermissionsManager
    @State private var loginItemEnabled = false

    @AppStorage(Constants.UserDefaultsKeys.appLanguage,
                store: AppGroupManager.shared.sharedUserDefaults() ?? .standard)
    private var appLanguage = "auto"

    @AppStorage("overlayThemePreset",
                store: AppGroupManager.shared.sharedUserDefaults() ?? .standard)
    private var overlayThemePreset = "system"

    var body: some View {
        ScrollView {
            VStack(spacing: AITheme.spacingL) {
                generalSection
                overlayAppearanceSection
            }
            .padding(AITheme.spacingL)
            .padding(.bottom, AITheme.spacingL)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            L.setLanguage(appLanguage)
            loadLoginItemState()
            _ = permissionsManager.checkAccessibility()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            _ = permissionsManager.checkAccessibility()
        }
    }

    // MARK: - Sections

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

    @ViewBuilder
    private var generalSection: some View {
        premiumSection(title: L.settings_appLanguage) {
            Picker(L.settings_appLanguage, selection: $appLanguage) {
                Text("Auto").tag("auto")
                Text("Русский").tag("ru")
                Text("English").tag("en")
            }
            .onChange(of: appLanguage) {
                L.setLanguage(appLanguage)
            }
        }

        premiumSection(title: L.isRussian ? "Автозапуск" : "Auto-Launch") {
            Toggle(
                L.isRussian ? "Запускать при входе в систему" : "Launch at Login",
                isOn: $loginItemEnabled
            )
            .toggleStyle(.switch)
            .onChange(of: loginItemEnabled) {
                updateLoginItem(enabled: loginItemEnabled)
            }

            Text(L.isRussian
                 ? "AIComplete будет автоматически запускаться при входе в macOS."
                 : "AIComplete will automatically start when you log into macOS.")
                .font(AITheme.fontCaption)
                .foregroundStyle(AITheme.textSecondary)
        }

        premiumSection(title: L.isRussian ? "Accessibility" : "Accessibility") {
            HStack {
                Text(L.isRussian
                     ? "Доступ к Accessibility API"
                     : "Accessibility API Access")
                Spacer()
                if permissionsManager.isAccessibilityGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(L.isRussian ? "Разрешено" : "Granted")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(L.isRussian ? "Не разрешено" : "Not Granted")
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                Button(L.isRussian ? "Проверить снова" : "Refresh Status") {
                    if permissionsManager.checkAccessibility() {
                        NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
                    } else {
                        permissionsManager.startPolling(forceRestart: true)
                    }
                }
                Spacer()
            }

            if !permissionsManager.isAccessibilityGranted {
                Button(L.isRussian ? "Открыть Системные настройки" : "Open System Settings") {
                    permissionsManager.openAccessibilitySettings()
                }
                Button(L.isRussian ? "Показать системный запрос доступа" : "Show Permission Prompt") {
                    permissionsManager.requestAccessibility(force: true)
                    permissionsManager.startPolling(forceRestart: true)
                }

                Text(L.isRussian
                     ? "AIComplete необходим доступ к Accessibility для чтения текста из любого приложения и показа автодополнений."
                     : "AIComplete needs Accessibility access to read text from any application and show autocomplete suggestions.")
                    .font(AITheme.fontCaption)
                    .foregroundStyle(AITheme.textSecondary)

                    if permissionsManager.isLikelyRunningFromXcode {
                        Text(L.isRussian
                             ? "Сейчас приложение запущено из Xcode (DerivedData). Если галочка в настройках уже включена, но статус остается Not Granted: завершите приложение, сбросьте TCC для текущего bundle id, снова запустите из Xcode и выдайте доступ заново."
                             : "The app is running from Xcode (DerivedData). If the checkbox is enabled in System Settings but status is still Not Granted: quit the app, reset TCC for the current bundle id, relaunch from Xcode, and grant access again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        Text(permissionsManager.currentBundlePath)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                        Text(permissionsManager.currentBundleIdentifier)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                        Text(permissionsManager.accessibilityResetCommand)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                        if permissionsManager.isLikelyAdHocSigned {
                            Text(L.isRussian
                                 ? "Текущая подпись ad-hoc (TeamIdentifier не найден). Это частая причина, почему Accessibility не закрепляется между сборками. В Signing & Capabilities укажите Development Team."
                                 : "Current signature is ad-hoc (TeamIdentifier is missing). This commonly breaks persistent Accessibility trust across builds. Set a Development Team in Signing & Capabilities.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        } else if let teamID = permissionsManager.codeSigningTeamIdentifier {
                            Text("TeamIdentifier: \(teamID)")
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
    }

    // MARK: - Overlay Appearance

    @ViewBuilder
    private var overlayAppearanceSection: some View {
        premiumSection(title: L.isRussian ? "Оверлей подсказок" : "Suggestion Overlay") {
            Picker(L.isRussian ? "Тема оверлея" : "Overlay Theme", selection: $overlayThemePreset) {
                Text(L.isRussian ? "Авто (системная)" : "System (Auto)").tag("system")
                Text("Dark Chrome").tag("darkChrome")
                Text("Light").tag("light")
                Text("Liquid Glass").tag("liquidGlass")
            }
            .pickerStyle(.segmented)

            Text(L.isRussian
                 ? "Управляет внешним видом всплывающего оверлея с подсказками. «Авто» следует за темой macOS. Liquid Glass — полупрозрачный с эффектом матового стекла."
                 : "Controls the look of the autocomplete suggestion overlay. \"System\" follows macOS appearance. Liquid Glass shows a frosted translucent panel.")
                .font(AITheme.fontCaption)
                .foregroundStyle(AITheme.textSecondary)
        }
    }

    // MARK: - Login Item

    private func loadLoginItemState() {
        if #available(macOS 13.0, *) {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func updateLoginItem(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently handle — user can retry
            }
        }
    }
}

@MainActor
final class AppOverridesSettingsViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var records: [AppOverrideRecord] = []
    @Published var selectedBundleIdentifier: String?

    private let store: AppOverridesStore

    init(store: AppOverridesStore = .shared) {
        self.store = store
        reload()
    }

    var filteredRecords: [AppOverrideRecord] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return records }
        return records.filter { record in
            record.displayName.lowercased().contains(query)
                || record.bundleIdentifier.lowercased().contains(query)
        }
    }

    var selectedRecord: AppOverrideRecord? {
        guard let selectedBundleIdentifier else {
            return filteredRecords.first ?? records.first
        }
        return records.first(where: { $0.bundleIdentifier == selectedBundleIdentifier })
    }

    func reload() {
        store.seedFromRunningApplications()
        records = store.allRecords()
        if selectedBundleIdentifier == nil {
            selectedBundleIdentifier = records.first?.bundleIdentifier
        } else if records.contains(where: { $0.bundleIdentifier == selectedBundleIdentifier }) == false {
            selectedBundleIdentifier = records.first?.bundleIdentifier
        }
    }

    func select(_ record: AppOverrideRecord) {
        selectedBundleIdentifier = record.bundleIdentifier
    }

    func updateSelected(
        completionsMode: AppOverrideRecord.OverrideMode? = nil,
        disableTabMode: AppOverrideRecord.OverrideMode? = nil,
        customInstructions: String? = nil
    ) {
        guard var record = selectedRecord else { return }
        if let completionsMode {
            record.completionsMode = completionsMode
        }
        if let disableTabMode {
            record.disableTabMode = disableTabMode
        }
        if let customInstructions {
            record.customInstructions = customInstructions
        }
        store.save(record)
        reload()
        selectedBundleIdentifier = record.bundleIdentifier
    }

    func resetSelected() {
        guard let selectedBundleIdentifier else { return }
        store.resetOverride(for: selectedBundleIdentifier)
        reload()
        self.selectedBundleIdentifier = selectedBundleIdentifier
    }
}

struct AppOverridesSettingsView: View {
    @StateObject private var viewModel = AppOverridesSettingsViewModel()

    var body: some View {
        HStack(spacing: AITheme.spacingL) {
            appListColumn
            detailColumn
        }
        .padding(AITheme.spacingL)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.reload()
        }
    }

    private var appListColumn: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingM) {
            Text(L.isRussian ? "Приложения" : "Apps")
                .font(AITheme.fontTitleSection)
                .foregroundStyle(AITheme.accentGradient)

            TextField(L.isRussian ? "Поиск по приложениям" : "Search apps", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(spacing: AITheme.spacingS) {
                    ForEach(viewModel.filteredRecords) { record in
                        Button {
                            viewModel.select(record)
                        } label: {
                            HStack(spacing: AITheme.spacingS) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.displayName)
                                        .font(AITheme.fontCaptionBold)
                                        .foregroundStyle(AITheme.textPrimary)
                                        .lineLimit(1)
                                    Text(record.bundleIdentifier)
                                        .font(AITheme.fontCaption2)
                                        .foregroundStyle(AITheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if record.hasCustomizations {
                                    Text(L.isRussian ? "Кастом" : "Custom")
                                        .font(AITheme.fontCaption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(AITheme.accentMint.opacity(0.2)))
                                }
                            }
                            .padding(.horizontal, AITheme.spacingM)
                            .padding(.vertical, AITheme.spacingS)
                            .background(
                                RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                                    .fill(viewModel.selectedBundleIdentifier == record.bundleIdentifier
                                          ? AITheme.accentMint.opacity(0.14)
                                          : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                                    .stroke(viewModel.selectedBundleIdentifier == record.bundleIdentifier
                                            ? AITheme.borderHover
                                            : AITheme.borderSubtle, lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 320, alignment: .topLeading)
        .aiCard()
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let record = viewModel.selectedRecord {
            VStack(alignment: .leading, spacing: AITheme.spacingL) {
                VStack(alignment: .leading, spacing: AITheme.spacingS) {
                    Text(record.displayName)
                        .font(AITheme.fontHeading)
                        .foregroundStyle(AITheme.textPrimary)
                    Text(record.bundleIdentifier)
                        .font(AITheme.fontCaption)
                        .foregroundStyle(AITheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: AITheme.spacingM) {
                    LabeledContent(L.isRussian ? "Подсказки" : "Completions") {
                        Picker(
                            "",
                            selection: Binding(
                                get: { viewModel.selectedRecord?.completionsMode ?? .inherit },
                                set: { viewModel.updateSelected(completionsMode: $0) }
                            )
                        ) {
                            Text(L.isRussian ? "По умолчанию" : "Default").tag(AppOverrideRecord.OverrideMode.inherit)
                            Text(L.isRussian ? "Вкл" : "On").tag(AppOverrideRecord.OverrideMode.enabled)
                            Text(L.isRussian ? "Выкл" : "Off").tag(AppOverrideRecord.OverrideMode.disabled)
                        }
                        .frame(width: 180)
                    }

                    LabeledContent(L.isRussian ? "Отключить Tab для принятия" : "Disable Tab Accept") {
                        Picker(
                            "",
                            selection: Binding(
                                get: { viewModel.selectedRecord?.disableTabMode ?? .inherit },
                                set: { viewModel.updateSelected(disableTabMode: $0) }
                            )
                        ) {
                            Text(L.isRussian ? "По умолчанию" : "Default").tag(AppOverrideRecord.OverrideMode.inherit)
                            Text(L.isRussian ? "Вкл" : "On").tag(AppOverrideRecord.OverrideMode.enabled)
                            Text(L.isRussian ? "Выкл" : "Off").tag(AppOverrideRecord.OverrideMode.disabled)
                        }
                        .frame(width: 180)
                    }
                }

                VStack(alignment: .leading, spacing: AITheme.spacingS) {
                    Text(L.isRussian ? "Кастомные инструкции" : "Custom Instructions")
                        .font(AITheme.fontTitleSection)
                        .foregroundStyle(AITheme.accentGradient)

                    Text(L.isRussian
                         ? "Добавляются к глобальному prompt только для этого приложения."
                         : "These are appended to the global prompt only for this app.")
                        .font(AITheme.fontCaption)
                        .foregroundStyle(AITheme.textSecondary)

                    TextEditor(
                        text: Binding(
                            get: { viewModel.selectedRecord?.customInstructions ?? "" },
                            set: { viewModel.updateSelected(customInstructions: $0) }
                        )
                    )
                    .font(AITheme.fontMono)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                            .stroke(AITheme.borderSubtle, lineWidth: 0.8)
                    )
                }

                HStack {
                    Button(L.isRussian ? "Сбросить overrides" : "Reset Overrides") {
                        viewModel.resetSelected()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text(record.hasCustomizations
                         ? (L.isRussian ? "Для этого приложения есть кастомная политика." : "This app has a custom completion policy.")
                         : (L.isRussian ? "Для этого приложения используются глобальные настройки." : "This app uses the global settings."))
                        .font(AITheme.fontCaption)
                        .foregroundStyle(AITheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aiCard()
        } else {
            VStack(alignment: .leading, spacing: AITheme.spacingM) {
                Text(L.isRussian ? "Нет приложений" : "No Apps Yet")
                    .font(AITheme.fontHeading)
                    .foregroundStyle(AITheme.textPrimary)
                Text(L.isRussian
                     ? "Открой несколько приложений и вернись сюда — список заполнится автоматически."
                     : "Open a few apps and come back here. The list is populated automatically.")
                    .font(AITheme.fontCaption)
                    .foregroundStyle(AITheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aiCard()
        }
    }
}
