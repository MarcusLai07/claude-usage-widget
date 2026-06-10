import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @State private var pkce = OAuthClient.PKCE()
    @State private var pastedCode = ""
    @State private var error: String?
    @State private var isExchanging = false

    var body: some View {
        VStack(spacing: 14) {
            SunburstMark(size: 30)
                .padding(.top, 6)
            Text("Claude Usage")
                .font(.system(size: 16, weight: .semibold))
            Text("Sign in to see your session and weekly limits in the menu bar.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)

            Button {
                pkce = OAuthClient.PKCE()
                NSWorkspace.shared.open(OAuthClient.authorizeURL(pkce: pkce))
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Sign in with Claude")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.clay, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Rectangle().fill(.quaternary).frame(height: 0.5)
                Text("or paste a code")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                Rectangle().fill(.quaternary).frame(height: 0.5)
            }

            HStack(spacing: 8) {
                TextField("Paste authorization code", text: $pastedCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
                Button("Submit") {
                    Task { await exchange() }
                }
                .disabled(pastedCode.isEmpty || isExchanging)
            }

            Button {
                if let tokens = ClaudeCodeImport.importTokens() {
                    refresher.signIn(with: tokens)
                } else {
                    error = "Couldn't read Claude Code credentials from the keychain."
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 11))
                    Text("Use Claude Code credentials")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.clay)
            }
            .buttonStyle(.plain)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.init(top: 20, leading: 18, bottom: 18, trailing: 18))
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
