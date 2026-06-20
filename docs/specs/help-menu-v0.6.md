# cPerch — In-app Help (v0.6 spec)

**Status:** open questions resolved (2026-06-19) — scope locked. Ready to implement **on your go-ahead**.
**Date:** 2026-06-19 · **Branch target:** new `help-menu-v0.6` off `main` (now current).
**Origin:** the `/idea-refine` one-pager [docs/ideas/help-menu.md](../ideas/help-menu.md).

> Per `~/.claude/CLAUDE.md` (spec-first rule): each decision is stated with its locked answer; the four
> open questions from the idea pass are resolved in §10.

---

## 1. Objective

Give cPerch a built-in, in-app **Help** so a user can answer "what does this icon mean?", "how do I open
it?", and "where's that setting?" without leaving the app — calm, minimal, and fully local.

| Part | One-liner |
|---|---|
| **Entry** | A `questionmark.circle` **"?"** button in the popover footer, next to the gear. |
| **Help view** | Tapping "?" swaps the popover to a scrollable in-app Help view, with a back arrow. |
| **First-run hint** | A one-time, auto-dismissing callout near the "?" on the first popover open. |
| **Report an issue** | "Copy diagnostics" (version + macOS, no identifiers) → open the GitHub issue form. |
| **About** | App version (from the bundle) + MIT license. |

---

## 2. Boundaries (unchanged — these gate every decision)

- **Fully local. No network, ever.** The only outward actions are user-initiated links opened in the
  default browser (privacy policy, GitHub). They are clearly marked as leaving the app (§5).
- **Read-only on `~/.claude`.** Help reads nothing from there; no new read surface.
- **No new TCC permission.** Opening a URL (`NSWorkspace.open`) and writing the clipboard
  (`NSPasteboard`) need no permission. No Accessibility, no Input Monitoring.
- **`CPerchCore` stays Foundation-only.** The pure pieces (the `hasSeenHelpHint` pref, the diagnostics
  string builder) live in Core and are unit-tested; all UI / clipboard / link-opening / bundle-version
  reading stay in `CPerchApp`.
- **Calm > complete.** Help is concise *reference*, not documentation. It never nags (one-time hint
  only), and links out for depth instead of duplicating it.

---

## 3. Commands (unchanged toolchain)

