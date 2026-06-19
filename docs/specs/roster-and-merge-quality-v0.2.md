# cPerch — Roster & merge quality spec (v0.2)

*Continuation of [dedup-hardening-v0.1.md](dedup-hardening-v0.1.md) (D1/D2/D3 shipped on branch
`dedup-hardening-v0.1`). Covers three findings from **live toolbar testing** (L1–L3) plus four
**leftover gap-analysis findings** (D4, D5, D6, D9 — see [../handover-v0.md](../handover-v0.md) §Dedup
& merge — gap analysis). Grounded in the source and the running app.*

- **Status:** reviewed 2026-06-18 — decisions locked (Q1 = **both**: heuristic + opt-in hooks; Q2 = **AI
  titles + collision label**). Implementation **deferred** by request. Pick up at §10 when ready.
- **Themes:** status accuracy (L1, D6) · roster display (L2, L3) · merge/join robustness (D4, D5, D9).
- **ACs** live per finding below; carried D-findings reference the handover rather than re-deriving.

---

## 1. Objective

Make cPerch's roster *tell the truth at a glance* on real multi-session use: (1) a live session that's
**waiting on you** must look different from one that's **done**; (2) two sessions must be
**tellable apart**; and (3) the merge's joins/tie-breaks must stay correct under real-world path and
registry messiness. Users: the same multi-agent babysitter — the value is a correct nudge and a
legible list.

**Definition of done:** `swift build` green · `./scripts/test.sh` green (new tests added) · `swift run
CPerchApp --print` and the live toolbar reflect the fixes on the author's real sessions · `~/.claude`
still read-only · no regression in the 79 tests from v0.1.

## 2. Background

