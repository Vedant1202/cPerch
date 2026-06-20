# cPerch — Release pipeline (v0.6 spec)

**Status:** open questions resolved via `/interview-me` (2026-06-19) — scope locked. Ready to implement
**on your go-ahead**.
**Date:** 2026-06-19 · **Branch target:** new `release-pipeline-v0.6` off `main` (post-v0.6 merge).
**Origin:** confirmed intent [docs/intent/release.md](../intent/release.md).

> This batch is **tooling + docs only** — no app source changes. `CPerchCore`/`CPerchApp` are untouched.

---

## 1. Objective

Make cPerch releasable with **one command**: `scripts/release.sh X.Y.Z` cuts a versioned GitHub Release
with curated changelog notes and two downloadable artifacts — a **zip** and a **DMG** of the (unsigned)
app — built reproducibly by CI.

| # | Deliverable | One-liner |
|---|---|---|
| **D1** | `CHANGELOG.md` | Keep a Changelog format, backfilled v0.1→v0.6, `[Unreleased]` on top. |
| **D2** | Version bump | `build.sh` `VERSION` `0.5.0 → 0.6.0`. |
| **D3** | `scripts/release.sh X.Y.Z` | Bump VERSION, stamp the changelog, commit, tag, push (triggers CI). |
| **D4** | `.github/workflows/release.yml` | Tag-triggered macOS build → zip + DMG → GitHub Release. |
| **D5** | README **Download / Install** | Releases link + macOS "Open Anyway" steps. |

---

## 2. Boundaries

- **Unsigned / ad-hoc only.** No Apple Developer ID, so artifacts aren't notarized; both the README and
  the release notes carry the macOS "Open Anyway" steps. The pipeline is structured so a future
  Developer-ID sign + notarize step slots into `release.yml` without reshaping it.
- **No app behavior change.** This is release tooling + docs; `CPerchCore`/`CPerchApp` stay as-is, so the
  app remains fully local, no network, no new TCC permission, read-only on `~/.claude`.
- **No new secrets.** Release creation uses the workflow's built-in `GITHUB_TOKEN` (`contents: write`).
  (Notarization later would add `Developer ID` + `notarytool` secrets — out of scope now.)
- **Reproducible, not machine-bound.** The build/publish happens in CI on a macOS runner, not on a dev's
  Mac; the local command only prepares the version/changelog and pushes the tag.

---

## 3. Commands

- **Cut a release:** `scripts/release.sh 0.6.0` (the one command). Supports `--dry-run` to preview the
  version/changelog edits and the tag without committing or pushing.
- Existing toolchain unchanged: `swift build` · `./scripts/test.sh` (still **143**, no source changes) ·
  `./build.sh` (now stamps `0.6.0`).

---

## 4. D1 — CHANGELOG.md (Keep a Changelog)

