#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
tools/package_app.sh

APP_DIR="$ROOT_DIR/dist/MWall.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")
ARCH="$(uname -m)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

codesign --verify --deep --strict "$APP_DIR"
for executable in mwall mwall-aether; do
    test -x "$APP_DIR/Contents/MacOS/$executable"
    test "$(lipo -archs "$APP_DIR/Contents/MacOS/$executable")" = "$ARCH"
done
test -s "$APP_DIR/Contents/Resources/Aether-notice.txt"

ARCHIVE="MWall-v${VERSION}-macos-${ARCH}.zip"
# ditto preserves the app bundle and its executable permissions.
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ROOT_DIR/dist/$ARCHIVE"
(cd "$ROOT_DIR/dist" && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
echo "$ROOT_DIR/dist/$ARCHIVE"
