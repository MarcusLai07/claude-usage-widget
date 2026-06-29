#!/bin/bash
# Keeps the locally-installed /Applications/ClaudeUsage.app launchable.
#
# The app is signed with an "Apple Development" certificate, so its embedded
# provisioning profile is only valid for 7 days. Once it lapses, a cold launch
# (e.g. after a reboot) fails with "Launch failed" / POSIX 163 — launchd/AMFI
# refuses to spawn the process. This script rebuilds + reinstalls a freshly
# signed bundle (new 7-day profile) whenever the installed one is close to
# expiring. Driven by a LaunchAgent (see Scripts/install-signing-refresh.sh).
#
# It no-ops cheaply when the profile is still fresh, so running it daily / at
# login is fine — a full rebuild only happens every few days.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

APP="/Applications/ClaudeUsage.app"
THRESHOLD_DAYS="${THRESHOLD_DAYS:-4}"   # refresh once the profile has this many days (or fewer) left

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"Claude Usage\"" 2>/dev/null || true
}

# Echoes the days remaining on the installed profile, or "0" if the app /
# profile is missing or unreadable (which forces a refresh).
days_left() {
  local prof="$APP/Contents/embedded.provisionprofile"
  [ -f "$prof" ] || { echo 0; return; }
  local exp exp_epoch now
  exp=$(security cms -D -i "$prof" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null) || { echo 0; return; }
  exp_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$exp" +%s 2>/dev/null) || { echo 0; return; }
  now=$(date +%s)
  echo $(( (exp_epoch - now) / 86400 ))
}

REMAINING=$(days_left)
log "installed provisioning profile: ~${REMAINING} day(s) left (threshold ${THRESHOLD_DAYS})"

if [ "$REMAINING" -gt "$THRESHOLD_DAYS" ]; then
  log "still valid; nothing to do"
  exit 0
fi

log "refreshing signature (rebuild + reinstall)…"
if ! Scripts/release.sh; then
  log "ERROR: build failed — app will expire until this is fixed (check Xcode/Apple ID session)"
  notify "Auto-refresh failed — open Xcode and check your Apple ID, then rerun Scripts/refresh-signing.sh"
  exit 1
fi

was_running=0
if pgrep -x ClaudeUsage >/dev/null; then was_running=1; fi

/usr/bin/osascript -e 'tell application "ClaudeUsage" to quit' 2>/dev/null || true
pkill -x ClaudeUsage 2>/dev/null || true
sleep 1

rm -rf "$APP"
ditto dist/ClaudeUsage.app "$APP"

NEW_LEFT=$(days_left)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo '?')
log "reinstalled v${VERSION}; profile now ~${NEW_LEFT} day(s) left"

if [ "$was_running" -eq 1 ]; then
  open "$APP" || true
  log "relaunched app"
fi
