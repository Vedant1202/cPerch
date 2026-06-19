# cPerch — v0 handover

*For an agent (or human) picking up after v0. Read this first; it links to everything else.*
*Last updated 2026-06-18 · v0 complete + signed off (git `main`, 10 commits). Post-v0 dedup/merge gap analysis appended below (§Dedup & merge — gap analysis).*

## TL;DR
**cPerch** is a focused, minimal, **Claude-native macOS menu-bar app** that watches your running
Claude Code sessions: a single Claude-colored dot at rest, a dropdown roster (status · project ·
latest message · "blocked Nm"), one-click **jump** to the exact existing window (never a duplicate),
and **calm** needs-input notifications. Detection is **zero-permission** (reads `~/.claude`).
Built fresh in Swift — **not** a fork of so-agentbar. v0 is functionally complete and runs.

```bash
cd cPerch && ./build.sh && open dist/CPerch.app   # build + run the real app
./scripts/test.sh                                  # 39 tests (swift-testing)
swift run CPerchApp --print                        # headless: dump live sessions
```

## Start here (read order)
1. **This file.**
2. [SPEC.md](../SPEC.md) — the v0 contract (objective, acceptance criteria, architecture, boundaries).
3. [docs/decisions.md](decisions.md) — **D1–D11**, every decision + *why* (build-vs-fork, detection model, permissions, swift-testing/CLT, contract-first build, claude:// finding, bundle requirement).
4. [docs/ideas/cperch.md](ideas/cperch.md) — the "Calm Conscience" base camp (essence, Not-Doing list).
5. [tasks/plan.md](../tasks/plan.md) — the phased plan + **carry-forward notes** (what each phase deferred).
6. [CLAUDE.md](../CLAUDE.md) — always-loaded project context (data model, conventions).

## How it works (one screen)
**Two SPM targets.** `CPerchCore` = pure, Foundation-only, unit-tested. `CPerchApp` = AppKit
`NSStatusItem` + SwiftUI, manual-verified.

**Data flow** (`SessionStore.refresh()`):
```
ProcessScanner.scan()  ┐
RegistryReader.read()  ├─→ SessionMerger.merge() ─→ resolveTerminalApps ─→ applyBlockedSince ─→ applyRetention ─→ publish [Session]
gatherTranscripts()    ┘        (dedup by sessionId)                                                                  │ onChange
   (TranscriptReader)                                                                                                 ▼
driven by: FSEvents watch on ~/.claude/{projects,sessions} (0.5s debounce) + 3s poll        MenuBarController: dot + RosterView(popover) + Jumper + Notifier
```

**Three detection sources** (SPEC §3), merged on the `sessionId` spine:
- `ProcessScanner` — `ps`/`lsof`; live `claude` procs → existence, liveness, `tty` (for jump), cwd, cpu.
- `RegistryReader` — `~/.claude/sessions/<pid>.json` → the **pid→sessionId bridge** + Claude's own `status` (`busy`/`shell`/`idle`/`waiting`).
- `TranscriptReader` — `~/.claude/projects/<enc-cwd>/<id>.jsonl` tail → latest message, stop_reason, pending tool, mtime (status fallback when `status` is absent).

**Status resolution** (`SessionMerger.deriveStatus`): dead→`concluded`; registry `busy`/`shell`→`running`,
`waiting`→`needsInput`, `idle`→(pending tool ? `needsInput` : `concluded`); no status → transcript
heuristic (pending/stop_reason, stalled >120s). The **menu-bar dot** = `AggregateState` (most-urgent-wins).

## Files you'll touch
```
Sources/CPerchCore/   Models · SourceRecords · SessionProviding · StubSessionStore
                      ProcessScanner · RegistryReader · TranscriptReader · SessionMerger · SessionStore
Sources/CPerchApp/    main(+--print) · MenuBarController · RosterView · DesignTokens · Jumper · Notifier
Tests/CPerchCoreTests/  39 swift-testing tests · Tests/fixtures/
Package.swift · build.sh · scripts/{test.sh,capture-fixtures.sh}
```

## Gotchas the build already hit (don't re-discover these)
1. **XCTest is NOT in the Command Line Tools** (it needs full Xcode). Use **swift-testing** (`import Testing`),
   run via **`./scripts/test.sh`** — it points the linker at the CLT's `Testing.framework`. Plain
   `swift test` fails. (decisions D8)
2. **`UNUserNotificationCenter.current()` throws (uncatchable NSException) unless the app is a real,
   signed bundle.** Run as `CPerch.app` (built + ad-hoc signed by `build.sh`). `Notifier` guards on a
   bundle id so bare `swift run` / `--print` still work (notifications no-op). (decisions D11)
3. **`Package.swift` is tools-version 6.0 but language mode is pinned to v5** (avoids strict-concurrency
   churn in AppKit; adopt Swift 6 mode deliberately later).
4. **`lsof` can't map pid→transcript** (Claude appends-and-closes); the registry's `sessionId`+`cwd` is
   the mapping. The process cmdline has no `--session-id` either.
5. **Transcript tails are polluted** with meta record types (`mode`/`last-prompt`/`ai-title`/…) — filter
   to real `user`/`assistant`, drop `isSidechain`.
6. **Version skew:** the desktop app's bundled claude-code may omit the `status` field → transcript
   fallback. Don't assume `status` is always present.
7. **`SessionStore.decodeProjectDir` is lossy** for cwds whose path components contain `-` — and it's
   worse than cosmetic. The mangled cwd is a *join key* in `SessionMerger` Pass 2, so it can also drop a
   live unregistered session to `concluded` (a missed needs-input), not just show a wrong display name.
   Real fix: transcripts carry their own `cwd` field — read it. See §Dedup & merge — gap analysis (D1).

## Boundaries (hard invariants — see SPEC §8)
- **Read-only on `~/.claude`** — never write/mutate it.
- **Fully local** — no network, ever; never transmit transcript content.
- **`CPerchCore` stays pure** (Foundation-only, no AppKit/SwiftUI) so it's testable.
- **Never** request the Accessibility permission, spawn a duplicate window, or touch the user's auth token.
- **Non-sandboxed** (App Store sandbox would block `~/.claude` reads + window control).
- The Phase-0 "frozen contracts" (Models/records/`SessionProviding`) were frozen to enable the parallel
  fan-out; that freeze is **liftable now** that Phase 1 is merged — but they're widely depended on, so
  change them deliberately.

## What's done vs. what's next
**Done (v0):** detection (3 sources, deduped, zero TCC) · aggregate dot · roster · jump (exact terminal
tab via Apple Events + activate desktop) · calm DND-aware notifications · `build.sh` → ad-hoc-signed
`CPerch.app` · 39 tests · ~49 MB idle.

**Next — fast-follows (prioritized), each spec'd enough to start:**
1. **Run the manual acceptance checklist** ([docs/v0-acceptance-checklist.md](v0-acceptance-checklist.md))
   on real multi-session usage — the usage-dependent ACs (terminal jump + Automation prompt, live
   notifications, multi-session dedup) aren't verifiable headless.
2. **Exact-chat desktop deep-link** (mapping resolved): `~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json`
   maps `cliSessionId` (our id) → `sessionId` (desktop `local_…` id). Implement: look it up, then
   `open "claude://chat/<id>"`; **live-test the format** (the `local_` prefix vs the route's UUID gate).
   Wire into `Jumper` for `.desktop` hosts; keep activate-the-app as fallback. (decisions D10)
3. **Distribution:** Developer-ID sign + notarize in `build.sh`; DMG/zip → GitHub Release; maybe a
   Homebrew cask. (Currently ad-hoc signed, unsigned distribution = Gatekeeper warning.)
4. **Opt-in "precise mode" hooks** — install `Notification`/`Stop` hooks (transparent, merge-not-overwrite,
   one-click removable) for *exact* needs-input on the older desktop app. (decisions D5 — keep it opt-in;
   it touches the user's global `~/.claude/settings.json`.)
5. **Polish:** fix `decodeProjectDir` by reading the transcript's own `cwd` field (gotcha #7); trim the
   SwiftUI footprint; add an `.icns` app icon (build.sh TODO); adopt Swift 6 language mode.
6. **Breadth (deliberately out of v0):** Xcode / Desktop-Cowork session sources (so-agentbar reads these);
   the `claude-code-sessions` metadata is also a richer desktop-session source (cwd/model/activity).

## Dedup & merge — gap analysis (2026-06-18)

*Post-v0 review of the dedup/merge pipeline (`SessionMerger` + `SessionStore.gatherTranscripts`),
grounded in the source **and** this machine's live `~/.claude` (Claude CLI v2.1.170). Two real-data
findings reframe the rest:*

- **Registry files carry no `status` field** on the current CLI — real `~/.claude/sessions/<pid>.json`
  keys are `[cwd, entrypoint, kind, peerProtocol, pid, procStart, sessionId, startedAt, version]`. The
  `busy`/`waiting`/`idle` branch of `deriveStatus` is therefore **dead in practice**; every session falls
  through to the transcript heuristic + liveness. (Sharpens gotcha #6 — it's the *current* CLI, not just
  the old desktop app, that omits `status`.)
- **Transcript records carry exact `cwd`, `sessionId`, `timestamp`** — the `TranscriptReader` header
  comment ("sessionId and cwd are not carried in the transcript body") is wrong for current Claude, which
  makes the top fix (D1) a few lines.

### Findings (severity-ordered; line refs into `Sources/CPerchCore/`)

- **D1 · `decodeProjectDir` is lossy — it breaks the cwd join, not just display.** `[High]`
  `decodeProjectDir` (`"/" + split("-").joined("/")`, SessionStore.swift:160) can't tell a `/`-derived `-`
  from a literal `-`. Real dirs mis-decode: `-Users-vedant-…-claude-toolbar-mac` → `…/claude/toolbar/mac`
  (display "mac"); `…-Auto-UI-AB-Testing` → "Testing". Nearly every project here is hyphenated → pervasive.
  The mangled cwd lands in `TranscriptSignal.cwd` (SessionStore.swift:143) and is a **join key** in Pass 2
  (`$0.cwd == cwd`, SessionMerger.swift:69): a live *unregistered* session in a hyphenated dir gets `lsof`
  cwd `…/claude-toolbar-mac` vs signal cwd `…/claude/toolbar/mac` → no match → never binds → shown
  **concluded while running**, no needs-input fired. Gotcha #7 understates this.
  *Fix:* return the last record's own `cwd` from `TranscriptReader`; retire the decode (keep as fallback).

- **D2 · the merge's primary status signal is absent on the current CLI.** `[High]`
  `deriveStatus` trusts `registryStatus` first (SessionMerger.swift:114-121); real files have none → all
  hit `default:` → transcript heuristic (`:127-134`). This *amplifies* D1/D3: liveness (the pid bridge) is
  then the only thing separating `concluded` from `running`/`needsInput`. The tests/fixtures all set
  `status:"busy"/"waiting"` — a path that **doesn't run on real data**; the heuristic path that does is
  thinly tested and `stalledThreshold = 120s` is unvalidated. *Fix:* `status:nil` fixtures mirroring
  v2.1.170; broaden heuristic tests; validate 120s on real sessions.

- **D3 · pid reuse / stale registry → misattributed liveness + wrong-window jump.** `[High]`
  Pass 1 binds on any live pid found in the registry (SessionMerger.swift:53); `RegistryReader` does no
  liveness check (reads every `<pid>.json`). macOS recycles PIDs: session A (pid 4242) crashes leaving
  `4242.json`; the OS reassigns 4242 to another genuine-claude proc (e.g. `claude -p …`, kept by
  `isGenuineClaudeSession`) that doesn't re-register → A shown alive, host resolved from 4242's *new* tty →
  **jump focuses the wrong tab**. *Fix:* the registry already carries `procStart`/`startedAt` (the DTO
  drops them) — capture the live process start time (extra `ps` column) and bind only if it matches
  `procStart`. Interim: skip the bind when `p.cwd` ≠ `entry.cwd`.

- **D4 · exact-string cwd matching is brittle** (beyond D1). `[Med]` No normalization at
  SessionMerger.swift:69: trailing slash, case, dot-encoding (`.`→`-`?), symlink physical-vs-logical
  (`lsof` resolves). *Fix:* normalize both sides (`standardizedFileURL.resolvingSymlinksInPath`, strip
  trailing `/`); prefer joining on `sessionId` over cwd.

- **D5 · `registryById` tie-break is lexical, not recency/liveness.** `[Med]` On a duplicate `sessionId`
  the `uniquingKeysWith:{_,new in new}` (SessionMerger.swift:40) over `names.sorted()`
  (RegistryReader.swift:43) keeps the lexicographically-last *filename* → arbitrary; the `Session` then
  uses its possibly-stale cwd/kind. Comments calling it "more recently captured" mislead. *Fix:* prefer the
  live-pid entry, else newest `startedAt`.

- **D6 · `lastActivity` uses file mtime, not the record `timestamp`.** `[Med]`
  TranscriptReader.swift:52,142 uses `contentModificationDate`; records carry a precise `timestamp`. mtime
  is bumpable by Spotlight/backup/editor and drives stalled-threshold + sort + retention. *Fix:* parse the
  last record's `timestamp`; mtime only as fallback.

- **D7 · Pass 2 N:N pairing is arbitrary.** `[Low]` The "newest-process-first" comment
  (SessionMerger.swift:61-63) isn't implemented (`unregistered` is ps-order; no start time captured).
  `procStart` (D3) enables deterministic pairing.

- **D8 · startup race.** `[Low]` Process-only sessions are invisible until a registry/transcript lands —
  `allIds` is registry+transcript keys only (SessionMerger.swift:76). Known limitation.

- **D9 · future double-listing (desktop deep-link).** `[Med, forward-looking]` When the desktop source
  lands (fast-follow #2) the same conversation exists under a CLI `sessionId` and a desktop `local_…` id →
  lists **twice**. The spine needs a `cliSessionId ↔ desktop sessionId` alias before that ships.

- **D10 · dead code / test-reality gap.** `[trivia]` `transcriptsById`'s `uniquingKeysWith`
  (SessionMerger.swift:38) never collides (`gatherTranscripts` dedups by sessionId upstream).

### What's solid (calibration)
Universe = `Set` of `sessionId` ⇒ the roster *structurally cannot* show an id twice. Pass 2's sequential
mutation + inner re-check correctly stop two processes claiming one transcript. Registry-wins layering in
`gatherTranscripts` and skip-malformed readers are the right instincts.

### Suggested fix order
| # | Fix | Severity | Effort |
|---|-----|----------|--------|
| D1 | Read transcript's own `cwd`; retire lossy decode | High | Low |
| D3 | Validate pid bridge via `procStart` (cwd cross-check interim) | High | Med |
| D2 | `status:nil` fixtures + validate `stalledThreshold` | High | Low–Med |
| D6 | Use record `timestamp` for `lastActivity` | Med | Low |
| D4/D5 | Normalize cwd; tie-break registry by liveness/`startedAt` | Med | Low |
| D9 | Design `sessionId`-alias map before the desktop source | Med | — |

**Status (2026-06-18):** D1/D2/D3 **shipped** on branch `dedup-hardening-v0.1`
([spec](specs/dedup-hardening-v0.1.md)) — verified live (`--print`: hyphenated project names now render
correctly; the PID-reuse guard and status-heuristic coverage are in). Three more findings then surfaced
from **live toolbar testing**:

- **L1 · status: "waiting on you" vs "done".** `[High]` A live session that ended its turn on an assistant
  `end_turn` shows `concluded`/"all quiet" even when the agent asked *you* a question — `deriveStatus` maps
  every `end_turn` → concluded (SessionMerger.swift:130-134). The headline status-accuracy gap (CLAUDE.md's
  "hardest open problem").
- **L2 · same-project rows are visually identical.** `[Med]` Two `claude-toolbar-mac` rows (correct dedup of
  two real sessions) can't be told apart — `displayName` is only the cwd basename; the long-intended AI title
  (Models.swift "or AI-generated title") was never built, though `ai-title` records exist in the transcript.
- **L3 · missing message preview.** `[Low]` `latestMessage` is nil when the transcript tail has no assistant
  text block.

**Update (2026-06-18): v0.2 shipped.** L1, L2, L3, D4, D5, D6, D9 are all implemented on
`dedup-hardening-v0.1` (spec [roster-and-merge-quality-v0.2.md](specs/roster-and-merge-quality-v0.2.md),
plan [tasks/roster-merge-quality-plan.md](../tasks/roster-merge-quality-plan.md)) — **108 tests**, built
via the same contract-first 3-track fan-out (M/T/U). Live-verified: AI titles (L2) extract correctly
(37/37 ai-titled transcripts keep their title within the 256 KB tail — no tail-window gap); D6's
record-`timestamp` activity gives sharper retention than mtime. L1's word-boundary `looksLikeAwaitingUser`
is unit-tested (a live `end_turn`+question wasn't forced — tune the phrase set on real data if false
positives/negatives surface). **Deferred:** L1 opt-in `Stop`/`Notification` hooks (Phase 4 — writes
`~/.claude/settings.json`, needs explicit go-ahead). Still open: **D7** (Pass-2 N:N pairing), **D8**
(startup race), **D10** (dead defensive code / test-reality gap).

## Verifying any change
`swift build` green · **`./scripts/test.sh`** green (add tests for new `CPerchCore` logic — it's pure
and easy to test) · `swift run CPerchApp --print` matches reality on your machine · `./build.sh && open
dist/CPerch.app` launches clean. UI/jump/notify are manual (the checklist).

## If you fan out work to parallel agents
The v0 build used a **contract-first** pattern: freeze shared types, give each agent a disjoint file
set, reconverge with one integrated build. Worktree isolation needs the *session* at the git root
(this repo is a subdir of the session cwd) — so **clean `git clone`s into temp dirs** were used as
manual isolation, reconverged by copying disjoint files. Reuse that. (decisions D9)

## Git
Branch `main`, 10 commits, clean. Phase commits: initial → spec/plan → P0 → P1 (7 parallel tracks) →
S1 → decisions → P2 → P3 → P4 → v0 sign-off. No remote yet.
