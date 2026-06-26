import AppKit
import Foundation

// MARK: - Protocol

protocol AppGroupManaging: Sendable {
    func sharedContainerURL() -> URL?
    func sharedUserDefaults() -> UserDefaults?
    func modelsDirectoryURL(createIfMissing: Bool) throws -> URL
    func persistentStoreURL(createParentIfMissing: Bool) throws -> URL
}

// MARK: - Error

enum AppGroupManagerError: LocalizedError {
    case unableToCreateDirectory(URL, Error)

    var errorDescription: String? {
        switch self {
        case let .unableToCreateDirectory(url, error):
            return "Failed to create directory at \(url.path): \(error.localizedDescription)"
        }
    }
}

// MARK: - Manager

final class AppGroupManager: AppGroupManaging, @unchecked Sendable {
    static let shared = AppGroupManager()

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        // On macOS there is no keyboard extension to share defaults with,
        // so use .standard to avoid cfprefsd errors and data-access dialogs.
        self.cachedDefaults = .standard
    }

    private let cachedDefaults: UserDefaults?

    func sharedContainerURL() -> URL? {
        // On macOS there is no keyboard extension to share a container with.
        // Attempting to access the app group container triggers repeated
        // file-access permission dialogs, so always use the fallback path.
        return nil
    }

    func sharedUserDefaults() -> UserDefaults? {
        cachedDefaults
    }

    func modelsDirectoryURL(createIfMissing: Bool = true) throws -> URL {
        let documentsDirectory = try sharedDocumentsDirectory(createIfMissing: createIfMissing)
        let modelsDirectory = documentsDirectory.appendingPathComponent(
            Constants.AppGroup.modelsDirectoryName,
            isDirectory: true
        )

        if createIfMissing {
            try createDirectoryIfNeeded(at: modelsDirectory)
        }

        return modelsDirectory
    }

    func persistentStoreURL(createParentIfMissing: Bool = true) throws -> URL {
        let documentsDirectory = try sharedDocumentsDirectory(createIfMissing: createParentIfMissing)
        return documentsDirectory.appendingPathComponent(Constants.Storage.sqliteFileName, isDirectory: false)
    }

    // MARK: - Private

    private func sharedDocumentsDirectory(createIfMissing: Bool) throws -> URL {
        let baseURL = preferredContainerURL()
        let documentsURL = baseURL.appendingPathComponent(Constants.AppGroup.documentsDirectoryName, isDirectory: true)

        if createIfMissing {
            try createDirectoryIfNeeded(at: documentsURL)
        }

        return documentsURL
    }

    private func preferredContainerURL() -> URL {
        if let sharedContainerURL = sharedContainerURL() {
            return sharedContainerURL
        }

        // Keep local development and tests functional when App Group entitlement is unavailable.
        let fallbackRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return fallbackRoot.appendingPathComponent(Constants.AppGroup.sharedRootDirectoryName, isDirectory: true)
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw AppGroupManagerError.unableToCreateDirectory(url, error)
        }
    }
}

struct AppOverrideRecord: Codable, Identifiable, Hashable {
    enum OverrideMode: String, Codable, CaseIterable, Identifiable {
        case inherit
        case enabled
        case disabled

        var id: String { rawValue }
    }

    let bundleIdentifier: String
    var displayName: String
    var completionsMode: OverrideMode
    var disableTabMode: OverrideMode
    var customInstructions: String
    var lastSeenAt: Date

    var id: String { bundleIdentifier }

    var hasCustomizations: Bool {
        completionsMode != .inherit
            || disableTabMode != .inherit
            || !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resolvedCompletionsEnabled(defaultValue: Bool = true) -> Bool {
        switch completionsMode {
        case .inherit:
            return defaultValue
        case .enabled:
            return true
        case .disabled:
            return false
        }
    }

    func resolvedTabDisabled(defaultValue: Bool = false) -> Bool {
        switch disableTabMode {
        case .inherit:
            return defaultValue
        case .enabled:
            return true
        case .disabled:
            return false
        }
    }
}

final class AppOverridesStore {
    static let shared = AppOverridesStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard) {
        self.defaults = defaults
    }

