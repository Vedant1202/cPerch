# cPerch — release readiness (confirmed intent)

*Output of an `/interview-me` pass (2026-06-19). Confirmed by the user; drives
[docs/specs/release-pipeline-v0.6.md](../specs/release-pipeline-v0.6.md).*

## Confirmed intent
- **Outcome:** one command — `scripts/release.sh X.Y.Z` → a published GitHub Release with curated
  changelog notes plus a **zip and a DMG** (drag-to-Applications) of the app.
- **User:** the maintainer (cuts releases) and end users (download the zip or DMG from Releases).
- **Why now:** v0.6 merged to `main`; there's no release process, changelog, or downloadable build yet.
- **Success:** `scripts/release.sh 0.6.0` ends with a **`v0.6.0`** Release whose notes come from
  `CHANGELOG.md`, with `CPerch-0.6.0.zip` and `CPerch-0.6.0.dmg` attached — built by CI, zero manual steps.
- **Constraint:** unsigned / ad-hoc only (no Apple Developer ID) → both artifacts need the macOS
  "Open Anyway" first-run step, documented in the README and the release notes. Build the pipeline so
  Developer-ID signing + notarization slot in later without rework.
- **Out of scope (deferred until the $99 Apple Developer Program):** Developer-ID signing, notarization,
  Homebrew (official cask *and* a self-hosted tap), and 1.0.0.

## Why these distribution choices (evidence, 2026-06)
- **Notarization needs the paid program.** A "Developer ID Application" certificate is only available via
  the **Apple Developer Program ($99/yr)**; since macOS 10.15 an app must be signed *and* notarized to run
  without the user overriding security. The user does **not** have this account, so v0.6.0 ships unsigned.
- **A DMG does not fix trust.** It's packaging only and needs no Apple account, but an unsigned app inside
  a DMG hits the same Gatekeeper wall as a zip — DMG is cosmetics (a nicer drag-to-Applications UX), not a
  "no warnings" path. We ship it anyway because it's a cheap, polished option with zero account cost.
- **macOS Sequoia (15) tightened Gatekeeper:** the Control-click → Open shortcut for unsigned apps was
  removed; users now approve via System Settings → Privacy & Security → "Open Anyway". The README + release
  notes must spell this out.
- **Homebrew now effectively requires notarization:** the official `homebrew/cask` tap is deprecating
  unsigned/un-notarized casks (removal by Sept 2026) and removing `--no-quarantine`; cPerch also fails the
  notability bar for a self-submitted cask. A self-hosted tap is possible but still warns and adds
  maintenance — so Homebrew waits for the paid program too.

Sources: Apple Developer Program / notarization (developer.apple.com; apptimized.com), macOS Sequoia
Gatekeeper change (idownloadblog.com; daringfireball.net), Homebrew Acceptable Casks + brew#20755
(docs.brew.sh; workbrew.com).
</content>
