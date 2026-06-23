#!/bin/bash
set -e

APP_NAME="Textract"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ARCH=$(uname -m)

rm -rf "$APP_BUNDLE"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Generate app icon
echo "Generating icon..."
swift scripts/create_icon.swift
iconutil -c icns "$BUILD_DIR/Textract.iconset" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$BUILD_DIR/Textract.iconset"

# Compile
echo "Compiling..."
swiftc \
    Sources/main.swift \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -framework Vision \
    -framework Carbon \
    -framework ServiceManagement \
    -target "${ARCH}-apple-macosx13.0"

# Info.plist
cp Info.plist "$APP_BUNDLE/Contents/"

# Code sign so macOS remembers Screen Recording permission. A real signing
# identity (Apple Development / Developer ID) makes the grant persist across
# rebuilds; ad-hoc works but resets the grant on each rebuild.
# Override the chosen identity with:  TEXTRACT_SIGN_ID="Apple Development: ..."
SIGN_ID="${TEXTRACT_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '"[^"]+"' | head -1 | tr -d '"')"
fi
if [ -n "$SIGN_ID" ]; then
    codesign --force --sign "$SIGN_ID" "$APP_BUNDLE"
    echo "Signed with: $SIGN_ID"
else
    echo "No code-signing identity found — using ad-hoc (Screen Recording grant resets on each rebuild)."
    codesign --force --sign - "$APP_BUNDLE"
fi

echo "Built $APP_BUNDLE"
echo "Run:  open $APP_BUNDLE"