    func allRecords() -> [AppOverrideRecord] {
        loadRecords()
            .sorted { lhs, rhs in
                let lhsCustomized = lhs.hasCustomizations
                let rhsCustomized = rhs.hasCustomizations
                if lhsCustomized != rhsCustomized {
                    return lhsCustomized && !rhsCustomized
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func record(for bundleIdentifier: String?) -> AppOverrideRecord? {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else {
            return nil
        }
        return loadRecords().first(where: { $0.bundleIdentifier == bundleIdentifier })
    }

    func registerSeenApp(bundleIdentifier: String?, displayName: String?) {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else {
            return
        }

        let resolvedName = normalizedDisplayName(displayName) ?? bundleIdentifier
        var records = loadRecords()

        if let index = records.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            records[index].displayName = resolvedName
            records[index].lastSeenAt = Date()
        } else {
            records.append(
                AppOverrideRecord(
                    bundleIdentifier: bundleIdentifier,
                    displayName: resolvedName,
                    completionsMode: .inherit,
                    disableTabMode: .inherit,
                    customInstructions: "",
                    lastSeenAt: Date()
                )
            )
        }

        saveRecords(records)
    }

    func seedFromRunningApplications() {
        var records = loadRecords()
        var changed = false

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else {
                continue
            }
            guard let bundleIdentifier = normalizedBundleIdentifier(app.bundleIdentifier) else {
                continue
            }
            let resolvedName = normalizedDisplayName(app.localizedName) ?? bundleIdentifier

            if let index = records.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
                if records[index].displayName != resolvedName {
                    records[index].displayName = resolvedName
                    changed = true
                }
            } else {
                records.append(
                    AppOverrideRecord(
                        bundleIdentifier: bundleIdentifier,
                        displayName: resolvedName,
                        completionsMode: .inherit,
                        disableTabMode: .inherit,
                        customInstructions: "",
                        lastSeenAt: .distantPast
                    )
                )
                changed = true
            }
        }

        if changed {
            saveRecords(records)
        }
    }

    func save(_ record: AppOverrideRecord) {
        var records = loadRecords()
        if let index = records.firstIndex(where: { $0.bundleIdentifier == record.bundleIdentifier }) {
            records[index] = record
        } else {
            records.append(record)
        }
        saveRecords(records)
    }

    func resetOverride(for bundleIdentifier: String) {
        guard let existing = record(for: bundleIdentifier) else {
            return
        }

        let reset = AppOverrideRecord(
            bundleIdentifier: existing.bundleIdentifier,
            displayName: existing.displayName,
            completionsMode: .inherit,
            disableTabMode: .inherit,
            customInstructions: "",
            lastSeenAt: existing.lastSeenAt
        )
        save(reset)
    }

    func completionsEnabled(for bundleIdentifier: String?, defaultValue: Bool = true) -> Bool {
        guard let record = record(for: bundleIdentifier) else {
            return defaultValue
        }
        return record.resolvedCompletionsEnabled(defaultValue: defaultValue)
    }

    func isTabKeyDisabled(for bundleIdentifier: String?, defaultValue: Bool = false) -> Bool {
        guard let record = record(for: bundleIdentifier) else {
            return defaultValue
        }
        return record.resolvedTabDisabled(defaultValue: defaultValue)
    }

    func customInstructions(for bundleIdentifier: String?) -> String? {
        guard let record = record(for: bundleIdentifier) else {
            return nil
        }
        let instructions = record.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return instructions.isEmpty ? nil : instructions
    }

    private func loadRecords() -> [AppOverrideRecord] {
        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.appOverrideRecords),
              let decoded = try? decoder.decode([AppOverrideRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveRecords(_ records: [AppOverrideRecord]) {
        guard let data = try? encoder.encode(records) else {
            return
        }
        defaults.set(data, forKey: Constants.UserDefaultsKeys.appOverrideRecords)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        NotificationCenter.default.post(name: .aiCompleteSettingsChanged, object: nil)
    }

    private func normalizedBundleIdentifier(_ bundleIdentifier: String?) -> String? {
        let value = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private func normalizedDisplayName(_ displayName: String?) -> String? {
        let value = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}
