# cPerch — post-v0 handover (v0.4 → v0.5)

*Picks up after [handover-v0.4.md](handover-v0.4.md). Covers the **v0.5 accessibility batch** and the
**squash-merge of all post-v0 work to `main`**. Last updated 2026-06-19.*

## TL;DR
Two things since v0.4:

1. **v0.5 — accessibility batch** ([spec](specs/accessibility-v0.5.md) ·
   [plan](../tasks/accessibility-batch-plan.md) · [todo](../tasks/accessibility-batch-todo.md)): the app's
   status was conveyed by **color alone** (orange/blue/green dots) — failing WCAG 1.4.1 for the ~8% of men
   with color-vision deficiency (the confusable pair *is* needs-you-orange ↔ done-green), and light mode
   measurably under-contrasted (preview text **2.11:1**). This batch fixes both: **shape-coded status**,
   a **baseline contrast fix**, a **high-contrast mode**, **VoiceOver**, **reduce motion/transparency**,
   and a new **Accessibility** settings tab — then a Phase-2 fix added a **white menu-bar plate**.
2. **`main` is now current.** It had been **~33 commits / 5 batches behind** (still at v0). All post-v0
   work was **squash-merged to `main` as five per-version commits** (v0.1 → v0.5). `main` now equals the
   latest tree.

**141 tests** (up from 133). No remote. Signed off on-device and merged.

---

## v0.5 — the accessibility batch

### What shipped (feature → implementation → where)

| ID | Feature | Implementation notes |
|---|---|---|
| **A1** | **Shape-coded status** (always-on, opt-out) | Each status gets a distinct SF Symbol, not just a hue — the WCAG 1.4.1 fix. Abstract `StatusSymbol` + `statusSymbol(for:)` in Core (color-free, like `MenuBarModel.Glyph`); the App maps to a name via `Tokens.symbolName`. **Roster** uses the enclosed set: needs-input `exclamationmark.triangle.fill`, running `circle.lefthalf.filled`, concluded `checkmark.circle.fill` (three distinct silhouettes; each an industry-standard meaning). Default-on with an opt-out (`showStatusShapes`). → [StatusSymbol.swift](../Sources/CPerchCore/StatusSymbol.swift), [RosterView.swift](../Sources/CPerchApp/RosterView.swift), [MenuBarController.swift](../Sources/CPerchApp/MenuBarController.swift) |
| **A2** | **Baseline contrast fix** (everyone, no toggle) | Light mode failed WCAG AA *today*. Swap hardcoded `midGray`/`divider` for **semantic** colors (`secondaryLabelColor`, `tertiaryLabelColor`, `separatorColor`) which adapt to light/dark **and** auto-boost under Increase Contrast; the "blocked" pill rebuilt for legibility. → [DesignTokens.swift](../Sources/CPerchApp/DesignTokens.swift), RosterView |
| **A3** | **High-contrast mode** | Reacts to `NSWorkspace…ShouldIncreaseContrast` (or the tab override) → a **computed, WCAG-verified** accent palette (light ≥4.5:1 `#AB5E45`/`#51769B`/`#677850`; dark ≥7:1 `#DF8B70`/`#77A4D1`/`#96A581`), via `Tokens.statusColor(_:highContrast:dark:)`. Bar reacts live via an `accessibilityDisplayOptionsDidChangeNotification` observer; roster via `@Environment(\.colorSchemeContrast)`. |
| **A4** | **VoiceOver** | Pure Core string builders — `accessibilityLabel(for:now:)` (rows: "api, needs input, blocked 4 minutes. Latest: …") and `menuBarAccessibilityValue(...)` (bar: "2 sessions need you"). Each row is one combined element; Jump is a named action. → [AccessibilityText.swift](../Sources/CPerchCore/AccessibilityText.swift) |
| **A5/A6** | **Reduce motion / transparency** | Honor the system flags (popover `animates`; roster solid background) with per-tab overrides. |
| **Tab** | **Accessibility settings tab** | Third tab (General · Notifications · **Accessibility**): shapes toggle + High contrast / Reduce motion / Reduce transparency (`A11yOverride`: Follow System / Always on / Off). → [SettingsView.swift](../Sources/CPerchApp/SettingsView.swift), [Preferences.swift](../Sources/CPerchCore/Preferences.swift) |
| **fix** | **White menu-bar plate** | Phase-2 finding: the fixed-hue bar dot blended into a light/busy wallpaper behind the translucent bar. The glyph now rides a **white circular plate** with a hairline edge so it reads on any desktop. Bar uses **bare** glyphs on the plate (plate = the enclosure). → MenuBarController |

**Defaults stay calm:** shapes on (subtle), overrides "Follow System", no new TCC permission, no network.

