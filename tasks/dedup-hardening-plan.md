# cPerch — Dedup hardening: implementation plan

*Phased, dependency-ordered plan for the spec [docs/specs/dedup-hardening-v0.1.md](../docs/specs/dedup-hardening-v0.1.md)
(findings **D1, D2, D3**). Task list: [dedup-hardening-todo.md](dedup-hardening-todo.md).*

- **Status:** plan artifact — **implementation deferred** (spec-only sign-off). Not a trigger to code.
- **Locked decisions** (from spec §3 / sign-off): DD-1 (read transcript cwd), DD-2 (`startedAt` epoch,
  not `procStart`), DD-3 (reject bind only on confident mismatch; tolerance 120 s), **DD-4 (reuse ⇒ drop
  bind ⇒ concluded — ✓ confirmed)**, DD-5 (heuristic is the baseline), DD-6 (additive contract changes).
- **Acceptance criteria** live in the spec (AC-D1.x / AC-D2.x / AC-D3.x) — referenced, not duplicated.
- **Naming:** uses `dedup-hardening-*` files so the v0 `tasks/plan.md` + `tasks/todo.md` are untouched.

---

## 1. Dependency graph

```
Phase 0 · Contract + fixtures  ───────────────────────────────────  SERIAL (blocking)
  0.1 SourceRecords: +RegistryEntry.startedAt:Date?  +ProcessRecord.startTime:Date?   (init params = nil)
  0.2 Fixtures: status-less + startedAt registry entries; transcript w/ cwd; transcript w/o cwd
  0.3 (opt) Tests/TestSupport.swift: shared proc()/reg()/sig() factories (new fields defaulted)
        │
        │   ◇ Checkpoint C0 (fan-out gate): swift build + 39 existing tests green; change is additive-only
        ▼
Phase 1 · Implementation  ─────────────────────────────────────────  PARALLEL (disjoint file sets)
  ├─ Track A · D1  transcript-owned cwd     TranscriptReader.swift · SessionStore.swift  (+JoinTests)
  ├─ Track B · D3  PID-reuse guard          RegistryReader.swift · ProcessScanner.swift · SessionMerger.swift  (+ReuseTests)
  └─ Track C · D2  status-absent coverage   (tests only)  (+StatusTests)
        │
        │   ◇ Checkpoint C1 (per track): track builds + its own new suite green on the C0 baseline
        ▼
Phase 2 · Integration  ────────────────────────────────────────────  SERIAL
  2.1 Reconverge tracks → one swift build + full ./scripts/test.sh
        │   ◇ Checkpoint C2: whole suite green (39 + A/B/C), no warning regressions
        ▼
Phase 3 · Validate + commit  ──────────────────────────────────────  SERIAL · manual · human-in-loop
  3.1 swift run CPerchApp --print on real ~/.claude (AC-D1.3; D2 threshold; D3 eyeball)
  3.2 Append findings to handover; commit (branch off main) in D1→D3→D2 order
        │   ◇ Checkpoint C3: DoD met
```

## 2. Which phases parallelize (the headline)

| Phase | Mode | Agents | Why |
|---|---|---|---|
| **0** | Serial (blocking) | 1 | Shared contract + fixtures everyone compiles against. Cheap. |
| **1** | **Parallel** | **2–3** (A, B, C) | Disjoint file sets; each a vertical slice with its **own** new test suite. |
| **2** | Serial | 1 | Single reconvergence build — the one barrier. |
| **3** | Serial (manual) | 1 + human | One machine, real `~/.claude`, judgment calls (threshold, reuse sighting). |

**Only Phase 1 fans out.** B (D3) is the heaviest, A (D1) medium, C (D2) light. If running 2 agents, fold
C into the Phase-2 integrator. Phase 0's checkpoint **C0 must land and be shared before fan-out**.

### File-ownership matrix (the disjointness proof)

| File | P0 | A · D1 | B · D3 | C · D2 |
|---|:--:|:--:|:--:|:--:|
| `Sources/CPerchCore/SourceRecords.swift` | ✎ | | | |
| `Sources/CPerchCore/TranscriptReader.swift` | | ✎ | | |
| `Sources/CPerchCore/SessionStore.swift` | | ✎ | | |
| `Sources/CPerchCore/RegistryReader.swift` | | | ✎ | |
| `Sources/CPerchCore/ProcessScanner.swift` | | | ✎ | |
| `Sources/CPerchCore/SessionMerger.swift` | | | ✎ | |
| `Tests/…/TranscriptReaderTests.swift` | | ✎ | | |
| `Tests/…/RegistryReaderTests.swift` | | | ✎ | |
| `Tests/…/SessionMerger+JoinTests.swift` *(new)* | | ✎ | | |
| `Tests/…/SessionMerger+ReuseTests.swift` *(new)* | | | ✎ | |
| `Tests/…/SessionMerger+StatusTests.swift` *(new)* | | | | ✎ |
| `Tests/…/TestSupport.swift` *(new, opt)* | ✎ | ·read· | ·read· | ·read· |
| `Tests/fixtures/**` | ✎ | ·read· | ·read· | ·read· |

