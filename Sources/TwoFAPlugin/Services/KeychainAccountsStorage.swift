import Foundation
import Security

final class KeychainAccountsStorage {
    enum StorageError: LocalizedError {
        case unhandledStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandledStatus(let status):
                return "Keychain 操作失败：\(status)"
            }
        }
    }

    private let service = "com.local.TwoFATool.accounts"
    private let account = "totp-accounts"

    func load() throws -> [TOTPAccount] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess else {
            throw StorageError.unhandledStatus(status)
        }

        guard let data = item as? Data else {
            return []
        }

        return try JSONDecoder().decode([TOTPAccount].self, from: data)
    }

    func save(_ accounts: [TOTPAccount]) throws {
        let data = try JSONEncoder().encode(accounts)
        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw StorageError.unhandledStatus(updateStatus)
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw StorageError.unhandledStatus(addStatus)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
