# cPerch — Group sessions by host (v0.3 spec)

*A focused refinement of Settings → View → "Group by source" (shipped in "Settings 2/3"), prompted by:
"by source I meant if it was the Claude app or the terminal." **Decisions locked 2026-06-18 —
implementing.** Q1 = entrypoint-accurate; groups = **Terminal / Claude App / Background / Other** (own
groups); `source` refined as a single concept.*

## 1. Problem
"Group by source" groups by `Session.source` (`SessionSource`: `.cli` / `.desktop` / `.background` /
`.unknown`), which `SessionMerger.resolveSource` **derives** from the registry `kind` + whether a `tty`
resolved, and labels **CLI / Desktop / Background / Other**. The intent was **Terminal vs Claude app**.
Two gaps:
1. **Labels** don't read "Terminal" / "Claude App".
2. **Detection is derived and imperfect** — `.cli` vs `.desktop` hinges on tty resolution, so a *terminal*
   session launched via the desktop-bundled `claude` binary (no tty) is mis-classified as Desktop. (This
   very session reads `host=desktop`.)

## 2. Key insight (makes the fix accurate)
The registry `<pid>.json` carries a **direct `entrypoint`** field — `"cli"` (terminal) vs `"claude-desktop"`
(Claude app) — confirmed in fixtures **and** live data (`claude-desktop|interactive`, `cli|bg`). cPerch
currently **ignores** it. Using it classifies Terminal-vs-Claude-App directly, instead of inferring from tty.

## 3. Proposed change
- **Decode `entrypoint`** onto `RegistryEntry` (additive, nil-default — same pattern as `startedAt`).
- **Classify host primarily from `entrypoint`** (`cli` → terminal, `claude-desktop` → Claude app), falling
  back to today's host-derived logic when `entrypoint` is absent (older CLIs).
- **Relabel** the grouped view: **Terminal / Claude App / Background / Other** (pending Q1).

## 4. Decisions (locked 2026-06-18) ✓
- **Q1 — Approach:** **entrypoint-accurate** — `entrypoint` (`cli` → Terminal, `claude-desktop` → Claude
  App), falling back to the derived logic when absent.
- **Q2 — One concept:** `SessionSource` / `resolveSource` refined to be entrypoint-driven (single notion).
- **Q3 — Groups:** **own groups** — **Terminal / Claude App / Background / Other**.
- **Q4 — Scope:** the `source` concept refined globally (the grouping consumes it); no separate UI surface.
  A `bg`-kind worker stays Background even with a `cli` entrypoint.

## 5. Acceptance criteria (once decided)
- **AC1** a registry `entrypoint:"cli"` session groups under **Terminal**; `"claude-desktop"` under
  **Claude App** — regardless of tty resolution.
- **AC2** absent `entrypoint` → falls back to the current host-derived classification (no regression for
  older data).
- **AC3** grouped headers show the agreed labels; the classifier + grouping stay pure + unit-tested.

## 6. Implementation note
Additive + pure-testable, same shape as v0.1/v0.2: decode `entrypoint` (Phase-0 contract), refine the
classifier + labels, add tests. Small — but specced first because the *taxonomy* was the open question.
