# cPerch — Daily-driver batch (v0.4 spec)

**Status:** open questions resolved (2026-06-19) — scope locked to **#7, #9, #10, #4** (#3 cut, #11
deferred). Ready to implement **on your go-ahead**.
**Date:** 2026-06-19 · **Branch target:** new `daily-driver-v0.4` off `dedup-hardening-v0.1` (latest
baseline; `main` is behind).
**Origin:** the so-agentbar gap analysis → `/idea-refine` convergence. Features that make cPerch a
daily driver, kept inside the calm/minimal, fully-local ethos.

> Per `~/.claude/CLAUDE.md` (spec-first rule): each feature with an open question was stated with its
> open questions and an evidence-backed proposed answer; the questions in §10 are now resolved.

---

## 1. Objective

Ship four quality-of-life features so cPerch is something you leave running all day:

| # | Feature | One-liner |
|---|---|---|
| **#7** | Launch at login | cPerch starts itself at login (toggle in Settings → General). |
| **#9** | Global hotkey | **⌘⌥`** toggles the roster popover (system-wide). |
| **#10** | Richer menu-bar | The bar shows a tiny needs-you count + an all-done glyph — **not** quota text. |
| **#4** | Completion / error notifications | Notify on error (on by default) and completion (opt-in), tap-to-open. |

**Cut from this batch:** **#3 exact desktop deep-link** — verified infeasible (see §7). Claude.app
exposes no conversation deep-link, the Accessibility fallback is boundary-forbidden, and the shipping
competitor (so-agentbar) also just `open -a "Claude"`. cPerch's current Jump already matches it for
desktop and beats it for terminal, so cutting #3 costs nothing.

**Deferred / explicitly out of scope:** **#11 usage & cost — entirely.** No live quota % (needs
network + the Keychain auth token → violates two hard boundaries) **and** no local token/cost
estimation for now (user deferred 2026-06-19). The boundary-safe local-cost path remains documented
in the handover for a future revisit.

---

## 2. Boundaries (unchanged — these gate every decision below)

- **Fully local. No network, ever.** Nothing here phones home.
- **Read-only on `~/.claude`.** No new read surfaces this batch (#3, which would have read
  `~/Library/Application Support/Claude`, is cut).
- **Never touch the auth token. Never request Accessibility.** Dictates the Carbon hotkey API for #9
  (§5), and was a deciding factor in cutting #3 (its only fallback was Accessibility automation).
- **`CPerchCore` stays Foundation-only.** All AppKit / ServiceManagement / Carbon glue lives in
  `CPerchApp`; the *pure decision logic* (what glyph, which banner) lives in Core and is unit-tested.
- **Calm > complete.** Defaults stay quiet: completion notifications are opt-in; the bar stays a
  dot/glyph. We add signal, not noise.

---

## 3. Commands (unchanged toolchain)

- `swift build` — compiles.
- `./scripts/test.sh` — runs swift-testing unit tests (XCTest is not in the CLT).
- `./build.sh` then `open dist/CPerch.app` — the signed bundle (needed for notifications & a real
  login item). `swift run CPerchApp --print` dumps live sessions headless.

---

## 4. #7 — Launch at login

**Decision (locked):** use **`SMAppService.mainApp`** (ServiceManagement, macOS 13+; our floor is
14). `register()` on enable, `unregister()` on disable. No login-item helper target, no deprecated
`SMLoginItemSetEnabled`.

