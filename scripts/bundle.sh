#!/usr/bin/env bash
# Wraps the SwiftPM executable in a signed .app bundle.
#
# macOS ties the camera grant to the bundle identifier AND the signature, so
# the bare binary — or an ad-hoc re-sign after every build — keeps losing it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/Capstand.app"
BIN="$ROOT/.build/$CONFIG/Capstand"
VERSION="0.1.0"

[ -x "$BIN" ] || { echo "Build first: swift build -c $CONFIG"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Capstand"
cp "$ROOT/Sources/Capstand/Resources/BricolageGrotesque.ttf" "$APP/Contents/Resources/"
# CC0 frames for the Frame menu; ImageFrame.bundled lists whatever is here.
mkdir -p "$APP/Contents/Resources/Frames"
cp "$ROOT/Assets/Frames/"*.png "$APP/Contents/Resources/Frames/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Capstand</string>
    <key>CFBundleDisplayName</key><string>Capstand</string>
    <key>CFBundleIdentifier</key><string>com.fintonlabs.capstand</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Capstand</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License - Copyright (c) fintonlabs.com</string>
    <key>NSCameraUsageDescription</key>
    <string>macOS treats a plugged-in iPhone's screen as a camera. Capstand only shows it on this Mac.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Capstand plays your iPhone's sound through this Mac while its screen is shown.</string>
</dict>
</plist>
PLIST

# Discover the Developer ID rather than hardcoding it; fall back to ad-hoc so a
# machine without the certificate still gets a runnable local build.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"

if [ -n "$IDENTITY" ]; then
    echo "Signing as: $IDENTITY"
    codesign --force --options runtime --timestamp \
             --entitlements "$ROOT/Assets/Capstand.entitlements" \
             --sign "$IDENTITY" "$APP"
else
    echo "No Developer ID found — signing ad-hoc (local use only)."
    codesign --force --sign - "$APP"
fi

codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
echo "Built $APP"
