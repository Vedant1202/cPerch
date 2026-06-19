# cPerch — Roster & merge quality (v0.2): task list

*Checklist for [roster-merge-quality-plan.md](roster-merge-quality-plan.md) · spec
[../docs/specs/roster-and-merge-quality-v0.2.md](../docs/specs/roster-and-merge-quality-v0.2.md).
`⇄` = parallelizable. Baseline: 79 tests on `dedup-hardening-v0.1`.*

### Phase 0 · Contract + fixtures — SERIAL (blocking) ✓
- [x] **0.1** `SourceRecords.swift`: `TranscriptSignal.aiTitle: String?` (init `= nil`, additive). — *L2*
- [x] **0.2** Fixtures: `transcripts/ai-titled.jsonl` (`ai-title` record; field is **`aiTitle`**) + `transcripts/timestamped.jsonl` (records with `timestamp`).
- [x] **0.3** Extended `SourceRecordsTests`: aiTitle defaults nil + round-trips (RED→GREEN seen).
- [x] ◇ **C0:** `swift build` + `./scripts/test.sh` green (**81** = 79 + 2) · additive-only. ✓

### Phase 1 · Implementation — PARALLEL ⇄ (3 isolated-clone agents; disjoint files) ✓

**⇄ Track M · SessionMerger** — commit `5f2da1d`
- [x] **M-L1** `looksLikeAwaitingUser` (trailing `?` + curated phrases, **word-boundary** matched after integration review so "confirmed"/"should investigate" don't nag) + deriveStatus end_turn arm. — AC-L1.1–.4
- [x] **M-L2** `displayName = sig?.aiTitle ?? displayName(for: cwd)`.
- [x] **M-D4** `normalizedPath` (symlink/standardize/trailing-slash) on both Pass-2 sides. — AC-D4.1–.3
- [x] **M-D5** `preferRegistryEntry`: live-pid, else newest `startedAt`. — AC-D5.1/.2
- [x] **M-D9** `canonicalSessionId` + `aliases:` param (default empty = no-op). — AC-D9.1/.2
- [x] ◇ **C1-M** 95 tests green in clone.

**⇄ Track T · TranscriptReader** — commit `52a42d2`
- [x] **T-D6** `lastActivity` from last record `timestamp` (two ISO-8601 formatters; mtime fallback). — AC-D6.1/.2/.3
- [x] **T-L2** `aiTitle` from the raw tail's `ai-title` record (field `aiTitle`, last wins). — AC-L2.1/.2
- [x] **T-L3** `previewText` fallback: assistant → user → `Running <tool>…` → nil. — AC-L3.1/.2
- [x] ◇ **C1-T** 89 tests green in clone.

**⇄ Track U · Roster display** — commit `8c4267e`
- [x] **U-L2** pure `RosterDisambiguation.labels(for:now:)` (relative time + short-id tiebreak) + RosterView secondary label. — AC-L2.3
- [x] **U-L3** RosterView hides empty previews (Track T supplies upstream fallback); no placeholder needed.
- [x] ◇ **C1-U** 86 tests green in clone.

### Phase 2 · Integration — SERIAL ✓
- [x] **2.1** Reconverged M/T/U (disjoint copy, per-track review + commit). Integration-review fix: word-boundary phrase matching in L1.
- [x] ◇ **C2:** **108 tests in 12 suites** green; build clean, no warnings.

### Phase 3 · Validate + commit — SERIAL · manual ✓
- [x] **3.1** Rebuilt + relaunched v0.2 binary; `--print` on real `~/.claude`. **L2 verified**: 37/37 ai-titled transcripts keep their title within the 256KB tail (no tail-window gap); the current untitled session correctly shows its basename. **D6 visible**: sharper retention (record-timestamp activity drops stale sessions mtime would have kept). **L1**: unit-tested (a live end_turn+question wasn't forced).
- [x] **3.2** Per-track commits (M→T→U) on `dedup-hardening-v0.1` + handover note.
- [x] ◇ **C3 (DoD):** build+tests green ✓ · `--print` correct ✓ · `~/.claude` read-only ✓ · no new perms ✓ · 79 v0.1 tests intact (108 total) ✓.

### Phase 4 · L1 opt-in hooks — DEFERRED
- [ ] **(deferred)** Stop/Notification hooks installer — writes `~/.claude/settings.json`; needs explicit go-ahead. Out of this run.

---
**v0.2 complete** (Phases 0–3): L1/L2/L3 + D4/D5/D6/D9 shipped on `dedup-hardening-v0.1`, **108 tests**. Phase 4 (hooks) awaits your go-ahead.
