#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BarShelf"
BUNDLE_ID="com.gregagi.barshelf"
CONFIGURATION="release"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
rm -rf dist
swift build -c "$CONFIGURATION"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$BUILD_DIR/barshelf" "$MACOS_DIR/barshelf"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/$APP_NAME" "$MACOS_DIR/barshelf"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS_DIR/Info.plist" >/dev/null

echo "Built $APP_DIR"
