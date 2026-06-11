#!/bin/bash
# Builds a Release configuration bundle and zips it into dist/.
# Usage: Scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)

xcodegen generate
xcodebuild -scheme ClaudeUsage -configuration Release \
  -allowProvisioningUpdates -derivedDataPath build.noindex build | tail -2

mkdir -p dist
rm -rf dist/ClaudeUsage.app "dist/ClaudeUsage-${VERSION}.zip"
ditto build.noindex/Build/Products/Release/ClaudeUsage.app dist/ClaudeUsage.app
ditto -ck --keepParent dist/ClaudeUsage.app "dist/ClaudeUsage-${VERSION}.zip"

echo "Built dist/ClaudeUsage-${VERSION}.zip"