- **Live-test findings (this session's toolbar screenshot):** the roster showed this very session as
  `concluded`/"all quiet" while the user was mid-conversation (L1); two identical `claude-toolbar-mac`
  rows (L2 — correct dedup of two real sessions, ambiguous UX); and one row with no message preview (L3).
- **Carried gap-analysis findings:** D4 (brittle cwd join), D5 (lexical registry tie-break), D6 (mtime
  vs record `timestamp`), D9 (future desktop double-listing). Full evidence in the handover.
- **Key code facts (verified):** `deriveStatus` maps `end_turn`/`stop_sequence`/`max_tokens` → `concluded`
  regardless of whether the assistant asked a question (SessionMerger.swift:130-134). `displayName` is
  **only** `cwd` basename (SessionMerger.swift:204); there is **no** title logic — the Models.swift "or
  AI-generated title" was never built. `TranscriptReader` already *sees and discards* `ai-title` meta
  records, and records carry `timestamp`, `gitBranch`, and `sessionId`.

## 3. Design decisions (sign off in §11)

- **DD-L1 (status): add a conservative "awaiting-you" heuristic now; spec opt-in hooks as a separate,
  reliable phase.** After an assistant `end_turn`, the ball is always in the human's court — but only an
  *open question / permission request* is a `needsInput` loop; a finished task is `concluded`. Discriminate
  on the last assistant text (ends with `?` / a small permission-phrase set) **and** require the session to
  be alive. Conservative by design (CLAUDE.md: a false needs-input nags; a missed one defeats the app).
  *Reliable complement:* opt-in `Stop`/`Notification` hooks (handover fast-follow #4) that write exact
  signals — touches `~/.claude/settings.json`, so opt-in. **✓ Chosen (sign-off): both** — heuristic first
  (Phase 1), opt-in hooks as a gated later phase (Phase 4).

- **DD-L2 (naming): implement the long-intended AI title as the display name, basename as fallback; add a
  secondary disambiguator only when two *visible* rows still collide.** Read the `ai-title` meta record
  (already in the stream, currently filtered) → `TranscriptSignal.aiTitle` (additive). When two shown rows
  share a name, append a muted secondary (relative time by default; `gitBranch` optional). **✓ Chosen
  (sign-off): adopt AI titles** as the display name (basename fallback) + the collision label.

- **DD-L3 (preview): fall back when there's no assistant text** — last user message, else a pending-tool
  summary (`Running <tool>…`), else a neutral placeholder. Cheap; no contract change.

- **DD-D6 (activity): use the last real record's `timestamp` for `lastActivity`, mtime as fallback.**
  Precise and robust to non-Claude touches; feeds L1's freshness, the sort, and retention.

- **DD-D4 (join): normalize both cwds before the Pass-2 compare** (`standardizedFileURL
  .resolvingSymlinksInPath`, strip trailing `/`, case-fold per macOS default); prefer a `sessionId` match
  where available. (The encoder is also lossy for spaces — `DBZ game` — reinforcing "don't compare raw
  encoded paths.")

- **DD-D5 (tie-break): on a duplicate `sessionId`, prefer the entry whose pid is live, else the newest
  `startedAt`** (now available from D3) — not lexical filename order. Fix the misleading "more recently
  captured" comments.

- **DD-D9 (forward-looking): add an alias-canonicalize seam to the merge now, implement when the desktop
  source lands.** A `cliSessionId ↔ desktop local_… id` map (from the `claude-code-sessions` metadata,
  handover fast-follow #2) collapses the same conversation to one row. This spec adds the *seam*
  (design-only); no desktop source is built here.

- **DD-contract:** additive only — `TranscriptSignal.aiTitle: String?` (L2); everything else is internal
  logic. No existing field repurposed.

## 4. Specification by finding

### L1 — distinguish "waiting on you" from "done"  `[High]`
**Current:** alive + `end_turn`/`stop_sequence`/`max_tokens` → `concluded` (SessionMerger.swift:130-134),
so an assistant that *asked you something* and ended its turn shows green/"all quiet".
**Change (heuristic phase):** in `deriveStatus`, when alive and the last turn is an assistant `end_turn`
whose `lastText` is question/permission-shaped → `needsInput`; else `concluded`. Add a pure
`static func looksLikeAwaitingUser(_ text: String?) -> Bool` (ends with `?`, or matches a small curated
set: "let me know", "would you like", "should I", "shall I", "do you want", "which would you", "confirm",
"approve…"). Keep `pendingToolUses` handling as-is (tool-permission already routes via stalled/needsInput).
**Change (hooks phase, opt-in — only if chosen):** install merge-not-overwrite `Stop`/`Notification` hooks
that append exact events to a cPerch-owned file the store reads; one-click removable. Touches
`~/.claude/settings.json` (the only write cPerch would ever do — gated behind explicit opt-in).
**Files:** `SessionMerger.swift` (+ `looksLikeAwaitingUser`); hooks phase adds an installer + a reader.
**ACs:**
- **AC-L1.1** alive + `end_turn` + `lastText` "Should I deploy to prod?" → `needsInput`.
- **AC-L1.2** alive + `end_turn` + `lastText` "All tests pass. Done." → `concluded`.
- **AC-L1.3** dead (no live pid) + question text → `concluded` (liveness still gates; no nagging a dead session).
- **AC-L1.4** `looksLikeAwaitingUser` truth table (positives/negatives incl. a rhetorical-`?`-in-the-middle
  case that should NOT trip, e.g. "I checked whether X? yes, and finished.").
- **AC-L1.5** (hooks phase, if chosen) an injected hook "needs-input" event forces `needsInput` regardless
  of heuristic; removal restores heuristic behavior.

### D6 — `lastActivity` from the record `timestamp`  `[Med]`
**Current:** `lastActivity` = file `contentModificationDate` (TranscriptReader.swift:52,142).
**Change:** parse the last real record's `timestamp` (ISO-8601) → `Date`; fall back to mtime when absent/
unparseable. Pure `static func parseTimestamp(_:) -> Date?`.
**Files:** `TranscriptReader.swift`.
**ACs:** **AC-D6.1** a record `"timestamp":"2026-06-18T20:29:53.698Z"` yields that instant (±1s), not mtime;
**AC-D6.2** a transcript with no parseable timestamp falls back to mtime; **AC-D6.3** `parseTimestamp` unit
tests (Z, offset, fractional seconds, garbage→nil).

### L2 — disambiguate same-project sessions (AI title)  `[Med]`
**Current:** `displayName` = `cwd` basename only; identical for same-project sessions.
**Change:** (1) `TranscriptReader` extracts the `ai-title` record's title → new `TranscriptSignal.aiTitle:
String?`. (2) `SessionMerger` sets `displayName = aiTitle ?? basename(cwd)`. (3) `RosterView`: when two
*visible* rows share a `displayName`, show a muted secondary label (relative time by default; `gitBranch`
optional later). 
**Files:** `SourceRecords.swift` (+`aiTitle`), `TranscriptReader.swift` (extract), `SessionMerger.swift`
(displayName), `RosterView.swift` (collision label), tests + a fixture with an `ai-title` record.
**ACs:** **AC-L2.1** a transcript with an `ai-title` → that title is the displayName; **AC-L2.2** no
`ai-title` → basename fallback; **AC-L2.3** two sessions, same project, no titles → roster shows a
distinguishing secondary label on both (so they're not visually identical).

### L3 — message-preview fallback  `[Low]`
**Current:** `latestMessage` = latest assistant text block; nil when none (pure-tool_use tail, etc.) →
blank row body.
**Change:** fallback chain in `TranscriptReader.latestAssistantText` (or its caller): last user text →
`Running <toolName>…` if a tool is pending → `nil` only as a last resort (RosterView already hides empties).
**Files:** `TranscriptReader.swift` (+ optionally a tiny RosterView placeholder).
**ACs:** **AC-L3.1** a transcript whose last assistant turn is pure `tool_use` yields a non-nil preview
(tool summary or prior user text); **AC-L3.2** a totally empty/meta-only transcript yields nil without crash.

### D4 — normalize the cwd join  `[Med]`  · D5 — registry tie-break  `[Med]`  · D9 — alias seam  `[Med, fwd]`
Per the handover gap analysis; specifics:
- **D4:** add `static func normalizedPath(_:) -> String` (resolve symlinks, standardize, strip trailing `/`)
  and use it on both sides of the Pass-2 `cwd` compare (SessionMerger.swift:69); prefer a `sessionId` match
  when both records carry it. **ACs:** **AC-D4.1** `/tmp/x` vs `/private/tmp/x` join; **AC-D4.2** trailing-
  slash and case variants join; **AC-D4.3** distinct dirs still don't collide.
- **D5:** in the `registryById` build (SessionMerger.swift:40), on collision keep the **live-pid** entry,
  else the newest `startedAt`; correct the comments. **ACs:** **AC-D5.1** two entries, same sessionId, one
  live pid → the live one's cwd/kind/status are used; **AC-D5.2** neither live → newest `startedAt` wins.
- **D9:** add `static func canonicalSessionId(_:aliases:) -> String` applied before `allIds` is built;
  `aliases` defaults empty (no behavior change today). **AC-D9.1** with an injected `cli↔local_` alias, the
  two ids collapse to one session; **AC-D9.2** empty aliases ⇒ identical to current output (no regression).
  *(Design-only: the desktop source that populates `aliases` is not built here.)*

## 5. Commands
```bash
cd cPerch
swift build · ./scripts/test.sh · swift run CPerchApp --print · ./build.sh && open dist/CPerch.app
```

## 6. Project structure (files this spec touches)
```
Sources/CPerchCore/SourceRecords.swift   L2: + TranscriptSignal.aiTitle: String?
Sources/CPerchCore/TranscriptReader.swift D6 (timestamp), L2 (ai-title extract), L3 (preview fallback)
Sources/CPerchCore/SessionMerger.swift    L1 (deriveStatus + looksLikeAwaitingUser), L2 (displayName),
                                          D4 (normalize), D5 (tie-break), D9 (canonicalSessionId seam)
Sources/CPerchApp/RosterView.swift        L2 (collision secondary label), L3 (placeholder, optional)
Tests/CPerchCoreTests/…                   new suites per finding + fixtures (ai-title; timestamped records)
+ (L1 hooks phase, if chosen)             a hooks installer + event reader (new files)
```

## 7. Code style
Match the surrounding code: pure `static` helpers in `CPerchCore` (Foundation-only), swift-testing,
fixtures via `#filePath`, fixed-clock determinism, comments explaining *why*. New string-matching
(`looksLikeAwaitingUser`) stays small, curated, and unit-tested — no heavy NLP.

## 8. Testing strategy
Unit-first and pure: every behavioral change lands a swift-testing test; new heuristics
(`looksLikeAwaitingUser`, `parseTimestamp`, `normalizedPath`, `canonicalSessionId`) are pure and table-
tested. Add fixtures mirroring real shapes (an `ai-title` record; records with `timestamp`). Manual ACs
(L1/L2 in the live roster) verified via `--print` + the toolbar and recorded in the handover. Keep the 79
v0.1 tests green.

## 9. Boundaries
Read-only on `~/.claude` — **except** the optional L1 hooks phase, which is the *single* sanctioned write
(merge-not-overwrite, one-click removable, explicit opt-in; never silent). `CPerchCore` stays Foundation-
only. No new TCC/Accessibility, no network, no duplicate windows. Additive contract changes only. Don't
tune thresholds/heuristics blind — validate `looksLikeAwaitingUser` against real transcripts via `--print`.

## 10. Sequencing & parallelization
Contract-first, then fan out by file (the three core files are disjoint — clean parallel tracks):
- **Phase 0 (serial):** `SourceRecords.swift` +`aiTitle` (nil-default) + fixtures (ai-title, timestamped). C0.
- **Phase 1 (parallel):** **Track T** = `TranscriptReader.swift` (D6 + L2-extract + L3) · **Track M** =
  `SessionMerger.swift` (L1 heuristic + D4 + D5 + D9) · **Track U** = `RosterView.swift` (L2 label + L3).
  Disjoint files ⇒ same isolated-clone fan-out as v0.1.
- **Phase 2 (serial):** integrate → one build + full suite (C2).
- **Phase 3 (serial, manual):** `--print` + live toolbar (AC-L1/L2 judgment); validate `looksLikeAwaitingUser`.
- **Phase 4 (optional, gated):** L1 hooks installer — only if the hooks approach is chosen at sign-off.

## 11. Open questions for sign-off
- **Q1 (DD-L1): RESOLVED ✓** — **both**: conservative heuristic now (Phase 1) + opt-in hooks as a gated
  later phase (Phase 4).
- **Q2 (DD-L2): RESOLVED ✓** — adopt **AI titles** as the display name (basename fallback) + collision label.
- **Q3 — scope:** all seven (L1–L3, D4/D5/D6/D9) in one effort, or split (e.g. status L1+D6 first, the rest
  next)? Default: **one effort, fanned out** as §10.
- **Q4 (DD-L1 risk):** acceptable for the heuristic to occasionally mis-flag? (A false `needsInput` nags; a
  miss defeats the app — CLAUDE.md.) Default: **bias toward fewer false positives** (only clear questions).
