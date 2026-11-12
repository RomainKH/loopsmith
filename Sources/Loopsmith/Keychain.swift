import Foundation
#if canImport(Security)
import Security
#endif

/// Secrets (the Jira API token, custom API keys) never go into the settings file.
/// macOS keeps them in the login keychain; elsewhere they live in `secrets.json`, readable by the user only.
enum Keychain {
    private static let service = "Loopsmith"

    #if canImport(Security)
    static func get(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String, for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
    #else
    private static var file: URL { AppStore.folder.appendingPathComponent("secrets.json") }
    private static let lock = NSLock()

    private static func readAll() -> [String: String] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func get(_ account: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return readAll()[account] ?? ""
    }

    static func set(_ value: String, for account: String) {
        lock.lock(); defer { lock.unlock() }
        var all = readAll()
        all[account] = value.isEmpty ? nil : value
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(all) else { return }
        // Created empty with 0600 first, so the secrets are never readable by others, even for an instant.
        if !FileManager.default.fileExists(atPath: file.path) {
            _ = FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? data.write(to: file)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    #endif
}
