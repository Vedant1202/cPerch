# cPerch v0 — Build Plan

Executes [../SPEC.md](../SPEC.md). Structured for **parallel multi-agent execution**: a contract-first
Phase 0 unblocks a wide parallel fan-out (Phase 1), which converges through integration (Phases 2–3)
into a daily-driver-reliable app (Phase 4).

## How to read this
- Tasks are grouped into **phases**. Within a phase, **⇉ PARALLEL** tasks have *no dependency on each
  other* — hand each to a separate agent. **⏸ SEQUENTIAL** phases must finish before the next starts.
- Each task lists **Depends · Deliver · Acceptance · Verify**.  🔒 = human checkpoint before proceeding.

## Dependency graph

```
P0  Scaffold + Contracts + Walking skeleton      ⏸  (blocks everything)
        │  🔒 freeze contracts
        ▼
P1  ┌──────────────────── ⇉ PARALLEL  (up to 7 agents + 1 spike) ─────────────────────┐
    │  CPerchCore:  A ProcessScanner   B RegistryReader   C TranscriptReader   G SessionMerger │
    │  CPerchApp:   D Roster+MenuBar UI (vs stub)   E Jumper   F Notifier                       │
    │  Spike:       S1 claude:// route discovery (independent, anytime)                         │
    └──────────────────────────────────────────────────────────────────────────────────────────┘
        │  🔒 all compile · core unit tests green · UI/jump/notify OK in isolation
        ▼
P2  SessionStore  (real wiring: A+B+C+G + FSEvents/poll + retention)   ⏸  deps: A,B,C,G
        │  🔒 core emits correct [Session] headless on the live machine
        ▼
P3  App integration  (real store → UI; wire E,F; build.sh → .app)      ⏸  deps: P2 + D,E,F
        │  🔒 app runs in the bar with real sessions
        ▼
P4  Hardening + daily-driver validation (S2, S3, UI checklist, footprint)  ⏸  deps: P3
        │  🔒 v0 sign-off
```

## Parallelism map (multi-agent dispatch)
- **All concurrency lives in Phase 1: 7 independent tracks (A–G) + spike S1.** They share *only* the
  frozen Phase-0 contracts (`Models`, record types, `SessionProviding`) and the test fixtures.
  - Core tracks **A, B, C, G** each own exactly one source file + one test file → no overlap.
  - App tracks **D, E, F** each own one file; **D builds against the stub store**, so it never waits on A–G.
- **Everything else is a sequential convergence.** P0 defines the shared contract — changing it later
  invalidates in-flight parallel work, which is why it ends in a 🔒 *freeze*. P2 needs the four core
  tracks; P3 needs P2 + the three app tracks; P4 needs the running app.
- **Conflict avoidance for parallel agents:** Phase-1 agents must **not** edit `Models.swift` or
  `Package.swift` (frozen in P0). If a track needs a contract change, it stops and raises it rather than
  editing shared files mid-flight.
- **Why contract-first instead of pure vertical slices:** a menu-bar app shares one core, so the only
  way to get real fan-out is to freeze the seams first. P0 ships a *walking skeleton* (a real dot driven
  by a stub) so there's a working vertical thread before the fan-out, and D builds on that stub.

---

## Phase 0 — Scaffold + Contracts + Walking skeleton  ⏸ (blocks all)

**P0**
- **Depends:** none.
- **Deliver:** `Package.swift` (targets `CPerchCore`, `CPerchApp`, `CPerchCoreTests`; macOS 14; no deps).
  `Models.swift` — `Session`, `DerivedStatus{running,needsInput,concluded}`, `SessionSource`,
  `HostRef` (terminalApp+tty | desktop bundle id); record types `ProcessRecord`, `RegistryEntry`,
  `TranscriptSignal`; `SessionProviding` protocol (publishes `[Session]` + aggregate state). A **stub
  `SessionStore`** returning 1–2 hardcoded sessions. Minimal `CPerchApp` (NSApplication `LSUIElement`
  agent + `NSStatusItem` rendering the aggregate dot from the stub). `Tests/fixtures/` + a capture
  script snapshotting **sanitized** real `~/.claude` JSON.
- **Acceptance:** `swift build` green; `swift run CPerchApp` shows a Claude-colored dot in the bar
  driven by the stub; fixtures captured; contracts documented in-file.
