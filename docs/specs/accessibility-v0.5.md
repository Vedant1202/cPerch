# cPerch — Accessibility batch (v0.5 spec)

**Status:** open questions resolved (2026-06-19) — scope locked to **A1, A2, A3, A4, A5/A6 + the
Accessibility tab**. Ready to implement **on your go-ahead**. (Resolutions in §11.)
**Date:** 2026-06-19 · **Branch target:** new `accessibility-v0.5` off `daily-driver-v0.4` (latest
baseline; `main` is behind).
**Origin:** accessibility review of the roster + menu-bar (handover-v0.4 follow-up). cPerch's core
signal is **color** (orange/blue/green status), which fails for color-vision-deficient users and
measurably under-contrasts in light mode. This batch makes status legible without relying on hue, and
fixes the measured contrast gaps — inside the calm/minimal, fully-local ethos.

> Per `~/.claude/CLAUDE.md` (spec-first rule): every decision with an open question is stated with an
> evidence-backed proposed answer; the open ones are collected in §11.

---

## 1. Objective

Make cPerch usable without depending on color perception, and clear the WCAG contrast failures the
current palette has in light mode — plus a new **Accessibility** tab to house it.

| # | Feature | One-liner |
|---|---|---|
| **A1** | **Shape-coded status** (always-on) | Each status carries a distinct SF Symbol, not just a hue — so 🟠/🔵/🟢 are tellable apart in grayscale and for the ~8% of men with CVD. |
| **A2** | **Baseline contrast fix** | Swap hardcoded low-contrast grays for semantic colors and lift the dots/labels past the WCAG floor — fixes light mode for **everyone**, no toggle. |
| **A4** | **VoiceOver labels** | The menu-bar item and each roster row announce their state ("cPerch — 2 sessions need you"; "api, needs input, blocked 4 minutes…"). |
| **Tab** | **Accessibility settings tab** | A third Settings tab (General · Notifications · **Accessibility**) for the controls below. |
| **A3** | **High-contrast mode** | When macOS *Increase Contrast* is on (or the user forces it), swap to a high-contrast palette + stronger borders + solid fills. *In v0.5 (§11-Q1); values in §7.* |
| **A5/A6** | **Reduce motion / transparency** | Honor the system flags (popover animation + material background). Cheap; bundled to give the tab substance. *In v0.5 (§11-Q3).* |

**The evidence that drove this (measured on the real tokens, [DesignTokens.swift](../../Sources/CPerchApp/DesignTokens.swift)):**

- **Status is conveyed by color alone** — `StatusDot` is `Circle().fill(color)`
  ([RosterView.swift:291](../../Sources/CPerchApp/RosterView.swift)); the bar is one filled oval
  ([MenuBarController.swift:177](../../Sources/CPerchApp/MenuBarController.swift)). Strip the hue and the
  three states sit at near-identical lightness: orange↔blue **1.07:1**, orange↔green **1.18:1**. A
  red-green CVD user (1 in 12 men / 8% / ~300M people) cannot reliably tell **"needs you now" (orange)**
  from **"all done" (green)** — the single most important distinction the app makes. Fails **WCAG 1.4.1
  Use of Color (Level A)**.
- **Light mode under-contrasts today** (WCAG 2.1 ratios, computed):

  | Element | On light bg | WCAG verdict |
  |---|---|---|
  | Secondary / message-preview text `#B0AEA5` | **2.11 : 1** | ✗ fails AA text (4.5:1) — *the actual content* |
  | Orange dot `#D97757` | 2.96 : 1 (cream) / 3.12 (white) | ✗/borderline non-text (3:1) |
  | Blue dot `#6A9BCC` | **2.78 : 1** (cream) / 2.93 (white) | ✗ fails non-text (3:1) |
  | Green dot `#788C5D` | 3.49 : 1 | ✓ (barely) |
  | *(all of the above on **dark** bg)* | 5.0 – 8.3 : 1 | ✓ pass |

  Dark mode is fine; **light mode is the problem** — the mid-toned accents wash out on the cream/white
  background.

---

## 2. Boundaries (unchanged — these gate every decision below)