- `swift build` · `./scripts/test.sh` (swift-testing; XCTest isn't in the CLT) ·
  `./build.sh && open dist/CPerch.app` · `swift run CPerchApp --print`.
- **On-device check required** for the popover swap, the TTL hint, the clipboard copy, and the browser
  links (can't be exercised headless).

---

## 4. The "?" entry + in-popover Help view

**Decision (locked):** add a `questionmark.circle` button to the `RosterView` footer (beside the existing
`gearshape`). Tapping it switches the popover's content from the session list to a **`HelpView`**; a back
arrow (`chevron.left`) returns to the list.

- The switch is SwiftUI `@State` on the popover's root (e.g. `showingHelp`), which **survives roster
  refreshes** the same way `collapsedSources` does today (MenuBarController reassigns `hosting.rootView`
  on refresh; SwiftUI preserves `@State`). No new window.
- `HelpView` is a `ScrollView` (the popover is ~340 pt wide and height-capped, so the content scrolls).
- `HelpView` receives `onBack` and `onOpenSettings` closures (the latter reuses the existing
  Settings-window action). It performs its own link-opening and clipboard writes (it's in `CPerchApp`).

**Acceptance:** clicking "?" shows Help; back returns to the list; the list state (e.g. collapsed groups)
is intact on return. **Testable in Core?** No (SwiftUI); structure is live-verified.

---

## 5. Help content (the seven sections)

`HelpView`, top to bottom. Plain language, always "cPerch".

1. **What the icons mean** — the three states with their shape + one-line meaning, rendered with the
   *real* app symbols (`Tokens.symbolName(for:)` + `statusSymbol(for:)`) so the legend can't drift:
   needs-input (triangle, orange) = waiting on you; running (half-filled circle, blue) = working;
   concluded (check, green) = finished. **Plus a short "In the menu bar" note** (resolved Q4): the dot
   sits on a **white plate** so it's visible on any wallpaper, shows a **count** when 2+ sessions need
   you, and turns into the green **all-done** check when everything's concluded.
2. **Open cPerch** — the global shortcut **⌘⌥`**, and "click the cPerch icon in the menu bar."
3. **Settings overview** — one line each: **General** (theme, list layout, how long finished sessions
   stay, launch at login), **Notifications** (which events notify you, Focus/DND behavior, banner life),
   **Accessibility**. An **"Open Settings"** button (calls `onOpenSettings`).
4. **Accessibility** — shape-coded status, high-contrast mode, VoiceOver labels, reduce motion /
   transparency (pointing to the Accessibility tab).
5. **Privacy** — one sentence ("cPerch works entirely on your Mac and sends nothing.") + a
   **"Privacy policy"** link that **opens in the browser** (the website `privacy.html`), shown with an
   **external-link icon** (`arrow.up.right`, muted) so it's clear it leaves the app.
6. **Report an issue** — see §6.
7. **About** — "cPerch <version>" (from the bundle), the tagline, and "MIT License."

**External-link affordance (resolved Q2):** any link that leaves the app (Privacy policy, issue form)
shows the trailing `arrow.up.right` glyph and opens via `NSWorkspace.shared.open(_:)` in the default
browser.

**Acceptance:** all seven sections render and scroll; the two external links open the correct URLs in the
browser and visibly indicate they leave the app.

---

## 6. Report an issue (Copy diagnostics + link)

**Decision (locked):**
- A **"Copy diagnostics"** button writes a small, identifier-free string to the clipboard via
  `NSPasteboard` — built by the pure Core `diagnosticsText(appVersion:osVersion:)`, e.g.:
  ```
  cPerch 0.5.0
  macOS 14.5 (23F79)
  ```
  (App passes `Bundle.main` version + `ProcessInfo.processInfo.operatingSystemVersionString`.) The button
  briefly confirms ("Copied").
- An **"Open issue form"** link opens **`https://github.com/Vedant1202/cPerch/issues/new/choose`** in the
  browser (shows the bug/feature templates we added), with the external-link icon. The user pastes the
  diagnostics into the report. (Resolved Q2.)

**Acceptance:** Copy diagnostics puts `cPerch <version>` + the macOS version on the clipboard (no
identifiers); the link opens the GitHub issue chooser in the browser.
**Testable in Core?** **Yes** — `diagnosticsText(...)` is pure and unit-tested.

---

## 7. First-run hint (one-time, TTL callout)

**Decision (locked, resolves Q3):** the first time the popover opens, show a small **callout/tooltip near
the "?"** ("New here? Tap for help.") that **auto-dismisses after a few seconds** (TTL ~4–5 s) and is
shown **only once**, gated by a new pref **`hasSeenHelpHint`** (default false). It is also cleared
immediately if the user opens Help. Subtle, dismissable, never repeats — no welcome panel, no modal. The
"?" itself is the `questionmark.circle` glyph.

- `MenuBarController` shows the popover; if `hasSeenHelpHint == false`, it tells `RosterView` to show the
  callout, starts the TTL, and sets `hasSeenHelpHint = true` (persisted) so it never shows again.
- The callout is a lightweight SwiftUI overlay anchored to the "?"; the TTL is a cancellable task.

**Acceptance:** on a fresh install the hint appears once near the "?", fades after the TTL, and never
returns on later opens (even across relaunches). **Testable in Core?** The pref round-trip — yes; the
overlay/timing — live.

---

## 8. About + version bump

**Decision (locked, resolves Q1):** bump `build.sh` `VERSION` from `0.0.1` to **`0.5.0`** so
`CFBundleShortVersionString` (and `CFBundleVersion`) reflect the real project state, and **About** reads
it from `Bundle.main.infoDictionary["CFBundleShortVersionString"]` (falling back to "unknown" for a bare
`swift run`). About also shows the tagline and "MIT License."

---

## 9. Plumbing (additive — preserves the frozen contracts)

- `Preferences` (CPerchCore): **add `hasSeenHelpHint: Bool = false`** (additive, defaulted; persistence +
  load/save mirror the existing pattern). `PreferencesStore` exposes it like the others.
- New `Sources/CPerchCore/Diagnostics.swift`: `public func diagnosticsText(appVersion:osVersion:) -> String`.
- New `Sources/CPerchApp/HelpView.swift`: the SwiftUI Help content (sections, links, copy, about).
- `RosterView.swift`: footer "?" button, the list↔Help switch (`@State`), and the TTL hint overlay.
- `MenuBarController.swift`: trigger the one-time hint on first popover open; set/persist `hasSeenHelpHint`.
- `build.sh`: `VERSION="0.5.0"`.
- `Models.swift` / `SessionProviding` / readers / merge: **untouched** (frozen contract).

---

## 10. Open questions — RESOLVED (2026-06-19)

- [x] **Q1 — App version for About:** bump `build.sh` `VERSION` `0.0.1 → 0.5.0`; About reads the bundle. *(your call)*
- [x] **Q2 — Issue link + external links:** open in the browser; issue link → `/issues/new/choose`; both
  Privacy and issue links carry an `arrow.up.right` external-link icon. *(your call)*
- [x] **Q3 — First-run hint:** a TTL-based auto-dismissing callout near the "?", shown once
  (`hasSeenHelpHint`). The "?" is the `questionmark.circle` glyph. *(your call)*
- [x] **Q4 — Menu-bar signals:** folded into the "What the icons mean" section as a short "In the menu
  bar" note. *(your call)*

---

## 11. Proposed build order (after go-ahead)

1. **Phase 0 (serial · foundation):** `Preferences` (+`hasSeenHelpHint`) + `Diagnostics.swift`
   (`diagnosticsText`) with tests; bump `build.sh` `VERSION`. Compiles; the app is unchanged at runtime.
   Checkpoint: build + tests + bundle green.
2. **Phase 1 (UI):** `HelpView.swift` (new) + the `RosterView` footer/switch/hint + the
   `MenuBarController` first-open hint trigger. (Smaller and tightly coupled — done together rather than a
   fan-out.) Checkpoint: build + bundle.
3. **Phase 2 (manual, on-device):** "?" opens Help and back returns; all sections render + scroll; the two
   links open in the browser with the external-link icon; Copy diagnostics works; the first-run hint shows
   once and never again; About shows `0.5.0`.

---

## 12. Acceptance criteria (whole batch)

- The "?" in the popover footer opens an in-app Help view (back returns; list state preserved).
- All seven sections render; external links open in the browser and are marked as leaving the app.
- Copy diagnostics writes `cPerch <version>` + macOS version (no identifiers); the issue link opens the
  chooser.
- The first-run hint appears once and never repeats (persisted).
- About shows the real version (`0.5.0`).
- New pure logic (`diagnosticsText`, `hasSeenHelpHint` round-trip) is unit-tested; existing tests stay
  green. **No network, no new TCC permission, no new `~/.claude` reads.**
