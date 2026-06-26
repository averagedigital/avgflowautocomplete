import AppKit
import CoreText
import SwiftUI

@main
struct AICompleteMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppFontRegistrar.registerBundledFontsIfNeeded()
    }

    var body: some Scene {
        Window("AIComplete Settings", id: "settings") {
            MacSettingsContentView()
                .frame(minWidth: 720, minHeight: 520)
                .environmentObject(appDelegate.permissionsManager)
        }
        .defaultSize(width: 860, height: 680)
        .windowStyle(.hiddenTitleBar)
        .commands {
            AICompleteCommands()
        }
    }
}

private enum AppFontRegistrar {
    private static var didRegister = false

    static func registerBundledFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        registerFont(named: "Inter-Variable", extension: "ttf")
        registerFont(named: "JetBrainsMono-Variable", extension: "ttf")
    }

    private static func registerFont(named name: String, extension ext: String) {
        guard let fontURL = Bundle.main.url(forResource: name, withExtension: ext) else {
            return
        }
        var registrationError: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError)
    }
}

// MARK: - Keyboard Commands

struct AICompleteCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Divider()
            Button(L.isRussian ? "Обновить данные" : "Refresh Data") {
                NotificationCenter.default.post(name: .aiCompleteRefreshRequested, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

extension Notification.Name {
    static let aiCompleteRefreshRequested = Notification.Name("aiCompleteRefreshRequested")
    static let aiCompleteOpenSection = Notification.Name("aiCompleteOpenSection")
    static let aiCompleteSettingsChanged = Notification.Name("aiCompleteSettingsChanged")
}

// MARK: - Sidebar Navigation

enum SidebarItem: String, CaseIterable, Identifiable {
    case editor  = "editor"
    case engine  = "engine"
    case prompts = "prompts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .editor:  return "square.and.pencil"
        case .engine:  return "bolt.badge.a"
        case .prompts: return "text.bubble"
        }
    }

    var label: String {
        switch self {
        case .editor:  return L.isRussian ? "Редактор" : "Editor"
        case .engine:  return L.isRussian ? "Движок" : "Engine"
        case .prompts: return L.isRussian ? "Промпты" : "Prompts"
        }
    }

    var compactLabel: String {
        switch self {
        case .editor:  return L.isRussian ? "Ред."     : "Edit"
        case .engine:  return L.isRussian ? "Движок"   : "Engine"
        case .prompts: return L.isRussian ? "Промпт"   : "Prompts"
        }
    }
}

struct MacSettingsContentView: View {
    @EnvironmentObject private var permissionsManager: PermissionsManager

    @AppStorage(Constants.UserDefaultsKeys.guideCompleted,
                store: AppGroupManager.shared.sharedUserDefaults() ?? .standard)
    private var guideCompleted = false

    @State private var selection: SidebarItem? = .editor
    @State private var globalSearch = ""
    @State private var advancedSection: AdvancedSection? = nil
    @State private var showAdvancedPopover = false
    @State private var toolbarRefreshTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
    private let topChromeInset: CGFloat = 34

    // Status bar info
    private var currentMode: String {
        let raw = defaults.string(forKey: Constants.UserDefaultsKeys.completionMode) ?? "hybrid"
        switch raw {
        case "localOnly": return "Local"
        case "cloudOnly": return "Cloud"
        default: return "Hybrid"
        }
    }

    private var currentProvider: String {
        let raw = defaults.string(forKey: Constants.UserDefaultsKeys.cloudProvider) ?? "openAI"
        switch raw {
        case "anthropic": return "Anthropic"
        case "xAI": return "xAI"
        case "openRouter": return "OpenRouter"
        default: return "OpenAI"
        }
    }

    private var currentModel: String {
        let raw = defaults.string(forKey: Constants.UserDefaultsKeys.cloudModelIdentifier) ?? ""
        return raw
            .replacingOccurrences(of: "google/", with: "")
            .replacingOccurrences(of: "openai/", with: "")
            .replacingOccurrences(of: "anthropic/", with: "")
    }

