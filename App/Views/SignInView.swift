import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @State private var pkce = OAuthClient.PKCE()
    @State private var pastedCode = ""
    @State private var error: String?
    @State private var isExchanging = false
    @State private var browserOpened = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in with your Claude account to see plan usage.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Sign in with Claude…") {
                pkce = OAuthClient.PKCE()
                NSWorkspace.shared.open(OAuthClient.authorizeURL(pkce: pkce))
                browserOpened = true
            }

            if browserOpened {
                Text("Authorize in the browser, then paste the code shown:")
                    .font(.caption)
                TextField("Paste code here", text: $pastedCode)
                    .textFieldStyle(.roundedBorder)
                Button("Complete Sign-In") {
                    Task { await exchange() }
                }
                .disabled(pastedCode.isEmpty || isExchanging)
            }

            Divider()

            Button("Use Claude Code credentials instead") {
                if let tokens = ClaudeCodeImport.importTokens() {
                    refresher.signIn(with: tokens)
                } else {
                    error = "Couldn't read Claude Code credentials from the keychain."
                }
            }
            .controlSize(.small)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func exchange() async {
        isExchanging = true
        defer { isExchanging = false }
        do {
            let tokens = try await OAuthClient.exchange(pastedCode: pastedCode, pkce: pkce)
            refresher.signIn(with: tokens)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
