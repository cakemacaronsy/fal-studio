#!/bin/bash
# Build, package, and publish a GitHub release so other Macs' copies of
# FAL Studio see the update (Settings → Updates → GitHub repo).
#
# One-time setup:
#   1. gh auth login
#   2. gh repo create <owner>/fal-studio --private   (or public)
#   3. In the app: Settings → General → Updates → GitHub repo = <owner>/fal-studio
#
# Usage: ./scripts/release.sh <owner>/<repo> [notes]
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${1:?usage: release.sh <owner>/<repo> [notes]}"
NOTES="${2:-}"

./scripts/build.sh
./scripts/package.sh

VERSION=$(defaults read "$(pwd)/build/Build/Products/Release/FAL Studio.app/Contents/Info" CFBundleShortVersionString)
DMG="dist/FAL-Studio-$VERSION.dmg"
TAG="v$VERSION"

gh release create "$TAG" "$DMG" \
  --repo "$REPO" \
  --title "FAL Studio $VERSION" \
  --notes "${NOTES:-FAL Studio $VERSION}" \
  --latest
echo "Released $TAG to $REPO"
