# cPerch — In-app Help (v0.6) — todo

Tracks [help-menu-plan.md](help-menu-plan.md) · spec [help-menu-v0.6.md](../docs/specs/help-menu-v0.6.md).
Branch `help-menu-v0.6` off `main`. **Not started** — awaiting go-ahead.

## Phase 0 — Foundation (serial) ✅
- [x] **T0.1** `Preferences`: add `hasSeenHelpHint: Bool` (default false) + `Key`/`load`/`save`/`init`
- [x] **T0.2** `Diagnostics.swift` (new): `diagnosticsText(appVersion:osVersion:)` → "cPerch <v>\nmacOS <os>" (no identifiers)
- [x] **T0.3** Core tests: extend `PreferencesTests` (default + round-trip); new `DiagnosticsTests`
- [x] **T0.4** `build.sh`: `VERSION` `0.0.1` → `0.5.0`
- [x] **C0 checkpoint:** `swift build` + `./scripts/test.sh` (**143 tests**) + `./build.sh` green; bundle `CFBundleShortVersionString` = 0.5.0; app unchanged. Committed.

## Phase 1 — UI (serial)
- [ ] **T1.1** `HelpView.swift` (new): 7 sections; legend via real symbols; Open Settings; Privacy + issue links (`NSWorkspace.open` + `arrow.up.right`); Copy diagnostics (`NSPasteboard` + `diagnosticsText` + bundle version); About (version + MIT); back control
- [ ] **T1.2** `RosterView.swift`: footer `questionmark.circle` button; `@State showingHelp` switch → render `HelpView`; `showHelpHint` param + auto-dismiss TTL callout near the "?"
- [ ] **T1.3** `MenuBarController.swift`: first-popover-open hint trigger + persist `hasSeenHelpHint`; `makeRoster` passes `showHelpHint`
- [ ] **C1 checkpoint:** `swift build` + `./scripts/test.sh` + `./build.sh` green; boundary audit (Core Foundation-only; no network; only `NSWorkspace.open`/`NSPasteboard`; no new TCC permission / `~/.claude` reads). Commit.

## Phase 2 — On-device sign-off (manual, from `dist/CPerch.app`)
- [ ] "?" opens Help; back returns; list state preserved; content scrolls
- [ ] All seven sections render; legend matches the live symbols
- [ ] Privacy + Report-an-issue links open in the browser with the external-link icon (issue → chooser)
- [ ] Copy diagnostics → `cPerch 0.5.0` + macOS version on the clipboard (no identifiers)
- [ ] First-run hint shows once near the "?", auto-dismisses, never returns after relaunch
- [ ] About shows `0.5.0`
- [ ] Sign off → merge `help-menu-v0.6`; refresh handover
</content>
