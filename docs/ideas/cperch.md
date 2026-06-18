# cPerch — base camp (refined ideation)

*Refined 2026-06-18 via `/idea-refine`, building on the confirmed intent
([../intent/cperch-v0.md](../intent/cperch-v0.md)) plus the deep discovery, so-agentbar
comparison, official-docs confirmation, and permissions analysis that preceded it. This is the
foundation v0 is built on.*

## Problem Statement
**HMW make "which of my Claude agents needs me right now — and for how long" effortless to know
and trivial to act on, without ever babysitting them?**

## Recommended Direction — "The Calm Conscience"
cPerch is a calm conscience for your Claude agents. At rest it's a single Claude-colored dot in
your menu bar. It stays quiet while they work, and the moment one needs you it lights orange and
(when you're not in Do-Not-Disturb) taps you once — one click takes you to the exact window where
it's waiting. It never asks for scary permissions, never phones home, and never touches your
sessions.

The durable edge over so-agentbar is deliberate and narrow: **multi-source reliability** (correct
at the edges — crashes, blocked-on-permission, suppressed transcripts) and a **true window-focus**
(the exact tab, never a duplicate). Everything else they do — usage tracking, source breadth,
pixel pets — we consciously skip. The soul is **trust through restraint**: zero-permission
detection, fully local, incapable of interfering with your sessions.

## Locked Decisions
1. **Primary mode — Calm ("it finds you").** Silent and minimal by default; surfaces you only when
   it's your move. Not an always-on dashboard you have to check.
2. **Resting surface — one aggregate status dot.** A single Claude-colored dot = the most urgent
   state across all sessions: 🟠 someone needs you · 🔵 working · dim = all idle. The dot reflects
   **live** state only.
3. **Detection — zero-config, no permissions.** process-scan + registry (`status` enum) + transcript,
   deduped by sessionId. Works the instant you launch. **Hooks are NOT in v0** — they'd edit your
   global Claude config and run code inside your sessions, which cuts against the trustworthy,
   read-only soul. They become an **optional, opt-in "precise mode" later** (transparent,
   merge-not-overwrite, one-click removable).
4. **Jump — exact existing window, never a duplicate.** Exact-tab focus for terminal hosts (Apple
   Events / Automation); activate-the-app for Claude desktop. The no-duplicates requirement is
   non-negotiable.
5. **Notifications — lean on macOS, stay calm.** Post via the standard `UNUserNotificationCenter` so
   macOS Focus/DND is honored automatically (DND on → no banners, the dot is the badge; DND off → a
   small banner). **Banner only on the actionable transition (a session → needs-input).**
   New-agent-started and concluded are **silent by default** (shown in the dot + list), with an
   opt-in "notify on new agent" toggle. Coalesce simultaneous needs-input into one banner.

## Key Assumptions to Validate
- [ ] **Dedup spine holds** — sessionId via the registry `pid→id` bridge, with a `cwd`+recency
      fallback for unregistered processes, unifies process-scan + registry + transcript with no
      ghosts or duplicates. (Test live with several sessions incl. one unregistered terminal.)
- [ ] **Calm stays calm** — needs-input transitions are stable enough to tap you ~once per real
      block, not flap. (Tune debounce + coalescing against real sessions.)
- [ ] **Exact-tab focus works** for Terminal/iTerm via Apple Events; Claude desktop at least
      activates without duplicating. (See spikes.)
- [ ] **Zero-config needs-input *feels* accurate enough** for Calm mode — CLI exact via registry
      `waiting`; old desktop app approximate is acceptable.

## MVP Scope
**IN**
- Menu-bar app; resting state = one aggregate Claude-colored dot.
- Zero-config detection (process-scan + registry + transcript), dedup by sessionId, liveness via
  `kill -0`. No TCC permissions.
- Dropdown roster: needs-you-first; each row = status dot + project + latest-message preview +
  "blocked Nm" wait time + jump button.
- Calm notification on needs-input transitions (standard API → DND-aware), coalesced.
- Jump: exact-tab focus for terminals (Apple Events); activate for Claude desktop. Never a duplicate.
- Pixel-faithful Claude styling (`#d97757` / `#6a9bcc` / `#788c5d`; neutrals
  `#141413`/`#faf9f5`/`#b0aea5`/`#e8e6dc`; Inter/SF + JetBrains Mono).

**Permissions footprint (v0):** none for detection · Notification permission (standard) · Automation
(per-app, terminals only) for exact-tab jump. **NOT** Accessibility, **NOT** Keychain, **NOT** network.

**OUT** — see Not Doing.

## Not Doing (and Why)
- **Hooks in v0** — lower trust (edit global config, run code in sessions, can block Claude) and
  break the read-only soul. Optional "precise mode" later.
- **Usage / quota tracking** — needs Keychain + network + an unofficial OAuth API + token custody;
  breaks "fully local." That's so-agentbar's lane.
- **Codex / other agents** — focus is Claude.
- **Xcode / Cowork source breadth** — v0 is `~/.claude` (CLI + desktop); earn breadth later if asked.
- **Pixel pets / system monitor / cost charts** — feature sprawl; against "minimal."
- **Two-way input (answer prompts from the app)** — the north star, deliberately deferred so v0
  points toward it.
- **Accessibility-tier window control** — avoid the heavyweight "control your computer" grant;
  Apple Events suffices for terminals.

## Resolved Open Questions
- **Desktop focus:** No AppleScript (can't script a chat), but Claude desktop **registers a
  `claude://` URL scheme** (bundle `com.anthropic.claudefordesktop`). v0 = activate-the-app (no
  duplicate); **spike the `claude://` route table** — if a session-targeting route exists, upgrade
  desktop-jump to exact-chat at zero permission cost.
- **Concluded retention:** live never expires; concluded lingers ~3h (tunable), capped ~10 most
  recent, then leaves the UI (stays on disk). The dot reflects live state only.
- **cwd collision:** accept as a documented limitation with graceful degradation (registry covers
  ~all real sessions; on collision, sessions still list separately, jump degrades to activate-app).
  Future fix if needed: read `CLAUDE_SESSION_ID` from process env (`ps eww`), not cwd-guessing.
- **Notifications:** resolved in Locked Decision 5 — macOS-native DND handling, needs-input only,
  new-agent opt-in, coalesced.

## Remaining Spikes (before / while building)
- Discover the `claude://` route table (exact-chat deep-link feasibility for desktop).
- Validate the dedup spine + liveness against a live multi-session machine.
- Confirm the needs-input debounce/coalesce window feels calm (no flapping).

## Foundations already in place
- Status heuristic validated in a throwaway Swift spike (registry `status` enum
  busy/shell/idle/waiting + `kill -0` + transcript fallback).
- Toolchain proven: CLT + SwiftPM, no full Xcode; ship via GitHub Releases.
- Design tokens locked: [../design/design-tokens.md](../design/design-tokens.md).
