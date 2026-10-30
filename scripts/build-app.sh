#!/bin/zsh
# Builds a release Ostracon.app into ./build.
# Usage: scripts/build-app.sh [--open]
# VERSION and BUILD_NUMBER set the bundle's version (default 1.0 and 1).
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Ostracon.app"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

swift build -c release --product Ostracon
swift build -c release --product ostracon-mcp
swift build -c release --product ostracon-cli
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Ostracon"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ostracon"

# SwiftPM records the deployment target (15.0) as the SDK version, which makes macOS 26+ run the app in its
# compatibility appearance, without Liquid Glass. Record the SDK it was really built with.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
vtool -set-build-version macos 15.0 "$SDK_VERSION" -replace \
    -output "$APP/Contents/MacOS/Ostracon.tmp" "$APP/Contents/MacOS/Ostracon" 2>/dev/null
mv "$APP/Contents/MacOS/Ostracon.tmp" "$APP/Contents/MacOS/Ostracon"

# The MCP server and CLI ship inside the app, so installing Ostracon installs them too.
cp "$BIN_DIR/ostracon-mcp" "$APP/Contents/MacOS/ostracon-mcp"
cp "$BIN_DIR/ostracon-cli" "$APP/Contents/MacOS/ostracon-cli"

ICONSET="$(mktemp -d)/Ostracon.iconset"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Ostracon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
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
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>uk.bphilip.ostracon.tasks</string>
            <key>UTTypeDescription</key><string>Ostracon Tasks</string>
            <key>UTTypeConformsTo</key><array><string>public.data</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP/Contents/MacOS/ostracon-mcp"
codesign --force --sign - "$APP/Contents/MacOS/ostracon-cli"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
