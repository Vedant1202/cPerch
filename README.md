# cPerch

> A perch for your Claude sessions.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-555.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5%2F6-F05138.svg)](https://swift.org)
[![Tests](https://img.shields.io/badge/tests-141%20passing-3b6d11.svg)](#development)
[![Status](https://img.shields.io/badge/status-pre--release-d97757.svg)](#project-status)

cPerch is a native macOS menu-bar app that watches your running Claude Code sessions — across terminal
windows and the Claude desktop app — and surfaces them in one place. A glance at your menu bar tells you
which agent is waiting on you, which is still working, and which has finished; one click jumps to the
exact existing window. Detection is **zero-permission** and **fully local**.

It's built to solve a specific annoyance: when you're babysitting several agents at once, *"which window
was that one in again?"* cPerch answers that without you switching apps.

<!-- Add a screenshot here once captured, e.g. docs/assets/cperch.png -->
> _Screenshots coming with the first release._

## Features

- **Every session in one place** — terminal (`claude`) and Claude desktop sessions, listed together,
  needs-you first.
- **Status at a glance** — each session is **shape- and color-coded** (not color alone), so state is
  clear even in grayscale or for color-vision deficiency:

  | State | Meaning | Indicator |
  |-------|---------|-----------|
  | Needs input | waiting on you | orange, triangle |
  | Running | actively working | blue, half-filled circle |
  | Concluded | finished, nothing pending | green, checkmark |

- **Latest message inline** — read the most recent message without switching windows.
- **One-click Jump** — raises and focuses the *existing* host window (the exact terminal tab, or the
  desktop app). It never spawns a duplicate.
- **Calm notifications** — opt-in by kind (needs-input, error, completion), Focus/Do-Not-Disturb aware,
  with tap-to-open.
- **Global hotkey** — open cPerch from anywhere with `⌘⌥\`` (no extra permission required).
- **Launch at login** — optional, off by default.
- **Accessibility-first** — shape-coded status, a high-contrast mode that follows the system setting,
  VoiceOver labels, and reduce-motion / reduce-transparency support.
- **Private by design** — reads only your local `~/.claude` directory; no network, ever; no transcript
  content leaves your machine.

## Requirements

- macOS 14.0 or later.
- To build from source: the Xcode **Command Line Tools** (`xcode-select --install`). Full Xcode is not
  required.

## Install

No packaged release yet. Until one is published on the [Releases page](https://github.com/Vedant1202/cPerch/releases),
build from source:

```bash
git clone https://github.com/Vedant1202/cPerch.git
cd cPerch
./build.sh            # produces dist/CPerch.app (ad-hoc signed)
open dist/CPerch.app  # launches the menu-bar app
```

cPerch runs as a menu-bar accessory (no Dock icon). Look for its dot in the top-right of your menu bar.

## Usage

1. **Open cPerch** — click the cPerch icon in the menu bar, or press `⌘⌥\``.
2. **Read the list** — sessions are sorted with the ones waiting on you first. Each one shows the status
   indicator, the project name, the latest message, and how long a waiting session has been waiting.
3. **Jump** — click **Jump** on a row to focus that session's existing window. Terminal sessions focus
   the exact tab; desktop sessions bring the Claude app forward.
4. **Settings** — open from the gear at the bottom of the cPerch window:
   - **General** — appearance (System/Light/Dark), session list layout (simple or grouped by source),
     how long finished sessions linger, and launch-at-login.
   - **Notifications** — which events notify you, Focus/DND behavior, and how long banners persist.
   - **Accessibility** — status shapes, high contrast, reduce motion, and reduce transparency
     (each can follow the system or be forced on/off).

The menu-bar icon itself reflects the most urgent state at a glance, and shows a small count when more
than one session needs you.

## How it works

cPerch detects sessions from the local filesystem, so it works regardless of which app hosts a session
and needs no special permissions. It merges three signals on each session's id:

- **Process scan** (`ps`/`lsof`) — liveness and the owning terminal tab.
- **Registry** (`~/.claude/sessions/<pid>.json`) — the process-to-session bridge.
- **Transcript** (`~/.claude/projects/.../<id>.jsonl`) — latest message, status, and activity.

A filesystem watch plus a light poll keep it current while idling cheaply. The architecture and design
decisions are documented under [`docs/`](docs/) (start with [`SPEC.md`](SPEC.md) and the
[handover guides](docs/handover-v0.5.md)).

## Privacy & permissions

- **Local only.** cPerch never makes network requests and never transmits transcript content.
- **Read-only.** It reads `~/.claude`; it never writes to or mutates it.
- **No sensitive permissions.** No Accessibility (AX) permission, no Input Monitoring, no auth tokens.
  (Focusing a terminal tab uses Apple Events, which prompts once via the standard macOS Automation
  dialog.)
- **Not sandboxed**, because the App Store sandbox would forbid reading `~/.claude` and focusing other
  apps' windows — which is why distribution is via GitHub Releases rather than the Mac App Store.

## Development

```bash
swift build              # compile
./scripts/test.sh        # run the unit tests (swift-testing; 141 tests)
swift run CPerchApp --print   # dump detected sessions to the terminal (headless)
./build.sh               # assemble dist/CPerch.app
```

Notes:
- Tests use **swift-testing**, run via `./scripts/test.sh` (plain `swift test` won't work — XCTest isn't
  in the Command Line Tools).
- `CPerchCore` is pure, Foundation-only, and unit-tested; `CPerchApp` is the AppKit + SwiftUI layer.
- Run the real app as the bundle (`dist/CPerch.app`) — notifications need a signed bundle, which
  `build.sh` ad-hoc signs.

Repository layout:

```
Sources/CPerchCore/   detection + merge logic (pure, tested)
Sources/CPerchApp/    menu bar, session list, settings, notifications (AppKit + SwiftUI)
Tests/                swift-testing unit tests + synthetic fixtures
docs/                 spec, design tokens, decision log, handover guides
scripts/              test + fixture-capture helpers
```

## Project status

Pre-release. The core experience — detection, the menu-bar indicator, the session list, Jump, notifications,
and accessibility — is built and runs. Still ahead: a packaged, Developer-ID-notarized release. See the
[handover guides](docs/handover-v0.5.md) for the current state and what's next.

## License

Not yet licensed. Until a license is added, all rights are reserved by the author. (Adding an OSI
license such as MIT is recommended before wider distribution.)
</content>
