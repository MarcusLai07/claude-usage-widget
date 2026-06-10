import Foundation
import Security

/// Stores the OAuth tokens in the **data-protection keychain** (not the
/// file-based login keychain). That distinction matters: keychain access
/// groups only apply to the data-protection keychain, and the widget
/// extension can never show the login keychain's ACL consent prompt — so
/// this is the only way the widget can read the token silently. Both targets
/// list the same access group first in their entitlements, so items land in
/// the shared group by default.
enum TokenStore {
    private static let service = "com.marcuslai.ClaudeUsage.oauth"
    private static let account = "claude"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func load() -> TokenSet? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let tokens = try? JSONDecoder().decode(TokenSet.self, from: data) {
            return tokens
        }
        return migrateLegacyItem()
    }

    static func save(_ tokens: TokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let status = SecItemUpdate(baseQuery as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        SecItemDelete(legacyQuery as CFDictionary)
    }

    // MARK: Legacy migration

    private static var legacyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Early builds stored the token in the file-based login keychain. Move it
    /// over the first time the app looks for it. In the widget this read fails
    /// silently (no ACL prompt possible) and returns nil — the app does the
    /// migration on its next launch.
    private static func migrateLegacyItem() -> TokenSet? {
        var query = legacyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let tokens = try? JSONDecoder().decode(TokenSet.self, from: data) else { return nil }
        save(tokens)
        SecItemDelete(legacyQuery as CFDictionary)
        return tokens
    }
}
