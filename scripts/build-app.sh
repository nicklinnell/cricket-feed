#!/bin/zsh
# Builds build/CricketFeed.app from the Swift package.
set -euo pipefail
cd "$(dirname "$0")/.."

ICON_SRC=assets/icon-1024.png
if [[ ! -f "$ICON_SRC" ]]; then
    echo "Missing $ICON_SRC" >&2
    exit 1
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/CricketFeed"

APP=build/CricketFeed.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CricketFeed"

# App icon: assets/icon-1024.png -> AppIcon.icns.
# Only uses tools that ship with macOS (sips, iconutil).
ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>CricketFeed</string>
    <key>CFBundleDisplayName</key><string>Cricket Feed</string>
    <key>CFBundleIdentifier</key><string>local.cricketfeed</string>
    <key>CFBundleExecutable</key><string>CricketFeed</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