- **Verify:** launch → see the dot; `swift test` runs.
- 🔒 **CHECKPOINT — freeze contracts.** Human review of `Models`/record types/`SessionProviding`. All
  parallel work depends on these being stable.

## Phase 1 — Parallel fan-out  ⇉ (every task depends only on P0)

**P1-A · ProcessScanner** (CPerchCore)
- **Deliver:** scan claude processes → `[ProcessRecord{pid,ppid,tty,cwd,cpu}]`; liveness via
  `kill(pid,0)`; cwd via `lsof -d cwd`/proc; exclude desktop Electron helpers & daemons. Design with an
  **injectable process source** so tests use fixtures.
- **Acceptance:** returns live claude sessions with cwd+tty; ignores helpers. **Verify:** unit tests vs
  injected fixtures + a live spot-check against `ps`.

**P1-B · RegistryReader** (CPerchCore)
- **Deliver:** read `~/.claude/sessions/*.json` → `[RegistryEntry]`; tolerate missing `status`; parse
  kind/version/cwd/sessionId. **Acceptance:** parses the no-status desktop case + `status:"idle"` case;
  skips malformed. **Verify:** unit tests vs captured fixtures.

**P1-C · TranscriptReader** (CPerchCore)
- **Deliver:** tail-read a `.jsonl`; filter meta records; last real msg; `stop_reason`; pending tool_use;
  last assistant text; mtime. **Acceptance:** correct signals on running/needs-input/concluded fixtures
  incl. meta-noise + pending-tool. **Verify:** unit tests vs real-captured fixtures.

**P1-G · SessionMerger** (CPerchCore)
- **Deliver:** `merge([ProcessRecord],[RegistryEntry],[TranscriptSignal]) -> [Session]`; dedup by
  `sessionId`; pid→sessionId via registry bridge; cwd+recency fallback; liveness; status resolution
  (registry > transcript); preview; `blockedSince`. **Acceptance:** synthetic multi-source fixtures →
  correct unified sessions; stale-registry→concluded; unregistered-via-cwd; cwd-collision degrades
  (documented). **Verify:** table-driven unit tests.

**P1-D · Roster + MenuBar UI** (CPerchApp)
- **Deliver:** full `MenuBarController` (aggregate dot: orange/blue/dim) + SwiftUI `RosterView`
  (needs-you-first; status dot + project + preview + "blocked Nm" + jump button) styled to
  design-tokens; driven by `SessionProviding` (**stub**). **Acceptance:** AC3/AC6/AC8 — renders every
  state, light/dark. **Verify:** manual — drive the stub through states.

**P1-E · Jumper** (CPerchApp)
- **Deliver:** `jump(to: Session)` → terminal tab focus via Apple Events (Terminal/iTerm, keyed by tty);
  desktop → activate `com.anthropic.claudefordesktop` via `NSWorkspace`; **never a duplicate**; degrade
  to activate-app. **Acceptance:** AC5. **Verify:** manual on live terminals + desktop (Automation
  prompt expected).

**P1-F · Notifier** (CPerchApp)
- **Deliver:** `UNUserNotificationCenter` wrapper; request auth; fire on needsInput transition; debounce +
  coalesce; rely on OS Focus/DND; new-agent/concluded silent (opt-in toggle). **Acceptance:** AC4.
  **Verify:** manual — simulate transitions; toggle DND.

**S1 · claude:// route spike** (independent)
- **Deliver:** inspect `Claude.app` asar/JS for a session-targeting `claude://` route. If found →
  upgrade E's desktop path to exact-chat (zero permission cost). **Verify:** finding documented here.

- 🔒 **CHECKPOINT:** all targets compile; `CPerchCore` unit tests green; UI renders all states; jump &
  notify work in isolation.

## Phase 2 — SessionStore  ⏸ (deps: P1-A,B,C,G)

**P2**
- **Deliver:** orchestrate the real readers + merger; FSEvents watch on `~/.claude/{projects,sessions}`
  (0.5s debounce) + ~3s fallback poll (re-runs the process scan); publish `[Session]` via
  `SessionProviding`; concluded retention (~3h, cap ~10 most-recent); compute aggregate state. Add a
  `--print` debug mode that lists live `[Session]` (like the spike).
