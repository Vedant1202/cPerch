#!/usr/bin/env bash
# Assemble CPerch.app from a release build — a menu-bar agent (LSUIElement, no Dock icon).
# Pure SwiftPM + a hand-rolled bundle: no full Xcode required (CLT only).
# Distribute by zipping dist/CPerch.app onto a GitHub Release (unsigned for now;
# Developer-ID sign + notarize later).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="CPerch"
BUNDLE_ID="com.vedant.cperch"
VERSION="0.5.0"
DEST="dist/${APP_NAME}.app"

echo "▸ Building release…"
swift build -c release --product CPerchApp

BIN="$(swift build -c release --show-bin-path)/CPerchApp"
[ -x "$BIN" ] || { echo "✗ build failed: $BIN missing"; exit 1; }

echo "▸ Assembling ${DEST}…"
rm -rf "$DEST"
mkdir -p "${DEST}/Contents/MacOS" "${DEST}/Contents/Resources"
cp "$BIN" "${DEST}/Contents/MacOS/${APP_NAME}"

cat > "${DEST}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>cPerch</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>cPerch focuses the terminal tab or Claude window of the session you click — it never opens a duplicate.</string>
</dict>
</plist>
PLIST

# TODO: bundle an .icns app icon (optional for an LSUIElement agent — the menu-bar
# dot is drawn at runtime, and the app has no Dock presence).

echo "▸ Ad-hoc signing (so UNUserNotificationCenter + TCC work locally; Developer-ID later)…"
codesign --force --deep --sign - "$DEST" 2>/dev/null || echo "  (codesign skipped)"

echo "✓ Built ${DEST}"
echo "  Run:  open \"${DEST}\"   ·   or  \"${DEST}/Contents/MacOS/${APP_NAME}\""
