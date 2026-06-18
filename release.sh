#!/bin/bash
set -e

# Ensure Homebrew/local bin is in PATH so the newer Git is used
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Read current version from manifest.json
CURRENT_VERSION=$(grep '"version"' extension/manifest.json | sed -E 's/.*"([^"]+)".*/\1/')

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

# Update versions if changed
if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
    echo "Updating version strings..."
    # Update manifest.json
    sed -i '' "s/\"version\": \"$CURRENT_VERSION\"/\"version\": \"$NEW_VERSION\"/g" extension/manifest.json
    echo "Version updated in manifest.json."
else
    echo "Version unchanged."
fi

# Package extension
mkdir -p dist
ZIP_NAME="dist/dark-light-v$NEW_VERSION.zip"
echo "Packaging extension to $ZIP_NAME..."
rm -f "$ZIP_NAME"
cd extension
zip -r "../$ZIP_NAME" . -x "*/.*" -x ".*" > /dev/null
cd ..
echo "Extension packaged successfully."

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
