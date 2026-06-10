#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SunStatus"
BUNDLE_ID="com.discolotus.SunStatus"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_PATH="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$BUNDLE_PATH/Contents/MacOS/$APP_NAME"
VERIFY=false
APP_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --verify)
      VERIFY=true
      ;;
    *)
      APP_ARGS+=("$arg")
      ;;
  esac
done

cd "$ROOT_DIR"

/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true

swift build

rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH/Contents/MacOS"

cp ".build/debug/$APP_NAME" "$EXECUTABLE_PATH"
chmod +x "$EXECUTABLE_PATH"

cat > "$BUNDLE_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>SunStatus uses your location to center the sun map and calculate local sun position.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ ${#APP_ARGS[@]} -gt 0 ]]; then
  /usr/bin/open -n "$BUNDLE_PATH" --args "${APP_ARGS[@]}"
else
  /usr/bin/open -n "$BUNDLE_PATH"
fi

if [[ "$VERIFY" == true ]]; then
  sleep 1
  /usr/bin/pgrep -x "$APP_NAME" >/dev/null
fi
