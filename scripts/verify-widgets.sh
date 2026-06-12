#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SunStatus"
WIDGET_NAME="SunStatusWidgetExtension"
PROJECT_PATH="$ROOT_DIR/$APP_NAME.xcodeproj"
DERIVED_DATA_DIR="$ROOT_DIR/.build/widget-verification"
CONFIGURATION="Debug"
HOST_ARCH="$(uname -m)"
WIDGET_PRODUCT_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$WIDGET_NAME.appex"
APP_PRODUCT_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
EMBEDDED_WIDGET_PATH="$APP_PRODUCT_PATH/Contents/PlugIns/$WIDGET_NAME.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

cd "$ROOT_DIR"

cleanup_registrations() {
  pluginkit -r "$WIDGET_PRODUCT_PATH" >/dev/null 2>&1 || true
  pluginkit -r "$EMBEDDED_WIDGET_PATH" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$APP_PRODUCT_PATH" >/dev/null 2>&1 || true
}

trap cleanup_registrations EXIT

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet --spec "$ROOT_DIR/project.yml"
elif [[ ! -d "$PROJECT_PATH" ]]; then
  echo "SunStatus.xcodeproj is missing and xcodegen is not installed." >&2
  exit 1
fi

xcodebuild \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$WIDGET_NAME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=$HOST_ARCH" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  build

test -d "$WIDGET_PRODUCT_PATH"
plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$WIDGET_PRODUCT_PATH/Contents/Info.plist" | grep -Fx "com.apple.widgetkit-extension" >/dev/null
codesign --verify --strict --verbose=2 "$WIDGET_PRODUCT_PATH"
codesign -d --entitlements :- "$WIDGET_PRODUCT_PATH" 2>/dev/null | grep -F "com.apple.security.app-sandbox" >/dev/null

xcodebuild \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=$HOST_ARCH" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  build

test -d "$APP_PRODUCT_PATH"
test -d "$EMBEDDED_WIDGET_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PRODUCT_PATH"

echo "Widget extension, previews, embedding, and signing verified."
