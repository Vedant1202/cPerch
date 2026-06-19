# cPerch — Session over-counting (one conversation, many rows) — spec

*One Claude conversation shows as multiple roster rows. **Implementation NOT authorized** — this spec
lays out the mechanism (with live evidence) and the open questions in detail, for sign-off first
(spec-before-implement, per `~/.claude/CLAUDE.md`).*

- **Status:** reviewed 2026-06-18 — **decisions:** C2 (drop wrapper/parent procs) + B1 (collapse
  resumed/forked lineage); Pass-2 kept (A2). Implementing.
- **Severity:** medium UX (the headline app promise is a clean roster; over-counting undermines it).
- **Relation:** this is the **D7** gap ("Pass-2 N:N pairing is arbitrary", handover-v0.md) made concrete,
  plus a multi-transcript-per-conversation wrinkle.

## 1. Objective
A single Claude conversation should occupy **one** roster row (or at most one *live* row), even when it
has multiple OS processes and multiple transcript files in the same project directory.

## 2. Evidence (live, this machine)
`--print` showed **3 rows, all `claude-toolbar-mac`**, for what is really **one** conversation. The `ps`
tree explains it:

```
pid 1275   /Applications/Claude.app/Contents/MacOS/Claude                          ← desktop app
 └─ 76505  …/Helpers/disclaimer  …/claude-code/2.1.170/…/claude  --resume e8a02c8d --fork-session …   ← launcher (parent), UNREGISTERED
     └─ 76506  …/claude-code/2.1.170/…/claude  --resume e8a02c8d --fork-session …                     ← real session (child), REGISTERED → 4f82278b, entrypoint=claude-desktop
```

- Registry has **76506 → sessionId `4f82278b`** (the forked-to session). **76505 has no registry file.**
- Both 76505 and 76506 pass `ProcessScanner.isGenuineClaudeSession` (each cmdline names the lowercase
  `claude` binary — the `disclaimer` launcher is *deliberately* kept today; see handover).
- 3 `claude-toolbar-mac` transcripts fall inside the 3 h retention window (`4f82278b`, `e8a02c8d`, …).

### How the phantom row is born
1. **Pass 1** binds the registered process `76506` → its session `4f82278b` (Claude App, live). ✅ correct.
2. **Pass 2** takes the *unregistered* `76505` and binds it to the most-recent **unbound** transcript in
   the same cwd. `4f82278b` is taken, so it grabs the older **`e8a02c8d`** transcript → that session now
   reports a **live** pid → shows "running"/"needsInput". With no registry entry, its source is unknown →
   **"Other"**. **← the phantom.**
3. Separately, older transcripts of the same conversation linger in the 3 h retention window as concluded
   rows.

So three contributing problems:
- **P1 — wrapper process counted.** The `disclaimer` launcher (76505) is a *parent* of the real claude
  (76506); both are counted as sessions.
- **P2 — Pass-2 mis-binding.** An unregistered process attaches liveness to an *arbitrary older* transcript
  in the cwd (D7).
- **P3 — multi-transcript lineage.** A resumed/forked conversation (`e8a02c8d` → `4f82278b`) leaves several
  transcripts in one cwd; cPerch treats each as its own session.

## 3. What is NOT the bug
The `sessionId` dedup is **working** — distinct sessionIds are correctly kept distinct (two *genuinely
different* sessions in one project should still be two rows; the "4m ago / 17m ago" labels disambiguate
them). The defect is at a higher level: **the same conversation** is counted more than once.

## 4. Open questions — in detail, with examples

### Q-A · Should an *unregistered* process confer liveness via the Pass-2 cwd match at all?
Pass 2 exists so a session that **doesn't write a registry file** still shows "running". The question is
whether that's still needed, given it's the vector for the phantom.

