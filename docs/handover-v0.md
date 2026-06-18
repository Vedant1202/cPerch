# cPerch — v0 handover

*For an agent (or human) picking up after v0. Read this first; it links to everything else.*
*Last updated 2026-06-18 · v0 complete + signed off (git `main`, 10 commits, tree clean).*

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
7. **`SessionStore.decodeProjectDir` is lossy** for cwds whose path components contain `-` (only affects
   unregistered concluded sessions' display names). Fix is noted below.

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