**Decision (locked):** a hand-curated `CHANGELOG.md` in [Keep a Changelog](https://keepachangelog.com)
format, SemVer headings, newest first, with an `[Unreleased]` section at the top. Backfill the project's
history from the handover docs so the first published release tells the whole story:

| Heading | Maps to | Highlights |
|---|---|---|
| `[0.6.0]` | help batch | In-app Help ("?" → icons/shortcut/settings/accessibility/privacy/report/about), first-run hint, Copy diagnostics, version 0.6.0. |
| `[0.5.0]` | accessibility | Shape-coded status, baseline contrast fix, high-contrast mode, VoiceOver, reduce motion/transparency, Accessibility tab, white menu-bar plate. |
| `[0.4.0]` | daily-driver | Launch at login, global hotkey ⌘⌥`, richer menu bar, error/completion notifications. |
| `[0.3.0]` | group-by-host etc. | Group by host (Terminal vs Claude App), over-counting fix, configurable retention. |
| `[0.2.0]` | roster & merge quality | Waiting-vs-done status, AI-title naming, preview fallback, cwd/registry merge fixes, Settings window. |
| `[0.1.0]` | v0 + dedup-hardening | Initial detection (process + registry + transcript), aggregate dot, roster, jump, calm notifications; dedup/PID-reuse hardening. |

`release.sh` (D3) converts `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD` at release time and reseeds a fresh
empty `[Unreleased]`. `release.yml` (D4) extracts the matching version section as the GitHub Release body.

**Acceptance:** `CHANGELOG.md` parses as Keep a Changelog; every released version has a heading; the
0.6.0 section reflects the help batch.

---

## 5. D2 — Version bump

**Decision (locked):** `build.sh` `VERSION` → **`0.6.0`** (it lagged at `0.5.0`). About + the bundle's
`CFBundleShortVersionString`/`CFBundleVersion` then read `0.6.0`. From here, `release.sh` owns `VERSION`.

**Acceptance:** a fresh `./build.sh` yields `dist/CPerch.app` with `CFBundleShortVersionString == 0.6.0`.

---

## 6. D3 — scripts/release.sh

**Decision (locked):** `scripts/release.sh X.Y.Z` (SemVer arg, no `v` prefix). Steps, fail-fast:

1. **Validate:** arg matches `^[0-9]+\.[0-9]+\.[0-9]+$`; on `main`; working tree clean; `git fetch` then
   up-to-date with `origin/main`; tag `vX.Y.Z` doesn't already exist.
2. **Bump** `VERSION="X.Y.Z"` in `build.sh` (in-place, anchored on the `VERSION=` line).
3. **Stamp** `CHANGELOG.md`: `## [Unreleased]` → `## [X.Y.Z] - <today>`, insert a new empty
   `## [Unreleased]` above it.
4. **Commit** `release: vX.Y.Z` (build.sh + CHANGELOG).
5. **Tag** annotated `git tag -a vX.Y.Z -m "cPerch X.Y.Z"`.
6. **Push** `git push origin main` then `git push origin vX.Y.Z` → the tag push triggers D4.

`--dry-run` prints the diff it *would* make and the tag, and exits before step 4. The date is the local
date (the script runs on your Mac, where `date` is allowed).

**Acceptance:** on a clean `main`, `scripts/release.sh 0.6.0` produces the version+changelog commit, the
`v0.6.0` tag, and pushes both; `--dry-run` changes nothing. Re-running for an existing tag aborts with a
clear message.

---

## 7. D4 — .github/workflows/release.yml

**Decision (locked):** trigger on `push: tags: ['v*']`, `runs-on: macos-14`, `permissions: contents: write`.

1. `actions/checkout@v5`.
2. `VERSION="${GITHUB_REF_NAME#v}"`.
3. `./build.sh` → `dist/CPerch.app`.
4. **Zip:** `ditto -c -k --sequesterRsrc --keepParent dist/CPerch.app "CPerch-$VERSION.zip"` (ditto, not
   `zip`, to preserve the bundle's symlinks/metadata).
5. **DMG (zero external deps, `hdiutil`):** stage a temp dir holding `CPerch.app` + a symlink to
   `/Applications`, then `hdiutil create -volname "cPerch" -srcfolder <stage> -fs HFS+ -format UDZO -ov
   "CPerch-$VERSION.dmg"`. (No `create-dmg`/Homebrew install needed → robust.)
6. **Notes:** `awk`-extract the `## [$VERSION]` section from `CHANGELOG.md` into `notes.md`.
7. **Publish:** `softprops/action-gh-release@v2` with `tag_name`, `name: cPerch $VERSION`,
   `body_path: notes.md`, `files:` both artifacts.

**Acceptance:** pushing `vX.Y.Z` produces a published Release `cPerch X.Y.Z` with the changelog section as
notes and both `CPerch-X.Y.Z.zip` + `.dmg` attached; the DMG mounts and shows the app + Applications
alias; the zip expands to a runnable `CPerch.app`.
**Note:** the macOS CI build is unverified until the first real tag — the first `v0.6.0` run may need a
small fix (accepted).

---

## 8. D5 — README Download / Install

**Decision (locked):** add a **Download** subsection above "Build from source":
- Link to the [latest release](https://github.com/Vedant1202/cPerch/releases/latest); pick the **DMG**
  (drag cPerch to Applications) or the **zip**.
- **First run (unsigned):** because cPerch isn't notarized yet, macOS will block the first open. Steps for
  macOS 15+: try to open it, dismiss the dialog, then **System Settings → Privacy & Security → scroll down
  → "Open Anyway"**. Note this is a one-time step and a notarized build is planned.

**Acceptance:** the README explains where to download and exactly how to get past Gatekeeper on current macOS.

---

## 9. Project structure (files touched)

| Deliverable | New / edited |
|---|---|
| D1 | `CHANGELOG.md` (new) |
| D2 | `build.sh` (VERSION) |
| D3 | `scripts/release.sh` (new, `chmod +x`) |
| D4 | `.github/workflows/release.yml` (new) |
| D5 | `README.md` (Download section) |

**No source files** (`Sources/**`, tests) change. `CPerchCore`/`CPerchApp` untouched.

---

## 10. Testing strategy

- No unit tests (tooling/docs only); `./scripts/test.sh` stays green at **143** as a regression guard.
- `release.sh` ships with `--dry-run` and is validated against a clean tree before the real run.
- `release.yml` is verified by the first live tag (`v0.6.0`); the run is observed end-to-end and any fix
  is a follow-up commit before re-tagging.
- Manual: download both artifacts from the resulting Release; confirm the DMG mounts and the app launches
  after the "Open Anyway" step.

---

## 11. Open questions — RESOLVED (via /interview-me, 2026-06-19)

- [x] **Signing:** unsigned / ad-hoc — no Apple Developer ID. *(your call)*
- [x] **Distribution:** GitHub Releases with **zip + DMG**. *(your call)*
- [x] **Build/publish location:** **hybrid** — local `release.sh` tags/pushes; CI builds + publishes. *(your call)*
- [x] **Versioning / first release:** SemVer; first tag **v0.6.0**; reconcile `build.sh` VERSION. *(your call)*
- [x] **Changelog:** hand-curated **Keep a Changelog**, backfilled v0.1→v0.6. *(your call)*
- [x] **Deferred:** notarization, Homebrew (official + self tap), 1.0.0 — until the $99 program. *(your call)*

---

## 12. Proposed build order (after go-ahead)

1. **Phase 0:** `CHANGELOG.md` (D1) + `build.sh VERSION 0.6.0` (D2) + README Download section (D5). Docs;
   `swift build`/tests stay green.
2. **Phase 1:** `scripts/release.sh` (D3) — verified with `--dry-run` (no push).
3. **Phase 2:** `.github/workflows/release.yml` (D4).
4. **Phase 3 (the live release):** run `scripts/release.sh 0.6.0` → watch the workflow → confirm the
   `v0.6.0` Release has notes + both artifacts. Fix-forward if the first CI run trips, then re-tag.

---

## 13. Acceptance criteria (whole batch)

- `scripts/release.sh 0.6.0` (on a clean `main`) bumps VERSION, stamps + reseeds the changelog, commits,
  tags `v0.6.0`, and pushes — `--dry-run` does nothing.
- The tag triggers CI which publishes a **`cPerch 0.6.0`** Release with the 0.6.0 changelog as notes and
  `CPerch-0.6.0.zip` + `CPerch-0.6.0.dmg` attached.
- The DMG mounts (app + Applications alias); the zip expands to a launchable `CPerch.app` (after "Open
  Anyway").
- README documents download + the Gatekeeper "Open Anyway" steps. No app source changed; tests still 143;
  no network/secrets/permissions added.
</content>
