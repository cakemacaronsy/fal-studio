import Foundation
import Security

/// Stores the FAL API key as a generic password in the login keychain.
/// Note: because the app is ad-hoc signed, each rebuild produces a new code
/// signature and macOS shows one "wants to use your keychain" prompt — click
/// Always Allow. (A chmod-600 file under Application Support would avoid the
/// prompt at the cost of storing the key in plain text; not implemented.)
nonisolated enum KeychainStore {
    private static let service = "FAL Studio"
    private static let account = "FAL_KEY"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            return nil
        }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete()
            return true
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(trimmed.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            let addQuery = query.merging(attributes) { _, new in new }
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return updateStatus == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// The key to use for API calls: FAL_KEY env var (handy for CLI testing,
    /// mirroring the Python scripts) overrides the keychain entry.
    static var effectiveKey: String? {
        if let env = ProcessInfo.processInfo.environment["FAL_KEY"],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env.trimmingCharacters(in: .whitespaces)
        }
        return load()
    }
}
