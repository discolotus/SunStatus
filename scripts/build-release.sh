#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.4.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_NAME="SunStatus"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
SWIFTPM_BUILD_DIR="$BUILD_DIR/swiftpm"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
DMG_STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
DEPLOYMENT_TARGET="14.0"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR" "$ICONSET_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
    <key>NSLocationUsageDescription</key>
    <string>SunStatus uses your location locally to center the 3D sun map and estimate daylight timing for where you are.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>SunStatus uses your location locally to center the 3D sun map and estimate daylight timing for where you are.</string>
</dict>
</plist>
PLIST

swift build \
    --configuration release \
    --product "$APP_NAME" \
    --build-path "$SWIFTPM_BUILD_DIR" \
    -Xswiftc -module-cache-path \
    -Xswiftc "$MODULE_CACHE_DIR"

cp "$SWIFTPM_BUILD_DIR/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
python3 "$ROOT_DIR/scripts/make-icns.py" "$ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns"

xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc "$APP_DIR" "$ZIP_PATH"
xattr -cr "$APP_DIR"
xattr -dr com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -dr 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true

mkdir -p "$DMG_STAGING_DIR"
COPYFILE_DISABLE=1 ditto --norsrc "$APP_DIR" "$DMG_STAGING_DIR/$APP_NAME.app"
xattr -cr "$DMG_STAGING_DIR/$APP_NAME.app"
xattr -dr com.apple.FinderInfo "$DMG_STAGING_DIR/$APP_NAME.app" 2>/dev/null || true
xattr -dr 'com.apple.fileprovider.fpfs#P' "$DMG_STAGING_DIR/$APP_NAME.app" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$DMG_STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if unzip -Z1 "$ZIP_PATH" | grep -Eq '(^|/)\._'; then
    echo "Release archive contains AppleDouble metadata files." >&2
    exit 1
fi

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$ZIP_PATH" -d "$VERIFY_DIR"
codesign --verify --deep --strict --verbose=2 "$VERIFY_DIR/$APP_NAME.app"

DMG_MOUNT_POINT="$VERIFY_DIR/dmg"
mkdir -p "$DMG_MOUNT_POINT"
hdiutil attach "$DMG_PATH" -mountpoint "$DMG_MOUNT_POINT" -nobrowse -readonly
trap 'hdiutil detach "$DMG_MOUNT_POINT" >/dev/null 2>&1 || true; rm -rf "$VERIFY_DIR"' EXIT
test -d "$DMG_MOUNT_POINT/$APP_NAME.app"
test -L "$DMG_MOUNT_POINT/Applications"
mounted_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DMG_MOUNT_POINT/$APP_NAME.app/Contents/Info.plist")"
if [[ "$mounted_version" != "$VERSION" ]]; then
    echo "DMG app version mismatch: expected $VERSION, got $mounted_version" >&2
    exit 1
fi
DMG_EXTRACT_DIR="$VERIFY_DIR/dmg-extract"
mkdir -p "$DMG_EXTRACT_DIR"
COPYFILE_DISABLE=1 ditto --norsrc "$DMG_MOUNT_POINT/$APP_NAME.app" "$DMG_EXTRACT_DIR/$APP_NAME.app"
xattr -cr "$DMG_EXTRACT_DIR/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$DMG_EXTRACT_DIR/$APP_NAME.app"
hdiutil detach "$DMG_MOUNT_POINT"
rm -rf "$VERIFY_DIR"
trap - EXIT

echo "Built $ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
echo "Built $DMG_PATH"
shasum -a 256 "$DMG_PATH"
