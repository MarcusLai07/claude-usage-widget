import Foundation
import Security

/// Imports the OAuth credentials Claude Code stores in the login keychain
/// (service "Claude Code-credentials"), so users who already use Claude Code
/// can skip the browser sign-in. macOS shows a one-time consent prompt.
enum ClaudeCodeImport {
    static func importTokens() -> TokenSet? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }

        struct Credentials: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let refreshToken: String?
                let expiresAt: Double?
            }
            let claudeAiOauth: OAuth
        }
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else { return nil }
        let oauth = credentials.claudeAiOauth
        return TokenSet(
            accessToken: oauth.accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }
}
