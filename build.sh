#!/usr/bin/env bash
# Assemble CPerch.app from a release build — a menu-bar agent (LSUIElement, no Dock icon).
# Pure SwiftPM + a hand-rolled bundle: no full Xcode required (CLT only).
# Distribute by zipping dist/CPerch.app onto a GitHub Release (unsigned for now;
# Developer-ID sign + notarize later).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="CPerch"
BUNDLE_ID="com.vedant.cperch"
VERSION="0.7.1"
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
    <key>CFBundleIconFile</key><string>AppIcon</string>
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

# App icon (Finder / About box / the DMG). Generated from assets/brand/cperch-app-icon.svg
# by assets/brand/make-icns.sh. Optional for an LSUIElement agent (no Dock icon, and the
# menu-bar glyph is drawn at runtime), so a missing file just warns rather than failing.
ICON_SRC="assets/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "${DEST}/Contents/Resources/AppIcon.icns"
  echo "▸ Bundled app icon ($ICON_SRC)"
else
  echo "  (no $ICON_SRC — skipping icon; run ./assets/brand/make-icns.sh to generate it)"
fi

echo "▸ Ad-hoc signing (so UNUserNotificationCenter + TCC work locally; Developer-ID later)…"
codesign --force --deep --sign - "$DEST" 2>/dev/null || echo "  (codesign skipped)"

echo "✓ Built ${DEST}"
echo "  Run:  open \"${DEST}\"   ·   or  \"${DEST}/Contents/MacOS/${APP_NAME}\""
