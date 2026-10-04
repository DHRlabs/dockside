#!/bin/bash
# Usage: bash Scripts/package-dmg.sh <version>
# Builds the app, then writes build/Dockside-<version>.dmg (drag-to-Applications layout).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: bash Scripts/package-dmg.sh <version>}"
DMG="build/Dockside-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

bash Scripts/build.sh "$VERSION"

cp -R build/Dockside.app "$STAGE/Dockside.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Dockside" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null

echo "Done → $(pwd)/$DMG"
