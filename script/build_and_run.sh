#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SunStatus"
WIDGET_NAME="SunStatusWidgetExtension"
WIDGET_BUNDLE_ID="com.discolotus.SunStatus.WidgetExtension"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/$APP_NAME.xcodeproj"
SCHEME="$APP_NAME"
CONFIGURATION="Debug"
HOST_ARCH="$(uname -m)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode-dev"
PRODUCT_APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
PRODUCT_WIDGET_PATH="$PRODUCT_APP_PATH/Contents/PlugIns/$WIDGET_NAME.appex"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_PRODUCT_BUNDLE_PATH="$ROOT_DIR/.build/release/products/$APP_NAME.app"
RELEASE_PRODUCT_WIDGET_PATH="$RELEASE_PRODUCT_BUNDLE_PATH/Contents/PlugIns/$WIDGET_NAME.appex"
INSTALL=false
VERIFY=false
APP_ARGS=()
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

for arg in "$@"; do
  case "$arg" in
    --install)
      INSTALL=true
      ;;
    --verify)
      VERIFY=true
      ;;
    *)
      APP_ARGS+=("$arg")
      ;;
  esac
done

if [[ "$INSTALL" == true ]]; then
  BUNDLE_PATH="/Applications/$APP_NAME.app"
else
  BUNDLE_PATH="$DIST_DIR/$APP_NAME.app"
fi
WIDGET_BUNDLE_PATH="$BUNDLE_PATH/Contents/PlugIns/$WIDGET_NAME.appex"
STALE_DIST_BUNDLE_PATH="$DIST_DIR/$APP_NAME.app"
STALE_DIST_WIDGET_PATH="$STALE_DIST_BUNDLE_PATH/Contents/PlugIns/$WIDGET_NAME.appex"

cd "$ROOT_DIR"

/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true

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
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=$HOST_ARCH" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  build

test -d "$PRODUCT_APP_PATH"
test -d "$PRODUCT_WIDGET_PATH"

while IFS= read -r stale_widget_path; do
  stale_app_path="${stale_widget_path%%/Contents/PlugIns/$WIDGET_NAME.appex}"
  pluginkit -r "$stale_widget_path" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$stale_app_path" >/dev/null 2>&1 || true
done < <(find "$ROOT_DIR/.build" -path "*/$APP_NAME.app/Contents/PlugIns/$WIDGET_NAME.appex" -type d 2>/dev/null)

pluginkit -r "$PRODUCT_WIDGET_PATH" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$PRODUCT_APP_PATH" >/dev/null 2>&1 || true
if [[ -d "$RELEASE_PRODUCT_BUNDLE_PATH" ]]; then
  pluginkit -r "$RELEASE_PRODUCT_WIDGET_PATH" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$RELEASE_PRODUCT_BUNDLE_PATH" >/dev/null 2>&1 || true
fi

if [[ -d "$WIDGET_BUNDLE_PATH" ]]; then
  pluginkit -r "$WIDGET_BUNDLE_PATH" >/dev/null 2>&1 || true
fi
if [[ -d "$BUNDLE_PATH" ]]; then
  "$LSREGISTER" -u "$BUNDLE_PATH" >/dev/null 2>&1 || true
fi
if [[ "$INSTALL" == true && -d "$STALE_DIST_BUNDLE_PATH" ]]; then
  pluginkit -r "$STALE_DIST_WIDGET_PATH" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$STALE_DIST_BUNDLE_PATH" >/dev/null 2>&1 || true
  rm -rf "$STALE_DIST_BUNDLE_PATH"
fi

rm -rf "$BUNDLE_PATH"
mkdir -p "$(dirname "$BUNDLE_PATH")"
COPYFILE_DISABLE=1 ditto --norsrc "$PRODUCT_APP_PATH" "$BUNDLE_PATH"
xattr -cr "$BUNDLE_PATH"

codesign --verify --deep --strict --verbose=2 "$BUNDLE_PATH"
"$LSREGISTER" -f -R -trusted "$BUNDLE_PATH" >/dev/null 2>&1 || true
pluginkit -a "$WIDGET_BUNDLE_PATH" >/dev/null 2>&1 || true
pluginkit -e use -i "$WIDGET_BUNDLE_ID" >/dev/null 2>&1 || true

if [[ ${#APP_ARGS[@]} -gt 0 ]]; then
  /usr/bin/open -n "$BUNDLE_PATH" --args "${APP_ARGS[@]}"
else
  /usr/bin/open -n "$BUNDLE_PATH"
fi

if [[ "$VERIFY" == true ]]; then
  sleep 1
  /usr/bin/pgrep -x "$APP_NAME" >/dev/null
  pluginkit -m -A -D -vvv -p com.apple.widgetkit-extension | grep -F "Path = $WIDGET_BUNDLE_PATH" >/dev/null
fi
