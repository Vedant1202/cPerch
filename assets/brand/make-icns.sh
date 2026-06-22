#!/usr/bin/env bash
# Generate assets/AppIcon.icns from assets/brand/cperch-app-icon.svg.
# Prefers librsvg/resvg for crisp output; falls back to macOS QuickLook (qlmanage)
# so it works on a clean Command Line Tools box with no extra installs.
#   brew install librsvg   # optional, for best quality
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root (cPerch/)

SRC="assets/brand/cperch-app-icon.svg"
OUT="assets/AppIcon.icns"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MASTER="$TMP/master.png"

echo "▸ Rasterizing $SRC → 1024² master…"
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 1024 -h 1024 "$SRC" -o "$MASTER"
elif command -v resvg >/dev/null 2>&1; then
  resvg -w 1024 -h 1024 "$SRC" "$MASTER"
else
  echo "  (no librsvg/resvg — using QuickLook; brew install librsvg for sharper output)"
  qlmanage -t -s 1024 -o "$TMP" "$SRC" >/dev/null 2>&1 || true
  mv "$TMP/$(basename "$SRC").png" "$MASTER"
fi

echo "▸ Building iconset…"
ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
            128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 \
            512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
  px="${spec%%:*}"; name="${spec##*:}"
  sips -z "$px" "$px" "$MASTER" --out "$ICONSET/$name.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "✓ Wrote $OUT"
