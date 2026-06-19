# cPerch — Daily-driver batch — todo

Tracks [daily-driver-batch-plan.md](daily-driver-batch-plan.md). **✅ All phases implemented &
committed on `daily-driver-v0.4` (2026-06-19).** Build green, **133 tests** pass, bundle assembles.
Remaining boxes are the **live (on-device) checks** — those are yours to run from `dist/CPerch.app`.

## Phase 0 — contract extension ✅
- [x] `Preferences`: +`launchAtLogin`, +`notifyOnNeedsInput/Error/Completion`, +`showAllDoneGlyph`
- [x] `TranscriptSignal.hadApiError` · `Session.hadApiError` (additive, false-default)
- [x] `PreferencesTests`: new defaults + round-trip
- [x] Checkpoint: build + tests green; committed `932a499`

## Phase 1 — #7 ‖ #9 (parallel agents) ✅
### #7 launch-at-login
- [x] `LoginItem.swift` — SMAppService.mainApp register/unregister + status
- [x] `PreferencesStore.applyLoginItem()` in `didSet`
- [x] General-tab toggle + `.requiresApproval` hint
- [ ] **Live:** toggle on/off survives logout/login *(launch `dist/CPerch.app`)*

### #9 global hotkey
- [x] `GlobalHotkey.swift` — Carbon `RegisterEventHotKey` ⌘⌥` (kVK_ANSI_Grave, cmd|opt), unregister on deinit
- [x] Wired to `MenuBarController.togglePopover`; activates app on open
- [ ] **Live:** ⌘⌥` toggles from any app; **no Accessibility prompt**

- [x] Checkpoint: reconverge → build + 123 tests + bundle; committed `4ac3667`

## Phase 2 — #4 ‖ #10 (parallel agents) ✅
### #10 menu-bar
- [x] `MenuBarModel.swift` pure fn (count only at ≥2; allDone only when concluded+enabled) + 7 tests
- [x] `MenuBarController.refresh()` renders glyph + count; no quota text
- [ ] **Live:** 0 / 1 / 3 needs-input + all-done green glyph

### #4 notifications
- [x] `TranscriptReader` — detect `isApiErrorMessage`/top-level `error` (NOT `is_error`) → `hadApiError`
- [x] `SessionMerger` — surface `hadApiError` onto `Session`
- [x] `Notifier` — `banners → [Banner{text,sessionId?,kind}]`; error (once/transition) + completion kinds, per-kind gated; self-check → 12 cases
- [x] `Notifier` — tap-to-open delegate → `Jumper.jump`; `userInfo[sessionId]`
- [x] `SettingsView` Notifications — needs-input / error / completion + all-done-glyph toggles
- [x] Fixtures `api-errored.jsonl` + `tool-error-not-api.jsonl` + 3 tests
- [ ] ~~roster row error affordance~~ (stretch — deferred, kept minimal)
- [ ] **Live:** error banner, completion banner (after enabling), tap focuses session, tool-only `is_error` stays silent

- [x] Checkpoint: reconverge → build + 133 tests + bundle; committed `e611abc`