### Decisions worth remembering
- **The NSWorkspace `accessibilityDisplay*` flags are NOT the Accessibility (AX) permission** — they're
  readable display preferences, no prompt. This was the key feasibility point that kept the batch inside
  the "never request Accessibility" boundary.
- **Semantic colors do double duty:** they fix the measured light-mode failures for *everyone* and
  auto-strengthen under Increase Contrast — so A2 does much of A3's text work for free. The brand accents
  can't be semantic, so those get the explicit high-contrast variants.
- **Symbol set was chosen on evidence** (industry conventions + a rendered [spike](../spikes/a11y-status-symbols.html),
  judged in grayscale). `Tokens.useCircleFallback` flips to the cohesive all-circle set if the
  triangle/half-disc read too busy at 9 pt on-device.
- **Bar vs roster glyphs differ by context:** roster = enclosed `.circle.fill` on a controlled bg; bar =
  **bare** glyph on a white plate (the plate is the wallpaper-contrast surface + the enclosure).

### Gotchas this batch hit (don't re-discover)
- **A palette `SymbolConfiguration` color is LOST when an SF Symbol is composited via `NSImage.draw()`**
  (it only survives when a control renders the symbol directly). The plated bar glyph therefore tints
  **explicitly** — draw as a template, then fill with the status color (`sourceAtop`). The first plate
  attempt rendered an invisible (clear) glyph because of this.
- **computer-use can't target the app.** cPerch is an `LSUIElement` accessory app; the computer-use access
  resolver only surfaces regular/Dock apps, and its screenshot compositor filters out non-granted apps —
  so the menu bar **can't be screenshotted headlessly**. Visual sign-off is manual.

---

## How it was built (the same contract-first fan-out, refined)
1. **Phase 0 (serial):** extend the shared contracts **additively, defaulted** — `Preferences`
   (+`A11yOverride`, `showStatusShapes`, the three overrides, `effective(_:system:)`), new
   `StatusSymbol`/`AccessibilityText`, and the App-side `DesignTokens` vocabulary (semantic aliases, HC
   palette, `statusColor`, `symbolName`). No call sites changed ⇒ app unchanged. Checkpoint C0 (build +
   141 tests + bundle).
2. **Phase 1 (parallel ‖):** three agents on **strictly disjoint files** — **Track R** `RosterView`,
   **Track M** `MenuBarController`, **Track S** `SettingsView` — each delivering one surface's full a11y
   behavior. The one cross-track seam (RosterView gaining a defaulted `preferences` param that
   MenuBarController passes) was handled additively. Reconverged in-tree with **2 mechanical fixes** (arg
   order; module-qualify `CPerchCore.accessibilityLabel`). Checkpoint C1.
3. **Phase 2 (manual):** on-device sign-off (grayscale/CVD legibility, live Increase-Contrast / Reduce-Motion
   reaction, VoiceOver) → the white-plate fix → merge.

*Why slice by file, not feature:* every feature touches several files (A1 alone touches roster + bar), so
the only conflict-free parallel cut is one-agent-per-file — the repo's established pattern.

---

## What's left
- **A3 high-contrast** — live-confirm the palette strengthens dots/text and removes tints across light/dark;
  flip `useCircleFallback` only if the symbols read too busy at 9 pt.
- **Carried-over deferrals** (unchanged by this batch): **#11** local token/cost (boundary-safe, parked);
  **#3** desktop deep-link (cut — no Claude.app route); over-counting **multi-level `--resume` chain**
  residual; **L1 opt-in `Stop`/`Notification` hooks** (writes `~/.claude/settings.json` — needs explicit
  go-ahead); **distribution** (Developer-ID sign + notarize + DMG; currently ad-hoc signed).
- **Branch cleanup (optional):** `accessibility-v0.5`, `daily-driver-v0.4`, `dedup-hardening-v0.1` are now
  fully contained in `main` — safe to delete.

---

## Build / test / run
- `swift build` — compiles. `./scripts/test.sh` — **141 tests** (swift-testing; XCTest isn't in the CLT).
- `./build.sh` then `open dist/CPerch.app` — the ad-hoc-signed bundle (needed for notifications + a real
  login item). `swift run CPerchApp --print` dumps live sessions headless.
- New files this batch: `Sources/CPerchCore/{StatusSymbol,AccessibilityText}.swift`,
  `docs/specs/accessibility-v0.5.md`, `tasks/accessibility-batch-{plan,todo}.md`,
  `spikes/a11y-status-symbols.html`.

## Git
- **`main` is current** — v0.1 → v0.5 squash-merged as five per-version commits on top of v0 (`baec0d0`):
  `a917c7a` v0.1 → `719b150` v0.2 → `847b26b` v0.3 → `1b02447` v0.4 → `fa19a3c` v0.5. Its tree is
  byte-identical to the `accessibility-v0.5` branch tip.
- Feature branches retained for now (`accessibility-v0.5` etc.); no remote yet.
- Trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
</content>
