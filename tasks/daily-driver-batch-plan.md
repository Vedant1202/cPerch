# cPerch — Daily-driver batch — implementation plan

**Source spec:** [docs/specs/daily-driver-batch-v0.4.md](../docs/specs/daily-driver-batch-v0.4.md) (signed off 2026-06-19).
**Scope:** #7 launch-at-login · #9 global hotkey · #10 richer menu-bar · #4 completion/error notifications.
**Branch:** `daily-driver-v0.4` off **`dedup-hardening-v0.1`** (the latest baseline — `main` is 24
commits behind; the batch builds on the dedup / Settings / retention work, so branching off `main`
would regress it). Never commit to `main`.
**Status:** planning only — implementation begins on go-ahead.

> Boundaries (gate every task): fully local, **no network**, read-only `~/.claude`, **no new read
> surface**, never touch the auth token, **never request Accessibility / Input Monitoring**,
> `CPerchCore` stays Foundation-only, calm/minimal defaults.

---

## 1. Dependency graph (what forces the ordering)

```
            ┌─────────────────────────────────────────────┐
 Phase 0    │  CONTRACT EXTENSION (additive, nil/false)    │   shared surface every slice reads
 (prelude)  │  Preferences  · Session.hadApiError          │
            │  TranscriptSignal.hadApiError                │
            └───────────────┬─────────────────┬───────────┘
                            │                 │
        ┌───────────────────┘                 └───────────────────┐
 Phase 1│  #7 launch-at-login        ‖        #9 global hotkey     │  DISJOINT FILES → parallel
        │  (Preferences-read,                 (MenuBarController,  │
        │   LoginItem, Settings-General)       GlobalHotkey)       │
        └───────────────────┬─────────────────┬───────────────────┘
                            │                 │
        ┌───────────────────┘                 └───────────────────┐
 Phase 2│  #4 notifications          ‖        #10 menu-bar render  │  DISJOINT FILES → parallel
        │  (Notifier, TranscriptReader,       (MenuBarModel[new],  │
        │   SessionMerger, Settings-Notif)     MenuBarController)   │
        └─────────────────────────────────────────────────────────┘
```

**Why this shape:**
- **Phase 0 is the one deliberate horizontal step.** Every parallel slice reads `Preferences`; #4
  also extends the frozen `Session` / `TranscriptSignal` contracts. Doing these additive,
  nil/false-defaulted extensions up front (the same "freeze the contract first" move as
  dedup-hardening Phase 0) means the parallel agents in Phases 1–2 never touch the same shared type,
  so reconvergence is a clean file-copy.
- **#9 and #10 both edit `MenuBarController.swift`** → they must NOT be in the same parallel wave.
  Putting #9 in Phase 1 and #10 in Phase 2 makes that edit sequential (Phase 2 clones start from the
  post-Phase-1 tree, so #10 builds on #9's hotkey wiring).
- Everything else is genuinely disjoint (see file ownership per phase below).

---

## 2. Parallelization summary (the headline)

| Wave | Runs in parallel | Why safe | Must be sequential after |
|---|---|---|---|
| **Phase 0** | — (single small step) | shared contract; everyone depends on it | → gates Phases 1 & 2 |
| **Phase 1** | **#7 ‖ #9** (2 agents) | zero shared files (table §4) | after Phase 0 |
| **Phase 2** | **#4 ‖ #10** (2 agents) | zero shared files; both only *read* Phase-0 `Preferences` | after Phase 1 (shared `MenuBarController`) |

So: **two parallel fan-outs of two agents each**, bracketed by a tiny contract prelude and gated
Phase 1 → Phase 2. You can live-test on the toolbar after each phase's reconverge.

---

## 3. Fan-out mechanics (contract-first pattern, as used in prior batches)

This repo is a **subdirectory of its git root**, so worktrees are awkward → use **clean clones under
`/tmp`** (one per parallel agent), each given a **disjoint write-set** of files. Procedure per wave:

1. Commit Phase-0 (or prior phase) to `daily-driver-v0.4` so clones start from a stable tree.
2. `git clone <repo> /tmp/ddb-<feature>` per agent; each agent edits **only its owned files** (§4).
3. Reconverge: copy each agent's owned files back into the main tree (disjoint sets never collide).
4. Checkpoint in the main tree: `swift build` → `./scripts/test.sh` → `./build.sh && open dist/CPerch.app`
   for the live check. Only then start the next wave.

---

## 4. File ownership (the disjointness contract)

**Phase 0 — contract extension (one step, no fan-out):**
- `Sources/CPerchCore/Preferences.swift` — add fields + `Key` + `load`/`save` + `defaults` + init params.
- `Sources/CPerchCore/SourceRecords.swift` — `TranscriptSignal.hadApiError: Bool = false`.
- `Sources/CPerchCore/Models.swift` — `Session.hadApiError: Bool = false`.
- `Tests/CPerchCoreTests/PreferencesTests.swift` — defaults + round-trip for the new fields.

**Phase 1 — #7 ‖ #9:**

