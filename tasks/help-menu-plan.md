# cPerch — In-app Help (v0.6) — plan

Implements [docs/specs/help-menu-v0.6.md](../docs/specs/help-menu-v0.6.md) (open questions resolved
2026-06-19). **Branch:** new `help-menu-v0.6` off `main` (now current). Todo:
[help-menu-todo.md](help-menu-todo.md).

> Toolchain: `swift build` · `./scripts/test.sh` (swift-testing) · `./build.sh && open dist/CPerch.app` ·
> `swift run CPerchApp --print`. Commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## Scope (locked)

A `questionmark.circle` "?" in the popover footer that swaps the popover to an in-app, scrollable Help
view (back arrow returns). Seven sections (icons + menu-bar note · ⌘⌥` shortcut · Settings overview ·
Accessibility · Privacy link · Report an issue · About). External links open in the browser with an
`arrow.up.right` icon. "Copy diagnostics" = version + macOS, no identifiers. One-time TTL hint near the
"?" gated by `hasSeenHelpHint`. `build.sh VERSION` → `0.5.0`.

---

## Dependency graph

```
Phase 0 — foundation (serial)
  CPerchCore: Preferences(+hasSeenHelpHint)   Diagnostics.swift (diagnosticsText)   + tests
  build.sh: VERSION 0.0.1 -> 0.5.0
        │ consumed by ▼
Phase 1 — UI (serial; tightly coupled chain)
  HelpView.swift (new)            ← consumes diagnosticsText, Tokens.symbolName, Bundle version
        │ rendered by ▼
  RosterView.swift                ← "?" footer button, list↔Help @State, TTL hint overlay, +showHelpHint param
        │ new init param ▼
  MenuBarController.swift          ← first-open hint trigger + persist hasSeenHelpHint; makeRoster passes showHelpHint
        │ ▼
Phase 2 — on-device sign-off (manual)
```

**Why serial, not a parallel fan-out.** Unlike the accessibility batch (disjoint files), the three App
files here form a **dependency chain** — `MenuBarController` constructs `RosterView`, which renders
`HelpView` — and the batch is small. A fan-out would add isolation overhead for no parallelism gain, so
Phase 1 is done in order (HelpView → RosterView → MenuBarController). `Models.swift` / the frozen contract
is untouched.

---

## Phase 0 — Foundation (serial)

Additive + a build constant; the app is unchanged at runtime.

**T0.1 — Preferences (edit `Sources/CPerchCore/Preferences.swift`)**
- Add `hasSeenHelpHint: Bool` (default **false**); extend `init`, `Key`, `load` (guard
  `object(forKey:) != nil`), `save` — mirroring `launchAtLogin`/`showStatusShapes`.
- **AC:** default is false; save→load round-trips it. **Verify:** `./scripts/test.sh` (T0.3 tests).

**T0.2 — Diagnostics (new `Sources/CPerchCore/Diagnostics.swift`)**
- `public func diagnosticsText(appVersion: String, osVersion: String) -> String` →
  `"cPerch <appVersion>\nmacOS <osVersion>"`. Pure, no identifiers.
- **AC:** exact two-line format; contains only the two inputs. **Verify:** T0.3 tests.

**T0.3 — Core tests**
- Extend `PreferencesTests` (default + round-trip for `hasSeenHelpHint`); new `DiagnosticsTests`.
- **AC:** suite grows from 141; all green.

**T0.4 — Version bump (edit `build.sh`)**
- `VERSION="0.0.1"` → `VERSION="0.5.0"`.
- **AC:** `dist/CPerch.app/Contents/Info.plist` `CFBundleShortVersionString` == `0.5.0`.
  **Verify:** `./build.sh` then `PlistBuddy -c "Print :CFBundleShortVersionString"`.

> **Checkpoint C0:** `swift build` + `./scripts/test.sh` + `./build.sh` green; app visually unchanged
> (new API unused). Commit.

---

## Phase 1 — UI (serial)

**T1.1 — `HelpView.swift` (new, `Sources/CPerchApp/`)**
- A `ScrollView` with the seven sections (§5 of the spec). Legend uses the **real** symbols
  (`Tokens.symbolName(for: statusSymbol(for:))` + `Tokens.statusColor`) so it can't drift; "In the menu
  bar" note. **Open Settings** button → `onOpenSettings`. **Privacy** + **Report an issue** links →
  `NSWorkspace.shared.open` with a trailing `arrow.up.right`. **Copy diagnostics** → `NSPasteboard` using
  `diagnosticsText(appVersion: <Bundle.main CFBundleShortVersionString>, osVersion: <ProcessInfo…>)`,
  with a brief "Copied" confirm. **About** = `cPerch <version>` + tagline + "MIT License". A back control
  → `onBack`. Signature ~ `HelpView(onBack: () -> Void, onOpenSettings: () -> Void)`.
- **AC:** compiles; renders all seven sections; the legend matches the live status symbols.
  **Verify:** `swift build`; visual check in Phase 2.

**T1.2 — `RosterView.swift`**
- Footer: add a `questionmark.circle` button (beside the gear) → sets `@State showingHelp = true`.
- Body: when `showingHelp`, render `HelpView(onBack: { showingHelp = false }, onOpenSettings: onSettings)`
  instead of the list; else the current content. `@State` survives `rootView` refreshes (like
  `collapsedSources`).
- Add `var showHelpHint: Bool = false`; when true, show a small auto-dismissing callout anchored near the
  "?" ("New here? Tap for help.") via a `.task`/timer (~4.5 s; no animation under reduce-motion), and hide
  it immediately if Help opens.
- **AC:** "?" opens Help; back returns with list state intact; the callout shows only when
  `showHelpHint` and fades. **Verify:** `swift build`; visual in Phase 2.

**T1.3 — `MenuBarController.swift`**
- In `showPopover()`: if `preferences.preferences.hasSeenHelpHint == false`, arrange for the next
  `makeRoster()` to pass `showHelpHint: true`, then set `preferences.preferences.hasSeenHelpHint = true`
  (persists via `didSet`) so it never shows again.
- `makeRoster()`: pass `showHelpHint:` (true once, false otherwise).
- **AC:** first-ever popover open shows the hint once; never again, even across relaunches.
  **Verify:** `swift build` + `./build.sh`; on-device in Phase 2.

> **Checkpoint C1:** reconverge → `swift build` + `./scripts/test.sh` + `./build.sh` green; boundary audit
> (Core Foundation-only; no network; only `NSWorkspace.open`/`NSPasteboard`, no new TCC permission; no new
> `~/.claude` reads). Commit.

---

## Phase 2 — On-device sign-off (manual)

From `dist/CPerch.app`:
1. "?" opens Help; back returns; list state preserved; content scrolls.
2. All seven sections render; the legend matches the live symbols.
3. **Privacy policy** and **Report an issue** open in the browser, each with the `arrow.up.right` icon;
   issue link lands on the GitHub issue chooser.
4. **Copy diagnostics** puts `cPerch 0.5.0` + the macOS version on the clipboard (paste to confirm).
5. The first-run hint appears once near the "?", auto-dismisses, and never returns after relaunch.
6. **About** shows `0.5.0`.

Then merge `help-menu-v0.6` → `main`; refresh the handover.

---

## File ownership

| File | Phase 0 | Phase 1 |
|---|:--:|:--:|
| `CPerchCore/Preferences.swift` | ● | |
| `CPerchCore/Diagnostics.swift` (new) | ● | |
| `CPerchCoreTests/*` | ● | |
| `build.sh` | ● | |
| `CPerchApp/HelpView.swift` (new) | | ● (T1.1) |
| `CPerchApp/RosterView.swift` | | ● (T1.2) |
| `CPerchApp/MenuBarController.swift` | | ● (T1.3) |

`Models.swift` / `SessionProviding` / readers / merge: **untouched** (frozen contract).
</content>
