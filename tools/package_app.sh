#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/MWall.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/mwall" "$MACOS_DIR/mwall"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Resources/MWall.entitlements" "$RESOURCES_DIR/MWall.entitlements"

chmod +x "$MACOS_DIR/mwall"

if command -v codesign >/dev/null 2>&1; then
    if [ "${MWALL_SANDBOX:-0}" = "1" ]; then
        codesign --force --deep --sign - --entitlements "Resources/MWall.entitlements" "$APP_DIR"
    else
        codesign --force --deep --sign - "$APP_DIR"
    fi
fi

echo "$APP_DIR"
