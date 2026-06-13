#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$("$ROOT_DIR/scripts/resolve-release-version.sh" "${1:-}")"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_NAME="SunStatus"
WIDGET_NAME="SunStatusWidgetExtension"
PROJECT_PATH="$ROOT_DIR/$APP_NAME.xcodeproj"
SCHEME="$APP_NAME"
HOST_ARCH="$(uname -m)"
DERIVED_DATA_DIR="$BUILD_DIR/xcode-derived-data"
PRODUCTS_DIR="$BUILD_DIR/products"
APP_DIR="$PRODUCTS_DIR/$APP_NAME.app"
WIDGET_DIR="$APP_DIR/Contents/PlugIns/$WIDGET_NAME.appex"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
DMG_STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$ROOT_DIR"

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --quiet --spec "$ROOT_DIR/project.yml"
elif [[ ! -d "$PROJECT_PATH" ]]; then
    echo "SunStatus.xcodeproj is missing and xcodegen is not installed." >&2
    exit 1
fi

xcodebuild \
    -quiet \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=macOS,arch=$HOST_ARCH" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CONFIGURATION_BUILD_DIR="$PRODUCTS_DIR" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    build

test -d "$APP_DIR"
test -d "$WIDGET_DIR"
test -f "$APP_DIR/Contents/Resources/AppIcon.icns"

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

while IFS= read -r stale_widget_path; do
    stale_app_path="${stale_widget_path%%/Contents/PlugIns/$WIDGET_NAME.appex}"
    pluginkit -r "$stale_widget_path" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$stale_app_path" >/dev/null 2>&1 || true
done < <(find "$ROOT_DIR/.build" -path "*/$APP_NAME.app/Contents/PlugIns/$WIDGET_NAME.appex" -type d 2>/dev/null)
