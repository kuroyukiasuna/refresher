#!/usr/bin/env bash
# Builds build/Refresher.app with SwiftPM. Works with just the Xcode Command Line Tools.
#   scripts/build-app.sh                 release build
#   CONFIG=debug scripts/build-app.sh    debug build
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Refresher"
CONFIG="${CONFIG:-release}"
BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/$APP_NAME.app"
ICON="$BUILD_DIR/AppIcon.icns"

swift build -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

# The icon only needs drawing once; delete build/AppIcon.icns to redraw it.
if [[ ! -f "$ICON" ]]; then
  mkdir -p "$BUILD_DIR"
  swiftc -O scripts/make-icon.swift -o "$BUILD_DIR/make-icon"
  rm -rf "$BUILD_DIR/AppIcon.iconset"
  "$BUILD_DIR/make-icon" "$BUILD_DIR/AppIcon.iconset"
  iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$ICON"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp "$ICON" "$APP/Contents/Resources/"
# An ad-hoc signature is enough to run locally and to register as a login item.
codesign --force --sign - "$APP"
echo "Built $APP"