- **A1 — Drop Pass-2 for unregistered processes entirely.** Only registered processes (Pass 1) make a
  session live.
  - *Kills:* the 76505 phantom, and any unregistered-process phantom.
  - *Example it breaks:* a real terminal session on an **older Claude CLI that never writes
    `~/.claude/sessions/<pid>.json`** — it would show **concluded while actually running** (a missed
    "needs input", the worst failure per CLAUDE.md). On v2.1.x sessions *do* register, so the blast radius
    is old CLIs / a pre-registry-write race only.
- **A2 — Keep Pass-2, but remove wrapper processes first (see Q-C).** Once 76505 is filtered out, the only
  remaining claude process is the *registered* 76506 (handled by Pass 1) — there's no unregistered spare
  left to mis-bind. Legit unregistered sessions keep their Pass-2 liveness.
  - *Example it preserves:* an old-CLI terminal session (one process, unregistered, no child) still binds
    its own transcript via cwd → shows running. ✅
- **A3 — Keep Pass-2, but forbid binding an OLDER transcript when a newer transcript in the same cwd is
  already live.** Surgical: the spare can't grab `e8a02c8d` while `4f82278b` (same cwd) is live.
  - *Trade-off:* narrower than A2; doesn't remove the wrapper from other surfaces.

**Recommendation: A2** (filter wrappers — Q-C — so Pass-2 stays safe for genuine unregistered sessions),
optionally + A3 as belt-and-suspenders.

### Q-B · Should cPerch collapse multiple transcripts of the *same conversation* into one row?
A resumed/forked conversation (`e8a02c8d` → `4f82278b`) leaves an ancestor transcript that lingers. Even
after the phantom is gone, you may still see the **current** session *and* the **resumed-from ancestor**
(as a concluded row). Collapse them?

Lineage-detection options:
- **B1 — Process cmdline `--resume <id>` / `--fork-session`.** The live process literally states its
  ancestor: `76506`'s cmdline has `--resume e8a02c8d`, and its registry session is `4f82278b` ⇒
  `e8a02c8d` and `4f82278b` are one lineage. `ProcessScanner` would capture the `--resume` id from the
  cmdline (it currently captures pid/ppid/tty/cwd/cpu only).
  - *Pro:* direct, already in the data, unambiguous for live forks.
  - *Con:* only available while a process is alive (a fully-concluded ancestor with no live process can't
    be linked this way); cmdline parsing is fragile.
- **B2 — Transcript resume marker (`summary` record / `leafUuid`).** A resumed transcript can carry a
  `summary`-type record whose `leafUuid` points at the prior session's last message.
  - *Caveat from live data:* `4f82278b`'s first records are `mode` / `queue-operation` (meta), **not** a
    `summary` — for `--fork-session` the marker may be absent or elsewhere. Needs verification before
    relying on it.
  - *Pro:* works for concluded sessions too (no live process required).
- **B3 — `parentUuid` chains.** Per-record `parentUuid` links messages *within* a transcript, not *across*
  sessions — not a lineage signal. ✗

What "collapse" means (if we do it):
- Keep the **newest** session in a lineage (`4f82278b`), **hide** the resumed-from ancestor(s)
  (`e8a02c8d`). Example result: one Claude-App row instead of three.
- *Alternative:* show one row with a small "resumed" affordance.

**Recommendation:** **B1 now** (cmdline `--resume` link for live lineages — solves the visible case),
**defer B2** to a follow-up for concluded-ancestor collapse. *Or* defer Q-B entirely if Q-A/Q-C already
make the roster acceptable (the ancestor would then show only as a single concluded row in retention).

### Q-C · Should `isGenuineClaudeSession` (or the merge) drop wrapper/parent processes?
The `disclaimer` launcher (76505) is a *parent* of the real claude (76506). Both are counted.

- **C1 — Exclude `disclaimer` by path.** Add `…/Claude.app/Contents/Helpers/disclaimer` to the
  desktop-marker exclusions.
  - *Pro:* targeted, one line. *Con:* brittle — only this one wrapper; the handover *kept* `disclaimer`
    on purpose (its cmdline names the real binary), so blanket-excluding it risks dropping a session on
    setups where `disclaimer` is the only match (unlikely, but unverified).