    private var currentModelLabel: String {
        let rawLabel = currentModel.isEmpty ? currentProvider : currentModel
        return rawLabel.replacingOccurrences(of: "_", with: "-")
    }

    private var hasAPIKey: Bool {
        let key = APIKeyStore.read() ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentModeRaw: String {
        defaults.string(forKey: Constants.UserDefaultsKeys.completionMode) ?? "hybrid"
    }

    private var currentProviderOption: SettingsViewModel.CloudProviderOption {
        SettingsViewModel.CloudProviderOption(
            rawValue: defaults.string(forKey: Constants.UserDefaultsKeys.cloudProvider) ?? "openAI"
        ) ?? .openAI
    }

    private var searchItems: [GlobalSearchItem] {
        [
            .init(title: L.isRussian ? "Редактор" : "Editor", subtitle: L.isRussian ? "Тест автодополнения" : "Autocomplete sandbox", sidebarItem: .editor),
            .init(title: L.isRussian ? "Движок" : "Engine", subtitle: L.isRussian ? "Режим, провайдер, модель" : "Mode, provider, model", sidebarItem: .engine),
            .init(title: L.isRussian ? "Промпты" : "Prompts", subtitle: L.isRussian ? "Системный промпт, продолжение" : "System prompt, continuation", sidebarItem: .prompts),
            .init(title: L.isRussian ? "Общие" : "General", subtitle: L.isRussian ? "Язык, запуск, доступы" : "Language, launch, access", advancedSection: .general),
            .init(title: L.isRussian ? "Приложения" : "Apps", subtitle: L.isRussian ? "Per-app правила и инструкции" : "Per-app rules and instructions", advancedSection: .apps),
            .init(title: L.isRussian ? "Модели" : "Models", subtitle: L.isRussian ? "GGUF каталог" : "GGUF catalog", advancedSection: .models),
            .init(title: L.isRussian ? "Память" : "Memory", subtitle: L.isRussian ? "Словарь, профиль" : "Dictionary, profile", advancedSection: .memory),
            .init(title: L.isRussian ? "Аналитика" : "Analytics", subtitle: L.isRussian ? "Метрики, анализ" : "Metrics, analysis", advancedSection: .analytics),
            .init(title: "TinyStyleLM", subtitle: L.isRussian ? "Обучение стилю" : "Style training", advancedSection: .tinyStyle),
            .init(title: L.isRussian ? "Настройка" : "Setup", subtitle: L.isRussian ? "Гайд запуска" : "Setup guide", advancedSection: .setup)
        ]
    }

    private var filteredSearchItems: [GlobalSearchItem] {
        let query = globalSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return searchItems.filter { item in
            item.title.lowercased().contains(query) || item.subtitle.lowercased().contains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // ── Icon Sidebar ───────────────────────────────────
            sidebarColumn
                .background(AITheme.bgBase)
                .zIndex(2)

            // Thin chrome divider
            Rectangle()
                .fill(AITheme.borderSubtle)
                .frame(width: 1)
                .padding(.top, topChromeInset)

            // ── Detail Area ──────────────────────────────────
            VStack(spacing: 0) {
                headerBar
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(
                ZStack {
                    GlassBackground(material: .hudWindow, blendingMode: .behindWindow)
                    ChromeTextureBackground()
                    AITheme.windowBg.opacity(0.78)
                }
                .allowsHitTesting(false)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)
        }
        .background(AITheme.windowBg)
        .ignoresSafeArea(.container, edges: [.top, .leading, .trailing, .bottom])
        .preferredColorScheme(.dark)
        .onAppear {
            if !guideCompleted {
                advancedSection = .setup
                selection = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let window = NSApp.windows.first(where: {
                    ($0.title.contains("AIComplete") || $0.identifier?.rawValue.contains("settings") == true)
                    && !($0 is SuggestionPanel)
                }) {
                    AppDelegate.applyVibrancy(to: window)
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .aiCompleteSettingsChanged)
                .receive(on: RunLoop.main)
        ) { _ in
            toolbarRefreshTick += 1
        }
    }

    // MARK: - Icon Sidebar

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            // Reserve space for traffic lights/titlebar zone.
            Spacer().frame(height: topChromeInset)

            // Navigation items
            VStack(spacing: 8) {
                ForEach(SidebarItem.allCases) { item in
                    sidebarButton(item)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // App logo at the bottom — opens advanced settings
            Button {
                advancedSection = nil
                showAdvancedPopover.toggle()
            } label: {
                VStack(spacing: 4) {
                    SiteAutocompleteLogoMark()
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    AvgFlowWordmark(
                        font: Font.custom("JetBrains Mono", size: 11).weight(.semibold),
                        caretHeight: 10,
                        usesPrimaryPrefixColor: false
                    )
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAdvancedPopover, arrowEdge: .trailing) {
                AdvancedSettingsPopover { section in
                    showAdvancedPopover = false
                    selection = nil
                    advancedSection = section
                }
            }
            .padding(.bottom, 16)
        }
        .frame(minWidth: 92, idealWidth: 92, maxWidth: 92, maxHeight: .infinity)
        .layoutPriority(3)
        .contentShape(Rectangle())
    }

    private func sidebarButton(_ item: SidebarItem) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = item
                advancedSection = nil
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: selection == item ? .semibold : .regular))
                    .foregroundStyle(selection == item ? AITheme.chromeWhite : AITheme.textSecondary)
                    .frame(width: 20, height: 20)
                Text(item.compactLabel)
                    .font(.system(size: 11, weight: selection == item ? .semibold : .medium))
                    .foregroundStyle(selection == item ? AITheme.textPrimary : AITheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .frame(width: 56)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 72, alignment: .center)
            .frame(minHeight: 64)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        selection == item
                            ? AITheme.accentMint.opacity(0.14)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selection == item
                            ? AITheme.borderHover
                            : AITheme.borderSubtle.opacity(0.18),
                        lineWidth: selection == item ? 0.9 : 0.45
                    )
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection == item)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let advanced = advancedSection {
            advancedDetailContent(advanced)
        } else {
            switch selection {
            case .editor, .none:
                EditorView()
            case .engine:
                EngineSettingsView()
            case .prompts:
                PromptsView()
            }
        }
    }

    @ViewBuilder
    private func advancedDetailContent(_ section: AdvancedSection) -> some View {
        switch section {
        case .general:
            SettingsView()
                .environmentObject(permissionsManager)
        case .apps:
            AppOverridesSettingsView()
        case .models:
            ModelManagementView()
        case .memory:
            MemorySettingsView()
        case .analytics:
            AnalyticsView()
        case .tinyStyle:
            TinyStyleSettingsView()
        case .setup:
            OnboardingView(guideCompleted: $guideCompleted)
        }
    }

    // MARK: - Top Controls

    private var headerBar: some View {
        HStack(alignment: .top, spacing: AITheme.spacingM) {
            SiteAutocompleteBrandView()
                .padding(.top, 2)
            Spacer(minLength: AITheme.spacingS)
            searchControl
            statusToolbar
        }
        .padding(.top, topChromeInset)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.18), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .zIndex(2)
    }

    private var searchControl: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(AITheme.textSecondary)
                TextField(
                    L.isRussian ? "Поиск по настройкам и разделам" : "Search settings and sections",
                    text: $globalSearch
                )
                .textFieldStyle(.plain)
                .font(AITheme.fontCaption)
                .frame(width: 220)
                .onSubmit {
                    if let first = filteredSearchItems.first {
                        openSearchItem(first)
                    }
                }
                if !globalSearch.isEmpty {
                    Button {
                        globalSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AITheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )

            if !filteredSearchItems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredSearchItems.prefix(6)) { item in
                        Button {
                            openSearchItem(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(AITheme.fontCaptionBold)
                                    .foregroundStyle(AITheme.textPrimary)
                                Text(item.subtitle)
                                    .font(AITheme.fontCaption2)
                                    .foregroundStyle(AITheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 300)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AITheme.chromeSilver.opacity(0.18), lineWidth: 1)
                )
            }
        }
    }

    private var statusToolbar: some View {
        HStack(spacing: AITheme.spacingS) {
            Menu {
                Button("Local Only") { setCompletionMode("localOnly") }
                Button("Hybrid") { setCompletionMode("hybrid") }
                Button("Cloud Only") { setCompletionMode("cloudOnly") }
            } label: {
                HStack(spacing: AITheme.spacingXS) {
                    Circle()
                        .fill(currentMode == "Local" ? .green : (currentMode == "Cloud" ? .blue : .purple))
                        .frame(width: 6, height: 6)
                    Text(currentMode)
                        .font(AITheme.fontCaption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .menuStyle(.borderlessButton)
            .pointingHandCursor()

            Menu {
                Section(L.isRussian ? "Провайдер" : "Provider") {
                    ForEach(SettingsViewModel.CloudProviderOption.allCases) { provider in
                        Button(provider.title) {
                            setCloudProvider(provider)
                        }
                    }
                }
                Section(L.isRussian ? "Модель" : "Model") {
                    ForEach(SettingsViewModel.cloudModels(for: currentProviderOption), id: \.id) { model in
                        Button(model.title) {
                            setCloudModel(model.id)
                        }
                    }
                }
            } label: {
                HStack(spacing: AITheme.spacingXS) {
                    Image(systemName: "cloud")
                        .font(.caption2)
                    Text(currentModelLabel)
                        .font(AITheme.fontCaption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 120, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .menuStyle(.borderlessButton)
            .pointingHandCursor()

            // API key status
            if !hasAPIKey && currentMode != "Local" {
                HStack(spacing: AITheme.spacingXS) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(L.isRussian ? "Нет API ключа" : "No API key")
                        .font(AITheme.fontCaption2)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange.opacity(0.1)))
            }
        }
    }

    private func setCompletionMode(_ rawValue: String) {
        defaults.set(rawValue, forKey: Constants.UserDefaultsKeys.completionMode)
        toolbarRefreshTick += 1
    }

    private func setCloudProvider(_ provider: SettingsViewModel.CloudProviderOption) {
        defaults.set(provider.rawValue, forKey: Constants.UserDefaultsKeys.cloudProvider)
        let modelOptions = SettingsViewModel.cloudModels(for: provider)
        let currentModel = defaults.string(forKey: Constants.UserDefaultsKeys.cloudModelIdentifier) ?? ""
        if !modelOptions.contains(where: { $0.id == currentModel }) {
            defaults.set(modelOptions.first?.id ?? "", forKey: Constants.UserDefaultsKeys.cloudModelIdentifier)
        }
        toolbarRefreshTick += 1
    }

    private func setCloudModel(_ modelID: String) {
        defaults.set(modelID, forKey: Constants.UserDefaultsKeys.cloudModelIdentifier)
        toolbarRefreshTick += 1
    }

    private func openSearchItem(_ item: GlobalSearchItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let sidebarItem = item.sidebarItem {
                advancedSection = nil
                selection = sidebarItem
            } else if let advanced = item.advancedSection {
                selection = nil
                advancedSection = advanced
            }
        }
        globalSearch = ""
    }

    // MARK: - Welcome View (chrome-styled)

    private var welcomeView: some View {
        VStack(spacing: AITheme.spacingL) {
            Spacer()

            // Chameleon Mascot Logo
            SiteAutocompleteLogoMark()
                .frame(width: 132, height: 132)
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                .padding(.vertical, 20)

            AvgFlowWordmark(
                font: Font.custom("JetBrains Mono", size: 30).weight(.bold),
                caretHeight: 24
            )

            Text(L.isRussian
                 ? "Умный помощник автодополнения для macOS"
                 : "Smart autocomplete assistant for macOS")
                .font(AITheme.fontBody)
                .foregroundStyle(AITheme.textSecondary)

            // Quick start cards
            HStack(spacing: AITheme.spacingM) {
                quickStartCard(
                    icon: "bolt.badge.a",
                    title: L.isRussian ? "Движок" : "Engine",
                    desc: L.isRussian ? "Настройте провайдера" : "Configure your provider",
                    action: { selection = .engine; advancedSection = nil }
                )
                quickStartCard(
                    icon: "text.bubble",
                    title: L.isRussian ? "Промпты" : "Prompts",
                    desc: L.isRussian ? "Настройте промпты" : "Customize prompts",
                    action: { selection = .prompts; advancedSection = nil }
                )
                quickStartCard(
                    icon: "square.and.pencil",
                    title: L.isRussian ? "Тестировать" : "Try It",
                    desc: L.isRussian ? "Откройте редактор" : "Open the test editor",
                    action: { selection = .editor; advancedSection = nil }
                )
            }
            .padding(.top, AITheme.spacingS)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickStartCard(icon: String, title: String, desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AITheme.spacingS) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(AITheme.chromeSilver)
                Text(title)
                    .font(AITheme.fontHeading)
                    .foregroundStyle(AITheme.textPrimary)
                Text(desc)
                    .font(AITheme.fontCaption2)
                    .foregroundStyle(AITheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 140, height: 110)
            .aiCard()
        }
        .buttonStyle(.plain)
    }
}

private struct GlobalSearchItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    var sidebarItem: SidebarItem? = nil
    var advancedSection: AdvancedSection? = nil
}

private struct SiteAutocompleteBrandView: View {
    var body: some View {
        HStack(spacing: 8) {
            SiteAutocompleteLogoMark()
                .frame(width: 24, height: 24)
            AvgFlowWordmark(font: Font.custom("JetBrains Mono", size: 13).weight(.semibold), caretHeight: 13)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AITheme.borderSubtle, lineWidth: 0.7)
        )
    }
}

private struct SiteAutocompleteLogoMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AITheme.bgSurface.opacity(0.98),
                            AITheme.accentMint.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            GeometryReader { proxy in
                let rect = proxy.frame(in: .local)

                ZStack {
                    SiteWaveLineShape(amplitude: rect.height * 0.20, phase: phase, verticalOffset: rect.height * 0.50)
                        .stroke(AITheme.accentMint, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    SiteWaveLineShape(amplitude: rect.height * 0.14, phase: phase * 0.72 + .pi * 0.35, verticalOffset: rect.height * 0.50)
                        .stroke(AITheme.textSecondary.opacity(0.72), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

private struct SiteWaveLineShape: Shape {
    let amplitude: CGFloat
    let phase: CGFloat
    let verticalOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startX = -rect.width
        let endX = rect.width * 2
        let step: CGFloat = 2
        let frequency = (CGFloat.pi * 2) / (rect.width * 0.9)

        path.move(to: CGPoint(x: startX, y: verticalOffset))
        var x = startX
        while x <= endX {
            let y = verticalOffset + (amplitude * sin((x * frequency) + phase))
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        return path
    }
}

private struct AvgFlowWordmark: View {
    let font: Font
    let caretHeight: CGFloat
    var usesPrimaryPrefixColor = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var caretVisible = true

    var body: some View {
        HStack(spacing: 1) {
            Text("avg")
                .font(font)
                .foregroundStyle(usesPrimaryPrefixColor ? AITheme.textPrimary : AITheme.textSecondary)
            Text("Flow")
                .font(font)
                .foregroundStyle(AITheme.accentMint)
            Rectangle()
                .fill(AITheme.accentMint)
                .frame(width: 1.6, height: caretHeight)
                .opacity(caretVisible ? 1 : 0.25)
                .padding(.leading, 2)
        }
        .lineLimit(1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                caretVisible.toggle()
            }
        }
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

private struct ChromeTextureBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AITheme.bgBase,
                    AITheme.bgSurface,
                    AITheme.bgBase
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AITheme.accentMint.opacity(0.07), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 540
            )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [AITheme.accentMint.opacity(0.11), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 330
                    )
                )
                .frame(width: 820, height: 560)
                .blur(radius: 38)
                .offset(x: -240, y: -190)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            AITheme.liquidChromeBase.opacity(0.16),
                            AITheme.chromeBlue.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 620, height: 340)
                .blur(radius: 26)
                .offset(x: 170, y: 40)

            Ellipse()
                .fill(AITheme.liquidChromeBase.opacity(0.08))
                .frame(width: 460, height: 260)
                .blur(radius: 36)
                .offset(x: -200, y: 240)

            LiquidNoiseLayer()
                .opacity(0.34)
                .blendMode(.overlay)

            FogGradientLayer()
                .opacity(0.36)
                .blendMode(.softLight)
        }
        .compositingGroup()
    }
}

