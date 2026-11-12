import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var refresher: UsageRefresher
    @State private var hasClaudeAccess = ClaudeFolderAccess.resolve() != nil
    @State private var hasDesktopAccess = ClaudeFolderAccess.resolve(ClaudeFolderAccess.claudeDesktop) != nil
    @AppStorage(AppGroupStore.SharedKey.hideAccount, store: AppGroupStore.defaults)
    private var hideAccount = false

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
                    HStack(spacing: 7) {
                        Text(signedInTitle)
                            .font(.system(size: 15, weight: .semibold))
                        if let plan = refresher.profile?.plan {
                            PlanBadge(text: plan)
                        }
                    }
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

    private var signedInTitle: String {
        guard let email = refresher.profile?.email else { return "Signed in" }
        return hideAccount ? AccountProfile.masked(email) : email
    }

    private var claudeAccessCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("Claude Code access")
                .padding(.bottom, 12)
            VStack(spacing: 8) {
                folderRow(title: "~/.claude folder", icon: "folder", granted: hasClaudeAccess,
                          grant: {
                              if ClaudeFolderAccess.requestAccess() != nil { hasClaudeAccess = true }
                          },
                          revoke: {
                              ClaudeFolderAccess.revoke()
                              hasClaudeAccess = false
                          })
                folderRow(title: "Claude Desktop sessions (optional)", icon: "sparkles",
                          granted: hasDesktopAccess,
                          grant: {
                              if ClaudeFolderAccess.requestAccess(ClaudeFolderAccess.claudeDesktop) != nil {
                                  hasDesktopAccess = true
                              }
                          },
                          revoke: {
                              ClaudeFolderAccess.revoke(ClaudeFolderAccess.claudeDesktop)
                              hasDesktopAccess = false
                          })
            }
            HintRow("Used to count Claude Code tokens by app, model and project on the Usage page. Claude Desktop's local-agent sessions keep their own transcripts in ~/Library/Application Support/Claude. Files are read locally and never uploaded.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    private func folderRow(title: String, icon: String, granted: Bool,
                           grant: @escaping () -> Void, revoke: @escaping () -> Void) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clay.opacity(0.2))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.clay)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if granted {
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
            if granted {
                Button("Revoke", action: revoke)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.clay)
            } else {
                Button("Grant Access…", action: grant)
                    .buttonStyle(.borderedProminent)
                    .tint(.clay)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cardStroke, lineWidth: 0.5))
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
