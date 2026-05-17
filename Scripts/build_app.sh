#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BarShelf"
APP_EXECUTABLE="BarShelfApp"
BUNDLE_ID="com.gregagi.barshelf"
CONFIGURATION="release"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_PNG="$ROOT_DIR/Resources/Assets/AppIcon.png"
ICONSET_DIR="$ROOT_DIR/dist/AppIcon.iconset"
ICON_ICNS="$ROOT_DIR/dist/AppIcon.icns"

cd "$ROOT_DIR"
rm -rf dist
swift build -c "$CONFIGURATION"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$APP_EXECUTABLE" "$MACOS_DIR/$APP_EXECUTABLE"
cp "$BUILD_DIR/barshelf" "$MACOS_DIR/barshelf"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/$APP_EXECUTABLE" "$MACOS_DIR/barshelf"

if [[ -f "$ICON_PNG" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
  cp "$ICON_ICNS" "$RESOURCES_DIR/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS_DIR/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_EXECUTABLE" "$CONTENTS_DIR/Info.plist" >/dev/null

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$MACOS_DIR/barshelf"
  codesign --force --timestamp --options runtime --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
elif command -v codesign >/dev/null 2>&1; then
  echo "No Developer ID signing identity configured; leaving app unsigned to avoid per-build ad-hoc cdhash changes that reset macOS privacy permissions."
fi

echo "Built $APP_DIR"