- **Acceptance:** AC1/AC2 — live sessions appear/vanish within ~3s; statuses correct on the real machine.
- **Verify:** run the debug print mode; compare to reality.
- 🔒 **CHECKPOINT:** core emits correct sessions headless on the live machine.

## Phase 3 — App integration  ⏸ (deps: P2 + P1-D,E,F)

**P3**
- **Deliver:** replace the stub with the real `SessionStore` in the app; wire `Notifier` to status
  transitions; wire `Jumper` to roster rows; `build.sh` assembles `CPerch.app` (Info.plist
  `LSUIElement` + `NSAppleEventsUsageDescription` + icon).
- **Acceptance:** the bar app shows real sessions, notifies on needs-input, jumps to the exact window.
- **Verify:** run the `.app`; exercise every feature against real sessions.
- 🔒 **CHECKPOINT:** app runs as a daily-driver candidate.

## Phase 4 — Hardening + daily-driver validation  ⏸ (deps: P3)

- **P4a · S2 dedup validation** on a live multi-session machine (incl. an unregistered terminal + a cwd
  collision) — confirm no ghosts/dupes.
- **P4b · S3 debounce/coalesce tuning** — notifications fire ~once per real block, no flapping.
- **P4c · Manual UI checklist** (full) + **footprint check** (idle CPU/mem); fold the S1 result if positive.
- **Acceptance:** all 8 SPEC acceptance criteria met; daily-driver reliable.
- **Verify:** use it for a real working session; checklist signed off.
- 🔒 **CHECKPOINT:** v0 sign-off.

---

## Carry-forward notes (from P1 + S1 → P2 / P3)

Discovered during the parallel build — the next phases must handle these (don't re-derive):

**Into P2 (SessionStore):**
- **Terminal-app resolution.** `SessionMerger` currently tags terminal hosts generically as
  `HostRef.terminal(app: "Terminal", tty:)`. Resolve the *actual* app (Terminal vs iTerm2) by walking
  the process `ppid` to the owning terminal, so Jumper targets the right one. (`ProcessRecord` carries
  `ppid` + `tty` for this.)
- **`blockedSince` tracking.** The merger can't know *when* a session entered needs-input from a single
  snapshot. The store must track status transitions across refreshes and stamp `blockedSince` (drives
  the roster's "blocked Nm").

**Into P3 (app integration):**
- **Wire Notifier:** call `Notifier.reconcile(previous:current:)` on each store update (it fires the
  banner only on →needs-input, coalesced). Its `#if DEBUG` self-check runs once on first init — expected.
- **Wire Jumper:** connect `RosterView.onJump` (currently a placeholder `NSLog` in `MenuBarController`)
  to `Jumper.jump(to:)`; add `NSAppleEventsUsageDescription` to the Info.plist via `build.sh`.
- **Jumper terminal fallback:** degrade-to-activate-the-app when a tty can't be resolved belongs at the
  *call site* (the `HostRef.terminal` contract has no app-bundle fallback) — resolve an app-activation
  `HostRef` upstream when tty resolution fails.
- **Exact-chat deep link (S1/P4 — resolved mapping, optional fast-follow):** `claude-code-sessions/**/local_*.json`
  maps `cliSessionId` (our id) → `sessionId` (the desktop `local_…` id). To enable: look it up, then
  `claude://chat/<id>`, and live-test the format (the `local_` prefix vs the route's UUID gate). v0 keeps
  activate-the-app.

**Process note (multi-agent):** the contract-first freeze made the 7-way fan-out conflict-free.
Worktree isolation needs the session at the git root (ours is a subdir), so clean `git clone`s were
used as manual isolation, reconverged by copying disjoint files + one integrated build. Reuse this
pattern for future fan-outs. Full rationale for all decisions lives in [`../docs/decisions.md`](../docs/decisions.md).

## Suggested multi-agent dispatch
1. One agent runs **P0** solo → stop at the freeze checkpoint for review.
2. Fan **P1** out: up to **7 agents** (A,B,C,G,D,E,F) in parallel + S1 → reconvene at the P1 checkpoint.
3. One agent runs **P2**, then **P3** (sequential) → checkpoints between.
4. **P4** hardening (can split P4a/P4b/P4c across agents; they touch different surfaces).
```
