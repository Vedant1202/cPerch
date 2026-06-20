# cPerch — Release pipeline (v0.6) — todo

Tracks [release-pipeline-plan.md](release-pipeline-plan.md) · spec
[release-pipeline-v0.6.md](../docs/specs/release-pipeline-v0.6.md). Branch `release-pipeline-v0.6` off
`main` (sync to `origin/main` first). **Not started.**

## Phase 0 — Docs & config ✅
- [x] **T0.1** `CHANGELOG.md` (new): Keep a Changelog; `[Unreleased]` (0.6.0 help batch) + backfilled `[0.5.0]`…`[0.1.0]`
- [x] **T0.2** `build.sh` `VERSION` `0.5.0` → `0.6.0`
- [x] **T0.3** README **Download / Install** section: Releases link + macOS 15 "Open Anyway" steps
- [x] **C0 checkpoint:** `swift build` + `./scripts/test.sh` (**143**) + `./build.sh` green; bundle = **0.6.0**. Committed.

## Phase 1 — release.sh
- [ ] **T1.1** `scripts/release.sh X.Y.Z` (new, +x): validate (SemVer · on main · clean · up-to-date · tag absent) → bump VERSION → stamp+reseed CHANGELOG → commit `release: vX.Y.Z` → annotated tag → push; `--dry-run` previews + skips branch/remote guards
- [ ] **C1 checkpoint:** `scripts/release.sh 0.6.0 --dry-run` shows correct edits + tag, mutates nothing; bad arg / existing tag aborts; `shellcheck` clean (if available)

## Phase 2 — release workflow
- [ ] **T2.1** `.github/workflows/release.yml` (new): on `v*` tags · `macos-14` · `contents: write`; `build.sh` → `ditto` zip + `hdiutil` DMG (app + /Applications symlink) → `awk` changelog section → `softprops/action-gh-release@v2` (both artifacts + notes), `GITHUB_TOKEN` only
- [ ] **C2 checkpoint:** YAML valid / `actionlint` clean; review matches spec. **Open PR `release-pipeline-v0.6 → main` and merge** (workflow must be on main).

## Phase 3 — Cut v0.6.0 (live)
- [ ] Run `scripts/release.sh 0.6.0` on merged `main` → commit + `v0.6.0` tag pushed
- [ ] `release.yml` run succeeds (macOS) and publishes
- [ ] Release `cPerch 0.6.0` has the 0.6.0 changelog as notes + `CPerch-0.6.0.zip` + `CPerch-0.6.0.dmg`
- [ ] DMG mounts (app + Applications alias); zip expands to a launchable `CPerch.app` (after "Open Anyway")
- [ ] Fix-forward if the first CI run trips; re-tag. Then refresh handover.
</content>
