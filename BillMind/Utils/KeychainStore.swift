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

    /// Session token accounts (BillMind server auth).
    static let accessTokenAccount = "session_access_token"
    static let refreshTokenAccount = "session_refresh_token"
    static let userIDAccount = "session_user_id"

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

/// The session token vault — `TokenStore` backed by the Keychain. Stores the
/// access JWT + opaque refresh token + user id, all `AfterFirstUnlockThisDeviceOnly`
/// (available to background sync after first unlock, never in iCloud/backups).
struct TokenVault: TokenStore {
    func accessToken() async -> String? { KeychainStore.get(account: KeychainStore.accessTokenAccount) }
    func refreshToken() async -> String? { KeychainStore.get(account: KeychainStore.refreshTokenAccount) }

    /// The signed-in user id, if any — drives the launch sign-in gate.
    func userID() -> UUID? {
        KeychainStore.get(account: KeychainStore.userIDAccount).flatMap(UUID.init(uuidString:))
    }

    func update(_ tokens: APIAuthTokens) async {
        try? KeychainStore.set(tokens.accessToken, account: KeychainStore.accessTokenAccount)
        try? KeychainStore.set(tokens.refreshToken, account: KeychainStore.refreshTokenAccount)
        try? KeychainStore.set(tokens.userID.uuidString, account: KeychainStore.userIDAccount)
    }

    func clear() async {
        try? KeychainStore.delete(account: KeychainStore.accessTokenAccount)
        try? KeychainStore.delete(account: KeychainStore.refreshTokenAccount)
        try? KeychainStore.delete(account: KeychainStore.userIDAccount)
    }
}
