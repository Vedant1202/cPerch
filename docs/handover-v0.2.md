# cPerch — post-v0 handover (v0.1 + v0.2)

*Picks up after [handover-v0.md](handover-v0.md). Covers the two post-v0 work streams, both on branch
`dedup-hardening-v0.1`. Last updated 2026-06-18.*

## TL;DR
After v0 shipped, a dedup/merge **gap analysis** (handover-v0.md §"Dedup & merge — gap analysis") found
ten issues, **D1–D10**. Two batches were specced → planned → built, each via a **contract-first 3-track
parallel fan-out** (isolated `git clone`s, disjoint files, reconverge), landing on `dedup-hardening-v0.1`:

- **v0.1 — D1/D2/D3** ([spec](specs/dedup-hardening-v0.1.md)): transcript-owned cwd (fixes mangled names +
  a missed-liveness join bug), status-heuristic test coverage, **PID-reuse guard** (no wrong-window jump).
- **v0.2 — L1/L2/L3 + D4/D5/D6/D9** ([spec](specs/roster-and-merge-quality-v0.2.md)): waiting-vs-done
  status, AI-title naming + same-project disambiguation, preview fallback, cwd normalization, registry
  tie-break, record-`timestamp` activity, desktop alias seam. (L1–L3 surfaced from live toolbar testing.)

**108 tests** (up from 79). Tree clean, **not pushed** (no remote yet).

## What shipped (finding → change → where)
| ID | Change | Key symbol |
|----|--------|-----------|
| D1 | Read the transcript's own `cwd`; retire lossy `decodeProjectDir` from the join | `TranscriptReader.recordCwd` |
| D2 | Tests for the `status:nil` transcript heuristic (the path that actually runs) | `SessionMerger+StatusTests` |
| D3 | Gate the pid→sessionId bind on a start-time match (PID reuse → drop bind) | `SessionMerger.bindIsTrustworthy`, `pidReuseTolerance` |
| L1 | `end_turn`+question → `needsInput` (else `concluded`); word-boundary phrase match | `SessionMerger.looksLikeAwaitingUser` |
| L2 | `displayName = aiTitle ?? basename`; collision label for same-named rows | `TranscriptReader.aiTitle`, `RosterDisambiguation.labels` |
| L3 | Preview fallback: assistant → user → `Running <tool>…` → nil | `TranscriptReader.previewText` |
| D4 | Normalize both cwds before the Pass-2 join (symlink / trailing slash) | `SessionMerger.normalizedPath` |
| D5 | Registry tie-break: live pid, else newest `startedAt` (not lexical filename) | `SessionMerger.preferRegistryEntry` |
| D6 | `lastActivity` from the record's `timestamp` (mtime fallback) | `TranscriptReader.parseTimestamp` |
| D9 | `aliases` param + `canonicalSessionId` seam (default empty = no-op) | `SessionMerger.canonicalSessionId` |

Contract additions (all additive, nil-defaulted): `ProcessRecord.startTime`, `RegistryEntry.startedAt`,
`TranscriptSignal.aiTitle`.

## How it was built (reusable pattern)
1. **Spec** (`docs/specs/*.md`) with ACs + locked design decisions → **plan + todo** (`tasks/*.md`).
2. **Phase 0 (serial):** extend the frozen records **additively** (optional, nil-default) so all tracks
   compile against one baseline; stage fixtures; contract test. Checkpoint **C0**.
3. **Phase 1 (parallel):** one **agent per disjoint file** (TranscriptReader / SessionMerger / RosterView),
   each in a fresh `git clone` under `/tmp`, each running the TDD build cycle; new tests go in per-concern
   suite files (never the shared `SessionMergerTests.swift`).
4. **Phase 2 (serial):** reconverge by copying disjoint files; **review each production diff**; per-track
   `swift build` + `./scripts/test.sh` + commit. Checkpoint **C2**.
5. **Phase 3 (manual):** `./build.sh` + relaunch + `swift run CPerchApp --print` / toolbar verification.

*Why isolated clones, not worktrees:* this repo is a **subdir** of the git/session root, so harness
worktree isolation is awkward — clean clones + copy-back is the reliable substitute.

## What's left
- **Phase 4 — L1 opt-in hooks** (DEFERRED; needs explicit go-ahead): install merge-not-overwrite
  `Stop`/`Notification` hooks for *exact* needs-input. **Writes `~/.claude/settings.json`** — the single
  sanctioned write (one-click removable). Spec'd in v0.2 §4/L1.
- **D7** (Pass-2 N:N pairing is arbitrary for multiple unregistered same-dir procs), **D8** (startup race:
  a process-only session is invisible until its registry/transcript lands), **D10** (dead defensive code /
  status-fixture-vs-reality). Lower severity — see handover-v0.md gap analysis.
- **L1 tuning:** validate `looksLikeAwaitingUser`'s phrase set on real transcripts; adjust if false +/-.
- **UI work (done this session):** (1) responsive **roster max-height + scroll** (`0e2eef6`) — the list
  caps at ~60% of the active screen's visible height and scrolls. (2) a **Settings window** (gear in the
  roster footer; commits "Settings 1/3–3/3"): General (Theme System/Light/Dark via `NSApp.appearance`;
  Session list = Simple list / collapsible **Group-by-source**) + Notifications (DND system / notify-anyway
  / silent; life timed-`N`s / persisted). Pure `Preferences` (UserDefaults) + `SessionGrouping` live in
  CPerchCore (tested, **116 tests**); `PreferencesStore` / `SettingsView` / `SettingsWindowController` +
  `Notifier` wiring in CPerchApp.
  - *macOS caveats:* "Notify anyway" sets `.timeSensitive` — truly overriding Focus/DND needs the
    time-sensitive **entitlement** (best-effort without it). "Timed" auto-clears the notification from
    Notification Center after `N`s; the on-screen **banner** duration is macOS's to decide.
  - *Not yet visually click-tested* by the agent (build + 116 tests green; relaunched) — verify the gear →
    window, theme/view switches, and grouped collapse on the live toolbar.

## Build / test / run
```bash
cd cPerch
swift build · ./scripts/test.sh · swift run CPerchApp --print
./build.sh && open dist/CPerch.app        # the real bundle (ad-hoc signed; needed for notifications)
```

## Git
Branch `dedup-hardening-v0.1` — v0.1 (D1/D3/D2 + docs) then v0.2 (Phase 0 + M/T/U + docs). Clean working
tree. No remote (push when one's added). Per-finding commits; each one's body lists its ACs + test count.