| Agent | Owns (writes) | Reads only |
|---|---|---|
| **#7 login** | `Sources/CPerchApp/LoginItem.swift` *(new)* · `Sources/CPerchApp/SettingsView.swift` (General tab) · `Sources/CPerchApp/PreferencesStore.swift` (apply) | `Preferences.launchAtLogin` |
| **#9 hotkey** | `Sources/CPerchApp/GlobalHotkey.swift` *(new)* · `Sources/CPerchApp/MenuBarController.swift` (wire) | — |

**Phase 2 — #4 ‖ #10:**

| Agent | Owns (writes) | Reads only |
|---|---|---|
| **#10 menu-bar** | `Sources/CPerchCore/MenuBarModel.swift` *(new)* · `Tests/CPerchCoreTests/MenuBarModelTests.swift` *(new)* · `Sources/CPerchApp/MenuBarController.swift` (render) | `Preferences.showAllDoneGlyph`, `AggregateState` |
| **#4 notifs** | `Sources/CPerchApp/Notifier.swift` · `Sources/CPerchApp/SettingsView.swift` (Notifications tab) · `Sources/CPerchCore/TranscriptReader.swift` · `Sources/CPerchCore/SessionMerger.swift` · `Tests/CPerchCoreTests/{TranscriptReaderTests,SessionMerger... }` · `Tests/.../Fixtures/transcripts/{api-errored,tool-error-not-api}.jsonl` *(new)* | `Preferences` kinds, `Session.hadApiError` |

