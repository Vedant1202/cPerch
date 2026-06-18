# cPerch — v0 Specification

*Status: Draft · 2026-06-18 · The build contract for v0.*
*Grounds: [docs/ideas/cperch.md](docs/ideas/cperch.md) (base camp) · [docs/intent/cperch-v0.md](docs/intent/cperch-v0.md) · [docs/design/design-tokens.md](docs/design/design-tokens.md) · validated by [spikes/session-status-scanner](spikes/session-status-scanner/README.md).*

---

## 1. Objective

A focused, minimal, **Claude-native macOS menu-bar app** — *"the Calm Conscience."* It sits as a
single Claude-colored dot in the menu bar, stays quiet while your Claude agents work, and surfaces
you only when one needs you — then one click takes you to the exact existing window where it waits.

- **User:** a developer running several logged-in Claude sessions in parallel (terminal + Claude
  desktop) who loses track of which one is waiting on them.
- **Success (v0 "done" = daily-driver reliable):** you can rely on cPerch all day for your real
  CLI + Claude-desktop sessions — correct status, calm (non-flapping) notifications, and a jump that
  lands on the exact window without duplicating it.
- **Soul:** trust through restraint — zero-permission detection, fully local, incapable of
  interfering with your sessions.

## 2. Features & Acceptance Criteria

Daily-driver bar. Each criterion is observable/testable.

- **AC1 — Detection & freshness.** Every live Claude session (CLI + desktop) appears within ~3s of
  starting; a session whose process exits (or terminal closes) flips to *concluded* within ~3s. No
  duplicates, no ghosts.
- **AC2 — Status correctness.** Actively-working → 🔵 *running*; blocked on a permission / idle
  awaiting you → 🟠 *needs-input*; finished or exited → ✅ *concluded*. Exact for recent CLI sessions
  (registry `waiting`); best-effort for the older desktop app.
- **AC3 — Aggregate dot.** The resting menu-bar dot is 🟠 iff ≥1 session needs you, else 🔵 iff ≥1
  running, else dim. Reflects **live** state only — a concluded session never turns it orange.
- **AC4 — Calm notifications.** Exactly one banner per *real* needs-input transition (no flapping),
  coalesced if several fire within a few seconds; suppressed under Focus/DND (OS-handled); new-agent
  and concluded are silent by default (opt-in toggle for new-agent).
- **AC5 — Jump (no duplicates).** Clicking a session focuses the **exact** existing terminal tab
  (Terminal/iTerm via Apple Events) or activates the Claude desktop window — never spawns a
  duplicate. Degrades to activate-the-app when the exact host can't be resolved.
- **AC6 — Roster.** Dropdown sorts needs-you-first; each row shows status dot + project name +
  latest-message preview + "blocked Nm" wait time (for needs-input).
- **AC7 — Footprint.** Zero TCC prompts for detection. Only Notification permission + per-app
  Automation (terminals) are ever requested. Idles at low CPU / modest memory.
- **AC8 — Look & feel.** Exact Claude palette + fonts per design-tokens.md; follows system
  light/dark.

## 3. Architecture & Data Model

**Layered, zero-config detection** (no hooks in v0). Three sources, merged:

| Source | Path / mechanism | Contributes |
|---|---|---|
| Process scan | `ps`/libproc + `lsof -d cwd`; `kill(pid,0)` | existence, liveness, cwd, **tty** (for jump), CPU |
| Registry | `~/.claude/sessions/<pid>.json` | `sessionId`, `pid`, `cwd`, `status` (`busy`/`shell`/`idle`/`waiting`) |
| Transcript | `~/.claude/projects/<enc-cwd>/<sessionId>.jsonl` | latest message, `stop_reason`, pending-tool, mtime |

**Dedup spine = `sessionId`.** The registry bridges `pid → sessionId`; process-scan PIDs join via that
bridge, falling back to `cwd`+recency for unregistered processes (documented limitation on collision —
§8). Records are keyed by `sessionId`; **liveness** from `kill -0`; **status** resolved by reliability
(registry `status` → transcript inference); **preview** from the transcript.

**Status derivation** (validated in the spike):
- not alive → `concluded`
- registry `busy`/`shell` → `running`; `waiting` → `needsInput`; `idle` + nothing pending → `concluded`
- no status (e.g. old desktop): pending tool fresh → `running`, stalled (>~120s) → `needsInput`;
  `end_turn` → `concluded`; else infer from last role.

**Refresh:** FSEvents watch on `~/.claude/{projects,sessions}` (0.5s debounce) + a periodic fallback
poll (~3s) that also re-runs the process scan.

**Jump resolution:** terminal host → `tty` (from process scan) → owning terminal app → Apple Events
selects that tab/window. Desktop host (no tty, kind `interactive`/`claude-desktop`) → activate
`com.anthropic.claudefordesktop` via `NSWorkspace` (no duplicate). `claude://` deep-link = spike (§9).

## 4. Project Structure

Two SPM targets — pure logic split from UI so the core is unit-testable:

