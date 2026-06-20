# cPerch — Release pipeline (v0.6) — plan

Implements [docs/specs/release-pipeline-v0.6.md](../docs/specs/release-pipeline-v0.6.md) (scope locked via
`/interview-me`). **Branch:** new `release-pipeline-v0.6` off `main` (sync to `origin/main` = `4744c18`
first). Tooling + docs only — **no app source changes**. Todo:
[release-pipeline-todo.md](release-pipeline-todo.md).

> Commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## Dependency graph

```
Phase 0 — docs/config (independent edits)
  D1 CHANGELOG.md        D2 build.sh VERSION 0.6.0        D5 README Download section
        │                        │
        └──────────┬─────────────┘  (release.sh edits both files; needs their format)
                   ▼
Phase 1   D3 scripts/release.sh   ──(stamps D1, bumps D2)
                   ▼
Phase 2   D4 .github/workflows/release.yml   ──(reads D1 for notes; runs build.sh)
                   ▼
        merge release-pipeline-v0.6 → main   (release.yml must be ON main for the tag to trigger it)
                   ▼
Phase 3   run scripts/release.sh 0.6.0  →  CI builds zip+DMG → publishes the v0.6.0 Release
```

**Serial, not a fan-out.** Small, tooling-only, and the steps build on each other (`release.sh` edits the
CHANGELOG/VERSION; `release.yml` reads the CHANGELOG; the live cut needs everything on `main`). The
real end-to-end path is exercised only in **Phase 3**.

**Key sequencing rule:** the `release.yml` workflow only runs if it exists at the tagged commit, so the
pipeline must be **merged to `main` before** `release.sh 0.6.0` is run.

---

## Phase 0 — Docs & config

**T0.1 — `CHANGELOG.md` (new)** — Keep a Changelog; `[Unreleased]` + backfilled `[0.6.0]`…`[0.1.0]` per
spec §4 (highlights from the handover chain).
- **AC:** valid Keep-a-Changelog structure; every version 0.1.0–0.6.0 has a dated heading; 0.6.0 = the
  help batch. **Verify:** read-through; headings match `## [x.y.z] - YYYY-MM-DD`.

**T0.2 — `build.sh` VERSION → `0.6.0`.**
- **AC:** `./build.sh` yields `dist/CPerch.app` with `CFBundleShortVersionString == 0.6.0`.
  **Verify:** `./build.sh` + `PlistBuddy -c "Print :CFBundleShortVersionString"`.

**T0.3 — README **Download / Install** section** (spec §8) — Releases link + macOS 15 "Open Anyway" steps.
- **AC:** explains DMG vs zip and the exact Gatekeeper override. **Verify:** read-through.

> **Checkpoint C0:** `swift build` + `./scripts/test.sh` (**143**, unchanged) + `./build.sh` green; bundle
> reports `0.6.0`.

---

## Phase 1 — `scripts/release.sh` (D3)

**T1.1 — `scripts/release.sh X.Y.Z`** (new, `chmod +x`), per spec §6: validate (SemVer arg, on `main`,
clean tree, up-to-date, tag absent) → bump `build.sh` VERSION → stamp + reseed CHANGELOG → commit
`release: vX.Y.Z` → annotated tag → push branch + tag. `--dry-run` previews the file edits and the tag
without committing/pushing and **skips the branch/remote guards** so it can be previewed off `main`.
- **AC:** `scripts/release.sh 0.6.0 --dry-run` prints the intended VERSION + CHANGELOG diff and the tag,
  mutates nothing; a non-SemVer arg or an existing tag aborts with a clear message.
- **Verify:** run `--dry-run` on the branch; `shellcheck scripts/release.sh` (if available); `git status`
  clean after dry-run.

> **Checkpoint C1:** dry-run output correct; nothing committed/pushed by it.

---

## Phase 2 — `.github/workflows/release.yml` (D4)

**T2.1 — release workflow** (new), per spec §7: `on: push: tags: ['v*']`, `runs-on: macos-14`,
`permissions: contents: write`; checkout → `./build.sh` → `ditto` zip + `hdiutil` DMG (app + Applications
symlink) → `awk`-extract the `[$VERSION]` CHANGELOG section → `softprops/action-gh-release@v2` with both
artifacts + notes.
- **AC:** YAML is valid; logic matches spec; uses only `GITHUB_TOKEN` (no secrets). **Verify:** review +
  `actionlint` (if available); full validation deferred to Phase 3 (live).

> **Checkpoint C2:** workflow lints/reviews clean. **Then open a PR `release-pipeline-v0.6 → main` and
> merge** (so the workflow is on `main`).

---

## Phase 3 — Cut v0.6.0 (the live, end-to-end test)

On the merged `main`:
1. `scripts/release.sh 0.6.0` → version+changelog commit, `v0.6.0` tag, pushed.
2. Watch the `release.yml` run (macOS) → it must succeed and publish.
3. **Verify the Release:** `cPerch 0.6.0` exists with the 0.6.0 changelog as notes and
   `CPerch-0.6.0.zip` + `CPerch-0.6.0.dmg` attached; DMG mounts (app + Applications alias); zip expands to
   a launchable `CPerch.app` (after the "Open Anyway" step).
- **Fix-forward if needed:** the first macOS CI run is unverified; if it trips, fix the workflow on `main`,
  delete the failed tag/release, and re-run `release.sh 0.6.0` (or just re-push the tag).

---

## File ownership

| File | Phase |
|---|---|
| `CHANGELOG.md` (new) | 0 |
| `build.sh` | 0 |
| `README.md` | 0 |
| `scripts/release.sh` (new) | 1 |
| `.github/workflows/release.yml` (new) | 2 |

**Untouched:** all of `Sources/**`, `Tests/**` (`CPerchCore`/`CPerchApp` unchanged; tests stay 143).
</content>
