#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_NAME="SunStatus"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
SOURCE_FILE="$ROOT_DIR/Sources/SunStatus/main.swift"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
DEPLOYMENT_TARGET="13.0"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.discolotus.SunStatus</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>$DEPLOYMENT_TARGET</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

swiftc "$SOURCE_FILE" \
    -target arm64-apple-macos"$DEPLOYMENT_TARGET" \
    -sdk "$SDK_PATH" \
    -framework AppKit \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -o "$MACOS_DIR/$APP_NAME"

codesign --force --sign - "$APP_DIR"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Built $ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
