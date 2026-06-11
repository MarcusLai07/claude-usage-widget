import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @State private var hasClaudeAccess = ClaudeFolderAccess.resolve() != nil

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Account")
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    claudeAccessCard
                    credentialsCard
                }
                .padding(.init(top: 4, leading: 22, bottom: 22, trailing: 22))
            }
        }
        .background(Color.windowContent)
    }

    @ViewBuilder
    private var statusCard: some View {
        if refresher.isSignedIn {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(Color.clay.opacity(0.2))
                        .frame(width: 46, height: 46)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.clay)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed in")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Usage data refreshes every 5 minutes.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refresher.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .designCard()
        } else {
            VStack {
                SignInView()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var claudeAccessCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("Claude Code access")
                .padding(.bottom, 12)
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clay.opacity(0.2))
                        .frame(width: 34, height: 34)
                    Image(systemName: "folder")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.clay)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("~/.claude folder")
                        .font(.system(size: 13, weight: .medium))
                    if hasClaudeAccess {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("Access granted")
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.green)
                    } else {
                        Text("Not granted")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if hasClaudeAccess {
                    Button("Revoke") {
                        ClaudeFolderAccess.revoke()
                        hasClaudeAccess = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.clay)
                } else {
                    Button("Grant Access…") {
                        if ClaudeFolderAccess.requestAccess() != nil {
                            hasClaudeAccess = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.clay)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cardStroke, lineWidth: 0.5))
            HintRow("Used to count tokens by model in Analytics. Files are read locally and never uploaded.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("How your credentials are handled")
                .padding(.bottom, 4)
            kvRow("Authentication", "OAuth via Anthropic's public Claude Code client")
            Divider()
            kvRow("Token storage", "macOS Keychain only — never leaves this Mac")
            Divider()
            kvRow("Reading usage", "Costs zero Claude tokens")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    private func kvRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}
