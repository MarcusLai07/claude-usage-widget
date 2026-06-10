import AppKit

/// The app is sandboxed, so reading `~/.claude` requires a one-time
/// user-granted security-scoped bookmark.
enum ClaudeFolderAccess {
    private static let bookmarkKey = "claudeFolderBookmark"

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    static func resolve() -> URL? {
        guard let data = AppGroupStore.defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            AppGroupStore.defaults.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    @MainActor
    static func requestAccess() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Grant read access to your Claude Code folder to analyze local token usage."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = defaultFolder
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return nil }
        AppGroupStore.defaults.set(bookmark, forKey: bookmarkKey)
        return url
    }

    static func revoke() {
        AppGroupStore.defaults.removeObject(forKey: bookmarkKey)
    }
}
