import Foundation
import Security

/// Minimal Keychain wrapper for storing a single sensitive string (the AI API key).
///
/// The API key currently lives in `AppSettings.apiKey` as plaintext inside the
/// SwiftData store (recoverable from device backups). This type is the
/// replacement home for it. Integration is staged: ship the verified utility
/// first, then migrate `AppSettings` to read/write through it and clear the
/// legacy plaintext field on first launch (see `Agent/README.md`).
///
/// Items are stored as `kSecClassGenericPassword`, scoped to this service, and
/// protected with `kSecAttrAccessibleAfterFirstThisDeviceOnly` so the key is
/// available to background work after first unlock but never leaves the device
/// in an iCloud/backup-restorable form.
enum KeychainStore {
    static let service = "com.billmind.app.secrets"

    /// Stable account identifier for the AI provider API key.
    static let apiKeyAccount = "ai_api_key"

    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
        case encodingFailed
    }

    /// Insert or update the value for `account`. Empty string deletes the item.
    static func set(_ value: String, account: String) throws {
        guard !value.isEmpty else {
            try delete(account: account)
            return
        }
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

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
            return
        }
        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }
        throw KeychainError.unexpectedStatus(updateStatus)
    }

    /// Fetch the value for `account`, or `nil` if absent.
    static func get(account: String) -> String? {
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
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Remove the item for `account`. Succeeds whether or not it existed.
    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