```
cPerch/
├── Package.swift
├── Sources/
│   ├── CPerchCore/            # PURE: Foundation only, no AppKit/SwiftUI. The testable brain.
│   │   ├── Models.swift       #   Session, DerivedStatus, SessionSource, HostRef
│   │   ├── ProcessScanner.swift
│   │   ├── RegistryReader.swift
│   │   ├── TranscriptReader.swift
│   │   ├── SessionMerger.swift   # dedup/merge + status resolution
│   │   └── SessionStore.swift    # orchestrates sources + FSEvents/poll → [Session]
│   └── CPerchApp/             # AppKit NSStatusItem + SwiftUI dropdown; notifications; jump
│       ├── main.swift            # NSApplication + LSUIElement agent
│       ├── MenuBarController.swift
│       ├── RosterView.swift
│       ├── Notifier.swift
│       └── Jumper.swift          # Apple Events / NSWorkspace
├── Tests/CPerchCoreTests/     # fixtures/ holds captured ~/.claude JSON
├── build.sh                   # assembles CPerch.app (Info.plist, icon, sign-later)
└── spikes/…                   # archived reference
```

- `CPerchCore` imports **only Foundation** — no UI, no global state, pure functions where possible.
- Bundle id: `com.vedant.cperch` (adjust to your org). App is `LSUIElement = true` (no Dock icon).

## 5. Commands

```bash
swift build                                  # compile (CLT, no Xcode)
./scripts/test.sh                            # run unit tests (swift-testing — XCTest isn't in the CLT)
swift run CPerchApp                          # run the menu-bar app from the package
./build.sh                                   # assemble CPerch.app bundle (Info.plist + icon)
# distribute: zip CPerch.app → attach to a GitHub Release (unsigned v0; notarize later)
```

`build.sh` writes `Info.plist` with `LSUIElement=true`, `NSAppleEventsUsageDescription` (for the
terminal jump), the app icon (`iconutil`/`sips`), and bundles the `CPerchApp` binary.

## 6. Code Style

- **Swift API Design Guidelines.** Clear names, value types for models, `struct`/`enum` over classes
  unless reference semantics are needed.
- **`CPerchCore` is pure & side-effect-light** — Foundation-only, dependency-injected clock/FS where
  it aids testing, no force-unwraps (`!`) on external data.
- Concurrency: keep the scan/merge synchronous and fast; use a single `actor`/serial queue for the
  store; UI updates on the main actor.
- Small files, one responsibility each. Match the spike's readability (focused functions, table-driven
  status logic). No external dependencies in v0.

## 7. Testing Strategy

**Pragmatic: unit-test the core, verify the UI by hand.** Tests use **swift-testing** (`import Testing`),
run via **`./scripts/test.sh`** — XCTest ships only with full Xcode, so the script points the linker at
the CLT's `Testing.framework`. Package is **tools-version 6.0, language mode v5** (v6 mode later).

- **`CPerchCoreTests` (the safety net):** table-driven tests over **JSON fixtures captured from real
  `~/.claude` data**, covering:
  - status derivation — every registry status + transcript-fallback case (running / needs-input /
    concluded), incl. stalled-pending and `end_turn`.
  - merge/dedup — multi-source records → one session; stale registry entry (dead pid) → concluded;
    unregistered process via cwd fallback; **cwd-collision** degradation.
  - transcript parsing — tail read, meta-record filtering, pending-tool detection, last-message
    extraction.
- **Manual UI checklist** (menu-bar/NSStatusItem automation is low-value): dot color = correct
  aggregate; roster order + previews + wait time; one banner per needs-input (DND off) / suppressed
  (DND on); jump focuses the exact terminal tab and activates desktop **without** a duplicate.
- A `Tests/fixtures/` capture script snapshots sanitized session JSON for reproducible tests.

## 8. Boundaries

**Always**
- Keep **all data local** — nothing leaves the device, ever.
- Read-only access to `~/.claude`; never write or mutate it.
- `CPerchCore` stays UI-free and pure (testability).
- Respect macOS Focus/DND via the standard notification API (don't reimplement it).
- Stay idle-cheap (low CPU/memory — it runs all day).

**Ask first** (deferred past v0; require explicit, transparent opt-in)
- Anything that writes to `~/.claude/settings.json` (hooks / "precise mode").
- Anything requiring the Accessibility permission.
- Any network request.

**Never** (in v0)
- Make network calls; read or transmit transcript **content** off-device.
- Write to / mutate `~/.claude`.
- Request the Accessibility (“control your computer”) permission.
- Spawn a duplicate terminal window/tab or Claude window.
- Read or store the user's auth token / credentials.

## 9. Out of Scope (v0) & Open Spikes

**Out of scope:** hooks (optional "precise mode" later) · usage/quota tracking · Codex/other agents ·
Xcode/Cowork source breadth · pixel pets / system monitor / cost · two-way input (answer prompts from
the app) · App Store / sandbox.

**Spikes to run while building:**
1. Discover the `claude://` route table — if a session-targeting route exists, upgrade desktop-jump
   to exact-chat at zero permission cost.
2. Validate the dedup spine + liveness against a live multi-session machine.
3. Tune the needs-input debounce/coalesce window so notifications feel calm (no flapping).
