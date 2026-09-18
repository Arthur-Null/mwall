#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REVISION="$(tr -d '\n' < "$ROOT_DIR/tools/aether/UPSTREAM_REVISION")"
SOURCE_DIR="$ROOT_DIR/.build/aether-source"
BINARY="$ROOT_DIR/.build/mwall-aether"
STAMP="$ROOT_DIR/.build/aether-build.stamp"
FINGERPRINT="$REVISION $(shasum -a 256 "$ROOT_DIR/tools/aether/cli-main.go" | cut -d ' ' -f 1) $(uname -m)"
if [[ -x "$BINARY" && -f "$STAMP" && "$(cat "$STAMP")" == "$FINGERPRINT" ]]; then
    echo "$BINARY"
    exit 0
fi
GO_BIN="${GO_BIN:-$(command -v go || true)}"
if [[ -z "$GO_BIN" && -x /usr/local/go/bin/go ]]; then GO_BIN=/usr/local/go/bin/go; fi
if [[ -z "$GO_BIN" ]]; then
    echo "Go is required to build the bundled Aether engine. Install Go, then retry." >&2
    exit 1
fi
mkdir -p "$ROOT_DIR/.build"
if [[ ! -d "$SOURCE_DIR/.git" ]]; then git init -q "$SOURCE_DIR"; fi
if ! git -C "$SOURCE_DIR" cat-file -e "$REVISION^{commit}" 2>/dev/null; then
    git -C "$SOURCE_DIR" \
      -c url.https://github.com/omacom/aether.git.insteadOf=git@github.com:omacom/aether.git \
      fetch --depth 1 git@github.com:omacom/aether.git "$REVISION"
fi
git -C "$SOURCE_DIR" checkout -q --detach "$REVISION"
git -C "$SOURCE_DIR" diff --exit-code HEAD
cp "$ROOT_DIR/tools/aether/cli-main.go" "$SOURCE_DIR/mwall_cli_main.go"
(cd "$SOURCE_DIR" && "$GO_BIN" build -trimpath -ldflags="-s -w" -o "$BINARY" mwall_cli_main.go templates.go)
printf '%s' "$FINGERPRINT" > "$STAMP"
echo "$BINARY"

