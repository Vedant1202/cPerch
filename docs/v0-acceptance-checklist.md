# cPerch v0 — acceptance checklist

Automated/headless checks are **green**: `swift build`, `./scripts/test.sh` (39 tests),
`swift run CPerchApp --print` (clean dedup), idle footprint ≈49 MB / ~1% CPU.

These are the **usage-dependent** checks for daily-driver sign-off — run them as you use it.

**Build & run:** `./build.sh && open dist/CPerch.app`

## Manual checks
- [ ] **Bar dot** reflects state: 🟠 when a session needs you, 🔵 when one's working, dim when all idle.
- [ ] **Roster** (click the dot): sessions needs-you-first; each shows project, latest message, and — for needs-input — a "blocked Nm" timer.
- [ ] **Terminal session** — start `claude` in a Terminal/iTerm tab → it shows as running with the right project.
- [ ] **Jump (terminal)** — click Jump → focuses the *exact* tab. First time: grant the one-time macOS **Automation** prompt. Never opens a duplicate.
- [ ] **Jump (desktop)** — click Jump on a Claude-desktop session → brings the Claude window forward, no duplicate.
- [ ] **Calm notification** — let a session block (permission/question) → exactly one banner (DND off); none under Do-Not-Disturb (dot still goes orange).
- [ ] **Multi-session** — run several at once → no duplicate rows, no ghosts; concluded ones drop off after ~3h.
- [ ] **Footprint** stays modest with several sessions open.

## Known v0 limitations (by design)
- needs-input is **exact** for recent CLI sessions (registry `waiting`); **approximate** for the older desktop app (no `status` field).
- A **concluded** session whose process is gone can't be "jumped" (no live window) — it's informational.
- **Exact-chat** desktop deep-link is a fast-follow (decisions D10); v0 activates the Claude app.
- **cwd collision** (two unregistered sessions in one dir) degrades gracefully — documented, rare.