> Note the only file appearing twice across the whole batch is `MenuBarController.swift` (#9 then
> #10) — and they are in different phases, so never edited concurrently.

---

## 5. Phase 0 — contract extension (prelude)

**Goal:** stabilize the shared surface so Phases 1–2 fan out cleanly. Additive only — **no behavior
change**, everything keeps compiling via defaults.

**Tasks**
1. `Preferences`: add
   - `launchAtLogin: Bool = false` (#7)
   - `notifyOnNeedsInput: Bool = true`, `notifyOnError: Bool = true`, `notifyOnCompletion: Bool = false` (#4)
   - `showAllDoneGlyph: Bool = true` (#10/#4)
   - Wire each into `Key` (`pref.launchAtLogin`, …), `load` (default-fallback), `save`, `defaults`,
     and the `init` (defaulted params so existing call sites — incl. `PreferencesTests` — compile).
2. `TranscriptSignal`: add `hadApiError: Bool = false` (last init param, defaulted).
3. `Session`: add `hadApiError: Bool = false` (last init param, defaulted) — the `Notifier`
   self-check's `session(...)` helper keeps compiling.
4. `PreferencesTests`: assert new defaults; extend the round-trip to cover the new fields.

**Acceptance / verify:** `swift build` clean; `./scripts/test.sh` green; `swift run CPerchApp --print`
unchanged output. Commit to `daily-driver-v0.4`.

---

## 6. Phase 1 — #7 ‖ #9 (parallel)

### #7 — Launch at login
**Vertical slice:** pref (Phase 0) → `LoginItem` wrapper → General toggle → applied on change.
**Tasks**
- `LoginItem.swift`: thin wrapper over `SMAppService.mainApp` — `setEnabled(_:)` →
  `register()`/`unregister()` (swallow + log errors); `isEnabled`/`status` reading
  `SMAppService.mainApp.status` (maps `.enabled`, `.requiresApproval`, `.notRegistered`).
- `PreferencesStore`: add `applyLoginItem()` (called from `didSet`, beside `applyTheme()`) →
  `LoginItem.setEnabled(preferences.launchAtLogin)`.
- `SettingsView` General tab: a **"Launch cPerch at login"** `Toggle($prefs.launchAtLogin)`; when
  `status == .requiresApproval`, show a caption hint linking to System Settings ▸ Login Items.
**Acceptance:** toggle on → bundle relaunches after logout/login; off → it doesn't; reflects external
changes; `.requiresApproval` shows the hint. **Verify:** live with `dist/CPerch.app` (note: the
registered item points at wherever the bundle lives).

### #9 — Global hotkey
**Vertical slice:** Carbon hotkey → `MenuBarController.togglePopover`.
**Tasks**
- `GlobalHotkey.swift`: `RegisterEventHotKey` for **⌘⌥`** — keycode `kVK_ANSI_Grave` (50),
  modifiers `cmdKey | optionKey`; install an `EventHandler` (`kEventClassKeyboard` /
  `kEventHotKeyPressed`) that invokes a stored callback; `UnregisterEventHotKey` on `deinit`.
  Register by **physical keycode** so it tracks the top-left key across layouts.
- `MenuBarController`: own a `GlobalHotkey` (stored prop), register in `init` with
  `{ [weak self] in self?.togglePopover() }`; ensure `togglePopover` activates the app when opening
  so the list takes key focus.
**Acceptance:** ⌘⌥` from any app toggles the popover; **no Accessibility prompt ever**; quit
unregisters cleanly. **Verify:** live — press the chord from another app.

**Phase-1 checkpoint:** reconverge → `swift build` → `./scripts/test.sh` → `./build.sh && open dist/CPerch.app`;
hand-verify both. Commit.

---

## 7. Phase 2 — #4 ‖ #10 (parallel)

### #10 — Richer menu-bar (minimal)
**Vertical slice:** pure `menuBarModel` (Core, tested) → `MenuBarController` render.
**Tasks**
- `MenuBarModel.swift` (Core, pure):
  ```
  struct MenuBarModel: Equatable { enum Glyph { case idle, running, needsInput, allDone }
                                    let glyph: Glyph; let count: Int? }
  func menuBarModel(aggregate:AggregateState, needsInputCount:Int,
                    allConcluded:Bool, allDoneGlyphEnabled:Bool) -> MenuBarModel
  ```
  Rules: `needsInput` glyph with `count = needsInputCount` **only when ≥ 2** (else `count = nil`);
  `allDone` glyph **only when** `allConcluded && allDoneGlyphEnabled` (and nothing needs input);
  else map aggregate → running/idle.
- `MenuBarModelTests.swift`: 0 sessions; 1 needsInput (dot, no count); 3 needsInput (`count==3`);
  all concluded + enabled → `.allDone`; all concluded + disabled → `.idle`; running.
- `MenuBarController.refresh()`: compute `needsInputCount` / `allConcluded` from `store.sessions`,
  call `menuBarModel(...)`, map `Glyph` → dot image (reuse `dotImage`; green check/dot for
  `.allDone`) and set `button.attributedTitle` to the count (empty when `nil`). Keep it a dot/glyph —
  no quota text.
**Acceptance:** matches the §6 spec table. **Verify:** live — drive 0/1/3 needs-input + all-done.

### #4 — Completion / error notifications
**Vertical slice:** detect error in transcript → surface on `Session` → notify by kind → tap-to-open.
**Tasks**
- `TranscriptReader`: in `read(...)`, scan the **raw tail** (like `aiTitle(in:)`) for a record with
  `isApiErrorMessage == true` **or** a top-level `error` key → set `hadApiError`. **Never** key off
  `is_error` (routine tool failures). Populate the new `TranscriptSignal.hadApiError`.
- `SessionMerger`: in the `Session(...)` build (~line 185), pass `hadApiError: sig?.hadApiError ?? false`.
- `Notifier`: evolve `banners(...)` from `[String]` to `[Banner]` (`{ text; sessionId:String?; kind }`)
  so tap-to-open has a target; add **error** (session newly `hadApiError`, debounced once per
  transcript `requestId`/uuid) and **completion** (→`concluded` transition) kinds, each gated by the
  `Preferences` toggle; update the `#if DEBUG` self-check accordingly. In `post(...)`, attach
  `userInfo["sessionId"]`; add a `UNUserNotificationCenterDelegate` handling the tap →
  `Jumper.jump(to:)` (look the session up by id; terminal focuses the tab, desktop activates Claude.app).
- `SettingsView` Notifications tab: three `Toggle`s (needs-input / error / completion) + a
  **"Show all-done glyph in menu bar"** toggle (`showAllDoneGlyph`).
- Fixtures: `api-errored.jsonl` (has `isApiErrorMessage:true`), `tool-error-not-api.jsonl` (has
  `is_error:true` only — must **not** trip the error signal); tests for both + the new banner kinds.
- *(Optional stretch)* a subtle error affordance on the roster row — would add `RosterView.swift` to
  #4's write-set (still disjoint from #10). Defer unless quick.
**Acceptance:** matches the §8 spec acceptance. **Verify:** live — induce an API error, a conclude, an
all-done; confirm tool-only `is_error` stays silent; tap focuses the right session.

**Phase-2 checkpoint:** reconverge → `swift build` → `./scripts/test.sh` → `./build.sh && open dist/CPerch.app`;
hand-verify #4 + #10. Commit.

---

## 8. Risks & notes
- **`banners` return-type change (#4)** ripples through the self-check in the same file — contained to
  `Notifier.swift`, no external caller (only `reconcile` uses it). Keep coalescing for needs-input.
- **SMAppService (#7)** on an ad-hoc-signed SPM bundle: registers by bundle id + path; the dev path
  works for testing but a moved bundle re-registers — call out in live-verify, not a blocker.
- **Hotkey collisions (#9):** ⌘⌥` is unbound by macOS; if a user app grabs it, registration just
  fails silently — acceptable for a fixed default (customization deferred).
- **No Info.plist / entitlement changes** expected: Carbon hotkeys, SMAppService, and
  `UNUserNotificationCenter` all work within the existing ad-hoc-signed bundle. Confirm at Phase-1/2
  checkpoints.
- **Contract discipline:** Phases 1–2 agents must treat Phase-0 types as read-only (no further edits
  to `Preferences`/`Session`/`TranscriptSignal`) so reconverge stays a clean copy.

---

## 9. Checkpoints (human review gates)
- **After Phase 0:** build+tests green, no behavior change. ✋ review the contract additions.
- **After Phase 1:** login toggle + hotkey live-verified. ✋ toolbar live-test.
- **After Phase 2:** notifications + menu-bar live-verified. ✋ toolbar live-test → merge to `main`.
