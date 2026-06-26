import SwiftUI
import CryptoKit

private struct ModelCatalogItem: Identifiable, Hashable {
    let id: String
    let displayName: String
    let shortDescription: String
    let estimatedSizeLabel: String
    let recommendedFor: String
    let fileName: String
    let downloadURL: URL
    let expectedSHA256: String?
    let qualityRating: Int      // 1-5
    let speedRating: Int        // 1-5
    let languageSupport: String // e.g. "EN, RU, Multi"
}

private struct LocalModelFile: Identifiable {
    let url: URL
    let sizeBytes: Int64

    var id: String { url.path }
}

private struct HuggingFaceModelInfo: Decodable {
    struct Sibling: Decodable {
        let rfilename: String
    }

    let siblings: [Sibling]?
}

private enum ModelDownloadError: LocalizedError {
    case invalidResponse
    case failedStatusCode(Int)
    case suspiciousFileSize(Int64)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Download response is invalid."
        case let .failedStatusCode(statusCode):
            return "Download failed with HTTP status \(statusCode)."
        case let .suspiciousFileSize(fileSize):
            return "Downloaded file is too small (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))."
        case let .checksumMismatch(expected, actual):
            return "Checksum mismatch. Expected \(expected), got \(actual)."
        }
    }
}

struct ModelManagementView: View {
    // MARK: - State

    @State private var downloadingModelID: String?
    @State private var downloadProgressByModelID: [String: Double] = [:]
    @State private var downloadTask: Task<Void, Never>?
    @State private var localModels: [LocalModelFile] = []
    @State private var selectedModelIdentifier: String?
    @State private var localModelEnabled = true
    @State private var errorMessage: String?

    // Cloud provider state
    @State private var cloudProvider: SettingsViewModel.CloudProviderOption = .openAI
    @State private var cloudModelIdentifier: String = "gpt-4.1-nano"
    @State private var apiKey: String = ""
    @State private var privacyModeEnabled = false

    // Catalog State
    @State private var searchText = ""
    @State private var testingModelID: String?
    @State private var testPromptInput = ""
    @State private var testPromptResponse = ""
    @State private var isTestRunning = false
    @State private var hfRepoInput = "bartowski/Qwen2.5-1.5B-Instruct-GGUF"
    @State private var hfGGUFFiles: [String] = []
    @State private var selectedHFGGUFFile = ""
    @State private var isFetchingHFFiles = false

    // MARK: - Dependencies

    private let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard

    // MARK: - Catalog

