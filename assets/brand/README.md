# cPerch brand assets

The cPerch mark is a songbird perched on a terminal prompt (`>_`) — a nod to the Claude Code
sessions cPerch watches, which live in the terminal. The bird is a single solid silhouette with a
negative-space wing line and a cut-out eye, so it reverses cleanly to one color and holds up in
monochrome.

## Files

| File | Use |
|------|-----|
| `cperch-mark.svg` | Primary mark, ink (`#141413`) on transparent. |
| `cperch-mark-white.svg` | Reversed mark, white — for dark backgrounds. |
| `cperch-mark-orange.svg` | Mark in the brand orange (`#d97757`). |
| `cperch-lockup.svg` | Horizontal mark + `cPerch` wordmark. |
| `cperch-app-icon.svg` | Source for the macOS app icon (dark rounded square, cream bird, orange prompt). |
| `cperch-menubar-template.svg` | Simplified single-color glyph for small / template use (eye and wing dropped). |
| `make-icns.sh` | Regenerates `../AppIcon.icns` from `cperch-app-icon.svg`. |

## Palette

These match `docs/design/design-tokens.md`.

- Orange `#d97757` — needs-input / primary accent
- Blue `#6a9bcc` — running
- Green `#788c5d` — concluded
- Ink `#141413` · Cream `#faf9f5` · Mid gray `#b0aea5` · Light gray `#e8e6dc`

## Regenerating the app icon

```bash
./assets/brand/make-icns.sh      # writes assets/AppIcon.icns
```

`build.sh` copies `assets/AppIcon.icns` into the app bundle and sets `CFBundleIconFile`. The script
prefers `librsvg` (`brew install librsvg`) or `resvg` for crisp output and falls back to macOS
QuickLook (`qlmanage`) so it still works on a clean Command Line Tools box.

## Notes

- The **live menu-bar glyph is drawn at runtime** in `Sources/CPerchApp/MenuBarController.swift`
  and reflects the most-urgent session status (the shape-coded `!` / half-circle / check on a white
  plate). It is intentionally *not* this bird — these assets are the app/brand identity, not the
  status indicator. The bird could optionally become the idle/resting glyph later.
- The wordmark uses Inter as a stand-in; for distribution, convert the text to outlines or embed the
  final typeface.
- `site/og-image.png` still carries the old (green check) branding and should be regenerated to match.