private struct LiquidNoiseLayer: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5
            var path = Path()

            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    if noiseValue(x: Int(x), y: Int(y)) > 0.84 {
                        path.addRect(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                    x += step
                }
                y += step
            }

            context.fill(path, with: .color(Color.white.opacity(0.08)))
        }
        .allowsHitTesting(false)
    }

    private func noiseValue(x: Int, y: Int) -> Double {
        var n = Int64(x &* 374_761_393) &+ Int64(y &* 668_265_263)
        n = (n ^ (n >> 13)) &* 1_274_126_177
        n = n ^ (n >> 16)
        return Double(n & 1023) / 1023.0
    }
}

private struct FogGradientLayer: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AITheme.accentMint.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(width, height) * 0.42
                        )
                    )
                    .frame(width: width * 0.85, height: height * 0.85)
                    .offset(x: width * 0.24, y: -height * 0.18)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AITheme.chromeBlue.opacity(0.11), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(width, height) * 0.46
                        )
                    )
                    .frame(width: width * 0.72, height: height * 0.72)
                    .offset(x: -width * 0.34, y: height * 0.18)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ChromiumCodeLogoView: View {
    var showsBackground = false

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / 260
            let offsetX = (geometry.size.width - side) * 0.5
            let offsetY = (geometry.size.height - side) * 0.5

            ZStack {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.12, green: 0.12, blue: 0.12))
                }

                svgPath(scale: scale, offsetX: offsetX, offsetY: offsetY) { path in
                    path.move(to: point(50, 50, scale, offsetX, offsetY))
                    path.addLine(to: point(30, 50, scale, offsetX, offsetY))
                    path.addLine(to: point(30, 210, scale, offsetX, offsetY))
                    path.addLine(to: point(50, 210, scale, offsetX, offsetY))
                }
                .stroke(
                    Color(red: 0.34, green: 0.61, blue: 0.84),
                    style: StrokeStyle(lineWidth: 10 * scale, lineCap: .round, lineJoin: .round)
                )

                svgPath(scale: scale, offsetX: offsetX, offsetY: offsetY) { path in
                    path.move(to: point(210, 50, scale, offsetX, offsetY))
                    path.addLine(to: point(230, 50, scale, offsetX, offsetY))
                    path.addLine(to: point(230, 210, scale, offsetX, offsetY))
                    path.addLine(to: point(210, 210, scale, offsetX, offsetY))
                }
                .stroke(
                    Color(red: 0.34, green: 0.61, blue: 0.84),
                    style: StrokeStyle(lineWidth: 10 * scale, lineCap: .round, lineJoin: .round)
                )

                svgPath(scale: scale, offsetX: offsetX, offsetY: offsetY) { path in
                    path.move(to: point(135, 50, scale, offsetX, offsetY))
                    path.addLine(to: point(185, 90, scale, offsetX, offsetY))
                    path.addLine(to: point(135, 90, scale, offsetX, offsetY))
                    path.closeSubpath()
                }
                .stroke(
                    Color(red: 0.86, green: 0.86, blue: 0.67),
                    style: StrokeStyle(lineWidth: 10 * scale, lineCap: .round, lineJoin: .round)
                )

                svgPath(scale: scale, offsetX: offsetX, offsetY: offsetY) { path in
                    path.move(to: point(135, 50, scale, offsetX, offsetY))
                    path.addCurve(
                        to: point(75, 160, scale, offsetX, offsetY),
                        control1: point(95, 50, scale, offsetX, offsetY),
                        control2: point(75, 100, scale, offsetX, offsetY)
                    )
                    path.addCurve(
                        to: point(165, 160, scale, offsetX, offsetY),
                        control1: point(75, 210, scale, offsetX, offsetY),
                        control2: point(165, 210, scale, offsetX, offsetY)
                    )
                }
                .stroke(
                    Color(red: 0.31, green: 0.79, blue: 0.69),
                    style: StrokeStyle(lineWidth: 10 * scale, lineCap: .round, lineJoin: .round)
                )

                svgPath(scale: scale, offsetX: offsetX, offsetY: offsetY) { path in
                    path.move(to: point(165, 160, scale, offsetX, offsetY))
                    path.addCurve(
                        to: point(115, 160, scale, offsetX, offsetY),
                        control1: point(165, 120, scale, offsetX, offsetY),
                        control2: point(115, 120, scale, offsetX, offsetY)
                    )
                }
                .stroke(
                    Color(red: 0.81, green: 0.57, blue: 0.47),
                    style: StrokeStyle(lineWidth: 10 * scale, lineCap: .round, lineJoin: .round)
                )

                svgPath(scale: scale, offsetX: offsetX, offsetY: offsetY) { path in
                    path.move(to: point(115, 160, scale, offsetX, offsetY))
                    path.addCurve(
                        to: point(140, 160, scale, offsetX, offsetY),
                        control1: point(115, 180, scale, offsetX, offsetY),
                        control2: point(140, 180, scale, offsetX, offsetY)
                    )
                }
                .stroke(
                    Color(red: 0.77, green: 0.52, blue: 0.75),
                    style: StrokeStyle(lineWidth: 10 * scale, lineCap: .round, lineJoin: .round)
                )

                svgPath(scale: scale, offsetX: offsetX, offsetY: offsetY) { path in
                    path.move(to: point(135, 90, scale, offsetX, offsetY))
                    path.addLine(to: point(135, 115, scale, offsetX, offsetY))
                    path.addLine(to: point(150, 115, scale, offsetX, offsetY))
                }
                .stroke(
                    Color(red: 0.61, green: 0.86, blue: 0.99),
                    style: StrokeStyle(lineWidth: 10 * scale, lineCap: .round, lineJoin: .round)
                )

                svgPath(scale: scale, offsetX: offsetX, offsetY: offsetY) { path in
                    path.move(to: point(85, 110, scale, offsetX, offsetY))
                    path.addLine(to: point(85, 135, scale, offsetX, offsetY))
                    path.addLine(to: point(100, 135, scale, offsetX, offsetY))
                }
                .stroke(
                    Color(red: 0.61, green: 0.86, blue: 0.99),
                    style: StrokeStyle(lineWidth: 10 * scale, lineCap: .round, lineJoin: .round)
                )

                Circle()
                    .stroke(
                        Color(red: 0.61, green: 0.86, blue: 0.99),
                        lineWidth: 4 * scale
                    )
                    .frame(width: 8 * scale, height: 8 * scale)
                    .position(point(160, 75, scale, offsetX, offsetY))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func svgPath(
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        builder: (inout Path) -> Void
    ) -> Path {
        var path = Path()
        builder(&path)
        return path
    }

    private func point(
        _ x: CGFloat,
        _ y: CGFloat,
        _ scale: CGFloat,
        _ offsetX: CGFloat,
        _ offsetY: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: offsetX + x * scale,
            y: offsetY + y * scale
        )
    }
}
