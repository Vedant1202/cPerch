# cPerch — Accessibility batch (v0.5) — plan

Implements [docs/specs/accessibility-v0.5.md](../docs/specs/accessibility-v0.5.md) (open questions
resolved 2026-06-19). **Branch:** new `accessibility-v0.5` off `daily-driver-v0.4` (latest baseline;
`main` is behind). **Pattern:** the repo's **contract-first parallel fan-out** — a serial Phase 0 that
lands all shared vocabulary additively, then a **parallel Phase 1** of disjoint-file tracks, then a
manual Phase 2. Todo: [accessibility-batch-todo.md](accessibility-batch-todo.md).

> Toolchain (unchanged): `swift build` · `./scripts/test.sh` (swift-testing; XCTest isn't in the CLT) ·
> `./build.sh && open dist/CPerch.app` · `swift run CPerchApp --print`. Commit trailer
> `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Never commit to `main`.

---

## Scope (locked)

A1 shape-coded status (on by default + opt-out) · A2 baseline contrast fix · A3 high-contrast mode ·
A4 VoiceOver · A5/A6 reduce motion + transparency · the new **Accessibility** settings tab. Symbol set
locked: needs-input `exclamationmark.triangle.fill`, running `circle.lefthalf.filled`, concluded
`checkmark.circle.fill` (fallback: cohesive all-circle family, decided on-device).

---

## Dependency graph

```
                       ┌──────────────────────── FOUNDATION (Phase 0, serial) ───────────────────────┐
   CPerchCore (pure)   │  Preferences(+A11yOverride,+4 fields,+effective)                             │
                       │  StatusSymbol + statusSymbol(for:DerivedStatus / MenuBarModel.Glyph)         │
                       │  AccessibilityText: accessibilityLabel(for:Session) · menuBarAccessibilityValue│
   CPerchApp (vocab)   │  DesignTokens(+semantic aliases, +HC palette, +statusColor(), +symbolName()) │
                       └───────────────┬───────────────────┬───────────────────┬─────────────────────┘
                                       │ consume            │ consume            │ consume
                            ┌──────────▼────────┐ ┌─────────▼─────────┐ ┌───────▼────────────┐
   App fan-out (Phase 1 ‖)  │ Track R           │ │ Track M           │ │ Track S            │
   one agent per box,       │ RosterView.swift  │ │ MenuBarController  │ │ SettingsView.swift │
   DISJOINT files           │ A1·A2·A3·A4·A6    │ │ A1·A2·A3·A4·A5     │ │ (+PreferencesStore)│
                            └──────────┬────────┘ └─────────┬─────────┘ └───────┬────────────┘
                                       └──────────── reconverge → C1 ───────────┘
                                                          │
                                              Phase 2 (manual, on-device)
```

**Why slice by file, not by feature.** The features are *horizontal* — each touches several files:
A1 touches RosterView **and** MenuBarController; A2 touches RosterView + DesignTokens + MenuBarController;
A3 touches DesignTokens + MenuBarController + RosterView. The only conflict-free parallel cut is the
repo's established **one-agent-per-disjoint-file**. So Phase 0 lands **all** shared vocabulary
(the pure Core helpers + the DesignTokens API), and each Phase-1 track then delivers the **complete
accessibility behavior for one surface** (the roster, the bar, the settings) — vertical per surface,
disjoint by file. No Phase-1 track edits a file another track edits.

**Contract safety.** `Models.swift` is the FROZEN v0 contract — this batch does **not** modify it.
`StatusSymbol` is a *new* file; `accessibilityLabel(for:)` *reads* `Session` fields (additive
consumption). `Preferences` is not frozen and is extended additively (defaulted), preserving every
existing call site — same discipline as the v0.4 batch.

---

## Phase 0 — Foundation (SERIAL · one agent · the one deliberate horizontal step)

All additive, defaulted; **no call site changes yet** ⇒ everything compiles, behavior unchanged.

**T0.1 — Preferences (edit `Sources/CPerchCore/Preferences.swift`)**
- Add `public enum A11yOverride: String, CaseIterable, Sendable, Codable { case system, on, off }`
  with `.label` ("Follow System" / "Always on" / "Off").
- Add fields: `showStatusShapes: Bool = true`, `highContrast/reduceMotion/reduceTransparency: A11yOverride = .system`.
- Extend `init`, `defaults`, `Key`, `load`, `save` (guard Bool on `object(forKey:) != nil`, mirror the
  existing pattern at Preferences.swift:148–166).
- Add pure `public func effective(_ o: A11yOverride, system: Bool) -> Bool` (`.on`→true, `.off`→false,
  `.system`→system).
- **AC:** defaults match spec (shapes on, overrides `.system`); a partial/older domain still loads a
  complete value; `effective` truth table holds. **Verify:** `./scripts/test.sh` green (T0.5 tests).

**T0.2 — StatusSymbol (new `Sources/CPerchCore/StatusSymbol.swift`)**
- `public enum StatusSymbol: Sendable, Equatable { case needsInput, running, concluded, idle }`.
- `public func statusSymbol(for: DerivedStatus) -> StatusSymbol` and an overload
  `for: MenuBarModel.Glyph` (so the bar's symbol is decided in tested Core, mirroring the color-free
  `MenuBarModel.Glyph` precedent). **No SF-Symbol strings here** — those are App-side (T0.4).
- **AC:** every `DerivedStatus`/`Glyph` case maps as specified. **Verify:** T0.5 tests.

**T0.3 — AccessibilityText (new `Sources/CPerchCore/AccessibilityText.swift`)**
- `public func accessibilityLabel(for s: Session, now: Date) -> String` →
  e.g. `"api, needs input, blocked 4 minutes. Latest: Can I run the migration?"` (reuse the
  `SessionRow.relativeWait` phrasing; omit empty preview; status spoken as words).
- `public func menuBarAccessibilityValue(aggregate: AggregateState, needsInputCount: Int, runningCount: Int) -> String`
  → `"2 sessions need you"` / `"1 running"` / `"all quiet"`.
- **AC:** strings match for needs-input/running/concluded, singular/plural, nil-preview. **Verify:** T0.5.

**T0.4 — DesignTokens vocabulary (edit `Sources/CPerchApp/DesignTokens.swift`)**
- Semantic aliases: `secondaryText = Color(NSColor.secondaryLabelColor)`, `tertiaryText`, `separator`.
- HC palette constants per status (spec §7): light `#AB5E45/#51769B/#677850`, dark `#DF8B70/#77A4D1/#96A581`.
- `func statusColor(_ status: DerivedStatus, highContrast: Bool, dark: Bool) -> NSColor` (+ a `Color`
  bridge) returning standard brand or the HC variant.
- `func symbolName(for: StatusSymbol) -> String` → the locked SF Symbol names; a single flag flips to the
  all-circle fallback set (so the on-device fallback is a one-line switch).
- Additive only — **no existing call site changed.** **AC/Verify:** `swift build` green.

**T0.5 — Core tests**
- Edit `Tests/CPerchCoreTests/PreferencesTests.swift` (new defaults + round-trip + `effective` table).
- New `Tests/CPerchCoreTests/StatusSymbolTests.swift`, `Tests/CPerchCoreTests/AccessibilityTextTests.swift`.
- **AC:** suite grows from 133; all green.

> **Checkpoint C0:** `swift build` + `./scripts/test.sh` + `./build.sh` all green; no behavior change
> (the app looks identical — only new, unused API exists). Commit `Phase 0: additive a11y foundation`.

---

## Phase 1 — App fan-out (PARALLEL ‖ · 3 agents · strictly disjoint files)

Each track is one agent in its own clean `git clone` under `/tmp` (worktrees are awkward — this repo is
a git *subdir*), given **only** its file(s). Reconverge by copying each owned file back. **No two tracks
share a file**, so there are no merge conflicts by construction.

### ‖ Track R — the roster surface · owns `Sources/CPerchApp/RosterView.swift`
- **A1:** `StatusDot` → `Image(systemName: symbolName(for: statusSymbol(for: status)))` tinted by
  `statusColor(...)`; when `showStatusShapes == false`, render the plain `Circle().fill`.
- **A2:** swap `TokenColors.midGray`/`divider` for the semantic aliases at the spec §6 sites
  (preview :249, header/empty/footer/group :160/:179/:122/:192/:203, disambiguator :231, dividers
  :94/:141, group count :125); fix the "blocked" pill (:237/:241) to readable text on a solid/bordered fill.
- **A3:** `statusColor(highContrast:)` resolved from `prefs.highContrast` + `@Environment(\.colorSchemeContrast)`
  via `effective(...)`; drop opacity tints when high-contrast.
- **A4:** `SessionRow` → one element, `.accessibilityElement(children: .ignore)` +
  `.accessibilityLabel(accessibilityLabel(for:now:))`; Jump exposed via `.accessibilityAction(named:"Jump")` / labeled button.
- **A6:** background → `Color(NSColor.windowBackgroundColor)` when `effective(prefs.reduceTransparency, env)`.
- **AC:** in a grayscale/CVD filter the three rows are distinct; preview text ≥4.5:1; VoiceOver reads each
  row; high-contrast strengthens dots/removes tints; shapes opt-out returns the plain dot; reduce-transparency
  → opaque bg. **Verify:** `swift build`; `./build.sh && open dist/CPerch.app` (roster spot-check).

### ‖ Track M — the menu-bar surface · owns `Sources/CPerchApp/MenuBarController.swift`
- **A1:** `dotImage` → `NSImage(systemSymbolName: symbolName(for: statusSymbol(for: model.glyph)), …)`
  tinted (`isTemplate=false`); plain oval when `showStatusShapes==false`.
- **A2:** `countTitle` color → `NSColor.labelColor` (adapts to the bar).
- **A3:** color via `statusColor(highContrast: effective(prefs.highContrast, NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast), dark:)`;
  add an observer on `NSWorkspace.shared.notificationCenter` for `accessibilityDisplayOptionsDidChangeNotification` → `refresh()`.
- **A4:** `statusItem.button?.setAccessibilityLabel("cPerch")` + dynamic
  `setAccessibilityValue(menuBarAccessibilityValue(...))` inside `refresh()`.
- **A5:** `popover.animates = !effective(prefs.reduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)`.
- **AC:** bar shows a glyph (not a bare disc); ≥2 needs-input shows the count; VoiceOver speaks the live
  summary; toggling system Increase-Contrast / Reduce-Motion reacts **live** (no relaunch); shapes opt-out
  → plain dot. **Verify:** `swift build`; bundle launch; VoiceOver + System-Settings toggles.

### ‖ Track S — the settings path · owns `Sources/CPerchApp/SettingsView.swift` (+ `PreferencesStore.swift` if touched)
- Add the third tab to the `TabView` (SettingsView.swift:10): `Label("Accessibility", systemImage:"accessibility")`,
  a `Form(.grouped)` with: **Differentiate status with shapes** (Toggle, default on), **High contrast** /
  **Reduce motion** / **Reduce transparency** (Pickers: Follow System / Always on / Off).
- `PreferencesStore`: confirm `onChange` already re-renders the roster + bar on a pref flip (it does —
  PreferencesStore.swift:9–17/45–51); extend only if a gap is found. (No NSApp.appearance change for HC.)
- **AC:** the tab appears and binds; flipping each control changes the live UI; values persist (the
  round-trip is already covered by T0.5). **Verify:** `swift build`; bundle → open Settings → exercise each control.

> **Reconverge + Checkpoint C1:** copy R/M/S files back; **boundary audit** (CPerchCore stays
> Foundation-only; no Accessibility-permission API — only the readable `accessibilityDisplay*` flags; no
> network; no new `~/.claude` reads); `swift build` + `./scripts/test.sh` + `./build.sh` green. Commit
> `Phase 1: a11y roster + menu-bar + settings tab`.

---

## Phase 2 — On-device sign-off (SERIAL · manual · yours)

From `dist/CPerch.app` — these can't be exercised headless:
1. **Symbol legibility:** at 9–11 pt, the three statuses are distinct in color **and** under a grayscale /
   color filter (Sim Daltonism or System Settings ▸ Accessibility ▸ Display ▸ Color Filters). If the
   triangle/half-disc read too busy, flip the one-line fallback to the all-circle set (T0.4) and re-check.
2. **High contrast:** System Settings ▸ Accessibility ▸ Display ▸ Increase Contrast on → dots/text/borders
   strengthen, tints go solid, **live**; the tab's Always-on / Off overrides win over the system flag.
3. **Reduce motion / transparency:** the system toggles (and the tab overrides) stop the popover animation /
   make the background opaque.
4. **VoiceOver:** the bar item speaks the summary; arrowing the roster speaks each row + reaches Jump.

Then **merge `accessibility-v0.5`** (held pending sign-off, like v0.4) and refresh the handover.

---

## File ownership (the parallel contract — no file in two Phase-1 tracks)

| File | Phase 0 | Track R | Track M | Track S |
|---|:--:|:--:|:--:|:--:|
| `CPerchCore/Preferences.swift` | ● | | | |
| `CPerchCore/StatusSymbol.swift` (new) | ● | | | |
| `CPerchCore/AccessibilityText.swift` (new) | ● | | | |
| `CPerchApp/DesignTokens.swift` | ● | | | |
| `CPerchCoreTests/*` (3 files) | ● | | | |
| `CPerchApp/RosterView.swift` | | ● | | |
| `CPerchApp/MenuBarController.swift` | | | ● | |
| `CPerchApp/SettingsView.swift` (+`PreferencesStore.swift`) | | | | ● |

`Models.swift` / `SessionProviding.swift` / `SessionMerger.swift` / readers: **untouched** (frozen contract).
</content>
