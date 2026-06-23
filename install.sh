#!/usr/bin/env bash
#
# Textract one-line installer.
#   curl -fsSL https://raw.githubusercontent.com/seanx10m/textract/main/install.sh | bash
#
set -euo pipefail

REPO_URL="https://github.com/seanx10m/textract.git"
APP_NAME="Textract"
INSTALL_DIR="$HOME/Applications"

echo "→ Installing $APP_NAME…"

# --- Prerequisites -----------------------------------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
    echo "✗ Xcode Command Line Tools are required."
    echo "  Run:  xcode-select --install   (then re-run this installer)"
    exit 1
fi
for bin in git swiftc iconutil codesign; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "✗ '$bin' not found. Install the Xcode Command Line Tools: xcode-select --install"
        exit 1
    }
done

# --- Fetch & build -----------------------------------------------------------
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "→ Fetching source…"
git clone --depth 1 "$REPO_URL" "$WORKDIR/textract" >/dev/null 2>&1

cd "$WORKDIR/textract"
echo "→ Building…"
./build.sh

# --- Install -----------------------------------------------------------------
echo "→ Installing to $INSTALL_DIR…"
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "build/$APP_NAME.app" "$INSTALL_DIR/$APP_NAME.app"

echo "→ Launching…"
open "$INSTALL_DIR/$APP_NAME.app"

cat <<'EOF'

✓ Textract installed to ~/Applications and running in your menu bar (look for the "T").

  • ⌘⇧2  capture a screen region → text on your clipboard
  • ⌘⇧1  OCR an image already on your clipboard

First capture asks for Screen Recording permission. Grant it, then quit &
reopen once so it takes effect:

    pkill -x Textract; sleep 1; open ~/Applications/Textract.app

EOF
