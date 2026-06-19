# cPerch — Roster & merge quality (v0.2): implementation plan

*Phased, dependency-ordered plan for [docs/specs/roster-and-merge-quality-v0.2.md](../docs/specs/roster-and-merge-quality-v0.2.md)
(L1, L2, L3, D4, D5, D6, D9). Checklist: [roster-merge-quality-todo.md](roster-merge-quality-todo.md).
Builds on branch `dedup-hardening-v0.1` (v0.1 D1/D2/D3 shipped; baseline **79 tests**).*

- **Locked decisions:** L1 = conservative heuristic now (+ opt-in hooks **deferred** to Phase 4);
  L2 = AI titles as the display name (basename fallback) + collision label.
- **ACs** live in the spec (§4). **Phase 4 (L1 hooks installer) is DEFERRED** — it writes
  `~/.claude/settings.json`, so it needs separate authorization; this run builds Phases 0–3 only.
- **Naming:** `roster-merge-quality-*` files; the v0.1 `dedup-hardening-*` and v0 `tasks/*.md` are untouched.

---

## 1. Dependency graph

```
Phase 0 · Contract + fixtures  ──────────────────────────────  SERIAL (blocking)
  0.1 SourceRecords: + TranscriptSignal.aiTitle: String?  (init param = nil)
  0.2 Fixtures: ai-titled.jsonl (an `ai-title` record) · timestamped.jsonl (records with `timestamp`)
  0.3 Contract test (extend SourceRecordsTests): aiTitle defaults nil + round-trips
        │  ◇ C0: swift build + 79 tests green · additive-only
        ▼
Phase 1 · Implementation  ───────────────────────────────────  PARALLEL (disjoint files)
  ├─ Track T · TranscriptReader.swift   D6 (record timestamp) · L2-extract (ai-title) · L3 (preview fallback)
  ├─ Track M · SessionMerger.swift      L1 (looksLikeAwaitingUser + deriveStatus) · D4 · D5 · D9 · L2 displayName
  └─ Track U · RosterView.swift + new CPerchCore/RosterDisambiguation.swift   L2 collision label · L3 render
        │  ◇ C1 per track: builds + own suites green on C0
        ▼
Phase 2 · Integration  ──────────────────────────────────────  SERIAL
  2.1 Reconverge (disjoint copy) → one swift build + full ./scripts/test.sh
        │  ◇ C2: whole suite green, no new warnings
        ▼
Phase 3 · Validate + commit  ────────────────────────────────  SERIAL · manual
  3.1 Rebuild app + swift run --print + live toolbar (AC-L1/L2 judgment; validate looksLikeAwaitingUser)
  3.2 Per-track commits (T → M → U) + handover note
        │  ◇ C3 (DoD)
        ▼
Phase 4 · L1 opt-in hooks installer  ────────────────────────  DEFERRED (separate authorization; writes settings.json)
```

## 2. Parallelization

| Phase | Mode | Agents | Why |
|---|---|---|---|
| 0 | Serial (blocking) | 1 | Shared `aiTitle` contract + fixtures |
| **1** | **Parallel** | **3** (T, M, U) | Disjoint files; each a vertical slice with its own new suite |
| 2 | Serial | 1 | One reconvergence build |
| 3 | Serial (manual) | 1 + human | Live `--print`/toolbar judgment |
| 4 | **Deferred** | — | Hooks write `~/.claude/settings.json` → needs explicit go-ahead |

### File-ownership matrix (disjointness proof)

| File | P0 | T | M | U |
|---|:--:|:--:|:--:|:--:|
| `CPerchCore/SourceRecords.swift` | ✎ | | | |
| `CPerchCore/TranscriptReader.swift` | | ✎ | | |
| `CPerchCore/SessionMerger.swift` | | | ✎ | |
| `CPerchApp/RosterView.swift` | | | | ✎ |
| `CPerchCore/RosterDisambiguation.swift` *(new)* | | | | ✎ |
| `…/TranscriptReaderTests.swift` | | ✎ | | |
| `…/SessionMerger+QualityTests.swift` *(new)* | | | ✎ | |
| `…/RosterDisambiguationTests.swift` *(new)* | | | | ✎ |
| `…/SourceRecordsTests.swift` | ✎ | | | |
| `Tests/fixtures/transcripts/*` | ✎ | ·read· | | |

No file written by two tracks. The existing `SessionMergerTests.swift` and the v0.1
`SessionMerger+{Join,Reuse,Status}Tests.swift` are **not touched**. New merger tests go in
`SessionMerger+QualityTests.swift` (M-owned).

**Cross-track via contract:** M's `displayName = sig.aiTitle ?? basename` compiles against the Phase-0
`aiTitle` field; T populates it; U's helper operates on `[Session].displayName`. All independent given C0.

---

## 3. Phase 0 — Contract + fixtures  *(serial)*

- **0.1** `SourceRecords.swift`: add `public let aiTitle: String?` to `TranscriptSignal`, init param
  `aiTitle: String? = nil` (additive — existing construction sites compile). — *enables L2*
- **0.2** Fixtures under `Tests/fixtures/transcripts/`:
  - `ai-titled.jsonl` — real/assistant records **plus** an `{"type":"ai-title","title":"My Cool Title", …}`
    meta record (shape per the meta types TranscriptReader already lists).
  - `timestamped.jsonl` — records carrying `"timestamp":"2026-06-18T20:29:53.698Z"` (for D6).
