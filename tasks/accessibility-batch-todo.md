# cPerch — Accessibility batch (v0.5) — todo

Tracks [accessibility-batch-plan.md](accessibility-batch-plan.md) · spec
[accessibility-v0.5.md](../docs/specs/accessibility-v0.5.md). Branch `accessibility-v0.5` off
`daily-driver-v0.4`. **Not started** — awaiting go-ahead.

Legend: **‖** = parallel-agent track (own clean clone, disjoint files, reconverge by copy-back).

## Phase 0 — Foundation (SERIAL · one agent) ✅
- [x] **T0.1** `Preferences`: `A11yOverride` enum + `showStatusShapes`/`highContrast`/`reduceMotion`/`reduceTransparency` (additive, defaulted) + `effective(_:system:)`; extend `Key`/`load`/`save`
- [x] **T0.2** `StatusSymbol.swift` (new): enum + `statusSymbol(for: DerivedStatus)` + `for: MenuBarModel.Glyph` (no SF-Symbol strings)
- [x] **T0.3** `AccessibilityText.swift` (new): `accessibilityLabel(for:now:)` + `menuBarAccessibilityValue(...)`
- [x] **T0.4** `DesignTokens.swift`: semantic aliases + HC palette (§7) + `statusColor(_:highContrast:dark:)` + `symbolName(for:)` (incl. all-circle fallback flag) — additive, no call sites changed
- [x] **T0.5** Core tests: extend `PreferencesTests` (defaults + round-trip + `effective` table); new `StatusSymbolTests`, `AccessibilityTextTests`
- [x] **C0 checkpoint:** `swift build` + `./scripts/test.sh` (**141 tests**) + `./build.sh` green; app visually unchanged. Committed.

## Phase 1 — App fan-out (PARALLEL ‖ · 3 disjoint tracks) ✅ code-complete
### ‖ Track R — `RosterView.swift`
- [x] A1 `StatusDot` → `Image(systemName:)` from `symbolName(for: statusSymbol(...))` (11pt); plain dot when shapes off
- [x] A2 semantic colors at the §6 sites; "blocked" pill rebuilt (secondaryText on solid + status border)
- [x] A3 high-contrast `statusColor` via `colorSchemeContrast` env + `effective`; tints → solid in HC
- [x] A4 row = one a11y element (`children: .ignore`) + composed label; Jump as named action + labeled
- [x] A6 opaque `windowBackgroundColor` when reduce-transparency effective
- [x] Seam: added defaulted `preferences: Preferences = .defaults` param
- [ ] **AC (on-device, Phase 2):** grayscale-distinct rows · preview ≥4.5:1 · VO reads rows · HC strengthens · opt-out = plain dot · reduce-transparency opaque

### ‖ Track M — `MenuBarController.swift`
- [x] A1 bar dot → `NSImage(systemSymbolName:)` palette-tinted (13pt); plain oval when shapes off
- [x] A2 `countTitle` → `NSColor.labelColor`
- [x] A3 HC color via `…ShouldIncreaseContrast` + override + `isDarkBar`; observes `accessibilityDisplayOptionsDidChangeNotification` → `refresh()` (added init / removed deinit)
- [x] A4 bar `setAccessibilityLabel("cPerch")` + dynamic `setAccessibilityValue(menuBarAccessibilityValue(...))`
- [x] A5 `popover.animates` = !reduce-motion effective (init + refresh)
- [x] Seam: `makeRoster()` passes `preferences:`; `onChange` also calls `refresh()`
- [ ] **AC (on-device, Phase 2):** bar shows glyph · ≥2 count · VO speaks summary · HC/motion react live · opt-out = plain dot

### ‖ Track S — `SettingsView.swift`
- [x] Added **Accessibility** tab: shapes toggle + High contrast / Reduce motion / Reduce transparency (`.menu` pickers); frame height 280 → 320; caption
- [x] `PreferencesStore` untouched — `onChange` already propagates (Track M wired `onChange → refresh()`)
- [ ] **AC (on-device, Phase 2):** tab appears + binds · each control changes the live UI · values persist

- [x] **C1 checkpoint:** reconverged in-tree (disjoint files) · 2 seam fixes (arg order; module-qualified `accessibilityLabel`) · boundary audit clean (Core Foundation-only; only readable `accessibilityDisplay*` flags; no AX/network/new reads) · `swift build` + `./scripts/test.sh` (141) + `./build.sh` green. Committed.

## Phase 2 — On-device sign-off (manual · yours, from `dist/CPerch.app`)
- [ ] Symbols distinct at 9–11 pt in color **and** under a grayscale / color filter (flip to all-circle fallback if needed)
- [ ] Increase Contrast (system + tab override) strengthens UI live
- [ ] Reduce Motion / Reduce Transparency (system + tab override) take effect
- [ ] VoiceOver speaks the bar summary + each row, reaches Jump
- [ ] Sign off → merge `accessibility-v0.5`; refresh handover
</content>
