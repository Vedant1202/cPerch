# cPerch — Dedup hardening spec (v0.1)

*Implementation spec for the three high-severity findings (D1, D2, D3) from the post-v0
dedup/merge gap analysis. Companion to [../handover-v0.md](../handover-v0.md) §Dedup & merge —
gap analysis (the "why"); this file is the "what & how to build + how we'll know it's done".*

- **Status:** reviewed 2026-06-18 — decisions locked (incl. DD-4); implementation **deferred** by request
  ("spec only"). A future session/agent can pick up at §10 with no further sign-off on the locked items.
- **Scope:** D1 (transcript-owned cwd), D2 (status-absent reality + test coverage), D3 (PID-reuse guard).
- **Out of scope (this spec):** D4–D10. D6 (record `timestamp` for `lastActivity`) is the natural next
  spec and is called out where it intersects D3, but is **not** built here.
- **Grounding:** all claims verified against the source and this machine's live `~/.claude`
  (Claude CLI **v2.1.170**). Re-verify the data shapes on the target machine before coding (§7).

---

## 1. Objective

Make the merge's session→liveness join correct and trustworthy on **real current-Claude data**, where
(a) project dirs are hyphenated, (b) registry files omit `status`, and (c) PIDs get recycled. Concretely:

1. **D1** — a live session must never be mis-shown as `concluded` because its directory name contains `-`.
2. **D2** — the status path that actually runs on real data (the transcript heuristic) must be the one we
   test and tune; the registry-`status` path must be treated as a bonus, not the baseline.
3. **D3** — "jump" must never focus the wrong window, and a session must never be shown alive, because a
   dead session's PID was reused by an unrelated process.

