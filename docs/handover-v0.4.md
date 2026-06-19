# cPerch — post-v0 handover (v0.3 → v0.4)

*Picks up after [handover-v0.2.md](handover-v0.2.md). Covers everything since v0.2: the v0.3
group-by-host change, the over-counting + retention fixes, and the **v0.4 "daily-driver" batch**
(the bulk of this stream). Last updated 2026-06-19.*

## TL;DR
Since v0.2, four more things landed — first on `dedup-hardening-v0.1`, then the v0.4 batch on a new
branch **`daily-driver-v0.4`** (branched off `dedup-hardening-v0.1`, **not** `main`, which is ~26
commits behind):

1. **v0.3 — group by host** ([spec](specs/group-by-host-v0.3.md)): the roster's "group by source" now
   means **Terminal vs Claude App**, driven by the registry `entrypoint` field.
2. **Session over-counting fix** ([spec](specs/session-overcounting.md)): one conversation was showing
   as several rows. **C2** drops wrapper/parent processes (leaf-filter); **B1** collapses `--resume`
   lineage. (Residual: a multi-level resume *chain* can still linger; **B2** transcript-lineage was
   verified infeasible — forks re-stamp the sessionId.)
3. **Configurable retention** : the "keep finished sessions for" window moved from a hard-coded 3 h to a
   General-tab picker (`RetentionWindow`, `SessionStore.setRetentionWindow`).
4. **v0.4 — daily-driver batch** ([spec](specs/daily-driver-batch-v0.4.md) ·
   [plan](../tasks/daily-driver-batch-plan.md) · [todo](../tasks/daily-driver-batch-todo.md)): four
   QoL features — launch-at-login, a global hotkey, a richer menu-bar, and error/completion
   notifications.

**133 tests** (up from 108 at v0.2). Tree clean, **not pushed** (no remote). v0.4 is **code-complete
and committed but awaiting on-device sign-off** before merge to `main`.

---

## v0.4 — the daily-driver batch (the main event)

### Where it came from
A gap analysis vs **so-agentbar** + an `/idea-refine` pass produced a 6-feature wishlist. Two were
**dropped after evidence**, not guesswork:

- **#3 exact desktop deep-link — CUT.** Claude.app (v1.11847.5) registers the `claude` URL scheme but
  exposes **no conversation deep-link** — grepping the bundle finds only `…/mcp-auth-callback/sdk` and
  `…/cowork/shared-artifact?uuid=`. so-agentbar, which *does* integrate with the desktop app, also just
  `open -a "Claude"`. The only alternative (UI-scripting the sidebar) needs **Accessibility — a hard
  boundary**. So #3 is cut; cPerch's existing Jump already matches so-agentbar for desktop and beats it
  for terminal (focuses the exact tab by tty). The cli↔desktop mapping *does* exist
  (`~/Library/Application Support/Claude/claude-code-sessions/…/local_<uuid>.json` carries a
  `cliSessionId`) — kept as a note for if a future Claude.app ships a route.
- **#11 usage/cost — DEFERRED entirely.** Live quota % needs the network + the Keychain auth token
  (violates two boundaries). Local token/cost (parsing `message.usage`) is boundary-safe and verified
  feasible (this stream's transcript had `message.usage` on 100% of assistant records, full cache-tier
  breakdown), but the user deferred it for now. so-agentbar's own Claude cost path ignores cache pricing
  — cPerch can do better when it revisits.

### What shipped (feature → key implementation → where)

| # | Feature | Implementation notes |
|---|---|---|
| **#7** | **Launch at login** | `LoginItem` wraps `SMAppService.mainApp` (register/unregister/status). `PreferencesStore.applyLoginItem()` fires from the `launchAtLogin` toggle's `didSet` (so never on plain launch — the OS persists it). General-tab toggle + a `.requiresApproval` hint. → [LoginItem.swift](../Sources/CPerchApp/LoginItem.swift), [PreferencesStore.swift](../Sources/CPerchApp/PreferencesStore.swift), [SettingsView.swift](../Sources/CPerchApp/SettingsView.swift) |
| **#9** | **Global hotkey** | **⌘⌥`** via Carbon `RegisterEventHotKey` — the deliberate choice: **no TCC permission**, unlike an `NSEvent` global monitor (Input Monitoring) or Accessibility. Registered by physical key code (`kVK_ANSI_Grave`) so it tracks the top-left key across layouts. `MenuBarController` owns it → `togglePopover` (activates the app on open). → [GlobalHotkey.swift](../Sources/CPerchApp/GlobalHotkey.swift), [MenuBarController.swift](../Sources/CPerchApp/MenuBarController.swift) |
| **#10** | **Richer menu-bar** (minimal) | Pure `menuBarModel(aggregate, needsInputCount, allConcluded, allDoneGlyphEnabled) → (glyph, count?)` in CPerchCore (unit-tested). Needs-you count shown **only at ≥2**; green all-done glyph when everything's concluded and nothing needs you (gated by `showAllDoneGlyph`). No quota text. → [MenuBarModel.swift](../Sources/CPerchCore/MenuBarModel.swift), [MenuBarController.swift](../Sources/CPerchApp/MenuBarController.swift) |
| **#4** | **Error / completion notifications** | `TranscriptReader` flags `hadApiError` from the tail on **`isApiErrorMessage`/top-level `error`** — **never `is_error`** (routine tool failures; would cry wolf). Surfaced onto `Session` by `SessionMerger`. `Notifier.banners → [Banner{text, sessionId?, kind}]` (kinds: needsInput / error / completion), each gated by its pref; needs-input still **coalesces**, error **debounces** on false→true, completion fires on →concluded (**opt-in, off by default**). **Tap-to-open**: the banner's `sessionId` resolves against the last snapshot → `Jumper.jump`. → [TranscriptReader.swift](../Sources/CPerchCore/TranscriptReader.swift), [SessionMerger.swift](../Sources/CPerchCore/SessionMerger.swift), [Notifier.swift](../Sources/CPerchApp/Notifier.swift), [SettingsView.swift](../Sources/CPerchApp/SettingsView.swift) |

