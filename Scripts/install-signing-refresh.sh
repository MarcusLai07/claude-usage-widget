#!/bin/bash
# Installs (or reinstalls) the LaunchAgent that keeps the dev-signed app
# launchable by refreshing its 7-day provisioning profile before it lapses.
#   Install:   Scripts/install-signing-refresh.sh
#   Uninstall: Scripts/install-signing-refresh.sh --uninstall
set -euo pipefail

LABEL="com.marcuslai.claudeusage.signing-refresh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/Scripts/$LABEL.plist"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if [ "${1:-}" = "--uninstall" ]; then
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$DEST"
    echo "Uninstalled $LABEL"
    exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cp "$SRC" "$DEST"

# Reload cleanly (ignore "not loaded" on first install).
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$DEST"
launchctl enable "$DOMAIN/$LABEL"

echo "Installed $LABEL"
echo "  plist: $DEST"
echo "  log:   $HOME/Library/Logs/ClaudeUsage-signing-refresh.log"
echo "Runs at login + daily at 10:00. Kick off a check now with:"
echo "  launchctl kickstart $DOMAIN/$LABEL"
