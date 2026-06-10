import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var refresher: UsageRefresher

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if refresher.isSignedIn {
                    GroupBox {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(Color.clay)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Signed in")
                                    .font(.headline)
                                Text("Usage data refreshes every 5 minutes.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Sign Out", role: .destructive) {
                                refresher.signOut()
                            }
                        }
                        .padding(8)
                    }
                } else {
                    GroupBox {
                        SignInView()
                            .frame(maxWidth: 320)
                            .frame(maxWidth: .infinity)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How your credentials are handled", systemImage: "lock.shield")
                            .font(.headline)
                        Text("""
                        Sign-in uses OAuth with Anthropic's public Claude Code client — \
                        the consent page shows "Claude Code" because Anthropic doesn't \
                        offer third-party app registration. Tokens are stored only in \
                        the macOS keychain, requests go only to Anthropic's servers, \
                        and polling never invokes a model or consumes Claude tokens.
                        """)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
    }
}
