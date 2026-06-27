#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

MANIFEST_PATH="extension/manifest.json"
SAFARI_EXTENSION_MANIFEST_PATH="safari/Dark Light/Dark Light Extension/Resources/manifest.json"
XCODEPROJ_PATH="safari/Dark Light/Dark Light.xcodeproj/project.pbxproj"

# Ensure Homebrew/local bin is in PATH so the newer Git is used
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Read current version from manifest.json
CURRENT_VERSION="$(perl -ne 'if (/"version"\s*:\s*"([^"]+)"/) { print $1; exit }' "$MANIFEST_PATH")"

if [ -z "$CURRENT_VERSION" ]; then
    echo "Failed to read version from $MANIFEST_PATH"
    exit 1
fi

echo "==================================="
echo "Dark Light Release Wizard"
echo "==================================="
echo "Current version is: $CURRENT_VERSION"
read -p "Enter new version (or press Enter to keep $CURRENT_VERSION): " NEW_VERSION

if [ -z "$NEW_VERSION" ]; then
    NEW_VERSION=$CURRENT_VERSION
fi

echo ""
echo "Releasing version v$NEW_VERSION..."

CURRENT_BUILD_NUMBER="$(
    grep -Eo 'CURRENT_PROJECT_VERSION = [0-9]+' "$XCODEPROJ_PATH" \
        | sed -E 's/.*= ([0-9]+)/\1/' \
        | sort -nr \
        | head -n 1 \
        || true
)"
if [ -z "$CURRENT_BUILD_NUMBER" ]; then
    CURRENT_BUILD_NUMBER=0
fi
NEXT_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
echo "Incrementing Xcode build number: $CURRENT_BUILD_NUMBER -> $NEXT_BUILD_NUMBER"

# Always increment macOS app + Safari extension build number for each release
perl -i -pe "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $NEXT_BUILD_NUMBER;/g" "$XCODEPROJ_PATH"

# Update versions if changed
if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
    echo "Updating version strings..."
    # Update Chrome + Safari extension manifests
    perl -i -pe "s/\"version\"\s*:\s*\"[^\"]+\"/\"version\": \"$NEW_VERSION\"/" "$MANIFEST_PATH"
    perl -i -pe "s/\"version\"\s*:\s*\"[^\"]+\"/\"version\": \"$NEW_VERSION\"/" "$SAFARI_EXTENSION_MANIFEST_PATH"
    perl -i -pe "s/\"version\"\s*:\s*\"[^\"]+\"/\"version\": \"$NEW_VERSION\"/" "firefox/manifest.json"

    # Update macOS app + Safari extension MARKETING_VERSION in Xcode project
    perl -i -pe "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $NEW_VERSION;/g" "$XCODEPROJ_PATH"

    echo "Version updated in Chrome/Safari manifests and Xcode MARKETING_VERSION."
else
    echo "Version unchanged (build number still incremented)."
fi

FIREFOX_MANIFEST_PATH="firefox/manifest.json"

# Package Chrome extension
mkdir -p dist
echo "Cleaning up old package files..."
rm -f dist/*.zip dist/*.xpi

ZIP_NAME="dist/dark-light-chrome-v$NEW_VERSION.zip"
echo "Packaging Chrome extension to $ZIP_NAME..."
rm -f "$ZIP_NAME"
cd extension
zip -r "../$ZIP_NAME" . -x "*/.*" -x ".*" > /dev/null
cd ..
echo "Chrome extension packaged successfully."

# Package Firefox extension (same source, overlay Firefox manifest)
FIREFOX_ZIP_NAME="dist/dark-light-firefox-v$NEW_VERSION.xpi"
echo "Packaging Firefox extension to $FIREFOX_ZIP_NAME..."
rm -f "$FIREFOX_ZIP_NAME"
FIREFOX_TMP="$(mktemp -d)"
cp -r extension/. "$FIREFOX_TMP/"
# Overlay Firefox-specific manifest (adds gecko ID, replaces service_worker with scripts)
cp "$FIREFOX_MANIFEST_PATH" "$FIREFOX_TMP/manifest.json"
# Update version in Firefox manifest to match release version
perl -i -pe "s/\"version\"\s*:\s*\"[^\"]+\"/\"version\": \"$NEW_VERSION\"/" "$FIREFOX_TMP/manifest.json"
cd "$FIREFOX_TMP"
zip -r "$ROOT_DIR/$FIREFOX_ZIP_NAME" . -x "*/.*" -x ".*" > /dev/null
cd "$ROOT_DIR"
rm -rf "$FIREFOX_TMP"
echo "Firefox extension packaged successfully."

# Git commit and push
echo "Committing to git..."
git add .
git commit -m "chore: release v$NEW_VERSION" || echo "No changes to commit."

echo "Tagging v$NEW_VERSION..."
git tag -m "Release v$NEW_VERSION" "v$NEW_VERSION" || echo "Tag v$NEW_VERSION already exists."

echo "Pushing commits and tags to remote..."
git push
git push --tags

echo "Release v$NEW_VERSION completed successfully!"