- **Fully local. No network, ever.** Pure presentation work.
- **Read-only on `~/.claude`.** No new read surfaces.
- **No new TCC permission — and specifically NOT Accessibility.** ⚠️ Important distinction: the macOS
  signals this batch reads — `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`,
  `…ShouldDifferentiateWithoutColor`, `…ShouldReduceMotion`, `…ShouldReduceTransparency` — are **plain
  readable display preferences**, *not* the Accessibility (AX/`AXIsProcessTrusted`) control permission
  cPerch is forbidden from requesting. Reading them triggers **no prompt** and honors the hard boundary.
  ([Apple docs](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshoulddifferentiatewithoutcolor))
- **`CPerchCore` stays Foundation-only.** The *decisions* — which abstract symbol per status, how to
  compose a VoiceOver string, resolve an override against a system flag — live in Core and are
  unit-tested (exactly the precedent of the color-free `MenuBarModel.Glyph`,
  [MenuBarModel.swift:14](../../Sources/CPerchCore/MenuBarModel.swift)). All SF-Symbol / NSColor /
  NSWorkspace / SwiftUI glue stays in `CPerchApp`.
- **No Xcode / asset catalog.** cPerch builds with SwiftPM + CLT and defines colors as hex in code, so
  high-contrast variants are **code-driven palettes keyed on the flag** — not `.xcassets` "High Contrast"
  slots (which need Xcode's `actool`). This *fits* the existing all-in-code token approach.
- **Calm > complete.** Shapes are subtle (a glyph inside the existing dot), defaults stay quiet, the bar
  stays a dot/glyph. We add clarity, not noise.

---

## 3. Commands (unchanged toolchain)

- `swift build` — compiles. `./scripts/test.sh` — swift-testing unit tests (XCTest isn't in the CLT).
- `./build.sh` then `open dist/CPerch.app` — the ad-hoc-signed bundle. `swift run CPerchApp --print`
  dumps live sessions headless.
- **On-device visual check is required** for the symbol set at 9–11 pt and the live reaction to the
  System Settings ▸ Accessibility ▸ Display toggles (these can't be exercised headless — same posture as
  v0.4's live sign-off).

---

## 4. The Accessibility settings tab

**Decision (locked):** add a third tab to the existing `TabView`
([SettingsView.swift:10](../../Sources/CPerchApp/SettingsView.swift)) — **General · Notifications ·
Accessibility** — `Label("Accessibility", systemImage: "accessibility")`, a `Form(.grouped)` like the
others. Controls:

| Control | Type | Default | Backing |
|---|---|---|---|
| **Differentiate status with shapes** | Toggle | **On** | A1 — on by default (the "always-on" call); opt-out for the user who wants the pure dot (§11-Q2, confirmed) |
| **High contrast** | Picker: Follow System / Always on / Off | **Follow System** | A3 — resolved against `accessibilityDisplayShouldIncreaseContrast` |
| **Reduce motion** | Picker: Follow System / Always on / Off | **Follow System** | A5 — popover animation |
| **Reduce transparency** | Picker: Follow System / Always on / Off | **Follow System** | A6 — material background |

**Preferences additions** (additive, defaulted ⇒ preserves the frozen-contract pattern;
[Preferences.swift](../../Sources/CPerchCore/Preferences.swift)):

```swift
public enum A11yOverride: String, CaseIterable, Sendable, Codable { case system, on, off }   // Follow System / Always on / Off
public var showStatusShapes: Bool         // default true
public var highContrast: A11yOverride      // default .system
public var reduceMotion: A11yOverride      // default .system
public var reduceTransparency: A11yOverride// default .system
```

**Resolution is a pure Core helper** (unit-tested): `effective(_ override: A11yOverride, system: Bool) -> Bool`
→ `.on`⇒true, `.off`⇒false, `.system`⇒the live flag. The App layer reads the live flag from
`NSWorkspace.shared` and feeds it in.

**Live reaction:** the SwiftUI roster already re-renders on the matching `@Environment` values
(`accessibilityDifferentiateWithoutColor`, `colorSchemeContrast`, `accessibilityReduceMotion`,
`accessibilityReduceTransparency`) — SwiftUI re-invokes `body` automatically when they change. The
**AppKit** menu-bar dot needs one observer on `NSWorkspace.shared.notificationCenter` for
`accessibilityDisplayOptionsDidChangeNotification` → re-render the dot
([Apple docs](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayoptionsdidchangenotification)).
One shared reaction point covers A3/A5/A6 in the bar.

---

## 5. A1 — Shape-coded status (always-on)

**Decision (locked):** every status renders **color + a distinct SF Symbol glyph**, on by default for
everyone (not gated behind the system flag — that's the "always-on" call). Color still serves the 92%;
the shape serves everyone, including grayscale/CVD. This is the primary fix for **WCAG 1.4.1**.

**Symbol set — LOCKED (2026-06-19, three distinct silhouettes, each an industry-standard meaning):**

| Status | SF Symbol | Why |
|---|---|---|
| **needs-input** 🟠 | `exclamationmark.triangle.fill` | Warning / attention — the triangle is the universal caution silhouette (ISO 7010, ANSI Z535, Apple's own alerts). The one state you *must* act on gets the most distinct, attention-grabbing outline. |
| **running** 🔵 | `circle.lefthalf.filled` | "In Progress" — the partially-filled circle is the de-facto issue-tracker standard (Linear, Things, Asana). Partial fill = ongoing. |
| **concluded** 🟢 | `checkmark.circle.fill` | Universal "done / success." |
| *(menu-bar idle)* | `circle.fill` (dim gray) | Resting state — plain dot, no glyph. |

**Why this set (grounded):**
- **Distinct in grayscale by silhouette:** triangle vs half-filled disc vs full disc + check — three
  genuinely different *outlines*, so they separate at 13 px grayscale without relying on hue (the
  decisive view in the [spike](../../spikes/a11y-status-symbols.html)). This is the core WCAG 1.4.1 fix.
- **Each glyph carries an established meaning:** triangle = warning/attention; partially-filled circle =
  in-progress; checkmark = done. Nothing is invented.
- **Reads as a lifecycle:** running (half disc) → concluded (full disc + check) mirror an
  in-progress → done progression, while **needs-input** deliberately breaks the circle family as the
  alert triangle — the exception you want to notice.
- Apple HIG: enclosing shapes + the **fill** variant improve legibility at **small sizes**
  ([Apple HIG: SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)) —
  all three are filled/enclosed forms.

**Documented fallback (decide on-device):** if the triangle / half-disc read too busy at 9 pt, fall back
to the cohesive **all-circle** family (`exclamationmark.circle.fill` / `ellipsis.circle.fill` /
`checkmark.circle.fill`) — distinguished by inner glyph rather than outline. Recorded so the live tester
has a sanctioned plan B rather than re-deriving one.

**Implementation:**
- Core: an abstract `StatusSymbol` enum (`needsInput / running / concluded / idle`) + a pure
  `statusSymbol(for: DerivedStatus) -> StatusSymbol`, mirroring the existing abstract-glyph pattern.
  Unit-tested. (Symbol *names* are an App concern — SF Symbols isn't Foundation — so the
  `StatusSymbol → systemName` map sits in the App layer, beside the existing glyph→color map at
  [MenuBarController.swift:70](../../Sources/CPerchApp/MenuBarController.swift).)
- Roster: replace the `Circle().fill` in `StatusDot` with `Image(systemName:)` tinted by the status
  color (keep the 9 pt frame).
- Menu bar: replace the hand-drawn oval ([MenuBarController.swift:177](../../Sources/CPerchApp/MenuBarController.swift))
  with `NSImage(systemSymbolName:accessibilityDescription:)`, tinted, `isTemplate = false` (keep color).

**Acceptance:** in grayscale (or Sim Daltonism / macOS color filters), the three states are
distinguishable; the bar dot shows a glyph, not a bare disc; toggling **Differentiate status with shapes**
off returns the plain colored dot. **Testable in Core?** The *mapping* yes; the rendering is live-verified.

---

## 6. A2 — Baseline contrast fix (for everyone, no toggle)

The measured failures in §1 are present in default light mode regardless of any accessibility setting —
they're a bug. **Decision (locked):** fix them structurally with **semantic system colors** (which
adapt to light/dark *and* auto-boost under Increase Contrast) and small dot treatment.

**Contrast / opacity audit — every low-contrast site and its fix:**

| Site | Now | Fix |
|---|---|---|
| Message-preview text [RosterView.swift:249](../../Sources/CPerchApp/RosterView.swift) | `midGray #B0AEA5` → 2.11:1 | `Color(NSColor.secondaryLabelColor)` (semantic, adapts) |
| Header summary / empty-state / footer / group-header text (`:160,:179,:122,:192,:203`) | `midGray` | `secondaryLabelColor` |
| Disambiguator label `:231` | `midGray` | `Color(NSColor.tertiaryLabelColor)` |
| "blocked Nm" pill `:237/:241` | orange text `#D97757` (2.96:1) on `needsInput.opacity(0.14)` | readable text (`secondaryLabelColor` or AA-passing orange) on a solid/bordered pill |
| List dividers `:94,:141` | `divider #E8E6DC.opacity(0.6)` | `Color(NSColor.separatorColor)` (semantic) |
| Group count `:125` | `midGray.opacity(0.7)` | `secondaryLabelColor`, drop the extra opacity |
| Menu-bar count text [MenuBarController.swift:191](../../Sources/CPerchApp/MenuBarController.swift) | fixed orange (≈3:1 on a light bar) | `NSColor.labelColor` (adapts to the bar) |
| Status dots (light) | brand fills 2.78–3.49:1 | keep **brand hue** + a 1 px `separatorColor` ring for edge definition; the always-on **shape** carries the meaning |

**Why semantic colors:** Apple's `labelColor` / `secondaryLabelColor` / `separatorColor` are guaranteed
to meet system contrast and **automatically increase** when the user turns on Increase Contrast — so A2
also does most of A3's text work for free. The brand **accent** colors can't be semantic (they're brand),
so those get the explicit high-contrast variants in §7.

**Acceptance:** in light mode, preview text and secondary labels are comfortably legible (≥ 4.5:1); the
dots read against the background; no element relies on a sub-3:1 tint to be seen.
**Testable in Core?** Contrast is visual/live; no Core logic changes here (pure token/style edits).

---

## 7. A3 — High-contrast mode (in v0.5; §11-Q1)

**Decision (locked):** when high contrast is effective (system flag on, or the tab's override = Always
on), the App swaps the accent palette to the **verified high-contrast set** below, draws a **1 px solid
border** on dots and the popover edge, and **removes opacity tints** (all alphas → 1.0). SwiftUI's own
guidance is to target **7:1** under increased contrast; semantic text colors already move there, and the
accent fills below are pushed to ≥ 4.5:1 (light) / ≥ 7:1 (dark).

**High-contrast accent tokens (computed + WCAG-verified, vs the real backgrounds):**

| Status | Standard (unchanged) | **HC light** (on `#FAF9F5`/white) | **HC dark** (on `#141413`) |
|---|---|---|---|
| needs-input | `#D97757` | **`#AB5E45`** — 4.51:1 / 4.75:1 | **`#DF8B70`** — 7.08:1 |
| running | `#6A9BCC` | **`#51769B`** — 4.52:1 / 4.76:1 | **`#77A4D1`** — 7.04:1 |
| concluded | `#788C5D` | **`#677850`** — 4.55:1 / 4.80:1 | **`#96A581`** — 7.02:1 |

*(Standard **dark** dots keep the brand accents — already 5.0–6.3:1. Standard **light** dots keep brand
hue + the §6 ring. Only **HC** swaps the fills.)*

**Opacity behavior in HC** (reuses the §6 audit): every `.opacity(<1)` tint listed there goes solid; the
"blocked" pill becomes a bordered solid; dividers use full-strength `separatorColor`.

**Acceptance:** turning on System Settings ▸ Accessibility ▸ Display ▸ **Increase Contrast** (or the tab
override) visibly strengthens dots/text/borders and removes the faint tints, live, without relaunch.
**Testable in Core?** The `effective(override, system)` resolver — yes. The palette/render — live.

---

## 8. A4 — VoiceOver labels

cPerch is an *announcer* app, yet today a screen reader gets almost nothing: the menu-bar button exposes
only a static `"cPerch"` tooltip ([MenuBarController.swift:37](../../Sources/CPerchApp/MenuBarController.swift)),
and `StatusDot` labels with the raw enum value (`"needsInput"`) ([RosterView.swift:306](../../Sources/CPerchApp/RosterView.swift)).

**Decision (locked):**
- **Menu-bar item:** set `setAccessibilityLabel("cPerch")` and a **dynamic** `setAccessibilityValue(…)`
  in `refresh()` — e.g. *"2 sessions need you"* / *"1 running"* / *"all quiet"* (reuse the summary logic).
- **Each roster row:** one combined accessibility element with a composed label —
  *"api, needs input, blocked 4 minutes. Latest: Can I run the database migration?"* — and the Jump button
  exposed as a named `.accessibilityAction(named: "Jump")` (or a properly labeled button), not an
  unlabeled control.
- **Pure Core helpers** (unit-tested): `accessibilityLabel(for: Session, now:) -> String` and
  `menuBarAccessibilityValue(aggregate:needsInputCount:runningCount:) -> String`. The App reads them and
  applies them.

**Acceptance:** with VoiceOver on, focusing the menu-bar item speaks the live summary; arrowing the roster
speaks each session's name + status + wait + latest message; Jump is reachable and labeled.
**Testable in Core?** **Yes** — the string composition is pure. VoiceOver delivery is live-verified.

---

## 9. A5 / A6 — Reduce motion & transparency (cheap; in v0.5 — §11-Q3)

- **Reduce motion:** when effective, set `popover.animates = false`
  ([MenuBarController.swift:31](../../Sources/CPerchApp/MenuBarController.swift)) and skip any view
  transition.
- **Reduce transparency:** when effective, render the roster background solid
  (`Color(NSColor.windowBackgroundColor)`) instead of the `.background` material
  ([RosterView.swift:82](../../Sources/CPerchApp/RosterView.swift)).

Both read the same resolver as A3. Trivial surface; included to give the Accessibility tab real controls
and round out the system-flag honoring. **Acceptance:** with the respective system setting on, the popover
doesn't animate / the background is opaque.

---

## 10. Project structure (files touched)

| Feature | CPerchCore (Foundation, tested) | CPerchApp (glue, live-verified) |
|---|---|---|
| Tab + prefs | `Preferences` (+`showStatusShapes`, `highContrast`, `reduceMotion`, `reduceTransparency`, `A11yOverride`, `effective(…)`) + tests | `SettingsView` (third tab), `PreferencesStore` |
| A1 shapes | `StatusSymbol` + `statusSymbol(for:)` + tests | `DesignTokens`/`MenuBarController` (symbol-name map), `RosterView` (`StatusDot`), `MenuBarController` (bar glyph) |
| A2 contrast | — | `DesignTokens` (semantic token aliases), `RosterView`, `MenuBarController` |
| A3 high-contrast | `effective(override, system)` (shared) + tests | `DesignTokens` (HC palette), `RosterView`, `MenuBarController`, NSWorkspace observer |
| A4 VoiceOver | `accessibilityLabel(for:)`, `menuBarAccessibilityValue(…)` + tests | `RosterView` (row), `MenuBarController` (bar item) |
| A5/A6 | (resolver shared) | `MenuBarController` (animates), `RosterView` (background) |

**Code style:** match the repo — small verifiable increments; pure decisions in Core with swift-testing;
additive, defaulted contract extension; AppKit/SwiftUI glue "compiles + structurally correct,"
live-verified (the `Jumper.swift` / v0.4 precedent).

---

## 11. Open questions — RESOLVED (2026-06-19)

- [x] **Q1 — A3 high-contrast mode:** **included in v0.5.** The palette is designed (§7) and the marginal
  cost over A2 is small (A2 already splits tokens into a palette), and the new tab wants a working
  High-contrast control. *(your call)*
- [x] **Q2 — Shapes:** **on by default + an opt-out toggle** ("Differentiate status with shapes") — honors
  "always-on" as the default while leaving an escape hatch. *(your call)*
- [x] **Q3 — A5/A6 reduce motion / transparency:** **included** in this batch. *(your call)*
- [x] **Q4 — Symbol set:** **locked** (§5) — needs-input `exclamationmark.triangle.fill`, running
  `circle.lefthalf.filled`, concluded `checkmark.circle.fill`: three distinct silhouettes, each an
  industry-standard meaning (warning / in-progress / done). Final 9–11 pt legibility verified on-device;
  documented fallback = the cohesive all-circle family. *(your call, via the rendered spike)*

*Everything else (token values, semantic-color swaps, VoiceOver composition, file layout) is locked.*

---

## 12. Proposed build order (after go-ahead)

Phase 0 is the one deliberate horizontal step (additive contract); the rest fan out like prior batches.

1. **Phase 0 (serial):** extend `Preferences` additively + the pure Core helpers (`A11yOverride`/`effective`,
   `StatusSymbol`/`statusSymbol`, the two VoiceOver string fns) with their tests. Everything still compiles;
   no behavior change. Checkpoint: build + tests green.
2. **Phase 1:** **A2 (contrast fix)** + **the Accessibility tab** — both touch tokens/SettingsView, do them
   together. Lands a visible win (light mode stops failing) immediately.
3. **Phase 2:** **A1 (shapes)** ‖ **A4 (VoiceOver)** — disjoint (`StatusDot`/bar glyph vs row/bar
   accessibility attrs); safe to parallelize.
4. **Phase 3:** **A3 (high-contrast palette + observer)** + **A5/A6**, sharing the resolver.
5. **Phase 4 (manual):** `./build.sh`, then the live checks — grayscale/CVD-filter legibility at 9–11 pt,
   the Increase-Contrast/Reduce-Motion/Transparency toggles reacting live, and a VoiceOver pass.

---

## 13. Acceptance criteria (whole batch)

- Status is distinguishable **without color** (grayscale / CVD filter), in the roster and the bar — clears
  **WCAG 1.4.1 (A)**.
- Light-mode text + indicators meet **WCAG AA** (4.5:1 text, 3:1 non-text); high-contrast mode (if built)
  reaches the ≥4.5/≥7:1 targets in §7 — clears **WCAG 1.4.11 (AA)**.
- VoiceOver speaks the bar summary and each row's full state.
- All existing tests stay green; new pure logic (`statusSymbol`, `effective`, the two VoiceOver fns) is
  unit-tested; the batch keeps the **133-test** suite growing in the Core-pure pattern.
- **No network. No new TCC permission** (the NSWorkspace display flags are not the Accessibility permission).
  Reads stay read-only; no new read surfaces. Defaults stay calm (shapes subtle, overrides "Follow System").

---

## 14. Sources

- WCAG 2.1 [1.4.1 Use of Color (Level A)](https://www.w3.org/WAI/WCAG21/Understanding/use-of-color.html) ·
  [1.4.11 Non-text Contrast (Level AA, 3:1)](https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html)
- Apple — [SF Symbols HIG](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
  (enclosing shape + fill for small-size status) ·
  [`accessibilityDisplayShouldDifferentiateWithoutColor`](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshoulddifferentiatewithoutcolor) ·
  [`accessibilityDisplayShouldIncreaseContrast`](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldincreasecontrast) ·
  [`accessibilityDisplayOptionsDidChangeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayoptionsdidchangenotification)
- SwiftUI accessibility environment values (auto-re-render; target 7:1 under increased contrast) —
  [Hacking with Swift](https://www.hackingwithswift.com/books/ios-swiftui/supporting-specific-accessibility-needs-with-swiftui)
- Color-vision-deficiency prevalence (1 in 12 men / 8% / ~300M; red-green predominant) —
  [Colour Blind Awareness](https://www.colourblindawareness.org/colour-blindness/)
- Contrast ratios + high-contrast token values computed locally (WCAG 2.1 relative-luminance) against
  [DesignTokens.swift](../../Sources/CPerchApp/DesignTokens.swift).
</content>
</invoke>
