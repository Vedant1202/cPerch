# cPerch — in-app Help (idea one-pager)

*Output of an `/idea-refine` pass (2026-06-19). The concept below is locked; next step is a spec.*

## Problem Statement
**How might we** let a cPerch user answer "what does this icon mean?", "how do I open it?", and "where's
that setting?" *without leaving the app* — while staying calm, minimal, and fully local?

## Locked decisions (from refinement)
- **Entry point:** a **"?" button in the cPerch popover footer**, next to the gear.
- **Discoverability:** a **one-time gentle hint** on first launch, then never again.
- **Scope:** **Help + About + "Copy diagnostics"** (not just the six requested items).

## Recommended Direction
Tapping **"?"** swaps the popover's content from the session list to a **scrollable Help view**, with a
back arrow to return — Help lives *inside* cPerch's existing menu-bar surface, so there's no extra window
to build or manage and nothing leaves the app except when the user follows a link. This fits the calm
ethos and reuses the popover that's already there (`RosterView` is hosted in an `NSPopover` via
`NSHostingController`; the host view simply renders Help or the list based on state).

The Help view is concise **reference**, not documentation — it answers the common questions and links out
for depth (the full privacy policy stays on the website as the single source of truth). Sections:

1. **What the icons mean** — the three states (needs-input triangle, running half-circle, concluded
   check) with one-line meanings, plus a short note on the menu-bar dot (the white plate, the needs-you
   count, the all-done glyph).
2. **Open cPerch** — the global shortcut **⌘⌥`**, and "click the menu-bar icon."
3. **Settings overview** — one line each for General, Notifications, Accessibility, with an "Open
   Settings" button.
4. **Accessibility** — shape-coded status, high-contrast mode, VoiceOver, reduce motion/transparency.
5. **Privacy** — one sentence + a "Privacy policy" link (opens the website page).
6. **Report an issue** — a **"Copy diagnostics"** button (cPerch version + macOS version, no identifiers)
   then an "Open issue form" link to the GitHub issue chooser, where the user pastes the diagnostics.
7. **About** — name, version (from the bundle), MIT license, one-line credit.

**Architecture fit (keeps the invariants):** the pure pieces live in `CPerchCore` and are unit-tested —
a `hasSeenHelpHint` preference (additive, default false) and a `diagnosticsText(appVersion:osVersion:)`
builder. All UI (`HelpView`), clipboard (`NSPasteboard`), link opening (`NSWorkspace.open`), and bundle
version reading stay in `CPerchApp`. No network, no `~/.claude` access, **no new TCC permission**.

## Key Assumptions to Validate
- [ ] In-popover Help (vs a separate window) holds all seven sections comfortably — *test on-device; the
      popover is ~340pt wide and height-capped, so the Help view must scroll.*
- [ ] A transient popover closing when the user follows a link (privacy/issue) is acceptable — *they're
      navigating to the browser anyway; confirm it doesn't feel abrupt.*
- [ ] The one-time hint reads as helpful, not naggy — *one subtle, dismissable line; gone after first
      open.*
- [ ] "Copy diagnostics → open issue form" is a good-enough flow given GitHub issue **forms** can't be
      reliably pre-filled from a URL — *validate the paste step is obvious.*

## MVP Scope
**In:** the "?" footer button; an in-popover scrollable `HelpView` with the seven sections; the one-time
first-launch hint; Copy diagnostics; links out to the privacy page and the GitHub issue chooser; About
with the bundle version. Pure Core: `hasSeenHelpHint` + `diagnosticsText(...)` (+ tests).

**Out (this pass):** see Not Doing.

## Not Doing (and why)
- **A separate Help window** — chosen against; in-popover keeps it calm and avoids window management.
- **Rendering the full privacy policy in-app** — link to the web page; one source of truth, less to maintain.
- **A guided tour / coach marks beyond the single hint** — over-engineered for this surface.
- **Search within Help** — the content is short enough to scan.
- **Localization** — English only for now.
- **A "What's new" / changelog feed** — About shows the version; release notes live on GitHub.
- **Any diagnostics beyond version + OS** — no identifiers, no system profiling; stays privacy-true.

## Open Questions (resolve in the spec)
- Bump `VERSION` in `build.sh` from `0.0.1` to match the project (e.g. `0.5.0`) so **About** shows a real
  version?
- Exact issue URL — the chooser (`/issues/new/choose`, shows our templates) vs the bug form directly?
- Does the one-time hint live in the popover footer (a small line by the "?") or as a tiny badge on the
  "?" itself, and what clears it (first Help open, or first dismiss)?
- Should the menu-bar-signal note (count / all-done glyph / plate) be in the icons section or folded into
  a short "menu bar" line?
