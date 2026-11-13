#!/bin/bash
# Renders the README screenshots into docs/media/ without showing a window or
# taking focus: the app's and widget's real views, fed a sample account
# (Shots/SampleData.swift), drawn offscreen at 2x in dark appearance.
# Usage: Scripts/shot.sh [shot …] [-settle 3] [-height 820]
#   shots: popover menubar widget-rings-small widget-bars-medium
#          widget-rings-medium widget-bars-large window-usage
#          window-requests window-sessions window-context (default: all)
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -scheme ClaudeUsageShots -configuration Debug -derivedDataPath build.noindex build 2>&1 \
  | grep -E "error:|BUILD FAILED" >&2 || true
build.noindex/Build/Products/Debug/ClaudeUsageShots docs/media "$@"
