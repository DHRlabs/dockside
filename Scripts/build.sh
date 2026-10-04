#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Dockside.app"
BIN="Dockside"
BUNDLE_ID="com.dhrlabs.dockside"
VERSION="${1:-0.1.0}"

echo "Compiling…"
swift build -c release

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/$BIN" "$APP/Contents/MacOS/$BIN"

ICON_KEY=""
if [ -f docs/logo.png ]; then
    echo "Making app icon…"
    ICON_TMP="$(mktemp -d)"
    mkdir -p "$ICON_TMP/AppIcon.iconset" "$APP/Contents/Resources"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" docs/logo.png --out "$ICON_TMP/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" docs/logo.png --out "$ICON_TMP/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICON_TMP"
    ICON_KEY="<key>CFBundleIconFile</key>            <string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>Dockside</string>
    <key>CFBundleDisplayName</key>         <string>Dockside</string>
    <key>CFBundleExecutable</key>          <string>$BIN</string>
    $ICON_KEY
    <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>             <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>  <string>$VERSION</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSPrincipalClass</key>            <string>NSApplication</string>
</dict>
</plist>
PLIST

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ { print $2; exit }' || true)"
if [ -n "$IDENTITY" ]; then
    echo "Signing with Apple Development identity…"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "No Apple Development identity found; using ad-hoc signing…"
    codesign --force --deep --sign - "$APP"
fi

echo "Done → $(pwd)/$APP"
