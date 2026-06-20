# cPerch — post-v0 handover (v0.5 → v0.6 + first release)

*Picks up after [handover-v0.5.md](handover-v0.5.md). Covers the **v0.6 in-app Help batch** and the
**release pipeline** that shipped cPerch's **first public release, v0.6.0**. Last updated 2026-06-19.*

## TL;DR
- **v0.6 — in-app Help** ([spec](specs/help-menu-v0.6.md)): a `questionmark.circle` "?" in the popover
  footer opens an in-app Help view (icon meanings + menu-bar note, the ⌘⌥` shortcut, a Settings overview,
  accessibility, a privacy link, "Report an issue" with **Copy diagnostics**, and **About**). A one-time
  first-run callout (tail + highlighted "?") points new users at it.
- **Release pipeline** ([spec](specs/release-pipeline-v0.6.md) · [intent](intent/release.md)): a
  `CHANGELOG.md` (Keep a Changelog), a one-command `scripts/release.sh`, and a tag-triggered macOS
  GitHub Actions workflow that builds + packages a **zip and a DMG** and publishes a GitHub Release.
- **Shipped: [v0.6.0](https://github.com/Vedant1202/cPerch/releases/tag/v0.6.0)** — unsigned zip + DMG on
  GitHub Releases. **143 tests.** `main` is current; both batches merged via PRs (#1, #2).

---

## v0.6 — in-app Help (what shipped)
| Piece | Where |
|---|---|
| Abstract `StatusSymbol` already existed (v0.5); Help renders the legend from it so it can't drift | [HelpView.swift](../Sources/CPerchApp/HelpView.swift) |
| `hasSeenHelpHint` pref + `diagnosticsText(appVersion:osVersion:)` (pure, tested) | [Preferences.swift](../Sources/CPerchCore/Preferences.swift), [Diagnostics.swift](../Sources/CPerchCore/Diagnostics.swift) |
| "?" footer button → in-popover Help (`@State`, survives refresh); first-run callout overlay | [RosterView.swift](../Sources/CPerchApp/RosterView.swift) |
| First-open hint trigger (controller-owned ~4.5 s TTL) + persist; `hosting.sizingOptions = .preferredContentSize` so the popover resizes for Help | [MenuBarController.swift](../Sources/CPerchApp/MenuBarController.swift) |

**Decisions:** Help lives **in the popover** (no separate window); links (privacy policy, GitHub issue
chooser) open in the browser with an `arrow.up.right` icon; Copy diagnostics is **version + macOS only**
(no identifiers); `VERSION` bumped to `0.6.0`. No network, no new TCC permission, `CPerchCore` stays
Foundation-only.

---

## The release pipeline (how to ship)
**One command** (after merging your changes to `main`):
```bash
git switch main && git pull --ff-only
# add notes under [Unreleased] in CHANGELOG.md, commit, then:
scripts/release.sh 0.7.0
```
`release.sh` validates (on `main`, clean, in sync, tag absent), bumps `build.sh` `VERSION`, stamps the
changelog (`[Unreleased]` → `[X.Y.Z] - date`, reseeds an empty `[Unreleased]`), commits `release: vX.Y.Z`,
annotated-tags, and pushes. The **tag push** triggers [`release.yml`](../.github/workflows/release.yml),
which on a **macOS runner** runs `build.sh`, packages a **zip** (`ditto`) + a **DMG** (`hdiutil`, app +
`/Applications` symlink), extracts the matching `CHANGELOG` section as the notes, and publishes the
Release via `softprops/action-gh-release`. `--dry-run` previews without mutating; `workflow_dispatch`
(with a `tag` input) re-runs against an existing tag for fix-forward.

### Gotcha (don't re-discover)
The first `v0.6.0` run **failed**: GitHub's macOS runner defaulted to Xcode 15 (**Swift 5.10**), but
`Package.swift` needs **tools 6.0**. Fix: `runs-on: macos-15` **and** a step that selects the newest
installed Xcode (`xcode-select` to the highest `/Applications/Xcode_*.app`). `Package.swift` pins
`.macOS(.v14)`, so the deployment target stays 14 regardless of the build SDK.

---

## Distribution status & what's next
- **Unsigned / ad-hoc** for now → first launch needs **System Settings → Privacy & Security → "Open
  Anyway"** (macOS 15 removed the Control-click bypass). Documented in the README + release notes.
- **Deferred until a paid Apple Developer Program ($99/yr):** Developer-ID **signing + notarization**
  (the only way to a warning-free install) and **Homebrew** (the official cask tap now requires
  notarization + notability; a self-tap still warns). The pipeline is built so a sign/notarize step
  slots into `release.yml` later. Evidence + reasoning in [intent/release.md](intent/release.md).
- Carried-over from earlier: #11 local token/cost, #3 desktop deep-link (cut), the over-counting
  multi-level `--resume` residual, and L1 opt-in `Stop`/`Notification` hooks.

## Build / test / run
- `swift build` · `./scripts/test.sh` (**143**) · `./build.sh && open dist/CPerch.app` ·
  `swift run CPerchApp --print`.
- **Release:** `scripts/release.sh X.Y.Z` (see above). New since v0.5: `CHANGELOG.md`,
  `scripts/release.sh`, `.github/workflows/release.yml`, `Sources/CPerchApp/HelpView.swift`,
  `Sources/CPerchCore/Diagnostics.swift`.

## Git
- `main` includes everything through v0.6 + the release pipeline; tag **`v0.6.0`** is published. No
  signing secrets (unsigned). Trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Merged feature branches were deleted after this batch (`help-menu-v0.6`, `release-pipeline-v0.6`, and
  the older `accessibility-v0.5` / `daily-driver-v0.4` / `dedup-hardening-v0.1`).
</content>
