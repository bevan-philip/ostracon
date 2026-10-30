#!/bin/zsh
# Builds a release Ostracon.app into ./build.
# Usage: scripts/build-app.sh [--open]
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Ostracon.app"

swift build -c release --product Ostracon
BIN="$(swift build -c release --show-bin-path)/Ostracon"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ostracon"

ICONSET="$(mktemp -d)/Ostracon.iconset"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Ostracon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Ostracon</string>
    <key>CFBundleDisplayName</key><string>Ostracon</string>
    <key>CFBundleIdentifier</key><string>uk.bphilip.Ostracon</string>
    <key>CFBundleExecutable</key><string>Ostracon</string>
    <key>CFBundleIconFile</key><string>Ostracon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