**Users:** the cPerch user babysitting several Claude sessions. The failure modes above are exactly the
ones the product promises to prevent (CLAUDE.md: "a missed [needs-input] defeats the app"; jump "must
never spawn a duplicate" / focus the wrong window).

**Definition of done:** `swift build` green · `./scripts/test.sh` green with the new tests · `swift run
CPerchApp --print` shows correct project names and live/concluded states for the author's real sessions
(including a hyphenated-dir session and, if reproducible, a reused-PID case) · no regression in the
existing 39 tests · `~/.claude` still only ever read.

---

## 2. Background — the three findings (one paragraph each)

- **D1 · `decodeProjectDir` is lossy and feeds a join key.** `SessionStore.decodeProjectDir`
  ([SessionStore.swift:160](../../Sources/CPerchCore/SessionStore.swift)) reverses the `/`→`-` encoding with
  `"/" + dir.split("-").joined("/")`, which cannot distinguish a `/`-derived `-` from a literal one. Real
  dir `-Users-vedant-Projects-Personal-claude-toolbar-mac` decodes to `…/claude/toolbar/mac`. That cwd is
  attached to `TranscriptSignal.cwd` for recent (registry-absent) transcripts and then used as a join key
  in `SessionMerger` Pass 2 (`$0.cwd == cwd`,
  [SessionMerger.swift:69](../../Sources/CPerchCore/SessionMerger.swift)). A live **unregistered** session
  in a hyphenated dir therefore fails to bind its process → shows `concluded` while running. **Real
  transcripts carry an exact `cwd` field**, so the decode is unnecessary.

- **D2 · the registry `status` field is absent on the current CLI.** Real `~/.claude/sessions/<pid>.json`
  keys: `[cwd, entrypoint, kind, peerProtocol, pid, procStart, sessionId, startedAt, version]` — no
  `status`. So `deriveStatus`' `busy`/`waiting`/`idle` switch
  ([SessionMerger.swift:114](../../Sources/CPerchCore/SessionMerger.swift)) never fires; everything falls to
  the transcript heuristic. Yet every `SessionMergerTests` case sets `status:` to a non-nil value, so the
  real path is under-tested and `stalledThreshold = 120s` is unvalidated.

- **D3 · the PID→sessionId bridge trusts a recycled PID.** Pass 1 binds
  `pidForSession[entry.sessionId] = p.pid` for any live pid present in the registry
  ([SessionMerger.swift:53](../../Sources/CPerchCore/SessionMerger.swift)); `RegistryReader` ingests every
  `<pid>.json` with no liveness check. If a crashed session's `<pid>.json` lingers and the OS reassigns that
  pid to another genuine-`claude` process (e.g. `claude -p …`, which `isGenuineClaudeSession` keeps), the
  dead session is shown alive and its host resolves from the **new** process's tty → wrong-window jump.

---

## 3. Design decisions (flag any you disagree with at sign-off)

- **DD-1 (D1): retire `decodeProjectDir` from the data path; read `cwd` from the transcript.** Every real
  record carries `cwd`. `TranscriptReader` will parse it from the last real record and set it on the
  returned `TranscriptSignal`. `decodeProjectDir` is **kept only** as a display-name fallback for the
  (rare) transcript with no parseable `cwd`. *Alternative considered:* fix the decode by storing Claude's
  exact encoding rules — rejected: brittle, and the authoritative value is already in the file.

- **DD-2 (D3): `startedAt` (epoch ms) is the start-time source of truth, not `procStart`.** Empirically
  `procStart` (`'Thu Jun 18 20:29:53 2026'`) and `ps -o lstart` (`'Thu Jun 18 15:29:53 2026'`) for the same
  live pid differ by the local UTC offset — `procStart`'s timezone is ambiguous. `startedAt`
  (`1781814593698`) is absolute. We decode `startedAt`, derive the live process's start time from `ps`, and
  compare as instants. *Alternative:* parse `procStart`/`lstart` strings — rejected: TZ-ambiguous (proven).

- **DD-3 (D3): reject the bind only on a *confident* start-time mismatch; never on "unknown".** Bind iff
  the process start time is unavailable (ps failed → don't regress) **or** matches `startedAt` within a
  generous tolerance. Reject only when both are known and differ beyond the tolerance. A reused pid's new
  process starts long after the dead session's `startedAt` (minutes–hours), so a loose tolerance catches
  reuse with ~zero false rejects. **Default tolerance: 120 s** (tunable constant). *Why a dropped bind is
  correct, not a regression:* if pid 4242 is now a different process, session A genuinely has no live
  process → `concluded` is the **true** state, and jump correctly won't target 4242's tty.

- **DD-4 (D3): when reuse is detected, drop the bind entirely** (session resolves via its other signals).
  **✓ Confirmed at sign-off (2026-06-18).** Simpler than "bind liveness but suppress jump", and yields the
  correct status (the real session is gone → `concluded` is true). *Alternative (rejected):* keep liveness,
  mark `host = .unknown` — more states to reason about; revisit only if a real case shows a live session we
  still want to surface.

- **DD-5 (D2): treat the transcript heuristic as the baseline; keep the `status` branch as an optimization.**
  No behavior change to `deriveStatus`' precedence (registry-status-first is still correct *when present*,
  e.g. older/other versions). The work is **test coverage + threshold validation**, plus a one-line log/note
  so future readers know `status` is usually nil.

- **DD-6 (contracts): the Phase-0 frozen records may now change (handover sanctions the lift).** D1 needs no
  contract change (`TranscriptSignal.cwd` already exists). D3 adds **optional** fields: `RegistryEntry.startedAt:
  Date?` and `ProcessRecord.startTime: Date?`. Additive + optional ⇒ existing construction sites compile
  after adding the argument; semantics preserved.

---

## 4. Specification by finding

### D1 — transcript-owned cwd

**Current:** `TranscriptReader.read(path:sessionId:cwd:)` echoes the caller-supplied `cwd`
([TranscriptReader.swift:36-54](../../Sources/CPerchCore/TranscriptReader.swift)). `SessionStore.gatherTranscripts`
supplies a `decodeProjectDir`-derived cwd for recent/registry-absent transcripts
([SessionStore.swift:118-123](../../Sources/CPerchCore/SessionStore.swift)).

**Change:**
1. In `TranscriptReader`, extract `cwd` from the last real record's top-level `cwd` field; use it for the
   returned signal. Fall back to the passed-in `cwd` when absent. (`sessionId` may likewise be cross-checked
   against the record's `sessionId` for a future hardening — note only, not built here.)
2. In `SessionStore.gatherTranscripts`, pass the best-known cwd as a *fallback* (registry `cwd` for
   registry sessions; `decodeProjectDir` only as the last resort for recent files).
3. `displayName(for:)` is unchanged but now receives a correct cwd.

**Files:** `TranscriptReader.swift` (parse cwd), `SessionStore.swift` (fallback wiring), tests + a fixture.

**Acceptance criteria:**
- **AC-D1.1** Given a transcript whose records carry `"cwd":"/Users/x/my-hyphen-project"`, `TranscriptReader`
  returns a signal with that exact cwd regardless of the `cwd` argument passed.
- **AC-D1.2** Given a registry-absent recent transcript in a hyphenated dir and a live unregistered process
  whose `lsof` cwd equals the record cwd, `SessionMerger` binds the process → status is live
  (`running`/`needsInput`), **not** `concluded`. (Regression test for the join.)
- **AC-D1.3** Display name for a hyphenated-dir session is the full basename (e.g. `claude-toolbar-mac`,
  not `mac`). Verifiable live via `swift run CPerchApp --print`.
- **AC-D1.4** A transcript with no `cwd` field still yields a signal (fallback cwd), no crash.

### D2 — status-absent reality + heuristic coverage

**Change (tests/fixtures, minimal prod code):**
1. Add `RegistryEntry` fixtures/tests with `status: nil` mirroring v2.1.170 (the real shape) and assert
   the resulting status comes from the transcript heuristic.
2. Broaden `SessionMergerTests` to cover the `deriveStatus` transcript-fallback branch directly: pending
   tool fresh→`running` vs stalled→`needsInput`; `end_turn`/`stop_sequence`/`max_tokens`→`concluded`; last
   role `user` fresh→`running`, stalled→`needsInput`; the `stalledThreshold` boundary (just under vs just
   over 120 s).
3. Validation task (not a unit test): with `--print`, confirm the 120 s threshold produces sane
   needs-input timing on real sessions; record findings in the handover. If 120 s proves wrong, change the
   constant in a follow-up (don't guess here).
4. Optional one-liner: a comment (or `os_log` at debug) noting `status` is typically nil on current CLI, so
   the heuristic is the primary path.

**Acceptance criteria:**
- **AC-D2.1** A `status: nil` registry entry + a live pid + a transcript with a fresh pending tool ⇒
  `running`; same but `lastActivity` older than `stalledThreshold` ⇒ `needsInput`.
- **AC-D2.2** A `status: nil` entry + `end_turn` transcript + live pid ⇒ `concluded`.
- **AC-D2.3** Tests exist that would **fail** if the `deriveStatus` `default:`/transcript branch regressed
  (i.e. coverage no longer depends on a non-nil `status`).
- **AC-D2.4** The threshold-boundary test pins behavior at `now - lastActivity` = 119 s vs 121 s.

### D3 — PID-reuse guard

**Change:**
1. `RegistryReader`: decode `startedAt` (epoch ms, `Int`) → `RegistryEntry.startedAt: Date?`
   (`Date(timeIntervalSince1970: ms/1000)`). Tolerate absence.
2. `ProcessScanner`: capture each process's start time into `ProcessRecord.startTime: Date?`. Source: add a
   start column to the existing `ps` call. Prefer an absolute, locale-stable parse:
   `ps -Ao pid,ppid,tty,%cpu,lstart,command` is **not** column-stable (lstart has spaces); instead fetch
   start separately or compute from elapsed. **Recommended:** `ps -o etime= -p <pid>` per live claude pid
   (small N) → `startTime ≈ now − etime` (TZ-free). *Alternative:* `ps -o lstart=` parsed with a POSIX
   `DateFormatter` (`"EEE MMM d HH:mm:ss yyyy"`, local TZ). Pick one in implementation; both are speced to
   match `startedAt` within tolerance.
3. `SessionMerger.merge` Pass 1: a new pure helper gates the bind:
   ```
   static func bindIsTrustworthy(process: ProcessRecord, entry: RegistryEntry,
                                 tolerance: TimeInterval = pidReuseTolerance) -> Bool {
       guard let pStart = process.startTime, let rStart = entry.startedAt else { return true } // unknown → trust
       return abs(pStart.timeIntervalSince(rStart)) <= tolerance
   }
   ```
   Pass 1 binds only when `bindIsTrustworthy` is true; otherwise the pid is treated as unregistered noise
   (not added to `unregistered` for cwd-claiming either — it isn't our session).
4. New constant `pidReuseTolerance: TimeInterval = 120`.

**Files:** `RegistryReader.swift`, `SourceRecords.swift` (two optional fields), `ProcessScanner.swift`
(start-time capture), `SessionMerger.swift` (gate), tests.

**Acceptance criteria:**
- **AC-D3.1** `bindIsTrustworthy` is true when `|process.startTime − entry.startedAt| ≤ tolerance`, false
  when it exceeds it, and true when either is nil (no regression on missing data). Pure unit tests.
- **AC-D3.2** Merge test: a registry entry (pid 4242, `startedAt` = T0) + a live process (pid 4242,
  `startTime` = T0 + 1h) ⇒ session is **`concluded`**, `pid == nil`, host is **not** a terminal from 4242.
- **AC-D3.3** Merge test: same pid, `startTime` within tolerance of `startedAt` ⇒ bound, live, host from tty
  (the normal case still works).
- **AC-D3.4** `RegistryReader` decodes `startedAt` from real-shaped JSON (epoch ms) and yields a `Date`
  within 1 s of the expected instant; missing `startedAt` ⇒ nil, no throw.
- **AC-D3.5** No new permission prompt; still pure `ps`/file reads.

---

## 5. Commands

```bash
cd cPerch
swift build                       # compiles (core stays Foundation-only)
./scripts/test.sh                 # swift-testing suite (XCTest is NOT in the CLT — use this)
swift run CPerchApp --print       # headless: dump live sessions to eyeball D1/D3 on real data
./build.sh && open dist/CPerch.app  # full bundle (only needed for UI/notify/jump manual checks)
```

## 6. Project structure (files this spec touches)

```
Sources/CPerchCore/
  SourceRecords.swift   D3: + RegistryEntry.startedAt: Date?, + ProcessRecord.startTime: Date?
  RegistryReader.swift  D3: decode startedAt (epoch ms → Date)
  ProcessScanner.swift  D3: capture process start time (etime or lstart)
  TranscriptReader.swift D1: read cwd (and optionally sessionId) from the last record
  SessionStore.swift    D1: pass fallback cwd; decodeProjectDir demoted to fallback-only
  SessionMerger.swift   D3: bindIsTrustworthy gate in Pass 1; + pidReuseTolerance constant
Tests/CPerchCoreTests/
  TranscriptReaderTests.swift  D1 ACs
  SessionMergerTests.swift     D1.2 join, D2 heuristic coverage, D3 gate ACs
  RegistryReaderTests.swift    D3.4 startedAt decode
Tests/fixtures/
  transcripts/…                D1: a fixture whose records carry cwd (+ a no-cwd one)
  registry-dir/…               D2/D3: status:nil + startedAt entries (real v2.1.170 shape)
```

## 7. Verify-before-coding (re-confirm the data contract)

The spec leans on field shapes observed on one machine. Before implementing, re-confirm on the target:

```bash
# D1: records carry cwd?
ls -t ~/.claude/projects/*/*.jsonl | head -1 | xargs -I{} sh -c \
  'grep -m1 "\"type\":\"assistant\"" "{}" | python3 -c "import sys,json;print(json.loads(sys.stdin.readline()).get(\"cwd\"))"'
# D2/D3: registry omits status? carries startedAt (epoch ms) + procStart?
f=$(ls -t ~/.claude/sessions/*.json | head -1); python3 -c "import json;d=json.load(open('$f'));print({k:d.get(k) for k in ('status','startedAt','procStart','pid')})"
```
Expected (v2.1.170): record `cwd` = the real path; registry `status` = None, `startedAt` = int ms,
`procStart` = a TZ-ambiguous string. If a newer Claude restores `status` or changes shapes, revisit DD-2/DD-5.

## 8. Testing strategy

- **Unit-first, pure core.** Every behavioral change lands a `swift-testing` test in `CPerchCoreTests`. New
  logic (`bindIsTrustworthy`, transcript-cwd extraction) is pure and hand-fed synthetic records — no FS.
- **Fixtures mirror reality.** Add fixtures with the **real v2.1.170 shapes** (status-less registry +
  startedAt; transcripts with `cwd`). This closes the D2 "tests exercise a dead path" gap structurally.
- **Determinism.** Reuse the fixed-clock pattern (`now = Date(timeIntervalSince1970:)`) already in
  `SessionMergerTests` for all freshness/threshold/tolerance assertions.
- **Manual ACs** (can't be headless): AC-D1.3 and a real reused-PID sighting are verified via `--print` and
  recorded in the handover. The terminal-jump-to-wrong-tab non-regression is covered by AC-D3.2 at the unit
  level (host is not a 4242 terminal) so we don't depend on reproducing reuse live.
- **Gate:** the existing 39 tests must stay green; target net-new ≈ 10–14 tests.

## 9. Boundaries (inherited from SPEC §8 — non-negotiable)

- **Read-only on `~/.claude`** — these fixes add only reads (`ps`, JSON). Never write/mutate it.
- **`CPerchCore` stays pure** — Foundation only; no AppKit/SwiftUI; the new `ps` start-time call lives in
  `ProcessScanner` behind the existing injected-closure seam so tests don't shell out.
- **No new TCC/permissions**, no Accessibility, no network, no token access, no duplicate windows.
- **Additive contract changes only** — new record fields are optional; don't repurpose existing ones.
- **Don't guess the threshold.** `stalledThreshold`/`pidReuseTolerance` changes must be evidence-backed
  (validated via `--print`), not tuned blind.

## 10. Sequencing & rollout

Land in this order, each its own commit, tests green at every step:

1. **D1** — highest impact, lowest risk, no contract change. Ship + eyeball `--print` (names correct).
2. **D3** — contract additions + reuse gate. Ship + AC-D3.2/3.3 unit-proven; opportunistically confirm live.
3. **D2** — fixtures + heuristic coverage + threshold validation note. (Can parallel D1/D3 since it's mostly
   tests, but do the threshold validation **after** D1 so `--print` reflects correct sessions.)

Each step: `swift build` + `./scripts/test.sh` + `swift run CPerchApp --print` sanity. Append any
threshold/reuse findings to handover §Dedup & merge — gap analysis.

## 11. Open questions for sign-off

- **Q1 (scope):** strictly D1/D2/D3, or fold in **D6** (use record `timestamp` for `lastActivity`) since
  D3 already parses `ps`/record times? Default: **keep D6 out**, do it next.
- **Q2 (DD-3 tolerance):** 120 s default OK, or prefer tighter/looser? Default 120 s (loose = safe here).
- **Q3 (DD-4): RESOLVED ✓** — drop the bind → `concluded` (chosen at sign-off, 2026-06-18).
- **Q4 (D3 start source):** `etime`-derived (TZ-free, recommended) vs `lstart` parse — implementer's call,
  or do you want it pinned now?