- **0.3** Extend `SourceRecordsTests.swift`: `TranscriptSignal(...)` legacy init compiles + `aiTitle` defaults
  nil; round-trips when supplied.
- ◇ **C0:** `swift build` + `./scripts/test.sh` green (**79** + new contract tests) · additive-only.

## 4. Phase 1 — Implementation  *(parallel T ∥ M ∥ U)*

### Track T · TranscriptReader  *(M-size)* — owns `TranscriptReader.swift`, `TranscriptReaderTests.swift`
- **D6** — parse the last real record's `timestamp` (ISO-8601) → `lastActivity`; mtime fallback. Pure
  `static func parseTimestamp(_:) -> Date?`. *(AC-D6.1/.2/.3)*
- **L2-extract** — scan for the `ai-title` meta record (currently filtered) → `TranscriptSignal.aiTitle`.
  *(AC-L2.1/.2)*
- **L3** — preview fallback when no assistant text: last user text → `Running <tool>…` if a tool pends →
  nil last. *(AC-L3.1/.2)*

### Track M · SessionMerger  *(L-size — start first)* — owns `SessionMerger.swift`, new `SessionMerger+QualityTests.swift`
- **L1** — pure `static func looksLikeAwaitingUser(_ text: String?) -> Bool` (ends-with-`?` + small curated
  permission set); in `deriveStatus`, alive + `end_turn`/`stop_sequence`/`max_tokens` + awaiting → `needsInput`,
  else `concluded`. Bias to few false positives. *(AC-L1.1–.4)*
- **L2 displayName** — `displayName = sig?.aiTitle ?? displayName(for: cwd)`. *(supports AC-L2.x)*
- **D4** — `static func normalizedPath(_:) -> String` (resolveSymlinks/standardize/strip trailing `/`); use
  on both sides of the Pass-2 cwd compare. *(AC-D4.1–.3)*
- **D5** — `registryById` collision → prefer live-pid entry, else newest `startedAt`; fix comments. *(AC-D5.1/.2)*
- **D9** — `static func canonicalSessionId(_:aliases:) -> String` applied before `allIds`; default empty
  aliases = no behavior change. *(AC-D9.1/.2)*

### Track U · Roster display  *(S-size)* — owns `RosterView.swift`, new `CPerchCore/RosterDisambiguation.swift` + `RosterDisambiguationTests.swift`
- **L2 collision** — pure `disambiguationLabels(for: [Session], now:) -> [Session.ID: String]` (CPerchCore):
  for any displayName shared by ≥2 sessions, emit a muted secondary (relative time by default). RosterView
  renders it under the name. *(AC-L2.3)*
- **L3 render** — ensure a nil/empty preview degrades gracefully (RosterView already hides empties; add a
  faint placeholder only if needed).

> ◇ **C1 (per track):** the track builds and its own new suite passes on the C0 baseline.

## 5. Phase 2 — Integration  *(serial)*
- **2.1** Reconverge T/M/U (disjoint copy) → one `swift build` + full `./scripts/test.sh`. Confirm M's
  `deriveStatus` change doesn't break the v0.1 status/heuristic suites (it narrows end_turn only for
  awaiting-text; existing tests use non-question text → still concluded).
- ◇ **C2:** whole suite green; no new warnings.

## 6. Phase 3 — Validate + commit  *(serial · manual)*
- **3.1** `./build.sh` + relaunch + `swift run CPerchApp --print`: does this session now read `needsInput`
  when it ends on a question? do same-project rows disambiguate? do AI-titled sessions show titles?
  Validate `looksLikeAwaitingUser` against real transcripts (tune the curated set if needed).
- **3.2** Commit per track (T → M → U) on `dedup-hardening-v0.1`; append live results to the handover.
- ◇ **C3 (DoD):** build + tests green · `--print`/toolbar correct · `~/.claude` read-only · no new perms ·
  79 v0.1 tests intact.

## 7. Phase 4 — L1 opt-in hooks  *(DEFERRED)*
Install merge-not-overwrite `Stop`/`Notification` hooks → exact `needsInput`. **Writes
`~/.claude/settings.json`** (the one sanctioned write), so it needs explicit go-ahead and is out of this
autonomous run. Spec'd in v0.2 §4/L1 (hooks phase).

## 8. Agent fan-out playbook
Same as v0.1: land C0, then fan out **Track M first** (long pole) + T + U as **isolated `git clone`s into
`/tmp/cperch-{t,m,u}`** (this repo is a subdir of the git root → worktrees awkward). Reconverge by copying
each track's disjoint files; integrated build + per-track commit. Brief each agent with the spec, its track
section, and its exact file list; new tests in its named new suite (never the existing `SessionMergerTests`).

## 9. Risks & watch-items
- **L1 false positives** — keep `looksLikeAwaitingUser` conservative; validate on real transcripts (Phase 3).
- **D6 timestamp parsing** — ISO-8601 with/without fractional secs & offset; pure-test it; mtime fallback.
- **L2 ai-title shape** — confirm the real `ai-title` record's field name (`title`?) against a live
  transcript in Phase 0/3; tolerate absence.
- **Track U testability** — keep collision logic in the **pure CPerchCore helper**, not the SwiftUI view.
- **deriveStatus narrowing** — only `end_turn`+awaiting flips to needsInput; ensure v0.1 D2 suite (non-question
  end_turn) stays concluded.
