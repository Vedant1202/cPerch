# cPerch — Claude Code project context

**cPerch** is a native macOS menu-bar app that monitors running Claude Code sessions (across
terminals and the Claude desktop app), shows each session's status and latest message, and lets
you jump to the existing session window. Tagline: *a perch for your Claude sessions.*

## ✅ Project status — v0.6.0 released; v0 + six post-v0 batches on `main`

v0 shipped 2026-06-18; six post-v0 batches have since landed on `main`: dedup-hardening (v0.1/v0.2),
group-by-host + over-counting/retention (v0.3), the v0.4 daily-driver batch (launch-at-login, global
hotkey, richer menu-bar, error/completion notifications), the v0.5 accessibility batch (shape-coded
status, contrast fix, high-contrast mode, VoiceOver, reduce motion/transparency, Accessibility tab,
white menu-bar plate), and the **v0.6 in-app Help batch** ("?" Help panel, first-run hint, copy
diagnostics, About). The project's **first public release, v0.6.0**, is published on GitHub Releases
(unsigned zip + DMG) via a one-command pipeline (`scripts/release.sh` → tag-triggered macOS workflow).
**143 tests.**

**New here? Read the handover chain, newest first:** [docs/handover-v0.6.md](docs/handover-v0.6.md) →
[v0.5](docs/handover-v0.5.md) → [v0.4](docs/handover-v0.4.md) → [v0.2](docs/handover-v0.2.md) →
[v0](docs/handover-v0.md) — pickup guides (build/run, architecture, gotchas, what's next).

## What we're building (v0)

A menu-bar (status-bar) app. Clicking the bar icon opens a dropdown listing every live, logged-in
Claude session. Per session:

- **Status dot** — `needs-input` 🟠 / `running` 🔵 / `concluded` 🟢
- **Latest message** — the most recent message, inline, so the user can triage without switching windows
- **Jump button** — raises/focuses the **already-open** host window (terminal tab or Claude desktop
  window). **It must never spawn a duplicate.**

Goal: kill the "which window was that agent in again?" hunt when babysitting several agents at once.

## Tech stack & toolchain

- **Language / UI:** Swift — **AppKit `NSStatusItem`** for the menu-bar item, **SwiftUI** views hosted
  via `NSHostingView` for the dropdown. We avoid SwiftUI's `MenuBarExtra` because it leans on the
  SwiftUI App lifecycle, which is awkward to build outside Xcode.
- **Build:** **Swift Package Manager** (`Package.swift`) + a `build.sh` that assembles the `.app`
  bundle (writes `Info.plist` with `LSUIElement = true` so there's no Dock icon; bundles the `.icns`).
- **No full Xcode required.** Develop with **VS Code + the official Swift extension
  (`swiftlang.swift-vscode`, SourceKit-LSP)** and the **Command Line Tools** (`xcode-select --install`).
  The CLT package also ships `codesign` and `notarytool`, so the full build → sign → notarize pipeline
  works without the Xcode IDE.
- **Target:** macOS 14.0+.
- **Distribution:** **GitHub Releases** — unsigned `.zip` to start (right-click → Open past Gatekeeper);
  Developer ID notarization + DMG later. **Not** the Mac App Store — the sandbox forbids reading
  `~/.claude` and using Accessibility / Apple Events to focus other apps' windows.

## Data source — `~/.claude/`

Sessions are detected from the local filesystem (login/plan-based and app-agnostic — it works
regardless of which app hosts the session). Key paths:

- `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` — full transcript per session; file
  **mtime ≈ last activity**. `<encoded-cwd>` is the project path with `/` replaced by `-`.
- `~/.claude/sessions/<pid>.json` — live session state keyed by **process id** (a strong
  "is it running" signal).
- `ps` — cross-check that a session's PID is still alive.

We do **not** track Anthropic-API usage made by other apps — only logged-in Claude (Code) sessions.

## Status model (refine at design time)

| Status | Likely signal |
|---|---|
| 🔵 `running` | PID alive **and** transcript actively growing / last record is an in-flight assistant turn |
| 🟠 `needs-input` | PID alive **and** idle at a prompt — last turn is an assistant question or a tool-permission request awaiting the human |
| 🟢 `concluded` | PID gone / session ended, or the agent finished with nothing pending |

The exact heuristic is the **hardest open problem** — see *Known design challenges*.

## Design — look & feel (match the Claude app)

Full spec: [`docs/design/design-tokens.md`](docs/design/design-tokens.md). Summary:

**Status colors — Anthropic's official accent palette:**
- 🟠 needs-input → **`#d97757`** (Orange, primary accent)
- 🔵 running → **`#6a9bcc`** (Blue, secondary accent)
- 🟢 concluded → **`#788c5d`** (Green, tertiary accent)

**Neutrals:** Dark `#141413` · Light `#faf9f5` · Mid Gray `#b0aea5` · Light Gray `#e8e6dc`

**Type:** Claude's real UI fonts (Styrene B, Copernicus) are proprietary. Use the closest free stack —
**Inter** (UI/body ≈ Styrene B) with **SF Pro** native fallback, and **JetBrains Mono** for
message/code snippets (matches Claude). Stack: `Inter, -apple-system, "SF Pro Text", system-ui, sans-serif`.

## Known design challenges (resolve before coding)

1. **Status heuristic.** Reliably classify needs-input vs running vs concluded from the JSONL tail +
   live PID + `sessions/<pid>.json`. Needs real-data spelunking. A false "needs input" is annoying; a
   missed one defeats the app.
2. **Session → host-window mapping.** Terminals: PID → tty → owning terminal app (Terminal/iTerm) →
   focus the right tab via Apple Events / Accessibility. Claude desktop app: a separate focus path.
   Focus the existing window; never duplicate.
3. **"Concluded" retention.** How long a finished session lingers in the list before dropping off
   (time-based? until dismissed?).
4. **Polling vs watching.** FSEvents / `DispatchSource` watching on `~/.claude` vs a timer poll — pick
   the lightest approach that stays responsive.

## Repo layout

```
cPerch/
├── CLAUDE.md                     # this file — project context
├── README.md                     # WIP teaser
├── .gitignore
├── .claude/settings.json         # project permissions (safe dev commands)
├── .vscode/extensions.json       # recommends the Swift extension
└── docs/
    ├── intent/cperch-v0.md       # confirmed v0 scope (the "what & why")
    └── design/design-tokens.md   # exact colors + fonts (the "look")
```
Swift sources (`Package.swift`, `Sources/…`, `build.sh`) land here once implementation is greenlit.

## Working conventions

- **macOS-only, native.** Prefer native APIs over shelling out where practical.
- Keep the bar app **lightweight** — it idles all day; watch memory/CPU.
- When implementing: small, verifiable increments. `swift build` compiles, `swift run CPerchApp` runs,
  **`./scripts/test.sh`** runs unit tests (swift-testing — **XCTest is not in the CLT**, so the script
  points the linker at `Testing.framework`). `build.sh` assembles the `.app` (Phase 3).
- Package is **swift-tools-version 6.0** (needed for swift-testing) with **language mode pinned to v5**.
- Decisions and their *why* live in [docs/decisions.md](docs/decisions.md) (decision log) — consult it
  and append new ones as you go. Phase carry-forwards (what P2/P3 must handle) are in [tasks/plan.md](tasks/plan.md).
- Run the real app as the **bundle**: `./build.sh` then `open dist/CPerch.app` — `UNUserNotificationCenter`
  needs a signed bundle (build.sh ad-hoc signs it). Bare `swift run CPerchApp` launches but notifications
  no-op; `swift run CPerchApp --print` dumps the live sessions headless.
- Reading the user's own `~/.claude` transcripts is core to dev/testing — handle that data carefully
  and never exfiltrate it.
- **Copy / wording (user-facing).** Describe the privacy stance as **"privacy-focused"** (or "private by
  design") — do **not** use the phrase **"no special permissions"** (or "no permissions"). Frame it as a
  positive property, not the absence of one. Applies to the README, the website, release notes, and
  in-app text.

## Out of scope (v0)

VS Code / Cursor integrations (design for, don't build) · Codex / other agents · sending input *from*
the app · code-signing / notarization · history/analytics of past sessions.
