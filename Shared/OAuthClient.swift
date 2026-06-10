import Foundation
import CryptoKit
import Security

struct TokenSet: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

enum OAuthError: Error, LocalizedError {
    case invalidCode
    case exchangeFailed(Int)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "That code doesn't look right. Paste the full code shown in the browser."
        case .exchangeFailed(let status): return "Sign-in failed (HTTP \(status)). Try again."
        case .noRefreshToken: return "Session expired. Please sign in again."
        }
    }
}

/// OAuth 2.0 authorization-code flow with PKCE against the same public client
/// Claude Code uses. The user authorizes in the browser and pastes back the
/// code displayed on Anthropic's hosted callback page (format: `code#state`).
enum OAuthClient {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    static let authorizeBase = "https://claude.ai/oauth/authorize"
    static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!

    struct PKCE {
        let verifier: String
        let challenge: String

        init() {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            verifier = Data(bytes).base64URLEncoded
            challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        }
    }

    static func authorizeURL(pkce: PKCE) -> URL {
        var components = URLComponents(string: authorizeBase)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "org:create_api_key user:profile user:inference"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.verifier),
        ]
        return components.url!
    }

    static func exchange(pastedCode: String, pkce: PKCE) async throws -> TokenSet {
        let parts = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#")
        guard let code = parts.first, !code.isEmpty else { throw OAuthError.invalidCode }
        let state = parts.count > 1 ? String(parts[1]) : pkce.verifier

        return try await requestToken(body: [
            "grant_type": "authorization_code",
            "code": String(code),
            "state": state,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier,
        ], fallbackRefreshToken: nil)
    }

    static func refresh(_ tokens: TokenSet) async throws -> TokenSet {
        guard let refreshToken = tokens.refreshToken else { throw OAuthError.noRefreshToken }
        return try await requestToken(body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ], fallbackRefreshToken: refreshToken)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double?
    }

    private static func requestToken(body: [String: String], fallbackRefreshToken: String?) async throws -> TokenSet {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw OAuthError.exchangeFailed(status)
        }
        return TokenSet(
            accessToken: token.access_token,
            refreshToken: token.refresh_token ?? fallbackRefreshToken,
            expiresAt: token.expires_in.map { Date().addingTimeInterval($0) }
        )
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
