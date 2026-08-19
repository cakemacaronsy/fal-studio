import Foundation
import Security

/// Stores the FAL API key in a private file (chmod 600) under Application
/// Support instead of the keychain: ad-hoc-signed dev builds get a new code
/// signature every rebuild, which made macOS show a keychain permission
/// prompt after each update. A 600-permission file matches the security of
/// the fal skill's .env (where the key already lives in plain text) with
/// zero prompts.
nonisolated enum KeychainStore {
    private static var keyFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FAL Studio", isDirectory: true)
            .appendingPathComponent("fal_key")
    }

    static func load() -> String? {
        // One-time migration: drain any old keychain entry into the file
        // (delete does not trigger the permission prompt; reading would,
        // so we only migrate silently when the file already answers).
        if let key = try? String(contentsOf: keyFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            deleteLegacyKeychainItem()
            return key
        }
        return nil
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: keyFileURL)
            return true
        }
        do {
            try FileManager.default.createDirectory(
                at: keyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(trimmed.utf8).write(to: keyFileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: keyFileURL.path)
            deleteLegacyKeychainItem()
            return true
        } catch {
            return false
        }
    }

    static func delete() {
        try? FileManager.default.removeItem(at: keyFileURL)
        deleteLegacyKeychainItem()
    }

    private static func deleteLegacyKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "FAL Studio",
            kSecAttrAccount as String: "FAL_KEY",
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// The key to use for API calls, in priority order: FAL_KEY env var →
    /// saved key file (Settings) → the fal skill's .env file, mirroring the
    /// Python scripts so the app works without re-entering the key.
    static var effectiveKey: String? {
        if let env = ProcessInfo.processInfo.environment["FAL_KEY"],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env.trimmingCharacters(in: .whitespaces)
        }
        if let stored = load() {
            return stored
        }
        return dotEnvKey()
    }

    /// Parse FAL_KEY from the same .env file the fal skill scripts use.
    private static func dotEnvKey() -> String? {
        let path = NSHomeDirectory() + "/.claude/skills/fal/.env"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n") {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("export ") {
                trimmed = String(trimmed.dropFirst("export ".count))
            }
            guard trimmed.hasPrefix("FAL_KEY"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let value = trimmed[trimmed.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }
}
