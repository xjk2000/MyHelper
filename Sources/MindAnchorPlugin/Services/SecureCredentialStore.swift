import Foundation
import Security

struct SecureCredentialStore {
    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "MindAnchor",
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            AppLog.security.error("keychain_save_failed account=\(account, privacy: .public) status=\(status, privacy: .public)")
            throw KeychainError.unhandledStatus(status)
        }

        AppLog.security.info("keychain_save_completed account=\(account, privacy: .public)")
    }

    func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "MindAnchor",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            AppLog.security.info("keychain_read_miss account=\(account, privacy: .public)")
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            AppLog.security.error("keychain_read_failed account=\(account, privacy: .public) status=\(status, privacy: .public)")
            throw KeychainError.unhandledStatus(status)
        }

        return String(data: data, encoding: .utf8)
    }
}

enum KeychainError: Error {
    case unhandledStatus(OSStatus)
}
