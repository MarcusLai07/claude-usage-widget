#!/bin/bash
# Entry point for a macOS Shortcut / menu-bar button.
#
# Refreshes the signing only if the installed provisioning profile is near
# expiry (delegates to refresh-signing.sh), then always (re)opens the app.
# Because a Shortcut runs interactively, it can prompt once for Documents
# access instead of needing Full Disk Access on a background launchd job.
#
# Point a Shortcuts "Run Shell Script" action (shell: /bin/bash) at this file
# by absolute path:
#   /Users/marcus/Documents/GitHub/personal/claude-usage-widget/Scripts/refresh-and-open.sh
set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/ClaudeUsage.app"

notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Claude Usage\"" 2>/dev/null || true; }

if "$DIR/refresh-signing.sh"; then
    open "$APP" 2>/dev/null || true
    notify "Claude Usage is ready."
else
    notify "Refresh failed — open Xcode / check your Apple ID, then run the shortcut again."
    exit 1
fi
