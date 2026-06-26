import Foundation
import Security

enum APIKeyStore {
    private static let service = "com.aicomplete.mac.cloud-api-key"
    private static let account = "default"
    private static let cacheLock = NSLock()
    private static var cachedKey: String?
    private static var cacheLoaded = false

    static func read() -> String? {
        cacheLock.lock()
        if cacheLoaded {
            let key = cachedKey
            cacheLock.unlock()
            return key
        }
        cacheLock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            cacheLock.lock()
            cacheLoaded = true
            cachedKey = nil
            cacheLock.unlock()
            return nil
        }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? nil : trimmed
        cacheLock.lock()
        cacheLoaded = true
        cachedKey = normalized
        cacheLock.unlock()
        return normalized
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            delete()
            return true
        }

        let data = Data(normalized.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            cacheLock.lock()
            cacheLoaded = true
            cachedKey = normalized
            cacheLock.unlock()
            return true
        }

        var createAttributes = query
        createAttributes.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(createAttributes as CFDictionary, nil)
        let success = addStatus == errSecSuccess
        cacheLock.lock()
        cacheLoaded = true
        cachedKey = success ? normalized : nil
        cacheLock.unlock()
        return success
    }

    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        let success = status == errSecSuccess || status == errSecItemNotFound
        if success {
            cacheLock.lock()
            cacheLoaded = true
            cachedKey = nil
            cacheLock.unlock()
        }
        return success
    }

    static func migrateFromUserDefaultsIfNeeded(_ defaults: UserDefaults) {
        let defaultValue = defaults.string(forKey: Constants.UserDefaultsKeys.apiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Always remove legacy plaintext copy.
        defer {
            defaults.removeObject(forKey: Constants.UserDefaultsKeys.apiKey)
        }

        guard read() == nil,
              let defaultValue,
              !defaultValue.isEmpty else {
            return
        }

        _ = save(defaultValue)
    }
}