No file is written by two tracks. **New merger tests go in per-concern suite files**, so the existing
`SessionMergerTests.swift` is *not edited* by anyone (its `status:"busy"` cases stay valid — they cover the
registry-status-present path, still correct when present).

---

## 3. Phase 0 — Contract + fixtures  *(serial, blocking)*

**0.1 · Extend frozen records** — `SourceRecords.swift`
Add `public let startedAt: Date?` to `RegistryEntry` and `public let startTime: Date?` to `ProcessRecord`,
each as an init parameter **defaulted to `nil`**. Default-nil ⇒ every existing construction site
(`ProcessScanner`, `RegistryReader`, test helpers) compiles unchanged → additive, non-breaking (DD-6).
*Verify:* `swift build` green; `./scripts/test.sh` green (39 tests, no behavior change).

**0.2 · Real-shape fixtures** — `Tests/fixtures/`
- `registry-dir/`: 1–2 entries with **no `status` key**, **with** `startedAt` (epoch ms), `procStart`,
  `kind:"interactive"`, `pid`, `sessionId`, `cwd`, `version:"2.1.170"` (mirror spec §7's real shape).
- `transcripts/with-cwd.jsonl` (records carry `"cwd"` + `sessionId`) and `transcripts/no-cwd.jsonl`.
*Verify:* valid JSON/JSONL; consumed by Phase 1.

**0.3 · (optional, recommended) Shared test factories** — `Tests/…/TestSupport.swift`
Extract `proc()/reg()/sig()` factory helpers (with the new fields defaulted) so A/B/C don't each
re-declare them and don't touch `SessionMergerTests.swift`. Tracks consume it read-only.

> ◇ **Checkpoint C0 (fan-out gate):** build + all existing tests green · `SourceRecords` change is
> additive-only (no existing site edited) · fixtures parse. → safe to fan out Phase 1.

---

## 4. Phase 1 — Implementation  *(parallel: A ∥ B ∥ C)*

### Track A · D1 — transcript-owned cwd   *(spec §4/D1, DD-1)*  — size **M**
**Owns:** `TranscriptReader.swift`, `SessionStore.swift`, `TranscriptReaderTests.swift`,
`SessionMerger+JoinTests.swift` *(new)*. **Consumes:** 0.2 transcript fixtures.
1. `TranscriptReader`: read top-level `cwd` from the last real record → set on the returned `TranscriptSignal`;
   fall back to the passed-in `cwd` when absent. (May also read the record `sessionId` for a future
   cross-check — note only, not built.)
2. `SessionStore.gatherTranscripts`: pass best-known *fallback* cwd (registry `cwd` for registry sessions;
   `decodeProjectDir` **only** as last resort for recent files). Leave FSEvents/poll wiring untouched.
3. Tests: AC-D1.1 (record cwd overrides argument), AC-D1.4 (no-cwd → fallback, no crash) in
   `TranscriptReaderTests`; AC-D1.2 (live unregistered proc in a hyphenated dir **binds → live, not
   concluded**) in `SessionMerger+JoinTests` via synthetic records.
*Verify:* `./scripts/test.sh` green; AC-D1.1/1.2/1.4. **AC-D1.3 is manual → Phase 3.**

### Track B · D3 — PID-reuse guard   *(spec §4/D3, DD-2/3/4)*  — size **L** (heaviest)
**Owns:** `RegistryReader.swift`, `ProcessScanner.swift`, `SessionMerger.swift`,
`RegistryReaderTests.swift`, `SessionMerger+ReuseTests.swift` *(new)*. **Consumes:** 0.2 registry fixtures.
1. `RegistryReader`: decode `startedAt` (epoch **ms** `Int`) → `Date(timeIntervalSince1970: ms/1000)` →
   `RegistryEntry.startedAt`. Tolerate absence (nil).
2. `ProcessScanner`: capture process start → `ProcessRecord.startTime`, behind an **injectable resolver**
   (mirror the existing `resolveCwd` seam so tests never shell out). Production: `ps -o etime= -p <pid>` →
   `start = now − etime` (TZ-free, **recommended**), or `ps -o lstart=` parsed with a POSIX `DateFormatter`
   (local TZ). Small N (live claude pids only).
3. `SessionMerger`: add `static let pidReuseTolerance: TimeInterval = 120` and a **pure**
   `bindIsTrustworthy(process:entry:tolerance:) -> Bool` (true if either start time is nil → trust; else
   `abs(Δ) ≤ tolerance`). Gate Pass-1 binding on it; on a **confident mismatch DROP the bind** (don't add
   to `unregistered` either) → session resolves `concluded` (**DD-4**).
4. Tests: AC-D3.4 (startedAt decode) in `RegistryReaderTests`; AC-D3.1 (helper truth table), AC-D3.2
   (reuse → concluded, `pid==nil`, host **not** a 4242 terminal), AC-D3.3 (match → bound/live/terminal) in
   `SessionMerger+ReuseTests`.
*Verify:* `./scripts/test.sh` green; AC-D3.1–3.5. **B owns `SessionMerger.swift` exclusively** — if a D2
explanatory comment is wanted, add it here (not in Track C).

### Track C · D2 — status-absent coverage   *(spec §4/D2, DD-5)*  — size **S** (tests only)
**Owns:** `SessionMerger+StatusTests.swift` *(new)*. **Consumes:** 0.2 registry fixtures. **No prod edit.**
1. Exercise `deriveStatus`' transcript-fallback branch with `status: nil`: fresh pending → `running` vs
   stalled → `needsInput`; `end_turn`/`stop_sequence`/`max_tokens` → `concluded`; last role `user` fresh →
   `running`, stalled → `needsInput`; `stalledThreshold` boundary (119 s vs 121 s). AC-D2.1–2.4.
*Verify:* `./scripts/test.sh` green; AC-D2.1–2.4. **Threshold *validation* (is 120 s right on real data?)
is NOT a unit test → Phase 3**, done after D1 lands so `--print` reflects correct sessions.

> ◇ **Checkpoint C1 (per track):** the track builds and its own new suite passes on the C0 baseline.

**Latent cross-track coupling (only one):** Track C's tests call `merge()`/`deriveStatus`; Track B edits
the same *file* but not those *contracts* (B adds Pass-1 gating + a new helper; `deriveStatus` and `merge()`'s
public behavior are unchanged per the spec). So C and B stay independent. *If* B ever had to change
`deriveStatus`, serialize C after B.

---

## 5. Phase 2 — Integration  *(serial)*

**2.1** Reconverge the three tracks onto the C0 baseline (copy disjoint files / merge branches) → one
`swift build` + full `./scripts/test.sh` (39 existing + A/B/C suites). Confirm B's new Pass-1 gate doesn't
perturb A's join test or C's status tests (it can't — the gate only fires on a start-time mismatch those
tests don't create).
> ◇ **Checkpoint C2:** whole suite green; no new warnings.

## 6. Phase 3 — Validate + commit  *(serial · manual · human-in-loop)*

**3.1** `swift run CPerchApp --print` on the real `~/.claude`:
- **AC-D1.3** — hyphenated names render in full (`claude-toolbar-mac`, `Auto-UI-AB-Testing`), not `mac`/`Testing`.
- **D2 threshold** — observe needs-input timing; is 120 s sane? Record findings; change `stalledThreshold`
  only with evidence (separate follow-up if needed).
- **D3** — scan for any wrong host/liveness; opportunistically reproduce a reused-pid case (AC-D3.2 already
  proves the guard at unit level, so this is best-effort).

**3.2** Append findings to handover §Dedup & merge — gap analysis. Commit on a branch off `main` (repo norm:
don't commit to `main` directly). With parallel dev, commit each track's disjoint files as its own commit in
spec **§10 order (D1 → D3 → D2)** for a clean, bisectable history.
> ◇ **Checkpoint C3 (DoD):** build + tests green · `--print` correct on real data · `~/.claude` read-only ·
> no new permissions · existing 39 tests intact.

---

## 7. Agent fan-out playbook

- **Fan out only Phase 1** (Tracks A, B, C). Phases 0/2/3 are serial.
- **Gate:** land + share Phase 0 (checkpoint **C0**) first — all tracks compile against the extended
  `SourceRecords`.
- **Isolation:** this repo is a **subdir** of the git/session root, so `git worktree` is awkward (handover
  §"If you fan out work"). Use **clean `git clone`s into temp dirs** as manual isolation; reconverge by
  copying each track's disjoint files back. (Agent-tool `isolation: "worktree"` works only if rooted
  correctly; the disjoint-file guarantee is what makes copy-reconverge safe regardless.)
- **Brief each agent with:** the spec, this plan's track section, and its **exact disjoint file list**; tell
  it (a) touch nothing outside the set, (b) put new tests in its **named new suite file** (never the shared
  `SessionMergerTests.swift`), (c) keep `CPerchCore` Foundation-only and `~/.claude` read-only.
- **Recommended shape:** 2 agents (A, B) + fold C into the integrator, or 3 agents (A, B, C). B is the long
  pole — start it first.

## 8. Risks & watch-items

- **`ps` start-time parsing** (`etime`/`lstart`) — edge cases; keep behind the injectable seam and unit-test
  the parser on sample strings. (B)
- **`pidReuseTolerance = 120 s`** — loose by design (DD-3); confirm zero false rejects for normal sessions
  in Phase 3. (B)
- **`SessionStore` wiring** — don't disturb FSEvents/poll/debounce while editing `gatherTranscripts`. (A)
- **Cross-track coupling** — C depends on `merge()`/`deriveStatus` staying stable; spec mandates B keeps
  them so. Serialize C after B only if that changes.
- **Don't clobber** the v0 `tasks/plan.md` / `tasks/todo.md` — this work uses `dedup-hardening-*` files.