**Defaults stay calm:** needs-input + error **on**, completion **off**, the bar is still a dot/glyph,
launch-at-login **off**. No new TCC permission, no network, no new read surface.

### Decisions worth remembering
- **Evidence over assumption** decided #3 and #4: the `claude://` route absence (app bundle + competitor)
  and the `isApiErrorMessage`-vs-`is_error` distinction (14 vs 349 occurrences across 139 transcripts)
  were both *verified against real data* before designing.
- **Branch base:** v0.4 sits on `dedup-hardening-v0.1`, not `main` — the dedup/Settings/retention work
  isn't merged to `main` yet, so branching off `main` would have regressed it.

---

## How it was built (reusable pattern — same as v0.1/v0.2, refined)
**Contract-first parallel fan-out**, two waves of two agents:
1. **Phase 0** (sequential): extend the shared contracts **additively, nil/false-defaulted** —
   `Preferences` (+`launchAtLogin`, notification kinds, `showAllDoneGlyph`), `Session.hadApiError`,
   `TranscriptSignal.hadApiError`. Everything keeps compiling; no behavior change. This is the one
   deliberate horizontal step that lets the slices fan out cleanly.
2. **Phase 1: #7 ‖ #9** · **Phase 2: #4 ‖ #10** — each agent in a **clean `git clone` under `/tmp`**
   (this repo is a git *subdir*, so clones beat worktrees), given a **strictly disjoint file set**, each
   builds + tests in isolation. Reconverge by copying each agent's owned files back; then
   `swift build` + `./scripts/test.sh` + `./build.sh` at the phase checkpoint.
   - The ordering constraint: **#9 and #10 both touch `MenuBarController.swift`**, so they're in
     different phases (never the same wave).
   - Every reconverge was boundary-audited (CPerchCore stays Foundation-only; no forbidden APIs — the
     only `addGlobalMonitorForEvents`/`is_error` hits are doc-comments explaining what's *avoided*).

---

## What's left
**On-device sign-off (yours)** — these are the only unchecked boxes in the
[todo](../tasks/daily-driver-batch-todo.md); they can't be exercised headless. From `dist/CPerch.app`:
- **#9** — ⌘⌥` toggles the popover from any app, with **no Accessibility prompt**.
- **#10** — 1 waiting → orange dot; ≥2 → `🟠N`; all finished → green dot.
- **#4** — enable Completion in Settings → Notifications; finishing an agent banners; **tapping focuses
  the session**; a routine failing shell command does **not** banner.
- **#7** — the login toggle survives logout/login.

Then **merge `daily-driver-v0.4` → `main`** (held pending your live test).

**Deferred / future:**
- **#11 local token/cost** — boundary-safe, feasible, parked. The richer-menu-bar (#10) left room for it.
- **#3** — only if a future Claude.app exposes a conversation deep-link (the mapping store is ready).
- **Over-counting residual** — a multi-level `--resume` chain can still linger one extra row.

---

## Build / test / run
- `swift build` — compiles. `./scripts/test.sh` — **133 tests** (swift-testing; XCTest isn't in the CLT).
- `./build.sh` then `open dist/CPerch.app` — the ad-hoc-signed bundle (needed for notifications + a real
  login item). `swift run CPerchApp --print` dumps live sessions headless.
- New files this batch: `Sources/CPerchApp/{LoginItem,GlobalHotkey}.swift`,
  `Sources/CPerchCore/MenuBarModel.swift`, fixtures `Tests/fixtures/transcripts/{api-errored,tool-error-not-api}.jsonl`.

## Git
- Branch **`daily-driver-v0.4`** (off `dedup-hardening-v0.1`). Never commit to `main`. No remote yet.
- v0.4 commits: `b7029fb` docs → `932a499` Phase 0 → `4ac3667` Phase 1 (#7+#9) → `e611abc` Phase 2 (#4+#10).
- Trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