- **C2 — Drop any genuine-claude process that is the PARENT of another genuine-claude process (keep the
  leaf).** `76506.ppid == 76505` and both are claude ⇒ `76505` is a launcher ⇒ drop it; keep the leaf
  `76506`. `ProcessRecord` already carries `ppid`, so this is pure + testable.
  - *Pro:* general — handles any wrapper/relauncher chain, not just `disclaimer`. *Con:* a (rare) case
    where a real session is the parent of a *subagent* claude process — but subagents run with
    `--bg-pty`/`isSidechain` and are already excluded, so the leaf is the user session.
  - *Example:* terminal `claude` with no child claude → it's a leaf → kept. ✅
- **C3 — Prefer the registered sibling.** Among claude processes in one ppid chain, keep the one with a
  registry entry; drop unregistered ancestors. (Similar effect to C2, via the registry instead of ppid.)

**Recommendation: C2** (drop parent-of-claude, keep the leaf) — it removes the unregistered spare at the
source, which also makes Q-A moot (no spare to mis-bind) and is the cleanest general rule.

## 5. Decisions (locked 2026-06-18) ✓
1. **Primary fix:** **C2** — drop any genuine-claude process that is the *parent* of another genuine-claude
   process (keep the leaf). *Not* A3 (it would wrongly conclude a second real agent in the same repo).
2. **Lineage collapse:** **B1** — capture `--resume <id>` from the live process cmdline and drop the
   resumed-from **ancestor** session, so a forked conversation is one row.
3. **Scope:** one row per (live) conversation. **Pass-2 kept (A2)** for genuine unregistered sessions.

## 6. Proposed approach (pending the above)
Likely **C2 + A2** as the core (kills the phantom; keeps liveness for genuine unregistered sessions),
with **B1** optional for full one-row-per-conversation. All additive + pure-testable in `CPerchCore`
(`ProcessScanner` leaf-filtering; optional `--resume` capture on `ProcessRecord`; merge unchanged or a
small Pass-2 guard). Same contract-first, unit-tested pattern as v0.1/v0.2.

## 7. Acceptance criteria (once decided)
- **AC1** Given a parent claude process (76505) and its registered child (76506) in one cwd, the merge
  yields **one** live session (the child's), **no** phantom "Other" row.
- **AC2** A genuine **unregistered** single (leaf) session still shows live (no liveness regression) —
  *(if A2 chosen)*.
- **AC3** *(if B1 chosen)* a resumed/forked conversation (`--resume X` → registered `Y`) shows **one** row
  (the newest), not one per transcript.
- **AC4** Two *genuinely distinct* sessions in the same project remain **two** rows (no over-collapsing).
- Pure helpers (`leaf-process` filter, lineage link) unit-tested; full suite stays green.

## 8. Boundaries
Read-only on `~/.claude`; `CPerchCore` Foundation-only; additive contract changes only; no new perms.
**Don't over-collapse** (AC4) — distinct conversations must stay distinct.

## 9. Implemented (2026-06-18) + residual
**Shipped:** C2 (leaf-only processes — `ProcessScanner.leafRows`) + B1 (collapse the *immediate* `--resume`
ancestor — `ProcessScanner.parseResumedFrom` + a `SessionMerger` supersede step). 123 tests; verified on
live data — the **phantom-live wrapper row is gone** and `e8a02c8d` (the direct resumed-from) is collapsed.

**Residual — multi-level resume chains aren't fully collapsed.** Live: `02338efe → e8a02c8d → 4f82278b`
(current). B1 reads `--resume` from the *live* process, which names only the **immediate** parent
(`e8a02c8d`), so the **grandparent `02338efe`** still shows as a single concluded row (no live process to
read a `--resume` from). Collapsing the full chain needs **B2** (transcript-level lineage — a resumed-from
/ `summary` / `leafUuid` marker *inside* each transcript), which has its own open question (no such marker
was at the head of `4f82278b`) and is **deferred**. The grandparent also ages out of the 3 h retention
window on its own.