- New pref `launchAtLogin: Bool` (default **false** — opt-in; we don't auto-enroll).
- New `LoginItem.swift` (CPerchApp) wrapping register/unregister + reading `.status`.
- Settings → General gets a **"Launch cPerch at login"** toggle (`PreferencesStore` applies on change).
- On load, reflect the *real* `SMAppService.mainApp.status`. If macOS reports `.requiresApproval`
  (user disabled it in System Settings ▸ General ▸ Login Items), show a one-line hint linking there
  rather than silently lying that it's on.

**Acceptance:** toggle on → after logout/login cPerch is running; toggle off → it isn't; the toggle
reflects external changes made in System Settings; `.requiresApproval` shows the hint.
**Testable in Core?** No (SMAppService is App-side, live-verified). Pref round-trip is unit-tested.

---

## 5. #9 — Global hotkey to toggle the popover

**Decision (locked):** register the chord with **Carbon `RegisterEventHotKey`** (in a small
`GlobalHotkey.swift`, CPerchApp). This is the deliberate choice: Carbon hotkeys are the standard way
a menu-bar agent gets a system-wide chord **without the Accessibility / Input-Monitoring TCC
permission** — which our boundaries forbid. `NSEvent.addGlobalMonitorForEvents` is rejected: global
*keyboard* monitors require Input Monitoring and can't consume the event.

- The chord calls the same toggle path as clicking the bar item (`MenuBarController.togglePopover`),
  and when it opens the popover it activates the app so the list takes key focus.
- Unregister on teardown.

**Default chord (locked 2026-06-19): ⌘⌥`** (Command-Option-Backtick). `⌘`` alone cycles an app's
windows; adding `⌥` is unbound, so there's no collision, and it's a fast top-left one-handed reach.
Customization (a recorder field) is deferred to keep the surface minimal. *(Layout note: `⌘`` is
keyboard-locale-sensitive — perfect on US/ANSI; we register the physical key **code** so it tracks the
top-left key regardless of layout.)*

**Acceptance:** pressing ⌘⌥` from any app toggles the popover; it never requires an Accessibility
prompt; quitting unregisters cleanly.
**Testable in Core?** No (Carbon glue). Behavior live-verified.

---

## 6. #10 — Richer menu-bar display (minimal)

Today the bar is a single colored dot = the aggregate most-urgent state (`AggregateState`:
needsInput / running / idle). Keep this **minimal (dot / tiny glyph only) — no quota text** (quota is
deferred with #11 anyway).

**Decision (locked):** keep the most-urgent **glyph**, and add at most two minimal embellishments,
both driven by a **pure function in Core** so the rule is unit-tested:

```
menuBarModel(aggregate, needsInputCount, allConcluded, allDoneGlyphEnabled)
  → (glyph, optionalCount)
```

1. **Needs-you count** — when **≥ 2** sessions need input, append the count next to the orange glyph
   (e.g. `🟠2`). A single one stays just the dot — one waiting agent doesn't need a number.
2. **All-done glyph** — when every session is concluded and none needs you, show the green done glyph
   (🟢). Opt-out-able via the pref shared with #4 (`showAllDoneGlyph`, default on).

No per-session emoji strip (so-agentbar's `.emoji` mode), no count-of-everything, no quota suffix.

**Decision Q10 (locked, default accepted):** needs-you count appears at **≥ 2** (calmer). It's one
constant if we ever want ≥ 1.

**Acceptance:** 0 sessions → idle/neutral glyph (or all-done glyph if just finished); 1 needs-input →
orange dot, no number; 3 needs-input → `🟠3`; everything concluded → 🟢 (unless opted out).
**Testable in Core?** **Yes** — `menuBarModel(...)` is pure; rendering stays in `MenuBarController`.

---

## 7. #3 — Exact desktop deep-link for "Jump" — ❌ CUT from v0.4

**Goal (was):** today `Jumper` for a `.desktop` session just `NSWorkspace.activate`s Claude.app — it
surfaces *whatever conversation was last open*, not the one you clicked. #3 wanted the *exact* one.

### Evidence gathered (2026-06-19, this machine)

| Question | Finding |
|---|---|
| Does a cli↔desktop session mapping exist? | **Yes.** `~/Library/Application Support/Claude/claude-code-sessions/<…>/local_<uuid>.json` — each file carries a **`cliSessionId`** field (plus `sessionId`, `cwd`, `title`, `model`, `lastActivityAt`). Verified: cli `4f82278b…` lives in `local_b0680609-37fb-4059-8a0c-53bd0399ed34.json`. |
| Does Claude.app register a URL scheme? | **Yes** — `CFBundleURLSchemes = ["claude"]` (app v1.11847.5). |
| Is there a `claude://chat/<id>` (or similar) route to open a conversation? | **No — not found.** Grepping the app bundle for `claude://…` literals returns only `claude://claude.ai/mcp-auth-callback/sdk` and `claude://cowork/shared-artifact?uuid=`. No conversation/chat/session deep-link route exists. |
| How does the shipping competitor do it? | **It doesn't.** so-agentbar's entire desktop "jump" is `open -a "Claude"` — activate the app, no targeting (`AgentStore.open`, `case .desktopCode, .desktopCowork`). For CLI sessions it opens the project *folder* in an editor. |

### Decision (locked 2026-06-19): cut #3 from v0.4

Two independent lines of evidence agree that no exact-conversation deep-link is available: the **app
bundle** (only auth-callback + cowork-artifact routes) and **so-agentbar** (a competitor that *does*
integrate with the desktop app yet still just activates it). The only remaining path — UI-scripting
the sidebar — needs **Accessibility, a hard-boundary violation.** So #3 is cut.

**No regression:** cPerch keeps its current `Jumper`, which already **matches** so-agentbar for
desktop sessions (activate Claude.app) and **beats** it for terminal sessions (focus the exact tab by
tty, vs so-agentbar opening the project folder). The mapping store (`claude-code-sessions`) stays
unread — no new read surface. Revisit only if a future Claude.app ships a conversation deep-link.

---

## 8. #4 — Completion / error notifications

Today `Notifier` fires only on a →needs-input transition (coalesced, calm). #4 adds **error** and
**completion** events, opt-in by kind, with **tap-to-open**.

### Evidence gathered (2026-06-19) — what is an "error", what is "completion"

- **Error = `isApiErrorMessage: true`.** Verified present in real transcripts (**14 records across your
  139 transcripts**). Structurally it's an `type:"assistant"` record with `isApiErrorMessage:true` **and a
  top-level `error` key** — the synthetic turn the CLI writes when the API call itself fails.
- **NOT `is_error: true`.** That appears **349×** and is just routine *tool* failures (a `grep` that
  exited non-zero, a file-not-found). Using it would make #4 cry wolf constantly. **#4 keys off
  `isApiErrorMessage` / top-level `error`, never `is_error`.**
- **Completion = the existing →`concluded` transition** (`DerivedStatus.concluded`: process gone, or last
  turn `stop_reason:"end_turn"` with nothing pending). We reuse what the merge already computes — we do
  **not** re-derive completion from scratch.

### Decisions (locked)

- **Notification kinds** with per-kind toggles in **Settings → Notifications**:
  | Kind | Default | Source |
  |---|---|---|
  | `needsInput` | **on** | existing →needsInput transition |
  | `error` | **on** | new: a session newly shows `isApiErrorMessage`/`error` in its tail |
  | `completion` | **off (opt-in)** | →concluded transition |
- **Tap-to-open:** the banner carries the `sessionId` in `userInfo`; tapping calls `Jumper.jump(to:)`.
  Terminal sessions focus the exact tab (works today). Desktop sessions activate Claude.app (#3 cut —
  no exact-conversation targeting exists).
- **All-done glyph** (shared with #10): pref `showAllDoneGlyph` (default on). This is the menu-bar
  signal that "everything you're not opted out of is done" — it is **not** a banner (calm).
- **Calm-ethos guard:** completion off-by-default keeps the daily experience quiet; error on-by-default
  is justified (a dead agent is exactly what you want to be told). Existing coalescing in
  `Notifier.banners(...)` extends to the new kinds so a burst doesn't spam.
- **Q4.1 (locked, default accepted):** fire a completion banner **per session** as each concludes
  (opt-in), *and* show the aggregate all-done glyph in the bar.
- **Q4.2 (locked, default accepted):** notify **once per error occurrence**, debounced on the record
  `requestId` — not repeatedly while the errored record sits in the tail.

### Plumbing (additive, nil/false-default — preserves the frozen contracts)

- `TranscriptReader`: read the tail for an error marker → new signal, e.g. `hadApiError: Bool`.
- `SourceRecords.TranscriptSignal` / `Models.Session`: **add** `hadApiError: Bool = false` (additive).
- `SessionMerger`: surface the flag onto the `Session` (no status change — error is orthogonal to
  running/needs-input/concluded; it's a banner trigger + optional row affordance).
- `Notifier.banners(...)`: extend the pure rules with `error` and `completion` kinds + the per-kind
  enable flags from `Preferences`; add the `UNNotificationResponse` handler for tap-to-open.
- `Preferences`: add `notify: Set<NotificationKind>` (or three Bools) + `showAllDoneGlyph: Bool`.

**Acceptance:** new `isApiErrorMessage` in a live session → one error banner (if enabled); tapping it
focuses that session; a session going →concluded with completion enabled → one completion banner; with it
disabled → none; routine `is_error` tool failures → **no** banner; all sessions done → 🟢 in the bar
(unless opted out).
**Testable in Core?** **Yes** — `banners(...)` and the error-tail parse are pure; `TranscriptReader` gets
new fixtures (`api-errored.jsonl`, `tool-error-not-api.jsonl`). Notification delivery is live-verified.

---

## 9. Project structure (files touched)

| Feature | CPerchCore (Foundation, tested) | CPerchApp (glue, live-verified) |
|---|---|---|
| #7 | `Preferences` (+`launchAtLogin`) | **`LoginItem.swift`** (new), `SettingsView` (General toggle), `PreferencesStore` |
| #9 | — | **`GlobalHotkey.swift`** (new, Carbon), `MenuBarController` |
| #10 | **`menuBarModel(...)`** (new pure fn) + tests | `MenuBarController` (render count/glyph) |
| #4 | `TranscriptReader`, `SourceRecords`, `Models`, `SessionMerger`, `Notifier.banners`, `Preferences` (+kinds, +`showAllDoneGlyph`) + tests | `Notifier` (delivery + tap handler), `SettingsView` (Notifications toggles) |

**Code style:** match the repo — small verifiable increments; pure logic in Core with swift-testing;
additive extension of frozen records (nil/false defaults); AppKit glue stays untested but
"compiles + structurally correct," live-verified per `Jumper.swift`'s precedent.

---

## 10. Open questions — RESOLVED (2026-06-19)

- [x] **Q3 (#3 deep-link):** **cut** — no deep-link route exists (app bundle + so-agentbar both confirm); Accessibility fallback forbidden.
- [x] **Q3-boundary:** moot — #3 cut, no new read surface.
- [x] **Q9 (hotkey):** **⌘⌥`** fixed; customization deferred.
- [x] **Q4.1 (completion granularity):** per-session opt-in banner + aggregate all-done glyph. *(default accepted)*
- [x] **Q4.2 (error re-fire):** once per `requestId`. *(default accepted)*
- [x] **Q10 (needs-you count):** show at ≥ 2. *(default accepted)*

## 11. Proposed build order (after go-ahead)

1. **#7 + #9** — self-contained quick wins, no Core contract changes (login item + Carbon hotkey).
   Fully disjoint files → safe to fan out in parallel.
2. **#4 + #10** — share `Preferences` (notification kinds + `showAllDoneGlyph`) and the all-done glyph;
   #10's pure `menuBarModel` lands first, then #4's plumbing builds on the shared pref.

---

## 12. Acceptance criteria (whole batch)

- All existing tests stay green; new pure logic (`menuBarModel`, error-tail parse, extended `banners`)
  is unit-tested.
- Defaults preserve the calm ethos: completion off, bar still a dot/glyph, no new prompts at first run
  except the one-time Automation prompt that already exists for terminal jumps.
- **No network. No new TCC permission** (no Accessibility, no Input Monitoring). Login item via
  SMAppService and hotkey via Carbon both honor this.
- Reads stay read-only; no new read surfaces (the only candidate, #3's mapping store, is cut).
