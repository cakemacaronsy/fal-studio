#!/bin/bash
# Build FAL Studio.app (Release) into build/Build/Products/Release/
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
# Stamp each build with a timestamp build number so the in-app updater can
# tell when the local build is newer than the installed copy.
BUILD_NUMBER=$(date +%Y%m%d%H%M)
xcodebuild -project FALStudio.xcodeproj -scheme FALStudio -configuration Release \
  -derivedDataPath build CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build "$@"
echo
# Record where this build lives so the in-app updater finds it even if the
# project folder moves.
mkdir -p "$HOME/Library/Application Support/FAL Studio"
echo "$(pwd)/build/Build/Products/Release/FAL Studio.app" \
  > "$HOME/Library/Application Support/FAL Studio/dev_build_path.txt"
echo "Built: $(pwd)/build/Build/Products/Release/FAL Studio.app"
