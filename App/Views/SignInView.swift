import SwiftUI

/// The auth card from the window design: primary "Sign in with Claude",
/// paste-a-code with inline error state, and the Claude Code credentials
/// shortcut. 340 pt wide, radius 14.
struct SignInView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @State private var pkce = OAuthClient.PKCE()
    @State private var pastedCode = ""
    @State private var error: String?
    @State private var isExchanging = false

    var body: some View {
        VStack(spacing: 13) {
            Button {
                pkce = OAuthClient.PKCE()
                NSWorkspace.shared.open(OAuthClient.authorizeURL(pkce: pkce))
            } label: {
                HStack(spacing: 7) {
                    SunburstMark(size: 15, color: .white)
                    Text("Sign in with Claude")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.clay, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            divider("or paste a code")

            HStack(spacing: 8) {
                TextField("Paste authorization code", text: $pastedCode)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.init(top: 9, leading: 11, bottom: 9, trailing: 11))
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(error == nil ? Color.cardStroke : Color.red,
                                      lineWidth: error == nil ? 0.5 : 1))
                Button {
                    Task { await exchange() }
                } label: {
                    Text("Submit")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.init(top: 9, leading: 14, bottom: 9, trailing: 14))
                        .background(Color.clay, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(pastedCode.isEmpty || isExchanging)
                .opacity(pastedCode.isEmpty || isExchanging ? 0.5 : 1)
            }

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                    Text(error)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            divider("or")

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
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.clay)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 340)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cardStroke, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
    }

    private func divider(_ label: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(.quaternary).frame(height: 0.5)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle().fill(.quaternary).frame(height: 0.5)
        }
    }

    private func exchange() async {
        isExchanging = true
        defer { isExchanging = false }
        do {
            let tokens = try await OAuthClient.exchange(pastedCode: pastedCode, pkce: pkce)
            refresher.signIn(with: tokens)
        } catch {
            self.error = "That code didn't work — check for typos and try again."
        }
    }
}
