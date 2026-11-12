#!/bin/bash
# Builds a Release configuration bundle and zips it into dist/.
# Usage: Scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)

xcodegen generate
xcodebuild -scheme ClaudeUsage -configuration Release \
  -allowProvisioningUpdates -derivedDataPath build.noindex build | tail -2

BUILT=build.noindex/Build/Products/Release/ClaudeUsage.app

# Zip straight from the build products. An unzipped .app left in dist/ (which
# Spotlight indexes, unlike build.noindex/) shows up as a second
# "ClaudeUsage.app" in Spotlight and Launchpad.
mkdir -p dist
rm -rf dist/ClaudeUsage.app "dist/ClaudeUsage-${VERSION}.zip"
ditto -ck --keepParent "$BUILT" "dist/ClaudeUsage-${VERSION}.zip"

# xcodebuild registers its build products with LaunchServices, which can also
# surface duplicates. Only the copy in /Applications should be registered.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for app in build.noindex/Build/Products/{Debug,Release}/ClaudeUsage.app; do
  if [ -d "$app" ]; then "$LSREGISTER" -u "$PWD/$app" >/dev/null 2>&1 || true; fi
done

echo "Built dist/ClaudeUsage-${VERSION}.zip"
