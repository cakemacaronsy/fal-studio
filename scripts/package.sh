#!/bin/bash
# Package FAL Studio.app into a distributable DMG in dist/.
# The DMG contains the app, an Applications shortcut, and install notes.
# No API key is ever bundled — each user adds their own in the app's Settings.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Build/Products/Release/FAL Studio.app"
[ -d "$APP" ] || { echo "Build first: ./scripts/build.sh"; exit 1; }

VERSION=$(defaults read "$(pwd)/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
STAGE=$(mktemp -d)/FALStudio
mkdir -p "$STAGE" dist

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/READ ME FIRST.txt" <<'EOF'
FAL Studio — Install Notes
==========================

INSTALL
1. Drag "FAL Studio" onto the "Applications" shortcut.
2. FIRST LAUNCH: right-click (or Control-click) FAL Studio in Applications
   and choose "Open", then click "Open" in the dialog.
   (Needed once because this app is not notarized by Apple.)
   If macOS still blocks it, run this in Terminal:
   xattr -d com.apple.quarantine "/Applications/FAL Studio.app"

YOUR OWN API KEY (required)
This app ships with NO API key. Generations run on your own fal.ai account:
1. Create an account at https://fal.ai and add billing.
2. Go to fal.ai -> Dashboard -> Keys -> create a key.
3. In FAL Studio press Cmd+, (Settings), paste the key, click Save.
   The key is stored only in your Mac's keychain.

TRY IT FREE FIRST
Turn on "Mock mode" in Settings to explore the app with placeholder
images/videos — no account or credits needed.

COSTS
The number next to Generate (e.g. ~$0.30) is an estimate of what fal.ai
will charge YOUR account for that generation. Video is much pricier than
images — check the estimate before generating.

Your works are saved in:
~/Library/Application Support/FAL Studio/
EOF

DMG="dist/FAL-Studio-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "FAL Studio" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"
echo "Packaged: $(pwd)/$DMG"
