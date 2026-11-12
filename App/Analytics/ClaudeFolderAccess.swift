import AppKit

/// The app is sandboxed, so reading transcripts requires one-time
/// user-granted security-scoped bookmarks: one for `~/.claude` (Claude
/// Code), and optionally one for Claude Desktop's data folder, whose
/// local-agent sessions keep Claude Code transcripts of their own.
enum ClaudeFolderAccess {
    struct Folder {
        let bookmarkKey: String
        /// Path under the user's real home folder.
        let relativePath: String
        let message: String
    }

    static let claudeCode = Folder(
        bookmarkKey: "claudeFolderBookmark",
        relativePath: ".claude",
        message: "Grant read access to your Claude Code folder to analyze local token usage.")

    static let claudeDesktop = Folder(
        bookmarkKey: "claudeDesktopFolderBookmark",
        relativePath: "Library/Application Support/Claude",
        message: "Grant read access to Claude Desktop's folder to include its local-agent sessions.")

    /// The user's real home folder (in the sandbox, `NSHomeDirectory()` and
    /// `homeDirectoryForCurrentUser` are the app's container).
    static let realHome: URL = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    static func defaultURL(_ folder: Folder) -> URL {
        realHome.appendingPathComponent(folder.relativePath, isDirectory: true)
    }

    static func resolve(_ folder: Folder = claudeCode) -> URL? {
        guard let data = AppGroupStore.defaults.data(forKey: folder.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            AppGroupStore.defaults.set(fresh, forKey: folder.bookmarkKey)
        }
        return url
    }

    @MainActor
    static func requestAccess(_ folder: Folder = claudeCode) -> URL? {
        let panel = NSOpenPanel()
        panel.message = folder.message
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = defaultURL(folder)
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return nil }
        AppGroupStore.defaults.set(bookmark, forKey: folder.bookmarkKey)
        return url
    }

    static func revoke(_ folder: Folder = claudeCode) {
        AppGroupStore.defaults.removeObject(forKey: folder.bookmarkKey)
    }
}
