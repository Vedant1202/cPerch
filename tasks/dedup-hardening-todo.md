# cPerch — Dedup hardening: task list

*Checklist for [dedup-hardening-plan.md](dedup-hardening-plan.md) · spec
[docs/specs/dedup-hardening-v0.1.md](../docs/specs/dedup-hardening-v0.1.md). **Implementation deferred** —
this is the ready-to-pick-up list. `⇄` = parallelizable.*

Legend: `[ ]` todo · `◇` checkpoint (must pass before proceeding) · AC refs point into the spec.

---

### Phase 0 · Contract + fixtures — SERIAL (blocking)
- [x] **0.1** `SourceRecords.swift`: added `RegistryEntry.startedAt: Date?` + `ProcessRecord.startTime: Date?`
      (init params **defaulted `nil`** → additive; pinned by `SourceRecordsTests.swift`, 4 tests). — *DD-6*
- [x] **0.2** Fixtures: added `transcripts/with-cwd.jsonl` + `transcripts/no-cwd.jsonl`. Registry side **already
      covered** — `registry-dir/4242.json` (startedAt+status) and `5151.json` (startedAt, no status) are the real
      v2.1.170 shapes; left untouched (the `count==2` assertion). — *AC-D1.1/1.4 staged; AC-D3.4 reuses 4242*
- [~] **0.3** *(deferred — optional)* shared `TestSupport.swift`: not needed for C0. Each Phase-1 track can add its
      own helpers (existing per-file `#filePath` + private-helper pattern). Revisit at Phase-1 start if useful.
- [x] ◇ **C0 fan-out gate:** `swift build` green · `./scripts/test.sh` green (**43** = 39 + 4 contract) · additive-only · fixtures parse. ✓

### Phase 1 · Implementation — PARALLEL ⇄ (done via 3 isolated-clone agents; disjoint files) ✓

**⇄ Track A · D1 — transcript-owned cwd** — commit `6db55f5`
- [x] **A1** `TranscriptReader.recordCwd(in:)` reads `cwd` from the last record carrying one; falls back to the passed-in cwd.
- [x] **A2** `SessionStore.gatherTranscripts`: `decodeProjectDir` demoted to fallback (comments; reader now prefers record cwd). FSEvents/poll untouched.
- [x] **A3** AC-D1.1 / AC-D1.4 in `TranscriptReaderTests`; AC-D1.2 in new `SessionMerger+JoinTests`. (RED→GREEN seen on AC-D1.1.)
- [x] ◇ **C1-A:** 47 tests green in clone. *(AC-D1.3 → Phase 3, now live-testable in the running app.)*

**⇄ Track B · D3 — PID-reuse guard** — commit `7eb539e`
- [x] **B1** `RegistryReader`: `SessionFile.startedAt: Int?` (epoch ms) → `RegistryEntry.startedAt: Date?`; absent → nil.
- [x] **B2** `ProcessScanner`: injectable `resolveStartTime` seam; prod `ps -o etime=` → `now − parseElapsed` (pure, TZ-free, unit-tested).
- [x] **B3** `SessionMerger`: `pidReuseTolerance = 120` + pure `bindIsTrustworthy`; gates Pass 1 only; confident mismatch ⇒ drop bind, no Pass-2 re-claim (DD-4).
- [x] **B4** AC-D3.4 + no-startedAt in `RegistryReaderTests`; AC-D3.1/3.2/3.3 + `parseElapsed` in new `SessionMerger+ReuseTests`.
- [x] ◇ **C1-B:** 63 tests green in clone.

**⇄ Track C · D2 — status-absent coverage** — commit `031741a`
- [x] **C1** New `SessionMerger+StatusTests` (12): fresh/stalled pending; `end_turn`/`stop_sequence`/`max_tokens`→concluded; user fresh/stalled; 119/120/121 s boundary; dead-session anchor. — *AC-D2.1–2.4*
- [x] ◇ **C1-C:** 55 tests green in clone. **120 s threshold validated at unit level** (strict `>`).

### Phase 2 · Integration — SERIAL ✓
- [x] **2.1** Reconverged all three (disjoint copy), per-track build+test+commit in D1→D3→D2 order.
- [x] ◇ **C2:** whole suite green — **79 tests in 10 suites**, `swift build` clean, no new warnings.

### Phase 3 · Validate + commit — SERIAL · manual · human-in-loop
- [~] **3.1** App rebuilt + relaunched (Phase-1 binary) for live toolbar / `--print` check: AC-D1.3 (full hyphenated names), D2 threshold, D3 eyeball. **In the user's hands now.**
- [x] **3.2** Per-track commits on branch `dedup-hardening-v0.1` (D1→D3→D2). *(Handover findings append: optional follow-up after live results.)*
- [~] ◇ **C3 (DoD):** build+tests green ✓ · `~/.claude` read-only ✓ · no new perms ✓ · 79 tests (43 intact) ✓ · **awaiting live toolbar/`--print` confirmation.**

---

**Parallelism at a glance:** Phase 0 serial → **Phase 1 fans out (A ∥ B ∥ C)** → Phase 2 serial → Phase 3 serial.
Start **B** first (long pole). 2-agent option: A + B, fold C into Phase 2.
