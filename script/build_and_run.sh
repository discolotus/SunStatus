#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SunStatus"
BUNDLE_ID="com.discolotus.SunStatus"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_PATH="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$BUNDLE_PATH/Contents/MacOS/$APP_NAME"
RESOURCES_PATH="$BUNDLE_PATH/Contents/Resources"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.png"
ICONSET_PATH="$DIST_DIR/AppIcon.iconset"
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
rm -rf "$ICONSET_PATH"
mkdir -p "$BUNDLE_PATH/Contents/MacOS" "$RESOURCES_PATH" "$ICONSET_PATH"

cp ".build/debug/$APP_NAME" "$EXECUTABLE_PATH"
chmod +x "$EXECUTABLE_PATH"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_512x512@2x.png" >/dev/null
python3 "$ROOT_DIR/scripts/make-icns.py" "$ICONSET_PATH" "$RESOURCES_PATH/AppIcon.icns"

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSLocationUsageDescription</key>
  <string>SunStatus uses your location locally to center the 3D sun map and estimate daylight timing for where you are.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>SunStatus uses your location locally to center the 3D sun map and estimate daylight timing for where you are.</string>
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