    private let recommendedModels: [ModelCatalogItem] = [
        .init(
            id: "gemma3-1b-q4km",
            displayName: "Gemma 3 1B IT (Q4_K_M)",
            shortDescription: "Default local model aligned with Cotypist-style compact multilingual behavior.",
            estimatedSizeLabel: "~788 MB",
            recommendedFor: "Default Local Model",
            fileName: "gemma-3-1b-it-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf")!,
            expectedSHA256: "2a7fd9f36b0df87050002b2545be31cb19dfc315f160492b70bec970564a0263",
            qualityRating: 3,
            speedRating: 4,
            languageSupport: "EN, RU, Multi"
        ),
        .init(
            id: "smollm2-360m-q4km",
            displayName: "SmolLM2 360M (Q4_K_M)",
            shortDescription: "Fastest option for autocomplete.",
            estimatedSizeLabel: "~246 MB",
            recommendedFor: "Fast Autocomplete",
            fileName: "SmolLM2-360M-Instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf")!,
            expectedSHA256: "4788feabb1627cd4245b2bb0014c01f672a1c54b4d674d8fa3267ce0fd663acb",
            qualityRating: 2,
            speedRating: 5,
            languageSupport: "EN"
        ),
        .init(
            id: "qwen25-15b-q4km",
            displayName: "Qwen2.5 1.5B (Q4_K_M)",
            shortDescription: "Best quality/speed balance for text editing.",
            estimatedSizeLabel: "~1.12 GB",
            recommendedFor: "Primary Model",
            fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            expectedSHA256: "6ca5463cf24c16cd56d7ad7461524d813b07b3f29889b2fbdbb8286a7e97a14a",
            qualityRating: 4,
            speedRating: 3,
            languageSupport: "EN, RU, Multi"
        ),
        .init(
            id: "llama32-1b-q4km",
            displayName: "Llama 3.2 1B (Q4_K_M)",
            shortDescription: "Balanced tiny model for fast local completion.",
            estimatedSizeLabel: "~810 MB",
            recommendedFor: "General Local Use",
            fileName: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!,
            expectedSHA256: nil,
            qualityRating: 3,
            speedRating: 4,
            languageSupport: "EN, Multi"
        ),
        .init(
            id: "qwen25-3b-q4km",
            displayName: "Qwen2.5 3B (Q4_K_M)",
            shortDescription: "Higher-quality local option, still practical on laptops.",
            estimatedSizeLabel: "~1.9 GB",
            recommendedFor: "Quality First",
            fileName: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf")!,
            expectedSHA256: nil,
            qualityRating: 4,
            speedRating: 2,
            languageSupport: "EN, RU, Multi"
        ),
        .init(
            id: "phi35-mini-q4km",
            displayName: "Phi-3.5 Mini (Q4_K_M)",
            shortDescription: "Strong coding/text model in compact footprint.",
            estimatedSizeLabel: "~2.2 GB",
            recommendedFor: "Code + Text",
            fileName: "Phi-3.5-mini-instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf")!,
            expectedSHA256: nil,
            qualityRating: 4,
            speedRating: 2,
            languageSupport: "EN, Multi"
        )
    ]

    // MARK: - View

    private var cloudModels: [SettingsViewModel.CloudModelOption] {
        SettingsViewModel.cloudModels(for: cloudProvider)
    }

    private var filteredModels: [ModelCatalogItem] {
        if searchText.isEmpty { return recommendedModels }
        return recommendedModels.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.shortDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ── Inline Search Bar ───────────────────────────
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AITheme.textSecondary)
                    TextField(L.isRussian ? "Поиск моделей..." : "Search catalog...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(AITheme.fontBody)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AITheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous)
                        .stroke(AITheme.chromeSilver.opacity(0.2), lineWidth: 1)
                )
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Cloud Provider").font(AITheme.fontHeading)
                    VStack(spacing: 12) {
                        Picker("Provider", selection: $cloudProvider) {
                        ForEach(SettingsViewModel.CloudProviderOption.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: cloudProvider) {
                        if !cloudModels.contains(where: { $0.id == cloudModelIdentifier }) {
                            cloudModelIdentifier = cloudModels.first?.id ?? ""
                        }
                        persistCloud()
                    }

                    Picker("Model", selection: $cloudModelIdentifier) {
                        ForEach(cloudModels) { model in
                            Text(model.title).tag(model.id)
                        }
                    }
                    .onChange(of: cloudModelIdentifier) {
                        persistCloud()
                    }

                    HStack(spacing: 10) {
                        Text("API Key")
                            .font(AITheme.fontCaption)
                            .foregroundStyle(AITheme.textSecondary)
                            .frame(width: 56, alignment: .leading)
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(AITheme.fontMono)
                            .autocorrectionDisabled()
                            .frame(width: 280, alignment: .leading)
                            .onChange(of: apiKey) {
                                persistCloud()
                            }
                    }

                    if apiKey.isEmpty {
                        Text("Enter your API key to enable cloud completions.")
                            .font(AITheme.fontCaption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if cloudProvider == .openAI && !apiKey.lowercased().hasPrefix("sk-") {
                        Text("OpenAI key usually starts with sk-. If requests fail with 401, verify the key/provider pair.")
                            .font(AITheme.fontCaption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Toggle("Privacy Mode", isOn: $privacyModeEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: privacyModeEnabled) {
                            persistCloud()
                        }

                    Text(privacyModeEnabled
                         ? "Only local models will be used. No data sent to cloud."
                         : "Text context is sent to the cloud provider for completions.")
                        .font(AITheme.fontCaption)
                        .foregroundStyle(AITheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 8)
            .aiCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("Local Runtime").font(AITheme.fontHeading)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Local Model", isOn: $localModelEnabled)
                        .toggleStyle(.switch)
                        .disabled(!LocalModelManager.isAvailable)
                        .onChange(of: localModelEnabled) {
                            defaults.set(localModelEnabled, forKey: Constants.UserDefaultsKeys.localModelEnabled)
                        }

                    Text(localModelEnabled
                         ? "Local inference is enabled."
                         : "Local model stays on disk but is not loaded into memory.")
                        .font(AITheme.fontCaption)
                        .foregroundStyle(AITheme.textSecondary)

                    if !LocalModelManager.isAvailable {
                        Text("Local runtime is unavailable. Build the bundled llama.cpp runtime to enable in-process GGUF inference.")
                            .font(AITheme.fontCaption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .aiCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("Model Catalog")
                    .font(AITheme.fontTitleSection)
                    .foregroundStyle(AITheme.accentGradient)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    ForEach(filteredModels) { model in
                        ModelCardView(
                            model: model,
                            isDownloading: downloadingModelID == model.id,
                            downloadProgress: downloadProgressByModelID[model.id] ?? 0,
                            isInstalled: isModelInstalled(model),
                            isSelected: isModelSelected(model),
                            isTesting: testingModelID == model.id,
                            testPromptResponse: testPromptResponse,
                            isTestRunning: isTestRunning,
                            testPromptInput: $testPromptInput,
                            onDownload: { downloadTask = Task { await downloadModel(model) } },
                            onCancelDownload: { cancelDownload() },
                            onSelect: { selectModel(model) },
                            onToggleTest: {
                                if testingModelID == model.id { testingModelID = nil }
                                else { testingModelID = model.id; testPromptResponse = "" }
                            },
                            onRunTest: { runTestPrompt() }
                        )
                    }
                }
            }
            .aiCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("Hugging Face (Any GGUF)")
                    .font(AITheme.fontHeading)

                HStack(spacing: 10) {
                    TextField("owner/repo (e.g. bartowski/Qwen2.5-3B-Instruct-GGUF)", text: $hfRepoInput)
                        .textFieldStyle(.roundedBorder)
                        .font(AITheme.fontCaption)
                        .autocorrectionDisabled()

                    Button(isFetchingHFFiles ? "Fetching..." : "Fetch GGUFs") {
                        Task { await fetchHFGGUFFiles() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFetchingHFFiles || hfRepoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !hfGGUFFiles.isEmpty {
                    Picker("GGUF File", selection: $selectedHFGGUFFile) {
                        ForEach(hfGGUFFiles, id: \.self) { file in
                            Text(file).tag(file)
                        }
                    }

                    Button("Download Selected GGUF") {
                        downloadTask = Task { await downloadSelectedHFGGUF() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedHFGGUFFile.isEmpty || downloadingModelID != nil)
                }

                Text("Enter any Hugging Face repo, fetch available GGUF files, then download directly into local models.")
                    .font(AITheme.fontCaption)
                    .foregroundStyle(AITheme.textSecondary)
            }
            .aiCard()

            if !localModels.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Downloaded Models").font(AITheme.fontHeading)
                    VStack(spacing: 12) {
                        ForEach(localModels) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.url.lastPathComponent)
                                        .font(AITheme.fontBody)
                                    Text(ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file))
                                        .font(AITheme.fontCaption)
                                        .foregroundStyle(AITheme.textSecondary)
                                }

                                Spacer()

                                HStack(spacing: 12) {
                                    Button(isSelectedModelFile(model) ? "Selected" : "Use") {
                                        selectLocalModel(model)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isSelectedModelFile(model))

                                    Button("Delete", role: .destructive) {
                                        deleteModel(model)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            Divider()
                        }
                    }
                }
                .aiCard()
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(AITheme.fontCaption)
            }
        }
        .padding()
        }
        .onAppear {
            loadSelectedModel()
            loadCloudSettings()
            localModelEnabled = (defaults.object(forKey: Constants.UserDefaultsKeys.localModelEnabled) as? Bool ?? true)
                && LocalModelManager.isAvailable
            refreshModels()
        }
    }

    // MARK: - Components

    private func runTestPrompt() {
        isTestRunning = true
        testPromptResponse = ""

        // Mock testing feature to provide immediate UI feedback per requirements
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                testPromptResponse = "This is a simulated completion for '\(testPromptInput)' to verify UI."
                isTestRunning = false
            }
        }
    }

    // MARK: - Private

    private func refreshModels() {
        do {
            let directory = try AppGroupManager.shared.modelsDirectoryURL(createIfMissing: true)
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            localModels = urls.compactMap { url in
                guard url.pathExtension.lowercased() == "gguf" else {
                    return nil
                }

                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                return LocalModelFile(url: url, sizeBytes: size)
            }
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }

            if let selectedModelIdentifier,
               !localModels.contains(where: { $0.url.lastPathComponent.caseInsensitiveCompare(selectedModelIdentifier) == .orderedSame }) {
                defaults.removeObject(forKey: Constants.UserDefaultsKeys.selectedModelIdentifier)
                self.selectedModelIdentifier = nil
            }

            if selectedModelIdentifier == nil {
                let preferredFileName = Constants.LocalModels.preferredDefaultFileName
                if let preferred = localModels.first(where: {
                    $0.url.lastPathComponent.caseInsensitiveCompare(preferredFileName) == .orderedSame
                }) {
                    selectLocalModel(preferred)
                } else if let firstInstalled = localModels.first {
                    selectLocalModel(firstInstalled)
                }
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isModelInstalled(_ model: ModelCatalogItem) -> Bool {
        localModels.contains { local in
            local.url.lastPathComponent.caseInsensitiveCompare(model.fileName) == .orderedSame
        }
    }

    private func isModelSelected(_ model: ModelCatalogItem) -> Bool {
        guard let selectedModelIdentifier else {
            return false
        }
        return selectedModelIdentifier.caseInsensitiveCompare(model.fileName) == .orderedSame
    }

    private func isSelectedModelFile(_ model: LocalModelFile) -> Bool {
        guard let selectedModelIdentifier else {
            return false
        }
        return selectedModelIdentifier.caseInsensitiveCompare(model.url.lastPathComponent) == .orderedSame
    }

    private func loadSelectedModel() {
        let value = defaults.string(forKey: Constants.UserDefaultsKeys.selectedModelIdentifier)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        selectedModelIdentifier = (value?.isEmpty == false) ? value : nil
    }

    private func selectModel(_ model: ModelCatalogItem) {
        defaults.set(model.fileName, forKey: Constants.UserDefaultsKeys.selectedModelIdentifier)
        selectedModelIdentifier = model.fileName
        errorMessage = nil
    }

    private func selectLocalModel(_ model: LocalModelFile) {
        let fileName = model.url.lastPathComponent
        defaults.set(fileName, forKey: Constants.UserDefaultsKeys.selectedModelIdentifier)
        selectedModelIdentifier = fileName
        errorMessage = nil
    }

    private func downloadModel(_ model: ModelCatalogItem) async {
        do {
            try await downloadModelFile(
                modelID: model.id,
                displayName: model.displayName,
                fileName: model.fileName,
                downloadURL: model.downloadURL,
                expectedSHA256: model.expectedSHA256
            )
            errorMessage = nil
        } catch {
            errorMessage = "Failed to download \(model.displayName): \(error.localizedDescription)"
        }
    }

    private func fetchHFGGUFFiles() async {
        let repo = hfRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidHFRepoID(repo) else {
            errorMessage = "Invalid repo format. Use owner/repository."
            return
        }

        isFetchingHFFiles = true
        defer { isFetchingHFFiles = false }

        do {
            guard let url = URL(string: "https://huggingface.co/api/models/\(repo)") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("AIComplete/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ModelDownloadError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ModelDownloadError.failedStatusCode(httpResponse.statusCode)
            }

            let modelInfo = try JSONDecoder().decode(HuggingFaceModelInfo.self, from: data)
            let ggufFiles = (modelInfo.siblings ?? [])
                .map(\.rfilename)
                .filter { $0.lowercased().hasSuffix(".gguf") }
                .sorted()

            hfGGUFFiles = ggufFiles
            selectedHFGGUFFile = ggufFiles.first ?? ""
            if ggufFiles.isEmpty {
                errorMessage = "No GGUF files found in this Hugging Face repository."
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = "Failed to fetch Hugging Face files: \(error.localizedDescription)"
            hfGGUFFiles = []
            selectedHFGGUFFile = ""
        }
    }

    private func downloadSelectedHFGGUF() async {
        let repo = hfRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = selectedHFGGUFFile.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidHFRepoID(repo) else {
            errorMessage = "Invalid repo format. Use owner/repository."
            return
        }
        guard !file.isEmpty else {
            errorMessage = "Pick a GGUF file before downloading."
            return
        }
        guard let downloadURL = makeHFResolveURL(repo: repo, file: file) else {
            errorMessage = "Failed to build Hugging Face download URL."
            return
        }

        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let modelID = "hf-\(repo)-\(fileName)".replacingOccurrences(of: "/", with: "_")
        let displayName = "HF \(fileName)"

        do {
            try await downloadModelFile(
                modelID: modelID,
                displayName: displayName,
                fileName: fileName,
                downloadURL: downloadURL,
                expectedSHA256: nil
            )
            errorMessage = nil
        } catch {
            errorMessage = "Failed to download \(displayName): \(error.localizedDescription)"
        }
    }

    private func downloadModelFile(
        modelID: String,
        displayName: String,
        fileName: String,
        downloadURL: URL,
        expectedSHA256: String?
    ) async throws {
        downloadingModelID = modelID
        downloadProgressByModelID[modelID] = 0
        defer {
            downloadingModelID = nil
            downloadProgressByModelID.removeValue(forKey: modelID)
        }

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 60 * 10
        request.setValue("AIComplete/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let (temporaryURL, response) = try await downloadTemporaryFile(for: request, modelID: modelID)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelDownloadError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw ModelDownloadError.failedStatusCode(httpResponse.statusCode)
        }

        try validateChecksum(for: temporaryURL, response: httpResponse, expectedSHA256: expectedSHA256)

        let downloadedFileSize = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if downloadedFileSize < 5 * 1024 * 1024 {
            throw ModelDownloadError.suspiciousFileSize(downloadedFileSize)
        }

        let destinationDirectory = try AppGroupManager.shared.modelsDirectoryURL(createIfMissing: true)
        let destinationURL = destinationDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        if selectedModelIdentifier == nil
            || fileName.caseInsensitiveCompare(Constants.LocalModels.preferredDefaultFileName) == .orderedSame {
            defaults.set(fileName, forKey: Constants.UserDefaultsKeys.selectedModelIdentifier)
            selectedModelIdentifier = fileName
        }
        refreshModels()
        NSLog("[AIComplete] Downloaded model: \(displayName) -> \(fileName)")
    }

    private func deleteModel(_ model: LocalModelFile) {
        do {
            try FileManager.default.removeItem(at: model.url)
            if isSelectedModelFile(model) {
                defaults.removeObject(forKey: Constants.UserDefaultsKeys.selectedModelIdentifier)
                selectedModelIdentifier = nil
            }
            refreshModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCloudSettings() {
        APIKeyStore.migrateFromUserDefaultsIfNeeded(defaults)
        cloudProvider = SettingsViewModel.CloudProviderOption(
            rawValue: defaults.string(forKey: Constants.UserDefaultsKeys.cloudProvider) ?? "openAI"
        ) ?? .openAI
        apiKey = APIKeyStore.read() ?? ""
        cloudModelIdentifier = defaults.string(forKey: Constants.UserDefaultsKeys.cloudModelIdentifier)
            ?? SettingsViewModel.cloudModels(for: cloudProvider).first?.id ?? ""
        privacyModeEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.privacyModeEnabled)
    }

    private func persistCloud() {
        defaults.set(cloudProvider.rawValue, forKey: Constants.UserDefaultsKeys.cloudProvider)
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = APIKeyStore.delete()
        } else {
            _ = APIKeyStore.save(apiKey)
        }
        defaults.set(cloudModelIdentifier, forKey: Constants.UserDefaultsKeys.cloudModelIdentifier)
        defaults.set(privacyModeEnabled, forKey: Constants.UserDefaultsKeys.privacyModeEnabled)
        if privacyModeEnabled {
            defaults.set(SettingsViewModel.CompletionModeOption.localOnly.rawValue,
                         forKey: Constants.UserDefaultsKeys.completionMode)
        }
    }

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if let id = downloadingModelID {
            downloadingModelID = nil
            downloadProgressByModelID.removeValue(forKey: id)
        }
    }

    private func formattedProgress(for modelID: String) -> String {
        let progress = min(max(downloadProgressByModelID[modelID] ?? 0, 0), 1)
        return "\(Int(progress * 100))%"
    }

    private func validateChecksum(for temporaryURL: URL, response: HTTPURLResponse, expectedSHA256: String?) throws {
        guard let expectedSHA256 else { return }
        let expected = expectedSHA256.lowercased()
        if let etagValue = response.value(forHTTPHeaderField: "ETag"),
           let responseHash = normalizedSHA256Candidate(from: etagValue),
           responseHash != expected {
            throw ModelDownloadError.checksumMismatch(expected: expected, actual: responseHash)
        }

        let actual = try sha256Hex(for: temporaryURL)
        guard actual == expected else {
            throw ModelDownloadError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    private func normalizedSHA256Candidate(from etag: String) -> String? {
        let normalized = etag
            .replacingOccurrences(of: "W/", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .lowercased()
        guard normalized.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }

    private func isValidHFRepoID(_ repoID: String) -> Bool {
        let parts = repoID.split(separator: "/")
        guard parts.count == 2 else { return false }
        return !parts[0].isEmpty && !parts[1].isEmpty
    }

    private func makeHFResolveURL(repo: String, file: String) -> URL? {
        let repoParts = repo.split(separator: "/").map(String.init)
        guard repoParts.count == 2 else { return nil }

        let encodedOwner = repoParts[0].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoParts[0]
        let encodedRepo = repoParts[1].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoParts[1]
        let encodedFile = file
            .split(separator: "/")
            .map { component in
                component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")

        return URL(string: "https://huggingface.co/\(encodedOwner)/\(encodedRepo)/resolve/main/\(encodedFile)")
    }

    private func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func downloadTemporaryFile(for request: URLRequest, modelID: String) async throws -> (URL, URLResponse) {
        final class DownloadResponse: @unchecked Sendable {
            var continuation: CheckedContinuation<(URL, URLResponse), Error>?
            var observation: NSKeyValueObservation?
            var session: URLSession?
        }

        let holder = DownloadResponse()

        return try await withCheckedThrowingContinuation { continuation in
            holder.continuation = continuation

            let session = URLSession(configuration: .default)
            holder.session = session

            let task = session.downloadTask(with: request) { temporaryURL, response, error in
                holder.observation?.invalidate()
                holder.session?.finishTasksAndInvalidate()

                if let error {
                    holder.continuation?.resume(throwing: error)
                    holder.continuation = nil
                    return
                }

                guard let temporaryURL, let response else {
                    holder.continuation?.resume(throwing: ModelDownloadError.invalidResponse)
                    holder.continuation = nil
                    return
                }

                holder.continuation?.resume(returning: (temporaryURL, response))
                holder.continuation = nil
            }

            holder.observation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                let value = min(max(progress.fractionCompleted, 0), 1)
                Task { @MainActor in
                    downloadProgressByModelID[modelID] = value
                }
            }

            task.resume()
        }
    }
}

// MARK: - Extracted Card View

private struct ModelCardView: View {
    let model: ModelCatalogItem
    let isDownloading: Bool
    let downloadProgress: Double
    let isInstalled: Bool
    let isSelected: Bool
    let isTesting: Bool
    let testPromptResponse: String
    let isTestRunning: Bool

    @Binding var testPromptInput: String

    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onSelect: () -> Void
    let onToggleTest: () -> Void
    let onRunTest: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: AITheme.spacingS + 4) {
            Text(model.displayName).font(AITheme.fontHeading)
            Text(model.shortDescription).font(AITheme.fontCaption).foregroundStyle(AITheme.textSecondary)

            HStack {
                Label("\(model.qualityRating)/5", systemImage: "star.fill")
                    .symbolRenderingMode(.multicolor)
                Label("\(model.speedRating)/5", systemImage: "bolt.fill")
                    .symbolRenderingMode(.multicolor)
                Spacer()
                Text(model.languageSupport)
            }
            .font(AITheme.fontCaption2)
            .foregroundStyle(AITheme.textSecondary)

            Text("\(model.estimatedSizeLabel) • \(model.recommendedFor)")
                .font(AITheme.fontCaption)
                .foregroundStyle(AITheme.textSecondary)

            Divider()

            // Action buttons — clear hierarchy:
            // Primary: .borderedProminent (Select/Download)
            // Secondary: .bordered (Test)
            // Tertiary: .plain (Cancel)
            HStack {
                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .frame(maxWidth: .infinity)
                    Button(action: onCancelDownload) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                } else if isInstalled {
                    if isSelected {
                        Button(action: onToggleTest) {
                            Label("Test", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        AITheme.statusPill("Selected", isPositive: true)
                    } else {
                        Button("Select", action: onSelect)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button("Download", action: onDownload)
                        .buttonStyle(.bordered)
                }
            }

            if isTesting {
                VStack(alignment: .leading, spacing: AITheme.spacingS) {
                    Divider()
                    Text("Test Prompt").font(AITheme.fontCaptionBold)
                    HStack {
                        TextField("E.g. The quick brown fox...", text: $testPromptInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Run", action: onRunTest)
                            .buttonStyle(.borderedProminent)
                            .disabled(testPromptInput.isEmpty || isTestRunning)
                    }
                    if isTestRunning {
                        ProgressView().controlSize(.small)
                    } else if !testPromptResponse.isEmpty {
                        Text(testPromptResponse)
                            .font(AITheme.fontCaption)
                            .padding(AITheme.spacingS)
                            .background(AITheme.accentMist, in: RoundedRectangle(cornerRadius: AITheme.spacingS))
                    }
                }
                .padding(.top, AITheme.spacingXS)
            }
        }
        .padding(AITheme.spacingM)
        .background(
            RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                .stroke(isSelected ? AnyShapeStyle(AITheme.accent) : AnyShapeStyle(AITheme.innerGlow), lineWidth: isSelected ? 2 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous))
        .shadow(
            color: isHovered ? AITheme.shadowHover.color : AITheme.shadowLight.color,
            radius: isHovered ? AITheme.shadowHover.radius : AITheme.shadowLight.radius,
            x: 0,
            y: isHovered ? AITheme.shadowHover.y : AITheme.shadowLight.y
        )
        .scaleEffect(reduceMotion ? 1.0 : (isHovered ? 1.02 : 1.0))
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isHovered = hovering
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.displayName), \(model.shortDescription)")
    }
}
