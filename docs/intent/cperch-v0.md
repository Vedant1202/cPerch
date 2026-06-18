# cPerch — v0 confirmed intent

*Locked 2026-06-17 via a structured requirements interview. This is the agreed "what & why" for v0;
design and implementation are downstream of it.*

**Outcome:** A native macOS menu-bar app that shows your live Claude Code sessions — each with a
status (needs input / running / concluded) and its latest message — plus a one-click jump to the
existing host window.

**User:** The maintainer — running several logged-in Claude sessions in parallel across
projects/terminals and losing track of which one is waiting on them.

**Why now:** Babysitting multiple agents across terminals and the Claude desktop app carries real
switching cost; one menu-bar glance removes it.

**Success:** At a glance you can tell which session needs you, read the question without switching
windows, and one click raises the *already-open* terminal tab / Claude window — never a duplicate.

**Behaviors:**
- Show running sessions across any host app (terminal, Claude desktop).
- Show status: 🟠 needs-input · 🔵 running · 🟢 concluded.
- Show the latest message inline.
- "Jump" button focuses the existing host window; must not spawn duplicates.

**Data source:** the `~/.claude/` filesystem (login/plan-based, app-agnostic). No Anthropic-API usage
from other apps.

**Stack:** native Swift (AppKit `NSStatusItem` + SwiftUI), built with Command Line Tools + VS Code +
SwiftPM (no full Xcode), shipped via GitHub Releases.

**Constraints:** must focus the existing host window (never duplicate); lightweight enough to idle in
the bar all day.

**Out of scope (v0):** VS Code / Cursor integrations (design for, don't build) · Codex / other agents
· sending input *from* the app · code-signing / notarization · history/analytics of past sessions.
